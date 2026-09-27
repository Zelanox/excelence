from backend.commands.command import Command


class SetColumnWidthCommand(Command):

    def __init__(
        self,
        document,
        name,
        width
    ):
        self.document = document
        self.name = name
        self.width = width

    def execute(self):
        return self.document.set_column_width(
            self.name,
            self.width
        )
