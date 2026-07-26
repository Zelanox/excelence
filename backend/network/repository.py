import os

import config


class Repository:

    # ==========================================
    # Root Folder
    # ==========================================

    ROOT = os.path.join(
        config.BASE_DIR,
        "Documents"
    )

    @classmethod
    def initialize(cls):

        os.makedirs(
            cls.ROOT,
            exist_ok=True
        )

    # ==========================================
    # Path Helpers
    # ==========================================

    @classmethod
    def path(cls, document):

        return os.path.join(
            cls.ROOT,
            document
        )

    @classmethod
    def exists(cls, document):

        return os.path.exists(
            cls.path(document)
        )

    # ==========================================
    # Listing
    # ==========================================

    @classmethod
    def list_documents(cls):

        cls.initialize()

        documents = []

        for file in os.listdir(cls.ROOT):

            full = cls.path(file)

            if os.path.isfile(full):

                documents.append(file)

        documents.sort()

        return documents

    # ==========================================
    # Create
    # ==========================================

    @classmethod
    def create(cls, document):

        cls.initialize()

        filename = cls.path(document)

        if os.path.exists(filename):

            return False

        open(filename, "wb").close()

        return True

    # ==========================================
    # Delete
    # ==========================================

    @classmethod
    def delete(cls, document):

        filename = cls.path(document)

        if not os.path.exists(filename):

            return False

        os.remove(filename)

        return True

    # ==========================================
    # Rename
    # ==========================================

    @classmethod
    def rename(
        cls,
        old_name,
        new_name
    ):

        old_file = cls.path(old_name)

        new_file = cls.path(new_name)

        if not os.path.exists(old_file):

            return False

        if os.path.exists(new_file):

            return False

        os.rename(
            old_file,
            new_file
        )

        return True

    # ==========================================
    # File Size
    # ==========================================

    @classmethod
    def size(cls, document):

        filename = cls.path(document)

        if not os.path.exists(filename):

            return 0

        return os.path.getsize(filename)

    # ==========================================
    # Information
    # ==========================================

    @classmethod
    def info(cls, document):

        filename = cls.path(document)

        if not os.path.exists(filename):

            return None

        stat = os.stat(filename)

        return {

            "name": document,

            "size": stat.st_size,

            "modified": stat.st_mtime
        }