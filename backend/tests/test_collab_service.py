"""Tests for submitting batches to a session and catching up
(backend/collab/service.py), including a check that replaying the log on a
second copy of the document gives exactly the same document.
"""

import random
import tempfile

from backend.collab import service
from backend.collab.operations import Batch, apply_batch
from backend.sessions import Session
from backend.tests.test_text_styles import make_controller

CLIENT = "client-aaaa"
OTHER = "client-bbbb"


def make_session(folder, name="t.xlsx"):
    controller = make_controller(folder, name=name)
    return Session(id="session", key=name, filename=name, controller=controller)


def payload(session, *ops, batch_id="b1", base=0):
    return {
        "client_batch_id": batch_id,
        "base_revision": base,
        "sheet_id": session.controller.current_sheet_id(),
        "ops": list(ops),
    }


def first_cell(session, value):
    data = session.controller.grid_data()
    return {"op": "set_cells", "cells": [{"row": data.row_ids[0], "column": data.column_ids[0], "value": value}]}


def names(session):
    return [row["Name"] for row in session.controller.grid_data().rows]


def test_each_accepted_batch_gets_the_next_revision():
    with tempfile.TemporaryDirectory() as folder:
        session = make_session(folder)

        one = service.submit(session, CLIENT, payload(session, first_cell(session, "A1"), batch_id="b1"))
        two = service.submit(session, OTHER, payload(session, first_cell(session, "A2"), batch_id="b2", base=1))

        assert (one["accepted"], one["revision"], one["duplicate"]) == (True, 1, False)
        assert (two["accepted"], two["revision"]) == (True, 2)
        assert names(session)[0] == "A2"


def test_a_resent_batch_is_not_applied_twice():
    with tempfile.TemporaryDirectory() as folder:
        session = make_session(folder)
        grow = payload(session, {"op": "insert_row", "before": None}, batch_id="grow")

        first = service.submit(session, CLIENT, grow)
        again = service.submit(session, CLIENT, grow)

        assert first["revision"] == again["revision"] == 1
        assert again["duplicate"] is True and again["applied"] == first["applied"]
        assert len(session.controller.grid_data().rows) == 5          # one new row, not two
        assert session.oplog.revision == 1


def test_the_same_batch_id_from_another_client_is_a_different_batch():
    with tempfile.TemporaryDirectory() as folder:
        session = make_session(folder)
        grow = payload(session, {"op": "insert_row", "before": None}, batch_id="same")

        service.submit(session, CLIENT, grow)
        other = service.submit(session, OTHER, grow)

        assert other["duplicate"] is False and other["revision"] == 2
        assert len(session.controller.grid_data().rows) == 6


def test_a_refused_batch_changes_nothing_and_uses_no_revision():
    with tempfile.TemporaryDirectory() as folder:
        session = make_session(folder)
        data = session.controller.grid_data()

        refused = service.submit(session, CLIENT, payload(
            session,
            first_cell(session, "changed"),
            {"op": "delete_row", "row": "r999"},
        ))

        assert refused["accepted"] is False and refused["code"] == "UNKNOWN_ROW"
        assert refused["index"] == 1 and refused["resync_required"] is False
        assert names(session)[0] == "Alice"
        assert session.oplog.revision == 0

        malformed = service.submit(session, CLIENT, {"ops": []})
        assert malformed["accepted"] is False and session.oplog.revision == 0
        assert session.controller.grid_data().row_ids == data.row_ids


def test_a_client_cannot_claim_to_have_seen_a_revision_that_does_not_exist():
    with tempfile.TemporaryDirectory() as folder:
        session = make_session(folder)

        result = service.submit(session, CLIENT, payload(session, first_cell(session, "x"), base=5))

        assert result["accepted"] is False and result["code"] == "REVISION_FROM_FUTURE"
        assert names(session)[0] == "Alice"


def test_a_missing_or_malformed_client_id_is_refused():
    with tempfile.TemporaryDirectory() as folder:
        session = make_session(folder)

        for client in ("", "short", "has space in it", None):
            result = service.submit(session, client, payload(session, first_cell(session, "x")))
            assert result["accepted"] is False and result["code"] == "BAD_REQUEST", client

        assert session.oplog.revision == 0


def test_a_batch_whose_changes_were_all_dropped_uses_no_revision():
    with tempfile.TemporaryDirectory() as folder:
        session = make_session(folder)
        edit = first_cell(session, "late")
        session.controller.delete_row(0)

        result = service.submit(session, CLIENT, payload(session, edit))

        assert result["accepted"] is True and result["applied"] == []
        assert result["dropped"][0]["reason"] == "ROW_DELETED"
        assert result["revision"] == 0 and session.oplog.revision == 0


def test_changes_since_lists_what_happened_after_a_revision():
    with tempfile.TemporaryDirectory() as folder:
        session = make_session(folder)
        service.submit(session, CLIENT, payload(session, first_cell(session, "one"), batch_id="b1"))
        service.submit(session, OTHER, payload(session, first_cell(session, "two"), batch_id="b2"))
        service.submit(session, CLIENT, payload(session, first_cell(session, "three"), batch_id="b3"))

        result = service.changes_since(session, 1)

        assert result["accepted"] is True and result["resync_required"] is False
        assert result["revision"] == 3
        assert [b["revision"] for b in result["batches"]] == [2, 3]
        assert result["batches"][0]["client_id"] == OTHER
        assert service.changes_since(session, 3)["batches"] == []


def test_changes_since_refuses_a_revision_from_the_future_or_nonsense():
    with tempfile.TemporaryDirectory() as folder:
        session = make_session(folder)

        assert service.changes_since(session, 1)["code"] == "REVISION_FROM_FUTURE"

        for bad in (-1, "1", None, True, 1.5):
            assert service.changes_since(session, bad)["code"] == "BAD_REQUEST", bad


def test_a_client_that_is_too_far_behind_is_told_to_reload():
    with tempfile.TemporaryDirectory() as folder:
        session = make_session(folder)
        service.submit(session, CLIENT, payload(session, first_cell(session, "one"), batch_id="b1"))
        service.submit(session, CLIENT, payload(session, first_cell(session, "two"), batch_id="b2"))

        session.oplog.reset()                      # e.g. the document was reloaded

        assert service.changes_since(session, 0)["resync_required"] is True
        assert service.changes_since(session, 1)["resync_required"] is True
        assert service.changes_since(session, 2) == {"accepted": True, "revision": 2, "resync_required": False, "batches": []}


def test_a_change_the_log_cannot_describe_makes_clients_reload_until_they_pass_it():
    with tempfile.TemporaryDirectory() as folder:
        session = make_session(folder)
        service.submit(session, CLIENT, payload(session, first_cell(session, "one"), batch_id="b1"))

        marker = service.mark_resync(session)
        service.submit(session, CLIENT, payload(session, first_cell(session, "two"), batch_id="b2", base=marker))

        assert service.changes_since(session, 0)["resync_required"] is True
        assert service.changes_since(session, 1)["resync_required"] is True
        later = service.changes_since(session, marker)
        assert later["resync_required"] is False and [b["revision"] for b in later["batches"]] == [marker + 1]


# ----------------------------------------------------------------------
# Convergence: replaying the log on a second copy gives the same document
# ----------------------------------------------------------------------

def strip_assigned_ids(ops):
    """The "id" the server gave to a new row/column/sheet is an answer, not an input."""
    return [{key: value for key, value in op.items() if key != "id"} for op in ops]


def replay(replica, entry):
    ops = strip_assigned_ids(entry["ops"])
    outcome = apply_batch(replica, Batch("replay", 0, entry["sheet_id"], ops))

    # the replica must hand out the same IDs the server did
    assert [op.get("id") for op in outcome.applied] == [op.get("id") for op in entry["ops"]]
    assert outcome.dropped == []


def random_batch(rng, session, stale_rows, stale_columns, counter):
    data = session.controller.grid_data()
    rows, columns = list(data.row_ids), list(data.column_ids)
    sheet_id = data.sheet_id
    ops = []

    for _ in range(rng.randint(1, 3)):
        kind = rng.choice(["cells", "cells", "insert_row", "delete_row", "insert_column",
                           "delete_column", "rename_column", "width", "rtl"])

        if kind == "cells":
            pool_rows = rows + rng.sample(stale_rows, min(1, len(stale_rows)))
            pool_columns = columns + rng.sample(stale_columns, min(1, len(stale_columns)))
            cells = [
                {"row": rng.choice(pool_rows), "column": rng.choice(pool_columns), "value": rng.choice(["x", "", "7", "2.5", None, "text"])}
                for _ in range(rng.randint(1, 4))
            ]
            ops.append({"op": "set_cells", "cells": cells})
        elif kind == "insert_row":
            ops.append({"op": "insert_row", "before": rng.choice(rows + [None])})
        elif kind == "delete_row" and len(rows) > 1:
            ops.append({"op": "delete_row", "row": rng.choice(rows)})
        elif kind == "insert_column":
            counter[0] += 1
            ops.append({"op": "insert_column", "name": f"Col{counter[0]}", "before": rng.choice(columns + [None])})
        elif kind == "delete_column" and len(columns) > 1:
            ops.append({"op": "delete_column", "column": rng.choice(columns)})
        elif kind == "rename_column":
            counter[0] += 1
            ops.append({"op": "rename_column", "column": rng.choice(columns), "name": f"Ren{counter[0]}"})
        elif kind == "width":
            ops.append({"op": "set_column_width", "column": rng.choice(columns), "width": rng.randint(5, 80)})
        elif kind == "rtl":
            ops.append({"op": "set_rtl", "value": rng.choice([True, False])})

    return {"client_batch_id": f"b{counter[0]}-{rng.random()}", "base_revision": session.oplog.revision, "sheet_id": sheet_id, "ops": ops} if ops else None


def test_replaying_the_log_on_a_second_copy_gives_the_same_document():
    rng = random.Random(2026)

    with tempfile.TemporaryDirectory() as server_folder, tempfile.TemporaryDirectory() as replica_folder:
        session = make_session(server_folder)
        replica = make_controller(replica_folder)
        stale_rows, stale_columns, counter = [], [], [0]
        accepted = 0

        for _ in range(250):
            before = session.controller.grid_data()
            payload_ = random_batch(rng, session, stale_rows, stale_columns, counter)

            if payload_ is None:
                continue

            result = service.submit(session, CLIENT, payload_)

            after = session.controller.grid_data()
            stale_rows += [r for r in before.row_ids if r not in after.row_ids]
            stale_columns += [c for c in before.column_ids if c not in after.column_ids]

            if result["accepted"] and result["applied"]:
                accepted += 1

        log = service.changes_since(session, 0)
        assert log["resync_required"] is False
        assert accepted > 100 and len(log["batches"]) == accepted

        for entry in log["batches"]:
            replay(replica.__class__ and replica, entry)

        mine, theirs = session.controller.grid_data(), replica.grid_data()

        assert theirs.headers == mine.headers
        assert theirs.rows == mine.rows
        assert theirs.row_ids == mine.row_ids
        assert theirs.column_ids == mine.column_ids
        assert theirs.column_widths == mine.column_widths
        assert theirs.rtl == mine.rtl


# ----------------------------------------------------------------------
# Changes that bypass the operation path
# ----------------------------------------------------------------------

def test_the_document_counts_changes_but_not_reads_or_view_changes():
    with tempfile.TemporaryDirectory() as folder:
        c = make_controller(folder)
        counted = c.document.change_count

        c.grid_data()
        c.search("a")
        c.clear_search()
        c.sort([{"column": "Score", "ascending": True}])
        c.clear_sort()
        assert c.add_sheet("Other") is True
        counted = c.document.change_count                      # adding a sheet is a change
        assert c.set_sheet("Sheet1") is True

        assert c.document.change_count == counted              # switching sheets is not

        for change in (
            lambda: c.edit_cell(0, 0, "x"),
            lambda: c.insert_row(0),
            lambda: c.delete_row(0),
            lambda: c.insert_column("New"),
            lambda: c.rename_column("New", "Newer"),
            lambda: c.set_column_width("Name", 20),
            lambda: c.set_rtl(True),
            lambda: c.undo(),
        ):
            before = c.document.change_count
            assert change() is True
            assert c.document.change_count > before


def test_a_change_made_outside_the_operation_path_becomes_a_resync_entry():
    with tempfile.TemporaryDirectory() as folder:
        session = make_session(folder)
        service.submit(session, CLIENT, payload(session, first_cell(session, "via ops"), batch_id="b1"))

        assert service.account_for_untracked_changes(session) is False      # nothing outside the path yet

        session.controller.edit_cell(1, 0, "via old route")                 # the old way

        assert service.account_for_untracked_changes(session) is True
        assert service.account_for_untracked_changes(session) is False      # only once

        assert session.oplog.revision == 2
        assert service.changes_since(session, 1)["resync_required"] is True
        assert service.changes_since(session, 2)["resync_required"] is False


def test_a_batch_through_the_operation_path_is_not_also_reported_as_untracked():
    with tempfile.TemporaryDirectory() as folder:
        session = make_session(folder)

        service.submit(session, CLIENT, payload(session, first_cell(session, "x"), {"op": "insert_row", "before": None}, batch_id="b1"))
        service.submit(session, CLIENT, payload(session, {"op": "set_rtl", "value": True}, batch_id="b2", base=1))

        assert service.account_for_untracked_changes(session) is False
        assert session.oplog.revision == 2


def test_a_refused_batch_leaves_nothing_unaccounted():
    with tempfile.TemporaryDirectory() as folder:
        session = make_session(folder)

        service.submit(session, CLIENT, payload(session, first_cell(session, "x"), {"op": "delete_row", "row": "r999"}))

        assert service.account_for_untracked_changes(session) is False
        assert session.oplog.revision == 0


def test_restarting_the_log_makes_even_an_up_to_date_client_reload():
    with tempfile.TemporaryDirectory() as folder:
        session = make_session(folder)
        service.submit(session, CLIENT, payload(session, first_cell(session, "one"), batch_id="b1"))
        service.submit(session, CLIENT, payload(session, first_cell(session, "two"), batch_id="b2", base=1))

        marker = service.restart_log(session)

        assert marker == 3
        assert service.changes_since(session, 0)["resync_required"] is True
        assert service.changes_since(session, 2)["resync_required"] is True      # was fully up to date
        assert service.changes_since(session, 3) == {"accepted": True, "revision": 3, "resync_required": False, "batches": []}


# ----------------------------------------------------------------------
# The revision a client's snapshot of the document matches
# ----------------------------------------------------------------------


def test_a_controller_outside_a_session_reports_revision_zero():
    with tempfile.TemporaryDirectory() as folder:
        assert make_controller(folder).revision() == 0


def test_the_controller_reports_the_revision_of_its_sessions_log():
    with tempfile.TemporaryDirectory() as folder:
        session = make_session(folder)
        assert session.controller.revision() == 0

        service.submit(session, CLIENT, payload(session, first_cell(session, "A1"), batch_id="b1"))
        service.submit(session, OTHER, payload(session, first_cell(session, "A2"), batch_id="b2", base=1))

        assert session.controller.revision() == 2 == session.revision()


def test_a_change_made_outside_the_log_is_counted_before_the_revision_is_read():
    from backend.collab.op_log import KIND_RESYNC

    with tempfile.TemporaryDirectory() as folder:
        session = make_session(folder)

        session.controller.edit_cell(0, 0, "old route")         # what an older route does

        assert session.controller.revision() == 1               # the "reload" entry is already in
        assert [entry.kind for entry in session.oplog.since(0)] == [KIND_RESYNC]
        assert session.controller.revision() == 1               # asking again adds nothing
