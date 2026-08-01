from abc import ABC, abstractmethod


class Command(ABC):

    @abstractmethod
    def execute(self):
        pass

    def undo(self):
        return False

    def redo(self):
        return self.execute()