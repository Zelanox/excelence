import socket
import traceback

import config
import network.protocol as protocol
import network.handlers as handlers


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


def handle_client(client, packet, address):

    print(f"{address} connected")

    try:

        while True:

            raw = client.recv(config.BUFFER_SIZE)

            if not raw:
                break

            packet = protocol.read_request(raw)

            print("\nCLIENT SENT:")
            print(raw.decode())

            command = packet["command"]

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

        print(f"{address} disconnected")

        client.close()


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

    server.bind((HOST, PORT))

    server.listen()

    print(f"Server listening on {HOST}:{PORT}")

    while True:

        client, address = server.accept()

        handle_client(client, address)


if __name__ == "__main__":

    main()