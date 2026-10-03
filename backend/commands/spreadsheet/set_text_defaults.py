from backend.commands.command import Command


class SetTextDefaultsCommand(Command):

    def __init__(
        self,
        document,
        values,
        reset
    ):
        self.document = document
        self.values = values
        self.reset = reset

    def execute(self):
        return self.document.set_text_defaults(
            self.values,
            self.reset
        )
