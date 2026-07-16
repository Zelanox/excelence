import pandas as pd


class Document:

    def __init__(self, storage, network, online=False):

        self.storage = storage
        self.network = network
        self.online = online

        self.df = pd.DataFrame()

        self.filename = None

        self.product_column = None
        self.sort_rules = []

        self.modified = False


    # ==========================================================
    # Open
    # ==========================================================

    def open(self, filename):

        self.filename = filename

        if self.online:

            try:

                if not self.network.connect():

                    raise ConnectionError(
                        "Unable to connect."
                    )

                server_version = self.network.get_version()

                local_version = self.network.local_version()

                if server_version > local_version:

                    print("Downloading newer version...")

                    reply = self.network.download_document()

                    if reply["status"] == "OK":

                        filename = reply["path"]

                reply = self.network.open_document()

                if reply["status"] != "OK":

                    raise RuntimeError(

                        reply.get(

                            "message",

                            "Document is locked."

                        )

                    )

            except Exception as e:

                print("Network error:", e)

                print("Falling back to offline mode.")

                self.online = False

                self.network.disconnect()

        self.load(filename)


    # ==========================================================
    # Load
    # ==========================================================

    def load(self, filename):

        self.filename = filename

        self.df = self.storage.load_excel(filename)

        self.product_column = self.df.columns[-1]

        self.storage.save_last_file(filename)


    # ==========================================================
    # Search
    # ==========================================================

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


    # ==========================================================
    # Add Row
    # ==========================================================

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

        self.modified = True

        self.sort(self.sort_rules)

        return True


    # ==========================================================
    # Sort
    # ==========================================================

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


    # ==========================================================
    # Update Cell
    # ==========================================================

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

        self.modified = True


    # ==========================================================
    # Delete Row
    # ==========================================================

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

        self.modified = True

        return True


    # ==========================================================
    # Save
    # ==========================================================

    def save(self):

        if not self.filename:

            return

        self.storage.save_excel(

            self.df,

            self.filename

        )


    def save_as(self, filename):

        self.filename = filename

        self.storage.save_last_file(filename)

        self.save()


    # ==========================================================
    # Close
    # ==========================================================

    def close(self):

        self.save()

        if not self.online:

            return

        try:

            if self.modified:

                reply = self.network.upload_document()

                if reply["status"] == "OK":

                    self.modified = False

            self.network.close_document()

        except Exception as e:

            print("Shutdown error:", e)

        finally:

            self.network.disconnect()


    # ==========================================================
    # Import / Export
    # ==========================================================

    def export_excel(self):

        pass


    def import_excel(self):

        pass