class CommandManager:

    def __init__(self):

        self.history = []

    def execute(self, command):

        result = command.execute()

        if result:
            self.history.append(command)

        return result