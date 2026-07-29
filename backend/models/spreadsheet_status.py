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