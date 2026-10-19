"""Tests for stable row and column IDs on the Sheet model (phase 4a).

Plain functions like the other tests. These build a Sheet directly (no
workbook, no storage), so they check the ID rules on their own; the
document-level behaviour (open, save, undo through the Document) is in
test_row_column_ids_document.py.
"""

import random

import pandas as pd

from backend.models.sheet import Sheet


def make_sheet(rows=None, columns=("Name", "Score")) -> Sheet:
    rows = [["Alice", 90], ["Bob", 85], ["Charlie", 95]] if rows is None else rows
    return Sheet(name="S", dataframe=pd.DataFrame(rows, columns=list(columns)))


def ids_by_name(sheet: Sheet) -> dict:
    """Row ID -> the value in the first column (a way to tell rows apart)."""
    first = sheet.dataframe.columns[0]
    return dict(zip(sheet.row_ids, sheet.dataframe[first]))


# ----------------------------------------------------------------------
# Assignment and the data payload
# ----------------------------------------------------------------------

def test_every_row_and_column_gets_a_unique_id():
    sheet = make_sheet()
    data = sheet.data()

    assert len(data.row_ids) == 3 and len(set(data.row_ids)) == 3
    assert len(data.column_ids) == 2 and len(set(data.column_ids)) == 2
    assert all(data.row_ids) and all(data.column_ids)


def test_payload_ids_are_parallel_to_rows_and_headers():
    sheet = make_sheet()
    data = sheet.data()

    assert len(data.row_ids) == len(data.rows)
    assert len(data.column_ids) == len(data.headers)
    assert sheet.column_name(data.column_ids[1]) == "Score"
    assert sheet.row_position(data.row_ids[2]) == 2


def test_ids_stay_the_same_between_reads():
    sheet = make_sheet()
    first = (sheet.data().row_ids, sheet.data().column_ids)
    second = (sheet.data().row_ids, sheet.data().column_ids)
    assert first == second


def test_empty_sheet_has_no_row_ids_but_keeps_column_ids():
    sheet = make_sheet(rows=[])
    data = sheet.data()

    assert data.row_ids == []
    assert len(data.column_ids) == 2


def test_sheet_without_columns_has_no_ids():
    sheet = Sheet(name="S", dataframe=pd.DataFrame())
    data = sheet.data()

    assert data.row_ids == [] and data.column_ids == []


# ----------------------------------------------------------------------
# Rows
# ----------------------------------------------------------------------

def test_row_ids_do_not_change_when_a_row_is_inserted_above():
    sheet = make_sheet()
    before = ids_by_name(sheet)

    assert sheet.insert_row(0) is True

    after = ids_by_name(sheet)
    new_ids = set(after) - set(before)

    assert len(new_ids) == 1
    assert sheet.row_ids[0] in new_ids            # the new row is on top
    for row_id, name in before.items():           # every old row kept its ID
        assert after[row_id] == name
        assert sheet.row_position(row_id) == list(sheet.dataframe["Name"]).index(name)


def test_append_row_gets_a_new_id_at_the_end():
    sheet = make_sheet()
    old = list(sheet.row_ids) or sheet.data().row_ids

    assert sheet.append_row("Dana") is True

    assert sheet.row_ids[:3] == old
    assert sheet.row_ids[3] not in old
    assert sheet.dataframe.iloc[3, 0] == "Dana"


def test_deleting_a_row_removes_only_its_id():
    sheet = make_sheet()
    before = ids_by_name(sheet)
    victim = [row_id for row_id, name in before.items() if name == "Bob"][0]

    assert sheet.delete_row(1) is True

    after = ids_by_name(sheet)
    assert victim not in after
    assert after == {row_id: name for row_id, name in before.items() if row_id != victim}
    assert sheet.row_position(victim) is None


def test_a_deleted_rows_id_is_never_given_to_a_new_row():
    sheet = make_sheet()
    seen = set(sheet.data().row_ids)

    for _ in range(5):
        sheet.delete_row(0)
        sheet.insert_row(0)
        new_id = sheet.row_ids[0]
        assert new_id not in seen
        seen.add(new_id)


def test_ids_follow_rows_in_a_sorted_view():
    sheet = make_sheet()
    names = ids_by_name(sheet)

    assert sheet.sort([{"column": "Score", "ascending": True}]) is True
    data = sheet.data()

    # Bob 85, Alice 90, Charlie 95
    assert [row["Name"] for row in data.rows] == ["Bob", "Alice", "Charlie"]
    assert [names[row_id] for row_id in data.row_ids] == ["Bob", "Alice", "Charlie"]


def test_ids_follow_rows_in_a_filtered_view():
    sheet = make_sheet()
    names = ids_by_name(sheet)

    sheet.active_view = sheet.dataframe[sheet.dataframe["Score"] >= 90]
    data = sheet.data()

    assert [row["Name"] for row in data.rows] == ["Alice", "Charlie"]
    assert [names[row_id] for row_id in data.row_ids] == ["Alice", "Charlie"]


def test_insert_row_under_a_sort_still_tracks_ids():
    sheet = make_sheet()
    names = ids_by_name(sheet)
    sheet.sort([{"column": "Score", "ascending": False}])   # Charlie, Alice, Bob

    assert sheet.insert_row(1) is True                       # above Alice, in the view
    sheet.clear_view()

    after = ids_by_name(sheet)
    for row_id, name in names.items():
        assert after[row_id] == name


# ----------------------------------------------------------------------
# Columns
# ----------------------------------------------------------------------

def test_a_renamed_column_keeps_its_id():
    sheet = make_sheet()
    score_id = sheet.column_id("Score")

    assert sheet.rename_column("Score", "Points") is True

    assert sheet.column_id("Points") == score_id
    assert sheet.column_name(score_id) == "Points"
    assert sheet.column_id("Score") is None
    assert sheet.data().column_ids == [sheet.column_id("Name"), score_id]


def test_column_ids_do_not_change_when_a_column_is_inserted_before():
    sheet = make_sheet()
    name_id, score_id = sheet.column_id("Name"), sheet.column_id("Score")

    assert sheet.insert_column("Age", 0) is True

    assert sheet.column_id("Name") == name_id
    assert sheet.column_id("Score") == score_id
    assert sheet.column_id("Age") not in (name_id, score_id)
    assert sheet.data().column_ids[0] == sheet.column_id("Age")


def test_a_deleted_columns_id_is_never_given_to_a_new_column():
    sheet = make_sheet()
    score_id = sheet.column_id("Score")

    assert sheet.delete_column("Score") is True
    assert sheet.column_name(score_id) is None

    assert sheet.insert_column("Score") is True           # same name, new column
    assert sheet.column_id("Score") != score_id


def test_a_failed_column_edit_changes_no_ids():
    sheet = make_sheet()
    before = (list(sheet.data().row_ids), dict(sheet.column_ids))

    assert sheet.insert_column("Name") is False           # duplicate name
    assert sheet.rename_column("Nope", "X") is False
    assert sheet.delete_column("Nope") is False
    assert sheet.delete_row(99) is False

    assert (list(sheet.row_ids), dict(sheet.column_ids)) == before


# ----------------------------------------------------------------------
# Undo / redo snapshots
# ----------------------------------------------------------------------

def test_restoring_a_snapshot_brings_back_the_same_ids():
    sheet = make_sheet()
    before = ids_by_name(sheet)
    columns_before = dict(sheet.column_ids)
    snapshot = sheet.snapshot()

    sheet.delete_row(0)
    sheet.delete_column("Score")
    sheet.restore(snapshot)

    assert ids_by_name(sheet) == before
    assert sheet.column_ids == columns_before


def test_undo_cannot_rewind_the_id_counters():
    sheet = make_sheet()
    sheet.data()
    snapshot = sheet.snapshot()
    ever_used = set(sheet.row_ids)

    sheet.insert_row(0)
    ever_used.add(sheet.row_ids[0])
    sheet.restore(snapshot)                     # the inserted row is gone again

    sheet.insert_row(0)                         # a different new row
    assert sheet.row_ids[0] not in ever_used


def test_snapshot_is_independent_of_later_edits():
    sheet = make_sheet()
    snapshot = sheet.snapshot()
    saved = list(snapshot.row_ids)

    sheet.insert_row(0)
    sheet.delete_row(1)

    assert snapshot.row_ids == saved


# ----------------------------------------------------------------------
# Repair, lookups
# ----------------------------------------------------------------------

def test_ids_are_reassigned_when_the_shape_changes_from_outside():
    sheet = make_sheet()
    old = set(sheet.data().row_ids)

    sheet.set_dataframe(pd.DataFrame([["x", 1], ["y", 2], ["z", 3], ["w", 4]], columns=["Name", "Score"]))
    data = sheet.data()

    assert len(data.row_ids) == 4 and len(set(data.row_ids)) == 4
    assert not (set(data.row_ids) & old)        # nothing from before is reused


def test_same_shape_replacement_keeps_ids():
    sheet = make_sheet()
    before = list(sheet.data().row_ids)

    sheet.set_dataframe(sheet.dataframe.copy())

    assert sheet.data().row_ids == before


def test_lookups_reject_unknown_and_invalid_input():
    sheet = make_sheet()
    sheet.data()

    assert sheet.row_position("r999") is None
    assert sheet.row_position("") is None
    assert sheet.column_name("c999") is None
    assert sheet.column_id("Nope") is None
    assert sheet.row_id_at(-1) is None
    assert sheet.row_id_at(3) is None
    assert sheet.row_id_at(True) is None
    assert sheet.row_id_at(0) == sheet.row_ids[0]


# ----------------------------------------------------------------------
# Randomised check against an independent model
# ----------------------------------------------------------------------

def test_ids_stay_attached_to_their_rows_through_random_edits():
    """After any mix of inserts, appends, deletes and undo-style restores, the
    row with a given ID still holds the content it was given.

    The model is a plain list of (id, label) pairs built independently of
    Sheet; labels are written into the first column so a row can be told apart.
    """
    rng = random.Random(4096)
    sheet = make_sheet(rows=[[f"seed{i}", i] for i in range(5)])
    sheet.data()
    model = list(zip(sheet.row_ids, [f"seed{i}" for i in range(5)]))
    snapshots = []

    for step in range(300):
        action = rng.choice(["insert", "append", "delete", "snapshot", "restore"])

        if action == "insert":
            index = rng.randint(0, len(model))
            before = set(sheet.row_ids)
            assert sheet.insert_row(index) is True
            new_id = (set(sheet.row_ids) - before).pop()
            label = f"n{step}"
            sheet.dataframe.iloc[index, 0] = label
            model.insert(index, (new_id, label))

        elif action == "append":
            before = set(sheet.row_ids)
            assert sheet.append_row(f"a{step}") is True
            new_id = (set(sheet.row_ids) - before).pop()
            model.append((new_id, f"a{step}"))

        elif action == "delete" and model:
            index = rng.randrange(len(model))
            assert sheet.delete_row(index) is True
            del model[index]

        elif action == "snapshot":
            snapshots.append((sheet.snapshot(), list(model)))

        elif action == "restore" and snapshots:
            snapshot, saved = snapshots.pop(rng.randrange(len(snapshots)))
            sheet.restore(snapshot)
            model = list(saved)

        assert sheet.row_ids == [row_id for row_id, _ in model]
        assert list(sheet.dataframe.iloc[:, 0]) == [label for _, label in model]
        assert len(set(sheet.row_ids)) == len(sheet.row_ids)


def test_the_sheet_id_travels_in_the_data_payload():
    sheet = make_sheet()
    sheet.sheet_id = "s7"

    assert sheet.data().sheet_id == "s7"
    assert make_sheet().data().sheet_id == ""        # not assigned until a Document does it
