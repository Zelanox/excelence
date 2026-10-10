from backend.commands.command import Command


class AppendRowCommand(Command):

    def __init__(
        self,
        document,
        first_value
    ):
        self.document = document
        self.first_value = first_value

    def execute(self):
        return self.document.append_row(self.first_value)
