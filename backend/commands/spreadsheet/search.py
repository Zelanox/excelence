from backend.commands.command import Command


class SearchCommand(Command):

    def __init__(

        self,

        document,

        text
    ):

        self.document = document
        self.text = text

    def execute(self):

        return self.document.search(
            self.text
        )