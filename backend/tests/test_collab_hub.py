"""Tests for live connections (backend/collab/hub.py).

The hub is tested with fake connections and a fake session; only the tests of
``submit`` use a real document. No web framework is involved.
"""

import asyncio
import tempfile
import threading

from backend.collab import service
from backend.collab.hub import (
    RESYNC_AHEAD,
    RESYNC_BEHIND,
    RESYNC_CHANGED,
    Hub,
    QueueConnection,
    entry_message,
)
from backend.collab.op_log import KIND_OPS, KIND_RESYNC, OpLog
from backend.tests.test_collab_service import first_cell, make_session, payload

ALICE = "client-alice-0001"
BOB = "client-bob-00002"
CARA = "client-cara-0003"


class FakeConnection:
    def __init__(self, client_id, name="Someone"):
        self.client_id = client_id
        self.name = name
        self.messages = []
        self.close_reason = None

    @property
    def closed(self):
        return self.close_reason is not None

    def deliver(self, message):
        self.messages.append(message)

    def close(self, reason):
        self.close_reason = reason

    def types(self):
        return [m["type"] for m in self.messages]

    def of_type(self, kind):
        return [m for m in self.messages if m["type"] == kind]


class FakeSession:
    """Only what the hub needs: a log (and an identity, so it can be a dict key)."""

    def __init__(self):
        self.oplog = OpLog()


def ops_entry(log, batch="b", client=ALICE):
    return log.append(KIND_OPS, client_id=client, client_batch_id=batch, ops=[{"op": "set_rtl", "value": True}])


def joined(hub, session, client_id, name="Someone", since=0):
    conn = FakeConnection(client_id, name)
    assert hub.join(session, conn, since) is True
    return conn


# ----------------------------------------------------------------------
# Joining: catch-up first, then live
# ----------------------------------------------------------------------


def test_a_new_connection_first_gets_the_catch_up_then_the_presence_list():
    hub, session = Hub(), FakeSession()

    conn = joined(hub, session, ALICE, "Alice")

    assert conn.types() == ["catch_up", "presence"]
    assert conn.messages[0] == {"type": "catch_up", "revision": 0, "batches": []}
    assert conn.messages[1]["clients"] == [{"id": ALICE, "name": "Alice"}]


def test_the_catch_up_holds_exactly_what_the_client_missed():
    hub, session = Hub(), FakeSession()
    for number in range(1, 4):
        ops_entry(session.oplog, batch=f"b{number}")

    conn = joined(hub, session, BOB, since=1)

    catch_up = conn.messages[0]
    assert catch_up["revision"] == 3
    assert [b["revision"] for b in catch_up["batches"]] == [2, 3]


def test_a_change_made_before_joining_is_not_also_sent_as_live():
    hub, session = Hub(), FakeSession()
    ops_entry(session.oplog)

    conn = joined(hub, session, BOB, since=0)
    ops_entry(session.oplog, batch="later")

    live = conn.of_type("batch")
    assert [b["batch"]["revision"] for b in live] == [2]
    assert [b["revision"] for b in conn.messages[0]["batches"]] == [1]


def test_a_client_too_far_behind_is_told_to_reload():
    hub, session = Hub(), FakeSession()
    ops_entry(session.oplog)
    ops_entry(session.oplog, batch="b2")
    session.oplog.reset()

    conn = joined(hub, session, BOB, since=0)

    assert conn.messages[0] == {"type": "resync", "revision": 2, "reason": RESYNC_BEHIND}


def test_a_client_ahead_of_the_server_is_told_to_reload_and_still_joins():
    hub, session = Hub(), FakeSession()
    ops_entry(session.oplog)

    conn = joined(hub, session, BOB, since=50)

    assert conn.messages[0] == {"type": "resync", "revision": 1, "reason": RESYNC_AHEAD}
    assert hub.presence(session) == [{"id": BOB, "name": "Someone"}]


def test_an_invalid_revision_is_an_error_and_nothing_is_registered():
    hub, session = Hub(), FakeSession()
    conn = FakeConnection(ALICE)

    assert hub.join(session, conn, -1) is False

    assert conn.types() == ["error"] and conn.messages[0]["code"] == "BAD_REQUEST"
    assert not hub.has_room(session)
    assert hub.presence(session) == []

    ops_entry(session.oplog)
    assert conn.types() == ["error"]                    # not subscribed either


# ----------------------------------------------------------------------
# Live messages
# ----------------------------------------------------------------------


def test_every_new_batch_reaches_everyone_including_the_sender():
    hub, session = Hub(), FakeSession()
    alice = joined(hub, session, ALICE)
    bob = joined(hub, session, BOB)

    entry = ops_entry(session.oplog, client=ALICE)

    for conn in (alice, bob):
        assert conn.of_type("batch") == [{"type": "batch", "batch": entry.to_dict()}]


def test_a_reload_entry_is_pushed_as_resync():
    hub, session = Hub(), FakeSession()
    alice = joined(hub, session, ALICE)

    entry = session.oplog.append(KIND_RESYNC)

    assert alice.of_type("resync") == [{"type": "resync", "revision": entry.revision, "reason": RESYNC_CHANGED}]


def test_replacing_the_document_gives_each_client_one_resync():
    hub, session = Hub(), FakeSession()
    alice = joined(hub, session, ALICE)

    # What collab.service.restart_log does: forget the log, then log a resync.
    session.oplog.reset()
    session.oplog.append(KIND_RESYNC)

    assert len(alice.of_type("resync")) == 1


def test_different_sessions_do_not_hear_each_other():
    hub = Hub()
    one, two = FakeSession(), FakeSession()
    alice = joined(hub, one, ALICE)
    bob = joined(hub, two, BOB)

    ops_entry(one.oplog)

    assert len(alice.of_type("batch")) == 1
    assert bob.of_type("batch") == []


def test_one_broken_connection_does_not_stop_the_others():
    hub, session = Hub(), FakeSession()
    alice = joined(hub, session, ALICE)
    bob = joined(hub, session, BOB)

    def explode(message):
        raise RuntimeError("socket gone")

    alice.deliver = explode
    ops_entry(session.oplog)

    assert len(bob.of_type("batch")) == 1
    assert session.oplog.revision == 1


# ----------------------------------------------------------------------
# Presence
# ----------------------------------------------------------------------


def test_presence_lists_the_connected_clients_oldest_first_and_updates_on_every_change():
    hub, session = Hub(), FakeSession()
    alice = joined(hub, session, ALICE, "Alice")
    bob = joined(hub, session, BOB, "Bob")
    cara = joined(hub, session, CARA, "Cara")

    assert [c["name"] for c in cara.of_type("presence")[-1]["clients"]] == ["Alice", "Bob", "Cara"]

    hub.leave(session, bob)

    expected = [{"id": ALICE, "name": "Alice"}, {"id": CARA, "name": "Cara"}]
    assert alice.of_type("presence")[-1]["clients"] == expected
    assert cara.of_type("presence")[-1]["clients"] == expected
    assert hub.presence(session) == expected


def test_a_leaving_client_hears_nothing_more():
    hub, session = Hub(), FakeSession()
    alice = joined(hub, session, ALICE)
    bob = joined(hub, session, BOB)
    hub.leave(session, bob)
    heard = len(bob.messages)

    ops_entry(session.oplog)

    assert len(bob.messages) == heard
    assert len(alice.of_type("batch")) == 1


def test_the_last_one_leaving_closes_the_room_and_stops_listening_to_the_log():
    hub, session = Hub(), FakeSession()
    alice = joined(hub, session, ALICE)

    assert hub.leave(session, alice) is True

    assert not hub.has_room(session)
    assert session.oplog._subscribers == []
    heard = len(alice.messages)
    ops_entry(session.oplog)
    assert len(alice.messages) == heard


def test_leaving_twice_or_without_joining_changes_nothing():
    hub, session = Hub(), FakeSession()
    alice = joined(hub, session, ALICE)
    bob = joined(hub, session, BOB)

    assert hub.leave(session, bob) is True
    assert hub.leave(session, bob) is False
    assert hub.leave(session, FakeConnection(CARA)) is False
    assert hub.leave(FakeSession(), alice) is False
    assert hub.presence(session) == [{"id": ALICE, "name": "Someone"}]


def test_reconnecting_replaces_the_old_connection_of_the_same_client():
    hub, session = Hub(), FakeSession()
    old = joined(hub, session, ALICE, "Alice")
    bob = joined(hub, session, BOB, "Bob")

    new = joined(hub, session, ALICE, "Alice")

    assert old.close_reason == "replaced"
    assert [c["id"] for c in hub.presence(session)] == [ALICE, BOB]      # one Alice, still first
    assert [c["id"] for c in bob.of_type("presence")[-1]["clients"]] == [ALICE, BOB]

    # The old connection's own clean-up arrives late and must not remove the new one.
    assert hub.leave(session, old) is False
    assert [c["id"] for c in hub.presence(session)] == [ALICE, BOB]

    heard_old = len(old.messages)
    ops_entry(session.oplog)
    assert len(old.messages) == heard_old
    assert len(new.of_type("batch")) == 1


def test_a_replaced_clients_catch_up_starts_from_what_the_new_connection_has_seen():
    hub, session = Hub(), FakeSession()
    joined(hub, session, ALICE)
    ops_entry(session.oplog)
    ops_entry(session.oplog, batch="b2")

    new = joined(hub, session, ALICE, since=1)

    assert [b["revision"] for b in new.messages[0]["batches"]] == [2]


# ----------------------------------------------------------------------
# Submitting over a connection (real document)
# ----------------------------------------------------------------------


def test_the_sender_gets_its_batch_back_and_then_a_result_and_others_only_the_batch():
    with tempfile.TemporaryDirectory() as folder:
        hub, session = Hub(), make_session(folder)
        alice = joined(hub, session, ALICE)
        bob = joined(hub, session, BOB)

        result = hub.submit(session, alice, payload(session, first_cell(session, "Hello"), batch_id="b1"))

        assert result["accepted"] is True and result["revision"] == 1
        assert alice.types()[-2:] == ["batch", "result"]
        assert bob.types()[-1] == "batch" and "result" not in bob.types()

        answer = alice.of_type("result")[0]
        assert answer["client_batch_id"] == "b1"
        assert answer["accepted"] is True and answer["duplicate"] is False and answer["dropped"] == []
        assert bob.of_type("batch")[0]["batch"]["revision"] == 1
        assert bob.of_type("batch")[0]["batch"]["client_id"] == ALICE


def test_a_refused_batch_is_answered_to_the_sender_only_and_is_not_broadcast():
    with tempfile.TemporaryDirectory() as folder:
        hub, session = Hub(), make_session(folder)
        alice = joined(hub, session, ALICE)
        bob = joined(hub, session, BOB)

        bad = payload(session, {"op": "no_such_operation"}, batch_id="oops")
        result = hub.submit(session, alice, bad)

        assert result["accepted"] is False
        answer = alice.of_type("result")[0]
        assert answer["accepted"] is False and answer["client_batch_id"] == "oops"
        assert alice.of_type("batch") == [] and bob.of_type("batch") == []
        assert session.oplog.revision == 0


def test_a_payload_that_is_not_even_an_object_is_refused_politely():
    with tempfile.TemporaryDirectory() as folder:
        hub, session = Hub(), make_session(folder)
        alice = joined(hub, session, ALICE)

        hub.submit(session, alice, ["not", "an", "object"])

        answer = alice.of_type("result")[0]
        assert answer["accepted"] is False and "client_batch_id" not in answer


def test_a_resent_batch_is_answered_as_duplicate_and_not_broadcast_again():
    with tempfile.TemporaryDirectory() as folder:
        hub, session = Hub(), make_session(folder)
        alice = joined(hub, session, ALICE)
        bob = joined(hub, session, BOB)
        grow = payload(session, {"op": "insert_row", "before": None}, batch_id="grow")

        hub.submit(session, alice, grow)
        hub.submit(session, alice, grow)

        assert [r["duplicate"] for r in alice.of_type("result")] == [False, True]
        assert len(bob.of_type("batch")) == 1


def test_a_batch_sent_over_http_style_service_call_also_reaches_live_clients():
    with tempfile.TemporaryDirectory() as folder:
        hub, session = Hub(), make_session(folder)
        bob = joined(hub, session, BOB)

        service.submit(session, ALICE, payload(session, first_cell(session, "Hi"), batch_id="http1"))

        assert [m["batch"]["client_batch_id"] for m in bob.of_type("batch")] == ["http1"]


def test_a_change_through_an_old_route_reaches_live_clients_as_resync():
    with tempfile.TemporaryDirectory() as folder:
        hub, session = Hub(), make_session(folder)
        bob = joined(hub, session, BOB)

        session.controller.document.modified = True        # what any old editing route does
        assert service.account_for_untracked_changes(session) is True

        assert [m["reason"] for m in bob.of_type("resync")] == [RESYNC_CHANGED]


def test_restarting_the_log_after_a_reload_sends_each_client_one_resync():
    with tempfile.TemporaryDirectory() as folder:
        hub, session = Hub(), make_session(folder)
        bob = joined(hub, session, BOB)

        service.restart_log(session)

        assert len(bob.of_type("resync")) == 1


def test_entry_message_shapes():
    log = OpLog()
    ops = ops_entry(log)
    resync = log.append(KIND_RESYNC)

    assert entry_message(ops) == {"type": "batch", "batch": ops.to_dict()}
    assert entry_message(resync) == {"type": "resync", "revision": 2, "reason": RESYNC_CHANGED}


# ----------------------------------------------------------------------
# QueueConnection (asyncio; messages arrive from another thread)
# ----------------------------------------------------------------------


def run(scenario):
    return asyncio.run(scenario())


def test_messages_published_from_another_thread_arrive_in_order():
    async def scenario():
        conn = QueueConnection(ALICE, "Alice", asyncio.get_running_loop())

        def publish():
            for number in range(5):
                conn.deliver({"n": number})

        await asyncio.to_thread(publish)

        return [(await conn.next_message())["n"] for _ in range(5)]

    assert run(scenario) == [0, 1, 2, 3, 4]


def test_a_client_that_falls_too_far_behind_is_cut_off():
    async def scenario():
        conn = QueueConnection(ALICE, "Alice", asyncio.get_running_loop(), max_queue=3)

        def publish():
            for number in range(5):
                conn.deliver({"n": number})

        await asyncio.to_thread(publish)
        await asyncio.sleep(0.05)

        # Its backlog is dropped; the sender task just sees the end.
        return conn.close_reason, conn.closed, await conn.next_message(), await conn.next_message()

    assert run(scenario) == ("overflow", True, None, None)


def test_exactly_max_queue_messages_waiting_is_not_an_overflow():
    async def scenario():
        conn = QueueConnection(ALICE, "Alice", asyncio.get_running_loop(), max_queue=3)

        def publish():
            for number in range(3):
                conn.deliver({"n": number})

        await asyncio.to_thread(publish)
        await asyncio.sleep(0.05)

        return conn.close_reason, [(await conn.next_message())["n"] for _ in range(3)]

    assert run(scenario) == (None, [0, 1, 2])


def test_closing_ends_the_stream_and_later_messages_are_ignored():
    async def scenario():
        conn = QueueConnection(ALICE, "Alice", asyncio.get_running_loop())

        await asyncio.to_thread(conn.close, "replaced")
        await asyncio.sleep(0.01)
        conn.deliver({"n": 1})
        await asyncio.sleep(0.01)

        return conn.close_reason, await conn.next_message(), await conn.next_message()

    assert run(scenario) == ("replaced", None, None)


def test_the_first_close_reason_wins():
    async def scenario():
        conn = QueueConnection(ALICE, "Alice", asyncio.get_running_loop())
        conn.close("replaced")
        conn.close("overflow")
        await asyncio.sleep(0.01)
        return conn.close_reason

    assert run(scenario) == "replaced"


def test_delivering_after_the_event_loop_has_stopped_does_not_raise():
    loop = asyncio.new_event_loop()
    conn = QueueConnection(ALICE, "Alice", loop)
    loop.close()

    conn.deliver({"n": 1})
    conn.close("anything")

    assert conn.closed


def test_the_hub_publishes_to_a_queue_connection_from_a_worker_thread():
    async def scenario():
        hub, session = Hub(), FakeSession()
        conn = QueueConnection(ALICE, "Alice", asyncio.get_running_loop())

        def in_worker():
            hub.join(session, conn, 0)
            ops_entry(session.oplog)

        await asyncio.to_thread(in_worker)

        return [(await conn.next_message())["type"] for _ in range(3)]

    assert run(scenario) == ["catch_up", "presence", "batch"]


def test_publishing_never_waits_for_a_slow_client():
    async def scenario():
        hub, session = Hub(), FakeSession()
        slow = QueueConnection(ALICE, "Slow", asyncio.get_running_loop(), max_queue=2)
        fast = FakeConnection(BOB)

        def in_worker():
            hub.join(session, slow, 0)
            hub.join(session, fast, 0)

            for number in range(50):                    # the slow client never reads
                ops_entry(session.oplog, batch=f"b{number}")

        worker = threading.Thread(target=in_worker)
        worker.start()
        await asyncio.sleep(0.01)
        await asyncio.to_thread(worker.join, 5)         # would hang if publishing could block

        await asyncio.sleep(0.05)

        return slow.close_reason, len(fast.of_type("batch")), session.oplog.revision

    assert run(scenario) == ("overflow", 50, 50)
