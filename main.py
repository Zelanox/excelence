import tkinter as tk

from gui import ExcelViewer
from document import Document
from storage import Storage


def main():

    root = tk.Tk()

    storage = Storage()

    document = Document(storage)

    last = storage.load_last()

    if last:
        document.load(last)

    viewer = ExcelViewer(root, document)

    root.mainloop()


if __name__ == "__main__":
    main()