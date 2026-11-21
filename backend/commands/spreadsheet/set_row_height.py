from backend.commands.command import Command


class SetRowHeightCommand(Command):

    def __init__(self, document, row_id, height):
        self.document = document
        self.row_id = row_id
        self.height = height

    def execute(self):
        return self.document.set_row_height(self.row_id, self.height)
