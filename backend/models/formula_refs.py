"""Keeping stored formulas pointing at the right cells when rows or columns move.

Formulas are stored as text (``=SUM(B2:B5)``) and refer to cells by column
letter and row number, exactly as the client's formula engine reads them:
``A`` is the first data column, row ``1`` is the first data row. When a row
or column is inserted or deleted, every reference that points past the
change has to move with its data - otherwise ``=A1+A2`` would quietly start
adding different cells after someone inserts a row above.

The grammar is deliberately small (matching the client's engine): numbers,
``+ - * /``, parentheses, functions (``SUM`` ...), single references
(``B3``) and ranges (``A1:B5``). There are no absolute (``$``) references,
no strings and no cross-sheet references, so a regular expression is enough.

Rules, in terms of 0-based positions (``p`` is where the change happens):

* insert at ``p``  - anything at or after ``p`` moves down/right by one. A
  range that spans ``p`` therefore grows; one that ends before it is
  untouched.
* delete at ``p`` - anything after ``p`` moves up/left by one. A reference
  to the deleted cell becomes ``#REF!`` (which the engine reports as an
  error). A range loses just that row/column: it shrinks, and only if the
  whole range was the deleted row/column does it become ``#REF!``.
"""

from __future__ import annotations

import re
from dataclasses import dataclass

REF_ERROR = "#REF!"

_REF = r"([A-Z]+)([1-9][0-9]*)"

# One reference or one range. Not preceded by a letter/digit/underscore/dot
# (so it isn't the tail of some other word or number) and not followed by a
# letter/digit/underscore or "(" (so a function name such as LOG10( isn't
# read as a cell).
_PATTERN = re.compile(rf"(?<![A-Za-z0-9_.#]){_REF}(?::{_REF})?(?![A-Za-z0-9_(])")


@dataclass(frozen=True)
class RefChange:
    """One structural change, in formula coordinates."""

    axis: str       # "row" or "column"
    kind: str       # "insert" or "delete"
    index: int      # 0-based position of the inserted / deleted row or column

    def __post_init__(self) -> None:
        if self.axis not in ("row", "column") or self.kind not in ("insert", "delete"):
            raise ValueError("axis must be row/column and kind insert/delete")

        if self.index < 0:
            raise ValueError("index must not be negative")


def column_index(letters: str) -> int:
    """'A' -> 0, 'Z' -> 25, 'AA' -> 26."""
    value = 0

    for character in letters:
        value = value * 26 + (ord(character) - 64)

    return value - 1


def column_letters(index: int) -> str:
    """0 -> 'A', 25 -> 'Z', 26 -> 'AA'."""
    value = index + 1
    letters = ""

    while value > 0:
        value, remainder = divmod(value - 1, 26)
        letters = chr(65 + remainder) + letters

    return letters


def _shift_single(position: int, change: RefChange) -> int | None:
    """New position of one cell coordinate, or None if it was deleted."""
    if change.kind == "insert":
        return position + 1 if position >= change.index else position

    if position == change.index:
        return None

    return position - 1 if position > change.index else position


def _shift_range(low: int, high: int, change: RefChange) -> tuple[int, int] | None:
    """New (low, high) of a range's extent along the changed axis, or None."""
    if change.kind == "insert":
        return (
            low + 1 if low >= change.index else low,
            high + 1 if high >= change.index else high,
        )

    if low == high == change.index:
        return None

    # A start inside/after the deleted slot moves up only if it is past it; a
    # start ON it stays (the next row/column slides into that position). An
    # end ON or past it always moves up.
    return (
        low - 1 if low > change.index else low,
        high - 1 if high >= change.index else high,
    )


def _rewrite(match: re.Match[str], change: RefChange) -> str:
    start_letters, start_row, end_letters, end_row = match.groups()

    start = (column_index(start_letters), int(start_row) - 1)

    if end_letters is None:
        column, row = start
        moved = _shift_single(row if change.axis == "row" else column, change)

        if moved is None:
            return REF_ERROR

        if change.axis == "row":
            row = moved
        else:
            column = moved

        return f"{column_letters(column)}{row + 1}"

    end = (column_index(end_letters), int(end_row) - 1)

    # Work on the extent along the changed axis; the engine accepts a range
    # written backwards (B5:A1), so keep each endpoint's own order.
    axis = 1 if change.axis == "row" else 0
    low, high = sorted((start[axis], end[axis]))
    shifted = _shift_range(low, high, change)

    if shifted is None:
        return REF_ERROR

    new_low, new_high = shifted
    start_is_low = start[axis] <= end[axis]
    new_start_axis, new_end_axis = (new_low, new_high) if start_is_low else (new_high, new_low)

    new_start = list(start)
    new_end = list(end)
    new_start[axis] = new_start_axis
    new_end[axis] = new_end_axis

    return (
        f"{column_letters(new_start[0])}{new_start[1] + 1}:"
        f"{column_letters(new_end[0])}{new_end[1] + 1}"
    )


def adjust_formula(formula: str, change: RefChange) -> str:
    """Rewrite the references in ``formula`` for ``change``.

    Anything that isn't a formula (doesn't start with ``=``) is returned
    unchanged, so callers can pass any cell value.
    """
    if not isinstance(formula, str) or not formula.startswith("="):
        return formula

    return _PATTERN.sub(lambda match: _rewrite(match, change), formula)
