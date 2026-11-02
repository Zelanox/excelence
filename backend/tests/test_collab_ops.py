"""Tests for canonical operations (backend/collab/operations.py), against a
real document. The sample workbook is "Sheet1" with columns Name, Age, Score
and rows Alice, Bob, Charlie, Dana (see make_controller in test_text_styles).
"""

import tempfile

from backend.collab.operations import (
    BATCH_TOO_LARGE,
    COLUMN_DELETED,
    EMPTY_BATCH,
    INVALID_VALUE,
    NAME_TAKEN,
    ROW_DELETED,
    SHEET_DELETED,
    UNKNOWN_COLUMN,
    UNKNOWN_ROW,
    UNKNOWN_SHEET,
    OpError,
    apply_batch,
    parse_batch,
)
from backend.tests.test_text_styles import make_controller


def batch(sheet_id, *ops, batch_id="b1", base=0):
    return {"client_batch_id": batch_id, "base_revision": base, "sheet_id": sheet_id, "ops": list(ops)}


def run(controller, payload):
    return apply_batch(controller, parse_batch(payload))


def refused(payload_or_call):
    """The OpError a call raises (the test fails if it does not raise)."""
    try:
        payload_or_call()
    except OpError as error:
        return error

    raise AssertionError("expected the batch to be refused")


def names(controller):
    return [row["Name"] for row in controller.grid_data().rows]


def ids(controller):
    data = controller.grid_data()
    return data.row_ids, data.column_ids, data.sheet_id


# ----------------------------------------------------------------------
# Reading a batch
# ----------------------------------------------------------------------

def test_a_well_formed_batch_is_accepted_as_it_is():
    parsed = parse_batch(batch("s1", {"op": "set_rtl", "value": True}))

    assert parsed.client_batch_id == "b1" and parsed.sheet_id == "s1" and parsed.base_revision == 0


MALFORMED_BATCHES = [
    None,
    [],
    {},                                                                                   # no batch id
    {"client_batch_id": "", "sheet_id": "s1", "ops": [{"op": "set_rtl", "value": True}]},
    {"client_batch_id": "b", "sheet_id": "s1", "ops": "nope"},
    {"client_batch_id": "b", "ops": [{"op": "set_rtl", "value": True}]},                  # no sheet id
    {"client_batch_id": "b", "sheet_id": "s1", "base_revision": -1, "ops": [{"op": "set_rtl", "value": True}]},
    {"client_batch_id": "b", "sheet_id": "s1", "base_revision": True, "ops": [{"op": "set_rtl", "value": True}]},
    {"client_batch_id": "b", "sheet_id": "s1", "ops": [{"op": "explode"}]},
    {"client_batch_id": "b", "sheet_id": "s1", "ops": ["set_rtl"]},
    {"client_batch_id": "b", "sheet_id": "s1", "ops": [{"op": "set_rtl", "value": "yes"}]},
    {"client_batch_id": "b", "sheet_id": "s1", "ops": [{"op": "set_rtl", "value": True, "extra": 1}]},
    {"client_batch_id": "b", "sheet_id": "s1", "ops": [{"op": "delete_row"}]},
    {"client_batch_id": "b", "sheet_id": "s1", "ops": [{"op": "insert_column", "name": "  "}]},
    {"client_batch_id": "b", "sheet_id": "s1", "ops": [{"op": "set_cells", "cells": []}]},
    {"client_batch_id": "b", "sheet_id": "s1", "ops": [{"op": "set_cells", "cells": [{"row": "r1", "column": "c1"}]}]},
]


def test_a_malformed_batch_is_refused():
    for payload in MALFORMED_BATCHES:
        error = refused(lambda: parse_batch(payload))
        assert error.code == "BAD_REQUEST", payload


def test_an_empty_batch_is_refused():
    assert refused(lambda: parse_batch(batch("s1"))).code == EMPTY_BATCH


def test_a_cell_value_must_be_plain():
    for value in [7, 2.5, True, float("nan"), float("inf"), {"a": 1}, [1], object()]:
        error = refused(lambda: parse_batch(batch("s1", {"op": "set_cells", "cells": [{"row": "r1", "column": "c1", "value": value}]})))
        assert error.code == INVALID_VALUE, value


def test_a_column_width_must_be_in_range():
    for width in [0, -5, 1001, True, "20", float("nan")]:
        error = refused(lambda: parse_batch(batch("s1", {"op": "set_column_width", "column": "c1", "width": width})))
        assert error.code == INVALID_VALUE, width


def test_a_batch_may_hold_500_changes_but_not_501():
    def cells(n):
        return [{"row": "r1", "column": "c1", "value": str(i)} for i in range(n)]

    parse_batch(batch("s1", {"op": "set_cells", "cells": cells(500)}))

    assert refused(lambda: parse_batch(batch("s1", {"op": "set_cells", "cells": cells(501)}))).code == BATCH_TOO_LARGE
    assert refused(lambda: parse_batch(batch("s1", {"op": "set_cells", "cells": cells(500)}, {"op": "set_rtl", "value": True}))).code == BATCH_TOO_LARGE


def test_sheet_operations_must_be_alone_in_their_batch():
    two = {"client_batch_id": "b", "ops": [{"op": "add_sheet", "name": "X"}, {"op": "set_rtl", "value": True}]}
    assert refused(lambda: parse_batch(two)).code == "BAD_REQUEST"

    parse_batch({"client_batch_id": "b", "ops": [{"op": "add_sheet", "name": "X"}]})     # no sheet_id needed


# ----------------------------------------------------------------------
# Cells
# ----------------------------------------------------------------------

def test_set_cells_changes_the_cell_named_by_its_ids():
    with tempfile.TemporaryDirectory() as folder:
        c = make_controller(folder)
        rows, columns, sheet = ids(c)
        op = {"op": "set_cells", "cells": [{"row": rows[1], "column": columns[0], "value": "Bobby"}]}

        outcome = run(c, batch(sheet, op))

        assert outcome.applied == [op] and outcome.dropped == []
        assert names(c) == ["Alice", "Bobby", "Charlie", "Dana"]


def test_a_change_lands_on_the_same_row_after_rows_were_inserted_above():
    with tempfile.TemporaryDirectory() as folder:
        c = make_controller(folder)
        rows, columns, sheet = ids(c)

        c.insert_row(0)                      # someone else adds a row on top
        c.insert_row(0)

        run(c, batch(sheet, {"op": "set_cells", "cells": [{"row": rows[2], "column": columns[0], "value": "Chuck"}]}))

        assert names(c) == ["", "", "Alice", "Bob", "Chuck", "Dana"]


def test_a_change_to_a_deleted_row_is_dropped_and_the_rest_applies():
    with tempfile.TemporaryDirectory() as folder:
        c = make_controller(folder)
        rows, columns, sheet = ids(c)
        c.delete_row(1)                      # Bob is gone

        outcome = run(c, batch(sheet, {"op": "set_cells", "cells": [
            {"row": rows[1], "column": columns[0], "value": "ghost"},
            {"row": rows[2], "column": columns[0], "value": "Chuck"},
        ]}))

        assert [d["reason"] for d in outcome.dropped] == [ROW_DELETED]
        assert outcome.dropped[0]["row"] == rows[1]
        assert outcome.applied[0]["cells"] == [{"row": rows[2], "column": columns[0], "value": "Chuck"}]
        assert names(c) == ["Alice", "Chuck", "Dana"]


def test_a_batch_that_only_touches_deleted_things_changes_nothing():
    with tempfile.TemporaryDirectory() as folder:
        c = make_controller(folder)
        rows, columns, sheet = ids(c)
        c.delete_row(0)

        outcome = run(c, batch(sheet, {"op": "set_cells", "cells": [{"row": rows[0], "column": columns[0], "value": "x"}]}))

        assert outcome.applied == [] and len(outcome.dropped) == 1


def test_an_id_that_never_existed_refuses_the_whole_batch_before_anything_changes():
    with tempfile.TemporaryDirectory() as folder:
        c = make_controller(folder)
        rows, columns, sheet = ids(c)

        error = refused(lambda: run(c, batch(
            sheet,
            {"op": "set_cells", "cells": [{"row": rows[0], "column": columns[0], "value": "changed"}]},
            {"op": "delete_row", "row": "r999"},
        )))

        assert error.code == UNKNOWN_ROW and error.index == 1
        assert names(c)[0] == "Alice"                        # the first operation was not applied

        error = refused(lambda: run(c, batch(sheet, {"op": "set_cells", "cells": [{"row": rows[0], "column": "c999", "value": "x"}]})))
        assert error.code == UNKNOWN_COLUMN


def test_a_cell_can_be_cleared_and_typed_text_becomes_a_number_in_a_numeric_column():
    with tempfile.TemporaryDirectory() as folder:
        c = make_controller(folder)
        rows, columns, sheet = ids(c)

        run(c, batch(sheet, {"op": "set_cells", "cells": [
            {"row": rows[0], "column": columns[0], "value": None},
            {"row": rows[0], "column": columns[1], "value": "41"},
        ]}))

        first = c.grid_data().rows[0]
        assert first["Name"] in ("", None) and first["Age"] == 41


# ----------------------------------------------------------------------
# Rows
# ----------------------------------------------------------------------

def test_insert_row_before_a_row_reports_the_id_of_the_new_row():
    with tempfile.TemporaryDirectory() as folder:
        c = make_controller(folder)
        rows, _, sheet = ids(c)

        outcome = run(c, batch(sheet, {"op": "insert_row", "before": rows[2]}))

        new_id = outcome.applied[0]["id"]
        data = c.grid_data()

        assert data.row_ids == [rows[0], rows[1], new_id, rows[2], rows[3]]
        assert new_id not in rows
        assert names(c) == ["Alice", "Bob", "", "Charlie", "Dana"]


def test_insert_row_with_no_row_to_go_before_adds_one_at_the_end():
    with tempfile.TemporaryDirectory() as folder:
        c = make_controller(folder)
        rows, _, sheet = ids(c)

        outcome = run(c, batch(sheet, {"op": "insert_row", "before": None}))

        assert c.grid_data().row_ids == rows + [outcome.applied[0]["id"]]


def test_insert_row_before_a_deleted_row_is_dropped():
    with tempfile.TemporaryDirectory() as folder:
        c = make_controller(folder)
        rows, _, sheet = ids(c)
        c.delete_row(2)

        outcome = run(c, batch(sheet, {"op": "insert_row", "before": rows[2]}))

        assert outcome.applied == [] and outcome.dropped[0]["reason"] == ROW_DELETED
        assert len(c.grid_data().rows) == 3


def test_delete_row_removes_it_and_a_second_delete_is_dropped():
    with tempfile.TemporaryDirectory() as folder:
        c = make_controller(folder)
        rows, _, sheet = ids(c)

        first = run(c, batch(sheet, {"op": "delete_row", "row": rows[1]}))
        again = run(c, batch(sheet, {"op": "delete_row", "row": rows[1]}, batch_id="b2"))

        assert first.applied == [{"op": "delete_row", "row": rows[1]}]
        assert again.applied == [] and again.dropped[0]["reason"] == ROW_DELETED
        assert names(c) == ["Alice", "Charlie", "Dana"]


def test_several_operations_in_one_batch_apply_in_order():
    with tempfile.TemporaryDirectory() as folder:
        c = make_controller(folder)
        rows, columns, sheet = ids(c)

        outcome = run(c, batch(
            sheet,
            {"op": "delete_row", "row": rows[0]},
            {"op": "set_cells", "cells": [{"row": rows[0], "column": columns[0], "value": "late"}]},   # its row was just deleted
            {"op": "set_cells", "cells": [{"row": rows[1], "column": columns[0], "value": "Bobby"}]},
        ))

        assert len(outcome.applied) == 2 and [d["index"] for d in outcome.dropped] == [1]
        assert names(c) == ["Bobby", "Charlie", "Dana"]


# ----------------------------------------------------------------------
# Columns
# ----------------------------------------------------------------------

def test_insert_column_goes_before_the_named_column_and_reports_its_id():
    with tempfile.TemporaryDirectory() as folder:
        c = make_controller(folder)
        _, columns, sheet = ids(c)

        outcome = run(c, batch(sheet, {"op": "insert_column", "name": "City", "before": columns[1]}))

        data = c.grid_data()
        assert data.headers == ["Name", "City", "Age", "Score"]
        assert data.column_ids == [columns[0], outcome.applied[0]["id"], columns[1], columns[2]]


def test_a_column_name_clash_refuses_the_batch_before_anything_changes():
    with tempfile.TemporaryDirectory() as folder:
        c = make_controller(folder)
        rows, columns, sheet = ids(c)

        error = refused(lambda: run(c, batch(
            sheet,
            {"op": "set_cells", "cells": [{"row": rows[0], "column": columns[0], "value": "changed"}]},
            {"op": "insert_column", "name": "Age"},
        )))

        assert error.code == NAME_TAKEN and error.index == 1
        assert names(c)[0] == "Alice"


def test_deleting_a_column_and_adding_its_name_back_in_one_batch_is_allowed():
    with tempfile.TemporaryDirectory() as folder:
        c = make_controller(folder)
        _, columns, sheet = ids(c)

        outcome = run(c, batch(
            sheet,
            {"op": "delete_column", "column": columns[1]},
            {"op": "insert_column", "name": "Age"},
        ))

        assert len(outcome.applied) == 2
        assert c.grid_data().headers == ["Name", "Score", "Age"] or c.grid_data().headers == ["Name", "Age", "Score"]


def test_a_renamed_column_is_still_reached_by_its_old_id():
    with tempfile.TemporaryDirectory() as folder:
        c = make_controller(folder)
        rows, columns, sheet = ids(c)

        run(c, batch(sheet, {"op": "rename_column", "column": columns[2], "name": "Points"}))
        run(c, batch(sheet, {"op": "set_cells", "cells": [{"row": rows[0], "column": columns[2], "value": "99"}]}, batch_id="b2"))

        data = c.grid_data()
        assert data.headers == ["Name", "Age", "Points"] and data.rows[0]["Points"] == 99
        assert data.column_ids == columns


def test_a_change_to_a_deleted_column_is_dropped():
    with tempfile.TemporaryDirectory() as folder:
        c = make_controller(folder)
        rows, columns, sheet = ids(c)
        c.delete_column("Score")

        outcome = run(c, batch(
            sheet,
            {"op": "set_cells", "cells": [{"row": rows[0], "column": columns[2], "value": "1"}]},
            {"op": "rename_column", "column": columns[2], "name": "X"},
            {"op": "set_column_width", "column": columns[2], "width": 30},
            {"op": "delete_column", "column": columns[2]},
        ))

        assert outcome.applied == []
        assert [d["reason"] for d in outcome.dropped] == [COLUMN_DELETED] * 4


def test_rename_to_a_name_in_use_is_refused():
    with tempfile.TemporaryDirectory() as folder:
        c = make_controller(folder)
        _, columns, sheet = ids(c)

        error = refused(lambda: run(c, batch(sheet, {"op": "rename_column", "column": columns[2], "name": "Age"})))

        assert error.code == NAME_TAKEN
        assert c.grid_data().headers == ["Name", "Age", "Score"]


def test_column_width_and_direction_are_set_by_operation():
    with tempfile.TemporaryDirectory() as folder:
        c = make_controller(folder)
        _, columns, sheet = ids(c)

        run(c, batch(sheet, {"op": "set_column_width", "column": columns[0], "width": 33.5}, {"op": "set_rtl", "value": True}))

        data = c.grid_data()
        assert data.column_widths == {"Name": 33.5} and data.rtl is True


# ----------------------------------------------------------------------
# Which sheet, and the server's own view
# ----------------------------------------------------------------------

def test_a_batch_for_a_sheet_that_is_not_open_changes_it_and_leaves_the_open_sheet_open():
    with tempfile.TemporaryDirectory() as folder:
        c = make_controller(folder)
        rows, columns, first = ids(c)
        assert c.add_sheet("Other") is True              # "Other" is now open
        open_ids = ids(c)

        run(c, batch(first, {"op": "set_cells", "cells": [{"row": rows[0], "column": columns[0], "value": "Zed"}]}))

        assert c.current_sheet() == "Other" and ids(c) == open_ids
        assert c.set_sheet("Sheet1") is True
        assert names(c) == ["Zed", "Bob", "Charlie", "Dana"]


def test_a_search_or_sort_left_on_the_server_does_not_misdirect_a_change():
    with tempfile.TemporaryDirectory() as folder:
        c = make_controller(folder)
        rows, columns, sheet = ids(c)
        assert c.sort([{"column": "Score", "ascending": True}]) is True      # Bob 85 first
        assert c.search("a") is True

        run(c, batch(sheet, {"op": "set_cells", "cells": [{"row": rows[0], "column": columns[0], "value": "Alicia"}]}))

        c.clear_search()
        c.clear_sort()
        assert names(c)[0] == "Alicia"


def test_an_unknown_sheet_is_refused_and_a_deleted_one_is_dropped():
    with tempfile.TemporaryDirectory() as folder:
        c = make_controller(folder)
        assert c.add_sheet("Other") is True
        other = c.current_sheet_id()
        assert c.delete_sheet("Other") is True

        op = {"op": "set_rtl", "value": True}

        assert refused(lambda: run(c, batch("s999", op))).code == UNKNOWN_SHEET

        outcome = run(c, batch(other, op))
        assert outcome.applied == [] and outcome.dropped[0]["reason"] == SHEET_DELETED


# ----------------------------------------------------------------------
# Sheet operations
# ----------------------------------------------------------------------

def sheet_op(op):
    return {"client_batch_id": "bs", "ops": [op]}


def test_add_sheet_reports_its_id_and_leaves_the_open_sheet_open():
    with tempfile.TemporaryDirectory() as folder:
        c = make_controller(folder)
        before = ids(c)

        outcome = run(c, sheet_op({"op": "add_sheet", "name": "Other"}))

        added = outcome.applied[0]
        assert c.sheets() == ["Sheet1", "Other"]
        assert added["id"] == c.sheet_ids()[1] and added["id"] != before[2]
        assert c.current_sheet() == "Sheet1" and ids(c) == before


def test_rename_sheet_and_delete_sheet_work_by_id():
    with tempfile.TemporaryDirectory() as folder:
        c = make_controller(folder)
        added = run(c, sheet_op({"op": "add_sheet", "name": "Other"})).applied[0]["id"]

        run(c, sheet_op({"op": "rename_sheet", "sheet": added, "name": "Renamed"}))
        assert c.sheets() == ["Sheet1", "Renamed"] and c.sheet_ids()[1] == added

        run(c, sheet_op({"op": "delete_sheet", "sheet": added}))
        assert c.sheets() == ["Sheet1"]


def test_sheet_operations_refuse_a_name_in_use_and_the_last_sheet_stays():
    with tempfile.TemporaryDirectory() as folder:
        c = make_controller(folder)
        only = c.current_sheet_id()

        assert refused(lambda: run(c, sheet_op({"op": "add_sheet", "name": "Sheet1"}))).code == NAME_TAKEN
        assert refused(lambda: run(c, sheet_op({"op": "delete_sheet", "sheet": only}))).code == "APPLY_FAILED"
        assert c.sheets() == ["Sheet1"]


def test_a_sheet_operation_on_a_deleted_sheet_is_dropped():
    with tempfile.TemporaryDirectory() as folder:
        c = make_controller(folder)
        added = run(c, sheet_op({"op": "add_sheet", "name": "Other"})).applied[0]["id"]
        run(c, sheet_op({"op": "delete_sheet", "sheet": added}))

        outcome = run(c, sheet_op({"op": "rename_sheet", "sheet": added, "name": "Late"}))

        assert outcome.applied == [] and outcome.dropped[0]["reason"] == SHEET_DELETED


# ----------------------------------------------------------------------
# Formatting: cell styles, text defaults, appearance
# ----------------------------------------------------------------------

def style_op(rows, columns, style=None, reset=None, start=0, end=-1):
    """A set_cell_style over the rectangle from rows[start] / columns[0] to rows[end] / columns[-1]."""
    op = {
        "op": "set_cell_style",
        "ranges": [{
            "start_row": rows[start], "end_row": rows[end],
            "start_column": columns[0], "end_column": columns[-1],
        }],
    }

    if style is not None:
        op["style"] = style

    if reset is not None:
        op["reset"] = reset

    return op


def styled_cells(controller):
    return {(entry["row"], entry["column"]): entry["style"] for entry in controller.cell_styles()}


def test_a_cell_style_covers_the_rectangle_between_its_corners_in_any_order():
    with tempfile.TemporaryDirectory() as folder:
        controller = make_controller(folder)
        rows, columns, sheet = ids(controller)

        outcome = run(controller, batch(sheet, style_op(rows[:2][::-1], columns[:2], {"bold": True}, end=-1)))

        assert outcome.dropped == []
        assert styled_cells(controller) == {
            (0, 0): {"bold": True}, (0, 1): {"bold": True},
            (1, 0): {"bold": True}, (1, 1): {"bold": True},
        }


def test_the_style_is_logged_the_way_the_document_stores_it():
    with tempfile.TemporaryDirectory() as folder:
        controller = make_controller(folder)
        rows, columns, sheet = ids(controller)

        outcome = run(controller, batch(sheet, style_op(rows, columns, {"color": "#ff0000", "font_size": 12}, ["italic"])))

        applied = outcome.applied[0]
        assert applied["style"] == {"color": "FF0000", "font_size": 12.0}
        assert applied["reset"] == ["italic"]
        assert applied["ranges"] == style_op(rows, columns)["ranges"]


def test_reset_returns_fields_to_inherit():
    with tempfile.TemporaryDirectory() as folder:
        controller = make_controller(folder)
        rows, columns, sheet = ids(controller)
        run(controller, batch(sheet, style_op(rows, columns, {"bold": True, "italic": True})))

        run(controller, batch(sheet, style_op(rows, columns, reset=["bold"]), batch_id="b2"))

        assert set(map(tuple, (s.items() for s in styled_cells(controller).values()))) == {(("italic", True),)}


def test_a_style_follows_its_rows_when_rows_are_inserted_in_the_same_batch():
    with tempfile.TemporaryDirectory() as folder:
        controller = make_controller(folder)
        rows, columns, sheet = ids(controller)

        run(controller, batch(
            sheet,
            {"op": "insert_row", "before": rows[0]},
            style_op(rows[:2], columns[:1], {"bold": True}),
        ))

        assert sorted(styled_cells(controller)) == [(1, 0), (2, 0)]        # moved down by the new first row


def test_a_range_whose_row_or_column_was_deleted_is_dropped_and_the_others_apply():
    with tempfile.TemporaryDirectory() as folder:
        controller = make_controller(folder)
        rows, columns, sheet = ids(controller)
        run(controller, batch(sheet, {"op": "delete_row", "row": rows[3]}, batch_id="gone"))
        run(controller, batch(sheet, {"op": "delete_column", "column": columns[2]}, batch_id="gone2"))

        outcome = run(controller, batch(sheet, {
            "op": "set_cell_style",
            "ranges": [
                {"start_row": rows[0], "end_row": rows[1], "start_column": columns[0], "end_column": columns[0]},
                {"start_row": rows[2], "end_row": rows[3], "start_column": columns[0], "end_column": columns[0]},
                {"start_row": rows[0], "end_row": rows[0], "start_column": columns[1], "end_column": columns[2]},
            ],
            "style": {"bold": True},
        }, batch_id="b3"))

        assert [(d["reason"], d.get("row") or d.get("column")) for d in outcome.dropped] == [
            (ROW_DELETED, rows[3]), (COLUMN_DELETED, columns[2]),
        ]
        assert len(outcome.applied[0]["ranges"]) == 1
        assert sorted(styled_cells(controller)) == [(0, 0), (1, 0)]


def test_a_batch_whose_ranges_are_all_gone_applies_nothing_and_is_not_an_error():
    with tempfile.TemporaryDirectory() as folder:
        controller = make_controller(folder)
        rows, columns, sheet = ids(controller)
        run(controller, batch(sheet, {"op": "delete_row", "row": rows[0]}, batch_id="gone"))

        outcome = run(controller, batch(sheet, style_op(rows[:1], columns, {"bold": True}), batch_id="b2"))

        assert outcome.applied == [] and len(outcome.dropped) == 1
        assert styled_cells(controller) == {}


def test_a_style_with_a_bad_field_value_or_shape_is_refused_before_anything_changes():
    with tempfile.TemporaryDirectory() as folder:
        controller = make_controller(folder)
        rows, columns, sheet = ids(controller)

        bad = [
            {"nonsense": True},
            {"bold": "yes"},
            {"color": "red"},
            {"font_size": True},
            {"font_size": 0},
            {"bold": None},
        ]

        for style in bad:
            error = refused(lambda s=style: run(controller, batch(sheet, {"op": "set_rtl", "value": True}, style_op(rows, columns, s))))
            assert error.code == INVALID_VALUE, style

        both = refused(lambda: run(controller, batch(sheet, style_op(rows, columns, {"bold": True}, ["bold"]))))
        assert both.code == INVALID_VALUE

        assert styled_cells(controller) == {}
        assert controller.rtl() is False                      # the set_rtl before the bad op was not applied either


def test_a_style_op_needs_a_style_or_a_reset_and_well_formed_ranges():
    with tempfile.TemporaryDirectory() as folder:
        controller = make_controller(folder)
        rows, columns, sheet = ids(controller)

        malformed = [
            style_op(rows, columns),                                    # neither style nor reset
            style_op(rows, columns, {}),
            style_op(rows, columns, {"bold": True}, "bold"),            # reset not a list
            style_op(rows, columns, [("bold", True)]),                  # style not an object
            {"op": "set_cell_style", "ranges": [], "style": {"bold": True}},
            {"op": "set_cell_style", "ranges": [{"start_row": rows[0]}], "style": {"bold": True}},
            {"op": "set_cell_style", "ranges": [{"start_row": 1, "end_row": 2, "start_column": 3, "end_column": 4}], "style": {"bold": True}},
            {"op": "set_cell_style", "style": {"bold": True}},
            {**style_op(rows, columns, {"bold": True}), "extra": 1},
        ]

        for op in malformed:
            assert refused(lambda o=op: parse_batch(batch(sheet, o))).code == "BAD_REQUEST", op


def test_a_range_naming_a_row_that_never_existed_is_refused():
    with tempfile.TemporaryDirectory() as folder:
        controller = make_controller(folder)
        rows, columns, sheet = ids(controller)

        error = refused(lambda: run(controller, batch(sheet, style_op(["r999", rows[0]], columns, {"bold": True}))))

        assert error.code == UNKNOWN_ROW and styled_cells(controller) == {}


def test_every_range_counts_towards_the_batch_limit():
    with tempfile.TemporaryDirectory() as folder:
        controller = make_controller(folder)
        rows, columns, sheet = ids(controller)
        one = style_op(rows, columns, {"bold": True})["ranges"][0]

        error = refused(lambda: parse_batch(batch(sheet, {"op": "set_cell_style", "ranges": [one] * 501, "style": {"bold": True}})))

        assert error.code == BATCH_TOO_LARGE


def test_text_defaults_and_appearance_can_be_set_reset_and_set_again():
    with tempfile.TemporaryDirectory() as folder:
        controller = make_controller(folder)
        rows, columns, sheet = ids(controller)

        first = run(controller, batch(sheet,
            {"op": "set_text_defaults", "style": {"font_size": 14, "background": "#eeeeee"}},
            {"op": "set_appearance", "style": {"banding": True, "banding_color": "#ccddee"}},
        ))

        assert first.applied[0]["style"] == {"font_size": 14.0, "background": "EEEEEE"}
        assert first.applied[1]["style"] == {"banding": True, "banding_color": "CCDDEE"}
        assert controller.document.data().text_defaults == {"font_size": 14.0, "background": "EEEEEE"}
        assert controller.appearance() == {"banding": True, "banding_color": "CCDDEE"}

        run(controller, batch(sheet,
            {"op": "set_text_defaults", "reset": ["background"]},
            {"op": "set_appearance", "reset": ["banding_color"]},
            batch_id="b2",
        ))

        assert controller.document.data().text_defaults == {"font_size": 14.0}
        assert controller.appearance() == {"banding": True}

        again = run(controller, batch(sheet, {"op": "set_appearance", "style": {"banding": True}}, batch_id="b3"))
        assert again.applied[0]["op"] == "set_appearance"                       # setting what is already set is fine


def test_bad_defaults_and_appearance_are_refused():
    with tempfile.TemporaryDirectory() as folder:
        controller = make_controller(folder)
        rows, columns, sheet = ids(controller)

        for op in (
            {"op": "set_text_defaults", "style": {"italic": "no"}},
            {"op": "set_appearance", "style": {"banding": "on"}},
            {"op": "set_appearance", "style": {"grid_color": "nope"}},
            {"op": "set_appearance", "style": {"bold": True}},                  # a cell field, not an appearance one
        ):
            assert refused(lambda o=op: run(controller, batch(sheet, o))).code == INVALID_VALUE, op

        for op in ({"op": "set_text_defaults"}, {"op": "set_appearance", "style": {}}):
            assert refused(lambda o=op: parse_batch(batch(sheet, o))).code == "BAD_REQUEST", op
