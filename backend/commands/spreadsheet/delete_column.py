from backend.commands.command import Command


class DeleteColumnCommand(Command):

    def __init__(
        self,
        document,
        name
    ):
        self.document = document
        self.name = name

    def execute(self):
        return self.document.delete_column(
            self.name
        )