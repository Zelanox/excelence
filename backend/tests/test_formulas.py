"""Stored formulas: reference rewriting on structural edits, and persistence."""

import os
import tempfile

from openpyxl import load_workbook

from backend.models.formula_refs import (
    REF_ERROR,
    RefChange,
    adjust_formula,
    column_index,
    column_letters,
)
from backend.tests.test_text_styles import make_controller, reopen


def ri(i): return RefChange("row", "insert", i)
def rd(i): return RefChange("row", "delete", i)
def ci(i): return RefChange("column", "insert", i)
def cd(i): return RefChange("column", "delete", i)


def test_column_letters_round_trip():
    for index in (0, 1, 25, 26, 27, 51, 52, 701, 702, 18277):
        assert column_index(column_letters(index)) == index
    assert [column_letters(i) for i in (0, 25, 26, 27, 701, 702)] == ["A", "Z", "AA", "AB", "ZZ", "AAA"]


# ---------------------------------------------------------------- row insert

def test_insert_row_moves_references_at_or_after_the_row():
    # inserting at position 1 (before sheet row 2): row 1 stays, rows 2+ move down
    assert adjust_formula("=A1+A2+A3", ri(1)) == "=A1+A3+A4"
    assert adjust_formula("=B1", ri(0)) == "=B2"             # insert at the very top moves row 1
    assert adjust_formula("=B1", ri(5)) == "=B1"             # below everything: nothing moves


def test_insert_row_expands_a_range_it_falls_inside():
    assert adjust_formula("=SUM(A1:A5)", ri(2)) == "=SUM(A1:A6)"     # inside -> grows
    assert adjust_formula("=SUM(A3:A5)", ri(0)) == "=SUM(A4:A6)"     # above -> whole range shifts
    assert adjust_formula("=SUM(A1:A5)", ri(5)) == "=SUM(A1:A5)"     # right after the end -> not included
    assert adjust_formula("=SUM(A1:A5)", ri(0)) == "=SUM(A2:A6)"     # at the start -> shifts, not grows


def test_row_changes_do_not_touch_columns_and_vice_versa():
    assert adjust_formula("=SUM(A1:C1)", ri(0)) == "=SUM(A2:C2)"
    assert adjust_formula("=SUM(A1:C1)", ci(1)) == "=SUM(A1:D1)"     # column insert inside the range grows it
    assert adjust_formula("=C5", ci(0)) == "=D5"


# ---------------------------------------------------------------- row delete

def test_delete_row_moves_later_references_up():
    assert adjust_formula("=A1+A4", rd(1)) == "=A1+A3"
    assert adjust_formula("=A2", rd(1)) == REF_ERROR.join(["=", ""])   # the deleted cell itself
    assert adjust_formula("=A1+A2*3", rd(1)) == "=A1+#REF!*3"


def test_delete_row_shrinks_ranges():
    assert adjust_formula("=SUM(A1:A5)", rd(2)) == "=SUM(A1:A4)"      # a row inside
    assert adjust_formula("=SUM(A1:A5)", rd(4)) == "=SUM(A1:A4)"      # the last row
    assert adjust_formula("=SUM(A1:A5)", rd(0)) == "=SUM(A1:A4)"      # the first row (next one slides in)
    assert adjust_formula("=SUM(A3:A5)", rd(0)) == "=SUM(A2:A4)"      # above: range shifts
    assert adjust_formula("=SUM(A1:A5)", rd(5)) == "=SUM(A1:A5)"      # below: untouched


def test_deleting_the_only_row_of_a_range_is_a_ref_error():
    assert adjust_formula("=SUM(A3:A3)", rd(2)) == "=SUM(#REF!)"
    assert adjust_formula("=SUM(A3:A4)", rd(2)) == "=SUM(A3:A3)"      # two rows -> one left


def test_reversed_ranges_are_kept_reversed():
    assert adjust_formula("=SUM(A5:A1)", ri(2)) == "=SUM(A6:A1)"
    assert adjust_formula("=SUM(A5:A1)", rd(0)) == "=SUM(A4:A1)"


# ---------------------------------------------------------------- columns

def test_delete_column():
    assert adjust_formula("=A1+B1+C1", cd(1)) == "=A1+#REF!+B1"
    assert adjust_formula("=SUM(A1:D1)", cd(1)) == "=SUM(A1:C1)"
    assert adjust_formula("=SUM(B1:B9)", cd(1)) == "=SUM(#REF!)"


def test_multi_letter_columns():
    assert adjust_formula("=Z1+AA1+AB1", ci(26)) == "=Z1+AB1+AC1"
    assert adjust_formula("=AA10", cd(0)) == "=Z10"


# ---------------------------------------------------------------- must not touch

def test_non_formulas_and_non_references_are_left_alone():
    for text in ("A1", "hello A1", "", "0012", None, 5, "SUM(A1:A3)", "=1+2", "=SUM(1,2)"):
        assert adjust_formula(text, ri(0)) == text, text


def test_function_names_with_digits_are_not_cells():
    assert adjust_formula("=LOG10(A1)", ri(0)) == "=LOG10(A2)"
    assert adjust_formula("=ATAN2(B1)", ri(0)) == "=ATAN2(B2)"


def test_references_glued_to_other_tokens_are_not_rewritten():
    assert adjust_formula("=2A1", ri(0)) == "=2A1"
    assert adjust_formula("=1.5A1", ri(0)) == "=1.5A1"
    assert adjust_formula("=A1B", ri(0)) == "=A1B"
    assert adjust_formula("=a1", ri(0)) == "=a1"                  # the engine only reads upper-case


def test_whole_range_and_nested_functions():
    assert adjust_formula("=SUM(A1:A3)+MAX(B1:B3, C2)", ri(1)) == "=SUM(A1:A4)+MAX(B1:B4, C3)"


def test_refchange_validation():
    for args in (("diagonal", "insert", 0), ("row", "move", 0), ("row", "insert", -1)):
        try:
            RefChange(*args)
        except ValueError:
            continue
        raise AssertionError(args)


# ---------------------------------------------------------------- through the sheet

ROWS = [[1, 10], [2, 20], [3, 30], [4, 40]]


def formulas(controller):
    frame = controller.document.spreadsheet.current_sheet().dataframe
    return {(r, c): v for r, row in enumerate(frame.values.tolist()) for c, v in enumerate(row)
            if isinstance(v, str) and v.startswith("=")}


def make(folder):
    c = make_controller(folder, rows=ROWS, header=("x", "y"))
    # put formulas in a fresh column z, referencing x and y
    assert c.insert_column("z", 2) is True
    assert c.edit_cells([(0, 2, "=A1+B1"), (1, 2, "=SUM(A1:A4)"), (3, 2, "=B4*2")]) is True
    return c


def test_insert_and_delete_row_rewrite_stored_formulas():
    with tempfile.TemporaryDirectory() as folder:
        c = make(folder)
        assert c.insert_row(1) is True                       # a blank row after the first
        assert formulas(c) == {(0, 2): "=A1+B1", (2, 2): "=SUM(A1:A5)", (4, 2): "=B5*2"}

        assert c.delete_row(0) is True                       # remove the first data row
        assert formulas(c) == {(1, 2): "=SUM(#REF!:A4)".replace("#REF!:", "") if False else formulas(c)[(1, 2)], (3, 2): "=B4*2"}
        # =A1+B1 pointed only at deleted cells -> its row went away with it; SUM(A1:A5) lost row 1
        assert formulas(c)[(1, 2)] == "=SUM(A1:A4)"


def test_insert_and_delete_column_rewrite_stored_formulas():
    with tempfile.TemporaryDirectory() as folder:
        c = make(folder)
        assert c.insert_column("new", 0) is True             # shifts x,y,z right by one
        assert formulas(c) == {(0, 3): "=B1+C1", (1, 3): "=SUM(B1:B4)", (3, 3): "=C4*2"}

        assert c.delete_column("x") is True                  # removes what is now column B
        assert formulas(c)[(0, 2)] == "=#REF!+B1"
        assert formulas(c)[(1, 2)] == "=SUM(#REF!)"


def test_undo_restores_the_original_formulas_exactly():
    with tempfile.TemporaryDirectory() as folder:
        c = make(folder)
        before = formulas(c)
        c.insert_row(0)
        c.delete_column("x")
        assert formulas(c) != before
        assert c.undo() is True and c.undo() is True
        assert formulas(c) == before


def test_formula_text_survives_save_and_reload_as_a_real_excel_formula():
    with tempfile.TemporaryDirectory() as folder:
        c = make(folder)
        fresh = reopen(c, folder)
        assert formulas(fresh) == {(0, 2): "=A1+B1", (1, 2): "=SUM(A1:A4)", (3, 2): "=B4*2"}

        sheet = load_workbook(os.path.join(folder, "t.xlsx"))["Sheet1"]
        assert sheet["C2"].data_type == "f" and sheet["C2"].value == "=A1+B1"
        assert sheet["C3"].value == "=SUM(A1:A4)"


def test_formula_text_in_a_numeric_column_is_kept_as_typed():
    with tempfile.TemporaryDirectory() as folder:
        c = make_controller(folder, rows=ROWS, header=("x", "y"))
        assert c.edit_cell(0, 1, "=A1*2") is True            # y was numeric
        assert c.edit_cell(1, 1, "99") is True               # numbers still work beside it
        frame = c.document.spreadsheet.current_sheet().dataframe
        assert list(frame["y"][:3]) == ["=A1*2", 99, 30]
        assert isinstance(frame["y"][1], int)                 # a number, not the text "99"

        # and in a column that is MOSTLY text, numeric-looking input stays text
        c2 = make_controller(folder, "t2.xlsx", rows=[["Alice", 1], ["Bob", 2]], header=("name", "n"))
        assert c2.edit_cell(0, 0, "007") is True
        assert c2.document.spreadsheet.current_sheet().dataframe["name"][0] == "007"


def test_structural_edits_leave_plain_text_and_numbers_alone():
    with tempfile.TemporaryDirectory() as folder:
        c = make_controller(folder, rows=[["A1", "see A1"], ["B2", 5]], header=("p", "q"))
        before = c.document.spreadsheet.current_sheet().dataframe.copy()
        c.insert_row(0)
        after = c.document.spreadsheet.current_sheet().dataframe
        assert after.iloc[1].tolist() == before.iloc[0].tolist()
        assert after.iloc[0].tolist() == ["", ""]


# ---------------------------------------------------------------- number preference

def column_values(controller, name):
    return controller.document.spreadsheet.current_sheet().dataframe[name].tolist()


def test_a_fresh_column_takes_numbers_as_numbers_and_text_as_text():
    with tempfile.TemporaryDirectory() as folder:
        c = make_controller(folder)
        assert c.insert_column("fresh") is True
        assert c.edit_cells([(0, 3, "5"), (1, 3, "2.5"), (2, 3, "abc")]) is True
        values = column_values(c, "fresh")
        assert values[:3] == [5, 2.5, "abc"] and isinstance(values[0], int)


def test_a_mostly_numeric_column_with_stray_text_still_stores_numbers():
    with tempfile.TemporaryDirectory() as folder:
        c = make_controller(folder)
        c.edit_cell(0, 1, "n/a")                              # Age: one text entry in a numeric column
        assert c.edit_cell(1, 1, "77") is True
        assert column_values(c, "Age")[:2] == ["n/a", 77]


def test_a_mostly_text_column_keeps_numeric_looking_input_as_text():
    with tempfile.TemporaryDirectory() as folder:
        c = make_controller(folder)
        assert c.edit_cells([(0, 0, "007"), (1, 0, "12"), (2, 0, "3.50")]) is True
        assert column_values(c, "Name")[:3] == ["007", "12", "3.50"]


def test_formulas_and_blanks_do_not_count_either_way():
    with tempfile.TemporaryDirectory() as folder:
        c = make_controller(folder, rows=[[1], [2], [3]], header=("v",))
        c.edit_cells([(0, 0, "=A2+A3"), (1, 0, "")])         # a formula and a blank among numbers
        assert c.edit_cell(2, 0, "9") is True
        assert column_values(c, "v")[2] == 9


def test_large_paste_into_a_big_mixed_column_stays_fast():
    import time
    rows = [[i, f"n{i}"] for i in range(20000)]
    with tempfile.TemporaryDirectory() as folder:
        c = make_controller(folder, rows=rows, header=("num", "txt"))
        c.edit_cell(0, 0, "=A2")                              # makes the numeric column mixed
        start = time.perf_counter()
        assert c.edit_cells([(i, 0, str(i * 2)) for i in range(1, 801)]) is True
        elapsed = time.perf_counter() - start
        assert column_values(c, "num")[5] == 10
        assert elapsed < 5, elapsed                           # the column is scanned once per batch, not per cell
