import json

# ---------- Commands ----------

PING = "PING"
VERSION = "VERSION"

DOWNLOAD_DOCUMENT = "DOWNLOAD_DOCUMENT"
UPLOAD_DOCUMENT = "UPLOAD_DOCUMENT"

LOCK = "LOCK"
UNLOCK = "UNLOCK"

READY = "READY"
ERROR = "ERROR"
OK = "OK"
PONG = "PONG"

# ---------- Packet Helpers ----------

def make_request(command, **data):
    """
    Create a JSON request packet.
    """
    packet = {
        "command": command,
        **data
    }

    return json.dumps(packet).encode("utf-8")


def read_request(data):
    """
    Decode bytes into a Python dictionary.
    """
    return json.loads(data.decode("utf-8"))


def make_response(status="OK", **data):
    """
    Create a JSON response packet.
    """
    packet = {
        "status": status,
        **data
    }

    return json.dumps(packet).encode("utf-8")


def read_response(data):
    """
    Decode a response packet.
    """
    return json.loads(data.decode("utf-8"))