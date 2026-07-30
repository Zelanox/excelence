from backend.commands.command import Command


class EditCellCommand(Command):

    def __init__(
        self,
        document,
        row,
        column,
        value
    ):
        self.document = document

        self.row = row
        self.column = column
        self.value = value

    def execute(self):

        return self.document.edit_cell(

            self.row,

            self.column,

            self.value
        )