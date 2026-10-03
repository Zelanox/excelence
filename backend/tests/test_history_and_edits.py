"""Tests for view-aware batch edits, cell typing, and undo/redo.

Plain functions like the other tests. Each builds its own workbook in a
temp folder (see make_controller in test_text_styles).
"""

import os
import tempfile

import pandas as pd
from openpyxl import load_workbook

from backend.tests.test_text_styles import make_controller, reopen, styles


def sheet(controller):
    return controller.document.spreadsheet.current_sheet()


def column(controller, name):
    return list(sheet(controller).dataframe[name])


def grid(controller):
    """The visible grid as a list of rows of values (view order)."""
    return [list(row.values()) for row in controller.data()]


# ----------------------------------------------------------------------
# Edits: view mapping, batching, typing
# ----------------------------------------------------------------------

def test_edit_targets_the_right_row_under_sort():
    with tempfile.TemporaryDirectory() as folder:
        c = make_controller(folder)
        assert c.sort([{"column": "Score", "ascending": False}]) is True
        # view: Charlie 95, Alice 90, Bob 85, Dana 70
        assert c.cell_value(2, 0) == "Bob"

        assert c.edit_cell(2, 0, "Robert") is True
        assert column(c, "Name") == ["Alice", "Robert", "Charlie", "Dana"]
        # the sorted view is still in place and reflects the edit
        assert c.cell_value(2, 0) == "Robert"


def test_edit_targets_the_right_row_under_filter():
    with tempfile.TemporaryDirectory() as folder:
        c = make_controller(folder)
        assert c.search("Dana") is True
        assert c.filtered_row_count() == 1

        assert c.edit_cell(0, 2, "71") is True
        assert column(c, "Score") == [90, 85, 95, 71]


def test_edit_cells_is_atomic_and_validated():
    with tempfile.TemporaryDirectory() as folder:
        c = make_controller(folder)
        before = column(c, "Name")

        assert c.edit_cells([(0, 0, "X"), (99, 0, "Y")]) is False   # second is out of range
        assert c.edit_cells([(0, 0, "X"), (0, 9, "Y")]) is False    # bad column
        assert c.edit_cells([(0, 0, "X"), (-1, 0, "Y")]) is False
        assert c.edit_cells([(0, 0, "X"), ("1", 0, "Y")]) is False
        assert c.edit_cells([(0, 0)]) is False
        assert c.edit_cells([]) is False
        assert column(c, "Name") == before
        assert len(c.document.undo_stack) == 0      # failed batches record nothing


def test_numbers_typed_into_numeric_columns_stay_numbers():
    with tempfile.TemporaryDirectory() as folder:
        c = make_controller(folder)

        assert c.edit_cell(0, 1, "26") is True            # Age: int column
        assert sheet(c).dataframe["Age"].dtype.kind == "i"
        assert column(c, "Age")[0] == 26 and isinstance(column(c, "Age")[0], int)

        assert c.edit_cell(1, 1, "30.5") is True          # decimal into int column
        assert sheet(c).dataframe["Age"].dtype.kind == "f"
        assert column(c, "Age")[1] == 30.5

        assert c.edit_cell(2, 2, " 7 ") is True           # whitespace tolerated
        assert column(c, "Score")[2] == 7

        # and the saved file holds real numbers, not text
        assert c.save_document() is True
        workbook = load_workbook(os.path.join(folder, "t.xlsx"))["Sheet1"]
        assert workbook["B2"].data_type == "n" and workbook["B2"].value == 26
        assert workbook["C4"].data_type == "n"


def test_non_numeric_text_in_a_numeric_column_is_kept_as_typed():
    with tempfile.TemporaryDirectory() as folder:
        c = make_controller(folder)
        assert c.edit_cell(0, 1, "n/a") is True
        assert column(c, "Age")[0] == "n/a"
        assert column(c, "Age")[1:] == [30, 22, 41]       # the rest untouched

        assert c.edit_cell(1, 1, "") is True              # blank is allowed too
        assert column(c, "Age")[1] == ""


def test_text_columns_are_not_converted():
    with tempfile.TemporaryDirectory() as folder:
        c = make_controller(folder)
        assert c.edit_cell(0, 0, "007") is True
        assert column(c, "Name")[0] == "007"              # stays text, keeps zeros


# ----------------------------------------------------------------------
# Undo / redo
# ----------------------------------------------------------------------

def test_undo_redo_edit_restores_value_and_type():
    with tempfile.TemporaryDirectory() as folder:
        c = make_controller(folder)
        original = sheet(c).dataframe.copy()

        assert c.edit_cells([(0, 1, "99"), (1, 0, "Zed")]) is True
        assert column(c, "Age")[0] == 99

        assert c.undo() is True
        assert sheet(c).dataframe.equals(original)                    # exact, dtypes included
        assert list(sheet(c).dataframe.dtypes) == list(original.dtypes)

        assert c.redo() is True
        assert column(c, "Age")[0] == 99 and column(c, "Name")[1] == "Zed"

        assert c.undo() is True and c.undo() is False                 # nothing left


def test_one_batch_is_one_undo_step():
    with tempfile.TemporaryDirectory() as folder:
        c = make_controller(folder)
        c.edit_cells([(0, 0, "a"), (1, 0, "b"), (2, 0, "c"), (3, 0, "d")])
        assert len(c.document.undo_stack) == 1
        assert c.undo() is True
        assert column(c, "Name") == ["Alice", "Bob", "Charlie", "Dana"]


def test_undo_covers_every_operation_kind():
    with tempfile.TemporaryDirectory() as folder:
        c = make_controller(folder)
        c.set_column_width("Name", 33)
        baseline = sheet(c).dataframe.copy()

        steps = [
            lambda: c.set_cell_style(0, 0, 1, 1, {"bold": True}),
            lambda: c.insert_row(1),
            lambda: c.delete_row(0),
            lambda: c.insert_column("Extra", 1),
            lambda: c.rename_column("Extra", "Extra2"),
            lambda: c.delete_column("Score"),
            lambda: c.edit_cell(0, 0, "changed"),
        ]
        states = [(sheet(c).dataframe.copy(), dict(sheet(c).column_widths), styles(c))]

        for step in steps:
            assert step() is True
            states.append((sheet(c).dataframe.copy(), dict(sheet(c).column_widths), styles(c)))

        # walk all the way back, checking each intermediate state exactly
        for expected_index in range(len(steps) - 1, -1, -1):
            assert c.undo() is True
            frame, widths, style_map = states[expected_index]
            assert sheet(c).dataframe.equals(frame), expected_index
            assert list(sheet(c).dataframe.columns) == list(frame.columns)
            assert sheet(c).column_widths == widths
            assert styles(c) == style_map

        assert c.undo() is False
        assert sheet(c).dataframe.equals(baseline)

        # and all the way forward again
        for expected_index in range(1, len(steps) + 1):
            assert c.redo() is True
            assert sheet(c).dataframe.equals(states[expected_index][0]), expected_index
            assert styles(c) == states[expected_index][2]
        assert c.redo() is False


def test_undoing_a_delete_restores_data_styles_and_width():
    with tempfile.TemporaryDirectory() as folder:
        c = make_controller(folder)
        c.set_cell_style(1, 2, 1, 2, {"italic": True})
        c.set_column_width("Score", 55)

        assert c.delete_column("Score") is True
        assert "Score" not in sheet(c).column_widths
        assert styles(c) == {}

        assert c.undo() is True
        assert column(c, "Score") == [90, 85, 95, 70]
        assert sheet(c).dataframe["Score"].dtype.kind == "i"
        assert styles(c) == {(1, 2): {"italic": True}}
        assert sheet(c).column_widths["Score"] == 55

        assert c.delete_row(1) is True
        assert styles(c) == {}
        assert c.undo() is True
        assert c.cell_value(1, 0) == "Bob" and styles(c) == {(1, 2): {"italic": True}}


def test_a_new_change_discards_the_redo_branch():
    with tempfile.TemporaryDirectory() as folder:
        c = make_controller(folder)
        c.edit_cell(0, 0, "one")
        c.undo()
        assert len(c.document.redo_stack) == 1
        c.edit_cell(0, 0, "two")
        assert len(c.document.redo_stack) == 0
        assert c.redo() is False


def test_history_is_capped():
    with tempfile.TemporaryDirectory() as folder:
        c = make_controller(folder)

        for i in range(60):
            assert c.edit_cell(0, 0, f"v{i}") is True

        assert len(c.document.undo_stack) == 50
        for _ in range(50):
            assert c.undo() is True
        assert c.undo() is False
        assert column(c, "Name")[0] == "v9"        # oldest kept state


def test_depths_are_reported_with_the_data():
    with tempfile.TemporaryDirectory() as folder:
        c = make_controller(folder)
        assert (c.grid_data().undo_depth, c.grid_data().redo_depth) == (0, 0)
        c.edit_cell(0, 0, "a")
        c.edit_cell(1, 0, "b")
        c.undo()
        assert (c.grid_data().undo_depth, c.grid_data().redo_depth) == (1, 1)


def test_undo_leaves_direction_and_default_style_alone():
    with tempfile.TemporaryDirectory() as folder:
        c = make_controller(folder)
        c.edit_cell(0, 0, "x")
        c.set_rtl(True)
        c.set_text_defaults({"bold": True})
        assert c.undo() is True
        assert c.rtl() is True
        assert c.text_defaults() == {"bold": True}


def test_failed_operations_record_nothing():
    with tempfile.TemporaryDirectory() as folder:
        c = make_controller(folder)
        assert c.edit_cell(99, 0, "x") is False
        assert c.insert_row(99) is False
        assert c.delete_row(99) is False
        assert c.delete_column("nope") is False
        assert c.rename_column("nope", "x") is False
        assert c.set_cell_style(0, 0, 0, 0, {"color": "bad"}) is False
        assert len(c.document.undo_stack) == 0


# ----------------------------------------------------------------------
# Boundaries that must clear history
# ----------------------------------------------------------------------

def test_view_changes_clear_history():
    with tempfile.TemporaryDirectory() as folder:
        for change in (
            lambda c: c.search("a"),
            lambda c: c.clear_search(),
            lambda c: c.sort([{"column": "Age", "ascending": True}]),
            lambda c: c.clear_sort(),
        ):
            c = make_controller(folder)
            c.edit_cell(0, 0, "x")
            assert len(c.document.undo_stack) == 1
            change(c)
            assert len(c.document.undo_stack) == 0
            assert c.undo() is False


def test_sheet_and_document_changes_clear_history():
    with tempfile.TemporaryDirectory() as folder:
        c = make_controller(folder)
        c.edit_cell(0, 0, "x")
        assert c.add_sheet("Other") is True
        assert len(c.document.undo_stack) == 0

        c.edit_cell(0, 0, "y") if False else None
        assert c.set_sheet("Sheet1") is True
        c.edit_cell(0, 0, "x2")
        assert c.rename_sheet("Sheet1", "Renamed") is True
        assert len(c.document.undo_stack) == 0

        c.edit_cell(0, 0, "x3")
        assert c.open_document("t.xlsx") is True
        assert len(c.document.undo_stack) == 0 and len(c.document.redo_stack) == 0


def test_undo_works_while_a_filter_or_sort_is_in_place_and_stays_correct():
    with tempfile.TemporaryDirectory() as folder:
        c = make_controller(folder)
        assert c.search("a") is True               # Alice, Charlie, Dana
        rows_before = grid(c)

        assert c.edit_cell(1, 1, "50") is True     # Charlie's age
        assert c.undo() is True
        assert grid(c) == rows_before              # view re-applied, identical
        assert column(c, "Age") == [25, 30, 22, 41]


# ----------------------------------------------------------------------
# Persistence: what undo does must reach the file
# ----------------------------------------------------------------------

def test_undo_reaches_the_saved_file():
    with tempfile.TemporaryDirectory() as folder:
        c = make_controller(folder)
        c.edit_cells([(0, 0, "Changed"), (0, 1, "99")])
        c.set_cell_style(0, 0, 0, 0, {"bold": True})
        assert c.undo() is True                    # drop the bold
        assert c.undo() is True                    # drop the edits

        fresh = reopen(c, folder)
        assert column(fresh, "Name")[0] == "Alice"
        assert column(fresh, "Age")[0] == 25
        assert styles(fresh) == {}


def test_redo_reaches_the_saved_file():
    with tempfile.TemporaryDirectory() as folder:
        c = make_controller(folder)
        c.edit_cell(0, 0, "Changed")
        c.undo()
        c.redo()

        fresh = reopen(c, folder)
        assert column(fresh, "Name")[0] == "Changed"


def test_large_sheet_history_timing_smoke():
    import time

    rows = [[f"n{i}", i, i * 2] for i in range(20000)]
    with tempfile.TemporaryDirectory() as folder:
        c = make_controller(folder, rows=rows, header=("a", "b", "c"))

        start = time.perf_counter()
        for i in range(20):
            assert c.edit_cell(i, 0, f"v{i}") is True
        edit_seconds = (time.perf_counter() - start) / 20

        start = time.perf_counter()
        assert c.undo() is True
        undo_seconds = time.perf_counter() - start

        start = time.perf_counter()
        assert c.edit_cells([(i, 0, "p") for i in range(500)]) is True
        batch_seconds = time.perf_counter() - start

        print(
            f"20k rows: edit {edit_seconds * 1000:.0f} ms each, undo {undo_seconds * 1000:.0f} ms, "
            f"500-cell batch {batch_seconds * 1000:.0f} ms"
        )
