from dataclasses import dataclass, field

from backend.models.sheet import Sheet
from backend.models.spreadsheet_status import SpreadsheetData


@dataclass(slots=True)
class Spreadsheet:

    sheets: list[Sheet] = field(default_factory=list)

    active_sheet: int = 0

    def current_sheet(self):

        if not self.sheets:
            return None

        return self.sheets[self.active_sheet]

    def current_sheet_name(self):

        sheet = self.current_sheet()

        if sheet is None:
            return ""

        return sheet.name

    def sheet_names(self):

        return [

            sheet.name

            for sheet in self.sheets

        ]


    def get_sheet(self, name):

        for sheet in self.sheets:

            if sheet.name == name:

                return sheet

        return None

    def set_active_sheet(self, name):

        for index, sheet in enumerate(self.sheets):

            if sheet.name == name:

                self.active_sheet = index

                return True

        return False

    def row_count(self):

        sheet = self.current_sheet()

        if sheet is None:
            return 0

        return sheet.row_count

    def column_count(self):

        sheet = self.current_sheet()

        if sheet is None:
            return 0

        return sheet.column_count

    def filtered_row_count(self):

        sheet = self.current_sheet()

        if sheet is None:
            return 0

        return sheet.filtered_row_count()

    def headers(self):

        sheet = self.current_sheet()

        if sheet is None:
            return []

        return sheet.headers

    def data(self):

        sheet = self.current_sheet()

        if sheet is None:
            return SpreadsheetData()

        return sheet.data()

    def search(self, text):

        sheet = self.current_sheet()

        if sheet is None:
            return False

        return sheet.search(text)

    def clear_search(self):

        sheet = self.current_sheet()

        if sheet is None:
            return False

        return sheet.clear_search()

    def sort(self, rules, reapply=False):

        sheet = self.current_sheet()

        if sheet is None:
            return False

        return sheet.sort(rules, reapply=reapply)

    def clear_sort(self):

        sheet = self.current_sheet()

        if sheet is None:
            return False

        return sheet.clear_sort()

    def edit_cell(
        self,
        row,
        column,
        value
    ):

        sheet = self.current_sheet()

        if sheet is None:
            return False

        return sheet.edit_cell(
            row,
            column,
            value
        )

    def insert_row(self, index=None):

        sheet = self.current_sheet()

        if sheet is None:
            return False

        return sheet.insert_row(index)

    def delete_row(self, index):

        sheet = self.current_sheet()

        if sheet is None:
            return False

        return sheet.delete_row(index)

    def insert_column(
        self,
        name,
        index=None
    ):

        sheet = self.current_sheet()

        if sheet is None:
            return False

        return sheet.insert_column(
            name,
            index
        )

    def delete_column(
        self,
        name
    ):

        sheet = self.current_sheet()

        if sheet is None:
            return False

        return sheet.delete_column(name)

    