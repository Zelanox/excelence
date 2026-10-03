from backend.document.document import Document
from backend.storage.excel_storage import ExcelStorage
from backend.network.client import NetworkClient
from backend.utils.config import SERVER_IP, SERVER_PORT
from backend.models.spreadsheet_status import SpreadsheetStatus

from backend.services.spreadsheet_service import SpreadsheetService


class Controller:
    """Coordinate spreadsheet operations for the backend."""

    def __init__(self, document: Document | None = None, spreadsheet_service: SpreadsheetService | None = None) -> None:
        """Initialize the controller with document and spreadsheet services."""
        if document is None:
            document = Document(ExcelStorage(), NetworkClient(SERVER_IP, SERVER_PORT))

        if spreadsheet_service is None:
            spreadsheet_service = SpreadsheetService(document)

        self.document = document
        self.spreadsheet_service = spreadsheet_service

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

    def upload_document(self, filename: str, data: bytes) -> bool:
        """
        Save an uploaded file's raw bytes to the documents root.

        Args:
            filename: The uploaded file's original name.
            data: The file's raw bytes.

        Returns:
            True if the file was accepted and written, otherwise False.
        """
        return self.document.upload(filename, data)

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

    def data(self) -> list[dict[str, str]]:
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
        Return the available sort columns for the current sheet.

        Returns:
            A list of column names.
        """
        return self.document.headers()

    def sort(self, sort_rules: list[dict[str, object]]) -> bool:
        """
        Apply a list of sort rules to the current view.

        Args:
            sort_rules: A list of sort rule dictionaries.

        Returns:
            True if the sort operation completed, otherwise False.
        """
        success = self.spreadsheet_service.sort(sort_rules)

        if success:
            # Undo history is tied to the rows the client is looking at;
            # changing the view invalidates it (clients clear theirs too).
            self.document.clear_history()

        return success

    def clear_sort(self) -> bool:
        """
        Clear the active sort rules.

        Returns:
            True if sorting was reset successfully, otherwise False.
        """
        success = self.spreadsheet_service.clear_sort()

        if success:
            self.document.clear_history()

        return success

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
        success = self.spreadsheet_service.search(text)

        if success:
            self.document.clear_history()

        return success

    def clear_search(self) -> bool:
        """
        Clear the active search filter.

        Returns:
            True if the search filter was cleared successfully, otherwise False.
        """
        success = self.spreadsheet_service.clear_search()

        if success:
            self.document.clear_history()

        return success

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
        return self.document.filtered_row_count()

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
        return self.spreadsheet_service.edit_cell(
            row,
            column,
            value,
        )

    def insert_row(self, index: int | None = None) -> bool:
        """
        Insert a new row into the active document.

        Args:
            index: Optional zero-based index where the row should be inserted.

        Returns:
            True if the row was inserted successfully, otherwise False.
        """
        return self.spreadsheet_service.insert_row(index)

    def delete_row(self, index: int) -> bool:
        """
        Delete a row from the active document.

        Args:
            index: Zero-based row index to remove.

        Returns:
            True if the row was deleted successfully, otherwise False.
        """
        return self.spreadsheet_service.delete_row(index)

    def insert_column(self, name: str, index: int | None = None) -> bool:
        """
        Insert a new column into the active document.

        Args:
            name: Name of the new column.
            index: Optional zero-based index for the new column.

        Returns:
            True if the column was inserted successfully, otherwise False.
        """
        return self.spreadsheet_service.insert_column(name, index)

    def delete_column(self, name: str) -> bool:
        """
        Delete a column from the active document.

        Args:
            name: Column name to remove.

        Returns:
            True if the column was deleted successfully, otherwise False.
        """
        return self.spreadsheet_service.delete_column(name)

    def rename_column(self, old_name: str, new_name: str) -> bool:
        """
        Rename a column in the active document.

        Args:
            old_name: Current column name.
            new_name: New column name.

        Returns:
            True if the column was renamed successfully, otherwise False.
        """
        return self.spreadsheet_service.rename_column(
            old_name,
            new_name,
        )

    def set_column_width(self, name: str, width: float) -> bool:
        """
        Set a column's display width in the active document.

        Args:
            name: Column name to resize.
            width: New width, in openpyxl's column_dimensions units.

        Returns:
            True if the width was set successfully, otherwise False.
        """
        return self.spreadsheet_service.set_column_width(
            name,
            width,
        )

    def column_widths(self) -> dict[str, float]:
        """
        Return the current column widths for the active worksheet.

        Returns:
            A dict of column name to width, for any column with an
            explicitly set width.
        """
        return self.document.data().column_widths

    def set_rtl(self, rtl: bool) -> bool:
        """
        Set the active worksheet's right-to-left direction.

        Args:
            rtl: True for right-to-left, False for left-to-right.

        Returns:
            True if the flag was set successfully, otherwise False.
        """
        return self.spreadsheet_service.set_rtl(rtl)

    def rtl(self) -> bool:
        """
        Return whether the active worksheet is right-to-left.

        Returns:
            True if the active worksheet is right-to-left.
        """
        return self.document.data().rtl

    def edit_cells(self, edits: list[tuple[int, int, object]]) -> bool:
        """
        Update several cells as one undoable change.

        Args:
            edits: ``(row, column, value)`` tuples (rows are rows of the
                grid as currently shown). All-or-nothing.

        Returns:
            True if every edit was applied, otherwise False.
        """
        return self.spreadsheet_service.edit_cells(edits)

    def undo(self) -> bool:
        """Undo the last content change. False if there is nothing to undo."""
        return self.spreadsheet_service.undo()

    def redo(self) -> bool:
        """Redo the last undone change. False if there is nothing to redo."""
        return self.spreadsheet_service.redo()

    def set_cell_style(
        self,
        start_row: int,
        start_column: int,
        end_row: int,
        end_column: int,
        values: dict | None = None,
        reset: list[str] | None = None,
    ) -> bool:
        """
        Set or clear text-style fields on a rectangle of cells.

        Coordinates are view coordinates (as shown in the current grid),
        inclusive, in any corner order.

        Returns:
            True if the style was applied, otherwise False.
        """
        return self.spreadsheet_service.set_cell_style(
            start_row,
            start_column,
            end_row,
            end_column,
            values,
            reset,
        )

    def set_text_defaults(
        self,
        values: dict | None = None,
        reset: list[str] | None = None,
    ) -> bool:
        """
        Set or clear fields of the active sheet's default text style.

        Returns:
            True if the defaults were updated, otherwise False.
        """
        return self.spreadsheet_service.set_text_defaults(values, reset)

    def grid_data(self):
        """
        Return the active sheet's complete grid payload in one call.

        Every grid-returning API response is built from this single
        snapshot (see the API layer's _grid_fields) rather than calling
        data()/column_widths()/rtl()/... separately - each of those
        rebuilds every visible row, and separate snapshots could also
        disagree with one another.
        """
        return self.document.data()

    def cell_styles(self) -> list[dict]:
        """Return the active sheet's per-cell style overrides (view coordinates)."""
        return self.document.data().cell_styles

    def text_defaults(self) -> dict:
        """Return the active sheet's default text style (set fields only)."""
        return self.document.data().text_defaults

    def rename_sheet(self, old_name: str, new_name: str) -> bool:
        """
        Rename a worksheet in the active document.

        Args:
            old_name: Current worksheet name.
            new_name: New worksheet name.

        Returns:
            True if the worksheet was renamed successfully, otherwise False.
        """
        return self.spreadsheet_service.rename_sheet(
            old_name,
            new_name,
        )

    def add_sheet(self, name: str) -> bool:
        """
        Add a new worksheet to the active document.

        Args:
            name: Name of the new worksheet.

        Returns:
            True if the worksheet was added successfully, otherwise False.
        """
        return self.spreadsheet_service.add_sheet(name)

    def delete_sheet(self, name: str) -> bool:
        """
        Delete a worksheet from the active document.

        Args:
            name: Worksheet name to remove.

        Returns:
            True if the worksheet was deleted successfully, otherwise False.
        """
        return self.spreadsheet_service.delete_sheet(name)

    # ==========================================================
    # File Management
    # ==========================================================

    def list_documents(self, folder: str = "") -> list[str]:
        """
        List Excel documents in a folder.

        Args:
            folder: Folder to inspect, relative to the documents root.
                Defaults to the documents root itself.

        Returns:
            A sorted list of workbook filenames.
        """
        return self.document.list_documents(folder)

    def list_folder_entries(self, folder: str = "") -> dict[str, list[str]] | None:
        """
        List the subfolders and Excel documents directly inside a folder,
        for file-browser navigation.

        Args:
            folder: Folder to inspect, relative to the documents root.
                Defaults to the documents root itself.

        Returns:
            A dict with "folders" and "documents" lists, or None if
            folder is invalid or escapes the documents root.
        """
        return self.document.list_folder_entries(folder)

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