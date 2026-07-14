import pandas as pd

import config
from network import protocol
from network.clientmetadata import ClientMetadata


class Document:

    def __init__(self, storage, network):

        self.storage = storage
        self.network = network

        self.df = pd.DataFrame()

        self.filename = None

        self.product_column = None
        self.sort_rules = []

    # --------------------------------------------------
    # Open document
    # --------------------------------------------------

    def load(self, filename):

        self.filename = filename

        #
        # ONLINE MODE
        #
        if self.network is not None:

            if not self.network.connect():
                raise ConnectionError(
                    "Unable to connect to server."
                )

            #
            # Ask server for lock
            #
            reply = self.network.open_document()

            if reply["status"] == protocol.LOCKED:

                self.network.disconnect()

                raise PermissionError(
                    "Document is currently being edited."
                )

            #
            # Version check
            #
            server_version = self.network.get_version()["version"]

            local_version = ClientMetadata.version()

            if server_version != local_version:

                print("Downloading newer document...")

                response = self.network.download_document()

                if response["status"] != "OK":

                    self.network.disconnect()

                    raise RuntimeError(
                        response.get(
                            "message",
                            "Download failed."
                        )
                    )

                ClientMetadata.set_version(server_version)

            #
            # Open local cache
            #
            self.filename = config.CACHE_FILE

        #
        # OFFLINE MODE
        #
        else:

            self.filename = filename

        #
        # Load dataframe
        #
        self.df = self.storage.load_excel(
            self.filename
        )

        self.product_column = self.df.columns[-1]

        self.storage.save_last_file(self.filename)

    # --------------------------------------------------
    # Search
    # --------------------------------------------------

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

    # --------------------------------------------------
    # Add row
    # --------------------------------------------------

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

    # --------------------------------------------------
    # Sort
    # --------------------------------------------------

    def sort(self, sort_rules):

        self.sort_rules = sort_rules

        if not sort_rules:
            return

        columns = [
            rule["column"]
            for rule in sort_rules
        ]

        ascending = [
            rule["ascending"]
            for rule in sort_rules
        ]

        self.df.sort_values(

            by=columns,

            ascending=ascending,

            inplace=True,

            ignore_index=True

        )

    # --------------------------------------------------
    # Edit
    # --------------------------------------------------

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

    # --------------------------------------------------
    # Delete
    # --------------------------------------------------

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

    # --------------------------------------------------
    # Save
    # --------------------------------------------------

    def save(self):

        if not self.filename:
            return

        #
        # Save locally
        #
        self.storage.save_excel(
            self.df,
            self.filename
        )

        #
        # Upload if connected
        #
        if self.network is not None:
            
            try:

                response = self.network.upload_document()

                if response["status"] == "OK":

                    ClientMetadata.set_version(
                        response["version"]
                    )
            
            except Exception as e:
                print(e)

                return

    # --------------------------------------------------
    # Save As
    # --------------------------------------------------

    def save_as(self, filename):

        self.filename = filename

        self.storage.save_last_file(filename)

        self.save()

    # --------------------------------------------------
    # Close
    # --------------------------------------------------

    def close(self):

        if self.network is None:
            return

        try:

            self.save()

            self.network.close_document()

        finally:

            self.network.disconnect()

    # --------------------------------------------------

    def export_excel(self):
        pass

    def import_excel(self):
        pass