"""The rules of a live connection, without the web framework.

backend/api/live.py is the WebSocket route; everything it decides lives here so
it can be tested without a network:

* ``parse_connect`` checks the connection's query parameters.
* ``connect`` finds the session and joins its room (catch-up, presence).
* ``handle_text`` deals with one message from the client (``ping`` or ``ops``).
* ``disconnect`` leaves the room.

Messages from the client (JSON text):

    {"type": "ping"}                      answered with {"type": "pong"}
    {"type": "ops", "payload": {...}}     the same payload as ``POST /spreadsheet/ops``;
                                          answered with the batch (to everyone) and a
                                          ``result`` (to the sender), see collab/hub.py

Anything else, and anything that isn't JSON, is answered with an ``error``
message and the connection stays open.

Keeping the session alive. A connected client sends nothing over HTTP, and the
session registry forgets clients it has not heard from for 120 seconds (and
then saves and closes a document nobody has open). So every message, ``ping``
included, refreshes the client in the registry: clients should ping about
every 30 seconds.

Disconnecting does NOT remove the client from the registry. Presence (who is
here) follows the live connections and changes at once, but the session
stays open until the usual idle expiry, so a phone that loses Wi-Fi for a
moment reconnects to the same open document instead of making the server
save, close and re-open it.
"""

from __future__ import annotations

import json
import re
from dataclasses import dataclass
from typing import Any

from backend.collab.hub import Connection, Hub
from backend.sessions import DEFAULT_NAME, MAX_NAME_LENGTH, SessionNotOpen, SessionRegistry, valid_client_id
from backend.utils.logger import get_logger

logger = get_logger("collab")

# A batch is at most 500 changes; this is far more than that needs.
MAX_MESSAGE_CHARS = 1_000_000

# What handle_text tells the route to do next.
CONTINUE = "continue"
HANG_UP = "hang_up"

_REVISION = re.compile(r"^[0-9]{1,12}$")


class ConnectError(Exception):
    """A connection that can't be accepted; ``code`` and ``message`` go to the client."""

    def __init__(self, code: str, message: str) -> None:
        super().__init__(message)
        self.code = code
        self.message = message


@dataclass(frozen=True)
class ConnectParams:
    document: str       # the session id the client was given when it opened the document
    client_id: str
    name: str
    since: int          # the last revision the client has applied


def parse_connect(document: object, client: object, name: object, since: object) -> ConnectParams:
    """Check the query parameters of a new connection, or raise ConnectError."""
    if not isinstance(document, str) or not document.strip():
        raise ConnectError("BAD_REQUEST", "Missing 'document': open the document first and use the session id it returned.")

    if not valid_client_id(client):
        raise ConnectError("BAD_REQUEST", "Missing or invalid 'client' (8-64 letters, digits, '-' or '_').")

    if name is None:
        clean_name = DEFAULT_NAME
    else:
        text = name if isinstance(name, str) else ""
        clean_name = " ".join("".join(ch for ch in text if ch.isprintable()).split())

        if not clean_name or len(clean_name) > MAX_NAME_LENGTH:
            raise ConnectError("BAD_REQUEST", f"'name' must be 1-{MAX_NAME_LENGTH} characters.")

    if since is None:
        revision = 0
    elif isinstance(since, str) and _REVISION.match(since):
        revision = int(since)
    else:
        raise ConnectError("BAD_REQUEST", "'since' must be a whole number, 0 or more.")

    return ConnectParams(document=document.strip(), client_id=client, name=clean_name, since=revision)


def connect(registry: SessionRegistry, hub: Hub, params: ConnectParams, conn: Connection):
    """Find the session and join its room. Blocking: run it in a worker thread.

    Returns the session. Raises ConnectError if the document is not open on
    this server (it may have restarted: the client should open it again).
    """
    try:
        session = registry.resolve(params.document, params.client_id, params.name)
    except SessionNotOpen:
        raise ConnectError(
            "SESSION_NOT_OPEN",
            "That document is no longer open on the server (it may have restarted). Open the document again.",
        ) from None

    with session.lock:
        if not hub.join(session, conn, params.since):
            raise ConnectError("BAD_REQUEST", "Invalid revision.")

    return session


def disconnect(hub: Hub, session, conn: Connection) -> None:
    """Leave the room (presence updates for everyone else). Blocking."""
    with session.lock:
        hub.leave(session, conn)


def handle_text(
    registry: SessionRegistry,
    hub: Hub,
    session,
    conn: Connection,
    document: str,
    text: str,
) -> str:
    """Deal with one message from the client. Blocking: run it in a worker thread.

    Returns CONTINUE, or HANG_UP when the connection can't go on (the
    document was closed and re-opened on the server, or forgotten): the
    client has been told why and should reconnect.
    """
    # Every message proves the client is alive. It also shows whether the
    # session this connection joined is still the one the server has open:
    # a session that expired and was re-opened is a new object with a new,
    # empty log, and changes must not be applied to the old one.
    try:
        current = registry.resolve(document, conn.client_id, conn.name)
    except SessionNotOpen:
        conn.deliver(_error("SESSION_NOT_OPEN", "That document is no longer open on the server. Open the document again."))
        return HANG_UP

    if current is not session:
        conn.deliver(_error("SESSION_REPLACED", "The document was closed and opened again on the server. Reconnect to reload it."))
        return HANG_UP

    try:
        _dispatch(hub, session, conn, text)
    except Exception:
        logger.exception("Unexpected failure handling a live message from client %s", conn.client_id)
        conn.deliver(_error("INTERNAL_ERROR", "The server could not handle that message."))

    return CONTINUE


def _dispatch(hub: Hub, session, conn: Connection, text: str) -> None:
    if len(text) > MAX_MESSAGE_CHARS:
        conn.deliver(_error("MESSAGE_TOO_LARGE", "That message is too large."))
        return

    try:
        message: Any = json.loads(text)
    except (ValueError, RecursionError):
        conn.deliver(_error("BAD_REQUEST", "Messages must be JSON."))
        return

    if not isinstance(message, dict):
        conn.deliver(_error("BAD_REQUEST", "A message must be a JSON object with a 'type'."))
        return

    kind = message.get("type")

    if kind == "ping":
        conn.deliver({"type": "pong"})
    elif kind == "ops":
        with session.lock:
            hub.submit(session, conn, message.get("payload"))
    else:
        conn.deliver(_error("BAD_REQUEST", "Unknown message type. Use 'ping' or 'ops'."))


def _error(code: str, message: str) -> dict[str, Any]:
    return {"type": "error", "code": code, "message": message}
