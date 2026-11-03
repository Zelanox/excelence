"""When documents are saved to disk (backend/save_scheduler.py).

Most tests drive tick() with a fake clock and stand-in sessions, so every rule
(debounce, ceiling, spacing, busy sessions, failures) is checked exactly; two
use real documents and files. Plain functions, like the other tests here.
"""

import asyncio
import tempfile
import threading

from openpyxl import load_workbook

from backend.save_scheduler import SaveScheduler
from backend.tests.test_sessions import FakeClock, make_registry, workbook


class FakeDocument:
    def __init__(self):
        self.change_count = 0


class FakeController:
    """Enough of a controller for the scheduler; saving takes ``save_takes`` fake seconds."""

    def __init__(self, clock, save_takes=0.0, loaded=True):
        self.document = FakeDocument()
        self._clock = clock
        self._modified = False
        self._loaded = loaded
        self.save_takes = save_takes
        self.saves = 0
        self.result = True

    def change(self):
        self.document.change_count += 1
        self._modified = True

    def is_loaded(self):
        return self._loaded

    def modified(self):
        return self._modified

    def save_document(self):
        self._clock.advance(self.save_takes)
        self.saves += 1

        if self.result:
            self._modified = False

        return self.result


class FakeSession:
    def __init__(self, controller, filename="a.xlsx"):
        self.controller = controller
        self.filename = filename
        self.lock = threading.Lock()


class FakeRegistry:
    def __init__(self, *sessions):
        self.sessions = list(sessions)

    def open_sessions(self):
        return list(self.sessions)


def setup(save_takes=0.0, **options):
    clock = FakeClock()
    controller = FakeController(clock, save_takes)
    session = FakeSession(controller)
    scheduler = SaveScheduler(FakeRegistry(session), clock=clock, **options)
    return clock, controller, session, scheduler


def run_for(clock, scheduler, seconds):
    """Tick once a second for ``seconds`` seconds; returns how many saves happened."""
    saved = 0

    for _ in range(seconds):
        clock.advance(1)
        saved += scheduler.tick()

    return saved


def test_a_document_is_saved_after_it_has_been_quiet_for_the_debounce_time():
    clock, controller, _, scheduler = setup()
    scheduler.tick()
    controller.change()

    assert scheduler.tick() == 0                       # just changed
    clock.advance(1)
    assert scheduler.tick() == 0                       # one second of quiet is not enough
    clock.advance(1)
    assert scheduler.tick() == 1                       # two seconds: saved
    assert controller.saves == 1 and not controller.modified()


def test_nothing_is_saved_while_the_changes_keep_coming():
    clock, controller, _, scheduler = setup()

    saved = 0

    for _ in range(25):                                # a change every second for 25 seconds
        controller.change()
        clock.advance(1)
        saved += scheduler.tick()

    assert saved == 0 and controller.saves == 0


def test_changes_that_never_stop_are_saved_anyway_once_the_oldest_is_30_seconds_old():
    clock, controller, _, scheduler = setup()
    scheduler.tick()

    saves_at = []

    for second in range(1, 70):
        controller.change()
        clock.advance(1)

        if scheduler.tick():
            saves_at.append(second)

    assert saves_at == [31, 62]            # 30 s after the tick that first saw each unsaved change


def test_a_clean_document_is_never_saved():
    clock, controller, _, scheduler = setup()

    assert run_for(clock, scheduler, 60) == 0
    assert controller.saves == 0


def test_saves_keep_a_distance_of_four_times_as_long_as_the_last_one_took():
    clock, controller, _, scheduler = setup(save_takes=3.0)     # a slow document: 3 s per save

    controller.change()
    run_for(clock, scheduler, 3)
    assert controller.saves == 1

    controller.change()                                 # changed again straight after
    first_at = clock()

    while controller.saves < 2:
        clock.advance(1)
        scheduler.tick()
        assert clock() - first_at < 60

    # 12 s (4 x 3 s) after that save finished, not sooner.
    assert clock() - first_at >= 12 - 3 - 1


def test_the_distance_is_at_least_the_minimum_interval_even_for_instant_saves():
    clock, controller, _, scheduler = setup(save_takes=0.0, debounce=0.0, min_interval=5.0)

    controller.change()
    assert run_for(clock, scheduler, 1) == 1

    controller.change()
    assert run_for(clock, scheduler, 3) == 0           # 4 s since the save: too soon
    assert run_for(clock, scheduler, 2) == 1           # 6 s: allowed


def test_a_document_somebody_is_working_in_is_skipped_and_saved_on_a_later_tick():
    clock, controller, session, scheduler = setup()
    scheduler.tick()
    controller.change()
    scheduler.tick()
    clock.advance(5)

    session.lock.acquire()                              # a request holds the lock
    assert scheduler.tick() == 0 and controller.saves == 0

    session.lock.release()
    assert scheduler.tick() == 1


def test_a_failed_save_is_retried_at_the_normal_pace_and_the_document_stays_unsaved():
    clock, controller, _, scheduler = setup(min_interval=4.0)
    scheduler.tick()
    controller.result = False
    controller.change()
    scheduler.tick()
    clock.advance(3)

    assert scheduler.tick() == 0 and controller.saves == 1 and controller.modified()

    for _ in range(3):                                  # not again within the interval
        clock.advance(1)
        scheduler.tick()
        assert controller.saves == 1

    controller.result = True
    clock.advance(2)
    assert scheduler.tick() == 1 and not controller.modified()


def test_an_exception_while_saving_does_not_escape_or_lose_the_lock():
    clock, controller, session, scheduler = setup()

    def explode():
        raise OSError("disk full")

    controller.save_document = explode
    controller.change()
    clock.advance(3)

    assert scheduler.tick() == 0
    assert session.lock.acquire(blocking=False)         # released
    session.lock.release()


def test_unloaded_sessions_are_ignored_and_each_session_has_its_own_timing():
    clock = FakeClock()
    unloaded = FakeSession(FakeController(clock, loaded=False), "x.xlsx")
    first = FakeSession(FakeController(clock), "a.xlsx")
    second = FakeSession(FakeController(clock), "b.xlsx")
    scheduler = SaveScheduler(FakeRegistry(unloaded, first, second), clock=clock)

    unloaded.controller.change()
    first.controller.change()
    scheduler.tick()
    clock.advance(1)
    second.controller.change()                          # a second later
    scheduler.tick()

    clock.advance(1)
    assert scheduler.tick() == 1                        # only the first has been quiet for 2 s
    assert (first.controller.saves, second.controller.saves, unloaded.controller.saves) == (1, 0, 0)

    clock.advance(1)
    assert scheduler.tick() == 1
    assert second.controller.saves == 1


def test_a_document_that_is_closed_and_forgotten_does_not_leak_state():
    clock, controller, session, scheduler = setup()
    controller.change()
    scheduler.tick()
    assert len(scheduler._states) == 1

    scheduler._registry.sessions.clear()
    del session
    import gc
    gc.collect()

    assert len(scheduler._states) == 0


def test_real_documents_are_saved_to_disk_by_a_tick():
    with tempfile.TemporaryDirectory() as folder:
        workbook(folder, "a.xlsx")
        registry, clock = make_registry(folder)
        session = registry.open("a.xlsx", "client-alice-0001", "Alice")
        scheduler = SaveScheduler(registry, clock=clock)

        scheduler.tick()
        session.controller.edit_cells([(0, 0, "saved by the scheduler")])
        assert session.controller.modified()

        clock.advance(1)
        assert scheduler.tick() == 0                    # not quiet long enough
        clock.advance(2)
        assert scheduler.tick() == 1

        assert not session.controller.modified()
        path = session.controller.document._resolve_path("a.xlsx")
        assert load_workbook(path).active.cell(row=2, column=1).value == "saved by the scheduler"


def test_only_the_scheduler_saves_a_busy_real_document_and_never_while_it_is_locked():
    with tempfile.TemporaryDirectory() as folder:
        workbook(folder, "a.xlsx")
        registry, clock = make_registry(folder)
        session = registry.open("a.xlsx", "client-alice-0001", "Alice")
        scheduler = SaveScheduler(registry, clock=clock)
        scheduler.tick()
        session.controller.edit_cells([(0, 0, "x")])
        scheduler.tick()
        clock.advance(5)

        with session.lock:
            assert scheduler.tick() == 0
            assert session.controller.modified()

        assert scheduler.tick() == 1


async def until(condition, timeout=10.0):
    """Wait for ``condition()`` instead of for a fixed time (timers are coarse on Windows)."""
    loop = asyncio.get_running_loop()
    deadline = loop.time() + timeout

    while not condition():
        assert loop.time() < deadline, "timed out waiting"
        await asyncio.sleep(0.005)


def test_run_ticks_until_cancelled_and_says_whether_it_is_running():
    async def scenario():
        clock, controller, _, scheduler = setup(debounce=0.0, min_interval=0.0)
        ticks = []
        scheduler.tick = lambda: ticks.append(1) or 0

        assert scheduler.running is False
        task = asyncio.create_task(scheduler.run(period=0.01))
        await until(lambda: len(ticks) >= 3)
        assert scheduler.running is True

        task.cancel()
        await asyncio.gather(task, return_exceptions=True)
        await asyncio.sleep(0.1)                        # a tick already running may still finish
        stopped = len(ticks)
        await asyncio.sleep(0.1)

        return scheduler.running, len(ticks) == stopped

    assert asyncio.run(scenario()) == (False, True)


def test_a_failing_tick_does_not_stop_the_loop():
    async def scenario():
        clock, controller, _, scheduler = setup()
        calls = []

        def flaky():
            calls.append(1)

            if len(calls) == 1:
                raise RuntimeError("boom")

            return 0

        scheduler.tick = flaky
        task = asyncio.create_task(scheduler.run(period=0.01))
        await until(lambda: len(calls) >= 3)            # it carried on after the failure
        task.cancel()
        await asyncio.gather(task, return_exceptions=True)

    asyncio.run(scenario())
