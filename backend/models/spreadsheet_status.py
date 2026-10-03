
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

    # Per-cell text-style overrides, in VIEW coordinates (the row/column a
    # client sees in the current filtered/sorted grid): a list of
    # {"row": int, "column": int, "style": {...set fields only...}}.
    cell_styles: list[dict[str, Any]] = field(default_factory=list)

    # The sheet-wide default text style (set fields only).
    text_defaults: dict[str, Any] = field(default_factory=dict)


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
