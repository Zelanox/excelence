from backend.commands.command import Command


class SetAppearanceCommand(Command):

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
        return self.document.set_appearance(
            self.values,
            self.reset
        )
