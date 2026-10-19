"""Routes for live collaboration: send a batch of changes, and catch up.

Both need an identified client (``X-Client-Id``, and ``X-Document`` for the
session it is in, see dependencies.py). The work is in backend/collab; these
only hand the request over, under the session's lock.
"""

from typing import Any

from fastapi import APIRouter, Body, Depends, Query, Request

from backend.collab import service
from backend.dependencies import get_session
from backend.sessions import Session

router = APIRouter(
    prefix="/spreadsheet",
    tags=["Collaboration"]
)


@router.post("/ops")
def submit_ops(
    http_request: Request,
    payload: Any = Body(...),
    session: Session = Depends(get_session)
):
    """Apply a batch of changes addressed by row, column and sheet IDs.

    Body: ``{"client_batch_id": "...", "base_revision": 12, "sheet_id": "s1",
    "ops": [...]}``. The answer is always HTTP 200 with either
    ``{"accepted": true, "revision", "duplicate", "applied", "dropped"}`` or
    ``{"accepted": false, "code", "message", "index", "resync_required"}``.
    Sending the same ``client_batch_id`` again is safe: it is not applied twice.
    """
    return service.submit(
        session,
        http_request.headers.get("x-client-id") or "",
        payload
    )


@router.get("/ops")
def ops_since(
    since: int = Query(0, ge=0, description="The newest revision the client has already applied."),
    session: Session = Depends(get_session)
):
    """What changed after revision ``since``, so a client can catch up.

    ``resync_required`` true means the client is too far behind (or something
    changed that can't be replayed) and must load the whole document again.
    """
    return service.changes_since(session, since)
