"""The web layer of live collaboration: the two routes in backend/api/collab.py.

Like test_api_sessions, these call the route functions directly (no HTTP) and
do nothing where FastAPI is not importable.
"""

import tempfile

try:
    import fastapi  # noqa: F401
    AVAILABLE = True
except ImportError:                                           # pragma: no cover
    AVAILABLE = False

from backend.tests.test_collab_service import make_session

if AVAILABLE:
    from backend.api import collab as collab_api

CLIENT = "client-aaaa"


class FakeRequest:
    """Just enough of a Starlette Request: a header lookup."""

    def __init__(self, client=None):
        self.headers = {"x-client-id": client} if client else {}


def body(session, *ops, batch_id="b1", base=0):
    return {
        "client_batch_id": batch_id,
        "base_revision": base,
        "sheet_id": session.controller.current_sheet_id(),
        "ops": list(ops),
    }


def first_cell(session, value):
    data = session.controller.grid_data()
    return {"op": "set_cells", "cells": [{"row": data.row_ids[0], "column": data.column_ids[0], "value": value}]}


def test_submit_then_catch_up_through_the_routes():
    if not AVAILABLE: return
    with tempfile.TemporaryDirectory() as folder:
        session = make_session(folder)

        sent = collab_api.submit_ops(FakeRequest(CLIENT), body(session, first_cell(session, "Zed")), session)
        assert sent["accepted"] is True and sent["revision"] == 1
        assert session.controller.grid_data().rows[0]["Name"] == "Zed"

        caught_up = collab_api.ops_since(0, session)
        assert caught_up["resync_required"] is False
        assert [batch["revision"] for batch in caught_up["batches"]] == [1]
        assert caught_up["batches"][0]["ops"] == sent["applied"]


def test_the_client_id_comes_from_the_header():
    if not AVAILABLE: return
    with tempfile.TemporaryDirectory() as folder:
        session = make_session(folder)

        refused = collab_api.submit_ops(FakeRequest(), body(session, first_cell(session, "x")), session)

        assert refused["accepted"] is False and refused["code"] == "BAD_REQUEST"
        assert session.oplog.revision == 0


def test_a_refused_batch_comes_back_as_an_ordinary_answer():
    if not AVAILABLE: return
    with tempfile.TemporaryDirectory() as folder:
        session = make_session(folder)

        refused = collab_api.submit_ops(FakeRequest(CLIENT), {"ops": []}, session)

        assert refused["accepted"] is False and "message" in refused


# ----------------------------------------------------------------------
# Undo while others are in the document, reload, and the old routes
# ----------------------------------------------------------------------

def join(session, *client_ids):
    from backend.sessions import ClientInfo

    for client_id in client_ids:
        session.clients[client_id] = ClientInfo(client_id=client_id, name=client_id, joined_at=0.0, last_seen=0.0)


def test_undo_and_redo_are_refused_while_others_are_in_the_document():
    if not AVAILABLE: return
    from backend.api import spreadsheet as sheet_api

    with tempfile.TemporaryDirectory() as folder:
        session = make_session(folder)
        join(session, "client-aaaa", "client-bbbb")
        session.controller.edit_cell(0, 0, "mine")

        refused = sheet_api.undo(session)
        assert refused.success is False and refused.message == sheet_api.UNDO_UNAVAILABLE
        assert session.controller.grid_data().rows[0]["Name"] == "mine"       # untouched

        assert sheet_api.redo(session).success is False


def test_undo_still_works_for_someone_working_alone():
    if not AVAILABLE: return
    from backend.api import spreadsheet as sheet_api

    with tempfile.TemporaryDirectory() as folder:
        session = make_session(folder)
        join(session, "client-aaaa")
        session.controller.edit_cell(0, 0, "mine")

        assert sheet_api.undo(session).success is True
        assert session.controller.grid_data().rows[0]["Name"] == "Alice"

        legacy = make_session(folder, name="u.xlsx")        # a client with no identity at all
        legacy.controller.edit_cell(0, 0, "mine")
        assert sheet_api.undo(legacy).success is True


def test_reloading_a_document_makes_every_client_reload():
    if not AVAILABLE: return
    from backend.api import documents as docs_api

    with tempfile.TemporaryDirectory() as folder:
        session = make_session(folder)
        collab_api.submit_ops(FakeRequest(CLIENT), body(session, first_cell(session, "x")), session)

        docs_api.reload_document(session)

        assert collab_api.ops_since(0, session)["resync_required"] is True
        assert collab_api.ops_since(1, session)["resync_required"] is True


def test_the_per_request_dependency_logs_a_change_made_by_an_old_route():
    if not AVAILABLE: return
    import backend.dependencies as deps

    class OnlyThisSession:
        def __init__(self, session):
            self.session = session

        def resolve(self, session_id, client_id=None, client_name=None):
            return self.session

    with tempfile.TemporaryDirectory() as folder:
        session = make_session(folder)
        saved = deps.registry
        deps.registry = OnlyThisSession(session)

        try:
            request = FakeRequest(CLIENT)
            request.headers["x-document"] = "session"

            request_scope = deps.get_session(request)
            assert next(request_scope) is session
            session.controller.edit_cell(0, 0, "old route")         # what an old route's handler does

            try:
                next(request_scope)                                # the request ends
            except StopIteration:
                pass

            assert session.oplog.revision == 1
            assert collab_api.ops_since(0, session)["resync_required"] is True

            quiet = deps.get_session(request)                      # a request that changes nothing
            next(quiet)
            try:
                next(quiet)
            except StopIteration:
                pass

            assert session.oplog.revision == 1
        finally:
            deps.registry = saved


# ----------------------------------------------------------------------
# The revision that comes with the grid data
# ----------------------------------------------------------------------

def test_the_grid_payload_carries_the_revision_it_matches():
    if not AVAILABLE: return
    from backend.api import spreadsheet as sheet_api

    with tempfile.TemporaryDirectory() as folder:
        session = make_session(folder)
        assert sheet_api.data(session.controller).revision == 0

        collab_api.submit_ops(FakeRequest(CLIENT), body(session, first_cell(session, "x")), session)

        assert sheet_api.data(session.controller).revision == 1


def test_data_built_after_an_old_route_change_already_includes_that_changes_reload_entry():
    if not AVAILABLE: return
    from backend.api import spreadsheet as sheet_api

    with tempfile.TemporaryDirectory() as folder:
        session = make_session(folder)

        session.controller.edit_cell(0, 0, "old route")

        assert sheet_api.data(session.controller).revision == 1
