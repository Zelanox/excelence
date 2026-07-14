import pandas as pd

import config


class Document:

    def __init__(self, storage, network, online=False):

        self.storage = storage
        self.network = network
        self.online = online

        self.df = pd.DataFrame()

        self.filename = None

        self.product_column = None
        self.sort_rules = []


    # -------------------------------------------------
    # Open
    # -------------------------------------------------

    def open(self, filename):

        self.filename = filename

        if self.online:

            try:

                self.network.connect()

                server_version = self.network.get_version()

                local_version = self.storage.get_local_version()

                if server_version > local_version:

                    print("Downloading newer version...")

                    reply = self.network.download_document()

                    if reply["status"] == "OK":

                        filename = reply["path"]

                        self.storage.set_local_version(
                            server_version
                        )

                lock = self.network.lock_document()

                if lock["status"] != "OK":

                    raise RuntimeError(
                        lock.get(
                            "message",
                            "Document is already locked."
                        )
                    )

            except Exception as e:

                print(f"Network error: {e}")
                print("Falling back to offline mode.")

                self.online = False

            finally:

                self.network.disconnect()

        self.load(filename)


    # -------------------------------------------------
    # Load
    # -------------------------------------------------

    def load(self, filename):

        self.filename = filename

        self.df = self.storage.load_excel(filename)

        self.product_column = self.df.columns[-1]

        self.storage.save_last_file(filename)


    # -------------------------------------------------
    # Search
    # -------------------------------------------------

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


    # -------------------------------------------------
    # Add Row
    # -------------------------------------------------

    def add_row(self, value):

        value = value.strip()

        if not value:
            return False

        new_row = {

            column: ""

            for column in self.df.columns

        }

        new_row[self.product_column] = value

        self.df.loc[len(self.df)] = new_row

        self.sort(self.sort_rules)

        return True


    # -------------------------------------------------
    # Sort
    # -------------------------------------------------

    def sort(self, sort_rules):

        self.sort_rules = sort_rules

        if not sort_rules:
            return

        columns = [
            rule["column"]
            for rule in sort_rules
        ]

        ascending = [
            rule["تصاعدي"]
            for rule in sort_rules
        ]

        self.df.sort_values(

            by=columns,

            ascending=ascending,

            inplace=True,

            ignore_index=True

        )


    # -------------------------------------------------
    # Update Cell
    # -------------------------------------------------

    def update_cell(
        self,
        row,
        column_name,
        value
    ):

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


    # -------------------------------------------------
    # Delete
    # -------------------------------------------------

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


    # -------------------------------------------------
    # Save
    # -------------------------------------------------

    def save(self):

        if self.filename:

            self.storage.save_excel(

                self.df,

                self.filename

            )

            if self.online:

                try:

                    self.network.connect()

                    self.network.upload_document()

                finally:

                    self.network.disconnect()


    def save_as(self, filename):

        self.filename = filename

        self.storage.save_last_file(filename)

        self.save()


    # -------------------------------------------------
    # Close
    # -------------------------------------------------

    def close(self):

        if not self.online:
            return

        try:

            self.network.connect()

            self.network.unlock_document()

        except Exception:

            pass

        finally:

            self.network.disconnect()


    # -------------------------------------------------

    def export_excel(self):
        pass


    def import_excel(self):
        pass