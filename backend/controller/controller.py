from backend.document.document import Document
from backend.storage.excel_storage import ExcelStorage
from backend.network.client import NetworkClient
from backend.utils.config import SERVER_IP, SERVER_PORT

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
            return self.document.headers()


        def row_count(self):
            return self.document.row_count()


        def column_count(self):
            return self.document.column_count()


        def cell_value(self, row, column):

            table = self.document.table()

            if row >= len(table):
                return ""

            if column >= len(table.columns):
                return ""

            value = table.iat[row, column]

            if value is None:
                return ""

            return str(value)

    # ==========================================================
    # Sorting
    # ==========================================================

    def sort_columns(self):
        return list(self.document.df.columns)


    def sort(self, sort_rules):

        self.document.sort(sort_rules)
        
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

    def filtered_row_count(self):
        return len(self.document.filtered_df)

    def loaded_document(self):
        return self.document