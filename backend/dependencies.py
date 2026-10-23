"""Shared objects and request dependencies for the API.

Every request is attached to a SESSION (see backend/sessions.py):

* A client that opened a document with an identity sends the session id it
  was given in ``X-Document``, plus ``X-Client-Id`` (and optionally a
  percent-encoded ``X-Client-Name``). Its request runs against THAT
  document, under THAT document's lock - so different documents never wait
  for each other, while requests for the same document are serialized.
* A request with no ``X-Document`` uses the "default" session, which behaves
  exactly like the old single global document. Existing clients keep
  working unchanged.

The per-session lock replaces the old process-wide one. Its purpose is the
same: FastAPI runs ordinary route functions on a thread pool and the client
fires several requests at once, so handlers for one document must not
interleave (pandas is not thread-safe for concurrent writes, and the order
of undo history would depend on thread scheduling).
"""

from fastapi import Depends, HTTPException, Request

from backend.collab.hub import Hub
from backend.collab.service import account_for_untracked_changes
from backend.controller.controller import Controller
from backend.sessions import Session, SessionNotOpen, SessionRegistry

registry = SessionRegistry()

# The live connections (see backend/collab/hub.py), shared by the whole server.
hub = Hub()

# The default session's controller, kept under its old name for anything that
# still imports it.
controller = registry.default.controller


def get_registry() -> SessionRegistry:
    return registry


def get_hub() -> Hub:
    return hub


def get_session(request: Request):
    """The session this request belongs to, held (locked) for the whole request."""
    try:
        session = registry.resolve(
            request.headers.get("x-document"),
            request.headers.get("x-client-id"),
            request.headers.get("x-client-name"),
        )
    except SessionNotOpen:
        # Not "not found": the route exists, the document just isn't open.
        raise HTTPException(
            status_code=409,
            detail=(
                "SESSION_NOT_OPEN: that document is no longer open on the "
                "server (it may have restarted). Open the document again."
            ),
        ) from None

    with session.lock:
        try:
            yield session
        finally:
            # A change made by a route that doesn't write to the operation
            # log must still reach the other clients (as a "reload" entry).
            account_for_untracked_changes(session)


def get_controller(session: Session = Depends(get_session)) -> Controller:
    return session.controller
