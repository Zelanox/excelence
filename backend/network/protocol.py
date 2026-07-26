import json

# ==========================================================
# Protocol
# ==========================================================

PROTOCOL_VERSION = 2


# ==========================================================
# Generic Status
# ==========================================================

OK = "OK"
ERROR = "ERROR"

READY = "READY"

DENIED = "DENIED"

LOCKED = "LOCKED"


# ==========================================================
# Utility
# ==========================================================

PING = "PING"

GET_SERVER_INFO = "GET_SERVER_INFO"


# ==========================================================
# Repository
# ==========================================================

LIST_DOCUMENTS = "LIST_DOCUMENTS"

DOCUMENT_INFO = "DOCUMENT_INFO"

CREATE_DOCUMENT = "CREATE_DOCUMENT"

DELETE_DOCUMENT = "DELETE_DOCUMENT"

RENAME_DOCUMENT = "RENAME_DOCUMENT"


# ==========================================================
# File Transfer
# ==========================================================

DOWNLOAD_DOCUMENT = "DOWNLOAD_DOCUMENT"

UPLOAD_DOCUMENT = "UPLOAD_DOCUMENT"

IMPORT_DOCUMENT = "IMPORT_DOCUMENT"

EXPORT_DOCUMENT = "EXPORT_DOCUMENT"


# ==========================================================
# Editing
# ==========================================================

BEGIN_EDIT = "BEGIN_EDIT"

END_EDIT = "END_EDIT"


# ==========================================================
# Synchronization
# ==========================================================

GET_VERSION = "GET_VERSION"

GET_OPERATIONS = "GET_OPERATIONS"

PUSH_OPERATIONS = "PUSH_OPERATIONS"


# ==========================================================
# Save Queue
# ==========================================================

REQUEST_SAVE = "REQUEST_SAVE"

SAVE_GRANTED = "SAVE_GRANTED"

SAVE_QUEUED = "SAVE_QUEUED"

SAVE_FINISHED = "SAVE_FINISHED"


# ==========================================================
# Packet Builders
# ==========================================================

def make_request(
    command,
    document=None,
    owner=None,
    data=None
):

    if data is None:
        data = {}

    packet = {

        "protocol": PROTOCOL_VERSION,

        "command": command,

        "document": document,

        "owner": owner,

        "data": data
    }

    return json.dumps(
        packet,
        ensure_ascii=False
    ).encode("utf-8")


def make_response(
    status,
    data=None
):

    if data is None:
        data = {}

    packet = {

        "protocol": PROTOCOL_VERSION,

        "status": status,

        "data": data
    }

    return json.dumps(
        packet,
        ensure_ascii=False
    ).encode("utf-8")


# ==========================================================
# Validators
# ==========================================================

def validate_request(packet):

    if packet.get("protocol") != PROTOCOL_VERSION:

        raise ValueError("Unsupported protocol version.")

    if "command" not in packet:

        raise ValueError("Missing command.")

    packet.setdefault("document", None)

    packet.setdefault("owner", None)

    packet.setdefault("data", {})

    return packet


def validate_response(packet):

    if packet.get("protocol") != PROTOCOL_VERSION:

        raise ValueError("Unsupported protocol version.")

    if "status" not in packet:

        raise ValueError("Missing status.")

    packet.setdefault("data", {})

    return packet


# ==========================================================
# Readers
# ==========================================================

def read_request(data):

    if not data:

        raise ConnectionError(
            "No request received."
        )

    try:

        packet = json.loads(
            data.decode("utf-8")
        )

        return validate_request(packet)

    except json.JSONDecodeError as error:

        raise ValueError(
            f"Invalid request packet: {error}"
        )


def read_response(data):

    if not data:

        raise ConnectionError(
            "No response received."
        )

    try:

        packet = json.loads(
            data.decode("utf-8")
        )

        return validate_response(packet)

    except json.JSONDecodeError as error:

        raise ValueError(
            f"Invalid response packet: {error}"
        )


# ==========================================================
# Debug
# ==========================================================

def print_request(packet):

    print("\nCLIENT -> SERVER")

    print(
        json.dumps(
            packet,
            indent=4,
            ensure_ascii=False
        )
    )


def print_response(packet):

    print("\nSERVER -> CLIENT")

    print(
        json.dumps(
            packet,
            indent=4,
            ensure_ascii=False
        )
    )