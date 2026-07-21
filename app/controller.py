from document import Document
from config import SERVER_IP, SERVER_PORT
from storage import ExcelStorage
from network.client import NetworkClient

import pandas as pd



class Controller:

    def __init__(self):

        # Managers
        self.storage = ExcelStorage()
        self.network = NetworkClient(SERVER_IP, SERVER_PORT)

        # Active document
        self.document = Document(
            self.storage,
            self.network,
            online=False
        )

    # ==========================================================
    # Document
    # ==========================================================

    def open_document(self, filename):

        return self.document.open(filename)


    def create_document(self, filename):

        return self.document.create(filename)


    def save_document(self):

        return self.document.save_local()


    def close_document(self):

        return self.document.close()


    def reload_document(self):

        return self.document.reload()

    # ==========================================================
    # Spreadsheet
    # ==========================================================

    def headers(self):

        return list(self.document.filtered_df.columns)

    def row_count(self):

        return len(self.document.filtered_df)

    def column_count(self):

        return len(self.document.filtered_df.columns)

    def cell_value(self, row, column):

        df = self.document.filtered_df

        if row < 0 or column < 0:
            return ""

        if row >= len(df):
            return ""

        if column >= len(df.columns):
            return ""

        value = df.iat[row, column]

        if pd.isna(value):
            return ""

        return str(value)

    # ==========================================================
    # Search
    # ==========================================================

    def search(self, text):

        self.document.search(text)


    def clear_search(self):

        self.document.clear_search()

    # ==========================================================
    # Sheets
    # ==========================================================

    def sheet_names(self):

        return self.document.list_sheets()

    def current_sheet(self):

        return self.document.sheet_name

    def set_sheet(self, sheet):

        return self.document.set_sheet(sheet)

    # ==========================================================
    # Status
    # ==========================================================

    def filename(self):

        return self.document.filename

    def modified(self):

        return self.document.modified

    def is_loaded(self):

        return self.document.loaded

    def row_total(self):

        return len(self.document.filtered_df)

