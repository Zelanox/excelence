import os
import tempfile

from openpyxl import Workbook, load_workbook

from backend.controller.controller import Controller
from backend.document.document import Document
from backend.network.client import NetworkClient
from backend.storage.excel_storage import ExcelStorage
from backend.utils.config import SERVER_IP, SERVER_PORT


def _controller(folder: str) -> Controller:
    workbook = Workbook()
    worksheet = workbook.active
    worksheet.append(["Name", "Value"])
    worksheet.append(["Alice", 1])
    worksheet.append(["Bob", 2])
    workbook.save(os.path.join(folder, "rows.xlsx"))

    document = Document(ExcelStorage(), NetworkClient(SERVER_IP, SERVER_PORT))
    document.documents_folder = folder
    controller = Controller(document)
    assert controller.open_document("rows.xlsx") is True
    return controller


def test_row_height_tracks_stable_row_id_and_roundtrips_to_excel():
    with tempfile.TemporaryDirectory() as folder:
        controller = _controller(folder)
        row_id = controller.grid_data().row_ids[1]

        assert controller.set_row_height(row_id, 48) is True
        assert controller.grid_data().row_heights == {row_id: 48.0}
        assert controller.set_row_height(row_id, 15) is False
        assert controller.set_row_height("r999", 48) is False

        # Removing the row above Bob changes his position, not his height.
        assert controller.delete_row(0) is True
        data = controller.grid_data()
        assert data.row_ids[0] == row_id
        assert data.row_heights[row_id] == 48.0
        assert controller.save_document() is True

        worksheet = load_workbook(os.path.join(folder, "rows.xlsx"))["Sheet"]
        assert worksheet.row_dimensions[2].height == 36

        fresh_document = Document(
            ExcelStorage(),
            NetworkClient(SERVER_IP, SERVER_PORT),
        )
        fresh_document.documents_folder = folder
        fresh = Controller(fresh_document)
        assert fresh.open_document("rows.xlsx") is True
        fresh_data = fresh.grid_data()
        assert fresh_data.row_heights == {fresh_data.row_ids[0]: 48.0}
