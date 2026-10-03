import threading

from backend.controller.controller import Controller


controller = Controller()

# Every request runs under this lock. FastAPI runs ordinary (non-async)
# route functions on a thread pool, and the client fires several requests
# at once (e.g. a batch of cell edits followed immediately by an undo).
# Interleaved handlers could corrupt the shared in-memory document - pandas
# is not thread-safe for concurrent writes - and would make undo history
# order depend on thread scheduling. The work per request is short, so
# running them one at a time costs nothing noticeable.
_request_lock = threading.Lock()


def get_controller():
    with _request_lock:
        yield controller
