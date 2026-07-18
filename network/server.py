import socket
import threading
import traceback

import config
import network.protocol as protocol
import network.handlers as handlers

HOST = "0.0.0.0"
PORT = config.SERVER_PORT

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

class ClientSession:

    def __init__(self, socket, address):

        self.socket = socket
        self.address = address

        self.client_id = None

        self.document = None

        self.saving = False

        self.connected = True
    
    def send(self, status, **data):

        self.socket.sendall(

            protocol.make_response(
                status=status,
                **data
            )

        )

    def disconnect(self):

        self.connected = False

        try:
            self.socket.close()

        except Exception:
            pass
        
    def packet_loop(session):

        print(f"{session.address} connected")

        try:

            while session.connected:

                raw = session.socket.recv(config.BUFFER_SIZE)

                if not raw:
                    break

                try:

                    packet = protocol.read_request(raw)

                except Exception as error:

                    print("Invalid packet:", error)

                    continue

                print()

                print("CLIENT -> SERVER")

                print(raw.decode(errors="replace"))

                command = packet.get("command")

                handler = REQUEST_HANDLERS.get(command)

                if handler is None:

                    session.socket.sendall(

                        protocol.make_response(

                            protocol.ERROR,

                            message="Unknown command."

                        )

                    )

                    continue

                handler(session, packet)

        except Exception:

            traceback.print_exc()

        finally:

            session.connected = False

            try:

                session.socket.close()

            except Exception:
                pass

            print(f"{session.address} disconnected")

    def client_thread(client, address):

        session = ClientSession(
            client,
            address
        )

        session.run()

def main():

    try:

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

        while True:

            print("\nWaiting for client...")

            client, address = server.accept()

            print(f"Accepted: {address}")

            start_client_thread(
                client,
                address
            )

    except KeyboardInterrupt:

        print("\nStopping server...")

    finally:

        server.close()

        print("Server closed.")


if __name__== "__main__":
    main()