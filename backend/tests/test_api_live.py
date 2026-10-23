"""The WebSocket route (backend/api/live.py) and the token check on it, through
Starlette's TestClient. The rules themselves are tested without a network in
test_collab_live.py and test_collab_hub.py; these prove the plumbing.

Note for whoever runs these: every ``receive_json`` waits for a message, so a
bug that stops a message from coming shows up as a test that hangs, not fails.
"""

import contextlib
import dataclasses
import json
import tempfile
from urllib.parse import urlencode

from fastapi.testclient import TestClient
from starlette.websockets import WebSocketDisconnect

import backend.main as main_module
from backend.collab import service
from backend.collab.hub import Hub
from backend.dependencies import get_hub, get_registry
from backend.main import app, require_access_token
from backend.tests.test_collab_hub import ALICE, BOB
from backend.tests.test_collab_live import ops_text
from backend.tests.test_sessions import make_registry, workbook

SECRET = "a-long-shared-secret"


@contextlib.contextmanager
def live_server(folder, token=None):
    """The real app, with a registry and hub of its own and a document open in it."""
    workbook(folder, "a.xlsx")
    registry, clock = make_registry(folder)
    session = registry.open("a.xlsx", ALICE, "Alice")

    hub = Hub()
    app.dependency_overrides[get_registry] = lambda: registry
    app.dependency_overrides[get_hub] = lambda: hub

    original_settings = main_module.settings

    if token is None:
        app.dependency_overrides[require_access_token] = lambda: None
    else:
        main_module.settings = dataclasses.replace(original_settings, access_token=token)

    try:
        yield TestClient(app), registry, clock, session, hub
    finally:
        for dependency in (get_registry, get_hub, require_access_token):
            app.dependency_overrides.pop(dependency, None)

        main_module.settings = original_settings


def url(session, client, name="Alice", since=0, **extra):
    query = {"document": session.id, "client": client, "name": name, "since": since, **extra}
    return "/spreadsheet/live?" + urlencode(query)


def drain(ws, count=2):
    """Read the two messages every new connection starts with (catch_up, presence)."""
    return [ws.receive_json() for _ in range(count)]


def close_code(ws):
    """The code the server closed the connection with."""
    try:
        ws.receive_json()
    except WebSocketDisconnect as closed:
        return closed.code

    raise AssertionError("the connection was not closed")


def rejected_at_the_handshake(client, address, **options):
    try:
        with client.websocket_connect(address, **options):
            pass
    except WebSocketDisconnect as refused:
        return refused.code

    raise AssertionError("the connection was accepted")


# ----------------------------------------------------------------------
# The basics
# ----------------------------------------------------------------------


def test_connecting_gives_catch_up_and_presence_and_pings_are_answered():
    with tempfile.TemporaryDirectory() as folder, live_server(folder) as (client, registry, clock, session, hub):
        with client.websocket_connect(url(session, ALICE)) as ws:
            catch_up, presence = drain(ws)

            assert catch_up == {"type": "catch_up", "revision": 0, "batches": []}
            assert presence == {"type": "presence", "clients": [{"id": ALICE, "name": "Alice"}]}

            ws.send_json({"type": "ping"})
            assert ws.receive_json() == {"type": "pong"}


def test_a_name_in_arabic_comes_through_the_url():
    with tempfile.TemporaryDirectory() as folder, live_server(folder) as (client, registry, clock, session, hub):
        with client.websocket_connect(url(session, ALICE, name="سلمى")) as ws:
            assert drain(ws)[1]["clients"] == [{"id": ALICE, "name": "سلمى"}]


def test_ops_sent_by_one_client_reach_the_other_and_the_sender_gets_a_result():
    with tempfile.TemporaryDirectory() as folder, live_server(folder) as (client, registry, clock, session, hub):
        with client.websocket_connect(url(session, ALICE)) as alice:
            drain(alice)

            with client.websocket_connect(url(session, BOB, "Bob")) as bob:
                drain(bob)
                assert [c["name"] for c in alice.receive_json()["clients"]] == ["Alice", "Bob"]

                alice.send_text(ops_text(session, "Zed"))

                own_batch, result = alice.receive_json(), alice.receive_json()
                assert own_batch["type"] == "batch" and own_batch["batch"]["revision"] == 1
                assert result["type"] == "result" and result["accepted"] is True
                assert result["client_batch_id"] == "b1"

                seen = bob.receive_json()
                assert seen["type"] == "batch" and seen["batch"]["client_id"] == ALICE

        assert next(iter(session.controller.grid_data().rows[0].values())) == "Zed"


def test_a_change_made_outside_the_connection_is_pushed_to_it():
    with tempfile.TemporaryDirectory() as folder, live_server(folder) as (client, registry, clock, session, hub):
        with client.websocket_connect(url(session, ALICE)) as alice:
            drain(alice)

            # What an HTTP request does: apply a batch under the session's lock, from another thread.
            with session.lock:
                service.submit(session, BOB, json.loads(ops_text(session, "From HTTP", batch_id="http1"))["payload"])

            pushed = alice.receive_json()
            assert pushed["type"] == "batch" and pushed["batch"]["client_id"] == BOB


def test_a_client_that_reconnects_with_its_last_revision_is_caught_up():
    with tempfile.TemporaryDirectory() as folder, live_server(folder) as (client, registry, clock, session, hub):
        with session.lock:
            service.submit(session, BOB, json.loads(ops_text(session, "One", batch_id="one"))["payload"])

        with client.websocket_connect(url(session, ALICE, since=0)) as alice:
            catch_up = alice.receive_json()

            assert [b["revision"] for b in catch_up["batches"]] == [1]


def test_a_client_that_is_ahead_of_the_server_is_told_to_reload():
    with tempfile.TemporaryDirectory() as folder, live_server(folder) as (client, registry, clock, session, hub):
        with client.websocket_connect(url(session, ALICE, since=99)) as alice:
            assert alice.receive_json()["type"] == "resync"


def test_presence_follows_clients_joining_and_leaving():
    with tempfile.TemporaryDirectory() as folder, live_server(folder) as (client, registry, clock, session, hub):
        with client.websocket_connect(url(session, ALICE)) as alice:
            drain(alice)

            with client.websocket_connect(url(session, BOB, "Bob")) as bob:
                drain(bob)
                assert len(alice.receive_json()["clients"]) == 2

            assert alice.receive_json()["clients"] == [{"id": ALICE, "name": "Alice"}]


def test_connecting_again_with_the_same_client_id_replaces_the_old_connection():
    with tempfile.TemporaryDirectory() as folder, live_server(folder) as (client, registry, clock, session, hub):
        with client.websocket_connect(url(session, ALICE)) as first:
            drain(first)

            with client.websocket_connect(url(session, ALICE)) as second:
                drain(second)

                assert close_code(first) == 4001

                second.send_json({"type": "ping"})
                assert second.receive_json() == {"type": "pong"}


# ----------------------------------------------------------------------
# Bad input
# ----------------------------------------------------------------------


def test_missing_parameters_are_answered_with_an_error_and_a_close():
    with tempfile.TemporaryDirectory() as folder, live_server(folder) as (client, *_):
        for address in (
            "/spreadsheet/live",
            "/spreadsheet/live?client=" + ALICE,
            "/spreadsheet/live?document=abc&client=short",
        ):
            with client.websocket_connect(address) as ws:
                assert ws.receive_json()["code"] == "BAD_REQUEST"
                assert close_code(ws) == 1008


def test_a_document_that_is_not_open_is_answered_with_an_error_and_a_close():
    with tempfile.TemporaryDirectory() as folder, live_server(folder) as (client, registry, clock, session, hub):
        with client.websocket_connect("/spreadsheet/live?document=0123456789abcdef&client=" + ALICE) as ws:
            assert ws.receive_json()["code"] == "SESSION_NOT_OPEN"
            assert close_code(ws) == 1008


def test_bad_messages_get_an_error_and_the_connection_stays_open():
    with tempfile.TemporaryDirectory() as folder, live_server(folder) as (client, registry, clock, session, hub):
        with client.websocket_connect(url(session, ALICE)) as ws:
            drain(ws)

            ws.send_text("not json")
            assert ws.receive_json()["code"] == "BAD_REQUEST"

            ws.send_bytes(b"\x00\x01")
            assert ws.receive_json()["code"] == "BAD_REQUEST"

            ws.send_json({"type": "nonsense"})
            assert ws.receive_json()["code"] == "BAD_REQUEST"

            ws.send_json({"type": "ping"})
            assert ws.receive_json() == {"type": "pong"}


def test_a_session_that_expired_is_reported_and_the_connection_closed():
    with tempfile.TemporaryDirectory() as folder, live_server(folder) as (client, registry, clock, session, hub):
        with client.websocket_connect(url(session, ALICE)) as ws:
            drain(ws)

            clock.advance(500)                          # no pings: the server forgot the client
            ws.send_json({"type": "ping"})

            assert ws.receive_json()["code"] == "SESSION_REPLACED"
            assert close_code(ws) == 1012


# ----------------------------------------------------------------------
# The access token
# ----------------------------------------------------------------------


def test_a_websocket_without_the_token_is_refused_at_the_handshake():
    with tempfile.TemporaryDirectory() as folder, live_server(folder, token=SECRET) as (client, registry, clock, session, hub):
        assert rejected_at_the_handshake(client, url(session, ALICE)) == 1008
        assert rejected_at_the_handshake(client, url(session, ALICE, token="wrong-token-value")) == 1008
        assert rejected_at_the_handshake(client, url(session, ALICE), headers={"Authorization": "Bearer nope-nope-nope"}) == 1008


def test_a_websocket_may_carry_the_token_in_the_query_or_in_the_header():
    with tempfile.TemporaryDirectory() as folder, live_server(folder, token=SECRET) as (client, registry, clock, session, hub):
        with client.websocket_connect(url(session, ALICE, token=SECRET)) as ws:
            assert ws.receive_json()["type"] == "catch_up"

        with client.websocket_connect(url(session, ALICE), headers={"Authorization": f"Bearer {SECRET}"}) as ws:
            assert ws.receive_json()["type"] == "catch_up"


def test_a_wrong_header_is_not_rescued_by_a_right_query_token():
    with tempfile.TemporaryDirectory() as folder, live_server(folder, token=SECRET) as (client, registry, clock, session, hub):
        address = url(session, ALICE, token=SECRET)

        assert rejected_at_the_handshake(client, address, headers={"Authorization": "Bearer something-else"}) == 1008


def test_ordinary_requests_still_need_the_header_and_ignore_a_token_in_the_url():
    with tempfile.TemporaryDirectory() as folder, live_server(folder, token=SECRET) as (client, *_):
        assert client.get("/sessions").status_code == 401
        assert client.get("/sessions?token=" + SECRET).status_code == 401
        assert client.get("/sessions", headers={"Authorization": f"Bearer {SECRET}"}).status_code == 200
