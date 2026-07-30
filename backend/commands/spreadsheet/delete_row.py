class DeleteRowCommand:

    def __init__(self, document, index):

        self.document = document
        self.index = index

    def execute(self):

        return self.document.delete_row(self.index)