from collections import deque


class SaveManager:

    # =====================================================
    # Structure
    # =====================================================

    # {
    #
    #   "Inventory.xlsx":
    #
    #   {
    #       "saving": "client-id",
    #       "queue": deque([...])
    #   }
    #
    # }

    _documents = {}

    # =====================================================
    # Internal
    # =====================================================

    @classmethod
    def _ensure(cls, document):

        if document not in cls._documents:

            cls._documents[document] = {

                "saving": None,

                "queue": deque()

            }

        return cls._documents[document]

    # =====================================================
    # Request Save
    # =====================================================

    @classmethod
    def request_save(cls, document, owner):

        doc = cls._ensure(document)

        # Nobody saving
        if doc["saving"] is None:

            doc["saving"] = owner

            print(f"{owner} granted save lock on {document}")

            return {

                "status": protocol.SAVE_GRANTED,

                "position": 0

            }

        # Already owns the save lock
        if doc["saving"] == owner:

            return {

                "status": protocol.SAVE_GRANTED,

                "position": 0

            }

        # Already waiting
        if owner in doc["queue"]:

            return {

                "status": protocol.SAVE_QUEUED,

                "position": list(doc["queue"]).index(owner) + 1

            }

        # Join queue
        doc["queue"].append(owner)

        print(f"{owner} queued for {document}")

        return {

            "status": protocol.SAVE_QUEUED,

            "position": len(doc["queue"])

        }

    # =====================================================
    # Finish Save
    # =====================================================

    @classmethod
    def finish_save(cls, document):

        doc = cls._ensure(document)

        finished = doc["saving"]

        if finished is None:

            return None

        print(f"{finished} finished saving {document}")

        if len(doc["queue"]) == 0:

            doc["saving"] = None

            return None

        next_owner = doc["queue"].popleft()

        doc["saving"] = next_owner

        print(f"{next_owner} granted save lock")

        return next_owner

    # =====================================================
    # Cancel Waiting
    # =====================================================

    @classmethod
    def cancel_request(cls, document, owner):

        doc = cls._ensure(document)

        if owner == doc["saving"]:

            cls.finish_save(document)

            return True

        if owner in doc["queue"]:

            doc["queue"].remove(owner)

            print(f"{owner} removed from queue")

            return True

        return False

    # =====================================================
    # Current Saver
    # =====================================================

    @classmethod
    def current_owner(cls, document):

        doc = cls._ensure(document)

        return doc["saving"]

    # =====================================================
    # Queue
    # =====================================================

    @classmethod
    def queue(cls, document):

        doc = cls._ensure(document)

        return list(doc["queue"])

    # =====================================================
    # Queue Position
    # =====================================================

    @classmethod
    def queue_position(cls, document, owner):

        doc = cls._ensure(document)

        if owner == doc["saving"]:

            return 0

        if owner not in doc["queue"]:

            return -1

        return list(doc["queue"]).index(owner) + 1

    # =====================================================
    # Is Saving
    # =====================================================

    @classmethod
    def is_saving(cls, document):

        doc = cls._ensure(document)

        return doc["saving"] is not None

    # =====================================================
    # Clear Document
    # =====================================================

    @classmethod
    def clear(cls, document):

        if document in cls._documents:

            del cls._documents[document]

    # =====================================================
    # Debug
    # =====================================================

    @classmethod
    def debug(cls):

        print()

        print("========== SAVE MANAGER ==========")

        for document, state in cls._documents.items():

            print(document)

            print("Saving :", state["saving"])

            print("Queue  :", list(state["queue"]))

            print()

        print("==================================")