import os
from network import protocol

SERVER_VERSION = 1

SERVER_DOCUMENT = "C:/Users/W/Desktop/\u0641\u0647\u0631\u0633.xlsx"

def ping(client, packet):

    client.sendall(
        protocol.make_response(
            status="PONG"
        )
    )

def version(client, packet):

    client.sendall(
        protocol.make_response(
            status="OK",
            version=1
        )
    )

def download_document(client, packet):

    print("Looking for:", SERVER_DOCUMENT)      # Debugging
    print("Absolute path:", os.path.abspath(SERVER_DOCUMENT))   # Debugging

    if not os.path.exists(SERVER_DOCUMENT):
        client.sendall(
            protocol.make_response(
                status="ERROR",
                message="Document not found"
            )
        )
    
        return
    
    size = os.path.getsize(SERVER_DOCUMENT)

    client.sendall(
        protocol.make_response(
            status="READY",
            size=size
        )
    )

    print("waiting for READY ack ...")  # debug

    raw = client.recv(4096)

    print("Raw ACK:", raw)  #debug

    if not raw:
        print("Client disconnected before ACK.")
        return

    ack = protocol.read_request(raw)

    print("ACK:", ack)  #debug0
    
    if ack["command"] != "READY":
        return
    
    with open(SERVER_DOCUMENT, "rb") as file:
        while True:
            chunk = file.read(4096)

            if not chunk:
                break

            client.sendall(chunk)

def upload_document(client, packet):

    size = packet["size"]

    save_path = config.SERVER_DOCUMENT

    os.makedirs(os.path.dirname(save_path), exist_ok=True)

    client.sendall(
        protocol.make_response(
            status="READY"
        )
    )

    received = 0

    with open(save_path, "wb") as file:

        while received < size:

            chunk = client.recv(
                min(config.BUFFER_SIZE, size - received)
            )

            if not chunk:
                break

            file.write(chunk)

            received += len(chunk)

    print(f"Received {received} bytes.")

    client.sendall(
        protocol.make_response(
            status="OK"
        )
    )