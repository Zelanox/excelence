import json
import os


VERSION_FILE = "storage/metadata.json"


class VersionManager:


    @staticmethod
    def load():

        if not os.path.exists(VERSION_FILE):

            data = {
                "version": 1
            }

            VersionManager.save(data)

            return data

        try:

            with open(
                VERSION_FILE,
                "r",
                encoding="utf-8"
            ) as file:

                return json.load(file)

        except (
            json.JSONDecodeError,
            OSError
        ):

            data = {
                "version": 1
            }

            VersionManager.save(data)

            return data


    @staticmethod
    def save(data):

        os.makedirs(
            os.path.dirname(VERSION_FILE),
            exist_ok=True
        )

        with open(
            VERSION_FILE,
            "w",
            encoding="utf-8"
        ) as file:

            json.dump(
                data,
                file,
                indent=4,
                ensure_ascii=False
            )


    @staticmethod
    def current():

        return VersionManager.load()["version"]


    @staticmethod
    def increment():

        data = VersionManager.load()

        data["version"] += 1

        VersionManager.save(data)

        return data["version"]


    @staticmethod
    def set(version):

        data = {
            "version": version
        }

        VersionManager.save(data)


    @staticmethod
    def reset():

        VersionManager.set(1)