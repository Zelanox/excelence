import os

import config
import network.protocol as protocol

from network.version import VersionManager
from network.lock import DocumentLock


def ping(client, packet):

    client.sendall(
        protocol.make_response(
            status="PONG"
        )
    )


def get_version(client, packet):

    client.sendall(
        protocol.make_response(
            status=protocol.OK,
            version=VersionManager.current()
        )
    )


def download_document(client, packet):

    filename = config.SERVER_DOCUMENT

    if not os.path.exists(filename):

        client.sendall(
            protocol.make_response(
                status="ERROR",
                message="Document not found."
            )
        )

        return

    filesize = os.path.getsize(filename)

    client.sendall(
        protocol.make_response(
            status=protocol.READY,
            size=filesize,
            version=VersionManager.current()
        )
    )

    ack = protocol.read_request(client.recv(config.BUFFER_SIZE))

    if ack["command"] != protocol.READY:
        return

    print(f"Sending {filesize} bytes...")

    with open(filename, "rb") as file:

        while True:

            chunk = file.read(config.BUFFER_SIZE)

            if not chunk:
                break

            client.sendall(chunk)

    print("Download complete.")


def upload_document(client, packet):

    filename = config.SERVER_DOCUMENT

    filesize = packet["size"]

    print(f"Saving to: {filename}")

    client.sendall(
        protocol.make_response(
            status=protocol.READY
        )
    )

    os.makedirs(
        os.path.dirname(filename),
        exist_ok=True
    )

    received = 0

    with open(filename, "wb") as file:

        while received < filesize:

            chunk = client.recv(
                min(config.BUFFER_SIZE, filesize - received)
            )

            if not chunk:
                raise ConnectionError("Connection lost.")

            file.write(chunk)

            received += len(chunk)

    print(f"Received {received} bytes.")

    new_version = VersionManager.increment()

    client.sendall(
        protocol.make_response(
            status=protocol.OK,
            version=new_version
        )
    )


def open_document(client, packet):

    owner = packet["owner"]

    if DocumentLock.lock(owner):

        client.sendall(
            protocol.make_response(
                status=protocol.OK,
                version=VersionManager.current()
            )
        )

    else:

        client.sendall(
            protocol.make_response(
                status="LOCKED",
                owner=DocumentLock.owner()
            )
        )
    


def close_document(client, packet):

    owner = packet["owner"]

    if DocumentLock.unlock(owner):

        client.sendall(
            protocol.make_response(
                status=protocol.OK
            )
        )

    else:

        client.sendall(
            protocol.make_response(
                status="DENIED"
            )
        )