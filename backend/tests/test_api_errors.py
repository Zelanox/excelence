import os
import tempfile

from fastapi.testclient import TestClient
from openpyxl import Workbook

from backend.dependencies import controller
from backend.main import app

client = TestClient(app)


def test_api_returns_structured_error_for_invalid_payload():
    response = client.post("/spreadsheet/edit-cell", json={"row": -1, "column": 0, "value": "x"})
    assert response.status_code == 422


def test_api_returns_false_payload_for_invalid_sheet_operations():
    with tempfile.TemporaryDirectory() as tmp_dir:
        workbook_path = os.path.join(tmp_dir, "api.xlsx")
        workbook = Workbook()
        sheet = workbook.active
        sheet.title = "Sheet1"
        sheet["A1"] = "name"
        sheet["A2"] = "Alice"
        workbook.save(workbook_path)

        # The app only opens files inside its documents folder, so point
        # that at the temp directory for this test and open by name.
        original_folder = controller.document.documents_folder
        controller.document.documents_folder = tmp_dir

        try:
            open_response = client.post(
                "/documents/open",
                json={"filename": os.path.basename(workbook_path)},
            )
            assert open_response.status_code == 200

            response = client.post("/spreadsheet/sheets/add", json={"name": "Sheet1"})
            assert response.status_code == 200
            payload = response.json()
            assert payload["success"] is False
            assert payload["message"] == "Unable to add worksheet."
        finally:
            controller.document.documents_folder = original_folder
