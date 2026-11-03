"""When the server saves documents to disk.

Saving rewrites and writes a whole .xlsx file while holding the document's
lock, so every other client waits for it: about 2 seconds for 10,000 rows on a
modest PC. If each client saved after every pause in its typing, a busy
document would spend its time saving. Instead the SERVER decides, once for
everybody:

* A document with unsaved changes is saved after it has been quiet for
  ``debounce`` seconds (the usual case: somebody stops typing).
* If changes never stop, it is saved anyway once the oldest unsaved change
  is ``max_wait`` seconds old, so a crash can lose at most about that much.
* Saves never come closer than ``factor`` times as long as the last save took
  (and ``min_interval``): a document whose save takes 2 s is saved at most
  every 8 s, so saving can't take more than about a fifth of the time.
* A document whose lock is busy (somebody is editing) is simply tried again
  on the next tick.

Clients' autosave requests (``POST /documents/save?auto=true``) are answered
"will be saved" without saving; an explicit Save, closing a document, the last
person leaving and server shutdown still save at once (see api/documents.py,
sessions.py and main.py).

``tick()`` does the work and is what the tests drive with a fake clock;
``run()`` calls it every second on a worker thread while the server lives.
"""

from __future__ import annotations

import asyncio
import math
import time
import weakref
from dataclasses import dataclass
from typing import Callable

from backend.utils.logger import get_logger

logger = get_logger("save")


@dataclass
class _State:
    seen_count: int = -1                # the document's change count when last looked at
    seen_at: float = 0.0                # when that count was first seen (the last change, to a tick)
    dirty_since: float | None = None    # when it was first seen with unsaved changes
    last_save_at: float | None = None
    last_save_seconds: float = 0.0


class SaveScheduler:

    def __init__(
        self,
        registry,
        clock: Callable[[], float] = time.monotonic,
        debounce: float = 2.0,
        max_wait: float = 30.0,
        factor: float = 4.0,
        min_interval: float = 2.0,
    ) -> None:
        self._registry = registry
        self._clock = clock
        self.debounce = debounce
        self.max_wait = max_wait
        self.factor = factor
        self.min_interval = min_interval

        self._states: "weakref.WeakKeyDictionary" = weakref.WeakKeyDictionary()
        self._running = False

    @property
    def running(self) -> bool:
        """True while run() is looping: clients may then leave autosaving to it."""
        return self._running

    def tick(self) -> int:
        """Save every document that is due. Returns how many were saved. Blocking: run it on a worker thread."""
        now = self._clock()
        saved = 0

        for session in self._registry.open_sessions():
            controller = session.controller

            if not controller.is_loaded():
                continue

            state = self._states.get(session)

            if state is None:
                state = self._states[session] = _State()

            count = controller.document.change_count

            if count != state.seen_count:
                state.seen_count = count
                state.seen_at = now

            if not controller.modified():
                state.dirty_since = None
                continue

            if state.dirty_since is None:
                state.dirty_since = now

            if self._due(state, now) and self._save(session, state):
                saved += 1

        return saved

    def _due(self, state: _State, now: float) -> bool:
        quiet = now - state.seen_at >= self.debounce
        waited_too_long = now - state.dirty_since >= self.max_wait
        interval = max(self.min_interval, self.factor * state.last_save_seconds)
        since_save = math.inf if state.last_save_at is None else now - state.last_save_at

        return (quiet or waited_too_long) and since_save >= interval

    def _save(self, session, state: _State) -> bool:
        # Somebody is working in the document: wait for the next tick rather
        # than queue behind them (or make them queue behind a save).
        if not session.lock.acquire(blocking=False):
            return False

        try:
            controller = session.controller

            if not controller.is_loaded() or not controller.modified():
                state.dirty_since = None
                return False

            started = self._clock()

            try:
                ok = controller.save_document()
            except Exception:
                logger.exception("Could not save %s", session.filename)
                ok = False

            finished = self._clock()
        finally:
            session.lock.release()

        # Counted even when it failed, so a failing save is retried at the
        # normal pace instead of every second.
        state.last_save_at = finished
        state.last_save_seconds = finished - started

        if ok:
            state.dirty_since = None
        else:
            logger.warning("Saving %s failed; will try again", session.filename)

        return ok

    async def run(self, period: float = 1.0) -> None:
        """Call tick() every ``period`` seconds until cancelled."""
        self._running = True

        try:
            while True:
                await asyncio.sleep(period)

                try:
                    await asyncio.to_thread(self.tick)
                except Exception:
                    logger.exception("The save scheduler's tick failed")
        finally:
            self._running = False
