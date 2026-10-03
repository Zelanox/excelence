from backend.commands.command import Command


class UndoCommand(Command):

    def __init__(self, document):
        self.document = document

    def execute(self):
        return self.document.undo()
