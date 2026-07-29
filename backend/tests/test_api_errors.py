import os
import tempfile

from fastapi.testclient import TestClient
from openpyxl import Workbook

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

        open_response = client.post("/documents/open", json={"filename": workbook_path})
        assert open_response.status_code == 200

        response = client.post("/spreadsheet/sheets/add", json={"name": "Sheet1"})
        assert response.status_code == 200
        payload = response.json()
        assert payload["success"] is False
        assert payload["message"] == "Unable to add worksheet."
