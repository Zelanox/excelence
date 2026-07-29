from backend.document.document import Document
from backend.storage.excel_storage import ExcelStorage
from backend.network.client import NetworkClient
from backend.utils.config import SERVER_IP, SERVER_PORT
from backend.models.spreadsheet_status import SpreadsheetStatus

class Controller:
    """Coordinate spreadsheet operations for the backend."""

    def __init__(self):
        """Initialize the controller with storage, network, and document services."""
        self.storage = ExcelStorage()
        self.network = NetworkClient(SERVER_IP, SERVER_PORT)
        self.document = Document(
            self.storage,
            self.network,
            online=False
        )

    # ==========================================================
    # Document
    # ==========================================================

    def open_document(self, filename: str) -> bool:
        """
        Open an Excel document from disk.

        Args:
            filename: Path to the workbook.

        Returns:
            True if the document was loaded successfully, otherwise False.
        """
        return self.document.open(filename)

    def create_document(self, filename: str) -> bool:
        """
        Create a new Excel document.

        Args:
            filename: Path for the new workbook.

        Returns:
            True if the new document was created successfully, otherwise False.
        """
        return self.document.create(filename)

    def save_document(self) -> bool:
        """
        Save the active document to disk.

        Returns:
            True if the document was saved successfully, otherwise False.
        """
        return self.document.save_local()

    def close_document(self) -> bool:
        """
        Close the active document.

        Returns:
            True if the document was closed successfully, otherwise False.
        """
        return self.document.close()

    def reload_document(self) -> bool:
        """
        Reload the active document from disk.

        Returns:
            True if the document was reloaded successfully, otherwise False.
        """
        return self.document.reload()

    # ==========================================================
    # Spreadsheet
    # ==========================================================


    def headers(self) -> list[str]:
        """
        Return the visible headers for the active sheet.


        Returns:
            A list of column names.
        """
        return self.document.headers()


    def row_count(self) -> int:
        """
        Return the number of visible rows.


        Returns:
            The visible row count.
        """
        return self.document.row_count()


    def column_count(self) -> int:
        """
        Return the number of visible columns.


        Returns:
            The visible column count.
        """
        return self.document.column_count()


    def data(self) -> list[dict]:
        """
        Return the visible spreadsheet data as row dictionaries.

        Returns:
            A list of row dictionaries.
        """
        return self.document.data().rows

    def cell_value(self, row: int, column: int) -> str:
        """
        Return the value from a specific cell position.

        Args:
            row: Zero-based row index.
            column: Zero-based column index.

        Returns:
            The cell value as a string, or an empty string if unavailable.
        """
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

    def sort_columns(self) -> list[str]:
        """
        Return the available sort columns.

        Returns:
            A list of column names.
        """
        return list(self.document.df.columns)

    def sort(self, sort_rules: list[dict]) -> bool:
        """
        Apply a list of sort rules to the current view.

        Args:
            sort_rules: A list of sort rule dictionaries.

        Returns:
            True if sorting completed successfully, otherwise False.
        """
        return self.document.sort(sort_rules)

    def clear_sort(self) -> bool:
        """
        Clear the active sort rules.

        Returns:
            True if sorting was reset successfully, otherwise False.
        """
        return self.document.clear_sort()

    # ==========================================================
    # Search
    # ==========================================================

    def search(self, text: str) -> bool:
        """
        Filter the visible rows by a search query.

        Args:
            text: Text to search for.

        Returns:
            True if the search completed successfully, otherwise False.
        """
        return self.document.search(text)

    def clear_search(self) -> bool:
        """
        Clear the active search filter.

        Returns:
            True if the search filter was cleared successfully, otherwise False.
        """
        return self.document.clear_search()

    # ==========================================================
    # Sheets
    # ==========================================================


    def sheets(self) -> list[str]:
        """
        Return the available worksheet names.

        Returns:
            A list of worksheet names.
        """
        return self.document.list_sheets()

    def current_sheet(self) -> str:
        """
        Return the currently active worksheet name.

        Returns:
            The active worksheet name.
        """
        return self.document.sheet_name

    def set_sheet(self, sheet: str) -> bool:
        """
        Switch to a different worksheet.

        Args:
            sheet: The worksheet name to activate.

        Returns:
            True if the worksheet changed successfully, otherwise False.
        """
        return self.document.set_sheet(sheet)

    # ==========================================================
    # Status
    # ==========================================================

    def filename(self) -> str:
        """
        Return the active document filename.

        Returns:
            The current filename.
        """
        return self.document.filename

    def modified(self) -> bool:
        """
        Return whether the active document has unsaved changes.

        Returns:
            True if the document has unsaved changes, otherwise False.
        """
        return self.document.modified

    def is_loaded(self) -> bool:
        """
        Return whether a document is currently loaded.

        Returns:
            True if a document is loaded, otherwise False.
        """
        return self.document.loaded

    def filtered_row_count(self) -> int:
        """
        Return the number of rows after search filtering.

        Returns:
            The filtered row count.
        """
        return len(self.document.filtered_df)

    def loaded_document(self):
        """
        Return the active document instance.

        Returns:
            The current document object.
        """
        return self.document

    def status(self) -> SpreadsheetStatus:
        """
        Return the current spreadsheet status summary.

        Returns:
            A status object with the current document metadata.
        """
        return SpreadsheetStatus(
            filename=self.filename(),
            loaded=self.is_loaded(),
            modified=self.modified(),
            rows=self.row_count(),

            columns=self.column_count()
        )

    
    # ==========================================================
    # Editing preparation
    # ==========================================================

    def edit_cell(self, row: int, column: int, value) -> bool:
        """
        Update a cell value in the active document.

        Args:
            row: Zero-based row index.
            column: Zero-based column index.
            value: New value for the cell.

        Returns:
            True if the update completed successfully, otherwise False.
        """
        return self.document.edit_cell(row, column, value)

    def insert_row(self, index: int | None = None) -> bool:
        """
        Insert a new row into the active document.

        Args:
            index: Optional zero-based index where the row should be inserted.

        Returns:
            True if the row was inserted successfully, otherwise False.
        """
        return self.document.insert_row(index)

    def delete_row(self, index: int) -> bool:
        """
        Delete a row from the active document.

        Args:
            index: Zero-based row index to remove.

        Returns:
            True if the row was deleted successfully, otherwise False.
        """
        return self.document.delete_row(index)

    def insert_column(self, name: str, index: int | None = None) -> bool:
        """
        Insert a new column into the active document.

        Args:
            name: Name of the new column.
            index: Optional zero-based index for the new column.

        Returns:
            True if the column was inserted successfully, otherwise False.
        """
        return self.document.insert_column(name, index)

    def delete_column(self, name: str) -> bool:
        """
        Delete a column from the active document.

        Args:
            name: Column name to remove.

        Returns:
            True if the column was deleted successfully, otherwise False.
        """
        return self.document.delete_column(name)

    def rename_sheet(self, old_name: str, new_name: str) -> bool:
        """
        Rename a worksheet in the active document.

        Args:
            old_name: Current worksheet name.
            new_name: New worksheet name.

        Returns:
            True if the worksheet was renamed successfully, otherwise False.
        """
        return self.document.rename_sheet(old_name, new_name)

    def add_sheet(self, name: str) -> bool:
        """
        Add a new worksheet to the active document.

        Args:
            name: Name of the new worksheet.

        Returns:
            True if the worksheet was added successfully, otherwise False.
        """
        return self.document.add_sheet(name)

    def delete_sheet(self, name: str) -> bool:
        """
        Delete a worksheet from the active document.

        Args:
            name: Worksheet name to remove.

        Returns:
            True if the worksheet was deleted successfully, otherwise False.
        """
        return self.document.delete_sheet(name)

    # ==========================================================
    # File Management
    # ==========================================================

    def list_documents(self, folder: str) -> list[str]:
        """
        List Excel documents in a folder.

        Args:
            folder: Folder to inspect.

        Returns:
            A sorted list of workbook filenames.
        """
        return self.document.list_documents(folder)

    def delete_document(self, filename: str) -> bool:
        """
        Delete an Excel document from disk.

        Args:
            filename: Path to the workbook.

        Returns:
            True if the workbook was deleted successfully, otherwise False.
        """
        return self.document.delete_document(filename)

    def copy_document(self, source: str, destination: str) -> bool:
        """
        Copy an Excel document to a new location.

        Args:
            source: Source workbook path.
            destination: Destination workbook path.

        Returns:
            True if the workbook was copied successfully, otherwise False.
        """
        return self.document.copy_document(source, destination)

    def rename_document(self, old_name: str, new_name: str) -> bool:
        """
        Rename an Excel document on disk.

        Args:
            old_name: Current workbook path.
            new_name: New workbook path.

        Returns:
            True if the workbook was renamed successfully, otherwise False.
        """
        return self.document.rename_document(old_name, new_name)
