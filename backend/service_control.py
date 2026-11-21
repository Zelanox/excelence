"""Run the Excelence server in the background and control it.

The server normally runs in a terminal window and stops when that window is
closed. This module lets it run on its own instead:

    excelence-server start      start it in the background and return
    excelence-server stop       stop it (unsaved work is saved first)
    excelence-server restart
    excelence-server status
    excelence-server logs
    excelence-server autostart on|off|status    start at Windows log-on
    excelence-server config     create the settings file

Only the standard library is used, so it works inside the packaged exe.

How it works
------------
* ``start`` launches the server as a detached process (no terminal, output to
  ``logs/server.out``) and waits until it answers.
* The running server writes ``run/server.pid`` itself and removes it when it
  exits. A second server refuses to start while one is running.
* ``stop`` asks the server to stop by creating ``run/server.stop``; the
  server notices, shuts down properly (saving every open document) and exits.
  Only if it does not exit in time is the process ended by force.
* Settings that must survive closing the terminal live in ``excelence.env``
  next to the program (``KEY=value`` lines); they never override a variable
  that is already set.
"""

from __future__ import annotations

import json
import os
import re
import signal
import socket
import subprocess
import sys
import threading
import time
import urllib.error
import urllib.request
from collections.abc import Callable, Mapping, MutableMapping
from dataclasses import dataclass
from pathlib import Path

EXIT_OK = 0
EXIT_NOT_RUNNING = 1
EXIT_USAGE = 2
EXIT_FAILED = 3

START_TIMEOUT = 20.0
STOP_TIMEOUT = 20.0
MAX_OUT_BYTES = 5 * 1024 * 1024

AUTOSTART_NAME = "ExcelenceServer"
RUN_KEY = r"Software\Microsoft\Windows\CurrentVersion\Run"

CONFIG_TEMPLATE = """\
# Excelence server settings.
# Lines starting with # are ignored. Remove the # to use a line.
# Restart the server after changing this file:  excelence-server restart

# Accept connections from other devices on the network (phones, other PCs).
#EXCELENCE_HOST=0.0.0.0

#EXCELENCE_PORT=8000

# Required on a shared network. Use at least 12 characters, and give the same
# value to the app when it is built (API_TOKEN).
#EXCELENCE_ACCESS_TOKEN=choose-a-long-secret-here

# Where the workbooks are kept.
#EXCELENCE_DOCUMENTS_DIR=D:\\Excelence\\documents
"""


@dataclass(frozen=True)
class Outcome:
    """What a command did: an exit code and a message for the user."""

    code: int
    message: str


@dataclass(frozen=True)
class ServicePaths:
    root: Path
    logs_dir: Path

    @property
    def env_file(self) -> Path:
        return self.root / "excelence.env"

    @property
    def run_dir(self) -> Path:
        return self.root / "run"

    @property
    def pid_file(self) -> Path:
        return self.run_dir / "server.pid"

    @property
    def stop_file(self) -> Path:
        return self.run_dir / "server.stop"

    @property
    def out_file(self) -> Path:
        return self.logs_dir / "server.out"

    @property
    def log_file(self) -> Path:
        return self.logs_dir / "backend.log"


def default_paths() -> ServicePaths:
    """Next to the exe when packaged, otherwise the project folder."""
    if getattr(sys, "frozen", False):
        root = Path(sys.executable).resolve().parent
        return ServicePaths(root=root, logs_dir=root / "logs")

    root = Path(__file__).resolve().parent.parent
    return ServicePaths(root=root, logs_dir=root / "backend" / "logs")


# ----------------------------------------------------------------------
# The settings file
# ----------------------------------------------------------------------

_KEY = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*$")


def parse_env_text(text: str) -> tuple[dict[str, str], list[int]]:
    """Parse ``KEY=value`` lines. Returns the values and the numbers of lines
    that could not be understood (blank lines and # comments are fine)."""
    values: dict[str, str] = {}
    bad: list[int] = []

    for number, raw in enumerate(text.splitlines(), start=1):
        line = raw.strip()

        if not line or line.startswith("#"):
            continue

        if line.lower().startswith("export "):
            line = line[7:].strip()

        key, separator, value = line.partition("=")
        key = key.strip()
        value = value.strip()

        if not separator or not _KEY.match(key):
            bad.append(number)
            continue

        if len(value) >= 2 and value[0] == value[-1] and value[0] in "\"'":
            value = value[1:-1]

        values[key] = value

    return values, bad


def load_env_file(path: Path, environ: MutableMapping[str, str] | None = None) -> dict[str, str]:
    """Apply ``path`` to ``environ`` without overriding anything already set.

    Returns the values that were applied. A missing or unreadable file is not
    an error (it is optional).
    """
    target = os.environ if environ is None else environ

    try:
        text = Path(path).read_text(encoding="utf-8-sig")
    except OSError:
        return {}

    values, _ = parse_env_text(text)
    applied: dict[str, str] = {}

    for key, value in values.items():
        if key not in target:
            target[key] = value
            applied[key] = value

    return applied


def init_config(paths: ServicePaths) -> Outcome:
    """Create the settings file with every option commented out."""
    if paths.env_file.exists():
        return Outcome(EXIT_OK, f"The settings file already exists: {paths.env_file}")

    try:
        paths.env_file.write_text(CONFIG_TEMPLATE, encoding="utf-8")
    except OSError as error:
        return Outcome(EXIT_FAILED, f"Could not create {paths.env_file}: {error}")

    return Outcome(EXIT_OK, f"Created {paths.env_file}\nEdit it, then run: excelence-server restart")


# ----------------------------------------------------------------------
# Process helpers
# ----------------------------------------------------------------------

def is_process_alive(pid: int) -> bool:
    if pid <= 0:
        return False

    if os.name == "nt":
        import ctypes

        kernel32 = ctypes.windll.kernel32  # type: ignore[attr-defined]
        handle = kernel32.OpenProcess(0x1000, False, pid)  # QUERY_LIMITED_INFORMATION

        if not handle:
            return False

        try:
            code = ctypes.c_ulong()

            if not kernel32.GetExitCodeProcess(handle, ctypes.byref(code)):
                return False

            return code.value == 259  # STILL_ACTIVE
        finally:
            kernel32.CloseHandle(handle)

    try:
        # A finished child of this process stays a zombie until it is
        # collected; collect it so it does not look alive.
        done, _ = os.waitpid(pid, os.WNOHANG)

        if done == pid:
            return False
    except ChildProcessError:
        pass
    except OSError:
        pass

    try:
        os.kill(pid, 0)
    except ProcessLookupError:
        return False
    except PermissionError:
        return True
    except OSError:
        return False

    return True


def force_kill(pid: int) -> None:
    """End a process immediately (last resort)."""
    if os.name == "nt":
        subprocess.run(
            ["taskkill", "/PID", str(pid), "/T", "/F"],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            check=False,
        )
        return

    try:
        os.kill(pid, signal.SIGKILL)
    except OSError:
        pass


def _connect_host(host: str) -> str:
    if host in ("", "0.0.0.0"):
        return "127.0.0.1"

    if host == "::":
        return "[::1]"

    return f"[{host}]" if ":" in host else host


def probe(host: str, port: int, timeout: float = 1.0) -> bool:
    """True if an Excelence server answers on this address.

    A reply that says "unauthorized" counts: the server is there, it just
    wants the access token.
    """
    url = f"http://{_connect_host(host)}:{port}/"

    try:
        with urllib.request.urlopen(url, timeout=timeout) as response:
            return "Excelence" in response.read(2000).decode("utf-8", "replace")
    except urllib.error.HTTPError as error:
        return error.code in (401, 403)
    except (urllib.error.URLError, OSError, ValueError):
        return False


def port_in_use(host: str, port: int) -> bool:
    """True if something is already listening on host:port."""
    bind_host = host if host not in ("",) else "0.0.0.0"
    family = socket.AF_INET6 if ":" in bind_host else socket.AF_INET

    with socket.socket(family, socket.SOCK_STREAM) as candidate:
        if os.name != "nt":
            # Like the server itself: a socket in TIME_WAIT is not "in use".
            candidate.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)

        try:
            candidate.bind((bind_host, port))
        except OSError:
            return True

    return False


def guess_lan_ip() -> str | None:
    """This machine's address on the local network (best guess, no traffic)."""
    try:
        with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as probe_socket:
            probe_socket.connect(("10.255.255.255", 1))
            address = probe_socket.getsockname()[0]
    except OSError:
        return None

    return None if address.startswith("127.") else address


# ----------------------------------------------------------------------
# The PID file (written by the running server)
# ----------------------------------------------------------------------

@dataclass(frozen=True)
class PidInfo:
    pid: int
    host: str
    port: int
    started: float


def write_pid_file(paths: ServicePaths, host: str, port: int, pid: int | None = None) -> None:
    paths.run_dir.mkdir(parents=True, exist_ok=True)
    data = {"pid": os.getpid() if pid is None else pid, "host": host, "port": port, "started": time.time()}
    paths.pid_file.write_text(json.dumps(data), encoding="utf-8")


def read_pid_file(paths: ServicePaths) -> PidInfo | None:
    """The PID file's content, or None if it is missing or damaged."""
    try:
        data = json.loads(paths.pid_file.read_text(encoding="utf-8"))
        return PidInfo(
            pid=int(data["pid"]),
            host=str(data["host"]),
            port=int(data["port"]),
            started=float(data.get("started", 0.0)),
        )
    except (OSError, ValueError, KeyError, TypeError):
        return None


def remove_pid_file(paths: ServicePaths, only_pid: int | None = None) -> None:
    """Delete the PID file (only if it names ``only_pid``, when given)."""
    if only_pid is not None:
        info = read_pid_file(paths)

        if info is not None and info.pid != only_pid:
            return

    try:
        paths.pid_file.unlink()
    except OSError:
        pass


def claim_pid_file(
    paths: ServicePaths,
    host: str,
    port: int,
    *,
    is_alive: Callable[[int], bool] = is_process_alive,
    probe_fn: Callable[[str, int], bool] = probe,
) -> str | None:
    """Called by the server as it starts. Returns a message if another server
    is already running (and does not write the file), otherwise writes it."""
    info = read_pid_file(paths)

    if info is not None and info.pid != os.getpid() and is_alive(info.pid) and probe_fn(info.host, info.port):
        return (
            f"The Excelence server is already running (PID {info.pid}) at "
            f"http://{_connect_host(info.host)}:{info.port}. "
            "Stop it first with: excelence-server stop"
        )

    write_pid_file(paths, host, port)
    return None


class StopWatcher:
    """Watches for the stop file and then calls ``on_stop`` once.

    Runs inside the server. It is how ``stop`` asks the server to shut down
    properly on every platform (Windows has no gentle signal for a process
    without a console).
    """

    def __init__(self, stop_file: Path, on_stop: Callable[[], None], interval: float = 0.5):
        self._stop_file = Path(stop_file)
        self._on_stop = on_stop
        self._interval = interval
        self._closed = threading.Event()
        self._thread = threading.Thread(target=self._run, name="stop-watcher", daemon=True)

    def start(self) -> None:
        self._thread.start()

    def close(self) -> None:
        self._closed.set()

    def _run(self) -> None:
        while not self._closed.wait(self._interval):
            if self._stop_file.exists():
                try:
                    self._stop_file.unlink()
                except OSError:
                    pass

                self._on_stop()
                return


# ----------------------------------------------------------------------
# status
# ----------------------------------------------------------------------

@dataclass(frozen=True)
class Status:
    kind: str  # "running", "stopped", "stale" or "unresponsive"
    pid: int | None
    host: str
    port: int
    started: float | None


def _settings(environ: Mapping[str, str]):
    from backend.utils.settings import load_settings

    return load_settings(environ)


def get_status(
    paths: ServicePaths,
    environ: Mapping[str, str] | None = None,
    *,
    is_alive: Callable[[int], bool] = is_process_alive,
    probe_fn: Callable[[str, int], bool] = probe,
) -> Status:
    env = os.environ if environ is None else environ
    info = read_pid_file(paths)

    if info is None:
        settings = _settings(env)
        return Status("stopped", None, settings.host, settings.port, None)

    if not is_alive(info.pid):
        return Status("stale", info.pid, info.host, info.port, info.started)

    if probe_fn(info.host, info.port):
        return Status("running", info.pid, info.host, info.port, info.started)

    return Status("unresponsive", info.pid, info.host, info.port, info.started)


def _duration(seconds: float) -> str:
    seconds = max(0, int(seconds))
    days, rest = divmod(seconds, 86400)
    hours, rest = divmod(rest, 3600)
    minutes = rest // 60

    if days:
        return f"{days}d {hours}h"

    if hours:
        return f"{hours}h {minutes}m"

    return f"{minutes}m"


def _addresses(host: str, port: int, lan_ip: Callable[[], str | None]) -> str:
    text = f"http://{_connect_host(host)}:{port}"

    if host in ("0.0.0.0", "::"):
        address = lan_ip()

        if address:
            text += f"\nOther devices on the network: http://{address}:{port}"

    return text


def format_status(
    status: Status,
    paths: ServicePaths,
    *,
    lan_ip: Callable[[], str | None] = guess_lan_ip,
    now: float | None = None,
) -> str:
    current = time.time() if now is None else now

    if status.kind == "running":
        up = _duration(current - status.started) if status.started else "unknown"
        return (
            f"The Excelence server is running (PID {status.pid}, up {up}).\n"
            f"{_addresses(status.host, status.port, lan_ip)}\n"
            f"Log: {paths.log_file}"
        )

    if status.kind == "unresponsive":
        return (
            f"The Excelence server process exists (PID {status.pid}) but is not answering "
            f"on port {status.port}. It may still be starting. If it stays like this, run: "
            "excelence-server stop"
        )

    if status.kind == "stale":
        return "The Excelence server is not running (a leftover PID file from an earlier run will be cleaned up)."

    return "The Excelence server is not running."


# ----------------------------------------------------------------------
# start / stop / restart
# ----------------------------------------------------------------------

def build_command(frozen: bool, executable: str, root: Path) -> list[str]:
    """The command that runs the server in the foreground (what start launches)."""
    if frozen:
        return [executable, "run"]

    return [executable, str(root / "server_entry.py"), "run"]


def spawn_flags() -> dict:
    """Options that detach the child from this terminal."""
    if os.name == "nt":
        detached = 0x00000008  # DETACHED_PROCESS
        new_group = 0x00000200  # CREATE_NEW_PROCESS_GROUP
        return {"creationflags": detached | new_group}

    return {"start_new_session": True}


def tail_lines(path: Path, count: int) -> list[str]:
    """The last ``count`` lines of a text file (without reading all of it)."""
    try:
        with open(path, "rb") as handle:
            handle.seek(0, os.SEEK_END)
            end = handle.tell()
            block = 8192
            data = b""
            position = end

            while position > 0 and data.count(b"\n") <= count:
                step = min(block, position)
                position -= step
                handle.seek(position)
                data = handle.read(step) + data
    except OSError:
        return []

    lines = data.decode("utf-8", "replace").splitlines()
    return lines[-count:] if count > 0 else []


def _rotate_out_file(paths: ServicePaths) -> None:
    try:
        if paths.out_file.exists() and paths.out_file.stat().st_size > MAX_OUT_BYTES:
            old = paths.out_file.with_suffix(".old")
            old.unlink(missing_ok=True)
            paths.out_file.rename(old)
    except OSError:
        pass


def start(
    paths: ServicePaths,
    environ: MutableMapping[str, str] | None = None,
    *,
    command: list[str] | None = None,
    popen: Callable = subprocess.Popen,
    is_alive: Callable[[int], bool] = is_process_alive,
    probe_fn: Callable[[str, int], bool] = probe,
    port_busy: Callable[[str, int], bool] = port_in_use,
    lan_ip: Callable[[], str | None] = guess_lan_ip,
    sleep: Callable[[float], None] = time.sleep,
    clock: Callable[[], float] = time.monotonic,
    timeout: float = START_TIMEOUT,
) -> Outcome:
    env = os.environ if environ is None else environ
    load_env_file(paths.env_file, env)

    try:
        settings = _settings(env)
    except ValueError as error:
        return Outcome(EXIT_USAGE, f"Configuration error: {error}")

    state = get_status(paths, env, is_alive=is_alive, probe_fn=probe_fn)

    if state.kind == "running":
        return Outcome(
            EXIT_OK,
            f"The Excelence server is already running (PID {state.pid}).\n"
            f"{_addresses(state.host, state.port, lan_ip)}",
        )

    if state.kind == "unresponsive":
        return Outcome(
            EXIT_FAILED,
            f"A server process (PID {state.pid}) exists but is not answering. "
            "If it is not just starting, run: excelence-server stop",
        )

    if state.kind == "stale":
        remove_pid_file(paths)

    if port_busy(settings.host, settings.port):
        return Outcome(
            EXIT_FAILED,
            f"Port {settings.port} is already in use by another program. Choose another port "
            f"(EXCELENCE_PORT in {paths.env_file}) or close the program that uses it.",
        )

    try:
        paths.run_dir.mkdir(parents=True, exist_ok=True)
        paths.logs_dir.mkdir(parents=True, exist_ok=True)
        paths.stop_file.unlink(missing_ok=True)
        _rotate_out_file(paths)
        out = open(paths.out_file, "ab")
    except OSError as error:
        return Outcome(EXIT_FAILED, f"Could not prepare the server's folders: {error}")

    cmd = command or build_command(bool(getattr(sys, "frozen", False)), sys.executable, paths.root)
    child_env = {**os.environ, **env}

    try:
        process = popen(
            cmd,
            cwd=str(paths.root),
            stdin=subprocess.DEVNULL,
            stdout=out,
            stderr=subprocess.STDOUT,
            env=child_env,
            close_fds=True,
            **spawn_flags(),
        )
    except OSError as error:
        return Outcome(EXIT_FAILED, f"Could not start the server: {error}")
    finally:
        out.close()

    deadline = clock() + timeout

    while clock() < deadline:
        code = process.poll()

        if code is not None:
            lines = tail_lines(paths.out_file, 15)
            detail = ("\n" + "\n".join(lines)) if lines else ""
            return Outcome(EXIT_FAILED, f"The server stopped right after starting (exit code {code}).{detail}")

        info = read_pid_file(paths)

        if info is not None and probe_fn(settings.host, settings.port):
            return Outcome(
                EXIT_OK,
                f"The Excelence server is running in the background (PID {info.pid}).\n"
                f"{_addresses(settings.host, settings.port, lan_ip)}\n"
                f"Log: {paths.log_file}\n"
                "It keeps running if you close this window. Stop it with: excelence-server stop",
            )

        sleep(0.25)

    return Outcome(
        EXIT_FAILED,
        f"The server did not answer within {int(timeout)} seconds. It may still be starting: run "
        f"'excelence-server status' in a moment, or read {paths.log_file}",
    )


def stop(
    paths: ServicePaths,
    *,
    is_alive: Callable[[int], bool] = is_process_alive,
    kill: Callable[[int], None] = force_kill,
    sleep: Callable[[float], None] = time.sleep,
    clock: Callable[[], float] = time.monotonic,
    timeout: float = STOP_TIMEOUT,
) -> Outcome:
    info = read_pid_file(paths)

    if info is None:
        return Outcome(EXIT_OK, "The Excelence server is not running.")

    if not is_alive(info.pid):
        remove_pid_file(paths)
        paths.stop_file.unlink(missing_ok=True)
        return Outcome(EXIT_OK, "The Excelence server was not running (removed a leftover PID file).")

    try:
        paths.run_dir.mkdir(parents=True, exist_ok=True)
        paths.stop_file.write_text("stop", encoding="utf-8")
    except OSError as error:
        return Outcome(EXIT_FAILED, f"Could not ask the server to stop: {error}")

    def wait_until_gone(seconds: float) -> bool:
        deadline = clock() + seconds

        while clock() < deadline:
            if not is_alive(info.pid):
                return True

            sleep(0.2)

        return not is_alive(info.pid)

    if wait_until_gone(timeout):
        paths.stop_file.unlink(missing_ok=True)
        remove_pid_file(paths)
        return Outcome(EXIT_OK, "The Excelence server stopped. Open documents were saved first.")

    kill(info.pid)
    gone = wait_until_gone(5.0)
    paths.stop_file.unlink(missing_ok=True)

    if gone:
        remove_pid_file(paths)
        return Outcome(
            EXIT_OK,
            f"The server did not stop in {int(timeout)} seconds and was ended by force. "
            "Changes made since the last save may be lost.",
        )

    return Outcome(EXIT_FAILED, f"Could not stop the server (PID {info.pid}). End it in Task Manager.")


def restart(paths: ServicePaths, environ: MutableMapping[str, str] | None = None, **options) -> Outcome:
    stopped = stop(paths)

    if stopped.code != EXIT_OK:
        return stopped

    started = start(paths, environ, **options)
    return Outcome(started.code, f"{stopped.message}\n{started.message}")


# ----------------------------------------------------------------------
# Start at Windows log-on
# ----------------------------------------------------------------------

def autostart_command(paths: ServicePaths, frozen: bool | None = None, executable: str | None = None) -> str:
    is_frozen = bool(getattr(sys, "frozen", False)) if frozen is None else frozen
    exe = sys.executable if executable is None else executable

    if is_frozen:
        return f'"{exe}" start'

    return f'"{exe}" "{paths.root / "server_entry.py"}" start'


def _registry(winreg_module):
    if winreg_module is not None:
        return winreg_module

    if os.name != "nt":
        return None

    import winreg

    return winreg


_NOT_WINDOWS = "Starting at log-on is only available on Windows."


def autostart_enable(paths: ServicePaths, winreg_module=None, command: str | None = None) -> Outcome:
    registry = _registry(winreg_module)

    if registry is None:
        return Outcome(EXIT_USAGE, _NOT_WINDOWS)

    value = command or autostart_command(paths)

    try:
        with registry.OpenKey(registry.HKEY_CURRENT_USER, RUN_KEY, 0, registry.KEY_SET_VALUE) as key:
            registry.SetValueEx(key, AUTOSTART_NAME, 0, registry.REG_SZ, value)
    except OSError as error:
        return Outcome(EXIT_FAILED, f"Could not turn on starting at log-on: {error}")

    return Outcome(
        EXIT_OK,
        "The server will start in the background when you log in to Windows.\n"
        f"Settings are read from {paths.env_file}.",
    )


def autostart_disable(paths: ServicePaths, winreg_module=None) -> Outcome:
    registry = _registry(winreg_module)

    if registry is None:
        return Outcome(EXIT_USAGE, _NOT_WINDOWS)

    try:
        with registry.OpenKey(registry.HKEY_CURRENT_USER, RUN_KEY, 0, registry.KEY_SET_VALUE) as key:
            registry.DeleteValue(key, AUTOSTART_NAME)
    except FileNotFoundError:
        return Outcome(EXIT_OK, "Starting at log-on was already off.")
    except OSError as error:
        return Outcome(EXIT_FAILED, f"Could not turn off starting at log-on: {error}")

    return Outcome(EXIT_OK, "The server will no longer start when you log in.")


def autostart_status(paths: ServicePaths, winreg_module=None) -> Outcome:
    registry = _registry(winreg_module)

    if registry is None:
        return Outcome(EXIT_USAGE, _NOT_WINDOWS)

    try:
        with registry.OpenKey(registry.HKEY_CURRENT_USER, RUN_KEY, 0, registry.KEY_READ) as key:
            value, _ = registry.QueryValueEx(key, AUTOSTART_NAME)
    except FileNotFoundError:
        return Outcome(EXIT_NOT_RUNNING, "Starting at log-on is off.")
    except OSError as error:
        return Outcome(EXIT_FAILED, f"Could not read the log-on setting: {error}")

    return Outcome(EXIT_OK, f"Starting at log-on is on: {value}")
