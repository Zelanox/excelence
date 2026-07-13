import socket
import os

import handlers
import protocol

HOST = "0.0.0.0"
PORT = 5000

COMMANDS = {
    protocol.PING: handlers.ping,
    protocol.VERSION: handlers.version,
    protocol.DOWNLOAD_DOCUMENT: handlers.download_document,
    protocol.UPLOAD_DOCUMENT: handlers.upload_document,
}


def handle_client(client, address):

    print(f"{address} connected")

    try:

        while True:

            raw = client.recv(config.BUFFER_SIZE)

            if not raw:
                break

            print("\nCLIENT SENT:")
            print(raw.decode())

            packet = protocol.read_request(raw)

            command = packet.get("command")

            handler = COMMANDS.get(command)

            if handler is None:

                client.sendall(
                    protocol.make_response(
                        status="ERROR",
                        message="Unknown command"
                    )
                )

                continue

            handler(client, packet)

    except ConnectionResetError:

        print(f"{address} disconnected unexpectedly")

    except Exception as e:

        print("Server error:", e)

    finally:

        client.close()

        print(f"{address} disconnected")


def main():

    server = socket.socket(
        socket.AF_INET,
        socket.SOCK_STREAM
    )

    server.bind((HOST, PORT))

    server.listen()

    print(f"Server listening on {HOST}:{PORT}")

    while True:

        client, address = server.accept()

        handle_client(client, address)


if __name__ == "__main__":

    main()