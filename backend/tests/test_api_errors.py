import functools
import os
import tempfile

from fastapi.testclient import TestClient
from openpyxl import Workbook

from backend.dependencies import controller
from backend.main import app, require_access_token

client = TestClient(app)


def without_access_token(test):
    """Run a test as if no access token were configured.

    The server reads EXCELENCE_ACCESS_TOKEN from the environment when it
    starts. If a developer has that variable set in the shell they run the
    tests from (for instance the one that started the server), every call
    these tests make would come back 401. This switches the check off for the
    duration of the test only, so the result doesn't depend on the shell.
    """

    @functools.wraps(test)
    def wrapper(*args, **kwargs):
        app.dependency_overrides[require_access_token] = lambda: None
        try:
            return test(*args, **kwargs)
        finally:
            app.dependency_overrides.pop(require_access_token, None)

    return wrapper


@without_access_token
def test_api_returns_structured_error_for_invalid_payload():
    response = client.post("/spreadsheet/edit-cell", json={"row": -1, "column": 0, "value": "x"})
    assert response.status_code == 422


@without_access_token
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


@without_access_token
def test_api_returns_stable_ids_for_rows_columns_and_sheets():
    with tempfile.TemporaryDirectory() as tmp_dir:
        workbook_path = os.path.join(tmp_dir, "ids.xlsx")
        workbook = Workbook()
        sheet = workbook.active
        sheet.title = "Sheet1"
        sheet["A1"] = "name"
        sheet["A2"] = "Alice"
        sheet["A3"] = "Bob"
        workbook.save(workbook_path)

        original_folder = controller.document.documents_folder
        controller.document.documents_folder = tmp_dir

        try:
            assert client.post(
                "/documents/open",
                json={"filename": os.path.basename(workbook_path)},
            ).status_code == 200

            data = client.get("/spreadsheet/data").json()
            assert len(data["row_ids"]) == len(data["rows"]) == 2
            assert len(data["column_ids"]) == len(data["headers"]) == 1
            assert len(set(data["row_ids"])) == 2
            assert data["current_sheet_id"]

            sheets = client.get("/spreadsheet/sheets").json()
            assert sheets["sheets"] == ["Sheet1"]
            assert sheets["sheet_ids"] == [data["current_sheet_id"]]
            assert sheets["current_sheet_id"] == data["current_sheet_id"]

            renamed = client.post(
                "/spreadsheet/sheets/rename",
                json={"old_name": "Sheet1", "new_name": "Renamed"},
            ).json()
            assert renamed["success"] is True
            assert renamed["sheets"] == ["Renamed"]
            assert renamed["sheet_ids"] == sheets["sheet_ids"]      # same ID after a rename
        finally:
            controller.document.documents_folder = original_folder
