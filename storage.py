import pandas as pd

import json

import os


class Storage:

    def __init__(self):

        self.config_file = "viewer_config.json"

    def load_excel(self, filename):

        return pd.read_excel(filename)

    def save_excel(self, dataframe, filename):

        dataframe.to_excel(
            filename,
            index=False
        )

    def load_last(self):

        return self.load_last_file()

    # -----------------------------
    # Config
    # -----------------------------

    def save_last_file(self, filename):

        with open(self.config_file, "w") as f:

            json.dump(
                {
                    "last_file": filename
                },
                f
            )


    def load_last_file(self):

        if not os.path.exists(self.config_file):

            return None

        try:

            with open(self.config_file, "r") as f:

                data = json.load(f)

            filename = data.get("last_file")

            if filename and os.path.exists(filename):

                return filename

        except Exception:

            pass

        return None