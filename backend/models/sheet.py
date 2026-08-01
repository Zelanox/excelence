from dataclasses import dataclass, field

from backend.models.spreadsheet_row import SpreadsheetRow


@dataclass(slots=True)
class Sheet:

    name: str

    rows: list[SpreadsheetRow] = field(default_factory=list)