# network/client.py

import socket
import os

import network.protocol as protocol
import config


class NetworkClient:

    def __init__(self, host, port):

        self.host = host
        self.port = port
        self.socket = None


    def connect(self):

        if self.socket is not None:
            return

        self.socket = socket.socket(
            socket.AF_INET,
            socket.SOCK_STREAM
        )

        self.socket.connect((self.host, self.port))


    def disconnect(self):

        if self.socket:
            self.socket.close()
            self.socket = None


    def send_request(self, command, **kwargs):

        packet = protocol.make_request(command, **kwargs)

        print("\nCLIENT -> SERVER")
        print(packet.decode())

        self.socket.sendall(packet)

        reply = self.socket.recv(4096)

        print("SERVER -> CLIENT")
        print(reply.decode())

        return protocol.read_response(reply)

    def recieve_file(self, path, size):
        os.makedirs(os.path.dirname(filename), exist_ok=True)

        recieved = 0

        with open(filename, "wb") as file:
            while recieved < size:

                chunk = self.socket.recv(
                    min(4096, size - recieved)
                )

                if not chunk:
                    raise ConnectionError(
                        "Connection Lost During Download"
                    )
                
                file.write(chunk)

                recieved += len(chunk)
        
        print(f"Downloaded {recieved} Bytes.")

    def send_file(self, path):
        with open(filename, "rb") as file:

            while True:

                chunk = file.read(4096)

                if not chunk:
                    break

                self.socket.sendall(chunk)
        
        print("Upload Finished.")

    # Commands

    def ping(self):
        return self.send_request(protocol.PING)

    def version(self):
        return self.send_request(protocol.VERSION)

    def download_document(self):

        response = self.send_request(protocol.DOWNLOAD_DOCUMENT)

        if response["status"] != protocol.READY:
            return response
        
        print("sending ready ack")  # debug

        self.socket.sendall(
            protocol.make_request(protocol.READY)
        )

        print("read ack sent")

        self.recieve_file(
            config.CACHE_FILE,
            response["size"]
        )

        return {
            "status": "OK",
            "path": config.CACHE_FILE
        }

    def upload_document(self):
        
        if not os.path.exists(config.CACHE_FILE):

            return{
                "status": "ERROR",
                "message": "Cache file not found."
            }
        
        size = os.path.getsize(config.CACHE_FILE)

        response = self.send_request(
            protocol.UPLOAD_DOCUMENT,
            size=size
        )

        if response["state"] != protocol.READY:
            return response
        
        self.send_file(config.CACHE_FILE)

        return self.socket.recv(4096)     
