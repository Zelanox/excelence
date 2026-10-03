"""Text styling for spreadsheet cells.

A CellStyle is a *partial* style: every field is optional, and ``None``
means "not set here - inherit". The same type is used at two levels:

* ``Sheet.text_defaults`` - the sheet-wide default text style.
* ``Sheet.cell_styles``   - per-cell overrides on top of that default.

A cell's effective style is its override merged over the sheet default
(see :meth:`CellStyle.merged_over`), and anything still unset after that
falls through to the application/Excel baseline.
"""

from __future__ import annotations

import re
from dataclasses import dataclass
from typing import Any

BOOL_FIELDS = ("bold", "italic", "underline", "strikethrough")
FIELDS = BOOL_FIELDS + ("font_family", "font_size", "color")

MAX_FAMILY_LENGTH = 64
MIN_FONT_SIZE = 1.0
MAX_FONT_SIZE = 409.0  # Excel's own upper bound for a font size.

_COLOR_PATTERN = re.compile(r"^#?([0-9a-fA-F]{6})$")


def _normalize_field(name: str, value: Any) -> tuple[bool, Any]:
    """Validate and normalize one field value.

    Returns ``(ok, normalized)``. ``ok`` is False for any invalid value -
    callers treat that as a rejected request rather than coercing it.
    """
    if name in BOOL_FIELDS:
        if isinstance(value, bool):
            return True, value
        return False, None

    if name == "font_family":
        if not isinstance(value, str):
            return False, None

        family = value.strip()

        if not family or len(family) > MAX_FAMILY_LENGTH:
            return False, None

        if any(ord(char) < 32 for char in family):
            return False, None

        return True, family

    if name == "font_size":
        if isinstance(value, bool) or not isinstance(value, (int, float)):
            return False, None

        size = float(value)

        # NaN fails both comparisons below only via the explicit check.
        if size != size or size < MIN_FONT_SIZE or size > MAX_FONT_SIZE:
            return False, None

        return True, size

    if name == "color":
        if not isinstance(value, str):
            return False, None

        match = _COLOR_PATTERN.match(value.strip())

        if match is None:
            return False, None

        return True, match.group(1).upper()

    return False, None


@dataclass(slots=True)
class CellStyle:

    bold: bool | None = None
    italic: bool | None = None
    underline: bool | None = None
    strikethrough: bool | None = None
    font_family: str | None = None
    font_size: float | None = None
    color: str | None = None  # "RRGGBB", upper-case, no leading "#".

    def is_empty(self) -> bool:
        return all(getattr(self, name) is None for name in FIELDS)

    def copy(self) -> "CellStyle":
        return CellStyle(**{name: getattr(self, name) for name in FIELDS})

    def to_dict(self) -> dict[str, Any]:
        """Only the fields that are set - an empty style is ``{}``."""
        return {
            name: getattr(self, name)
            for name in FIELDS
            if getattr(self, name) is not None
        }

    @classmethod
    def from_dict(cls, data: Any) -> "CellStyle":
        """Lenient constructor for data read back from a file.

        Unlike :meth:`apply_patch`, bad fields are dropped instead of
        rejecting the whole thing - a hand-edited or foreign file must
        never stop a workbook from opening.
        """
        style = cls()

        if not isinstance(data, dict):
            return style

        for name in FIELDS:
            if name not in data or data[name] is None:
                continue

            ok, value = _normalize_field(name, data[name])

            if ok:
                setattr(style, name, value)

        return style

    def apply_patch(
        self,
        values: dict[str, Any] | None,
        reset: list[str] | None = None,
    ) -> "CellStyle | None":
        """Return a new style with ``values`` set and ``reset`` cleared.

        ``values`` sets fields; ``reset`` returns fields to "inherit".
        Returns ``None`` if anything is invalid (unknown field, bad value,
        or a field both set and reset) so a request is all-or-nothing.
        """
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

            ok, normalized = _normalize_field(name, value)

            if not ok:
                return None

            setattr(updated, name, normalized)

        return updated

    def merged_over(self, base: "CellStyle") -> "CellStyle":
        """This style's set fields win; unset ones fall back to ``base``."""
        return CellStyle(**{
            name: (
                getattr(self, name)
                if getattr(self, name) is not None
                else getattr(base, name)
            )
            for name in FIELDS
        })
