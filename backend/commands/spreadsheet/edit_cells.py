from backend.commands.command import Command


class EditCellsCommand(Command):

    def __init__(
        self,
        document,
        edits
    ):
        self.document = document
        self.edits = edits

    def execute(self):
        return self.document.edit_cells(self.edits)
