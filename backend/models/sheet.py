import math
import re
from collections.abc import Callable
from dataclasses import dataclass, field
from typing import Any

import pandas as pd

from backend.models.cell_style import NO_FILL, CellStyle
from backend.models.formula_refs import RefChange, adjust_formula
from backend.models.sheet_appearance import SheetAppearance
from backend.models.spreadsheet_row import SpreadsheetRow
from backend.models.spreadsheet_status import SpreadsheetData
from backend.services.search_service import SearchService
from backend.services.sort_service import SortService


@dataclass(slots=True)
class SheetSnapshot:
    """An exact copy of the parts of a sheet that undo/redo rewinds.

    Deliberately limited to content: the cells (with their exact pandas
    types), per-cell styles, and column widths. Direction (RTL) and the
    sheet's default text style are settings, not edits, so undo leaves
    them as they are.
    """

    dataframe: pd.DataFrame
    cell_styles: dict[int, dict[str, CellStyle]]
    column_widths: dict[str, float]
    # Row and column IDs travel with the content they name, so undoing a
    # delete brings the same row (and the same ID) back.
    row_ids: list[str] = field(default_factory=list)
    column_ids: dict[str, str] = field(default_factory=dict)


@dataclass(slots=True)
class Sheet:

    name: str

    rows: list[SpreadsheetRow] = field(default_factory=list)
    dataframe: pd.DataFrame = field(default_factory=lambda: pd.DataFrame())
    worksheet: Any = None
    active_view: pd.DataFrame | None = None
    search_text: str = ""
    sort_rules: list[dict[str, Any]] = field(default_factory=list)
    # Keyed by column name (not index/letter) so a resize survives an
    # unrelated insert/delete elsewhere in the sheet, consistent with how
    # every other per-column operation here (rename/delete) identifies
    # columns. Populated from the workbook's own column_dimensions on
    # load and written back the same way on save - see Document.
    column_widths: dict[str, float] = field(default_factory=dict)
    # Mirrors the worksheet's native sheet_view.rightToLeft (a real
    # Excel/openpyxl property, not invented here) - round-trips through
    # save/load the same way column_widths does. Deliberately does NOT
    # reorder dataframe/active_view columns: every index-based backend
    # operation (insert/delete-by-index, column_widths' position-based
    # letter mapping, search, sort) stays correct against the sheet's
    # true logical column order regardless of this flag. Only the
    # frontend's rendering reverses visual column order and flips the
    # row-number column side when this is true - see SheetModel.isRtl /
    # SpreadsheetGrid on the frontend.
    rtl: bool = False
    # Sheet-wide default text style, and per-cell overrides on top of it.
    # Overrides are keyed [dataframe row position][column NAME] - names
    # rather than indices for the same reason column_widths is, and row
    # POSITIONS (not view rows) so they stay attached to the right data
    # through search/sort. Every structural edit below (insert/delete
    # row, delete/rename column) keeps this in step with the dataframe -
    # it is a third parallel representation, same hazard as the
    # workbook/spreadsheet pair, so any new structural operation must
    # update it too. Persisted as real cell fonts - see Document.
    text_defaults: CellStyle = field(default_factory=CellStyle)
    # Sheet-level display settings (grid color, alternating rows): not
    # cell content, not part of undo. See SheetAppearance.
    appearance: SheetAppearance = field(default_factory=SheetAppearance)
    cell_styles: dict[int, dict[str, CellStyle]] = field(default_factory=dict)
    # Stable identifiers, assigned by the server, so that a change can name
    # a row or column independently of where it currently sits.
    #
    # row_ids is parallel to the dataframe: row_ids[n] names dataframe row
    # POSITION n. column_ids maps a column NAME to its ID. Storage stays
    # keyed by position / name (cell_styles, column_widths, formulas); the
    # IDs are a translation layer on top, and every structural edit below
    # keeps them in step. This is one more parallel representation, so
    # any new structural operation must update it too (see ensure_ids).
    #
    # IDs are reassigned every time a document is loaded and are never
    # reused within a session: the counters below only go up and are
    # deliberately NOT part of a snapshot, so undo cannot rewind them.
    row_ids: list[str] = field(default_factory=list)
    column_ids: dict[str, str] = field(default_factory=dict)
    next_row_number: int = field(default=1, repr=False, compare=False)
    next_column_number: int = field(default=1, repr=False, compare=False)
    search_service: SearchService = field(default_factory=SearchService, repr=False, compare=False)
    sort_service: SortService = field(default_factory=SortService, repr=False, compare=False)

    def __post_init__(self) -> None:
        if self.active_view is None:
            self.active_view = self.dataframe

        self.ensure_ids()

    @property
    def row_count(self) -> int:
        view = self.active_view if self.active_view is not None else self.dataframe
        return len(view)

    @property
    def column_count(self) -> int:
        view = self.active_view if self.active_view is not None else self.dataframe

        # Deliberately checking column count, not view.empty: pandas
        # treats a dataframe as "empty" when EITHER axis is zero-length,
        # so a sheet with real columns but zero rows (e.g. every row's
        # cells were blank and openpyxl silently drops all-empty rows
        # on save - see read_sheet) would otherwise have its headers
        # discarded here even though the columns are genuinely present.
        if len(view.columns) == 0:
            return 0

        return len(view.columns)

    @property
    def headers(self) -> list[str]:
        view = self.active_view if self.active_view is not None else self.dataframe

        if len(view.columns) == 0:
            return []

        return list(view.columns)

    def data(self) -> SpreadsheetData:
        view = self.active_view if self.active_view is not None else self.dataframe

        if view is None:
            view = self.dataframe

        self.ensure_ids()

        return SpreadsheetData(
            headers=self.headers,
            rows=view.fillna("").to_dict("records"),
            row_ids=self._row_ids_for(view),
            column_ids=[self.column_ids.get(name, "") for name in view.columns],
            row_count=len(view),
            column_count=self.column_count,
            column_widths=dict(self.column_widths),
            rtl=self.rtl,
            cell_styles=self._style_entries(view),
            text_defaults=self.text_defaults.to_dict(),
            appearance=self.appearance.to_dict(),
        )

    # ------------------------------------------------------------------
    # Stable row / column IDs
    # ------------------------------------------------------------------

    def _new_row_id(self) -> str:
        identifier = f"r{self.next_row_number}"
        self.next_row_number += 1
        return identifier

    def _new_column_id(self) -> str:
        identifier = f"c{self.next_column_number}"
        self.next_column_number += 1
        return identifier

    def ensure_ids(self) -> None:
        """
        Make sure every row and column has an ID.

        Called before any structural edit and whenever IDs are read. If the
        number of IDs no longer matches the number of rows (a new sheet,
        or a dataframe replaced from outside the structural methods below)
        there is no way to know which row is which, so every row gets a
        fresh ID. Columns are matched by name: known names keep their ID,
        new names get one, names that are gone are forgotten.
        """
        if len(self.row_ids) != len(self.dataframe):
            self.row_ids = [self._new_row_id() for _ in range(len(self.dataframe))]

        self.column_ids = {
            name: self.column_ids.get(name) or self._new_column_id()
            for name in self.dataframe.columns
        }

    def _row_ids_for(self, view: pd.DataFrame) -> list[str]:
        """The row IDs of ``view``'s rows, in view order.

        A search or sort keeps each row's dataframe position as its index
        label (see _view_positions), which is how a shown row is traced
        back to its ID.
        """
        labels = list(view.index)

        if all(
            pd.api.types.is_integer(label) and 0 <= int(label) < len(self.row_ids)
            for label in labels
        ):
            return [self.row_ids[int(label)] for label in labels]

        # Index labels are not positions (should not happen): only an
        # unfiltered, unsorted view can be matched row for row.
        if len(labels) == len(self.row_ids):
            return list(self.row_ids)

        return ["" for _ in labels]

    def row_position(self, row_id: str) -> int | None:
        """The dataframe row position currently holding ``row_id``, or None."""
        self.ensure_ids()

        try:
            return self.row_ids.index(row_id)
        except ValueError:
            return None

    def row_id_at(self, position: int) -> str | None:
        """The ID of the row at dataframe position ``position``, or None."""
        self.ensure_ids()

        if isinstance(position, bool) or not isinstance(position, int):
            return None

        if position < 0 or position >= len(self.row_ids):
            return None

        return self.row_ids[position]

    def column_name(self, column_id: str) -> str | None:
        """The name of the column with ``column_id``, or None if there is none."""
        self.ensure_ids()

        for name, identifier in self.column_ids.items():
            if identifier == column_id:
                return name

        return None

    def column_id(self, name: str) -> str | None:
        """The ID of the column called ``name``, or None if there is none."""
        self.ensure_ids()
        return self.column_ids.get(name)

    def _style_entries(self, view: pd.DataFrame) -> list[dict[str, Any]]:
        """Per-cell overrides translated into the given view's coordinates."""
        if not self.cell_styles:
            return []

        column_index = {name: index for index, name in enumerate(view.columns)}
        entries: list[dict[str, Any]] = []

        for view_row, label in enumerate(view.index):
            row_styles = self.cell_styles.get(label)

            if not row_styles:
                continue

            for name, style in row_styles.items():
                column = column_index.get(name)

                if column is None:
                    continue

                entries.append({
                    "row": view_row,
                    "column": column,
                    "style": style.to_dict(),
                })

        return entries

    def _view_positions(self, first: int, last: int) -> list[int] | None:
        """Dataframe row positions for view rows ``first..last`` inclusive.

        The visible grid can be filtered and sorted, so a view row is not
        necessarily the same row of the underlying dataframe. The view
        keeps each row's original dataframe position as its index label
        (search preserves it, and SortService no longer resets it), which
        is what this reads. Returns None if any label isn't a valid
        dataframe position.
        """
        view = self.active_view if self.active_view is not None else self.dataframe
        positions: list[int] = []

        for label in view.index[first:last + 1]:
            if not pd.api.types.is_integer(label):
                return None

            position = int(label)

            if position < 0 or position >= len(self.dataframe):
                return None

            positions.append(position)

        return positions

    def filtered_row_count(self) -> int:
        view = self.active_view if self.active_view is not None else self.dataframe
        return len(view)

    def bind(self, worksheet: Any, dataframe: pd.DataFrame | None = None) -> None:
        self.worksheet = worksheet

        if dataframe is not None:
            self.dataframe = dataframe
            self.active_view = dataframe

    def clear_view(self) -> None:
        self.active_view = self.dataframe

    def set_dataframe(self, dataframe: pd.DataFrame) -> None:
        self.dataframe = dataframe
        self.active_view = dataframe

    def row(self, index: int):
        if index < 0:
            return None

        if index >= len(self.rows):
            return None

        return self.rows[index]

    def cell(self, row: int, column: int):
        current = self.row(row)

        if current is None:
            return None

        headers = self.headers

        if column >= len(headers):
            return None

        return current.values.get(headers[column])

    def search(self, text: str) -> bool:
        self.search_text = text.strip()
        self.active_view = self.search_service.search(self.dataframe, self.search_text)

        if self.sort_rules:
            self.sort(self.sort_rules, reapply=True)

        return True

    def clear_search(self) -> bool:
        self.search_text = ""
        self.active_view = self.dataframe.copy()
        return self._reapply_sort()

    def sort(self, rules: list[dict[str, Any]], reapply: bool = False) -> bool:
        if not reapply:
            self.sort_rules = rules

        self.active_view = self.sort_service.sort(self.active_view, self.sort_rules)
        return True

    def clear_sort(self) -> bool:
        self.sort_rules = []
        self.active_view = self.dataframe.copy()
        return True

    def edit_cell(self, row: int, column: int, value: Any) -> bool:
        return self.edit_cells([(row, column, value)])

    def edit_cells(self, edits: list[tuple[int, int, Any]]) -> bool:
        """
        Set several cells at once, all-or-nothing.

        ``row`` is a VIEW row - the row as the client sees it in the
        current filtered/sorted grid - and is translated to the underlying
        dataframe row (see _view_positions). With no filter or sort the
        two are the same. ``column`` is a column index (identical in the
        view and the dataframe).

        Every edit is validated before any is applied, so a bad entry
        leaves the sheet untouched.
        """
        if not isinstance(edits, (list, tuple)) or not edits:
            return False

        view = self.active_view if self.active_view is not None else self.dataframe
        resolved: list[tuple[int, int, Any]] = []

        for edit in edits:
            if not isinstance(edit, (list, tuple)) or len(edit) != 3:
                return False

            row, column, value = edit

            if any(isinstance(n, bool) or not isinstance(n, int) for n in (row, column)):
                return False

            if row < 0 or column < 0:
                return False

            if row >= len(view) or column >= len(self.dataframe.columns):
                return False

            positions = self._view_positions(row, row)

            if positions is None:
                return False

            resolved.append((positions[0], column, value))

        # Whether a column "prefers numbers" is decided once per column per
        # batch - it means scanning the column, and a large paste would
        # otherwise rescan it for every cell.
        preferences: dict[int, bool] = {}

        def prefers_numbers(column: int) -> Callable[[], bool]:
            def decide() -> bool:
                if column not in preferences:
                    preferences[column] = self._prefers_numbers(self.dataframe.iloc[:, column])

                return preferences[column]

            return decide

        for position, column, value in resolved:
            self._write_cell(position, column, value, prefers_numbers(column))

        self.active_view = self.dataframe.copy()
        return True

    _INTEGER_PATTERN = re.compile(r"^[+-]?\d+$")

    def _write_cell(
        self,
        position: int,
        column: int,
        value: Any,
        prefers_numbers: Callable[[], bool] | None = None,
    ) -> None:
        """
        Store one value, keeping the column's type sensible.

        Clients send every value as text. Writing text straight into a
        numeric column either upcasts the whole column to text (older
        pandas, with a warning) or raises (pandas 3), and either way a
        number typed into a number column would end up saved as text. So
        for a numeric column, text that is a valid number is stored as a
        number; anything else (including blank) turns the column into a
        general-purpose one first so the value can be stored as typed.
        Non-numeric columns store the value exactly as given.
        """
        series = self.dataframe.iloc[:, column]
        value, cast_to = self._coerce_value(value, series, prefers_numbers)

        if cast_to is not None:
            self.dataframe.isetitem(column, series.astype(cast_to))

        self.dataframe.iloc[position, column] = value

    @staticmethod
    def _prefers_numbers(series: pd.Series) -> bool:
        """
        Whether a general-purpose (text/mixed) column is mostly numbers.

        Used to decide if a numeric-looking entry should be stored as a
        number. Blank cells and formulas say nothing either way; a column
        with no content yet counts as numeric (typing 5 into a fresh column
        gives the number 5, as in Excel), while a column of names or IDs
        stays text so "007" keeps its zeros.
        """
        numbers = 0
        texts = 0

        for value in series:
            try:
                if pd.isna(value):
                    continue
            except (TypeError, ValueError):
                pass

            if isinstance(value, bool):
                texts += 1
            elif isinstance(value, (int, float)) or hasattr(value, "__float__") and not isinstance(value, str):
                numbers += 1
            elif isinstance(value, str):
                stripped = value.strip()

                if stripped and not stripped.startswith("="):
                    texts += 1
            else:
                texts += 1

        return numbers >= texts

    def _coerce_value(
        self,
        value: Any,
        series: pd.Series,
        prefers_numbers: Callable[[], bool] | None = None,
    ) -> tuple[Any, Any]:
        """
        Decide how to store ``value`` in a column shaped like ``series``.

        Returns ``(value, cast_to)``: the value to store (text that is a
        valid number becomes a number when the column is numeric - or is a
        text/mixed column that is mostly numbers, see _prefers_numbers),
        and the dtype the column must first be cast to, or None. See
        _write_cell.
        """
        is_numeric = (
            pd.api.types.is_numeric_dtype(series)
            and not pd.api.types.is_bool_dtype(series)
        )

        if isinstance(value, str) and not is_numeric and not (
            pd.api.types.is_bool_dtype(series) or pd.api.types.is_datetime64_any_dtype(series)
        ):
            # A general-purpose column (object, or pandas' string dtype):
            # numbers typed into a column that holds mostly numbers - say a
            # data column with a formula "total" row, which makes it mixed -
            # must still be stored as numbers, not as text.
            text = value.strip()
            is_integer_text = bool(self._INTEGER_PATTERN.match(text))
            number = None

            if not is_integer_text:
                try:
                    number = float(text)
                except ValueError:
                    number = None

                if number is not None and not math.isfinite(number):
                    number = None

            if (is_integer_text or number is not None) and (
                prefers_numbers() if prefers_numbers is not None else self._prefers_numbers(series)
            ):
                converted = int(text) if is_integer_text else number
                return converted, (None if pd.api.types.is_object_dtype(series) else object)

            return value, None

        if not (is_numeric and isinstance(value, str)):
            return value, None

        text = value.strip()
        is_integer_column = pd.api.types.is_integer_dtype(series)

        if self._INTEGER_PATTERN.match(text):
            number = int(text)
            return (number if is_integer_column else float(number)), None

        try:
            number = float(text)
        except ValueError:
            return value, object

        if not math.isfinite(number):
            return value, object

        return number, ("float64" if is_integer_column else None)

    def _rewrite_formulas(self, change: RefChange) -> None:
        """
        Re-point every stored formula after a row/column was inserted or deleted.

        Formulas are kept as text (``=A1+A2``) and name cells by position, so
        without this they would keep pointing at the OLD positions and quietly
        compute with different cells (see formula_refs for the rules). Only
        text columns are scanned, and only cells that start with ``=``.
        """
        changed_any = False

        for column in range(len(self.dataframe.columns)):
            series = self.dataframe.iloc[:, column]

            if pd.api.types.is_numeric_dtype(series) or pd.api.types.is_datetime64_any_dtype(series):
                continue

            values = series.tolist()
            changed = False

            for position, value in enumerate(values):
                if isinstance(value, str) and value.startswith("="):
                    rewritten = adjust_formula(value, change)

                    if rewritten != value:
                        values[position] = rewritten
                        changed = True

            if changed:
                self.dataframe.isetitem(column, pd.Series(values, index=series.index, dtype=object))
                changed_any = True

        if changed_any:
            self.active_view = self.dataframe.copy()

    def snapshot(self) -> "SheetSnapshot":
        """An exact, independent copy of this sheet's undoable state."""
        return SheetSnapshot(
            dataframe=self.dataframe.copy(deep=True),
            cell_styles={
                position: {name: style.copy() for name, style in styles.items()}
                for position, styles in self.cell_styles.items()
            },
            column_widths=dict(self.column_widths),
            row_ids=list(self.row_ids),
            column_ids=dict(self.column_ids),
        )

    def restore(self, snapshot: "SheetSnapshot") -> None:
        """Put this sheet back to ``snapshot`` (kept independent of it)."""
        self.dataframe = snapshot.dataframe.copy(deep=True)
        self.active_view = self.dataframe.copy()
        self.cell_styles = {
            position: {name: style.copy() for name, style in styles.items()}
            for position, styles in snapshot.cell_styles.items()
        }
        self.column_widths = dict(snapshot.column_widths)
        self.row_ids = list(snapshot.row_ids)
        self.column_ids = dict(snapshot.column_ids)
        self.ensure_ids()

    def _row_position(self, view_row: int | None) -> int | None:
        """
        Translate a row of the grid as shown into a dataframe row position.

        With a sort or filter in place the visible row N is not the
        underlying row N, so anything addressed by a row number a client
        read off the screen must go through here (see _view_positions).
        ``None`` or one-past-the-last visible row means "the end" and maps
        to the end of the underlying data. Returns None if invalid.
        """
        view_length = len(self.active_view) if self.active_view is not None else len(self.dataframe)

        if view_row is None or view_row == view_length:
            return len(self.dataframe)

        if isinstance(view_row, bool) or not isinstance(view_row, int):
            return None

        if view_row < 0 or view_row > view_length:
            return None

        positions = self._view_positions(view_row, view_row)

        if positions is None:
            return None

        return positions[0]

    def insert_row(self, index: int | None = None) -> bool:
        """
        Insert an empty row before visible row ``index`` (or at the end).

        ``index`` is a row of the grid as currently shown; it is mapped to
        the underlying row, so inserting "above row 3" of a sorted view
        goes where that row really is.
        """
        position = self._row_position(index)

        if position is None:
            return False

        index = position

        self.ensure_ids()

        empty = {column: "" for column in self.dataframe.columns}
        top = self.dataframe.iloc[:index]
        bottom = self.dataframe.iloc[index:]

        self.dataframe = pd.concat(
            [top, pd.DataFrame([empty]), bottom],
            ignore_index=True
        )
        self.row_ids.insert(index, self._new_row_id())
        self.active_view = self.dataframe.copy()
        self.cell_styles = {
            (position + 1 if position >= index else position): styles
            for position, styles in self.cell_styles.items()
        }
        self._rewrite_formulas(RefChange("row", "insert", index))
        return True

    def append_row(self, first_value: Any = None) -> bool:
        """
        Add a row at the end of the data, optionally setting its first cell.

        Done as ONE operation, rather than an insert followed by an edit,
        because with a sort or filter in place the new row's visible
        position is unpredictable (an empty row can sort anywhere, and a
        filter may hide it) - so a client can't reliably address it by
        row number afterwards.
        """
        if len(self.dataframe.columns) == 0:
            return False

        # A whitespace-only value is treated as no value.
        if isinstance(first_value, str) and not first_value.strip():
            first_value = ""

        # Decide how to store the value BEFORE adding the row: the blank
        # row turns a numeric column into a general one, after which "3"
        # typed into a column of numbers would no longer be recognised as
        # a number.
        if first_value not in (None, ""):
            first_value, _ = self._coerce_value(first_value, self.dataframe.iloc[:, 0])

        if not self.insert_row(None):
            return False

        if first_value not in (None, ""):
            self.dataframe.iloc[len(self.dataframe) - 1, 0] = first_value
            self.active_view = self.dataframe.copy()

        return True

    def delete_row(self, index: int) -> bool:
        """
        Delete visible row ``index`` (a row of the grid as currently shown).

        Mapped to the underlying row first: with a sort or filter in place
        the visible row N is not the underlying row N, and deleting by the
        raw number removes a different row than the one on screen.
        """
        view_length = len(self.active_view) if self.active_view is not None else len(self.dataframe)

        if isinstance(index, bool) or not isinstance(index, int):
            return False

        if index < 0 or index >= view_length:
            return False

        position = self._row_position(index)

        if position is None or position >= len(self.dataframe):
            return False

        index = position

        self.ensure_ids()
        del self.row_ids[index]

        self.dataframe = self.dataframe.drop(index)
        self.dataframe.reset_index(drop=True, inplace=True)
        self.active_view = self.dataframe.copy()
        self.cell_styles = {
            (position - 1 if position > index else position): styles
            for position, styles in self.cell_styles.items()
            if position != index
        }
        self._rewrite_formulas(RefChange("row", "delete", index))
        return True

    def insert_column(self, name: str, index: int | None = None) -> bool:
        if not isinstance(name, str) or not name.strip():
            return False

        if name in self.dataframe.columns:
            return False

        if index is None:
            index = len(self.dataframe.columns)

        if index < 0 or index > len(self.dataframe.columns):
            return False

        self.ensure_ids()
        self.dataframe.insert(index, name, "")
        self.column_ids[name] = self._new_column_id()
        self.active_view = self.dataframe.copy()
        self._rewrite_formulas(RefChange("column", "insert", index))
        return True

    def delete_column(self, name: str) -> bool:
        if name not in self.dataframe.columns:
            return False

        if len(self.dataframe.columns) == 1:
            # A sheet must always have at least one column - deleting the
            # last one would leave a zero-column DataFrame, which pandas
            # treats as "empty" the same way a zero-ROW DataFrame is,
            # collapsing headers/column_count to nothing even though rows
            # still exist. That self-contradictory shape (row_count > 0,
            # column_count == 0) is what a completely columnless sheet
            # produces - refuse it the same way a workbook is never
            # allowed to drop its last remaining sheet.
            return False

        position = list(self.dataframe.columns).index(name)

        self.ensure_ids()
        self.column_ids.pop(name, None)
        self.dataframe.drop(columns=[name], inplace=True)
        self.active_view = self.dataframe.copy()
        self.column_widths.pop(name, None)
        self._rewrite_formulas(RefChange("column", "delete", position))

        for position in list(self.cell_styles):
            self.cell_styles[position].pop(name, None)

            if not self.cell_styles[position]:
                del self.cell_styles[position]

        return True

    def rename_column(self, old_name: str, new_name: str) -> bool:
        if old_name not in self.dataframe.columns:
            return False

        if not isinstance(new_name, str) or not new_name.strip():
            return False

        if new_name != old_name and new_name in self.dataframe.columns:
            return False

        self.ensure_ids()
        self.dataframe.rename(columns={old_name: new_name}, inplace=True)
        self.active_view = self.dataframe.copy()

        # The column keeps its ID: that is the point of having one.
        if new_name != old_name:
            self.column_ids[new_name] = self.column_ids.pop(old_name)

        if new_name != old_name and old_name in self.column_widths:
            self.column_widths[new_name] = self.column_widths.pop(old_name)

        if new_name != old_name:
            for styles in self.cell_styles.values():
                if old_name in styles:
                    styles[new_name] = styles.pop(old_name)

        return True

    def set_column_width(self, name: str, width: float) -> bool:
        if name not in self.dataframe.columns:
            return False

        if not isinstance(width, (int, float)) or isinstance(width, bool):
            return False

        # Sanity bounds rather than a hard spec limit - keeps a stray
        # client value (0, negative, absurdly large) from corrupting the
        # saved workbook's column_dimensions. Excel's own UI caps width
        # similarly; this just mirrors that rather than inventing a limit.
        if width <= 0 or width > 1000:
            return False

        self.column_widths[name] = float(width)
        return True

    def set_rtl(self, rtl: bool) -> bool:
        """
        Set this sheet's right-to-left flag.

        Deliberately always succeeds (no validation branch that can
        return False) - unlike set_column_width, there's no invalid
        value to reject; any bool is a valid state for this flag.
        Kept returning bool anyway, matching every other Sheet mutator's
        shape, so Document/callers don't need a special case for this
        one operation.
        """
        self.rtl = bool(rtl)
        return True

    def set_cell_style(
        self,
        start_row: int,
        start_column: int,
        end_row: int,
        end_column: int,
        values: dict[str, Any] | None = None,
        reset: list[str] | None = None,
    ) -> bool:
        """
        Set or clear text-style fields on one rectangle of cells.

        See set_cell_style_ranges; this is the single-rectangle form.
        """
        return self.set_cell_style_ranges(
            [(start_row, start_column, end_row, end_column)],
            values,
            reset,
        )

    def set_cell_style_ranges(
        self,
        ranges: list[tuple[int, int, int, int]],
        values: dict[str, Any] | None = None,
        reset: list[str] | None = None,
    ) -> bool:
        """
        Set or clear text-style fields on several rectangles of cells at once.

        Each range is ``(start_row, start_column, end_row, end_column)`` in
        VIEW coordinates (what the client sees in the current grid),
        inclusive on both ends and in any corner order. A client with its
        own sort/filter selects a block of VISIBLE rows that may be
        scattered through the data, which is why this takes a list: it can
        describe them all in one request, applied as one undoable change.
        ``values`` sets fields; ``reset`` returns fields to "inherit from
        the sheet default". All-or-nothing: an invalid patch or any
        out-of-range rectangle changes nothing.
        """
        if not isinstance(ranges, (list, tuple)) or not ranges:
            return False

        view = self.active_view if self.active_view is not None else self.dataframe

        # Validate the patch once up front so a bad request can't leave a
        # half-applied selection behind.
        if CellStyle().apply_patch(values, reset) is None:
            return False

        resolved: list[tuple[list[int], list[str]]] = []

        for rectangle in ranges:
            if not isinstance(rectangle, (list, tuple)) or len(rectangle) != 4:
                return False

            if any(isinstance(c, bool) or not isinstance(c, int) for c in rectangle):
                return False

            start_row, start_column, end_row, end_column = rectangle

            row_low, row_high = sorted((start_row, end_row))
            column_low, column_high = sorted((start_column, end_column))

            if row_low < 0 or column_low < 0:
                return False

            if row_high >= len(view) or column_high >= len(view.columns):
                return False

            positions = self._view_positions(row_low, row_high)

            if positions is None:
                return False

            resolved.append((positions, list(view.columns[column_low:column_high + 1])))

        for positions, names in resolved:
            for position in positions:
                row_styles = self.cell_styles.get(position, {})

                for name in names:
                    updated = row_styles.get(name, CellStyle()).apply_patch(values, reset)

                    if updated is None or updated.is_empty():
                        row_styles.pop(name, None)
                    else:
                        row_styles[name] = updated

                if row_styles:
                    self.cell_styles[position] = row_styles
                else:
                    self.cell_styles.pop(position, None)

        return True

    def set_appearance(
        self,
        values: dict[str, Any] | None = None,
        reset: list[str] | None = None,
    ) -> bool:
        """Set or clear sheet-level display settings (grid color, banding)."""
        updated = self.appearance.apply_patch(values, reset)

        if updated is None:
            return False

        self.appearance = updated
        return True

    def set_text_defaults(
        self,
        values: dict[str, Any] | None = None,
        reset: list[str] | None = None,
    ) -> bool:
        """Set or clear fields of the sheet-wide default text style."""
        updated = self.text_defaults.apply_patch(values, reset)

        # "No fill" only means something as an override on a single cell;
        # as the sheet default it is just "unset".
        if updated is None or updated.background == NO_FILL:
            return False

        self.text_defaults = updated
        return True

    def _reapply_sort(self) -> bool:
        if self.sort_rules:
            return self.sort(self.sort_rules, reapply=True)
        return True