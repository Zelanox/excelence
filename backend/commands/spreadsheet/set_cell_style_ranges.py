from backend.commands.command import Command


class SetCellStyleRangesCommand(Command):

    def __init__(
        self,
        document,
        ranges,
        values,
        reset
    ):
        self.document = document
        self.ranges = ranges
        self.values = values
        self.reset = reset

    def execute(self):
        return self.document.set_cell_style_ranges(
            self.ranges,
            self.values,
            self.reset
        )
