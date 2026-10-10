"""Sheet-level display settings that aren't cell content.

Unlike CellStyle (real Excel cell fonts and fills), these have no Excel
equivalent - Excel's banded rows are a table feature and its grid color is
limited to an indexed palette - so they are stored in a hidden name in the
workbook that only Excelence reads (see Document). They are settings, not
edits: they aren't part of undo history.
"""

from __future__ import annotations

import re
from dataclasses import dataclass
from typing import Any

FIELDS = ("grid_color", "banding", "banding_color")

_COLOR_PATTERN = re.compile(r"^#?([0-9a-fA-F]{6})$")


def _normalize(name: str, value: Any) -> tuple[bool, Any]:
    if name == "banding":
        return (True, value) if isinstance(value, bool) else (False, None)

    if name in ("grid_color", "banding_color"):
        if not isinstance(value, str):
            return False, None

        match = _COLOR_PATTERN.match(value.strip())

        if match is None:
            return False, None

        return True, match.group(1).upper()

    return False, None


@dataclass(slots=True)
class SheetAppearance:

    grid_color: str | None = None       # "RRGGBB"; None = the built-in grid color
    banding: bool | None = None         # alternating row colors on/off; None = off
    banding_color: str | None = None    # "RRGGBB" for the alternate rows

    def is_empty(self) -> bool:
        return all(getattr(self, name) is None for name in FIELDS)

    def copy(self) -> "SheetAppearance":
        return SheetAppearance(**{name: getattr(self, name) for name in FIELDS})

    def to_dict(self) -> dict[str, Any]:
        return {
            name: getattr(self, name)
            for name in FIELDS
            if getattr(self, name) is not None
        }

    @classmethod
    def from_dict(cls, data: Any) -> "SheetAppearance":
        """Lenient: bad fields are dropped so a foreign file still opens."""
        appearance = cls()

        if not isinstance(data, dict):
            return appearance

        for name in FIELDS:
            if name not in data or data[name] is None:
                continue

            ok, value = _normalize(name, data[name])

            if ok:
                setattr(appearance, name, value)

        return appearance

    def apply_patch(
        self,
        values: dict[str, Any] | None,
        reset: list[str] | None = None,
    ) -> "SheetAppearance | None":
        """Return a copy with ``values`` set and ``reset`` cleared, or None if invalid."""
        values = values or {}
        reset = reset or []

        if not isinstance(values, dict) or not isinstance(reset, (list, tuple)):
            return None

        updated = self.copy()

        for name in reset:
            if name not in FIELDS or name in values:
                return None

            setattr(updated, name, None)

        for name, value in values.items():
            if name not in FIELDS:
                return None

            ok, normalized = _normalize(name, value)

            if not ok:
                return None

            setattr(updated, name, normalized)

        return updated
