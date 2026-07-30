class InsertColumnCommand:

    def __init__(self, document, name, index=None):

        self.document = document
        self.name = name
        self.index = index

    def execute(self):

        return self.document.insert_column(
            self.name,
            self.index
        )