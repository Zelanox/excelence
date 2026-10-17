"""Document-level tests for stable row and column IDs (phase 4a).

These go through the Controller and a real workbook, like
test_history_and_edits.py, to check that the IDs survive the whole path:
open, structural edits, sort, undo/redo, switching sheets, save and reopen.
The Sheet-level rules are in test_row_column_ids.py.
"""

import tempfile

from backend.tests.test_text_styles import make_controller, reopen


def names_by_id(controller) -> dict:
    """Row ID -> the Name shown in that row, from the grid payload."""
    data = controller.grid_data()
    return {row_id: row["Name"] for row_id, row in zip(data.row_ids, data.rows)}


def test_a_freshly_opened_document_has_unique_ids():
    with tempfile.TemporaryDirectory() as folder:
        c = make_controller(folder)
        data = c.grid_data()

        assert len(data.row_ids) == len(data.rows) == 4
        assert len(set(data.row_ids)) == 4
        assert len(data.column_ids) == len(data.headers) == 3
        assert len(set(data.column_ids)) == 3


def test_ids_follow_rows_through_insert_delete_and_sort():
    with tempfile.TemporaryDirectory() as folder:
        c = make_controller(folder)
        before = names_by_id(c)

        assert c.insert_row(0) is True
        assert c.delete_row(2) is True          # the old row 1 ("Bob") is now at 2

        after = names_by_id(c)
        bob_id = [row_id for row_id, name in before.items() if name == "Bob"][0]

        assert bob_id not in after
        for row_id, name in after.items():
            if name:                            # skip the new blank row
                assert before[row_id] == name

        assert c.sort([{"column": "Score", "ascending": False}]) is True
        assert names_by_id(c) == after         # sorting reorders rows, never re-IDs them


def test_undo_and_redo_bring_back_the_same_ids():
    with tempfile.TemporaryDirectory() as folder:
        c = make_controller(folder)
        before = c.grid_data().row_ids

        assert c.delete_row(1) is True
        assert c.grid_data().row_ids != before

        assert c.undo() is True
        assert c.grid_data().row_ids == before

        assert c.redo() is True
        assert c.grid_data().row_ids == [row_id for index, row_id in enumerate(before) if index != 1]


def test_a_renamed_column_keeps_its_id_and_a_new_column_gets_a_new_one():
    with tempfile.TemporaryDirectory() as folder:
        c = make_controller(folder)
        before = dict(zip(c.grid_data().headers, c.grid_data().column_ids))

        assert c.rename_column("Score", "Points") is True
        assert c.insert_column("Age2", 0) is True

        after = dict(zip(c.grid_data().headers, c.grid_data().column_ids))

        assert after["Points"] == before["Score"]
        assert after["Name"] == before["Name"]
        assert after["Age2"] not in before.values()


def test_ids_do_not_change_when_switching_sheets_and_back():
    with tempfile.TemporaryDirectory() as folder:
        c = make_controller(folder)
        rows = c.grid_data().row_ids
        columns = c.grid_data().column_ids

        assert c.add_sheet("Other") is True
        assert c.set_sheet("Sheet1") is True

        assert c.grid_data().row_ids == rows
        assert c.grid_data().column_ids == columns


def test_ids_are_reassigned_when_the_document_is_reopened():
    with tempfile.TemporaryDirectory() as folder:
        c = make_controller(folder)
        assert c.delete_row(0) is True           # so the saved file has fewer rows than IDs ever issued

        fresh = reopen(c, folder)
        data = fresh.grid_data()

        # Reassigned on load (a decided behavior): still complete and unique.
        assert len(data.row_ids) == len(data.rows) == 3
        assert len(set(data.row_ids)) == 3
        assert len(data.column_ids) == len(set(data.column_ids)) == 3
