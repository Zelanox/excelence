from backend.commands.command import Command


class SortCommand(Command):

    def __init__(

        self,

        document,

        rules
    ):

        self.document = document
        self.rules = rules

    def execute(self):

        return self.document.sort(
            self.rules
        )