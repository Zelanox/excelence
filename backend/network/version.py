import json
import os
from datetime import datetime

import config


class VersionManager:

    FILE = os.path.join(
        config.BASE_DIR,
        "versions.json"
    )

    # =====================================
    # Internal
    # =====================================

    @classmethod
    def _load(cls):

        if not os.path.exists(cls.FILE):

            return {}

        with open(
            cls.FILE,
            "r",
            encoding="utf-8"
        ) as f:

            return json.load(f)

    @classmethod
    def _save(cls, versions):

        with open(
            cls.FILE,
            "w",
            encoding="utf-8"
        ) as f:

            json.dump(
                versions,
                f,
                indent=4
            )

    # =====================================
    # Public
    # =====================================

    @classmethod
    def exists(cls, document):

        versions = cls._load()

        return document in versions

    @classmethod
    def current(cls, document):

        versions = cls._load()

        if document not in versions:

            versions[document] = {

                "version":1,

                "last_modified":
                    datetime.now().isoformat()

            }

            cls._save(versions)

        return versions[document]["version"]

    @classmethod
    def increment(cls, document):

        versions = cls._load()

        if document not in versions:

            versions[document] = {

                "version":1,

                "last_modified":
                    datetime.now().isoformat()

            }

        else:

            versions[document]["version"] += 1

            versions[document]["last_modified"] = \
                datetime.now().isoformat()

        cls._save(versions)

        return versions[document]["version"]

    @classmethod
    def set(
        cls,
        document,
        version
    ):

        versions = cls._load()

        versions[document] = {

            "version": version,

            "last_modified":
                datetime.now().isoformat()

        }

        cls._save(versions)

    @classmethod
    def delete(cls, document):

        versions = cls._load()

        if document in versions:

            del versions[document]

            cls._save(versions)

    @classmethod
    def rename(
        cls,
        old_name,
        new_name
    ):

        versions = cls._load()

        if old_name not in versions:

            return

        versions[new_name] = versions.pop(old_name)

        cls._save(versions)

    @classmethod
    def info(cls, document):

        versions = cls._load()

        return versions.get(document)

    @classmethod
    def all(cls):

        return cls._load()