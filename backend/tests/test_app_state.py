"""Last-opened document and preferences must survive an app restart."""

import json
import os
import tempfile

from openpyxl import Workbook

from backend.controller.controller import Controller
from backend.document.document import Document
from backend.network.client import NetworkClient
from backend.storage.app_state import STATE_FILENAME, AppState
from backend.storage.excel_storage import ExcelStorage
from backend.utils.config import SERVER_IP, SERVER_PORT


def workbook(folder, name, subfolder=None):
    target = os.path.join(folder, subfolder) if subfolder else folder
    os.makedirs(target, exist_ok=True)
    book = Workbook()
    book.active.title = "Sheet1"
    book.active.append(["a", "b"])
    book.active.append([1, 2])
    book.save(os.path.join(target, name))


def start(folder):
    """A brand-new app: new Document, new Controller, same folder on disk."""
    document = Document(ExcelStorage(), NetworkClient(SERVER_IP, SERVER_PORT))
    document.documents_folder = folder
    return Controller(document)


def state_file(folder):
    return os.path.join(folder, STATE_FILENAME)


def test_last_document_survives_a_restart():
    with tempfile.TemporaryDirectory() as folder:
        workbook(folder, "report.xlsx")
        first = start(folder)
        assert first.last_document() is None            # nothing opened yet
        assert first.open_document("report.xlsx") is True

        second = start(folder)                          # "close and reopen the app"
        assert second.last_document() == "report.xlsx"


def test_the_most_recent_open_wins():
    with tempfile.TemporaryDirectory() as folder:
        for name in ("a.xlsx", "b.xlsx", "c.xlsx"):
            workbook(folder, name)
        app = start(folder)
        for name in ("a.xlsx", "c.xlsx", "b.xlsx"):
            assert app.open_document(name) is True
        assert start(folder).last_document() == "b.xlsx"


def test_documents_in_subfolders_are_remembered_by_relative_path():
    with tempfile.TemporaryDirectory() as folder:
        workbook(folder, "q1.xlsx", subfolder="reports")
        assert start(folder).open_document("reports/q1.xlsx") is True
        assert start(folder).last_document() == "reports/q1.xlsx"


def test_a_failed_open_does_not_replace_the_remembered_document():
    with tempfile.TemporaryDirectory() as folder:
        workbook(folder, "good.xlsx")
        app = start(folder)
        assert app.open_document("good.xlsx") is True
        assert app.open_document("missing.xlsx") is False
        assert app.open_document("") is False
        assert app.open_document("../escape.xlsx") is False
        assert start(folder).last_document() == "good.xlsx"


def test_a_deleted_document_is_not_offered_again():
    with tempfile.TemporaryDirectory() as folder:
        workbook(folder, "gone.xlsx")
        assert start(folder).open_document("gone.xlsx") is True
        os.remove(os.path.join(folder, "gone.xlsx"))
        assert start(folder).last_document() is None


def test_a_created_document_is_remembered_once_it_exists_on_disk():
    with tempfile.TemporaryDirectory() as folder:
        app = start(folder)
        assert app.create_document("new.xlsx") is True
        if not os.path.isfile(os.path.join(folder, "new.xlsx")):
            assert start(folder).last_document() is None      # not offered while it is only in memory
            assert app.save_document() is True
        assert start(folder).last_document() == "new.xlsx"


def test_corrupt_state_file_is_ignored_and_does_not_block_opening():
    with tempfile.TemporaryDirectory() as folder:
        workbook(folder, "a.xlsx")
        with open(state_file(folder), "w") as handle:
            handle.write("{ this is not json")
        app = start(folder)
        assert app.last_document() is None
        assert app.open_document("a.xlsx") is True               # still opens...
        assert start(folder).last_document() == "a.xlsx"         # ...and repairs the file


def test_unwritable_state_never_blocks_opening():
    with tempfile.TemporaryDirectory() as folder:
        workbook(folder, "a.xlsx")
        os.mkdir(state_file(folder))          # a directory where the file should go: every write fails
        app = start(folder)
        assert app.open_document("a.xlsx") is True
        assert app.last_document() is None    # couldn't remember it, but nothing broke


def test_a_hostile_remembered_path_is_rejected():
    with tempfile.TemporaryDirectory() as folder:
        for value in ("../../etc/passwd", "/etc/passwd", "C:\\Windows\\win.ini", 5, "", "   "):
            with open(state_file(folder), "w") as handle:
                json.dump({"last_document": value}, handle)
            assert start(folder).last_document() is None, value


def test_state_file_is_not_listed_as_a_document_and_leaves_no_temp_files():
    with tempfile.TemporaryDirectory() as folder:
        workbook(folder, "a.xlsx")
        app = start(folder)
        app.open_document("a.xlsx")
        app.set_preference("auto_search_after_add_row", False)
        assert app.list_documents() == ["a.xlsx"]
        assert sorted(os.listdir(folder)) == sorted([STATE_FILENAME, "a.xlsx"])


def test_preferences_persist_and_update():
    with tempfile.TemporaryDirectory() as folder:
        app = start(folder)
        assert app.preferences() == {}
        assert app.set_preference("auto_search_after_add_row", False) is True
        assert app.set_preference("zoom", 1.25) is True
        assert app.set_preference("note", "hi") is True

        again = start(folder)
        assert again.preferences() == {"auto_search_after_add_row": False, "zoom": 1.25, "note": "hi"}
        assert again.set_preference("auto_search_after_add_row", True) is True
        assert start(folder).preferences()["auto_search_after_add_row"] is True


def test_preferences_reject_bad_keys_and_values():
    with tempfile.TemporaryDirectory() as folder:
        app = start(folder)
        for key in ("", "Has Caps", "with-dash", "../x", "a" * 65, 5, None):
            assert app.set_preference(key, True) is False, key
        for value in ({"nested": 1}, [1, 2], "x" * 257, float("nan"), float("inf"), object()):
            assert app.set_preference("ok_key", value) is False, value
        assert app.preferences() == {}


def test_preferences_and_last_document_do_not_clobber_each_other():
    with tempfile.TemporaryDirectory() as folder:
        workbook(folder, "a.xlsx")
        workbook(folder, "b.xlsx")
        app = start(folder)
        app.open_document("a.xlsx")
        app.set_preference("k", 1)
        app.open_document("b.xlsx")
        again = start(folder)
        assert again.last_document() == "b.xlsx" and again.preferences() == {"k": 1}


def test_junk_entries_in_a_hand_edited_state_file_are_filtered():
    with tempfile.TemporaryDirectory() as folder:
        with open(state_file(folder), "w") as handle:
            json.dump({"preferences": {"good": True, "Bad Key": 1, "nested": {"a": 1}}}, handle)
        assert start(folder).preferences() == {"good": True}
        with open(state_file(folder), "w") as handle:
            json.dump([1, 2, 3], handle)                       # wrong top-level type
        assert start(folder).preferences() == {} and start(folder).last_document() is None


def test_appstate_follows_the_folder_it_is_pointed_at():
    with tempfile.TemporaryDirectory() as one, tempfile.TemporaryDirectory() as two:
        current = {"folder": one}
        state = AppState(lambda: current["folder"])
        assert state.set_last_document("x.xlsx") is True
        current["folder"] = two
        assert state.get_last_document() is None
        current["folder"] = one
        assert state.get_last_document() == "x.xlsx"
