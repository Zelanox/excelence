import json
import os


METADATA_FILE = "cache/metadata.json"


class ClientMetadata:


    @staticmethod
    def load():

        if not os.path.exists(METADATA_FILE):

            data = {
                "version": 0
            }

            ClientMetadata.save(data)

            return data

        try:

            with open(METADATA_FILE, "r", encoding="utf-8") as file:

                return json.load(file)

        except (json.JSONDecodeError, OSError):

            data = {
                "version": 0
            }

            ClientMetadata.save(data)

            return data


    @staticmethod
    def save(data):

        os.makedirs(
            os.path.dirname(METADATA_FILE),
            exist_ok=True
        )

        with open(METADATA_FILE, "w", encoding="utf-8") as file:

            json.dump(
                data,
                file,
                indent=4
            )


    @staticmethod
    def current():

        return ClientMetadata.load()["version"]


    @staticmethod
    def set(version):

        data = ClientMetadata.load()

        data["version"] = version

        ClientMetadata.save(data)