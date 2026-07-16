import socket
import traceback

import config
import network.protocol as protocol
import network.handlers as handlers
from network.lock import DocumentLock


HOST = "0.0.0.0"
PORT = config.SERVER_PORT


COMMANDS = {

    protocol.PING:
        handlers.ping,

    protocol.GET_VERSION:
        handlers.get_version,

    protocol.DOWNLOAD_DOCUMENT:
        handlers.download_document,

    protocol.UPLOAD_DOCUMENT:
        handlers.upload_document,

    protocol.OPEN_DOCUMENT:
        handlers.open_document,

    protocol.CLOSE_DOCUMENT:
        handlers.close_document
}


def handle_client(client, address):

    print(f"{address} connected")

    owner = None

    try:

        while True:

            raw = client.recv(config.BUFFER_SIZE)

            if not raw:
                break

            try:

                packet = protocol.read_request(raw)

            except Exception as e:

                print("Invalid packet:", e)

                break

            print("\nCLIENT SENT:")
            print(raw.decode(errors="replace"))

            command = packet["command"]

            if command == protocol.OPEN_DOCUMENT:

                owner = packet["owner"]

            handler = COMMANDS.get(command)

            if handler is None:

                client.sendall(

                    protocol.make_response(

                        status=protocol.ERROR,

                        message="Unknown command."
                    )
                )

                continue

            handler(client, packet)

    except Exception as error:

        print("Server error:")
        traceback.print_exc()

        try:

            client.sendall(

                protocol.make_response(

                    status=protocol.ERROR,

                    message=str(error)
                )
            )

        except Exception:
            pass

    finally:

        if owner is not None:

            DocumentLock.unlock(owner)

        print(f"{address} disconnected")

        client.close()

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

        server.bind((HOST, PORT))

        server.listen()

        print(f"Server listening on {HOST}:{PORT}")

        while True:

            print("Waiting for client")
            
            client, address = server.accept()
            print("CONNECTED:", address)

            print(f"Accepted :\t{address}")

            handle_client(client, address)
    
    except KeyboardInterrupt:
        print("Stopping server")
    
    finally:
        server.close()


if __name__ == "__main__":

    main()