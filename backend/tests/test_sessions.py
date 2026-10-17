"""Document sessions: one shared in-memory document per open file."""

import os
import tempfile
import threading

from openpyxl import Workbook

import backend.sessions as sessions_module
from backend.controller.controller import Controller
from backend.document.document import Document
from backend.network.client import NetworkClient
from backend.sessions import (
    DEFAULT_NAME,
    DocumentBusy,
    SessionNotOpen,
    SessionRegistry,
    clean_client_name,
    document_key,
    session_id_for,
    valid_client_id,
)
from backend.storage.excel_storage import ExcelStorage
from backend.utils.config import SERVER_IP, SERVER_PORT

ALICE = "client-alice-0001"
BOB = "client-bob-00002"
CARA = "client-cara-0003"


class FakeClock:
    def __init__(self):
        self.now = 1000.0

    def __call__(self):
        return self.now

    def advance(self, seconds):
        self.now += seconds


def workbook(folder, name, rows=(("a", 1), ("b", 2)), subfolder=None):
    target = os.path.join(folder, subfolder) if subfolder else folder
    os.makedirs(target, exist_ok=True)
    book = Workbook()
    book.active.title = "Sheet1"
    book.active.append(["name", "n"])
    for row in rows:
        book.active.append(list(row))
    book.save(os.path.join(target, name))


def make_registry(folder, ttl=120.0, clock=None):
    def factory():
        document = Document(ExcelStorage(), NetworkClient(SERVER_IP, SERVER_PORT))
        document.documents_folder = folder
        return Controller(document)

    clock = clock or FakeClock()
    return SessionRegistry(factory, clock=clock, client_ttl=ttl), clock


# ----------------------------------------------------------------------
# Identity helpers
# ----------------------------------------------------------------------

def test_document_key_treats_equivalent_spellings_as_one_document():
    keys = {document_key(n) for n in ("reports/q1.xlsx", "reports\\q1.xlsx", "./reports/q1.xlsx",
                                      " reports//q1.xlsx ", "reports/./q1.xlsx")}
    assert len(keys) == 1 and None not in keys
    assert document_key("a.xlsx") != document_key("b.xlsx")
    if os.name == "nt":
        assert document_key("Budget.xlsx") == document_key("budget.xlsx")   # case-insensitive file system


def test_document_key_rejects_anything_that_is_not_a_plain_relative_path():
    for bad in ("", "   ", "..", "../x.xlsx", "a/../b.xlsx", "/etc/passwd", "C:\\x.xlsx", "c:/x.xlsx", None, 5, b"x"):
        assert document_key(bad) is None, bad


def test_session_ids_are_stable_distinct_and_header_safe():
    a, b = session_id_for(document_key("a.xlsx")), session_id_for(document_key("b.xlsx"))
    assert a == session_id_for(document_key("a.xlsx")) and a != b
    assert a.isascii() and a.isalnum() and len(a) == 16
    # an Arabic file name still gets an ASCII id
    assert session_id_for(document_key("ميزانية.xlsx")).isascii()


def test_client_id_validation():
    assert valid_client_id("abcdefgh") and valid_client_id("A1_b-2" * 5)
    for bad in ("short", "has space!!", "x" * 65, "", None, 123, "ünïcödé-id"):
        assert not valid_client_id(bad), bad


def test_client_names_are_decoded_cleaned_and_limited():
    assert clean_client_name("%D8%B3%D8%A7%D8%B1%D8%A9") == "سارة"                  # percent-encoded Arabic
    assert clean_client_name("  Sara   Ali  ") == "Sara Ali"
    assert clean_client_name("a\x00b\x1fc\nd") == "abcd"
    assert clean_client_name("x" * 100) == "x" * 40
    for blank in ("", "   ", None, 5, "\x00\x01"):
        assert clean_client_name(blank) == DEFAULT_NAME, blank
    assert clean_client_name("%FF%FE") == "%FF%FE"                                  # invalid UTF-8: never raises


# ----------------------------------------------------------------------
# Opening and joining
# ----------------------------------------------------------------------

def test_two_clients_opening_the_same_file_share_one_session_and_see_each_others_edits():
    with tempfile.TemporaryDirectory() as folder:
        workbook(folder, "shared.xlsx")
        registry, _ = make_registry(folder)

        first = registry.open("shared.xlsx", ALICE, "Alice")
        second = registry.open("shared.xlsx", BOB, "Bob")
        assert first is second and len(registry._sessions) == 1

        assert first.controller.edit_cell(0, 0, "changed by alice") is True       # NOT saved to disk
        assert second.controller.cell_value(0, 0) == "changed by alice"           # Bob sees it immediately

        assert [c["name"] for c in registry.describe()[0]["clients"]] == ["Alice", "Bob"]


def test_different_files_get_independent_sessions_and_locks():
    with tempfile.TemporaryDirectory() as folder:
        workbook(folder, "a.xlsx")
        workbook(folder, "b.xlsx")
        registry, _ = make_registry(folder)
        a = registry.open("a.xlsx", ALICE)
        b = registry.open("b.xlsx", BOB)
        assert a is not b and a.id != b.id and a.controller is not b.controller

        with a.lock:                                       # a request is busy in document A...
            assert b.lock.acquire(blocking=False)          # ...document B is not held up by it
            b.lock.release()
            assert not a.lock.acquire(blocking=False)      # while A's own requests do queue


def test_equivalent_spellings_join_the_same_session():
    with tempfile.TemporaryDirectory() as folder:
        workbook(folder, "q1.xlsx", subfolder="reports")
        registry, _ = make_registry(folder)
        one = registry.open("reports/q1.xlsx", ALICE)
        two = registry.open("reports\\q1.xlsx", BOB)
        assert one is two


def test_unopenable_requests_register_nothing():
    with tempfile.TemporaryDirectory() as folder:
        workbook(folder, "ok.xlsx")
        registry, _ = make_registry(folder)
        assert registry.open("missing.xlsx", ALICE) is None
        assert registry.open("../escape.xlsx", ALICE) is None
        assert registry.open("", ALICE) is None
        assert registry.open("ok.xlsx", "bad id") is None
        assert registry.open("ok.xlsx", None) is None
        assert registry._sessions == {} and registry.describe() == []


def test_rejoining_refreshes_presence_and_updates_the_name():
    with tempfile.TemporaryDirectory() as folder:
        workbook(folder, "a.xlsx")
        registry, clock = make_registry(folder)
        session = registry.open("a.xlsx", ALICE, "Alice")
        joined = session.clients[ALICE].joined_at
        clock.advance(30)
        registry.open("a.xlsx", ALICE, "Alice B.")
        assert session.clients[ALICE].joined_at == joined and session.clients[ALICE].last_seen == joined + 30
        assert session.clients[ALICE].name == "Alice B."
        assert len(session.clients) == 1


# ----------------------------------------------------------------------
# Resolving a request's session
# ----------------------------------------------------------------------

def test_no_session_id_means_the_default_session():
    with tempfile.TemporaryDirectory() as folder:
        registry, _ = make_registry(folder)
        assert registry.resolve(None) is registry.default
        assert registry.resolve("") is registry.default
        assert registry.default.is_default


def test_resolve_finds_the_session_and_refreshes_the_caller():
    with tempfile.TemporaryDirectory() as folder:
        workbook(folder, "a.xlsx")
        registry, clock = make_registry(folder)
        session = registry.open("a.xlsx", ALICE, "Alice")
        clock.advance(50)
        assert registry.resolve(session.id, ALICE, None) is session
        assert session.clients[ALICE].last_seen == clock.now
        registry.resolve(session.id, BOB, "Bob")                  # a client that never called open still joins
        assert BOB in session.clients


def test_an_unknown_session_id_is_rejected():
    with tempfile.TemporaryDirectory() as folder:
        registry, _ = make_registry(folder)
        try:
            registry.resolve("deadbeefdeadbeef", ALICE)
        except SessionNotOpen:
            return
        raise AssertionError("expected SessionNotOpen")


# ----------------------------------------------------------------------
# Leaving and releasing
# ----------------------------------------------------------------------

def test_leaving_keeps_the_session_until_the_last_client_goes_then_saves_it():
    with tempfile.TemporaryDirectory() as folder:
        workbook(folder, "a.xlsx")
        registry, _ = make_registry(folder)
        session = registry.open("a.xlsx", ALICE)
        registry.open("a.xlsx", BOB)
        session.controller.edit_cell(0, 0, "edited")

        assert registry.leave(session, ALICE) is False             # Bob is still here
        assert registry.is_open("a.xlsx") and session.controller.modified()

        assert registry.leave(session, BOB) is True                # last one out: saved and released
        assert not registry.is_open("a.xlsx") and registry._sessions == {}

        again = registry.open("a.xlsx", CARA)                       # loads fresh from disk
        assert again is not session and again.controller.cell_value(0, 0) == "edited"


def test_a_failed_save_keeps_the_session_so_work_is_not_lost():
    with tempfile.TemporaryDirectory() as folder:
        workbook(folder, "a.xlsx")
        registry, _ = make_registry(folder)
        session = registry.open("a.xlsx", ALICE)
        session.controller.edit_cell(0, 0, "precious")
        original = session.controller.save_document
        session.controller.save_document = lambda *a, **k: False

        assert registry.leave(session, ALICE) is False
        assert registry.is_open("a.xlsx") and session.controller.cell_value(0, 0) == "precious"

        session.controller.save_document = original
        assert registry.leave(session, None) is True


def test_leaving_the_default_session_never_releases_it():
    with tempfile.TemporaryDirectory() as folder:
        registry, _ = make_registry(folder)
        assert registry.leave(registry.default, ALICE) is False


# ----------------------------------------------------------------------
# Idle clients and re-attaching
# ----------------------------------------------------------------------

def test_idle_clients_expire_and_an_emptied_session_is_saved_and_released():
    with tempfile.TemporaryDirectory() as folder:
        workbook(folder, "a.xlsx")
        registry, clock = make_registry(folder, ttl=100)
        session = registry.open("a.xlsx", ALICE)
        registry.open("a.xlsx", BOB)
        session.controller.edit_cell(0, 0, "unsaved")

        clock.advance(60)
        registry.resolve(session.id, BOB)                          # Bob keeps talking, Alice goes quiet
        clock.advance(60)                                           # Alice: 120s idle, Bob: 60s
        assert [c["name"] for c in registry.describe()[0]["clients"]] == [DEFAULT_NAME]
        assert registry.is_open("a.xlsx")

        clock.advance(100)                                          # now Bob is gone too
        assert registry.describe() == [] and not registry.is_open("a.xlsx")


def test_a_released_session_is_reopened_transparently_for_a_returning_client():
    with tempfile.TemporaryDirectory() as folder:
        workbook(folder, "a.xlsx")
        registry, clock = make_registry(folder, ttl=100)
        session = registry.open("a.xlsx", ALICE, "Alice")
        session.controller.edit_cell(0, 0, "kept")
        clock.advance(500)
        registry.describe()                                         # expiry runs: session saved and released
        assert registry._sessions == {}

        back = registry.resolve(session.id, ALICE, "Alice")         # same id, no error
        assert back.id == session.id and back is not session
        assert back.controller.cell_value(0, 0) == "kept"           # it was saved when released
        assert ALICE in back.clients


def test_a_released_session_whose_file_is_gone_cannot_be_reopened():
    with tempfile.TemporaryDirectory() as folder:
        workbook(folder, "a.xlsx")
        registry, clock = make_registry(folder, ttl=10)
        session = registry.open("a.xlsx", ALICE)
        clock.advance(100)
        registry.describe()
        os.remove(os.path.join(folder, "a.xlsx"))
        try:
            registry.resolve(session.id, ALICE)
        except SessionNotOpen:
            return
        raise AssertionError("expected SessionNotOpen")


def test_expiry_never_waits_for_a_busy_session():
    with tempfile.TemporaryDirectory() as folder:
        workbook(folder, "a.xlsx")
        registry, clock = make_registry(folder, ttl=10)
        session = registry.open("a.xlsx", ALICE)
        clock.advance(100)

        with session.lock:                                          # a request is in flight
            registry.describe()                                     # must return immediately, not deadlock
            assert registry.is_open("a.xlsx")                       # skipped, not released under the request

        registry.describe()                                         # idle now: released
        assert not registry.is_open("a.xlsx")


def test_only_recently_released_sessions_are_remembered():
    with tempfile.TemporaryDirectory() as folder:
        for n in range(5):
            workbook(folder, f"d{n}.xlsx")
        registry, clock = make_registry(folder, ttl=10)
        original = sessions_module.MAX_REMEMBERED_SESSIONS
        sessions_module.MAX_REMEMBERED_SESSIONS = 3
        try:
            ids = [registry.open(f"d{n}.xlsx", ALICE).id for n in range(5)]
            clock.advance(100)
            registry.describe()
            assert len(registry._released) == 3
            assert list(registry._released) == ids[-3:]
        finally:
            sessions_module.MAX_REMEMBERED_SESSIONS = original


# ----------------------------------------------------------------------
# The legacy default session
# ----------------------------------------------------------------------

def test_a_file_open_in_the_default_session_is_refused_to_shared_clients():
    with tempfile.TemporaryDirectory() as folder:
        workbook(folder, "a.xlsx")
        registry, _ = make_registry(folder)
        assert registry.default.controller.open_document("a.xlsx") is True
        try:
            registry.open("a.xlsx", ALICE)
        except DocumentBusy:
            pass
        else:
            raise AssertionError("expected DocumentBusy")
        assert registry.is_open("a.xlsx") and not registry.is_open_in_session("a.xlsx")


def test_is_open_in_session_ignores_the_default_session():
    with tempfile.TemporaryDirectory() as folder:
        workbook(folder, "a.xlsx")
        workbook(folder, "b.xlsx")
        registry, _ = make_registry(folder)
        registry.default.controller.open_document("a.xlsx")
        registry.open("b.xlsx", ALICE)
        assert registry.is_open_in_session("b.xlsx") and not registry.is_open_in_session("a.xlsx")
        assert registry.is_open_in_session("../b.xlsx") is False


# ----------------------------------------------------------------------
# Creating
# ----------------------------------------------------------------------

def test_create_writes_the_file_and_opens_a_session():
    with tempfile.TemporaryDirectory() as folder:
        registry, _ = make_registry(folder)
        session = registry.create("new.xlsx", ALICE, "Alice")
        assert session is not None and os.path.isfile(os.path.join(folder, "new.xlsx"))
        assert registry.is_open("new.xlsx") and ALICE in session.clients
        assert registry.open("new.xlsx", BOB) is session            # the follow-up open joins it


def test_create_refuses_to_replace_an_existing_or_open_document():
    with tempfile.TemporaryDirectory() as folder:
        workbook(folder, "exists.xlsx")
        registry, _ = make_registry(folder)
        for name in ("exists.xlsx",):
            try:
                registry.create(name, ALICE)
            except DocumentBusy as error:
                assert "already exists" in str(error)
            else:
                raise AssertionError("expected DocumentBusy")

        registry.create("fresh.xlsx", ALICE)
        try:
            registry.create("fresh.xlsx", BOB)
        except DocumentBusy:
            pass
        else:
            raise AssertionError("expected DocumentBusy")


def test_create_rejects_bad_names_and_clients():
    with tempfile.TemporaryDirectory() as folder:
        registry, _ = make_registry(folder)
        assert registry.create("../x.xlsx", ALICE) is None
        assert registry.create("", ALICE) is None
        assert registry.create("x.xlsx", "bad id") is None
        assert registry.create("notexcel.txt", ALICE) is None
        assert registry.create("noextension", ALICE) is None          # would be invisible in the document list
        assert os.listdir(folder) == [] and registry._sessions == {}
        assert registry.create("Upper.XLSX", ALICE) is not None       # the extension check ignores case


# ----------------------------------------------------------------------
# Shutdown and concurrency
# ----------------------------------------------------------------------

def test_save_all_saves_every_modified_session_and_skips_busy_ones():
    with tempfile.TemporaryDirectory() as folder:
        workbook(folder, "a.xlsx")
        workbook(folder, "b.xlsx")
        workbook(folder, "c.xlsx")
        registry, _ = make_registry(folder)
        a = registry.open("a.xlsx", ALICE)
        b = registry.open("b.xlsx", ALICE)
        c = registry.open("c.xlsx", ALICE)
        a.controller.edit_cell(0, 0, "A!")
        b.controller.edit_cell(0, 0, "B!")                         # c is left unmodified

        assert registry.save_all() == 2
        assert not a.controller.modified() and not b.controller.modified()

        a.controller.edit_cell(0, 0, "A2")
        b.controller.edit_cell(0, 0, "B2")
        with b.lock:                                                 # b is mid-request
            assert registry.save_all(lock_timeout=0.05) == 1         # a saved; b skipped, no hang
        assert b.controller.modified()


def test_many_threads_opening_one_file_get_one_session():
    with tempfile.TemporaryDirectory() as folder:
        workbook(folder, "hot.xlsx")
        registry, _ = make_registry(folder)
        results, errors = [], []

        def worker(n):
            try:
                results.append(registry.open("hot.xlsx", f"client-thread-{n:04d}"))
            except Exception as error:                              # noqa: BLE001
                errors.append(error)

        threads = [threading.Thread(target=worker, args=(n,)) for n in range(24)]
        [t.start() for t in threads]
        [t.join() for t in threads]

        assert errors == []
        assert len({id(s) for s in results}) == 1 and len(registry._sessions) == 1
        assert len(results[0].clients) == 24


def test_threads_working_in_different_documents_do_not_interfere():
    with tempfile.TemporaryDirectory() as folder:
        names = [f"doc{n}.xlsx" for n in range(4)]
        for name in names:
            workbook(folder, name)
        registry, _ = make_registry(folder)
        opened = {name: registry.open(name, ALICE) for name in names}
        failures = []

        def worker(name):
            session = opened[name]
            for i in range(25):
                with session.lock:
                    if not session.controller.edit_cell(0, 0, f"{name}-{i}"):
                        failures.append((name, i))

        threads = [threading.Thread(target=worker, args=(name,)) for name in names]
        [t.start() for t in threads]
        [t.join() for t in threads]

        assert failures == []
        for name in names:
            assert opened[name].controller.cell_value(0, 0) == f"{name}-24"
