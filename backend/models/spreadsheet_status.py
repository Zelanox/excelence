from dataclasses import dataclass


@dataclass(slots=True)
class SpreadsheetStatus:

    filename: str

    loaded: bool

    modified: bool

    rows: int

    columns: int