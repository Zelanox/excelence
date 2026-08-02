class EditingService:

    def edit_cell(
        self,
        spreadsheet,
        row,
        column,
        value
    ):

        return spreadsheet.edit_cell(
            row,
            column,
            value
        )

    def insert_row(
        self,
        spreadsheet,
        index=None
    ):

        return spreadsheet.insert_row(index)

    def delete_row(
        self,
        spreadsheet,
        index
    ):

        return spreadsheet.delete_row(index)