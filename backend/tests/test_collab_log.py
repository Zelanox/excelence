"""Tests for the revision log (backend/collab/op_log.py). No document needed."""

from backend.collab.op_log import KIND_OPS, KIND_RESYNC, OpLog


class Clock:
    def __init__(self):
        self.now = 1000.0

    def __call__(self):
        return self.now


def add(log, n=1, client="client-aaaa", prefix="b"):
    return [log.append(KIND_OPS, client_id=client, client_batch_id=f"{prefix}{log.revision + 1}", ops=[{"op": "set_rtl", "value": True}]) for _ in range(n)]


def test_revisions_start_at_one_and_count_up_by_one():
    log = OpLog()
    assert log.revision == 0

    entries = add(log, 3)

    assert [e.revision for e in entries] == [1, 2, 3]
    assert log.revision == 3


def test_since_returns_only_later_entries_oldest_first():
    log = OpLog()
    add(log, 5)

    assert [e.revision for e in log.since(2)] == [3, 4, 5]
    assert log.since(5) == []
    assert [e.revision for e in log.since(0)] == [1, 2, 3, 4, 5]


def test_an_empty_log_has_nothing_since_zero():
    assert OpLog().since(0) == []


def test_a_resent_batch_is_found_again_but_not_under_another_client():
    log = OpLog()
    entry = log.append(KIND_OPS, client_id="client-aaaa", client_batch_id="same", ops=[{"op": "set_rtl", "value": True}])

    assert log.find_batch("client-aaaa", "same") is entry
    assert log.find_batch("client-bbbb", "same") is None
    assert log.find_batch("client-aaaa", "other") is None


def test_entries_are_kept_while_they_are_few_even_if_old():
    clock = Clock()
    log = OpLog(min_entries=5, min_age=60, clock=clock)
    add(log, 3)

    clock.now += 10_000

    add(log, 1)

    assert len(log.since(0)) == 4
    assert log.floor == 0


def test_entries_are_kept_while_they_are_young_even_if_many():
    clock = Clock()
    log = OpLog(min_entries=3, min_age=60, clock=clock)

    add(log, 10)

    assert len(log.since(0)) == 10


def test_old_entries_beyond_the_minimum_are_forgotten():
    clock = Clock()
    log = OpLog(min_entries=3, min_age=60, clock=clock)
    add(log, 6)

    clock.now += 61
    add(log, 1)                                   # trimming happens on append

    assert len(log._entries) == 3
    assert log.floor > 0
    assert log.since(log.floor - 1) is None       # too far behind: must reload
    assert [e.revision for e in log.since(log.floor)] == [e.revision for e in log._entries]


def test_a_forgotten_batch_id_can_no_longer_be_found():
    clock = Clock()
    log = OpLog(min_entries=1, min_age=60, clock=clock)
    log.append(KIND_OPS, client_id="client-aaaa", client_batch_id="first")
    clock.now += 61
    add(log, 2)

    assert log.find_batch("client-aaaa", "first") is None


def test_reset_makes_every_older_client_reload_but_keeps_counting():
    log = OpLog()
    add(log, 4)

    log.reset()

    assert log.revision == 4
    assert log.since(3) is None
    assert log.since(4) == []
    assert log.append(KIND_OPS).revision == 5
    assert log.find_batch("client-aaaa", "b1") is None


def test_the_entry_sent_to_clients_leaves_out_the_drop_notices():
    log = OpLog()
    entry = log.append(
        KIND_OPS,
        client_id="client-aaaa",
        client_batch_id="x",
        sheet_id="s1",
        ops=[{"op": "set_rtl", "value": True}],
        dropped=[{"index": 1, "reason": "ROW_DELETED"}],
    )

    sent = entry.to_dict()

    assert sent["ops"] == [{"op": "set_rtl", "value": True}]
    assert "dropped" not in sent
    assert sent["kind"] == KIND_OPS and sent["sheet_id"] == "s1" and sent["revision"] == 1


def test_a_resync_entry_is_recorded_like_any_other():
    log = OpLog()
    entry = log.append(KIND_RESYNC)

    assert entry.revision == 1 and entry.kind == KIND_RESYNC and entry.ops == ()
