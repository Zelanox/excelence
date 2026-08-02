from typing import Any, TYPE_CHECKING

from backend.commands.command import Command
from backend.commands.manager import CommandManager

from backend.commands.spreadsheet.edit_cell import EditCellCommand
from backend.commands.spreadsheet.insert_row import InsertRowCommand
from backend.commands.spreadsheet.delete_row import DeleteRowCommand
from backend.commands.spreadsheet.insert_column import InsertColumnCommand
from backend.commands.spreadsheet.delete_column import DeleteColumnCommand
from backend.commands.spreadsheet.search import SearchCommand
from backend.commands.spreadsheet.clear_search import ClearSearchCommand
from backend.commands.spreadsheet.sort import SortCommand
from backend.commands.spreadsheet.clear_sort import ClearSortCommand
from backend.commands.spreadsheet.add_sheet import AddSheetCommand
from backend.commands.spreadsheet.rename_sheet import RenameSheetCommand
from backend.commands.spreadsheet.delete_sheet import DeleteSheetCommand

if TYPE_CHECKING:
    from backend.document.document import Document


class SpreadsheetService:
    """Coordinate spreadsheet write operations through commands and the document layer."""

    def __init__(self, document: "Document") -> None:
        self.document = document
        self.command_manager: CommandManager = CommandManager()

    def _execute(self, command: Command) -> bool:
        """Execute a command through the shared command manager."""
        return self.command_manager.execute(command)

    # ------------------------------------------------------
    # Editing
    # ------------------------------------------------------

    def edit_cell(self, row: int, column: int, value: Any) -> bool:
        command = EditCellCommand(
            self.document,
            row,
            column,
            value,
        )

        return self._execute(command)

    def insert_row(self, index: int | None = None) -> bool:
        command = InsertRowCommand(
            self.document,
            index,
        )

        return self._execute(command)

    def delete_row(self, index: int) -> bool:
        command = DeleteRowCommand(
            self.document,
            index,
        )

        return self._execute(command)

    def insert_column(self, name: str, index: int | None = None) -> bool:
        command = InsertColumnCommand(
            self.document,
            name,
            index,
        )

        return self._execute(command)

    def delete_column(self, name: str) -> bool:
        command = DeleteColumnCommand(
            self.document,
            name,
        )

        return self._execute(command)

    def search(self, text: str) -> bool:
        command = SearchCommand(
            self.document,
            text,
        )

        return self._execute(command)

    def clear_search(self) -> bool:
        command = ClearSearchCommand(
            self.document,
        )

        return self._execute(command)

    def sort(self, sort_rules: list[dict[str, Any]]) -> bool:
        command = SortCommand(
            self.document,
            sort_rules,
        )

        return self._execute(command)

    def clear_sort(self) -> bool:
        command = ClearSortCommand(
            self.document,
        )

        return self._execute(command)

    def add_sheet(self, name: str) -> bool:
        command = AddSheetCommand(
            self.document,
            name,
        )

        return self._execute(command)

    def rename_sheet(self, old_name: str, new_name: str) -> bool:
        command = RenameSheetCommand(
            self.document,
            old_name,
            new_name,
        )

        return self._execute(command)

    def delete_sheet(self, name: str) -> bool:
        command = DeleteSheetCommand(
            self.document,
            name,
        )

        return self._execute(command)