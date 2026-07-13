import tkinter as tk

from gui import ExcelViewer
from document import Document
from storage import Storage
from network.client import NetworkClient

import config


def main():

    root = tk.Tk()

    storage = Storage()

    network = NetworkClient(config.SERVER_IP, config.SERVER_PORT)
    network.connect()

    if network.ping():
        print("Server Online")
    else:
        print("Server Offline")

    network.disconnect()

    document = Document(storage, network)

    last = storage.load_last()

    if last:
        document.load(last)

    viewer = ExcelViewer(root, document)

    root.mainloop()


if __name__ == "__main__":
    main()