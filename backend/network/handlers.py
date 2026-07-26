import os

import config
import network.protocol as protocol

from network.repository import Repository
from network.version import VersionManager
from network.lock import SaveManager


# ==========================================================
# Basic
# ==========================================================

def ping(client, packet):

    client.sendall(

        protocol.make_response(

            status="PONG"

        )

    )


# ==========================================================
# Server Information
# ==========================================================

def get_server_info(client, packet):

    client.sendall(

        protocol.make_response(

            status=protocol.OK,

            version=VersionManager.global_version(),

            document_count=len(
                Repository.list_documents()
            )

        )

    )


# ==========================================================
# Document List
# ==========================================================

def list_documents(client, packet):

    documents = []

    for filename in Repository.list_documents():

        documents.append({

            "name": filename,

            "locked": SaveManager.is_locked(filename),

            "version": VersionManager.current(filename)

        })

    client.sendall(

        protocol.make_response(

            status=protocol.OK,

            documents=documents

        )

    )


# ==========================================================
# Document Information
# ==========================================================

def document_info(client, packet):

    filename = packet["document"]

    if not Repository.exists(filename):

        client.sendall(

            protocol.make_response(

                status=protocol.ERROR,

                message="Document not found."

            )

        )

        return

    info = {

        "version": VersionManager.current(filename),

        "locked": SaveManager.is_locked(filename),

        "owner": SaveManager.owner(filename)

    }

    client.sendall(

        protocol.make_response(

            status=protocol.OK,

            info=info

        )

    )


# ==========================================================
# Begin Editing
# ==========================================================

def begin_edit(client, packet):

    filename = packet["document"]

    if not Repository.exists(filename):

        client.sendall(

            protocol.make_response(

                status=protocol.ERROR,

                message="Document not found."

            )

        )

        return

    client.sendall(

        protocol.make_response(

            status=protocol.OK,

            version=VersionManager.current(filename)

        )

    )


# ==========================================================
# Download
# ==========================================================

def download_document(client, packet):

    filename = Repository.path(
        packet["document"]
    )

    if not os.path.exists(filename):

        client.sendall(

            protocol.make_response(

                status=protocol.ERROR,

                message="Document not found."

            )

        )

        return

    filesize = os.path.getsize(filename)

    client.sendall(

        protocol.make_response(

            status=protocol.READY,

            size=filesize,

            version=VersionManager.current(
                packet["document"]
            )

        )

    )

    ack = protocol.read_request(

        client.recv(config.BUFFER_SIZE)

    )

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


# ==========================================================
# Upload
# ==========================================================

def upload_document(client, packet):

    filename = Repository.path(
        packet["document"]
    )

    filesize = packet["size"]

    print(f"Saving to: {filename}")

    client.sendall(

        protocol.make_response(

            status=protocol.READY

        )

    )

    received = 0

    with open(filename, "wb") as file:

        while received < filesize:

            chunk = client.recv(

                min(

                    config.BUFFER_SIZE,

                    filesize - received

                )

            )

            if not chunk:

                raise ConnectionError(

                    "Connection lost."

                )

            file.write(chunk)

            received += len(chunk)

    print(f"Received {received} bytes.")

    client.sendall(

        protocol.make_response(

            status=protocol.OK

        )

    )


# ==========================================================
# Request Save
# ==========================================================

def request_save(client, packet):

    filename = packet["document"]

    owner = packet["owner"]

    if SaveManager.request_save(

        filename,

        owner

    ):

        client.sendall(

            protocol.make_response(

                status=protocol.SAVE_GRANTED

            )

        )

    else:

        client.sendall(

            protocol.make_response(

                status=protocol.SAVE_DENIED,

                owner=SaveManager.owner(filename)

            )

        )


# ==========================================================
# Save Finished
# ==========================================================

def save_finished(client, packet):

    filename = packet["document"]

    owner = packet["owner"]

    SaveManager.finish_save(

        filename,

        owner

    )

    version = VersionManager.increment(

        filename

    )

    client.sendall(

        protocol.make_response(

            status=protocol.OK,

            version=version

        )

    )


# ==========================================================
# Operations
# ==========================================================

def get_operations(client, packet):

    client.sendall(

        protocol.make_response(

            status=protocol.OK,

            operations=[]

        )

    )


def push_operations(client, packet):

    client.sendall(

        protocol.make_response(

            status=protocol.OK

        )

    )


# ==========================================================
# Create Document
# ==========================================================

def create_document(client, packet):

    filename = packet["document"]

    if Repository.exists(filename):

        client.sendall(

            protocol.make_response(

                status=protocol.ERROR,

                message="Document already exists."

            )

        )

        return

    Repository.create_document(filename)

    VersionManager.create(filename)

    client.sendall(

        protocol.make_response(

            status=protocol.OK

        )

    )


# ==========================================================
# Delete Document
# ==========================================================

def delete_document(client, packet):

    filename = packet["document"]

    if not Repository.exists(filename):

        client.sendall(

            protocol.make_response(

                status=protocol.ERROR,

                message="Document not found."

            )

        )

        return

    Repository.delete_document(filename)

    VersionManager.delete(filename)

    client.sendall(

        protocol.make_response(

            status=protocol.OK

        )

    )


# ==========================================================
# Rename Document
# ==========================================================

def rename_document(client, packet):

    old_name = packet["old_name"]

    new_name = packet["new_name"]

    if not Repository.exists(old_name):

        client.sendall(

            protocol.make_response(

                status=protocol.ERROR,

                message="Document not found."

            )

        )

        return

    Repository.rename_document(

        old_name,

        new_name

    )

    VersionManager.rename(

        old_name,

        new_name

    )

    client.sendall(

        protocol.make_response(

            status=protocol.OK

        )

    )


# ==========================================================
# Import / Export
# ==========================================================

def import_document(client, packet):

    client.sendall(

        protocol.make_response(

            status=protocol.ERROR,

            message="Not implemented."

        )

    )


def export_document(client, packet):

    client.sendall(

        protocol.make_response(

            status=protocol.ERROR,

            message="Not implemented."

        )

    )