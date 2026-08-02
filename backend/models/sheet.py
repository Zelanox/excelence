from dataclasses import dataclass, field
from typing import Any

import pandas as pd

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

        if view.empty:
            return 0

        return len(view.columns)

    @property
    def headers(self) -> list[str]:
        view = self.active_view if self.active_view is not None else self.dataframe

        if view.empty:
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
        )

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
        return True

    def delete_row(self, index: int) -> bool:
        if index < 0 or index >= len(self.dataframe):
            return False

        self.dataframe = self.dataframe.drop(index)
        self.dataframe.reset_index(drop=True, inplace=True)
        self.active_view = self.dataframe.copy()
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

        self.dataframe.drop(columns=[name], inplace=True)
        self.active_view = self.dataframe.copy()
        return True

    def _reapply_sort(self) -> bool:
        if self.sort_rules:
            return self.sort(self.sort_rules, reapply=True)
        return True