"""Live connections to document sessions: who is connected, and what to send them.

This is the part of live collaboration that has no web framework in it. The
WebSocket route (backend/api/live.py) is a thin shell around it.

What a session's *room* does:

* Every entry added to the session's revision log (a batch from any client,
  over HTTP or over a live connection, or a "reload" entry) is pushed to every
  connection in the room, the sender included: the sender uses its own batch
  coming back as the acknowledgement.
* The room knows who is connected ("presence") and tells everyone whenever that
  changes. Presence is the set of live connections, nothing more.
* A connection that joins first receives what it missed since the revision it
  last saw, and only after that anything new: both happen under the session's
  lock, so nothing can be appended in between (no gap, no duplicate).

Messages sent to a client (JSON objects with a ``type``):

    catch_up   {"revision", "batches": [entry, ...]}   what was missed (maybe none)
    resync     {"revision", "reason"}                  reload the whole document
    batch      {"batch": entry}                        one new change
    presence   {"clients": [{"id", "name"}, ...]}      who is here, oldest first
    result     {"client_batch_id", ...}                the answer to the sender's own
                                                       batch (accepted/refused, with the
                                                       dropped notices)
    error      {"code", "message"}

``entry`` is ``LogEntry.to_dict()``. ``resync`` reasons: ``BEHIND`` (the client
asked for more history than the log keeps, or something that can't be replayed
happened in between), ``AHEAD_OF_SERVER`` (the client has seen a revision this
server never reached: it was talking to an earlier run of the server),
``CHANGED`` (the document was changed in a way the log can't describe).

Locking: every method that changes a room (``join``, ``leave``, ``submit``)
must be called with the session's lock held, which also keeps the messages to
one room in the order the log was written. The hub's own guard is only ever
taken after the session's lock, never before.

A connection must never make the code that is publishing wait: ``deliver``
returns at once. ``QueueConnection`` keeps a bounded queue and, if its client
falls too far behind, closes itself; the client reconnects and catches up
from the log.
"""

from __future__ import annotations

import asyncio
import threading
from dataclasses import dataclass, field
from typing import Any, Callable, Protocol

from backend.collab import op_log, service
from backend.collab.op_log import LogEntry
from backend.collab.operations import REVISION_FROM_FUTURE
from backend.utils.logger import get_logger

logger = get_logger("collab")

# How many messages may wait for one slow client before it is cut off.
DEFAULT_MAX_QUEUE = 256

RESYNC_BEHIND = "BEHIND"
RESYNC_AHEAD = "AHEAD_OF_SERVER"
RESYNC_CHANGED = "CHANGED"


class Connection(Protocol):
    """What the hub needs from a live connection."""

    client_id: str
    name: str

    @property
    def closed(self) -> bool: ...

    def deliver(self, message: dict[str, Any]) -> None:
        """Queue ``message`` for the client. Called from any thread; must not block or raise."""

    def close(self, reason: str) -> None:
        """Disconnect the client. Called from any thread."""


def entry_message(entry: LogEntry) -> dict[str, Any]:
    """The message that tells clients about one log entry."""
    if entry.kind == op_log.KIND_RESYNC:
        return {"type": "resync", "revision": entry.revision, "reason": RESYNC_CHANGED}

    return {"type": "batch", "batch": entry.to_dict()}


def _catch_up_message(session, since: int) -> dict[str, Any]:
    result = service.changes_since(session, since)

    if not result["accepted"]:
        if result.get("code") == REVISION_FROM_FUTURE:
            # The client's copy comes from a different run of the server
            # (this one restarted and counts from 0 again): reload.
            return {"type": "resync", "revision": session.oplog.revision, "reason": RESYNC_AHEAD}

        return {"type": "error", "code": result["code"], "message": result["message"]}

    if result["resync_required"]:
        return {"type": "resync", "revision": result["revision"], "reason": RESYNC_BEHIND}

    return {"type": "catch_up", "revision": result["revision"], "batches": result["batches"]}


@dataclass(eq=False)
class _Room:
    session: Any
    # client id -> its connection, in the order clients joined.
    connections: dict[str, Connection] = field(default_factory=dict)
    on_entry: Callable[[LogEntry], None] | None = None


class Hub:
    """The rooms of all sessions that have live connections."""

    def __init__(self) -> None:
        self._guard = threading.Lock()
        self._rooms: dict[Any, _Room] = {}

    # ------------------------------------------------------------------
    # Joining and leaving (the caller holds the session's lock)
    # ------------------------------------------------------------------

    def join(self, session, conn: Connection, since: int) -> bool:
        """Bring ``conn`` into the session's room, starting from revision ``since``.

        Sends the catch-up (or resync) first, then registers for live
        messages, then announces the new presence list to everybody. Returns
        False, after sending an ``error``, when ``since`` is not a valid
        revision; the connection is then not registered.

        A client that connects again while an older connection of the same
        client id is still registered replaces it: the old one is closed.
        """
        first = _catch_up_message(session, since)
        self._deliver(conn, first)

        if first["type"] == "error":
            return False

        with self._guard:
            room = self._rooms.get(session)

            if room is None:
                room = _Room(session=session)
                room.on_entry = lambda entry, room=room: self._broadcast(room, entry)
                self._rooms[session] = room
                session.oplog.subscribe(room.on_entry)

            replaced = room.connections.get(conn.client_id)
            room.connections[conn.client_id] = conn
            targets, presence = self._presence_locked(room)

        if replaced is not None and replaced is not conn:
            replaced.close("replaced")

        for target in targets:
            self._deliver(target, presence)

        return True

    def leave(self, session, conn: Connection) -> bool:
        """Take ``conn`` out of its room and tell the others who is left.

        Does nothing (returns False) if ``conn`` is not the registered
        connection of its client, for example because a newer one replaced it.
        """
        with self._guard:
            room = self._rooms.get(session)

            if room is None or room.connections.get(conn.client_id) is not conn:
                return False

            del room.connections[conn.client_id]

            if room.connections:
                targets, presence = self._presence_locked(room)
            else:
                session.oplog.unsubscribe(room.on_entry)
                del self._rooms[session]
                targets, presence = [], {}

        for target in targets:
            self._deliver(target, presence)

        return True

    # ------------------------------------------------------------------
    # Submitting and questions
    # ------------------------------------------------------------------

    def submit(self, session, conn: Connection, payload: Any) -> dict[str, Any]:
        """Apply a batch sent over ``conn`` and tell the sender how it went.

        The accepted batch itself reaches everyone (the sender too) through
        the log, before the ``result`` message; the ``result`` carries what
        only the sender needs: duplicate, dropped notices, or the refusal.
        """
        result = service.submit(session, conn.client_id, payload)
        message: dict[str, Any] = {"type": "result", **result}

        batch_id = payload.get("client_batch_id") if isinstance(payload, dict) else None

        if isinstance(batch_id, str):
            message["client_batch_id"] = batch_id

        self._deliver(conn, message)
        return result

    def presence(self, session) -> list[dict[str, str]]:
        """Who is connected to ``session`` now, oldest connection first."""
        with self._guard:
            room = self._rooms.get(session)
            return self._clients_locked(room) if room else []

    def has_room(self, session) -> bool:
        with self._guard:
            return session in self._rooms

    # ------------------------------------------------------------------
    # Internals
    # ------------------------------------------------------------------

    def _broadcast(self, room: _Room, entry: LogEntry) -> None:
        """Called by the log, in the appending thread, under the session's lock."""
        message = entry_message(entry)

        with self._guard:
            targets = list(room.connections.values())

        for target in targets:
            self._deliver(target, message)

    @staticmethod
    def _clients_locked(room: _Room) -> list[dict[str, str]]:
        return [{"id": c.client_id, "name": c.name} for c in room.connections.values()]

    def _presence_locked(self, room: _Room) -> tuple[list[Connection], dict[str, Any]]:
        return list(room.connections.values()), {"type": "presence", "clients": self._clients_locked(room)}

    @staticmethod
    def _deliver(conn: Connection, message: dict[str, Any]) -> None:
        # One broken connection must not stop the others from being served.
        try:
            conn.deliver(message)
        except Exception:
            logger.exception("Could not deliver a %s message to client %s", message.get("type"), conn.client_id)


_CLOSE = object()


class QueueConnection:
    """A live connection with a bounded queue, for use inside an asyncio server.

    ``deliver`` and ``close`` may be called from any thread (the thread that
    is publishing a change); they only schedule work on the event loop and
    return at once. The WebSocket route's sender task does::

        while (message := await conn.next_message()) is not None:
            await websocket.send_json(message)

    and ends when the connection closes (``close_reason`` says why).
    If more than ``max_queue`` messages are waiting, the client is too slow:
    its queue is dropped, the connection closes with reason ``"overflow"`` and
    the client is expected to reconnect and catch up from the log.
    """

    def __init__(self, client_id: str, name: str, loop: asyncio.AbstractEventLoop, max_queue: int = DEFAULT_MAX_QUEUE):
        self.client_id = client_id
        self.name = name
        self.close_reason: str | None = None

        self._loop = loop
        self._queue: asyncio.Queue = asyncio.Queue(maxsize=max_queue + 1)  # +1: room for the close marker
        self._max = max_queue

    @property
    def closed(self) -> bool:
        return self.close_reason is not None

    def deliver(self, message: dict[str, Any]) -> None:
        if self.closed:
            return

        self._schedule(self._enqueue, message)

    def close(self, reason: str) -> None:
        """Disconnect now: messages still waiting are dropped."""
        self._schedule(self._shut, reason)

    def end(self, reason: str) -> None:
        """Disconnect after the messages already waiting have been sent.

        Used to say something last ("your session was replaced") and then hang up.
        """
        self._schedule(self._finish, reason)

    async def next_message(self) -> dict[str, Any] | None:
        """The next message, or None once the connection is closed."""
        item = await self._queue.get()

        if item is _CLOSE:
            self._queue.put_nowait(_CLOSE)      # so asking again also returns None
            return None

        return item

    # -- run on the event loop ------------------------------------------

    def _schedule(self, function, argument) -> None:
        try:
            self._loop.call_soon_threadsafe(function, argument)
        except RuntimeError:
            # The loop is gone (the server is stopping): nobody is listening.
            self.close_reason = self.close_reason or "server stopped"

    def _enqueue(self, message: dict[str, Any]) -> None:
        if self.closed:
            return

        if self._queue.qsize() >= self._max:
            self._shut("overflow")
            return

        self._queue.put_nowait(message)

    def _finish(self, reason: str) -> None:
        if self.closed:
            return

        self.close_reason = reason
        self._queue.put_nowait(_CLOSE)      # there is always room: _enqueue stops one short

    def _shut(self, reason: str) -> None:
        if self.closed:
            return

        self.close_reason = reason

        while not self._queue.empty():
            self._queue.get_nowait()

        self._queue.put_nowait(_CLOSE)
