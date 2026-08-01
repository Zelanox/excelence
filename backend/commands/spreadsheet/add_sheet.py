from backend.commands.command import Command


class AddSheetCommand(Command):

    def __init__(

        self,

        document,

        name
    ):

        self.document = document
        self.name = name

    def execute(self):

        return self.document.add_sheet(
            self.name
        )