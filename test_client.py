from network.client import NetworkClient
import config

client = NetworkClient(config.SERVER_IP, config.SERVER_PORT)

client.connect()

print("Connected!")

response = client.download_document()

print(response)

client.disconnect()