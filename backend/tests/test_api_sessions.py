"""The web layer of sessions: route behaviour and the per-request dependency.

These call the route functions and the dependency directly (no HTTP), so they
need only FastAPI/pydantic to be importable. Where those are missing the
tests do nothing rather than fail.
"""

import asyncio
import os
import tempfile

try:
    import fastapi  # noqa: F401
    import pydantic  # noqa: F401
    AVAILABLE = True
except ImportError:                                           # pragma: no cover
    AVAILABLE = False

from backend.tests.test_sessions import ALICE, BOB, make_registry, workbook

if AVAILABLE:
    import backend.dependencies as deps
    from backend.api import documents as docs
    from backend.api import sessions as sess_api
    from backend.api.models import (
        CreateDocumentRequest, OpenDocumentRequest, RenameDocumentRequest)


class FakeRequest:
    """Just enough of a Starlette Request: case-insensitive header lookup."""

    def __init__(self, client=None, name=None, document=None):
        self.headers = {}
        if client:
            self.headers["x-client-id"] = client
        if name:
            self.headers["x-client-name"] = name
        if document:
            self.headers["x-document"] = document


class FakeUpload:
    def __init__(self, filename, data=b"x"):
        self.filename, self._data = filename, data

    async def read(self):
        return self._data


class patched_registry:
    """Point the dependency module at a registry built for the test."""

    def __init__(self, registry):
        self.registry = registry

    def __enter__(self):
        self.saved = deps.registry
        deps.registry = self.registry
        return self.registry

    def __exit__(self, *exc):
        deps.registry = self.saved


def open_as(registry, name, client, filename):
    return docs.open_document(OpenDocumentRequest(filename=filename), FakeRequest(client, name), registry)


# ---------------------------------------------------------------- open / create

def test_open_with_an_identity_joins_a_shared_session_and_returns_its_id():
    if not AVAILABLE: return
    with tempfile.TemporaryDirectory() as folder:
        workbook(folder, "a.xlsx")
        registry, _ = make_registry(folder)
        first = open_as(registry, "Alice", ALICE, "a.xlsx")
        second = open_as(registry, "Bob", BOB, "a.xlsx")
        assert first.success and second.success and first.session == second.session and first.session
        assert (first.rows, first.columns) == (2, 2) and first.filename == "a.xlsx"
        assert len(registry.describe()[0]["clients"]) == 2


def test_open_without_an_identity_keeps_the_old_single_document_behaviour():
    if not AVAILABLE: return
    with tempfile.TemporaryDirectory() as folder:
        workbook(folder, "a.xlsx")
        registry, _ = make_registry(folder)
        response = docs.open_document(OpenDocumentRequest(filename="a.xlsx"), FakeRequest(), registry)
        assert response.success and response.session is None
        assert registry.default.controller.filename() == "a.xlsx" and registry._sessions == {}


def test_old_and_new_style_clients_cannot_open_the_same_file_side_by_side():
    if not AVAILABLE: return
    with tempfile.TemporaryDirectory() as folder:
        workbook(folder, "a.xlsx")
        registry, _ = make_registry(folder)
        docs.open_document(OpenDocumentRequest(filename="a.xlsx"), FakeRequest(), registry)
        refused = open_as(registry, "Alice", ALICE, "a.xlsx")
        assert refused.success is False and "legacy" in refused.message

    with tempfile.TemporaryDirectory() as folder:
        workbook(folder, "a.xlsx")
        registry, _ = make_registry(folder)
        open_as(registry, "Alice", ALICE, "a.xlsx")
        refused = docs.open_document(OpenDocumentRequest(filename="a.xlsx"), FakeRequest(), registry)
        assert refused.success is False and "shared session" in refused.message


def test_open_failures_are_reported_not_raised():
    if not AVAILABLE: return
    with tempfile.TemporaryDirectory() as folder:
        registry, _ = make_registry(folder)
        response = open_as(registry, "Alice", ALICE, "missing.xlsx")
        assert response.success is False and response.session is None and response.message


def test_create_with_an_identity_writes_the_file_and_refuses_to_overwrite():
    if not AVAILABLE: return
    with tempfile.TemporaryDirectory() as folder:
        workbook(folder, "taken.xlsx")
        registry, _ = make_registry(folder)
        made = docs.create_document(CreateDocumentRequest(filename="new.xlsx"), FakeRequest(ALICE, "Alice"), registry)
        assert made.success and made.session and os.path.isfile(os.path.join(folder, "new.xlsx"))

        again = docs.create_document(CreateDocumentRequest(filename="taken.xlsx"), FakeRequest(ALICE), registry)
        assert again.success is False and "already exists" in again.message
        assert os.path.getsize(os.path.join(folder, "taken.xlsx")) > 0           # untouched


# ---------------------------------------------------------------- close

def test_close_leaves_the_session_and_the_last_one_out_saves_and_releases():
    if not AVAILABLE: return
    with tempfile.TemporaryDirectory() as folder:
        workbook(folder, "a.xlsx")
        registry, _ = make_registry(folder)
        session_id = open_as(registry, "Alice", ALICE, "a.xlsx").session
        open_as(registry, "Bob", BOB, "a.xlsx")

        with patched_registry(registry):
            for client, expect_open in ((ALICE, True), (BOB, False)):
                generator = deps.get_session(FakeRequest(client, document=session_id))
                session = next(generator)
                session.controller.edit_cell(0, 0, f"edited-{client}")
                response = docs.close_document(FakeRequest(client, document=session_id), session, registry)
                generator.close()
                assert response.success and response.filename == "a.xlsx"
                assert registry.is_open("a.xlsx") is expect_open

        reopened = registry.open("a.xlsx", ALICE)
        assert reopened.controller.cell_value(0, 0) == f"edited-{BOB}"          # saved on release


def test_close_on_the_default_session_closes_it_as_before():
    if not AVAILABLE: return
    with tempfile.TemporaryDirectory() as folder:
        workbook(folder, "a.xlsx")
        registry, _ = make_registry(folder)
        docs.open_document(OpenDocumentRequest(filename="a.xlsx"), FakeRequest(), registry)
        response = docs.close_document(FakeRequest(), registry.default, registry)
        assert response.success and registry.default.controller.is_loaded() is False


# ---------------------------------------------------------------- guards

def test_delete_rename_and_upload_are_refused_for_a_document_others_are_editing():
    if not AVAILABLE: return
    with tempfile.TemporaryDirectory() as folder:
        workbook(folder, "busy.xlsx")
        workbook(folder, "free.xlsx")
        registry, _ = make_registry(folder)
        open_as(registry, "Alice", ALICE, "busy.xlsx")
        controller = registry.default.controller

        refused = docs.delete_document("busy.xlsx", controller, registry)
        assert refused.success is False and os.path.isfile(os.path.join(folder, "busy.xlsx"))

        for old, new in (("busy.xlsx", "x.xlsx"), ("free.xlsx", "busy.xlsx")):
            refused = docs.rename_document(RenameDocumentRequest(old_name=old, new_name=new), controller, registry)
            assert refused.success is False
        assert sorted(f for f in os.listdir(folder) if f.endswith(".xlsx")) == ["busy.xlsx", "free.xlsx"]

        upload = asyncio.run(docs.upload_document(FakeUpload("busy.xlsx"), controller, registry))
        assert upload.success is False

        # a document nobody has open is unaffected
        assert docs.delete_document("free.xlsx", controller, registry).success is True


# ---------------------------------------------------------------- the dependency

def test_the_dependency_holds_the_sessions_lock_for_the_whole_request():
    if not AVAILABLE: return
    with tempfile.TemporaryDirectory() as folder:
        workbook(folder, "a.xlsx")
        registry, _ = make_registry(folder)
        session_id = open_as(registry, "Alice", ALICE, "a.xlsx").session

        with patched_registry(registry):
            generator = deps.get_session(FakeRequest(ALICE, document=session_id))
            session = next(generator)
            assert session.lock.locked()
            assert deps.get_controller(session) is session.controller
            generator.close()
            assert not session.lock.locked()


def test_a_request_with_no_session_header_uses_the_default_session():
    if not AVAILABLE: return
    with tempfile.TemporaryDirectory() as folder:
        registry, _ = make_registry(folder)
        with patched_registry(registry):
            generator = deps.get_session(FakeRequest())
            assert next(generator) is registry.default
            generator.close()


def test_an_unknown_session_gets_a_409_the_client_can_recognise():
    if not AVAILABLE: return
    with tempfile.TemporaryDirectory() as folder:
        registry, _ = make_registry(folder)
        with patched_registry(registry):
            generator = deps.get_session(FakeRequest(ALICE, document="0123456789abcdef"))
            try:
                next(generator)
            except Exception as error:                                   # HTTPException
                assert getattr(error, "status_code", None) == 409
                assert "SESSION_NOT_OPEN" in str(getattr(error, "detail", error))
                return
        raise AssertionError("expected a 409")


def test_a_session_released_while_idle_is_reattached_by_the_next_request():
    if not AVAILABLE: return
    with tempfile.TemporaryDirectory() as folder:
        workbook(folder, "a.xlsx")
        registry, clock = make_registry(folder, ttl=60)
        session_id = open_as(registry, "Alice", ALICE, "a.xlsx").session
        with patched_registry(registry):
            first = deps.get_session(FakeRequest(ALICE, document=session_id))
            session = next(first)
            session.controller.edit_cell(0, 0, "typed before the break")
            first.close()

            clock.advance(1000)                                          # the user walked away
            second = deps.get_session(FakeRequest(ALICE, document=session_id))
            back = next(second)                                          # no error: transparently re-opened
            assert back.controller.cell_value(0, 0) == "typed before the break"
            second.close()


# ---------------------------------------------------------------- listing

def test_the_sessions_listing_shows_documents_and_who_is_in_them():
    if not AVAILABLE: return
    with tempfile.TemporaryDirectory() as folder:
        workbook(folder, "a.xlsx")
        workbook(folder, "b.xlsx")
        registry, _ = make_registry(folder)
        open_as(registry, "Alice", ALICE, "a.xlsx")
        open_as(registry, "Bob", BOB, "a.xlsx")
        open_as(registry, "Bob", BOB, "b.xlsx")
        listing = sess_api.list_sessions(registry).model_dump()
        assert listing["success"] is True
        by_doc = {s["document"]: [c["name"] for c in s["clients"]] for s in listing["sessions"]}
        assert by_doc == {"a.xlsx": ["Alice", "Bob"], "b.xlsx": ["Bob"]}
