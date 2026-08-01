from backend.commands.command import Command

class RenameSheetCommand(Command):

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

        return self.document.rename_sheet(

            self.old_name,

            self.new_name
        )