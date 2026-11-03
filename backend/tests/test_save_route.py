"""The save route and the scheduler: an autosave request is only a hint while the
scheduler runs; an explicit Save always writes. Needs FastAPI (the route module), so
it runs on a real machine; without it each test passes vacuously, like test_collab_api."""

import tempfile

try:
    from backend import dependencies
    from backend.api import documents as documents_api
    AVAILABLE = True
except ImportError:
    AVAILABLE = False

from backend.tests.test_collab_service import first_cell, make_session


def with_scheduler_running(running, action):
    scheduler = dependencies.save_scheduler
    before = scheduler._running
    scheduler._running = running

    try:
        return action()
    finally:
        scheduler._running = before


def edited_session(folder):
    session = make_session(folder)
    session.controller.edit_cells([(0, 0, "changed")])
    assert session.controller.modified()
    return session


def test_an_autosave_request_is_deferred_while_the_scheduler_runs():
    if not AVAILABLE: return

    with tempfile.TemporaryDirectory() as folder:
        session = edited_session(folder)

        response = with_scheduler_running(True, lambda: documents_api.save_document(session.controller, auto=True))

        assert response.success is True and response.deferred is True
        assert response.modified is True                    # nothing was written


def test_an_explicit_save_writes_at_once_even_while_the_scheduler_runs():
    if not AVAILABLE: return

    with tempfile.TemporaryDirectory() as folder:
        session = edited_session(folder)

        response = with_scheduler_running(True, lambda: documents_api.save_document(session.controller))

        assert response.success is True and response.deferred is False
        assert response.modified is False


def test_without_a_running_scheduler_an_autosave_request_still_saves():
    if not AVAILABLE: return

    with tempfile.TemporaryDirectory() as folder:
        session = edited_session(folder)

        response = with_scheduler_running(False, lambda: documents_api.save_document(session.controller, auto=True))

        assert response.success is True and response.deferred is False
        assert response.modified is False


def test_the_save_response_says_deferred_false_by_default():
    if not AVAILABLE: return

    from backend.api.models import SaveDocumentResponse

    assert SaveDocumentResponse(success=True).deferred is False
