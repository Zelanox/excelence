import copy

import pandas as pd

from openpyxl import load_workbook
from openpyxl import Workbook


class Document:

    def __init__(self, storage, network, online=False):

        # Managers
        self.storage = storage
        self.network = network

        # Connection
        self.online = online

        # Workbook
        self.workbook = None
        self.sheet = None

        # File information
        self.filename = ""
        self.sheet_name = ""

        # Data
        self.df = pd.DataFrame()
        self.filtered_df = pd.DataFrame()

        # Search / Sort
        self.search_text = ""
        self.sort_rules = []

        # Document state
        self.loaded = False
        self.modified = False

        # Undo / Redo (future)
        self.undo_stack = []
        self.redo_stack = []

    # ==========================================================
    # Document
    # ==========================================================

    def open(self, filename):

        self.load_local(filename)

        self.filename = filename
        self.loaded = True
        self.modified = False

        return True


    def create(self, filename):

        self.workbook = Workbook()
        self.sheet = self.workbook.active

        self.sheet.title = "Sheet1"

        self.filename = filename
        self.sheet_name = self.sheet.title

        self.df = pd.DataFrame()
        self.filtered_df = pd.DataFrame()

        self.loaded = True
        self.modified = True

        return True


    def close(self):

        self.workbook = None
        self.sheet = None

        self.filename = ""
        self.sheet_name = ""

        self.df = pd.DataFrame()
        self.filtered_df = pd.DataFrame()

        self.search_text = ""
        self.sort_rules = []

        self.loaded = False
        self.modified = False

        return True


    def reload(self):

        if not self.loaded:
            return False

        self.load_local(self.filename)

        return True

    # ==========================================================
    # Loading / Saving
    # ==========================================================

    def load_local(self, filename):

        self.workbook = self.storage.open(filename)

        if self.workbook is None:
            return False

        self.sheet = self.workbook.active
        self.sheet_name = self.sheet.title

        self.df = self.storage.read_sheet(self.sheet)

        self.filtered_df = self.df.copy()

        self.modified = False

        return True


    def save_local(self):

        if self.workbook is None:
            return False

        self.storage.write_sheet(
            self.sheet,
            self.df
        )

        self.storage.save(
            self.workbook,
            self.filename
        )

        self.modified = False

        return True

    # ==========================================================
    # Search
    # ==========================================================

    def search(self, text):

        self.search_text = text.strip()

        if not self.search_text:

            self.filtered_df = self.df.copy()
            return True

        search = self.search_text.lower()

        mask = self.df.astype(str).apply(
            lambda column: column.str.lower().str.contains(
                search,
                na=False
            )
        ).any(axis=1)

        self.filtered_df = self.df[mask].copy()

        # Keep current sorting after searching
        if self.sort_rules:
            self.sort(self.sort_rules, reapply=True)

        return True


    def clear_search(self):

        self.search_text = ""
        self.filtered_df = self.df.copy()

        if self.sort_rules:
            self.sort(self.sort_rules, reapply=True)

        return True

    # ==========================================================
    # Sorting
    # ==========================================================

    def sort(self, sort_rules, reapply=False):

        if self.filtered_df.empty:
            return False

        if not reapply:
            self.sort_rules = sort_rules

        if not self.sort_rules:
            return True

        columns = []
        ascending = []

        for rule in self.sort_rules:

            column = rule.get("column")

            if column not in self.filtered_df.columns:
                continue

            columns.append(column)
            ascending.append(
                rule.get("ascending", True)
            )

        if not columns:
            return False

        self.filtered_df = self.filtered_df.sort_values(
            by=columns,
            ascending=ascending,
            kind="stable"
        ).reset_index(drop=True)

        return True

    # ==========================================================
    # Editing
    # ==========================================================

    def edit_cell(self, row, column, value):

        if row < 0 or column < 0:
            return False

        if row >= len(self.df):
            return False

        if column >= len(self.df.columns):
            return False

        self.df.iat[row, column] = value

        self.modified = True

        # Refresh filtered data
        self.search(self.search_text)

        return True


    def insert_row(self, index=None):

        if index is None:
            index = len(self.df)

        empty = {
            column: ""
            for column in self.df.columns
        }

        top = self.df.iloc[:index]
        bottom = self.df.iloc[index:]

        self.df = pd.concat(
            [
                top,
                pd.DataFrame([empty]),
                bottom
            ],
            ignore_index=True
        )

        self.modified = True

        self.search(self.search_text)

        return True


    def delete_row(self, index):

        if index < 0 or index >= len(self.df):
            return False

        self.df = self.df.drop(index)

        self.df.reset_index(
            drop=True,
            inplace=True
        )

        self.modified = True

        self.search(self.search_text)

        return True


    def insert_column(self, name, index=None):

        if name in self.df.columns:
            return False

        if index is None:
            index = len(self.df.columns)

        self.df.insert(
            index,
            name,
            ""
        )

        self.modified = True

        self.search(self.search_text)

        return True


    def delete_column(self, name):

        if name not in self.df.columns:
            return False

        self.df.drop(
            columns=[name],
            inplace=True
        )

        self.modified = True

        self.search(self.search_text)

        return True

    # ==========================================================
    # Sheets
    # ==========================================================

    def list_sheets(self):

        if self.workbook is None:
            return []

        return self.workbook.sheetnames


    def set_sheet(self, sheet_name):

        if self.workbook is None:
            return False

        if sheet_name not in self.workbook.sheetnames:
            return False

        self.sheet = self.workbook[sheet_name]
        self.sheet_name = sheet_name

        self.df = self.storage.read_sheet(self.sheet)

        self.filtered_df = self.df.copy()

        self.search(self.search_text)

        return True


    # ==========================================================
    # Helpers
    # ==========================================================

    def table(self):

        return self.filtered_df


    def original_table(self):

        return self.df


    def row_count(self):

        return len(self.filtered_df)


    def column_count(self):

        return len(self.filtered_df.columns)


    def headers(self):

        return list(self.filtered_df.columns)

