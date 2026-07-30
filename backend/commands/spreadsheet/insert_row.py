class InsertRowCommand:

    def __init__(self, document, index=None):

        self.document = document
        self.index = index

    def execute(self):

        return self.document.insert_row(self.index)