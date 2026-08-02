"""
Application composition root.

This module wires together the backend components and exposes
the application's controller.
"""

from backend.controller.controller import Controller

from backend.document.document import Document

from backend.network.client import NetworkClient

from backend.services.spreadsheet_service import SpreadsheetService

from backend.storage.excel_storage import ExcelStorage

from backend.utils.config import SERVER_IP, SERVER_PORT


class Application:
    """
    Application bootstrap.

    Responsible for creating and connecting all backend components.
    """

    def __init__(self):

        # Infrastructure

        self.storage = ExcelStorage()

        self.network = NetworkClient(
            SERVER_IP,
            SERVER_PORT,
        )

        # Domain

        self.document = Document(
            self.storage,
            self.network,
        )

        # Services

        self.spreadsheet_service = SpreadsheetService(
            self.document,
        )

        # Controller

        self.controller = Controller(
            document=self.document,
            spreadsheet_service=self.spreadsheet_service,
        )