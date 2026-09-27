from backend.commands.command import Command


class SetRtlCommand(Command):

    def __init__(
        self,
        document,
        rtl
    ):
        self.document = document
        self.rtl = rtl

    def execute(self):
        return self.document.set_rtl(
            self.rtl
        )
