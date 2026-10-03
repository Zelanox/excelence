from backend.commands.command import Command


class SetCellStyleCommand(Command):

    def __init__(
        self,
        document,
        start_row,
        start_column,
        end_row,
        end_column,
        values,
        reset
    ):
        self.document = document
        self.start_row = start_row
        self.start_column = start_column
        self.end_row = end_row
        self.end_column = end_column
        self.values = values
        self.reset = reset

    def execute(self):
        return self.document.set_cell_style(
            self.start_row,
            self.start_column,
            self.end_row,
            self.end_column,
            self.values,
            self.reset
        )
