from dataclasses import dataclass, field

from backend.models.sheet import Sheet


@dataclass(slots=True)
class Spreadsheet:

    sheets: list[Sheet] = field(default_factory=list)