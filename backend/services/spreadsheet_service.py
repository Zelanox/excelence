from backend.commands.manager import CommandManager

from backend.commands.spreadsheet.edit_cell import EditCellCommand
from backend.commands.spreadsheet.insert_row import InsertRowCommand
from backend.commands.spreadsheet.delete_row import DeleteRowCommand

from backend.commands.spreadsheet.insert_column import InsertColumnCommand
from backend.commands.spreadsheet.delete_column import DeleteColumnCommand

from backend.commands.spreadsheet.search import SearchCommand
from backend.commands.spreadsheet.clear_search import ClearSearchCommand


class SpreadsheetService:
    """
    Coordinates spreadsheet operations.

    Controllers call this service.
    Services execute commands.
    Commands manipulate the document.
    """

    def __init__(self, document):
        self.document = document
        self.command_manager = CommandManager()

    # ------------------------------------------------------
    # Editing
    # ------------------------------------------------------

    def edit_cell(self, row: int, column: int, value) -> bool:
        command = EditCellCommand(
            self.document,
            row,
            column,
            value,
        )

        return self.command_manager.execute(command)

    def insert_row(self, index: int | None = None) -> bool:
        command = InsertRowCommand(
            self.document,
            index,
        )

        return self.command_manager.execute(command)


    def delete_row(self, index: int) -> bool:
        command = DeleteRowCommand(
            self.document,
            index,
        )

        return self.command_manager.execute(command)


    def insert_column(self, name: str, index: int | None = None) -> bool:
        command = InsertColumnCommand(
            self.document,
            name,
            index,
        )

        return self.command_manager.execute(command)


    def delete_column(self, name: str) -> bool:
        command = DeleteColumnCommand(
            self.document,
            name,
        )

        return self.command_manager.execute(command)

    def search(self, text: str) -> bool:
        command = SearchCommand(
            self.document,
            text,
        )

        return self.command_manager.execute(command)


    def clear_search(self) -> bool:
        command = ClearSearchCommand(
            self.document,
        )

        return self.command_manager.execute(command)

    def sort(self, sort_rules: list[dict]) -> bool:
        command = SortCommand(
            self.document,
            sort_rules,
        )

        return self.command_manager.execute(command)


    def clear_sort(self) -> bool:
        command = ClearSortCommand(
            self.document,
        )

        return self.command_manager.execute(command)

    def add_sheet(self, name: str) -> bool:
        command = AddSheetCommand(
            self.document,
            name,
        )

        return self.command_manager.execute(command)


    def rename_sheet(self, old_name: str, new_name: str) -> bool:
        command = RenameSheetCommand(
            self.document,
            old_name,
            new_name,
        )

        return self.command_manager.execute(command)


    def delete_sheet(self, name: str) -> bool:
        command = DeleteSheetCommand(
            self.document,
            name,
        )

        return self.command_manager.execute(command)