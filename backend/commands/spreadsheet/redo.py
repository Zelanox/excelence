from backend.commands.command import Command


class RedoCommand(Command):

    def __init__(self, document):
        self.document = document

    def execute(self):
        return self.document.redo()
