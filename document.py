import pandas as pd

class Document:

    def __init__(self, storage, network ):
        self.storage = storage
        self.network = network

        self.df = pd.DataFrame()

        self.filename = None

        self.product_column = None
        self.sort_rules = []

    def load(self, filename):

        self.filename = filename

        self.df = self.storage.load_excel(filename)

        self.product_column = self.df.columns[-1]

        self.storage.save_last_file(filename)
            
    # ---------------- Search ----------------
    def search(self, text):

        text = text.strip().lower()

        if text == "":
            return self.df

        mask = self.df.astype(str).apply(

            lambda row:
            row.str.lower().str.contains(
                text,
                na=False
            ).any(),

            axis=1
        )

        return self.df[mask]


    # ------------- Add Row ----------------
    def add_row(self, value):

        value = value.strip()

        if not value:
            return False

        new_row = {column: "" for column in self.df.columns}

        new_row[self.product_column] = value

        self.df.loc[len(self.df)] = new_row

        self.sort(self.sort_rules)

        return True

    # ------------- Sorting ----------------
    def sort(self, sort_rules):

        if not sort_rules:
            return

        columns = [rule["column"] for rule in sort_rules]
        ascending = [rule["ascending"] for rule in sort_rules]

        self.df.sort_values(
            by=columns,
            ascending=ascending,
            inplace=True,
            ignore_index=True
        )

    def update_cell(self, row, column_name, value):

        dtype = self.df[column_name].dtype

        try:
            if pd.api.types.is_integer_dtype(dtype):
                value = int(value)

            elif pd.api.types.is_float_dtype(dtype):
                value = float(value)

        except ValueError:
            raise ValueError(
                f"Please enter a valid {dtype}."
            )

        self.df.at[row, column_name] = value

    # -------------- Delete ----------------
    def delete_row(self, index):

        if self.df.empty:
            return False

        if index not in self.df.index:
            return False

        self.df = (
            self.df
            .drop(index)
            .reset_index(drop=True)
        )

        return True


    # ---------------- Save ----------------
    def save(self):

        if self.filename:

            self.storage.save_excel(
                self.df,
                self.filename
            )


    def save_as(self, filename):

        self.filename = filename

        self.storage.save_last_file(filename)

        self.save()

    def export_excel():
        pass

    def import_excel():
        pass