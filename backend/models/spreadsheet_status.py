
from dataclasses import dataclass, field
from typing import Any



@dataclass(slots=True)
class SpreadsheetStatus:

    filename: str

    loaded: bool

    modified: bool

    rows: int

    columns: int


@dataclass(slots=True)
class SpreadsheetData:

    headers: list[str] = field(default_factory=list)

    rows: list[dict[str, Any]] = field(default_factory=list)

    row_count: int = 0

    column_count: int = 0

    column_widths: dict[str, float] = field(default_factory=dict)

    rtl: bool = False

    # Stable IDs, parallel to ``rows`` and ``headers``: row_ids[n] names
    # rows[n], column_ids[n] names headers[n]. Unlike a row number or a
    # column name they do not change when other rows are inserted or
    # deleted, or when a column is renamed.
    row_ids: list[str] = field(default_factory=list)
    column_ids: list[str] = field(default_factory=list)

    # ID of the sheet this grid belongs to (see Sheet.sheet_id).
    sheet_id: str = ""

    # Per-cell text-style overrides, in VIEW coordinates (the row/column a
    # client sees in the current filtered/sorted grid): a list of
    # {"row": int, "column": int, "style": {...set fields only...}}.
    cell_styles: list[dict[str, Any]] = field(default_factory=list)

    # The sheet-wide default text style (set fields only).
    text_defaults: dict[str, Any] = field(default_factory=dict)

    # Sheet-level display settings (grid color, alternating rows).
    appearance: dict[str, Any] = field(default_factory=dict)

    # How many undo / redo steps the backend currently holds. Clients keep
    # their own local history for instant feedback; comparing these counts
    # against it is how a client notices the two have drifted apart.
    undo_depth: int = 0
    redo_depth: int = 0


@dataclass(slots=True)
class SpreadsheetSheet:

    name: str

    active: bool = False


@dataclass(slots=True)
class DocumentInfo:

    filename: str

    loaded: bool

    modified: bool

    rows: int

    columns: int

    sheets: list[str] = field(default_factory=list)

    current_sheet: str = ""
