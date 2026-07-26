import socket
import threading
import traceback

import config
import network.protocol as protocol
import network.handlers as handlers


# ==========================================================
# Server Configuration
# ==========================================================

HOST = "0.0.0.0"
PORT = config.SERVER_PORT


# ==========================================================
# Request Dispatcher
# ==========================================================

REQUEST_HANDLERS = {

    protocol.PING: handlers.ping,

    protocol.GET_SERVER_INFO: handlers.get_server_info,

    protocol.LIST_DOCUMENTS: handlers.list_documents,

    protocol.DOCUMENT_INFO: handlers.document_info,

    protocol.DOWNLOAD_DOCUMENT: handlers.download_document,

    protocol.UPLOAD_DOCUMENT: handlers.upload_document,

    protocol.REQUEST_SAVE: handlers.request_save,

    protocol.SAVE_FINISHED: handlers.save_finished,

    protocol.GET_OPERATIONS: handlers.get_operations,

    protocol.PUSH_OPERATIONS: handlers.push_operations,

    protocol.CREATE_DOCUMENT: handlers.create_document,

    protocol.DELETE_DOCUMENT: handlers.delete_document,

    protocol.RENAME_DOCUMENT: handlers.rename_document,

    protocol.IMPORT_DOCUMENT: handlers.import_document,

    protocol.EXPORT_DOCUMENT: handlers.export_document,
}


# ==========================================================
# Client Session
# ==========================================================

class ClientSession:

    def __init__(self, client_socket, address):

        self.socket = client_socket
        self.address = address

        self.client_id = None

        self.document = None

        self.connected = True

        self.saving = False


    # ------------------------------------------------------

    def send(self, status, **data):

        self.socket.sendall(

            protocol.make_response(

                status=status,

                **data

            )

        )


    # ------------------------------------------------------

    def disconnect(self):

        self.connected = False

        try:

            self.socket.close()

        except Exception:

            pass


    # ------------------------------------------------------

    def packet_loop(self):

        print(f"{self.address} connected")

        try:

            while self.connected:

                raw = self.socket.recv(

                    config.BUFFER_SIZE

                )

                if not raw:

                    break

                try:

                    packet = protocol.read_request(raw)

                    protocol.validate_request(packet)

                except Exception as error:

                    print()

                    print("Invalid packet:")

                    print(error)

                    continue

                print()

                print("CLIENT -> SERVER")

                print(raw.decode(errors="replace"))

                command = packet["command"]

                handler = REQUEST_HANDLERS.get(command)

                if handler is None:

                    self.send(

                        protocol.ERROR,

                        message="Unknown command."

                    )

                    continue

                handler(

                    self,

                    packet

                )

        except Exception:

            print()

            print(f"Session crashed: {self.address}")

            traceback.print_exc()

        finally:

            self.disconnect()

            print(f"{self.address} disconnected")


# ==========================================================
# Thread Helpers
# ==========================================================

def client_thread(client_socket, address):

    session = ClientSession(

        client_socket,

        address

    )

    session.packet_loop()


def start_client_thread(client_socket, address):

    thread = threading.Thread(

        target=client_thread,

        args=(client_socket, address),

        daemon=True

    )

    thread.start()

    return thread


# ==========================================================
# Main Server
# ==========================================================

def main():

    server = socket.socket(

        socket.AF_INET,

        socket.SOCK_STREAM

    )

    server.setsockopt(

        socket.SOL_SOCKET,

        socket.SO_REUSEADDR,

        1

    )

    server.bind(

        (HOST, PORT)

    )

    server.listen()

    print("=" * 60)

    print("Excelence Server Started")

    print(f"Listening on {HOST}:{PORT}")

    print("=" * 60)

    try:

        while True:

            print()

            print("Waiting for client...")

            client_socket, address = server.accept()

            print(f"Accepted: {address}")

            start_client_thread(

                client_socket,

                address

            )

    except KeyboardInterrupt:

        print()

        print("Stopping server...")

    finally:

        server.close()

        print("Server closed.")


# ==========================================================

if __name__ == "__main__":

    main()