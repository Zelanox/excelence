"""The WebSocket route for live collaboration: ``/spreadsheet/live``.

Only the plumbing between the network and backend/collab/live.py lives here:

    ws://<server>/spreadsheet/live?document=<session id>&client=<client id>
        &name=<display name>&since=<last revision applied>&token=<access token>

``document`` and ``client`` are required (the same values the client sends as
``X-Document`` and ``X-Client-Id`` over HTTP); ``name`` and ``since`` default
to "Guest" and 0. Browsers cannot set headers on a WebSocket, so the shared
access token may be sent as the ``token`` query parameter (a non-browser
client may use the ``Authorization`` header instead). It is checked by the
app-wide dependency in backend/main.py *before* the connection is accepted, so
a connection without it is refused at the handshake.

Once accepted, the server sends ``catch_up`` (or ``resync``) and ``presence``,
then every change as it happens; the client sends ``ops`` and ``ping`` (see
backend/collab/live.py and backend/collab/hub.py for the messages).

Problems with the parameters, or with the document, are sent as an ``error``
message and the connection is closed with code 1008.

When the SERVER ends a connection it uses these close codes:

    1008  refused: bad parameters or document not open; reconnecting won't help
          until the client fixes it (or opens the document again)
    1012  the document was closed and re-opened on the server, or forgotten:
          reconnect (catch-up will tell it to reload)
    1013  the client fell too far behind: reconnect and catch up
    1011  an unexpected error on the server: reconnect
    4001  another connection with the same client id took over: do NOT
          reconnect automatically, or the two would keep replacing each other
"""

import asyncio

import anyio
from fastapi import APIRouter, Depends, Query, WebSocket
from starlette.concurrency import run_in_threadpool

from backend.collab import live
from backend.collab.hub import Hub, QueueConnection
from backend.dependencies import get_hub, get_registry
from backend.sessions import SessionRegistry
from backend.utils.logger import get_logger

logger = get_logger("live")

router = APIRouter(
    prefix="/spreadsheet",
    tags=["Collaboration"]
)

CLOSE_REFUSED = 1008
CLOSE_SESSION_CLOSED = 1012
CLOSE_TOO_SLOW = 1013
CLOSE_INTERNAL = 1011
CLOSE_REPLACED = 4001

# What the server says when it hangs up, by the connection's close reason.
# (Any other reason, such as "disconnected", means the client left first.)
CLOSE_CODES = {
    "replaced": CLOSE_REPLACED,
    "overflow": CLOSE_TOO_SLOW,
    "session closed": CLOSE_SESSION_CLOSED,
    "internal error": CLOSE_INTERNAL,
}


@router.websocket("/live")
async def live_socket(
    websocket: WebSocket,
    document: str | None = Query(None),
    client: str | None = Query(None),
    name: str | None = Query(None),
    since: str | None = Query(None),
    registry: SessionRegistry = Depends(get_registry),
    hub: Hub = Depends(get_hub),
):
    """Live changes and presence for one document."""
    await websocket.accept()

    try:
        params = live.parse_connect(document, client, name, since)
    except live.ConnectError as error:
        await _refuse(websocket, error)
        return

    conn = QueueConnection(params.client_id, params.name, asyncio.get_running_loop())

    try:
        session = await run_in_threadpool(live.connect, registry, hub, params, conn)
    except live.ConnectError as error:
        await _refuse(websocket, error)
        return

    try:
        # Two jobs run side by side inside one task group (so that stopping
        # the connection, from either side, cleanly stops both): reading the
        # client's messages, and sending the queued ones. Every way a
        # connection can end closes ``conn``, which ends the sending loop;
        # then the reading is stopped.
        async with anyio.create_task_group() as tasks:
            tasks.start_soon(_receive, websocket, registry, hub, session, conn, params)
            await _pump(websocket, conn)
            tasks.cancel_scope.cancel()
    finally:
        conn.close("disconnected")          # no effect when it was already closed

        # Leaving the room must happen even when this task is being cancelled
        # (the server stopping, a test client hanging up).
        with anyio.CancelScope(shield=True):
            try:
                await run_in_threadpool(live.disconnect, hub, session, conn)
            except Exception:
                logger.exception("Could not remove client %s from its room", params.client_id)

    code = CLOSE_CODES.get(conn.close_reason or "")

    if code is not None:
        await _close(websocket, code, conn.close_reason or "")


async def _pump(websocket: WebSocket, conn: QueueConnection) -> None:
    """Send queued messages until the connection is closed."""
    while True:
        message = await conn.next_message()

        if message is None:
            return

        try:
            await websocket.send_json(message)
        except Exception:
            conn.close("disconnected")          # the client is gone
            return


async def _receive(websocket: WebSocket, registry, hub, session, conn: QueueConnection, params) -> None:
    """Read the client's messages until it disconnects or the session is gone."""
    try:
        while True:
            message = await websocket.receive()

            if message["type"] == "websocket.disconnect":
                conn.close("disconnected")
                return

            text = message.get("text")

            if text is None:
                conn.deliver({"type": "error", "code": "BAD_REQUEST", "message": "Send text (JSON) messages only."})
                continue

            outcome = await run_in_threadpool(live.handle_text, registry, hub, session, conn, params.document, text)

            if outcome == live.HANG_UP:
                conn.end("session closed")     # the client was told why; hang up once that is sent
                return
    except Exception:
        logger.exception("Live connection of client %s failed", params.client_id)
        conn.close("internal error")


async def _refuse(websocket: WebSocket, error: live.ConnectError) -> None:
    try:
        await websocket.send_json({"type": "error", "code": error.code, "message": error.message})
    except Exception:
        pass

    await _close(websocket, CLOSE_REFUSED, error.code)


async def _close(websocket: WebSocket, code: int, reason: str) -> None:
    try:
        await websocket.close(code=code, reason=reason[:100])
    except Exception:
        pass            # the client is already gone
