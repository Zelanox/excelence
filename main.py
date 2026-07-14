import tkinter as tk

import config

from storage import Storage
from document import Document
from gui import ExcelViewer

from network.client import NetworkClient


def main():

    # ------------------------------------------
    # Create core objects
    # ------------------------------------------

    storage = Storage()

    network = NetworkClient(
        config.SERVER_IP,
        config.SERVER_PORT
    )

    print("Server IP:", config.SERVER_IP)
    print("Server Port:", config.SERVER_PORT)

    # ------------------------------------------
    # Detect server
    # ------------------------------------------

    online = network.connect()

    if online:

        print("Server Online")

        network.disconnect()

    else:

        print("Offline mode.")

    # ------------------------------------------
    # Create document
    # ------------------------------------------

    document = Document(
        storage,
        network,
        online
    )

    # ------------------------------------------
    # Open last document (if available)
    # ------------------------------------------

    last_file = storage.load_last_file()

    if last_file:

        try:

            document.open(last_file)

        except Exception as e:

            print(e)

    # ------------------------------------------
    # Create GUI
    # ------------------------------------------

    root = tk.Tk()

    app = ExcelViewer(
        root,
        document
    )

    # ------------------------------------------
    # Handle application closing
    # ------------------------------------------

    def on_close():

        try:

            document.close()

        finally:

            root.destroy()

    root.protocol(
        "WM_DELETE_WINDOW",
        on_close
    )

    root.mainloop()


if __name__ == "__main__":

    main()