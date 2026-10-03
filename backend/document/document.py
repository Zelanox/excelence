from typing import Any

import json
import os
import pandas as pd
from openpyxl import Workbook
from openpyxl.styles import Font
from openpyxl.utils import get_column_letter
from openpyxl.workbook.defined_name import DefinedName


from backend.models.spreadsheet_status import DocumentInfo, SpreadsheetData, SpreadsheetSheet
from backend.utils.config import DOCUMENTS_FOLDER
from backend.utils.logger import get_logger

from backend.models.cell_style import CellStyle
from backend.models.spreadsheet import Spreadsheet
from backend.models.sheet import Sheet
from backend.models.spreadsheet_row import SpreadsheetRow

from backend.services.search_service import SearchService
from backend.services.sort_service import SortService
from backend.services.editing_service import EditingService

logger = get_logger("document")

# Excel has no per-sheet default font (only a workbook-wide "Normal"
# style), so the sheet-wide default text style is stored as a hidden,
# worksheet-scoped defined name holding JSON as a string constant. It
# travels with the worksheet (survives a sheet rename) and Excel ignores
# it. Per-cell overrides, by contrast, are stored as ordinary cell fonts.
_TEXT_DEFAULTS_NAME = "_excelence_text_defaults"

# What an unstyled cell is in an Excel/openpyxl workbook.
_BASE_FONT_FAMILY = "Calibri"
_BASE_FONT_SIZE = 11.0
_BASE_FONT_COLOR = "000000"


class Document:
    """Own spreadsheet state and workbook operations for the backend."""

    def __init__(self, storage: Any, network: Any, online: bool = False) -> None:
        """
        Initialize the document state and its collaborators.

        Args:
            storage: Storage backend used for file operations.
            network: Network backend placeholder for future sync support.
            online: Whether the document is connected to a remote service.
        """
        self.storage = storage
        self.network = network
        self.online = online

        self.workbook = None
        self.sheet = None

        self.filename = ""
        self.sheet_name = ""

        self.search_service = SearchService()
        self.sort_service = SortService()
        self.editing_service = EditingService()

        self.documents_folder = DOCUMENTS_FOLDER

        self.df = pd.DataFrame()
        self.filtered_df = pd.DataFrame()

        # Domain Model
        self.spreadsheet = Spreadsheet()

        self.search_text = ""
        self.sort_rules: list[dict[str, Any]] = []

        self.loaded = False
        self.modified = False

        self.undo_stack: list[dict[str, Any]] = []
        self.redo_stack: list[dict[str, Any]] = []

    # ==========================================================
    # Document
    # ==========================================================

    def open(self, filename: str) -> bool:
        """
        Open an Excel document from disk.

        Args:
            filename: Path to the workbook, relative to documents_folder.

        Returns:
            True if the document was loaded successfully, otherwise False.
        """
        if not self._is_valid_filename(filename):
            logger.warning("Open rejected for invalid filename: %s", filename)
            return False

        if not self.load_local(filename):
            logger.warning("Failed to open workbook: %s", filename)
            return False

        self.filename = filename
        self.loaded = True
        self.modified = False
        logger.info("Opened document %s", filename)
        return True

    def create(self, filename: str) -> bool:
        """
        Create a new Excel document.

        Args:
            filename: Path for the new workbook, relative to
                documents_folder.

        Returns:
            True if the new document was created successfully, otherwise False.
        """
        if self._resolve_path(filename) is None:
            logger.warning("Create rejected for invalid filename: %s", filename)
            return False

        self.workbook = Workbook()
        self.sheet = self.workbook.active
        self.sheet.title = "Sheet1"

        # Same clean boundary as load_local - see the note there.
        self.spreadsheet = Spreadsheet()
        self.search_text = ""
        self.sort_rules = []

        self.filename = filename
        self.sheet_name = self.sheet.title

        self._clear_view_data()
        self._seed_blank_worksheet(self.sheet)

        # Read the header/blank-row content _seed_blank_worksheet just
        # wrote back into self.df, mirroring what open()/set_sheet() do
        # after reading a worksheet. Without this, self.df stays the
        # empty (zero-column) DataFrame _clear_view_data() set it to,
        # even though the worksheet and the Sheet domain model (built
        # next, by dataframe_to_spreadsheet()) both correctly have the
        # seeded header - operations that read column names from
        # self.df.columns directly (e.g. set_column_width's worksheet
        # write) would then silently do nothing on a freshly created
        # document, despite the in-memory Sheet model looking correct.
        self._set_view_data(self.storage.read_sheet(self.sheet))
        self.dataframe_to_spreadsheet()

        self.loaded = True
        self.modified = True
        logger.info("Created document %s", filename)
        return True

    def upload(self, filename: str, data: bytes) -> bool:
        """
        Save uploaded file bytes directly to documents_folder, without
        opening them as the active document. Always lands at the
        documents root (filename is the plain name the client sent, e.g.
        "budget.xlsx" - not a path with folders); an existing file with
        the same name is overwritten.

        Args:
            filename: The uploaded file's original name.
            data: The file's raw bytes.

        Returns:
            True if the file was accepted and written, otherwise False
            (invalid filename, wrong extension, or a write failure).
        """
        if not self._is_valid_filename(filename):
            logger.warning("Upload rejected for invalid filename: %s", filename)
            return False

        # Uploads always land at the root, regardless of what path the
        # client sent - strip any directory components from a filename
        # like "folder/budget.xlsx" or "../../budget.xlsx" down to just
        # "budget.xlsx" before resolving, so this can't be used to write
        # outside documents_folder or into a subfolder.
        safe_name = os.path.basename(filename)

        if not self.storage.is_excel_file(safe_name):
            logger.warning("Upload rejected for non-Excel filename: %s", filename)
            return False

        resolved = self._resolve_path(safe_name)

        if resolved is None:
            logger.warning("Upload rejected for invalid filename: %s", filename)
            return False

        written = self.storage.write_bytes(data, resolved)

        if written:
            logger.info("Uploaded document %s", safe_name)
        else:
            logger.warning("Failed to write uploaded document %s", safe_name)

        return written

    def close(self) -> bool:
        """
        Close the active document and clear its state.

        Returns:
            True if the document was closed successfully, otherwise False.
        """
        self._reset_state()
        return True

    def reload(self) -> bool:
        """
        Reload the active document from disk.

        Returns:
            True if the document was reloaded successfully, otherwise False.
        """
        if not self.loaded or not self.filename:
            return False

        return self.load_local(self.filename)


    # ==========================================================
    # Domain Model
    # ==========================================================

    def dataframe_to_spreadsheet(self) -> None:

        if self.workbook is None:
            self.spreadsheet = Spreadsheet()
            return

        current_sheet_name = self.sheet_name or (self.sheet.title if self.sheet is not None else "")
        existing_sheets = {
            sheet.name: sheet for sheet in getattr(self.spreadsheet, "sheets", [])
        }

        rebuilt_sheets: list[Sheet] = []
        active_index = 0

        for index, worksheet_name in enumerate(self.workbook.sheetnames):
            worksheet = self.workbook[worksheet_name]
            dataframe = self.storage.read_sheet(worksheet)

            sheet_model = existing_sheets.get(worksheet_name)

            if sheet_model is None:
                sheet_model = Sheet(name=worksheet_name)

                # Only a brand-new model reads text styles back from the
                # worksheet. An existing model is already authoritative
                # (every style change is written to the worksheet as it
                # happens), and re-scanning every cell on each sheet
                # switch would be wasted work.
                sheet_model.text_defaults, sheet_model.cell_styles = (
                    self._read_text_styles(worksheet, dataframe.columns)
                )

            sheet_model.bind(worksheet, dataframe.copy())
            sheet_model.column_widths = self._read_column_widths(worksheet, dataframe.columns)
            sheet_model.rtl = bool(worksheet.sheet_view.rightToLeft)

            if worksheet_name == current_sheet_name:
                sheet_model.set_dataframe(self.df.copy() if not self.df.empty else dataframe.copy())
                sheet_model.active_view = self.filtered_df.copy() if not self.filtered_df.empty else dataframe.copy()
                active_index = index
            else:
                sheet_model.set_dataframe(dataframe.copy())
                sheet_model.active_view = dataframe.copy()

            rebuilt_sheets.append(sheet_model)

        self.spreadsheet = Spreadsheet(sheets=rebuilt_sheets, active_sheet=active_index)


    # ==========================================================
    # Loading / Saving
    # ==========================================================

    def load_local(self, filename: str) -> bool:
        """
        Load a workbook from storage into memory.

        Args:
            filename: Path to the workbook, relative to documents_folder.

        Returns:
            True if the workbook was loaded successfully, otherwise False.
        """
        resolved = self._resolve_path(filename)

        if resolved is None:
            return False

        self.workbook = self.storage.open(resolved)

        if self.workbook is None:
            return False

        self.sheet = self.workbook.active
        self.sheet_name = self.sheet.title

        # Opening a workbook is a clean boundary: drop the previous
        # document's domain model (and its search/sort state) so a
        # same-named sheet (e.g. "Sheet1") can't carry the old
        # document's per-cell styles, search or sort into this one.
        self.spreadsheet = Spreadsheet()
        self.search_text = ""
        self.sort_rules = []

        self._set_view_data(self.storage.read_sheet(self.sheet))
        self.dataframe_to_spreadsheet()
        self.modified = False
        return True

    def save_local(self) -> bool:
        """
        Save the active workbook to disk.

        Returns:
            True if the workbook was saved successfully, otherwise False.
        """
        if self.workbook is None or not self.filename:
            logger.warning("Save skipped because no active workbook is available")
            return False

        resolved = self._resolve_path(self.filename)

        if resolved is None:
            logger.warning("Save rejected for invalid filename: %s", self.filename)
            return False

        self.storage.write_sheet(self.sheet, self.df)

        active_sheet = self._active_sheet_model()

        if active_sheet is not None:
            self._write_column_widths(self.sheet, self.df.columns, active_sheet.column_widths)
            self.sheet.sheet_view.rightToLeft = active_sheet.rtl
            self._write_text_styles(self.sheet, self.df, active_sheet)

        saved = self.storage.save(self.workbook, resolved)
        self.modified = False

        if saved:
            logger.info("Saved document %s", self.filename)
        else:
            logger.warning("Failed to save document %s", self.filename)

        return saved

    # ==========================================================
    # Search
    # ==========================================================

    def search(self, text: str) -> bool:
        """
        Filter the visible rows using a search query.

        Args:
            text: Text to search for.

        Returns:
            True if the search completed successfully, otherwise False.
        """
        if self.workbook is None:
            return False

        self.search_text = text

        success = self.spreadsheet.search(text)

        if success:
            self._sync_from_active_sheet()

        return success

    def clear_search(self) -> bool:
        """
        Clear the active search filter.

        Returns:
            True if the search filter was cleared successfully, otherwise False.
        """
        if self.workbook is None:
            return False

        self.search_text = ""

        success = self.spreadsheet.clear_search()

        if success:
            self._sync_from_active_sheet()

        return success

    # ==========================================================
    # Sorting
    # ==========================================================

    def sort(self, sort_rules: list[dict[str, Any]], reapply: bool = False) -> bool:
        """
        Apply sort rules to the filtered view.

        Args:
            sort_rules: A list of sort rule dictionaries.
            reapply: Whether to reuse the current sort rules.

        Returns:
            True if sorting completed successfully, otherwise False.
        """
        if not reapply:
            self.sort_rules = sort_rules

        success = self.spreadsheet.sort(self.sort_rules, reapply=reapply)

        if success:
            self._sync_from_active_sheet()

        return success

    def clear_sort(self) -> bool:
        """
        Clear the active sort rules.

        Returns:
            True if sorting was reset successfully, otherwise False.
        """
        if self.workbook is None:
            return False

        self.sort_rules = []

        success = self.spreadsheet.clear_sort()

        if success:
            self._sync_from_active_sheet()

        return success

    # ==========================================================
    # Editing
    # ==========================================================

    def _sync_active_sheet(self) -> None:
        """Write the current DataFrame to the active worksheet."""
        if self.workbook is None or self.sheet is None:
            return

        self.storage.write_sheet(self.sheet, self.df)

        active_sheet = self._active_sheet_model()

        # Guard against active_sheet belonging to a DIFFERENT worksheet
        # than self.sheet currently points at - this genuinely happens
        # mid-add_sheet: self.sheet is reassigned to the brand-new
        # worksheet before self.spreadsheet (and so _active_sheet_model())
        # is rebuilt via dataframe_to_spreadsheet(), so without this check
        # the PREVIOUS active sheet's column_widths/rtl would get written
        # onto the NEW worksheet. column_widths happens to dodge this by
        # accident (self.df is cleared to empty first, so its write loop
        # has nothing to iterate), but rtl's write is unconditional and
        # was actually leaking across sheets before this check existed.
        if active_sheet is not None and active_sheet.worksheet is self.sheet:
            self._write_column_widths(self.sheet, self.df.columns, active_sheet.column_widths)
            self.sheet.sheet_view.rightToLeft = active_sheet.rtl
            self._write_text_styles(self.sheet, self.df, active_sheet)

    def _refresh_view(self) -> None:
        """Reload the active worksheet and reapply the current search/sort state."""
        if self.workbook is None or self.sheet is None:
            self._clear_view_data()
            return

        self._set_view_data(self.storage.read_sheet(self.sheet), apply_search=True)

    def edit_cell(self, row: int, column: int, value: Any) -> bool:
        """
        Update a cell value in the active document.

        Args:
            row: Zero-based row index.
            column: Zero-based column index.
            value: New value for the cell.

        Returns:
            True if the update completed successfully, otherwise False.
        """
        if self.workbook is None:
            return False

        if row < 0 or column < 0:
            return False

        success = self.spreadsheet.edit_cell(row, column, value)

        if not success:
            return False

        self._sync_from_active_sheet()
        self._sync_active_sheet()

        self.modified = True

        self.search(self.search_text)

        return True

    def insert_row(self, index: int | None = None) -> bool:
        """
        Insert a new row into the active document.

        Args:
            index: Optional zero-based index where the row should be inserted.

        Returns:
            True if the row was inserted successfully, otherwise False.
        """
        if self.workbook is None:
            return False

        success = self.spreadsheet.insert_row(index)

        if not success:
            return False

        self._sync_from_active_sheet()
        self._sync_active_sheet()
        self.modified = True
        self.search(self.search_text)
        return True

    def delete_row(self, index: int) -> bool:
        """
        Delete a row from the active document.

        Args:
            index: Zero-based row index to remove.

        Returns:
            True if the row was deleted successfully, otherwise False.
        """
        if self.workbook is None:
            return False

        success = self.spreadsheet.delete_row(index)

        if not success:
            return False

        self._sync_from_active_sheet()
        self._sync_active_sheet()
        self.modified = True
        self.search(self.search_text)
        return True

    def insert_column(self, name: str, index: int | None = None) -> bool:
        """
        Insert a new column into the active document.

        Args:
            name: Name of the new column.
            index: Optional zero-based index for the new column.

        Returns:
            True if the column was inserted successfully, otherwise False.
        """
        if self.workbook is None:
            return False

        success = self.spreadsheet.insert_column(name, index)

        if not success:
            return False

        self._sync_from_active_sheet()
        self._sync_active_sheet()
        self.modified = True
        self.search(self.search_text)
        return True

    def delete_column(self, name: str) -> bool:
        """
        Delete a column from the active document.

        Args:
            name: Column name to remove.

        Returns:
            True if the column was deleted successfully, otherwise False.
        """
        if self.workbook is None:
            return False

        success = self.spreadsheet.delete_column(name)

        if not success:
            return False

        self._sync_from_active_sheet()
        self._sync_active_sheet()
        self.modified = True
        self.search(self.search_text)
        return True

    def rename_column(self, old_name: str, new_name: str) -> bool:
        """
        Rename a column in the active document.

        Args:
            old_name: Current column name.
            new_name: New column name.

        Returns:
            True if the column was renamed successfully, otherwise False.
        """
        if self.workbook is None:
            return False

        success = self.spreadsheet.rename_column(old_name, new_name)

        if not success:
            return False

        self._sync_from_active_sheet()
        self._sync_active_sheet()
        self.modified = True
        self.search(self.search_text)
        return True

    def set_column_width(self, name: str, width: float) -> bool:
        """
        Set a column's display width on the active document.

        Args:
            name: Column name to resize.
            width: New width, in the same units openpyxl uses for
                column_dimensions (Excel's "character width" unit).

        Returns:
            True if the width was set successfully, otherwise False.
        """
        if self.workbook is None:
            return False

        success = self.spreadsheet.set_column_width(name, width)

        if not success:
            return False

        # Unlike edit_cell/insert/delete, a width change doesn't touch
        # row visibility or the dataframe shape, so there's no need to
        # resync view state, reapply search, or (unlike
        # _sync_active_sheet's use elsewhere) rebuild the worksheet's
        # rows via write_sheet - that would be wasted work for a change
        # that's purely a column_dimensions update. Write the new width
        # onto the live worksheet directly so a save right after a
        # resize, with no other edit in between, still persists it.
        if self.sheet is not None:
            active_sheet = self._active_sheet_model()

            if active_sheet is not None:
                self._write_column_widths(self.sheet, self.df.columns, active_sheet.column_widths)

        self.modified = True
        return True

    def set_rtl(self, rtl: bool) -> bool:
        """
        Set the active worksheet's right-to-left direction.

        Args:
            rtl: True for right-to-left, False for left-to-right.

        Returns:
            True if the flag was set successfully, otherwise False.
        """
        if self.workbook is None:
            return False

        success = self.spreadsheet.set_rtl(rtl)

        if not success:
            return False

        # Same reasoning as set_column_width: sheet_view.rightToLeft is
        # independent of row data (like column_dimensions), so there's
        # no need to rebuild the worksheet's rows via write_sheet for
        # what's purely a sheet_view flag flip. Written directly onto
        # the live worksheet so a save right after toggling RTL, with no
        # other edit in between, still persists it.
        if self.sheet is not None:
            self.sheet.sheet_view.rightToLeft = rtl

        self.modified = True
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

        Args:
            start_row, start_column, end_row, end_column: Inclusive
                rectangle in view coordinates, in any corner order.
            values: Style fields to set (bold, italic, underline,
                strikethrough, font_family, font_size, color).
            reset: Style fields to return to "inherit from sheet default".

        Returns:
            True if the style was applied, otherwise False (invalid
            patch or out-of-range rectangle - nothing is changed).
        """
        if self.workbook is None:
            return False

        success = self.spreadsheet.set_cell_style(
            start_row,
            start_column,
            end_row,
            end_column,
            values,
            reset,
        )

        if not success:
            return False

        # Unlike a width or RTL flip, a style change can also REMOVE a
        # font from a cell, so the worksheet is rebuilt via
        # _sync_active_sheet (clear + rewrite + reapply fonts) rather than
        # patched in place - otherwise a cell that lost its override
        # would keep its old font in the saved file.
        self._sync_active_sheet()

        self.modified = True
        return True

    def set_text_defaults(
        self,
        values: dict[str, Any] | None = None,
        reset: list[str] | None = None,
    ) -> bool:
        """
        Set or clear fields of the active sheet's default text style.

        Returns:
            True if the defaults were updated, otherwise False.
        """
        if self.workbook is None:
            return False

        success = self.spreadsheet.set_text_defaults(values, reset)

        if not success:
            return False

        self._sync_active_sheet()

        self.modified = True
        return True

    def rename_sheet(self, old_name: str, new_name: str) -> bool:
        """
        Rename a worksheet in the active document.

        Args:
            old_name: Current worksheet name.
            new_name: New worksheet name.

        Returns:
            True if the worksheet was renamed successfully, otherwise False.
        """
        if self.workbook is None:
            return False

        if not self._is_valid_filename(old_name) or not self._is_valid_filename(new_name):
            return False

        if old_name not in self.workbook.sheetnames:
            return False

        if new_name in self.workbook.sheetnames and new_name != old_name:
            return False

        self.workbook[old_name].title = new_name
        self.sheet_name = new_name
        self.sheet = self.workbook[new_name]
        self._sync_active_sheet()
        self.dataframe_to_spreadsheet()
        self.modified = True
        return True

    def add_sheet(self, name: str) -> bool:
        """
        Add a new worksheet to the active document.

        Args:
            name: Name of the new worksheet.

        Returns:
            True if the worksheet was added successfully, otherwise False.
        """
        if self.workbook is None:
            return False

        if not self._is_valid_filename(name):
            return False

        if name in self.workbook.sheetnames:
            return False

        self.workbook.create_sheet(title=name)
        self.sheet = self.workbook[name]
        self.sheet_name = name
        self._clear_view_data()
        self._sync_active_sheet()
        self._seed_blank_worksheet(self.sheet)

        # See create() for why this is needed - without it, self.df
        # stays empty (zero columns) after adding a sheet, even though
        # the worksheet and Sheet model both have the seeded header.
        self._set_view_data(self.storage.read_sheet(self.sheet))
        self.dataframe_to_spreadsheet()
        self.modified = True
        self.search(self.search_text)
        return True

    def delete_sheet(self, name: str) -> bool:
        """
        Delete a worksheet from the active document.

        Args:
            name: Worksheet name to remove.

        Returns:
            True if the worksheet was deleted successfully, otherwise False.
        """
        if self.workbook is None:
            return False

        if not self._is_valid_filename(name):
            return False

        if name not in self.workbook.sheetnames:
            return False

        if len(self.workbook.sheetnames) == 1:
            return False

        current_sheet_removed = name == self.sheet_name

        self.workbook.remove(self.workbook[name])
        self.modified = True

        if current_sheet_removed:
            remaining_sheet = self.workbook.sheetnames[0]
            self.sheet = self.workbook[remaining_sheet]
            self.sheet_name = remaining_sheet
            self._refresh_view()
            self.dataframe_to_spreadsheet()
            return True

        if self.sheet_name in self.workbook.sheetnames:
            self.sheet = self.workbook[self.sheet_name]
        else:
            self.sheet = self.workbook.active
            self.sheet_name = self.sheet.title

        self._refresh_view()
        self.dataframe_to_spreadsheet()
        return True

    # ==========================================================
    # Sheets
    # ==========================================================

    def list_sheets(self) -> list[str]:
        """
        Return the worksheet names for the active workbook.

        Returns:
            A list of worksheet names.
        """
        if self.workbook is None:
            return []

        return self.spreadsheet.sheet_names()

    def set_sheet(self, sheet_name: str) -> bool:
        """
        Switch to a different worksheet.

        Args:
            sheet_name: The worksheet name to activate.

        Returns:
            True if the worksheet changed successfully, otherwise False.
        """
        if self.workbook is None:
            return False

        if sheet_name not in self.workbook.sheetnames:
            return False

        self.sheet = self.workbook[sheet_name]
        self.sheet_name = sheet_name

        if not self.spreadsheet.set_active_sheet(sheet_name):
            return False

        dataframe = self.storage.read_sheet(self.sheet)
        self._set_view_data(dataframe, apply_search=False)
        self.dataframe_to_spreadsheet()
        self.search(self.search_text)
        return True

    # ==========================================================
    # File Management
    # ==========================================================

    def list_documents(self, folder: str = "") -> list[str]:
        """
        List Excel documents in a folder.

        Args:
            folder: Folder to inspect, relative to documents_folder.
                Empty string means documents_folder itself.

        Returns:
            A sorted list of workbook filenames, or an empty list if
            folder is invalid or escapes documents_folder.
        """
        resolved = self._resolve_folder(folder)

        if resolved is None:
            return []

        return self.storage.list_documents(resolved)

    def list_folder_entries(self, folder: str = "") -> dict[str, list[str]] | None:
        """
        List the subfolders and Excel documents directly inside a folder,
        for file-browser navigation.

        Args:
            folder: Folder to inspect, relative to documents_folder.
                Empty string means documents_folder itself.

        Returns:
            A dict with "folders" and "documents" (both sorted lists of
            names, not full paths), or None if folder is invalid or
            escapes documents_folder.
        """
        resolved = self._resolve_folder(folder)

        if resolved is None:
            return None

        if not os.path.isdir(resolved):
            return {"folders": [], "documents": []}

        folders = []
        documents = self.storage.list_documents(resolved)

        for entry in os.listdir(resolved):
            if os.path.isdir(os.path.join(resolved, entry)):
                folders.append(entry)

        folders.sort()

        return {"folders": folders, "documents": documents}

    def delete_document(self, filename: str) -> bool:
        """
        Delete an Excel document from disk.

        Args:
            filename: Path to the workbook, relative to documents_folder.

        Returns:
            True if the workbook was deleted successfully, otherwise False.
        """
        resolved = self._resolve_path(filename)

        if resolved is None:
            logger.warning("Delete rejected for invalid filename: %s", filename)
            return False

        deleted = self.storage.delete(resolved)

        if deleted:
            logger.info("Deleted document %s", filename)
        else:
            logger.warning("Failed to delete document %s", filename)

        return deleted

    def copy_document(self, source: str, destination: str) -> bool:
        """
        Copy an Excel document to a new location.

        Args:
            source: Source workbook path, relative to documents_folder.
            destination: Destination workbook path, relative to
                documents_folder.

        Returns:
            True if the workbook was copied successfully, otherwise False.
        """
        resolved_source = self._resolve_path(source)
        resolved_destination = self._resolve_path(destination)

        if resolved_source is None or resolved_destination is None:
            return False

        return self.storage.copy(resolved_source, resolved_destination)

    def rename_document(self, old_name: str, new_name: str) -> bool:
        """
        Rename an Excel document on disk.

        Args:
            old_name: Current workbook path, relative to documents_folder.
            new_name: New workbook path, relative to documents_folder.

        Returns:
            True if the workbook was renamed successfully, otherwise False.
        """
        resolved_old = self._resolve_path(old_name)
        resolved_new = self._resolve_path(new_name)

        if resolved_old is None or resolved_new is None:
            return False

        return self.storage.rename(resolved_old, resolved_new)

    # ==========================================================
    # Helpers
    # ==========================================================

    def table(self) -> pd.DataFrame:
        """
        Return the currently filtered table view.

        Returns:
            The filtered pandas DataFrame.
        """
        active_sheet = self._active_sheet_model()

        if active_sheet is None:
            return self.filtered_df.copy()

        return active_sheet.active_view.copy() if active_sheet.active_view is not None else active_sheet.dataframe.copy()

    def data(self) -> SpreadsheetData:
        """
        Return the currently filtered spreadsheet data as a structured value object.

        Returns:
            A structured representation of the visible rows.
        """
        active_sheet = self._active_sheet_model()

        if active_sheet is None:
            return SpreadsheetData()

        return active_sheet.data()

    def original_table(self) -> pd.DataFrame:
        """
        Return the underlying document table.

        Returns:
            The full pandas DataFrame.
        """
        active_sheet = self._active_sheet_model()

        if active_sheet is None:
            return self.df.copy()

        return active_sheet.dataframe.copy()

    def filtered_row_count(self) -> int:
        """Return the number of rows in the filtered view."""
        return self.spreadsheet.filtered_row_count()

    def row_count(self) -> int:
        """
        Return the number of rows in the filtered view.

        Returns:
            The filtered row count.
        """
        return self.spreadsheet.row_count()

    def column_count(self) -> int:
        """
        Return the number of columns in the filtered view.

        Returns:
            The filtered column count.
        """
        return self.spreadsheet.column_count()

    def headers(self) -> list[str]:
        """
        Return the visible headers.

        Returns:
            The visible column names.
        """
        return self.spreadsheet.headers()

    def info(self) -> DocumentInfo:
        """
        Return a structured summary of the active document.

        Returns:
            A document summary object.
        """
        return DocumentInfo(
            filename=self.filename,
            loaded=self.loaded,
            modified=self.modified,
            rows=self.row_count(),
            columns=self.column_count(),
            sheets=self.list_sheets(),
            current_sheet=self.sheet_name
        )

    def sheet_metadata(self) -> list[SpreadsheetSheet]:
        """
        Return worksheet metadata for the active workbook.

        Returns:
            A list of worksheet metadata objects.
        """
        if self.workbook is None:
            return []

        return [
            SpreadsheetSheet(name=name, active=name == self.sheet_name)
            for name in self.workbook.sheetnames
        ]

    def _reset_state(self) -> None:
        """Reset the workbook and document state."""
        self.workbook = None
        self.sheet = None
        self.filename = ""
        self.sheet_name = ""
        self._clear_view_data()
        self.search_text = ""
        self.sort_rules = []
        self.loaded = False
        self.modified = False

    def _reapply_sort(self) -> bool:
        """Reapply the current sort rules to the filtered view."""
        if self.sort_rules:
            return self.sort(self.sort_rules, reapply=True)
        return True

    def _is_valid_filename(self, filename: str | None) -> bool:
        """Validate that a filename is a non-empty string."""
        return isinstance(filename, str) and bool(filename.strip())

    def _resolve_path(self, relative_path: str) -> str | None:
        """
        Resolve a user-supplied relative path against documents_folder,
        rejecting anything that would escape it (absolute paths, "..").

        This is the single place filenames coming from the API turn into
        real filesystem paths - open/create/save/list/delete/rename all
        route through here rather than handing storage a raw path, so a
        request can never read or write outside documents_folder.

        Args:
            relative_path: Path relative to documents_folder, using "/"
                as the separator regardless of platform (the frontend
                and API always send "/"; os.path.join below produces the
                correct native separator for wherever this runs).

        Returns:
            The resolved absolute path, or None if relative_path is
            empty, absolute, or escapes documents_folder.
        """
        if not self._is_valid_filename(relative_path):
            return None

        if os.path.isabs(relative_path) or ":" in relative_path:
            return None

        base = os.path.abspath(self.documents_folder)
        candidate = os.path.abspath(
            os.path.join(base, *relative_path.split("/"))
        )

        if candidate != base and not candidate.startswith(base + os.sep):
            return None

        return candidate

    def _resolve_folder(self, relative_folder: str) -> str | None:
        """
        Resolve a user-supplied relative folder against documents_folder,
        rejecting anything that would escape it. Unlike _resolve_path,
        an empty string is valid here and means documents_folder itself
        (the root of the browsable tree).

        Args:
            relative_folder: Folder path relative to documents_folder,
                using "/" as the separator. Empty string means the root.

        Returns:
            The resolved absolute path, or None if relative_folder is
            not a string, absolute, or escapes documents_folder.
        """
        if not isinstance(relative_folder, str):
            return None

        if relative_folder == "":
            return os.path.abspath(self.documents_folder)

        return self._resolve_path(relative_folder)

    def _seed_blank_worksheet(
        self,
        worksheet: Any,
        column_count: int = 1,
        row_count: int = 1,
    ) -> None:
        """
        Write a starter header row (and enough blank rows beneath it) into
        a brand-new, otherwise completely empty worksheet.

        Without this, a freshly created sheet has zero columns - openpyxl
        reports no cell values at all, so read_sheet() returns a totally
        empty DataFrame (headers=[], column_count=0), which the frontend
        can't render into anything usable. This gives a new sheet the
        same "Column A", "Column B", ... naming the frontend already uses
        for columns it adds itself, so a brand-new sheet looks and
        behaves like any other freshly inserted column.
        """
        headers = [
            f"Column {chr(65 + index)}" for index in range(column_count)
        ]
        worksheet.append(headers)

        for _ in range(row_count):
            worksheet.append(["" for _ in headers])

    def _font_for_style(self, style: CellStyle) -> Font:
        """Build the openpyxl Font for an effective (already merged) style."""
        return Font(
            name=style.font_family or _BASE_FONT_FAMILY,
            sz=style.font_size if style.font_size is not None else _BASE_FONT_SIZE,
            b=bool(style.bold),
            i=bool(style.italic),
            u="single" if style.underline else None,
            strike=bool(style.strikethrough),
            color=("FF" + style.color) if style.color else None,
        )

    def _write_text_styles(self, worksheet: Any, dataframe: pd.DataFrame, sheet_model: Sheet) -> None:
        """
        Write a sheet's text styles onto its worksheet.

        Must run AFTER the worksheet's rows have been (re)written, since
        write_sheet clears every cell - and its styles - first. The sheet
        default is stored in a hidden defined name (so a fresh
        ``Excelence`` load can tell default from override) AND applied to
        every data cell, merged under any per-cell override, so the file
        also looks right when opened in real Excel. The header row is
        left untouched.
        """
        defaults = sheet_model.text_defaults

        if defaults.is_empty():
            if _TEXT_DEFAULTS_NAME in worksheet.defined_names:
                del worksheet.defined_names[_TEXT_DEFAULTS_NAME]
        else:
            payload = json.dumps(defaults.to_dict(), separators=(",", ":"))
            worksheet.defined_names[_TEXT_DEFAULTS_NAME] = DefinedName(
                _TEXT_DEFAULTS_NAME,
                attr_text='"' + payload.replace('"', '""') + '"',
                hidden=True,
            )

        overrides = sheet_model.cell_styles

        if defaults.is_empty() and not overrides:
            return

        columns = list(dataframe.columns)
        column_index = {name: index + 1 for index, name in enumerate(columns)}
        row_count = len(dataframe)
        fonts: dict[tuple, Font] = {}

        def font_for(style: CellStyle) -> Font:
            key = tuple(sorted(style.to_dict().items()))

            if key not in fonts:
                fonts[key] = self._font_for_style(style)

            return fonts[key]

        if not defaults.is_empty():
            # Every data cell carries the default (plus its override, if any).
            for position in range(row_count):
                row_overrides = overrides.get(position, {})

                for name, column in column_index.items():
                    override = row_overrides.get(name)
                    style = override.merged_over(defaults) if override else defaults
                    worksheet.cell(row=position + 2, column=column).font = font_for(style)

            return

        for position, row_overrides in overrides.items():
            if position >= row_count:
                continue

            for name, override in row_overrides.items():
                column = column_index.get(name)

                if column is None:
                    continue

                worksheet.cell(row=position + 2, column=column).font = font_for(override)

    def _read_text_styles(
        self,
        worksheet: Any,
        headers: Any,
    ) -> tuple[CellStyle, dict[int, dict[str, CellStyle]]]:
        """
        Read a worksheet's default text style and per-cell overrides.

        The default comes from the hidden defined name written by
        _write_text_styles (absent for a file Excelence didn't write).
        A cell is an override for exactly the fields where its font
        differs from that default (or from Excel's own baseline of
        Calibri 11 when there is none), so styling from a workbook made
        elsewhere is picked up too. Never raises on odd input: a foreign
        or hand-edited file must still open.
        """
        defaults = CellStyle()
        marker = worksheet.defined_names.get(_TEXT_DEFAULTS_NAME)

        if marker is not None and isinstance(marker.attr_text, str):
            text = marker.attr_text.strip()

            if len(text) >= 2 and text[0] == '"' and text[-1] == '"':
                try:
                    defaults = CellStyle.from_dict(
                        json.loads(text[1:-1].replace('""', '"'))
                    )
                except ValueError:
                    defaults = CellStyle()

        columns = [str(header) for header in headers]
        overrides: dict[int, dict[str, CellStyle]] = {}

        if not columns:
            return defaults, overrides

        effective = defaults.merged_over(CellStyle(
            bold=False,
            italic=False,
            underline=False,
            strikethrough=False,
            font_family=_BASE_FONT_FAMILY,
            font_size=_BASE_FONT_SIZE,
            color=_BASE_FONT_COLOR,
        ))

        for row in worksheet.iter_rows(min_row=2, max_col=len(columns)):
            for cell in row:
                if not cell.has_style:
                    continue

                override = self._font_override(cell.font, effective)

                if override.is_empty():
                    continue

                overrides.setdefault(cell.row - 2, {})[columns[cell.column - 1]] = override

        return defaults, overrides

    def _font_override(self, font: Any, effective: CellStyle) -> CellStyle:
        """The fields in which ``font`` differs from the ``effective`` base."""
        found: dict[str, Any] = {}

        for field_name, value in (
            ("bold", bool(font.b)),
            ("italic", bool(font.i)),
            ("underline", font.u not in (None, "none")),
            ("strikethrough", bool(font.strike)),
        ):
            if value != bool(getattr(effective, field_name)):
                found[field_name] = value

        name = font.name

        if isinstance(name, str) and name.strip() and name.strip() != effective.font_family:
            found["font_family"] = name.strip()

        size = font.sz

        if (
            isinstance(size, (int, float))
            and not isinstance(size, bool)
            and abs(float(size) - float(effective.font_size)) > 1e-6
        ):
            found["font_size"] = float(size)

        color = font.color

        if color is not None and color.type == "rgb" and isinstance(color.rgb, str):
            rgb = color.rgb[-6:].upper()

            if rgb != (effective.color or _BASE_FONT_COLOR):
                found["color"] = rgb

        # from_dict drops anything invalid (e.g. an out-of-range size)
        # instead of raising.
        return CellStyle.from_dict(found)

    def _read_column_widths(self, worksheet: Any, headers: Any) -> dict[str, float]:
        """
        Translate a worksheet's native column_dimensions (keyed by
        letter, e.g. "A", "B") into a dict keyed by the current header
        name at that position, matching how Sheet.column_widths is
        keyed everywhere else.

        Args:
            worksheet: The openpyxl worksheet to read widths from.
            headers: The dataframe's columns, in position order - letter
                position N corresponds to headers[N - 1].

        Returns:
            A dict of header name to width, omitting any column with no
            explicitly set width (openpyxl only stores dimensions that
            were actually set, not every column up to max_column).
        """
        widths: dict[str, float] = {}

        for position, name in enumerate(headers, start=1):
            letter = get_column_letter(position)
            dimension = worksheet.column_dimensions.get(letter)

            if dimension is not None and dimension.width is not None:
                widths[str(name)] = dimension.width

        return widths

    def _write_column_widths(self, worksheet: Any, headers: Any, widths: dict[str, float]) -> None:
        """
        Write a Sheet's name-keyed column_widths back onto the worksheet
        as native openpyxl column_dimensions (letter-keyed), the inverse
        of _read_column_widths. Called after write_sheet() rebuilds the
        worksheet's rows, since column_dimensions lives independently of
        row data and isn't touched by that rebuild - this just keeps the
        two in sync with the current header order.

        Authoritative, not additive: every letter position up to the
        current header count is either set to its current width or
        explicitly cleared. Without the clear, a width set before a
        column was deleted or reordered would linger on the worksheet
        under its old letter and silently reattach itself to whatever
        column shifts into that position later (column_dimensions is
        letter-keyed and outlives the dataframe reshape that
        write_sheet/delete_column/insert_column perform).

        Args:
            worksheet: The openpyxl worksheet to write widths onto.
            headers: The dataframe's columns, in position order.
            widths: Header name to width, as stored on the Sheet model.
        """
        for position, name in enumerate(headers, start=1):
            letter = get_column_letter(position)
            width = widths.get(str(name))

            if width is not None:
                worksheet.column_dimensions[letter].width = width
            elif letter in worksheet.column_dimensions:
                del worksheet.column_dimensions[letter]

    def _clear_view_data(self) -> None:
        """Reset the in-memory DataFrame view state."""
        self.df = pd.DataFrame()
        self.filtered_df = pd.DataFrame()

    def _active_sheet_model(self) -> Sheet | None:
        """Return the current domain-sheet model for the active workbook sheet."""
        return self.spreadsheet.current_sheet()

    def _sync_from_active_sheet(self) -> None:
        """Synchronize the document view state from the active sheet model."""
        active_sheet = self._active_sheet_model()

        if active_sheet is None:
            self._clear_view_data()
            return

        self.df = active_sheet.dataframe
        self.filtered_df = active_sheet.active_view if active_sheet.active_view is not None else active_sheet.dataframe

    def _set_view_data(self, dataframe: pd.DataFrame, apply_search: bool = False) -> None:
        """Populate the active DataFrame view and optionally reapply search state."""
        self.df = dataframe
        self.filtered_df = dataframe.copy()

        if apply_search:
            self.search(self.search_text)

    def spreadsheet_to_dataframe(self) -> None:

        sheet = self.spreadsheet.current_sheet()

        if sheet is None:

            self._clear_view_data()

            return

        rows = [

            row.values

            for row in sheet.rows

        ]

        self._set_view_data(pd.DataFrame(rows))