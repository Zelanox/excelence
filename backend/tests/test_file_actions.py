"""File menu actions on the OPEN document: Save as, Rename, Delete.

Round B of docs/UI_REQUIREMENTS.md. The registry-level tests need only
pandas/openpyxl; the route-level ones are skipped where FastAPI is missing.
"""

import os
import tempfile

from openpyxl import load_workbook

from backend.sessions import DocumentBusy
from backend.tests.test_sessions import ALICE, BOB, make_registry, workbook

try:
    import fastapi  # noqa: F401
    import pydantic  # noqa: F401
    AVAILABLE = True
except ImportError:                                           # pragma: no cover
    AVAILABLE = False

if AVAILABLE:
    from backend.api import documents as docs
    from backend.api.models import NewNameRequest


def cell(folder, name, row=2, column=1):
    """A cell of a file on disk (row 1 is the header)."""
    book = load_workbook(os.path.join(folder, name))
    try:
        return book.active.cell(row, column)
    finally:
        book.close()


def value(folder, name, row=2, column=1):
    return cell(folder, name, row, column).value


def listing(folder):
    """The documents in a folder (the server's own dot-files are ignored)."""
    return sorted(name for name in os.listdir(folder) if not name.startswith("."))


def refused(action, *args):
    """The message of the DocumentBusy that ``action`` raises."""
    try:
        action(*args)
    except DocumentBusy as error:
        return str(error)
    raise AssertionError("expected the action to be refused")


def opened(folder, name="book.xlsx", clients=(ALICE,)):
    workbook(folder, name)
    registry, _ = make_registry(folder)
    session = None
    for client in clients:
        session = registry.open(name, client, "x")
    return registry, session


# ----------------------------------------------------------------------
# Save as
# ----------------------------------------------------------------------

def test_save_as_copies_the_current_content_and_styles():
    with tempfile.TemporaryDirectory() as folder:
        registry, session = opened(folder)
        assert session.controller.edit_cell(0, 0, "changed") is True          # not saved yet
        assert session.controller.set_cell_style(0, 0, 0, 0, {"bold": True}) is True

        assert registry.save_as(session, "copy.xlsx") == "copy.xlsx"

        assert value(folder, "copy.xlsx") == "changed"
        assert cell(folder, "copy.xlsx").font.bold is True
        assert value(folder, "copy.xlsx", 3, 1) == "b"                       # other rows came along
        # The original is saved first, so both hold the same content.
        assert value(folder, "book.xlsx") == "changed"
        # And the session is untouched: still open, still editable.
        assert registry.is_open("book.xlsx") and registry.is_open_in_session("book.xlsx")
        assert session.controller.edit_cell(1, 0, "later") is True


def test_save_as_keeps_everyone_in_the_session():
    with tempfile.TemporaryDirectory() as folder:
        registry, session = opened(folder, clients=(ALICE, BOB))
        registry.save_as(session, "copy.xlsx")
        assert set(session.clients) == {ALICE, BOB}
        assert not registry.is_open("copy.xlsx")                              # nobody was moved


def test_save_as_strips_spaces_and_supports_arabic_and_folders():
    with tempfile.TemporaryDirectory() as folder:
        registry, session = opened(folder)
        assert registry.save_as(session, "  تقرير.xlsx ") == "تقرير.xlsx"
        assert value(folder, "تقرير.xlsx") == "a"
        assert registry.save_as(session, "sub/dir/copy.xlsx") == "sub/dir/copy.xlsx"
        assert value(folder, os.path.join("sub", "dir", "copy.xlsx")) == "a"


def test_save_as_never_overwrites_and_changes_nothing_when_refused():
    with tempfile.TemporaryDirectory() as folder:
        registry, session = opened(folder)
        workbook(folder, "taken.xlsx", rows=(("keep", 9),))
        workbook(folder, "busy.xlsx")
        registry.open("busy.xlsx", BOB, "Bob")                                # open elsewhere
        before = listing(folder)

        assert "already exists" in refused(registry.save_as, session, "taken.xlsx")
        assert "already open" in refused(registry.save_as, session, "busy.xlsx")
        assert "already the name" in refused(registry.save_as, session, "book.xlsx")
        for bad in ("", "   ", "copy", "copy.csv", "../copy.xlsx", "/abs.xlsx", "C:\\x.xlsx", "a/../../b.xlsx"):
            assert "not valid" in refused(registry.save_as, session, bad), bad

        assert listing(folder) == before
        assert value(folder, "taken.xlsx") == "keep"


def test_save_as_is_refused_when_the_save_or_the_copy_fails():
    with tempfile.TemporaryDirectory() as folder:
        registry, session = opened(folder)
        session.controller.edit_cell(0, 0, "unsaved")

        session.controller.save_document = lambda: False
        assert "Could not save" in refused(registry.save_as, session, "copy.xlsx")
        assert not os.path.exists(os.path.join(folder, "copy.xlsx"))
        del session.controller.save_document

        session.controller.copy_document = lambda *args: False
        assert "Could not create the copy" in refused(registry.save_as, session, "copy.xlsx")
        assert not os.path.exists(os.path.join(folder, "copy.xlsx"))
        del session.controller.copy_document

        assert registry.save_as(session, "copy.xlsx") == "copy.xlsx"          # works once the fault is gone
        assert value(folder, "copy.xlsx") == "unsaved"


def test_save_as_twice_to_the_same_name_is_refused_the_second_time():
    with tempfile.TemporaryDirectory() as folder:
        registry, session = opened(folder)
        registry.save_as(session, "copy.xlsx")
        assert "already exists" in refused(registry.save_as, session, "copy.xlsx")


# ----------------------------------------------------------------------
# Rename
# ----------------------------------------------------------------------

def test_rename_open_saves_renames_and_closes_the_session():
    with tempfile.TemporaryDirectory() as folder:
        registry, session = opened(folder)
        session.controller.edit_cell(0, 0, "edited")

        assert registry.rename_open(session, ALICE, "new.xlsx") == "new.xlsx"

        assert not os.path.exists(os.path.join(folder, "book.xlsx"))
        assert value(folder, "new.xlsx") == "edited"                          # unsaved work was kept
        assert not registry.is_open("book.xlsx") and registry._sessions == {}

        again = registry.open("new.xlsx", ALICE, "x")                         # the caller opens the new name
        assert again.controller.cell_value(0, 0) == "edited"
        assert registry.open("book.xlsx", ALICE, "x") is None                 # the old name is gone


def test_rename_open_works_in_a_subfolder_and_with_arabic_names():
    with tempfile.TemporaryDirectory() as folder:
        workbook(folder, "q1.xlsx", subfolder="reports")
        registry, _ = make_registry(folder)
        session = registry.open("reports/q1.xlsx", ALICE, "x")

        registry.rename_open(session, ALICE, "reports/الربع.xlsx")

        assert os.path.exists(os.path.join(folder, "reports", "الربع.xlsx"))
        assert not os.path.exists(os.path.join(folder, "reports", "q1.xlsx"))


def test_rename_open_is_refused_while_others_are_present():
    with tempfile.TemporaryDirectory() as folder:
        registry, session = opened(folder, clients=(ALICE, BOB))
        assert "Other people" in refused(registry.rename_open, session, ALICE, "new.xlsx")

        assert os.path.exists(os.path.join(folder, "book.xlsx"))
        assert not os.path.exists(os.path.join(folder, "new.xlsx"))
        assert set(session.clients) == {ALICE, BOB} and registry.is_open("book.xlsx")


def test_rename_open_refuses_bad_names_and_changes_nothing():
    with tempfile.TemporaryDirectory() as folder:
        registry, session = opened(folder)
        workbook(folder, "taken.xlsx")

        assert "already exists" in refused(registry.rename_open, session, ALICE, "taken.xlsx")
        assert "already the name" in refused(registry.rename_open, session, ALICE, "book.xlsx")
        assert "not valid" in refused(registry.rename_open, session, ALICE, "no-extension")
        assert "not valid" in refused(registry.rename_open, session, ALICE, "../escape.xlsx")

        assert registry.is_open("book.xlsx") and set(session.clients) == {ALICE}
        assert listing(folder) == ["book.xlsx", "taken.xlsx"]


def test_rename_open_keeps_the_session_when_the_save_fails():
    with tempfile.TemporaryDirectory() as folder:
        registry, session = opened(folder)
        session.controller.edit_cell(0, 0, "unsaved")
        session.controller.save_document = lambda: False

        assert "Could not save" in refused(registry.rename_open, session, ALICE, "new.xlsx")

        assert registry.is_open("book.xlsx") and set(session.clients) == {ALICE}    # put back, nothing lost
        assert session.controller.cell_value(0, 0) == "unsaved"
        assert os.path.exists(os.path.join(folder, "book.xlsx"))
        assert not os.path.exists(os.path.join(folder, "new.xlsx"))


def test_rename_open_when_the_rename_itself_fails_leaves_the_saved_old_file():
    with tempfile.TemporaryDirectory() as folder:
        registry, session = opened(folder)
        session.controller.edit_cell(0, 0, "edited")
        session.controller.rename_document = lambda *args: False

        assert "saved under its old name" in refused(registry.rename_open, session, ALICE, "new.xlsx")

        assert value(folder, "book.xlsx") == "edited"                         # nothing lost
        assert not os.path.exists(os.path.join(folder, "new.xlsx"))
        assert registry.open("book.xlsx", ALICE, "x") is not None             # the caller can open it again


# ----------------------------------------------------------------------
# Delete
# ----------------------------------------------------------------------

def test_delete_open_removes_the_file_and_closes_the_session():
    with tempfile.TemporaryDirectory() as folder:
        registry, session = opened(folder)
        session.controller.edit_cell(0, 0, "edited")                           # unsaved edits are dropped with it

        assert registry.delete_open(session, ALICE) == "book.xlsx"

        assert not os.path.exists(os.path.join(folder, "book.xlsx"))
        assert registry._sessions == {} and not registry.is_open("book.xlsx")
        assert registry.open("book.xlsx", ALICE, "x") is None
        assert listing(folder) == []                                       # nothing was re-created by a later save


def test_delete_open_is_refused_while_others_are_present():
    with tempfile.TemporaryDirectory() as folder:
        registry, session = opened(folder, clients=(ALICE, BOB))
        assert "Other people" in refused(registry.delete_open, session, ALICE)
        assert os.path.exists(os.path.join(folder, "book.xlsx"))
        assert set(session.clients) == {ALICE, BOB}


def test_delete_open_keeps_the_session_and_the_work_when_the_file_cannot_be_deleted():
    with tempfile.TemporaryDirectory() as folder:
        registry, session = opened(folder)
        session.controller.edit_cell(0, 0, "unsaved")
        session.controller.delete_document = lambda *args: False

        assert "Could not delete" in refused(registry.delete_open, session, ALICE)

        assert registry.is_open("book.xlsx") and set(session.clients) == {ALICE}
        assert session.controller.cell_value(0, 0) == "unsaved"
        assert os.path.exists(os.path.join(folder, "book.xlsx"))


def test_delete_open_twice_reports_failure_instead_of_crashing():
    with tempfile.TemporaryDirectory() as folder:
        registry, session = opened(folder)
        registry.delete_open(session, ALICE)
        assert "Could not delete" in refused(registry.delete_open, session, ALICE)


def test_the_old_delete_and_rename_rules_for_other_files_are_unchanged():
    with tempfile.TemporaryDirectory() as folder:
        registry, session = opened(folder)
        workbook(folder, "other.xlsx")
        assert registry.is_open_in_session("book.xlsx") is True              # the old routes still refuse this one
        assert registry.is_open_in_session("other.xlsx") is False


# ----------------------------------------------------------------------
# Routes (need FastAPI)
# ----------------------------------------------------------------------

def test_routes_report_success_and_friendly_failures():
    if not AVAILABLE: return
    from backend.tests.test_api_sessions import FakeRequest

    with tempfile.TemporaryDirectory() as folder:
        registry, session = opened(folder, clients=(ALICE, BOB))
        request = FakeRequest(ALICE, "Alice")

        answer = docs.save_as_document(NewNameRequest(new_name="copy.xlsx"), session, registry)
        assert answer.success is True and answer.new_name == "copy.xlsx" and answer.filename == "book.xlsx"

        answer = docs.save_as_document(NewNameRequest(new_name="copy.xlsx"), session, registry)
        assert answer.success is False and "already exists" in answer.message

        answer = docs.rename_open_document(NewNameRequest(new_name="new.xlsx"), request, session, registry)
        assert answer.success is False and "Other people" in answer.message

        answer = docs.delete_open_document(request, session, registry)
        assert answer.success is False and "Other people" in answer.message

        registry.leave(session, BOB)
        answer = docs.rename_open_document(NewNameRequest(new_name="new.xlsx"), request, session, registry)
        assert answer.success is True and answer.old_name == "book.xlsx" and answer.new_name == "new.xlsx"

        session = registry.open("new.xlsx", ALICE, "Alice")
        answer = docs.delete_open_document(request, session, registry)
        assert answer.success is True and answer.filename == "new.xlsx"
        assert not os.path.exists(os.path.join(folder, "new.xlsx"))


def test_routes_refuse_the_legacy_default_session_with_a_message():
    if not AVAILABLE: return
    from backend.tests.test_api_sessions import FakeRequest

    with tempfile.TemporaryDirectory() as folder:
        registry, _ = make_registry(folder)
        default = registry.default

        for answer in (
            docs.save_as_document(NewNameRequest(new_name="x.xlsx"), default, registry),
            docs.rename_open_document(NewNameRequest(new_name="x.xlsx"), FakeRequest(), default, registry),
            docs.delete_open_document(FakeRequest(), default, registry),
        ):
            assert answer.success is False and "shared session" in answer.message
