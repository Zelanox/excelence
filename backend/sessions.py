"""Document sessions: one live, in-memory document per open file, shared by
everyone who has it open.

Until now the server held a single global document, so two people opening
different files replaced each other's. A *session* is one open document
together with its own lock and the list of clients currently in it:

* Everyone who opens the same file joins the SAME session (the same
  in-memory document), instead of each loading their own copy from disk -
  so they see each other's unsaved changes, and nobody overwrites anybody.
* Different files are different sessions with independent locks, so work on
  one document never waits for another.
* The server knows WHO is in a session (client id + display name). That is
  the foundation for "who is here", per-user undo and live updates.

A client identifies a session by an opaque session id handed back when it
opens a file (HTTP headers must be ASCII, and file names often are not - the
documents here have Arabic names - so the file name can't be the identifier).

Clients that send no identity at all (older clients, or anything calling the
API by hand) keep working: they share one "default" session, which behaves
exactly like the old single global document. Mixing the two styles on the
SAME file is refused rather than letting two in-memory copies drift apart.

This module has no web-framework dependency so it can be tested directly.
"""

from __future__ import annotations

import hashlib
import os
import re
import threading
import time
from collections import OrderedDict
from collections.abc import Callable
from dataclasses import dataclass, field
from urllib.parse import unquote

from backend.collab.op_log import OpLog
from backend.controller.controller import Controller
from backend.utils.logger import get_logger

logger = get_logger("sessions")

CLIENT_ID_PATTERN = re.compile(r"^[A-Za-z0-9_-]{8,64}$")
MAX_NAME_LENGTH = 40
DEFAULT_NAME = "Guest"

# A client that has not been heard from for this long is treated as gone.
DEFAULT_CLIENT_TTL = 120.0

# How many recently released sessions are remembered, so a client whose
# session was released while it was idle can be re-attached transparently.
MAX_REMEMBERED_SESSIONS = 100


class SessionNotOpen(Exception):
    """The session id isn't open and can't be re-opened."""


class DocumentBusy(Exception):
    """The document can't be opened this way right now; the message says why."""


def document_key(filename: object) -> str | None:
    """The identity of a document, for "is this the same file?".

    Equivalent spellings (``reports\\q1.xlsx``, ``./reports/q1.xlsx``) map to
    the same key, and on a case-insensitive file system (Windows)
    ``Budget.xlsx`` and ``budget.xlsx`` do too - otherwise two clients could
    each hold their own copy of one file and overwrite each other on save.
    Returns None for anything that isn't a plain relative path.
    """
    if not isinstance(filename, str):
        return None

    text = filename.strip().replace("\\", "/")

    if not text or text.startswith("/") or re.match(r"^[A-Za-z]:", text):
        return None

    parts = [part for part in text.split("/") if part not in ("", ".")]

    if not parts or ".." in parts:
        return None

    return os.path.normcase("/".join(parts)).replace("\\", "/")


def session_id_for(key: str) -> str:
    """A stable, header-safe id for a document key."""
    return hashlib.sha256(key.encode("utf-8")).hexdigest()[:16]


def valid_client_id(value: object) -> bool:
    return isinstance(value, str) and CLIENT_ID_PATTERN.match(value) is not None


def clean_client_name(raw: object) -> str:
    """A safe display name from a header value.

    Headers are ASCII, so clients percent-encode the name (an Arabic name
    arrives as ``%D8%B3...``); it is decoded here, stripped of control
    characters, collapsed to single spaces and length-limited.
    """
    if not isinstance(raw, str):
        return DEFAULT_NAME

    try:
        text = unquote(raw, errors="strict")
    except UnicodeDecodeError:
        text = raw

    text = "".join(ch for ch in text if ch.isprintable())
    text = " ".join(text.split())[:MAX_NAME_LENGTH].strip()

    return text or DEFAULT_NAME


@dataclass
class ClientInfo:

    client_id: str
    name: str
    joined_at: float
    last_seen: float


@dataclass(eq=False)
class Session:

    id: str
    key: str
    filename: str
    controller: Controller
    lock: threading.Lock = field(default_factory=threading.Lock)
    clients: dict[str, ClientInfo] = field(default_factory=dict)

    # Numbered record of the changes made through the operation path, so
    # clients can catch up (see backend/collab).
    oplog: OpLog = field(default_factory=OpLog)

    # The document's change count (Document.change_count) as of the last
    # change the log accounted for. A difference means somebody changed the
    # document through a route that doesn't write to the log (see
    # collab.service.account_for_untracked_changes).
    accounted_changes: int = 0

    def __post_init__(self) -> None:
        self.accounted_changes = self.controller.document.change_count

    @property
    def is_default(self) -> bool:
        return self.id == ""


class SessionRegistry:
    """All open sessions, plus the legacy "default" one."""

    def __init__(
        self,
        controller_factory: Callable[[], Controller] = Controller,
        clock: Callable[[], float] = time.monotonic,
        client_ttl: float = DEFAULT_CLIENT_TTL,
    ) -> None:
        self._factory = controller_factory
        self._clock = clock
        self._ttl = client_ttl

        # Guards the dictionaries below. Never held while waiting on a
        # session's lock (see _expire_locked), so the two can't deadlock.
        self._guard = threading.RLock()
        self._sessions: dict[str, Session] = {}
        self._by_key: dict[str, str] = {}
        self._released: OrderedDict[str, str] = OrderedDict()

        # The old single global document, for clients with no identity.
        self.default = Session(id="", key="", filename="", controller=controller_factory())

    # ------------------------------------------------------------------
    # Opening and joining
    # ------------------------------------------------------------------

    def open(self, filename: str, client_id: str, client_name: str | None = None) -> Session | None:
        """Join the session for ``filename``, loading the file if nobody has it open.

        Returns None if the file can't be opened (bad name, missing, not a
        workbook) or the client id is invalid. Raises DocumentBusy if the
        file is open in the legacy default session.
        """
        key = document_key(filename)

        if key is None or not valid_client_id(client_id):
            return None

        with self._guard:
            self._expire_locked()
            session = self._open_locked(key, filename)

            if session is None:
                return None

            self._join(session, client_id, client_name)
            return session

    def create(self, filename: str, client_id: str, client_name: str | None = None) -> Session | None:
        """Create a new workbook, save it, and join its (new) session.

        Refuses (DocumentBusy) if the file already exists or is open, rather
        than silently replacing it.
        """
        key = document_key(filename)

        if key is None or not valid_client_id(client_id):
            return None

        # The document list only shows .xlsx files, so a workbook saved under
        # any other name would exist on disk but never appear in the app.
        if not filename.strip().lower().endswith(".xlsx"):
            return None

        with self._guard:
            self._expire_locked()
            self._refuse_if_default_has(key)

            if key in self._by_key:
                raise DocumentBusy("A document with that name is already open.")

            controller = self._factory()
            resolved = controller.document._resolve_path(filename)

            if resolved is None:
                return None

            if os.path.exists(resolved):
                raise DocumentBusy("A document with that name already exists.")

            if not (controller.create_document(filename) and controller.save_document()):
                return None

            session = self._register(key, filename, controller)
            self._join(session, client_id, client_name)
            return session

    def _open_locked(self, key: str, filename: str) -> Session | None:
        session = self._sessions.get(self._by_key.get(key, ""))

        if session is not None:
            return session

        self._refuse_if_default_has(key)

        controller = self._factory()

        if not controller.open_document(filename):
            return None

        return self._register(key, filename, controller)

    def _refuse_if_default_has(self, key: str) -> None:
        if document_key(self.default.controller.filename()) == key:
            raise DocumentBusy(
                "This document is open in a single-user (legacy) session; "
                "close it there first."
            )

    def _register(self, key: str, filename: str, controller: Controller) -> Session:
        session = Session(id=session_id_for(key), key=key, filename=filename, controller=controller)
        self._sessions[session.id] = session
        self._by_key[key] = session.id
        self._released.pop(session.id, None)
        logger.info("Opened session %s for %s", session.id, filename)
        return session

    def _join(self, session: Session, client_id: str, client_name: str | None) -> None:
        now = self._clock()
        name = clean_client_name(client_name) if client_name is not None else None
        existing = session.clients.get(client_id)

        if existing is None:
            session.clients[client_id] = ClientInfo(
                client_id=client_id,
                name=name or DEFAULT_NAME,
                joined_at=now,
                last_seen=now,
            )
            return

        existing.last_seen = now

        if name:
            existing.name = name

    # ------------------------------------------------------------------
    # Finding the session a request belongs to
    # ------------------------------------------------------------------

    def resolve(
        self,
        session_id: str | None,
        client_id: str | None = None,
        client_name: str | None = None,
    ) -> Session:
        """The session a request is for, refreshing the caller's presence.

        No session id means the legacy default session. A session that
        ended while its client was idle (everyone expired, so it was saved
        and released) is re-opened transparently from disk - its document
        was saved on release, so nothing is lost. Raises SessionNotOpen for
        an id that was never open (e.g. the server restarted).
        """
        if not session_id:
            return self.default

        with self._guard:
            self._expire_locked()
            session = self._sessions.get(session_id)

            if session is None:
                filename = self._released.get(session_id)
                key = document_key(filename) if filename else None

                if key is None:
                    raise SessionNotOpen(session_id)

                try:
                    session = self._open_locked(key, filename)
                except DocumentBusy:
                    session = None

                if session is None:
                    raise SessionNotOpen(session_id)

                logger.info("Re-opened released session %s", session_id)

            if valid_client_id(client_id):
                self._join(session, client_id, client_name)

            return session

    # ------------------------------------------------------------------
    # Leaving and releasing
    # ------------------------------------------------------------------

    def leave(self, session: Session, client_id: str | None) -> bool:
        """Remove a client; release the session if it was the last one.

        The CALLER must hold ``session.lock`` (a request handler does, via
        its dependency): releasing saves and closes the document, which must
        not overlap other work on it. Returns True if the session was
        released (saved and dropped).
        """
        if session.is_default:
            return False

        with self._guard:
            if client_id is not None:
                session.clients.pop(client_id, None)

            if session.clients:
                return False

            return self._release(session)

    def _release(self, session: Session) -> bool:
        """Save and drop a session that has no clients. Caller holds its lock.

        If the save fails the session is KEPT, so unsaved work is never
        thrown away - it will be retried on the next expiry or shutdown.
        """
        controller = session.controller

        if controller.modified() and not controller.save_document():
            logger.error("Could not save %s; keeping its session open", session.filename)
            return False

        self._sessions.pop(session.id, None)
        self._by_key.pop(session.key, None)
        self._released[session.id] = session.filename
        self._released.move_to_end(session.id)

        while len(self._released) > MAX_REMEMBERED_SESSIONS:
            self._released.popitem(last=False)

        controller.close_document()
        logger.info("Released session %s (%s)", session.id, session.filename)
        return True

    def _expire_locked(self) -> None:
        """Drop clients not heard from within the TTL, and release empty sessions.

        Called with the registry guard held. It must never WAIT for a
        session lock - a request already holding that lock may be waiting on
        the guard - so a busy session is simply skipped and retried next time.
        """
        now = self._clock()

        for session in list(self._sessions.values()):
            for client_id, info in list(session.clients.items()):
                if now - info.last_seen > self._ttl:
                    del session.clients[client_id]

            if session.clients:
                continue

            if session.lock.acquire(blocking=False):
                try:
                    self._release(session)
                finally:
                    session.lock.release()

    # ------------------------------------------------------------------
    # Questions about the state of things
    # ------------------------------------------------------------------

    def is_open(self, filename: str) -> bool:
        """Whether ``filename`` is loaded anywhere (any session, or the default)."""
        key = document_key(filename)

        if key is None:
            return False

        with self._guard:
            return key in self._by_key or document_key(self.default.controller.filename()) == key

    def is_open_in_session(self, filename: str) -> bool:
        """Whether ``filename`` is open in a SHARED session (not the legacy default).

        Used to refuse deleting, renaming or overwriting a file other people
        are working in. The single-user default session is left alone so its
        behavior doesn't change.
        """
        key = document_key(filename)

        if key is None:
            return False

        with self._guard:
            return key in self._by_key

    def describe(self) -> list[dict]:
        """A snapshot of every open document and who is in it (for "who is here")."""
        with self._guard:
            self._expire_locked()

            return [
                {
                    "session": session.id,
                    "document": session.filename,
                    "modified": session.controller.modified(),
                    "clients": [
                        {"id": info.client_id, "name": info.name}
                        for info in sorted(session.clients.values(), key=lambda c: c.joined_at)
                    ],
                }
                for session in self._sessions.values()
            ]

    def save_all(self, lock_timeout: float = 10.0) -> int:
        """Save every session with unsaved changes (used at shutdown).

        Returns how many were saved. A session whose lock can't be taken
        within ``lock_timeout`` is skipped with an error rather than hanging
        shutdown.
        """
        with self._guard:
            sessions = [self.default, *self._sessions.values()]

        saved = 0

        for session in sessions:
            if not session.lock.acquire(timeout=lock_timeout):
                logger.error("Shutdown: %s was busy; not saved", session.filename or "default session")
                continue

            try:
                controller = session.controller

                if controller.is_loaded() and controller.modified() and controller.save_document():
                    saved += 1
            finally:
                session.lock.release()

        return saved
