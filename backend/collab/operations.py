"""Canonical operations: the one way a change is described for live collaboration.

A client sends a *batch* of operations. Each operation names what it changes
by stable ID (a row by its row ID, a column by its column ID, a sheet by its
sheet ID), never by screen position or name, so it still means the same thing
when somebody else has inserted rows, sorted, or renamed something in the
meantime. The server applies the operations, numbers the batch (see op_log),
and what it stores and sends on to the other clients is the batch as applied,
with the IDs it assigned to anything new.

Operations in this first set:

    set_cells        {"cells": [{"row": "r3", "column": "c2", "value": "x" | null}]}
    insert_row       {"before": "r3" | null}            -> applied form adds "id"
    delete_row       {"row": "r3"}
    insert_column    {"name": "Age", "before": "c2" | null}   -> adds "id"
    delete_column    {"column": "c2"}
    rename_column    {"column": "c2", "name": "Points"}
    set_column_width {"column": "c2", "width": 24}
    set_rtl          {"value": true}
    add_sheet        {"name": "Other"}                  -> adds "id"
    delete_sheet     {"sheet": "s2"}
    rename_sheet     {"sheet": "s2", "name": "Renamed"}

(Cell and text styles, appearance and text defaults follow in the next step.)

Rules
-----
* A batch changes ONE sheet, named by ``sheet_id``. add_sheet, delete_sheet
  and rename_sheet name their own sheet and must be alone in their batch.
* At most MAX_BATCH_SIZE changes per batch; a cell in set_cells counts as one.
* Everything that can be checked without touching the document is checked
  first (shape, types, IDs that never existed, column-name clashes). Nothing
  is applied if that fails.
* A change to something somebody else has already deleted (an ID that existed
  once) is DROPPED, not an error: the rest of the batch still applies and the
  sender is told which changes were dropped.
* If a change fails after others in the same batch were applied, which the
  checks above are meant to make impossible, the caller records a resync so
  every client reloads rather than trusting a half-applied batch.

This module has no web-framework dependency.
"""

from __future__ import annotations

import math
from dataclasses import dataclass, field
from typing import Any

MAX_BATCH_SIZE = 500
MAX_ID_LENGTH = 64
MAX_NAME_LENGTH = 255

# Codes a client can show a friendly message for.
BAD_REQUEST = "BAD_REQUEST"
EMPTY_BATCH = "EMPTY_BATCH"
BATCH_TOO_LARGE = "BATCH_TOO_LARGE"
UNKNOWN_SHEET = "UNKNOWN_SHEET"
UNKNOWN_ROW = "UNKNOWN_ROW"
UNKNOWN_COLUMN = "UNKNOWN_COLUMN"
NAME_TAKEN = "NAME_TAKEN"
INVALID_VALUE = "INVALID_VALUE"
REVISION_FROM_FUTURE = "REVISION_FROM_FUTURE"
APPLY_FAILED = "APPLY_FAILED"

# Reasons a single change is dropped.
SHEET_DELETED = "SHEET_DELETED"
ROW_DELETED = "ROW_DELETED"
COLUMN_DELETED = "COLUMN_DELETED"

SHEET_OPS = {"add_sheet", "delete_sheet", "rename_sheet"}

# A cell value is what the person typed (text), or null to clear the cell.
# The document turns text such as "7" into a number where the column is
# numeric. Raw numbers and booleans are refused: a text column can't hold
# them, and failing there (after other changes in the batch were applied) is
# exactly what the up-front checks exist to prevent.
_CELL_VALUE_TYPES = (str, type(None))


class OpError(Exception):
    """A batch is refused. ``code`` is for programs, ``message`` for logs."""

    def __init__(self, code: str, message: str, index: int | None = None, resync_required: bool = False):
        super().__init__(message)
        self.code = code
        self.message = message
        self.index = index
        self.resync_required = resync_required


@dataclass(frozen=True)
class Batch:

    client_batch_id: str
    base_revision: int
    sheet_id: str | None
    ops: list[dict[str, Any]]


@dataclass
class Outcome:

    applied: list[dict[str, Any]] = field(default_factory=list)
    dropped: list[dict[str, Any]] = field(default_factory=list)
    sheet_id: str | None = None


# ----------------------------------------------------------------------
# Reading and checking a batch
# ----------------------------------------------------------------------

def _is_text(value: object, limit: int = MAX_NAME_LENGTH) -> bool:
    return isinstance(value, str) and 0 < len(value) <= limit


def _is_id(value: object) -> bool:
    return _is_text(value, MAX_ID_LENGTH)


def _is_int(value: object) -> bool:
    return isinstance(value, int) and not isinstance(value, bool)


def _bad(message: str, index: int | None = None) -> OpError:
    return OpError(BAD_REQUEST, message, index)


def _only_keys(op: dict[str, Any], allowed: set[str], index: int) -> None:
    extra = set(op) - allowed - {"op"}

    if extra:
        raise _bad(f"Unknown field(s) in {op.get('op')}: {', '.join(sorted(extra))}.", index)


def _check_op(op: Any, index: int) -> int:
    """Check one operation's shape. Returns how many changes it counts as."""
    if not isinstance(op, dict):
        raise _bad("Each operation must be an object.", index)

    kind = op.get("op")

    if kind == "set_cells":
        _only_keys(op, {"cells"}, index)
        cells = op.get("cells")

        if not isinstance(cells, list) or not cells:
            raise _bad("set_cells needs a non-empty list of cells.", index)

        for cell in cells:
            if not isinstance(cell, dict) or set(cell) != {"row", "column", "value"}:
                raise _bad("Each cell needs exactly row, column and value.", index)

            if not _is_id(cell["row"]) or not _is_id(cell["column"]):
                raise _bad("A cell's row and column must be IDs.", index)

            value = cell["value"]

            if not isinstance(value, _CELL_VALUE_TYPES):
                raise OpError(INVALID_VALUE, "A cell value must be text, or null to clear the cell.", index)

        return len(cells)

    if kind == "insert_row":
        _only_keys(op, {"before"}, index)

        if op.get("before") is not None and not _is_id(op.get("before")):
            raise _bad("insert_row 'before' must be a row ID or null.", index)

    elif kind == "delete_row":
        _only_keys(op, {"row"}, index)

        if not _is_id(op.get("row")):
            raise _bad("delete_row needs a row ID.", index)

    elif kind == "insert_column":
        _only_keys(op, {"name", "before"}, index)

        if not _is_text(op.get("name")) or not op["name"].strip():
            raise _bad("insert_column needs a name.", index)

        if op.get("before") is not None and not _is_id(op.get("before")):
            raise _bad("insert_column 'before' must be a column ID or null.", index)

    elif kind == "delete_column":
        _only_keys(op, {"column"}, index)

        if not _is_id(op.get("column")):
            raise _bad("delete_column needs a column ID.", index)

    elif kind == "rename_column":
        _only_keys(op, {"column", "name"}, index)

        if not _is_id(op.get("column")) or not _is_text(op.get("name")) or not op["name"].strip():
            raise _bad("rename_column needs a column ID and a new name.", index)

    elif kind == "set_column_width":
        _only_keys(op, {"column", "width"}, index)
        width = op.get("width")

        if not _is_id(op.get("column")):
            raise _bad("set_column_width needs a column ID.", index)

        if isinstance(width, bool) or not isinstance(width, (int, float)) or not math.isfinite(width) or not 0 < width <= 1000:
            raise OpError(INVALID_VALUE, "A column width must be a number above 0 and at most 1000.", index)

    elif kind == "set_rtl":
        _only_keys(op, {"value"}, index)

        if not isinstance(op.get("value"), bool):
            raise _bad("set_rtl needs true or false.", index)

    elif kind == "add_sheet":
        _only_keys(op, {"name"}, index)

        if not _is_text(op.get("name")) or not op["name"].strip():
            raise _bad("add_sheet needs a name.", index)

    elif kind == "delete_sheet":
        _only_keys(op, {"sheet"}, index)

        if not _is_id(op.get("sheet")):
            raise _bad("delete_sheet needs a sheet ID.", index)

    elif kind == "rename_sheet":
        _only_keys(op, {"sheet", "name"}, index)

        if not _is_id(op.get("sheet")) or not _is_text(op.get("name")) or not op["name"].strip():
            raise _bad("rename_sheet needs a sheet ID and a new name.", index)

    else:
        raise _bad(f"Unknown operation: {kind!r}.", index)

    return 1


def parse_batch(payload: Any) -> Batch:
    """Check a batch's shape and size. Raises OpError; applies nothing."""
    if not isinstance(payload, dict):
        raise _bad("The request must be an object.")

    client_batch_id = payload.get("client_batch_id")

    if not _is_id(client_batch_id):
        raise _bad("client_batch_id is required (the client makes one up per batch).")

    base_revision = payload.get("base_revision", 0)

    if not _is_int(base_revision) or base_revision < 0:
        raise _bad("base_revision must be a whole number, 0 or more.")

    ops = payload.get("ops")

    if not isinstance(ops, list):
        raise _bad("ops must be a list.")

    if not ops:
        raise OpError(EMPTY_BATCH, "A batch needs at least one operation.")

    sheet_id = payload.get("sheet_id")

    if sheet_id is not None and not _is_id(sheet_id):
        raise _bad("sheet_id must be a sheet ID.")

    size = sum(_check_op(op, index) for index, op in enumerate(ops))

    if size > MAX_BATCH_SIZE:
        raise OpError(BATCH_TOO_LARGE, f"A batch can hold at most {MAX_BATCH_SIZE} changes; this one has {size}.")

    kinds = {op["op"] for op in ops}

    if kinds & SHEET_OPS:
        if len(ops) != 1:
            raise _bad("add_sheet, delete_sheet and rename_sheet must be alone in their batch.")
    elif sheet_id is None:
        raise _bad("sheet_id is required.")

    return Batch(client_batch_id=client_batch_id, base_revision=base_revision, sheet_id=sheet_id, ops=ops)


# ----------------------------------------------------------------------
# Applying a batch
# ----------------------------------------------------------------------

def _document(controller):
    return controller.document


def _find_sheet(document, sheet_id: str):
    for sheet in document.spreadsheet.sheets:
        if sheet.sheet_id == sheet_id:
            return sheet

    return None


def apply_batch(controller, batch: Batch) -> Outcome:
    """Apply ``batch`` to the controller's document and return what happened.

    The caller holds the session lock. Raises OpError if the batch is refused
    before anything changed (nothing applied), or with resync_required=True
    if it failed part-way.
    """
    document = _document(controller)

    if not controller.is_loaded():
        raise OpError(APPLY_FAILED, "No document is open.")

    kinds = {op["op"] for op in batch.ops}

    if kinds & SHEET_OPS:
        return _apply_sheet_op(controller, batch.ops[0])

    sheet = _find_sheet(document, batch.sheet_id)

    if sheet is None:
        if document.sheet_id_was_issued(batch.sheet_id):
            return Outcome(
                dropped=[_drop(i, SHEET_DELETED) for i in range(len(batch.ops))],
                sheet_id=batch.sheet_id,
            )

        raise OpError(UNKNOWN_SHEET, f"There is no sheet {batch.sheet_id}.")

    _check_never_existed(sheet, batch.ops)
    _check_column_names(sheet, batch.ops)

    return _on_sheet(controller, batch, sheet)


def _drop(index: int, reason: str, detail: dict[str, Any] | None = None) -> dict[str, Any]:
    notice = {"index": index, "reason": reason}

    if detail:
        notice.update(detail)

    return notice


def _check_never_existed(sheet, ops: list[dict[str, Any]]) -> None:
    """Refuse IDs that were never handed out (a bug or a forged request).

    An ID that existed and was deleted is not an error here; that is a drop.
    """
    sheet.ensure_ids()
    rows = set(sheet.row_ids)
    columns = set(sheet.column_ids.values())

    def check_row(row_id: str, index: int) -> None:
        if row_id not in rows and not sheet.row_id_was_issued(row_id):
            raise OpError(UNKNOWN_ROW, f"There is no row {row_id}.", index)

    def check_column(column_id: str, index: int) -> None:
        if column_id not in columns and not sheet.column_id_was_issued(column_id):
            raise OpError(UNKNOWN_COLUMN, f"There is no column {column_id}.", index)

    for index, op in enumerate(ops):
        kind = op["op"]

        if kind == "set_cells":
            for cell in op["cells"]:
                check_row(cell["row"], index)
                check_column(cell["column"], index)
        elif kind == "insert_row" and op["before"] is not None:
            check_row(op["before"], index)
        elif kind == "delete_row":
            check_row(op["row"], index)
        elif kind == "insert_column" and op.get("before") is not None:
            check_column(op["before"], index)
        elif kind in ("delete_column", "rename_column", "set_column_width"):
            check_column(op["column"], index)


def _check_column_names(sheet, ops: list[dict[str, Any]]) -> None:
    """Catch a column-name clash before anything is applied.

    Walks the batch with a stand-in for the column names, so a batch that
    deletes a column and then re-adds the name is judged correctly.
    """
    names = {name: identifier for name, identifier in sheet.column_ids.items()}

    for index, op in enumerate(ops):
        kind = op["op"]

        if kind == "insert_column":
            if op["name"] in names:
                raise OpError(NAME_TAKEN, f"There is already a column called {op['name']!r}.", index)

            names[op["name"]] = None

        elif kind == "delete_column":
            for name, identifier in list(names.items()):
                if identifier == op["column"]:
                    del names[name]

        elif kind == "rename_column":
            current = next((n for n, i in names.items() if i == op["column"]), None)

            if current is None:
                continue                                  # deleted earlier: dropped at apply time

            if op["name"] != current and op["name"] in names:
                raise OpError(NAME_TAKEN, f"There is already a column called {op['name']!r}.", index)

            names[op["name"]] = names.pop(current)


def _clear_server_view(controller) -> None:
    """Make the server's view the whole sheet, in natural order.

    The controller edits by position in the server's current view. Clients
    now search and sort on their own side, but an older client may have left
    a server-side search or sort on; applying changes by ID needs row N of
    the view to be row N of the sheet.
    """
    document = _document(controller)

    if document.search_text:
        controller.clear_search()

    if document.sort_rules:
        controller.clear_sort()


def _on_sheet(controller, batch: Batch, sheet) -> Outcome:
    """Apply a batch to ``sheet``, switching to it if it is not the open sheet,
    and switching back afterwards."""
    document = _document(controller)
    original_name = controller.current_sheet()
    switched = sheet.name != original_name

    if switched and not controller.set_sheet(sheet.name):
        raise OpError(APPLY_FAILED, "Could not switch to the sheet.")

    try:
        _clear_server_view(controller)
        active = document.spreadsheet.current_sheet()
        return _apply_to_active(controller, batch, active)
    finally:
        if switched and original_name in controller.sheets():
            controller.set_sheet(original_name)


def _apply_to_active(controller, batch: Batch, sheet) -> Outcome:
    outcome = Outcome(sheet_id=sheet.sheet_id)
    started = False                     # whether anything has been changed yet

    for index, op in enumerate(batch.ops):
        try:
            applied = _APPLY[op["op"]](controller, sheet, op, index, outcome)
        except OpError:
            raise
        except Exception as error:                        # an unexpected failure
            raise OpError(APPLY_FAILED, f"Operation {index} failed: {error}", index, resync_required=started) from error

        if applied is None:
            continue

        if applied is False:
            raise OpError(APPLY_FAILED, f"Operation {index} could not be applied.", index, resync_required=started)

        outcome.applied.append(applied)
        started = True

    return outcome


def _apply_set_cells(controller, sheet, op, index, outcome):
    positions = sheet.row_positions()
    headers = list(sheet.dataframe.columns)
    edits, kept = [], []

    for cell in op["cells"]:
        position = positions.get(cell["row"])

        if position is None:
            outcome.dropped.append(_drop(index, ROW_DELETED, {"row": cell["row"]}))
            continue

        name = sheet.column_name(cell["column"])

        if name is None:
            outcome.dropped.append(_drop(index, COLUMN_DELETED, {"column": cell["column"]}))
            continue

        edits.append((position, headers.index(name), cell["value"]))
        kept.append(cell)

    if not edits:
        return None

    if not controller.edit_cells(edits):
        return False

    return {"op": "set_cells", "cells": kept}


def _apply_insert_row(controller, sheet, op, index, outcome):
    before = op["before"]

    if before is None:
        before_count = len(sheet.row_ids)

        if not controller.append_row():
            return False
    else:
        position = sheet.row_position(before)

        if position is None:
            outcome.dropped.append(_drop(index, ROW_DELETED, {"row": before}))
            return None

        if not controller.insert_row(position):
            return False

    sheet.ensure_ids()
    new_position = len(sheet.row_ids) - 1 if before is None else sheet.row_position(before) - 1
    return {"op": "insert_row", "before": before, "id": sheet.row_ids[new_position]}


def _apply_delete_row(controller, sheet, op, index, outcome):
    position = sheet.row_position(op["row"])

    if position is None:
        outcome.dropped.append(_drop(index, ROW_DELETED, {"row": op["row"]}))
        return None

    if not controller.delete_row(position):
        return False

    return {"op": "delete_row", "row": op["row"]}


def _apply_insert_column(controller, sheet, op, index, outcome):
    before = op.get("before")
    position = None

    if before is not None:
        name = sheet.column_name(before)

        if name is None:
            outcome.dropped.append(_drop(index, COLUMN_DELETED, {"column": before}))
            return None

        position = list(sheet.dataframe.columns).index(name)

    if not controller.insert_column(op["name"], position):
        return False

    return {"op": "insert_column", "name": op["name"], "before": before, "id": sheet.column_id(op["name"])}


def _apply_delete_column(controller, sheet, op, index, outcome):
    name = sheet.column_name(op["column"])

    if name is None:
        outcome.dropped.append(_drop(index, COLUMN_DELETED, {"column": op["column"]}))
        return None

    if not controller.delete_column(name):
        return False

    return {"op": "delete_column", "column": op["column"]}


def _apply_rename_column(controller, sheet, op, index, outcome):
    name = sheet.column_name(op["column"])

    if name is None:
        outcome.dropped.append(_drop(index, COLUMN_DELETED, {"column": op["column"]}))
        return None

    if not controller.rename_column(name, op["name"]):
        return False

    return {"op": "rename_column", "column": op["column"], "name": op["name"]}


def _apply_set_column_width(controller, sheet, op, index, outcome):
    name = sheet.column_name(op["column"])

    if name is None:
        outcome.dropped.append(_drop(index, COLUMN_DELETED, {"column": op["column"]}))
        return None

    if not controller.set_column_width(name, float(op["width"])):
        return False

    return {"op": "set_column_width", "column": op["column"], "width": op["width"]}


def _apply_set_rtl(controller, sheet, op, index, outcome):
    if not controller.set_rtl(op["value"]):
        return False

    return {"op": "set_rtl", "value": op["value"]}


_APPLY = {
    "set_cells": _apply_set_cells,
    "insert_row": _apply_insert_row,
    "delete_row": _apply_delete_row,
    "insert_column": _apply_insert_column,
    "delete_column": _apply_delete_column,
    "rename_column": _apply_rename_column,
    "set_column_width": _apply_set_column_width,
    "set_rtl": _apply_set_rtl,
}


# ----------------------------------------------------------------------
# Sheet-level operations (alone in their batch)
# ----------------------------------------------------------------------

def _apply_sheet_op(controller, op: dict[str, Any]) -> Outcome:
    document = _document(controller)
    kind = op["op"]

    if kind == "add_sheet":
        original_name = controller.current_sheet()

        if op["name"] in controller.sheets():
            raise OpError(NAME_TAKEN, f"There is already a sheet called {op['name']!r}.", 0)

        if not controller.add_sheet(op["name"]):
            raise OpError(APPLY_FAILED, "Could not add the sheet.", 0)

        new_id = controller.current_sheet_id()

        # add_sheet opens the new sheet; put the open sheet back, since the
        # open sheet is shared state older clients rely on.
        if original_name in controller.sheets() and original_name != op["name"]:
            controller.set_sheet(original_name)

        return Outcome(applied=[{"op": "add_sheet", "name": op["name"], "id": new_id}])

    sheet = _find_sheet(document, op["sheet"])

    if sheet is None:
        if document.sheet_id_was_issued(op["sheet"]):
            return Outcome(dropped=[_drop(0, SHEET_DELETED, {"sheet": op["sheet"]})])

        raise OpError(UNKNOWN_SHEET, f"There is no sheet {op['sheet']}.", 0)

    if kind == "delete_sheet":
        if len(controller.sheets()) == 1:
            raise OpError(APPLY_FAILED, "The last sheet can't be deleted.", 0)

        if not controller.delete_sheet(sheet.name):
            raise OpError(APPLY_FAILED, "Could not delete the sheet.", 0)

        return Outcome(applied=[{"op": "delete_sheet", "sheet": op["sheet"]}])

    # rename_sheet
    if op["name"] != sheet.name and op["name"] in controller.sheets():
        raise OpError(NAME_TAKEN, f"There is already a sheet called {op['name']!r}.", 0)

    if not controller.rename_sheet(sheet.name, op["name"]):
        raise OpError(APPLY_FAILED, "Could not rename the sheet.", 0)

    return Outcome(applied=[{"op": "rename_sheet", "sheet": op["sheet"], "name": op["name"]}])
