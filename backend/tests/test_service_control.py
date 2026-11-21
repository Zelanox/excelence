"""Running the server in the background: start, stop, status, log-on start.

Most tests use stand-ins for the operating system (processes, ports, the
registry) so every branch can be checked. A few start a REAL detached
process (a tiny stand-in server written with the same pieces) to prove that
start / stop / the PID file / the stop file work together.
"""

import contextlib
import io
import os
import socket
import sys
import tempfile
import time
from pathlib import Path

from backend import service_cli
from backend import service_control as sc

PROJECT_ROOT = str(Path(__file__).resolve().parent.parent.parent)
ENV = {"EXCELENCE_HOST": "127.0.0.1", "EXCELENCE_PORT": "8765"}


def make_paths(folder):
    root = Path(folder)
    return sc.ServicePaths(root=root, logs_dir=root / "logs")


def free_port():
    with socket.socket() as probe:
        probe.bind(("127.0.0.1", 0))
        return probe.getsockname()[1]


def no_sleep(_):
    pass


class Clock:
    """A clock that moves forward only when something sleeps."""

    def __init__(self):
        self.now = 0.0

    def __call__(self):
        return self.now

    def sleep(self, seconds):
        self.now += seconds


class FakeProcess:
    def __init__(self, exit_code=None, on_poll=None):
        self.exit_code = exit_code
        self.on_poll = on_poll

    def poll(self):
        if self.on_poll:
            self.on_poll()
        return self.exit_code


# ----------------------------------------------------------------------
# The settings file
# ----------------------------------------------------------------------

def test_env_text_comments_blanks_quotes_and_export():
    values, bad = sc.parse_env_text(
        "# comment\n"
        "\n"
        "EXCELENCE_HOST=0.0.0.0\n"
        "  EXCELENCE_PORT = 9000  \n"
        'EXCELENCE_DOCUMENTS_DIR="D:\\My Files\\docs"\n'
        "export EXCELENCE_ACCESS_TOKEN='abcdefghijklmnop'\n"
    )

    assert bad == []
    assert values == {
        "EXCELENCE_HOST": "0.0.0.0",
        "EXCELENCE_PORT": "9000",
        "EXCELENCE_DOCUMENTS_DIR": "D:\\My Files\\docs",
        "EXCELENCE_ACCESS_TOKEN": "abcdefghijklmnop",
    }


def test_env_text_reports_lines_it_cannot_understand():
    values, bad = sc.parse_env_text("GOOD=1\nthis is not a setting\n=novalue\n1BAD=2\n")

    assert values == {"GOOD": "1"}
    assert bad == [2, 3, 4]


def test_env_file_never_overrides_what_is_already_set():
    with tempfile.TemporaryDirectory() as folder:
        path = Path(folder) / "excelence.env"
        path.write_text("EXCELENCE_PORT=9000\nEXCELENCE_HOST=0.0.0.0\n", encoding="utf-8")
        environ = {"EXCELENCE_PORT": "7000"}

        applied = sc.load_env_file(path, environ)

        assert environ == {"EXCELENCE_PORT": "7000", "EXCELENCE_HOST": "0.0.0.0"}
        assert applied == {"EXCELENCE_HOST": "0.0.0.0"}


def test_env_file_may_start_with_a_byte_order_mark_and_may_be_missing():
    with tempfile.TemporaryDirectory() as folder:
        path = Path(folder) / "excelence.env"
        path.write_bytes(b"\xef\xbb\xbfEXCELENCE_PORT=9000\r\n")
        environ = {}

        sc.load_env_file(path, environ)
        assert environ == {"EXCELENCE_PORT": "9000"}

        assert sc.load_env_file(Path(folder) / "nothing.env", {}) == {}


def test_config_template_is_created_once_and_changes_nothing_by_itself():
    with tempfile.TemporaryDirectory() as folder:
        paths = make_paths(folder)

        first = sc.init_config(paths)
        assert first.code == 0 and paths.env_file.exists()

        paths.env_file.write_text("EXCELENCE_PORT=1234\n", encoding="utf-8")
        second = sc.init_config(paths)

        assert "already exists" in second.message
        assert paths.env_file.read_text(encoding="utf-8") == "EXCELENCE_PORT=1234\n"

    # A fresh template applies no setting: every line is commented out.
    values, bad = sc.parse_env_text(sc.CONFIG_TEMPLATE)
    assert values == {} and bad == []


# ----------------------------------------------------------------------
# PID file
# ----------------------------------------------------------------------

def test_pid_file_round_trip_and_damaged_files():
    with tempfile.TemporaryDirectory() as folder:
        paths = make_paths(folder)

        assert sc.read_pid_file(paths) is None

        sc.write_pid_file(paths, "127.0.0.1", 8000, pid=4242)
        info = sc.read_pid_file(paths)

        assert (info.pid, info.host, info.port) == (4242, "127.0.0.1", 8000)
        assert info.started > 0

        for damaged in ("", "not json", "[]", '{"pid": "x"}', '{"host": "h"}'):
            paths.pid_file.write_text(damaged, encoding="utf-8")
            assert sc.read_pid_file(paths) is None, damaged

        sc.remove_pid_file(paths)
        assert not paths.pid_file.exists()
        sc.remove_pid_file(paths)  # removing twice is fine


def test_a_pid_file_is_only_removed_by_its_owner_when_asked():
    with tempfile.TemporaryDirectory() as folder:
        paths = make_paths(folder)
        sc.write_pid_file(paths, "127.0.0.1", 8000, pid=111)

        sc.remove_pid_file(paths, only_pid=222)
        assert paths.pid_file.exists()

        sc.remove_pid_file(paths, only_pid=111)
        assert not paths.pid_file.exists()


def test_a_second_server_is_refused_while_one_answers():
    with tempfile.TemporaryDirectory() as folder:
        paths = make_paths(folder)
        sc.write_pid_file(paths, "127.0.0.1", 8000, pid=999999)

        message = sc.claim_pid_file(paths, "127.0.0.1", 8000, is_alive=lambda pid: True, probe_fn=lambda h, p: True)

        assert "already running" in message and "999999" in message
        assert sc.read_pid_file(paths).pid == 999999        # untouched


def test_a_leftover_pid_file_does_not_block_a_new_server():
    with tempfile.TemporaryDirectory() as folder:
        paths = make_paths(folder)
        sc.write_pid_file(paths, "127.0.0.1", 8000, pid=999999)

        assert sc.claim_pid_file(paths, "127.0.0.1", 8001, is_alive=lambda pid: False, probe_fn=lambda h, p: True) is None
        assert sc.read_pid_file(paths).pid == os.getpid()
        assert sc.read_pid_file(paths).port == 8001

        # A live process that does not answer (a reused PID) does not block either.
        sc.write_pid_file(paths, "127.0.0.1", 8000, pid=999999)
        assert sc.claim_pid_file(paths, "127.0.0.1", 8000, is_alive=lambda pid: True, probe_fn=lambda h, p: False) is None


# ----------------------------------------------------------------------
# The stop watcher (runs inside the server)
# ----------------------------------------------------------------------

def test_stop_watcher_calls_back_once_and_removes_the_file():
    with tempfile.TemporaryDirectory() as folder:
        stop_file = Path(folder) / "server.stop"
        calls = []
        watcher = sc.StopWatcher(stop_file, lambda: calls.append(1), interval=0.02)
        watcher.start()

        time.sleep(0.1)
        assert calls == []                       # nothing happens until asked

        stop_file.write_text("stop")
        time.sleep(0.3)

        assert calls == [1]
        assert not stop_file.exists()

        stop_file.write_text("stop")             # the watcher has finished; once is enough
        time.sleep(0.1)
        assert calls == [1]

        watcher.close()


def test_a_closed_stop_watcher_does_nothing():
    with tempfile.TemporaryDirectory() as folder:
        stop_file = Path(folder) / "server.stop"
        calls = []
        watcher = sc.StopWatcher(stop_file, lambda: calls.append(1), interval=0.02)
        watcher.start()
        watcher.close()

        stop_file.write_text("stop")
        time.sleep(0.15)

        assert calls == []


# ----------------------------------------------------------------------
# status
# ----------------------------------------------------------------------

def test_status_stopped_stale_running_and_unresponsive():
    with tempfile.TemporaryDirectory() as folder:
        paths = make_paths(folder)

        assert sc.get_status(paths, ENV).kind == "stopped"
        assert sc.get_status(paths, ENV).port == 8765

        sc.write_pid_file(paths, "127.0.0.1", 8765, pid=555)

        assert sc.get_status(paths, ENV, is_alive=lambda p: False).kind == "stale"
        assert sc.get_status(paths, ENV, is_alive=lambda p: True, probe_fn=lambda h, p: True).kind == "running"
        assert sc.get_status(paths, ENV, is_alive=lambda p: True, probe_fn=lambda h, p: False).kind == "unresponsive"


def test_status_text_says_what_the_user_needs_to_know():
    paths = make_paths("/tmp/x")
    running = sc.Status("running", 321, "0.0.0.0", 8000, 1000.0)

    text = sc.format_status(running, paths, lan_ip=lambda: "192.168.1.20", now=1000.0 + 3 * 3600 + 5 * 60)

    assert "running (PID 321, up 3h 5m)" in text
    assert "http://127.0.0.1:8000" in text
    assert "http://192.168.1.20:8000" in text          # the address for other devices
    assert str(paths.log_file) in text

    local = sc.format_status(sc.Status("running", 1, "127.0.0.1", 8000, 1.0), paths, lan_ip=lambda: "192.168.1.20", now=61.0)
    assert "192.168.1.20" not in local                  # not offered when only this PC can reach it

    assert "not running" in sc.format_status(sc.Status("stopped", None, "h", 1, None), paths)
    assert "not answering" in sc.format_status(sc.Status("unresponsive", 9, "h", 1, 1.0), paths)
    assert "leftover" in sc.format_status(sc.Status("stale", 9, "h", 1, 1.0), paths)


# ----------------------------------------------------------------------
# start (with stand-ins for the operating system)
# ----------------------------------------------------------------------

def start_with(paths, *, process, probe=lambda h, p: False, busy=False, alive=lambda pid: False, clock=None, timeout=3.0, env=None):
    clock = clock or Clock()
    launched = []

    def popen(command, **options):
        launched.append((command, options))
        return process

    outcome = sc.start(
        paths,
        dict(ENV if env is None else env),
        command=["fake-server"],
        popen=popen,
        is_alive=alive,
        probe_fn=probe,
        port_busy=lambda h, p: busy,
        lan_ip=lambda: None,
        sleep=clock.sleep,
        clock=clock,
        timeout=timeout,
    )

    return outcome, launched


def test_start_waits_for_the_server_to_answer_then_reports_it():
    with tempfile.TemporaryDirectory() as folder:
        paths = make_paths(folder)
        polls = []

        def server_comes_up():
            polls.append(1)
            if len(polls) == 3:
                sc.write_pid_file(paths, "127.0.0.1", 8765, pid=777)

        outcome, launched = start_with(
            paths,
            process=FakeProcess(on_poll=server_comes_up),
            probe=lambda h, p: len(polls) >= 3,
        )

        assert outcome.code == 0
        assert "running in the background (PID 777)" in outcome.message
        assert "http://127.0.0.1:8765" in outcome.message
        assert "keeps running if you close this window" in outcome.message

        command, options = launched[0]
        assert command == ["fake-server"]
        assert options["cwd"] == str(paths.root)
        assert options["stdin"] is not None
        assert options["env"]["EXCELENCE_PORT"] == "8765"        # settings reach the child
        assert ("creationflags" in options) or options.get("start_new_session") is True   # detached


def test_start_when_already_running_changes_nothing():
    with tempfile.TemporaryDirectory() as folder:
        paths = make_paths(folder)
        sc.write_pid_file(paths, "127.0.0.1", 8765, pid=777)

        outcome, launched = start_with(paths, process=FakeProcess(), alive=lambda pid: True, probe=lambda h, p: True)

        assert outcome.code == 0 and "already running (PID 777)" in outcome.message
        assert launched == []


def test_start_refuses_when_a_process_exists_but_does_not_answer():
    with tempfile.TemporaryDirectory() as folder:
        paths = make_paths(folder)
        sc.write_pid_file(paths, "127.0.0.1", 8765, pid=777)

        outcome, launched = start_with(paths, process=FakeProcess(), alive=lambda pid: True, probe=lambda h, p: False)

        assert outcome.code == sc.EXIT_FAILED and "not answering" in outcome.message
        assert launched == []


def test_start_cleans_a_leftover_pid_file_and_starts():
    with tempfile.TemporaryDirectory() as folder:
        paths = make_paths(folder)
        sc.write_pid_file(paths, "127.0.0.1", 8765, pid=777)
        calls = []

        def server_comes_up():
            calls.append(1)
            sc.write_pid_file(paths, "127.0.0.1", 8765, pid=888)

        outcome, launched = start_with(
            paths,
            process=FakeProcess(on_poll=server_comes_up),
            alive=lambda pid: False,
            probe=lambda h, p: bool(calls),
        )

        assert outcome.code == 0 and "PID 888" in outcome.message
        assert len(launched) == 1


def test_start_says_when_the_port_belongs_to_another_program():
    with tempfile.TemporaryDirectory() as folder:
        paths = make_paths(folder)

        outcome, launched = start_with(paths, process=FakeProcess(), busy=True)

        assert outcome.code == sc.EXIT_FAILED
        assert "Port 8765 is already in use by another program" in outcome.message
        assert "EXCELENCE_PORT" in outcome.message
        assert launched == []


def test_start_shows_the_end_of_the_output_when_the_server_dies_at_once():
    with tempfile.TemporaryDirectory() as folder:
        paths = make_paths(folder)
        paths.logs_dir.mkdir()
        paths.out_file.write_text("line one\nConfiguration error: EXCELENCE_PORT must be a whole number\n", encoding="utf-8")

        outcome, _ = start_with(paths, process=FakeProcess(exit_code=2))

        assert outcome.code == sc.EXIT_FAILED
        assert "exit code 2" in outcome.message
        assert "Configuration error" in outcome.message


def test_start_gives_up_after_the_timeout_and_points_to_the_log():
    with tempfile.TemporaryDirectory() as folder:
        paths = make_paths(folder)

        outcome, _ = start_with(paths, process=FakeProcess(), timeout=2.0)

        assert outcome.code == sc.EXIT_FAILED
        assert "did not answer within 2 seconds" in outcome.message
        assert str(paths.log_file) in outcome.message


def test_start_reports_a_bad_setting_instead_of_starting():
    with tempfile.TemporaryDirectory() as folder:
        paths = make_paths(folder)

        outcome, launched = start_with(paths, process=FakeProcess(), env={"EXCELENCE_PORT": "not-a-port"})

        assert outcome.code == sc.EXIT_USAGE
        assert "Configuration error" in outcome.message and "EXCELENCE_PORT" in outcome.message
        assert launched == []


def test_start_reads_the_settings_file():
    with tempfile.TemporaryDirectory() as folder:
        paths = make_paths(folder)
        paths.env_file.write_text("EXCELENCE_PORT=9123\n", encoding="utf-8")

        outcome, launched = start_with(paths, process=FakeProcess(exit_code=1), env={})

        assert launched[0][1]["env"]["EXCELENCE_PORT"] == "9123"


def test_start_cannot_launch_a_missing_program():
    with tempfile.TemporaryDirectory() as folder:
        paths = make_paths(folder)

        def popen(command, **options):
            raise FileNotFoundError("nope")

        outcome = sc.start(
            paths, dict(ENV), command=["x"], popen=popen, is_alive=lambda p: False,
            probe_fn=lambda h, p: False, port_busy=lambda h, p: False, sleep=no_sleep,
        )

        assert outcome.code == sc.EXIT_FAILED and "Could not start the server" in outcome.message


def test_the_command_that_start_launches():
    root = Path("/app")

    assert sc.build_command(True, "/app/excelence-server.exe", root) == ["/app/excelence-server.exe", "run"]
    assert sc.build_command(False, "python", root) == ["python", str(root / "server_entry.py"), "run"]


def test_a_large_output_file_is_rotated_on_start():
    with tempfile.TemporaryDirectory() as folder:
        paths = make_paths(folder)
        paths.logs_dir.mkdir()
        paths.out_file.write_bytes(b"x" * (sc.MAX_OUT_BYTES + 1))

        start_with(paths, process=FakeProcess(exit_code=1))

        assert paths.out_file.with_suffix(".old").exists()
        assert paths.out_file.stat().st_size < 1000


# ----------------------------------------------------------------------
# stop
# ----------------------------------------------------------------------

def test_stop_when_nothing_runs_is_not_an_error():
    with tempfile.TemporaryDirectory() as folder:
        outcome = sc.stop(make_paths(folder))

        assert outcome.code == 0 and "not running" in outcome.message


def test_stop_cleans_a_leftover_pid_file():
    with tempfile.TemporaryDirectory() as folder:
        paths = make_paths(folder)
        sc.write_pid_file(paths, "h", 1, pid=4242)

        outcome = sc.stop(paths, is_alive=lambda pid: False)

        assert outcome.code == 0 and "leftover" in outcome.message
        assert not paths.pid_file.exists()


def test_stop_asks_politely_and_waits_for_the_server_to_exit():
    with tempfile.TemporaryDirectory() as folder:
        paths = make_paths(folder)
        sc.write_pid_file(paths, "h", 1, pid=4242)
        clock = Clock()
        killed = []

        # The "server" exits once it sees the stop file (as the real one does).
        def alive(pid):
            if paths.stop_file.exists() and clock.now >= 1.0:
                return False
            return True

        outcome = sc.stop(paths, is_alive=alive, kill=killed.append, sleep=clock.sleep, clock=clock, timeout=5.0)

        assert outcome.code == 0
        assert "stopped" in outcome.message and "saved" in outcome.message
        assert killed == []                                    # no force needed
        assert not paths.stop_file.exists() and not paths.pid_file.exists()


def test_stop_ends_the_process_by_force_only_after_the_timeout_and_says_so():
    with tempfile.TemporaryDirectory() as folder:
        paths = make_paths(folder)
        sc.write_pid_file(paths, "h", 1, pid=4242)
        clock = Clock()
        killed = []

        def alive(pid):
            return not killed          # dies only once killed

        outcome = sc.stop(paths, is_alive=alive, kill=killed.append, sleep=clock.sleep, clock=clock, timeout=2.0)

        assert killed == [4242]
        assert outcome.code == 0
        assert "by force" in outcome.message and "may be lost" in outcome.message
        assert not paths.pid_file.exists() and not paths.stop_file.exists()


def test_stop_reports_a_process_that_will_not_die():
    with tempfile.TemporaryDirectory() as folder:
        paths = make_paths(folder)
        sc.write_pid_file(paths, "h", 1, pid=4242)
        clock = Clock()

        outcome = sc.stop(paths, is_alive=lambda pid: True, kill=lambda pid: None, sleep=clock.sleep, clock=clock, timeout=1.0)

        assert outcome.code == sc.EXIT_FAILED
        assert "Task Manager" in outcome.message


def test_restart_stops_then_starts_and_gives_up_if_stopping_fails():
    with tempfile.TemporaryDirectory() as folder:
        paths = make_paths(folder)
        order = []

        original_stop, original_start = sc.stop, sc.start
        try:
            sc.stop = lambda p, **o: (order.append("stop"), sc.Outcome(0, "stopped."))[1]
            sc.start = lambda p, e=None, **o: (order.append("start"), sc.Outcome(0, "started."))[1]

            outcome = sc.restart(paths, dict(ENV))
            assert order == ["stop", "start"]
            assert outcome.code == 0 and "stopped." in outcome.message and "started." in outcome.message

            order.clear()
            sc.stop = lambda p, **o: (order.append("stop"), sc.Outcome(3, "stuck"))[1]
            outcome = sc.restart(paths, dict(ENV))

            assert order == ["stop"] and outcome.code == 3
        finally:
            sc.stop, sc.start = original_stop, original_start


# ----------------------------------------------------------------------
# Ports, addresses, log
# ----------------------------------------------------------------------

def test_port_in_use_sees_a_listening_socket_and_a_free_port():
    with socket.socket() as listener:
        listener.bind(("127.0.0.1", 0))
        listener.listen()
        port = listener.getsockname()[1]

        assert sc.port_in_use("127.0.0.1", port) is True

    assert sc.port_in_use("127.0.0.1", port) is False


def test_probe_only_trusts_an_excelence_server():
    import http.server
    import threading

    class Handler(http.server.BaseHTTPRequestHandler):
        body = b'{"application": "Excelence", "status": "running"}'
        status = 200

        def do_GET(self):
            self.send_response(Handler.status)
            self.end_headers()
            self.wfile.write(Handler.body)

        def log_message(self, *args):
            pass

    server = http.server.HTTPServer(("127.0.0.1", 0), Handler)
    port = server.server_address[1]
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()

    try:
        assert sc.probe("127.0.0.1", port) is True

        Handler.body = b"<html>some other program</html>"
        assert sc.probe("127.0.0.1", port) is False

        Handler.status = 401                  # token required: still our server answering
        assert sc.probe("127.0.0.1", port) is True
    finally:
        server.shutdown()
        server.server_close()

    assert sc.probe("127.0.0.1", port) is False        # nothing there any more


def test_tail_lines_reads_the_end_of_a_file():
    with tempfile.TemporaryDirectory() as folder:
        path = Path(folder) / "log.txt"

        assert sc.tail_lines(path, 5) == []             # missing file

        path.write_text("\n".join(f"line {number}" for number in range(1, 5001)) + "\n", encoding="utf-8")

        assert sc.tail_lines(path, 3) == ["line 4998", "line 4999", "line 5000"]
        assert len(sc.tail_lines(path, 100000)) == 5000
        assert sc.tail_lines(path, 0) == []

        path.write_text("only\n", encoding="utf-8")
        assert sc.tail_lines(path, 10) == ["only"]


# ----------------------------------------------------------------------
# Start at log-on (the registry is replaced by a stand-in)
# ----------------------------------------------------------------------

class FakeKey:
    def __init__(self, store):
        self.store = store

    def __enter__(self):
        return self.store

    def __exit__(self, *args):
        return False


class FakeWinreg:
    HKEY_CURRENT_USER = "HKCU"
    KEY_SET_VALUE = 2
    KEY_READ = 1
    REG_SZ = 1

    def __init__(self):
        self.values = {}
        self.opened = []

    def OpenKey(self, root, path, reserved, access):
        self.opened.append((root, path))
        return FakeKey(self.values)

    def SetValueEx(self, key, name, reserved, kind, value):
        key[name] = value

    def QueryValueEx(self, key, name):
        if name not in key:
            raise FileNotFoundError(name)
        return key[name], self.REG_SZ

    def DeleteValue(self, key, name):
        if name not in key:
            raise FileNotFoundError(name)
        del key[name]


def test_autostart_on_status_off_round_trip():
    registry = FakeWinreg()
    paths = make_paths("C:/Excelence")

    assert sc.autostart_status(paths, registry).code == sc.EXIT_NOT_RUNNING

    on = sc.autostart_enable(paths, registry, command='"C:\\Excelence\\excelence-server.exe" start')
    assert on.code == 0 and "log in" in on.message
    assert registry.values[sc.AUTOSTART_NAME] == '"C:\\Excelence\\excelence-server.exe" start'
    assert registry.opened[0] == ("HKCU", sc.RUN_KEY)

    status = sc.autostart_status(paths, registry)
    assert status.code == 0 and "is on" in status.message

    assert sc.autostart_disable(paths, registry).code == 0
    assert sc.AUTOSTART_NAME not in registry.values
    assert "already off" in sc.autostart_disable(paths, registry).message


def test_autostart_command_quotes_paths_with_spaces():
    paths = sc.ServicePaths(root=Path("C:/Program Files/Excelence"), logs_dir=Path("C:/Program Files/Excelence/logs"))

    packaged = sc.autostart_command(paths, frozen=True, executable="C:/Program Files/Excelence/excelence-server.exe")
    assert packaged == '"C:/Program Files/Excelence/excelence-server.exe" start'

    development = sc.autostart_command(paths, frozen=False, executable="C:/Python/python.exe")
    assert development.startswith('"C:/Python/python.exe" "')
    assert development.endswith('server_entry.py" start')


def test_autostart_is_only_offered_on_windows():
    if os.name == "nt":
        return

    paths = make_paths("/tmp/x")

    for outcome in (sc.autostart_enable(paths), sc.autostart_disable(paths), sc.autostart_status(paths)):
        assert outcome.code == sc.EXIT_USAGE and "only available on Windows" in outcome.message


def test_autostart_reports_a_registry_error():
    class Broken(FakeWinreg):
        def OpenKey(self, *args):
            raise PermissionError("denied")

    outcome = sc.autostart_enable(make_paths("/tmp/x"), Broken(), command="x")

    assert outcome.code == sc.EXIT_FAILED and "denied" in outcome.message


# ----------------------------------------------------------------------
# The command line
# ----------------------------------------------------------------------

def run_cli(arguments, paths, foreground=lambda: 99):
    with contextlib.redirect_stdout(io.StringIO()), contextlib.redirect_stderr(io.StringIO()):
        return service_cli.main(arguments, paths=paths, foreground=foreground)


def test_cli_no_command_and_run_run_in_the_foreground():
    with tempfile.TemporaryDirectory() as folder:
        paths = make_paths(folder)

        assert run_cli([], paths) == 99
        assert run_cli(["run"], paths) == 99
        assert run_cli(["RUN"], paths) == 99


def test_cli_status_exit_code_tells_whether_it_runs():
    with tempfile.TemporaryDirectory() as folder:
        paths = make_paths(folder)
        original = os.environ.copy()
        os.environ["EXCELENCE_PORT"] = "8765"

        try:
            assert run_cli(["status"], paths) == sc.EXIT_NOT_RUNNING

            os.environ["EXCELENCE_PORT"] = "not-a-port"
            assert run_cli(["status"], paths) == sc.EXIT_USAGE
        finally:
            os.environ.clear()
            os.environ.update(original)


def test_cli_unknown_commands_and_bad_arguments_show_usage():
    with tempfile.TemporaryDirectory() as folder:
        paths = make_paths(folder)

        assert run_cli(["explode"], paths) == sc.EXIT_USAGE
        assert run_cli(["autostart"], paths) == sc.EXIT_USAGE
        assert run_cli(["autostart", "sideways"], paths) == sc.EXIT_USAGE
        assert run_cli(["logs", "--lines"], paths) == sc.EXIT_USAGE
        assert run_cli(["logs", "--lines", "abc"], paths) == sc.EXIT_USAGE
        assert run_cli(["help"], paths) == 0


def test_cli_logs_prints_the_end_of_the_log():
    with tempfile.TemporaryDirectory() as folder:
        paths = make_paths(folder)
        paths.logs_dir.mkdir()
        paths.log_file.write_text("\n".join(f"entry {n}" for n in range(1, 11)) + "\n", encoding="utf-8")

        with contextlib.redirect_stdout(io.StringIO()) as captured:
            assert service_cli.main(["logs", "--lines", "2"], paths=paths) == 0

        assert captured.getvalue().strip().splitlines() == ["entry 9", "entry 10"]

        paths.log_file.unlink()

        with contextlib.redirect_stdout(io.StringIO()) as captured:
            assert service_cli.main(["logs"], paths=paths) == 0

        assert "No log yet" in captured.getvalue()


def test_cli_config_creates_the_settings_file():
    with tempfile.TemporaryDirectory() as folder:
        paths = make_paths(folder)

        assert run_cli(["config"], paths) == 0
        assert paths.env_file.exists()


# ----------------------------------------------------------------------
# A real detached process: start -> status -> start again -> stop
# ----------------------------------------------------------------------

STAND_IN = """
import http.server, json, os, sys, threading
from pathlib import Path
sys.path.insert(0, ROOT)
from backend import service_control as sc

paths = sc.ServicePaths(root=Path.cwd(), logs_dir=Path.cwd() / "logs")
problem = sc.claim_pid_file(paths, "127.0.0.1", PORT)

if problem:
    print(problem)
    raise SystemExit(3)

class Handler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        self.send_response(200)
        self.end_headers()
        self.wfile.write(json.dumps({"application": "Excelence", "status": "running"}).encode())
    def log_message(self, *args):
        pass

server = http.server.HTTPServer(("127.0.0.1", PORT), Handler)

if WATCH:
    watcher = sc.StopWatcher(paths.stop_file, lambda: threading.Thread(target=server.shutdown).start(), interval=0.1)
    watcher.start()

print("stand-in server up", flush=True)
server.serve_forever()
sc.remove_pid_file(paths, only_pid=os.getpid())
"""


def stand_in_server(port, watch_stop_file):
    return (
        STAND_IN.replace("ROOT", repr(PROJECT_ROOT))
        .replace("PORT", str(port))
        .replace("WATCH", repr(watch_stop_file))
    )


def real_start(paths, port, watch_stop_file=True):
    return sc.start(
        paths,
        {"EXCELENCE_HOST": "127.0.0.1", "EXCELENCE_PORT": str(port)},
        command=[sys.executable, "-c", stand_in_server(port, watch_stop_file)],
        lan_ip=lambda: None,
        timeout=15.0,
    )


def test_real_process_start_status_second_start_and_graceful_stop():
    with tempfile.TemporaryDirectory() as folder:
        paths = make_paths(folder)
        port = free_port()
        env = {"EXCELENCE_HOST": "127.0.0.1", "EXCELENCE_PORT": str(port)}

        started = real_start(paths, port)

        try:
            assert started.code == 0, started.message
            assert "running in the background" in started.message

            info = sc.read_pid_file(paths)
            assert info is not None and sc.is_process_alive(info.pid)

            state = sc.get_status(paths, env)
            assert state.kind == "running" and state.pid == info.pid

            again = real_start(paths, port)
            assert again.code == 0 and "already running" in again.message
            assert sc.read_pid_file(paths).pid == info.pid          # no second server

            stopped = sc.stop(paths, timeout=10.0)
            assert stopped.code == 0, stopped.message
            assert "by force" not in stopped.message                # shut down by itself

            assert not sc.is_process_alive(info.pid)
            assert not paths.pid_file.exists() and not paths.stop_file.exists()
            assert sc.get_status(paths, env).kind == "stopped"
            assert sc.probe("127.0.0.1", port) is False
        finally:
            leftover = sc.read_pid_file(paths)
            if leftover is not None:
                sc.force_kill(leftover.pid)


def test_real_process_that_ignores_the_stop_request_is_ended_by_force():
    with tempfile.TemporaryDirectory() as folder:
        paths = make_paths(folder)
        port = free_port()

        started = real_start(paths, port, watch_stop_file=False)

        try:
            assert started.code == 0, started.message
            pid = sc.read_pid_file(paths).pid

            stopped = sc.stop(paths, timeout=1.0)

            assert stopped.code == 0, stopped.message
            assert "by force" in stopped.message
            assert not sc.is_process_alive(pid)
            assert not paths.pid_file.exists()
        finally:
            leftover = sc.read_pid_file(paths)
            if leftover is not None:
                sc.force_kill(leftover.pid)


def test_real_process_a_server_that_cannot_start_reports_why():
    with tempfile.TemporaryDirectory() as folder:
        paths = make_paths(folder)
        port = free_port()

        outcome = sc.start(
            paths,
            {"EXCELENCE_HOST": "127.0.0.1", "EXCELENCE_PORT": str(port)},
            command=[sys.executable, "-c", "print('could not read the settings'); raise SystemExit(2)"],
            lan_ip=lambda: None,
            timeout=10.0,
        )

        assert outcome.code == sc.EXIT_FAILED
        assert "exit code 2" in outcome.message
        assert "could not read the settings" in outcome.message
