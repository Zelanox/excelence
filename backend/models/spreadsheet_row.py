from dataclasses import dataclass, field
from typing import Any


@dataclass(slots=True)
class SpreadsheetRow:

    values: dict[str, Any] = field(default_factory=dict)
