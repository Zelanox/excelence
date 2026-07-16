import os
import socket
import uuid

import config
import network.protocol as protocol
from network.client_metadata import ClientMetadata

class NetworkClient:

    def __init__(self, host, port):

        self.host = host
        self.port = port

        self.socket = None

        # Unique client id used for document locking
        self.owner = str(uuid.uuid4())

    # ==========================================================
    # Connection
    # ==========================================================

    def connect(self):

        if self.socket is not None:
            return True

        print(f"Connecting to {self.host}:{self.port}")

        try:
            self.socket = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
            self.socket.connect((self.host, self.port))
            print("Connected!")
            return True

        except Exception as e:
            print("Connect failed:", e)
            self.socket = None
            return False


    def disconnect(self):

        if self.socket is None:
            return

        try:

            try:
                self.socket.shutdown(socket.SHUT_RDWR)
            except OSError:
                pass

            self.socket.close()

        finally:

            self.socket = None
    def is_connected(self):

        return self.socket is not None

    def reconnect(self):

        self.disconnect()

        return self.connect()


    # ==========================================================
    # Generic Request
    # ==========================================================

    def send_request(self, command, **kwargs):

        if self.socket is None:
            raise ConnectionError("Not connected to server.")

        packet = protocol.make_request(
            command,
            **kwargs
        )

        self.socket.sendall(packet)

        print("\nCLIENT -> SERVER")
        print(packet.decode())

        reply = self.socket.recv(
            config.BUFFER_SIZE
        )

        print("SERVER -> CLIENT")
        print(reply.decode())

        return protocol.read_response(reply)


    # ==========================================================
    # File Transfer
    # ==========================================================

    def receive_file(self, filename, size):

        folder = os.path.dirname(filename)

        if folder:

            os.makedirs(
                folder,
                exist_ok=True
            )

        received = 0

        with open(filename, "wb") as file:

            while received < size:

                chunk = self.socket.recv(
                    min(
                        config.BUFFER_SIZE,
                        size - received
                    )
                )

                if not chunk:

                    raise ConnectionError(
                        "Connection lost during download."
                    )

                file.write(chunk)

                received += len(chunk)

        print(f"Downloaded {received} bytes.")


    def send_file(self, filename):

        filesize = os.path.getsize(filename)

        print(f"Uploading {filesize} bytes...")

        with open(filename, "rb") as file:

            while True:

                chunk = file.read(
                    config.BUFFER_SIZE
                )

                if not chunk:
                    break

                self.socket.sendall(chunk)

        print("Upload complete.")


    # ==========================================================
    # Ping
    # ==========================================================

    def ping(self):

        try:

            self.connect()

            response = self.send_request(protocol.PING)

            self.disconnect()

            return response["status"] == "PONG"

        except Exception:

            self.disconnect()

            return False


    # ==========================================================
    # Version
    # ==========================================================

    def get_version(self):

        reply = self.send_request(
            protocol.GET_VERSION
        )

        if reply["status"] != protocol.OK:
            return None

        return reply["version"]


    def local_version(self):

        return ClientMetadata.current()


    # ==========================================================
    # Download
    # ==========================================================

    def download_document(self):

        response = self.send_request(
            protocol.DOWNLOAD_DOCUMENT
        )

        if response["status"] != protocol.READY:

            return response

        self.socket.sendall(
            protocol.make_request(
                protocol.READY
            )
        )

        self.receive_file(
            config.CACHE_FILE,
            response["size"]
        )

        ClientMetadata.set(
            response["version"]
        )

        return {
            "status": protocol.OK,
            "path": config.CACHE_FILE,
            "version": response["version"]
        }


    # ==========================================================
    # Upload
    # ==========================================================

    def upload_document(self):

        if not os.path.exists(
            config.CACHE_FILE
        ):

            return {

                "status": protocol.ERROR,

                "message":
                "Cache file not found."
            }

        filesize = os.path.getsize(
            config.CACHE_FILE
        )

        response = self.send_request(

            protocol.UPLOAD_DOCUMENT,

            size=filesize
        )

        if response["status"] != protocol.READY:

            return response

        self.send_file(
            config.CACHE_FILE
        )

        reply = self.socket.recv(
            config.BUFFER_SIZE
        )

        response = protocol.read_response(
            reply
        )

        if response["status"] == protocol.OK:

            ClientMetadata.set(
                response["version"]
            )

        return response


    # ==========================================================
    # Document Lock
    # ==========================================================

    def open_document(self):

        return self.send_request(

            protocol.OPEN_DOCUMENT,

            owner=self.owner
        )

    def close_document(self):

        return self.send_request(

            protocol.CLOSE_DOCUMENT,

            owner=self.owner
        )