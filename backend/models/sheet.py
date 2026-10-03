from dataclasses import dataclass, field
from typing import Any

import pandas as pd

from backend.models.cell_style import CellStyle
from backend.models.spreadsheet_row import SpreadsheetRow
from backend.models.spreadsheet_status import SpreadsheetData
from backend.services.search_service import SearchService
from backend.services.sort_service import SortService


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
    cell_styles: dict[int, dict[str, CellStyle]] = field(default_factory=dict)
    search_service: SearchService = field(default_factory=SearchService, repr=False, compare=False)
    sort_service: SortService = field(default_factory=SortService, repr=False, compare=False)

    def __post_init__(self) -> None:
        if self.active_view is None:
            self.active_view = self.dataframe

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

        return SpreadsheetData(
            headers=self.headers,
            rows=view.fillna("").to_dict("records"),
            row_count=len(view),
            column_count=self.column_count,
            column_widths=dict(self.column_widths),
            rtl=self.rtl,
            cell_styles=self._style_entries(view),
            text_defaults=self.text_defaults.to_dict(),
        )

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
        if row < 0 or column < 0:
            return False

        if row >= len(self.dataframe):
            return False

        if column >= len(self.dataframe.columns):
            return False

        self.dataframe.iloc[row, column] = value
        self.active_view = self.dataframe.copy()
        return True

    def insert_row(self, index: int | None = None) -> bool:
        if index is None:
            index = len(self.dataframe)

        if index < 0 or index > len(self.dataframe):
            return False

        empty = {column: "" for column in self.dataframe.columns}
        top = self.dataframe.iloc[:index]
        bottom = self.dataframe.iloc[index:]

        self.dataframe = pd.concat(
            [top, pd.DataFrame([empty]), bottom],
            ignore_index=True
        )
        self.active_view = self.dataframe.copy()
        self.cell_styles = {
            (position + 1 if position >= index else position): styles
            for position, styles in self.cell_styles.items()
        }
        return True

    def delete_row(self, index: int) -> bool:
        if index < 0 or index >= len(self.dataframe):
            return False

        self.dataframe = self.dataframe.drop(index)
        self.dataframe.reset_index(drop=True, inplace=True)
        self.active_view = self.dataframe.copy()
        self.cell_styles = {
            (position - 1 if position > index else position): styles
            for position, styles in self.cell_styles.items()
            if position != index
        }
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

        self.dataframe.insert(index, name, "")
        self.active_view = self.dataframe.copy()
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

        self.dataframe.drop(columns=[name], inplace=True)
        self.active_view = self.dataframe.copy()
        self.column_widths.pop(name, None)

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

        self.dataframe.rename(columns={old_name: new_name}, inplace=True)
        self.active_view = self.dataframe.copy()

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
        Set or clear text-style fields on a rectangle of cells.

        Coordinates are VIEW coordinates (what the client sees in the
        current filtered/sorted grid), inclusive on both ends and in any
        corner order. ``values`` sets fields; ``reset`` returns fields to
        "inherit from the sheet default". All-or-nothing: an invalid
        patch or an out-of-range rectangle changes nothing.
        """
        coordinates = (start_row, start_column, end_row, end_column)

        if any(isinstance(c, bool) or not isinstance(c, int) for c in coordinates):
            return False

        view = self.active_view if self.active_view is not None else self.dataframe

        row_low, row_high = sorted((start_row, end_row))
        column_low, column_high = sorted((start_column, end_column))

        if row_low < 0 or column_low < 0:
            return False

        if row_high >= len(view) or column_high >= len(view.columns):
            return False

        # Validate the patch once up front so a bad request can't leave a
        # half-applied rectangle behind.
        if CellStyle().apply_patch(values, reset) is None:
            return False

        positions = self._view_positions(row_low, row_high)

        if positions is None:
            return False

        names = list(view.columns[column_low:column_high + 1])

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

    def set_text_defaults(
        self,
        values: dict[str, Any] | None = None,
        reset: list[str] | None = None,
    ) -> bool:
        """Set or clear fields of the sheet-wide default text style."""
        updated = self.text_defaults.apply_patch(values, reset)

        if updated is None:
            return False

        self.text_defaults = updated
        return True

    def _reapply_sort(self) -> bool:
        if self.sort_rules:
            return self.sort(self.sort_rules, reapply=True)
        return True