import os
import socket
import uuid

import config
import network.protocol as protocol

from network.client_metadata import ClientMetadata

# ==========================================================
# Network Client
# ==========================================================

class NetworkClient:

    def __init__(self, host, port):

        # ------------------------------------------
        # Server Connection
        # ------------------------------------------

        self.host = host
        self.port = port

        self.socket = None

        # ------------------------------------------
        # Client Identity
        # ------------------------------------------

        self.client_id = str(uuid.uuid4())

        # ------------------------------------------
        # Current Session
        # ------------------------------------------

        self.connected = False

        self.current_document = None

        self.current_version = 0

        self.save_state = None

        # ------------------------------------------
        # Cached Server Information
        # ------------------------------------------

        self.server_info = {}

    # ==========================================================
    # Connection Management
    # ==========================================================

    def connect(self):

        if self.connected:
            return True

        print(f"Connecting to {self.host}:{self.port}")

        try:

            self.socket = socket.socket(
                socket.AF_INET,
                socket.SOCK_STREAM
            )

            self.socket.settimeout(10)

            self.socket.connect(
                (self.host, self.port)
            )

            self.connected = True

            print("Connected.")

            return True

        except Exception as error:

            print("Connection failed:", error)

            self.socket = None

            self.connected = False

            return False


    def disconnect(self):

        if not self.connected:
            return

        try:

            try:

                self.socket.shutdown(
                    socket.SHUT_RDWR
                )

            except OSError:
                pass

            self.socket.close()

        except Exception:
            pass

        finally:

            self.socket = None

            self.connected = False

            print("Disconnected.")


    def reconnect(self):

        self.disconnect()

        return self.connect()


    def is_connected(self):

        return self.connected

    # ==========================================================
    # Packet API
    # ==========================================================

    def send_packet(self, packet):

        if not self.connected:

            raise ConnectionError(
                "Not connected to server."
            )

        self.socket.sendall(packet)

        print()
        print("CLIENT -> SERVER")
        print(packet.decode())

    def receive_packet(self):

        if not self.connected:

            raise ConnectionError(
                "Not connected to server."
            )

        raw = self.socket.recv(
            config.BUFFER_SIZE
        )

        if not raw:

            raise ConnectionError(
                "Server disconnected."
            )

        print()
        print("SERVER -> CLIENT")
        print(raw.decode())

        return protocol.read_response(raw)

    def send_request(self, command, **data):

        packet = protocol.make_request(
            command,
            **data
        )

        self.send_packet(packet)

        return self.receive_packet()

    # ==========================================================
    # Server Information
    # ==========================================================

    def ping(self):

        try:

            if not self.connect():
                return False

            response = self.send_request(
                protocol.PING
            )

            return response["status"] == "PONG"

        except Exception:

            return False

        finally:

            self.disconnect()

    def get_server_info(self):

        response = self.send_request(
            protocol.GET_SERVER_INFO
        )

        if response["status"] != protocol.OK:

            return None

        self.server_info = dict(response)

        self.current_version = response.get(
            "version",
            self.current_version
        )

        return response

    # ==========================================================
    # Repository API
    # ==========================================================

    def list_documents(self):

        response = self.send_request(
            protocol.LIST_DOCUMENTS
        )

        if response["status"] != protocol.OK:
            return []

        return response["documents"]

    def document_info(self, document):

        response = self.send_request(
            protocol.DOCUMENT_INFO,
            document=document
        )

        if response["status"] != protocol.OK:
            return None

        return response["info"]

    def create_document(self, name):

        return self.send_request(
            protocol.CREATE_DOCUMENT,
            document=name
        )
    
    def delete_document(self, name):

        return self.send_request(
            protocol.DELETE_DOCUMENT,
            document=name
        )

    def rename_document(self, old_name, new_name):

        return self.send_request(

            protocol.RENAME_DOCUMENT,

            document=old_name,

            new_name=new_name
        )

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

    def download_document(self, document, destination):

        response = self.send_request(

            protocol.DOWNLOAD_DOCUMENT,

            document=document
        )

        if response["status"] != protocol.READY:

            return response

        self.send_packet(

            protocol.make_request(
                protocol.READY
            )
        )

        self.receive_file(

            destination,

            response["size"]
        )

        self.current_document = document

        self.current_version = response["version"]
        ClientMetadata.set(response["version"])

        return {

            "status": protocol.OK,

            "path": destination,

            "version": response["version"]
        }

    def upload_document(self, document, filename):

        if not os.path.exists(filename):

            return {

                "status": protocol.ERROR,

                "message": "File not found."
            }

        filesize = os.path.getsize(filename)

        response = self.send_request(

            protocol.UPLOAD_DOCUMENT,

            document=document,

            size=filesize
        )

        if response["status"] != protocol.READY:

            return response

        self.send_file(filename)

        response = self.receive_packet()

        if response["status"] == protocol.OK:

            self.current_version = response["version"]
            ClientMetadata.set(response["version"])

        return response

    # ==========================================================
    # Operations API
    # ==========================================================

    def begin_edit(self, document):

        response = self.send_request(

            protocol.BEGIN_EDIT,

            document=document,

            client=self.client_id
        )

        if response["status"] == protocol.OK:

            self.current_document = document

            self.current_version = response["version"]

        return response

    def get_operations(self):

        response = self.send_request(

            protocol.GET_OPERATIONS,

            document=self.current_document,

            version=self.current_version
        )

        if response["status"] != protocol.OK:

            return []

        self.current_version = response["version"]

        return response["operations"]

    def push_operations(self, operations):

        response = self.send_request(

            protocol.PUSH_OPERATIONS,

            document=self.current_document,

            version=self.current_version,

            operations=operations
        )

        if response["status"] == protocol.OK:

            self.current_version = response["version"]

        return response

    def end_edit(self):

        if self.current_document is None:

            return

        response = self.send_request(

            protocol.END_EDIT,

            document=self.current_document,

            client=self.client_id
        )

        self.clear_session()

        return response

    def editing_document(self):

        return self.current_document is not None

    # ==========================================================
    # Save Queue API
    # ==========================================================

    def request_save(self):

        if self.current_document is None:

            return {

                "status": protocol.ERROR,

                "message": "No document selected."
            }

        response = self.send_request(

            protocol.REQUEST_SAVE,

            document=self.current_document,

            client=self.client_id
        )

        self.save_state = response["status"]

        return response

    def save_finished(self):

        if self.current_document is None:

            return


        response = self.send_request(

            protocol.SAVE_FINISHED,

            document=self.current_document,

            client=self.client_id
        )
        if response["status"] == protocol.OK:
            self.save_state = None

        return response

    def can_save(self):

        response = self.request_save()

        return response["status"] == protocol.SAVE_GRANTED

    # ==========================================================
    # Import / Export
    # ==========================================================

    def import_document(self, local_file, repository_name):

        if not os.path.exists(local_file):

            return {

                "status": protocol.ERROR,

                "message": "File not found."
            }

        filesize = os.path.getsize(local_file)

        response = self.send_request(

            protocol.IMPORT_DOCUMENT,

            document=repository_name,

            size=filesize
        )

        if response["status"] != protocol.READY:

            return response

        self.send_file(local_file)

        return self.receive_packet()

    def export_document(self, document, destination):

        response = self.send_request(

            protocol.EXPORT_DOCUMENT,

            document=document
        )

        if response["status"] != protocol.READY:

            return response

        self.send_packet(

            protocol.make_request(

                protocol.READY
            )
        )

        self.receive_file(

            destination,

            response["size"]
        )

        return {

            "status": protocol.OK,

            "path": destination
        }

    # ==========================================================
    # Utilities
    # ==========================================================

    def current_document_name(self):

        return self.current_document

    def current_document_version(self):

        return self.current_version

    def clear_session(self):

        self.current_document = None

        self.current_version = 0

        self.save_state = None

    def __repr__(self):

        return (

            f"NetworkClient("

            f"host={self.host}, "

            f"port={self.port}, "

            f"connected={self.is_connected()}, "

            f"document={self.current_document}"

            ")"

        )

    # ==========================================================
    # Stubs
    # ==========================================================

    def download_if_needed(self, document, version):

        pass

    def create_document(

        self,

        document_name

    ):

        pass