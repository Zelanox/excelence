import time


class DocumentLock:

    _locked = False
    _owner = None
    _timestamp = None


    @classmethod
    def lock(cls, owner):

        """
        Attempt to lock the document.

        Returns:
            True  -> Lock acquired
            False -> Already locked
        """

        if cls._locked:
            return False

        cls._locked = True
        cls._owner = owner
        cls._timestamp = time.time()

        print(f"Document locked by {owner}")

        return True


    @classmethod
    def unlock(cls, owner):

        """
        Release the document lock.

        Only the owner may unlock it.
        """

        if not cls._locked:
            return True

        if cls._owner != owner:
            return False

        cls._locked = False
        cls._owner = None
        cls._timestamp = None

        print(f"Document unlocked by {owner}")

        return True


    @classmethod
    def is_locked(cls):

        return cls._locked


    @classmethod
    def owner(cls):

        return cls._owner


    @classmethod
    def info(cls):

        return {
            "locked": cls._locked,
            "owner": cls._owner,
            "timestamp": cls._timestamp
        }


    @classmethod
    def force_unlock(cls):

        """
        Administrator function.
        """

        cls._locked = False
        cls._owner = None
        cls._timestamp = None

        print("Document force unlocked.")