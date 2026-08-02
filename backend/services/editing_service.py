from typing import Any


class EditingService:

    def edit_cell(
        self,
        spreadsheet: Any,
        row: int,
        column: int,
        value: Any
    ) -> bool:

        return spreadsheet.edit_cell(
            row,
            column,
            value
        )

    def insert_row(
        self,
        spreadsheet: Any,
        index: int | None = None
    ) -> bool:

        return spreadsheet.insert_row(index)

    def delete_row(
        self,
        spreadsheet: Any,
        index: int
    ) -> bool:

        return spreadsheet.delete_row(index)