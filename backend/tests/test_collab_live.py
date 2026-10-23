"""Tests for the rules of a live connection (backend/collab/live.py): no web framework."""

import tempfile

from backend.collab import live
from backend.collab.hub import Hub
from backend.collab.live import CONTINUE, HANG_UP, ConnectError, handle_text, parse_connect
from backend.sessions import SessionRegistry
from backend.tests.test_collab_hub import ALICE, BOB, FakeConnection
from backend.tests.test_sessions import make_registry, workbook

import json


def open_document(folder, clients=((ALICE, "Alice"),)):
    workbook(folder, "a.xlsx")
    registry, clock = make_registry(folder)
    session = None

    for client_id, name in clients:
        session = registry.open("a.xlsx", client_id, name)

    return registry, clock, session


def connected(registry, hub, session, client_id=ALICE, name="Alice", since=0):
    conn = FakeConnection(client_id, name)
    params = parse_connect(session.id, client_id, name, str(since))
    assert live.connect(registry, hub, params, conn) is session
    return conn


def ops_text(session, value, batch_id="b1"):
    data = session.controller.grid_data()
    cell = {"op": "set_cells", "cells": [{"row": data.row_ids[0], "column": data.column_ids[0], "value": value}]}
    payload = {
        "client_batch_id": batch_id,
        "base_revision": 0,
        "sheet_id": session.controller.current_sheet_id(),
        "ops": [cell],
    }
    return json.dumps({"type": "ops", "payload": payload})


def refused(call, *args):
    try:
        call(*args)
    except ConnectError as error:
        return error
    raise AssertionError("expected a ConnectError")


# ----------------------------------------------------------------------
# parse_connect
# ----------------------------------------------------------------------


def test_valid_parameters_are_accepted():
    params = parse_connect("abc123", ALICE, "Alice", "12")

    assert (params.document, params.client_id, params.name, params.since) == ("abc123", ALICE, "Alice", 12)


def test_name_and_revision_are_optional():
    params = parse_connect("abc123", ALICE, None, None)

    assert params.name == "Guest" and params.since == 0


def test_an_arabic_name_is_fine_and_stray_whitespace_and_control_characters_are_cleaned():
    assert parse_connect("d", ALICE, "  سلمى   أحمد ", "0").name == "سلمى أحمد"
    assert parse_connect("d", ALICE, "Al\nice\t\x00", "0").name == "Alice"


def test_a_name_of_exactly_40_characters_is_the_longest_allowed():
    assert parse_connect("d", ALICE, "x" * 40, "0").name == "x" * 40
    assert refused(parse_connect, "d", ALICE, "x" * 41, "0").code == "BAD_REQUEST"


def test_an_empty_or_blank_name_is_refused():
    for bad in ("", "   ", "\n\t", "\x00"):
        assert refused(parse_connect, "d", ALICE, bad, "0").code == "BAD_REQUEST"


def test_a_missing_or_blank_document_is_refused():
    for bad in (None, "", "   ", 5):
        assert refused(parse_connect, bad, ALICE, "A", "0").code == "BAD_REQUEST"


def test_a_missing_or_invalid_client_id_is_refused():
    for bad in (None, "", "short", "has spaces in it!", "x" * 65, 12345678):
        assert refused(parse_connect, "d", bad, "A", "0").code == "BAD_REQUEST"


def test_the_revision_must_be_a_whole_number_of_at_least_zero():
    for bad in ("-1", "abc", "1.5", "1e3", " 3", "", "9" * 13, 5):
        assert refused(parse_connect, "d", ALICE, "A", bad).code == "BAD_REQUEST"

    assert parse_connect("d", ALICE, "A", "007").since == 7
    assert parse_connect("d", ALICE, "A", "0").since == 0


# ----------------------------------------------------------------------
# connect / disconnect
# ----------------------------------------------------------------------


def test_connecting_joins_the_room_with_a_catch_up_and_presence():
    with tempfile.TemporaryDirectory() as folder:
        registry, _, session = open_document(folder)
        hub = Hub()

        conn = connected(registry, hub, session)

        assert conn.types() == ["catch_up", "presence"]
        assert hub.presence(session) == [{"id": ALICE, "name": "Alice"}]


def test_a_document_that_is_not_open_is_refused():
    with tempfile.TemporaryDirectory() as folder:
        registry, _, _ = open_document(folder)
        params = parse_connect("0123456789abcdef", ALICE, "Alice", "0")

        error = refused(live.connect, registry, Hub(), params, FakeConnection(ALICE))

        assert error.code == "SESSION_NOT_OPEN"


def test_connecting_also_registers_a_client_the_registry_did_not_know():
    with tempfile.TemporaryDirectory() as folder:
        registry, _, session = open_document(folder)

        connected(registry, Hub(), session, client_id=BOB, name="Bob")

        assert set(session.clients) == {ALICE, BOB}


def test_disconnecting_updates_presence_but_keeps_the_session_open_for_a_quick_return():
    with tempfile.TemporaryDirectory() as folder:
        registry, _, session = open_document(folder, clients=((ALICE, "Alice"), (BOB, "Bob")))
        hub = Hub()
        alice = connected(registry, hub, session)
        bob = connected(registry, hub, session, BOB, "Bob")

        live.disconnect(hub, session, alice)

        assert hub.presence(session) == [{"id": BOB, "name": "Bob"}]
        assert bob.of_type("presence")[-1]["clients"] == [{"id": BOB, "name": "Bob"}]
        assert ALICE in session.clients                      # still known to the registry

        live.disconnect(hub, session, bob)
        assert registry.is_open_in_session("a.xlsx")         # nobody connected, document still open


# ----------------------------------------------------------------------
# handle_text
# ----------------------------------------------------------------------


def test_a_ping_is_answered_with_a_pong():
    with tempfile.TemporaryDirectory() as folder:
        registry, _, session = open_document(folder)
        hub = Hub()
        conn = connected(registry, hub, session)

        outcome = handle_text(registry, hub, session, conn, session.id, '{"type": "ping"}')

        assert outcome == CONTINUE and conn.messages[-1] == {"type": "pong"}


def test_pings_keep_the_client_in_the_session_past_the_idle_limit():
    with tempfile.TemporaryDirectory() as folder:
        registry, clock, session = open_document(folder)
        hub = Hub()
        conn = connected(registry, hub, session)

        for _ in range(5):                      # 5 x 100 s, with a 120 s limit
            clock.advance(100)
            assert handle_text(registry, hub, session, conn, session.id, '{"type": "ping"}') == CONTINUE

        assert ALICE in session.clients
        assert registry.is_open_in_session("a.xlsx")


def test_ops_over_a_connection_change_the_document_and_reach_everyone():
    with tempfile.TemporaryDirectory() as folder:
        registry, _, session = open_document(folder, clients=((ALICE, "Alice"), (BOB, "Bob")))
        hub = Hub()
        alice = connected(registry, hub, session)
        bob = connected(registry, hub, session, BOB, "Bob")

        outcome = handle_text(registry, hub, session, alice, session.id, ops_text(session, "Zed"))

        assert outcome == CONTINUE
        assert next(iter(session.controller.grid_data().rows[0].values())) == "Zed"
        assert alice.types()[-2:] == ["batch", "result"] and alice.of_type("result")[0]["accepted"] is True
        assert bob.types()[-1] == "batch"


def test_a_message_that_is_not_json_is_answered_with_an_error_and_the_connection_goes_on():
    with tempfile.TemporaryDirectory() as folder:
        registry, _, session = open_document(folder)
        hub = Hub()
        conn = connected(registry, hub, session)

        for text in ("not json", "[1, 2]", "5", "null", '"ops"', "[" * 100000):
            assert handle_text(registry, hub, session, conn, session.id, text) == CONTINUE
            assert conn.messages[-1]["type"] == "error" and conn.messages[-1]["code"] == "BAD_REQUEST"

        assert session.oplog.revision == 0


def test_an_unknown_message_type_is_answered_with_an_error():
    with tempfile.TemporaryDirectory() as folder:
        registry, _, session = open_document(folder)
        hub = Hub()
        conn = connected(registry, hub, session)

        for text in ('{"type": "delete_everything"}', '{"no_type": 1}', '{"type": 5}'):
            handle_text(registry, hub, session, conn, session.id, text)
            assert conn.messages[-1]["code"] == "BAD_REQUEST"


def test_a_message_that_is_too_large_is_refused_without_being_read():
    with tempfile.TemporaryDirectory() as folder:
        registry, _, session = open_document(folder)
        hub = Hub()
        conn = connected(registry, hub, session)

        handle_text(registry, hub, session, conn, session.id, " " * (live.MAX_MESSAGE_CHARS + 1))

        assert conn.messages[-1]["code"] == "MESSAGE_TOO_LARGE"


def test_ops_without_a_payload_are_refused_by_the_normal_rules():
    with tempfile.TemporaryDirectory() as folder:
        registry, _, session = open_document(folder)
        hub = Hub()
        conn = connected(registry, hub, session)

        handle_text(registry, hub, session, conn, session.id, '{"type": "ops"}')

        answer = conn.messages[-1]
        assert answer["type"] == "result" and answer["accepted"] is False and session.oplog.revision == 0


def test_a_session_that_expired_and_was_reopened_makes_the_old_connection_hang_up():
    with tempfile.TemporaryDirectory() as folder:
        registry, clock, session = open_document(folder)
        hub = Hub()
        conn = connected(registry, hub, session)

        clock.advance(500)                     # no pings: the client expires, the document is released

        outcome = handle_text(registry, hub, session, conn, session.id, ops_text(session, "late"))

        assert outcome == HANG_UP
        assert conn.messages[-1]["code"] == "SESSION_REPLACED"
        assert session.oplog.revision == 0     # nothing was applied to the old, closed document


def test_a_session_the_server_has_forgotten_makes_the_connection_hang_up():
    with tempfile.TemporaryDirectory() as folder:
        registry, _, session = open_document(folder)
        hub = Hub()
        conn = connected(registry, hub, session)
        restarted = SessionRegistry(lambda: registry.default.controller)       # knows no sessions

        outcome = handle_text(restarted, hub, session, conn, session.id, '{"type": "ping"}')

        assert outcome == HANG_UP and conn.messages[-1]["code"] == "SESSION_NOT_OPEN"


def test_an_unexpected_failure_is_reported_and_the_connection_goes_on():
    class BrokenHub(Hub):
        def submit(self, session, conn, payload):
            raise RuntimeError("bug")

    with tempfile.TemporaryDirectory() as folder:
        registry, _, session = open_document(folder)
        hub = BrokenHub()
        conn = connected(registry, hub, session)

        outcome = handle_text(registry, hub, session, conn, session.id, ops_text(session, "x"))

        assert outcome == CONTINUE and conn.messages[-1]["code"] == "INTERNAL_ERROR"
        assert handle_text(registry, hub, session, conn, session.id, '{"type": "ping"}') == CONTINUE
