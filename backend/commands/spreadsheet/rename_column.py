from backend.commands.command import Command


class RenameColumnCommand(Command):

    def __init__(
        self,
        document,
        old_name,
        new_name
    ):
        self.document = document
        self.old_name = old_name
        self.new_name = new_name

    def execute(self):
        return self.document.rename_column(
            self.old_name,
            self.new_name
        )