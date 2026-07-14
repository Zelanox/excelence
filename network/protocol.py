import json


# ==========================================================
# Commands
# ==========================================================

PING = "PING"

GET_VERSION = "GET_VERSION"

DOWNLOAD_DOCUMENT = "DOWNLOAD_DOCUMENT"
UPLOAD_DOCUMENT = "UPLOAD_DOCUMENT"

OPEN_DOCUMENT = "OPEN_DOCUMENT"
CLOSE_DOCUMENT = "CLOSE_DOCUMENT"

READY = "READY"

OK = "OK"
ERROR = "ERROR"

LOCKED = "LOCKED"
DENIED = "DENIED"


# ==========================================================
# Packet Builders
# ==========================================================

def make_request(command, **kwargs):

    packet = {
        "protocol": 1,
        "command": command
    }

    packet.update(kwargs)

    return json.dumps(
        packet,
        ensure_ascii=False
    ).encode("utf-8")


def make_response(status, **kwargs):

    packet = {
        "protocol": 1,
        "status": status
    }

    packet.update(kwargs)

    return json.dumps(
        packet,
        ensure_ascii=False
    ).encode("utf-8")

# ==========================================================
# Packet Validators
# ==========================================================

def validate_request(packet):

    if "command" not in packet:
        raise ValueError("Missing command.")

    return packet


def validate_response(packet):

    if "status" not in packet:
        raise ValueError("Missing status.")

    return packet

# ==========================================================
# Packet Readers
# ==========================================================

def read_request(data):

    if not data:

        raise ConnectionError(
            "No request received."
        )

    try:

        return json.loads(
            data.decode("utf-8")
        )

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

        return json.loads(
            data.decode("utf-8")
        )

    except json.JSONDecodeError as error:

        raise ValueError(
            f"Invalid response packet: {error}"
        )


# ==========================================================
# Debug Helpers
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