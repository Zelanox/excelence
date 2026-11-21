"""Command-line front end for running the server in the background.

    excelence-server               run in this window (as before)
    excelence-server run           same
    excelence-server start         run in the background
    excelence-server stop
    excelence-server restart
    excelence-server status        exit code 0 when running, 1 when not
    excelence-server logs [--lines N]
    excelence-server autostart on | off | status
    excelence-server config        create the settings file

During development the same commands work as
``python server_entry.py <command>``.
"""

from __future__ import annotations

import sys
from collections.abc import Callable

from backend import service_control as control

USAGE = """\
Usage: excelence-server [command]

  (none), run         run the server in this window
  start               run the server in the background
  stop                stop the background server (open documents are saved)
  restart             stop, then start
  status              show whether it is running (exit code 0 = running)
  logs [--lines N]    show the end of the server log (default 40 lines)
  autostart on|off|status
                      start the server when you log in to Windows
  config              create the settings file (excelence.env)
  help                show this text
"""


def _foreground() -> int:
    from backend.run_server import main as run_main

    return run_main([])


def _emit(outcome: control.Outcome) -> int:
    stream = sys.stdout if outcome.code in (control.EXIT_OK, control.EXIT_NOT_RUNNING) else sys.stderr
    print(outcome.message, file=stream)
    return outcome.code


def main(
    argv: list[str] | None = None,
    *,
    paths: control.ServicePaths | None = None,
    foreground: Callable[[], int] = _foreground,
) -> int:
    arguments = list(sys.argv[1:] if argv is None else argv)
    command = arguments[0].lower() if arguments else "run"
    rest = arguments[1:]
    where = paths or control.default_paths()

    if command in ("help", "-h", "--help"):
        print(USAGE)
        return control.EXIT_OK

    if command == "run":
        return foreground()

    if command == "start":
        return _emit(control.start(where))

    if command == "stop":
        return _emit(control.stop(where))

    if command == "restart":
        return _emit(control.restart(where))

    if command == "status":
        try:
            state = control.get_status(where)
        except ValueError as error:
            print(f"Configuration error: {error}", file=sys.stderr)
            return control.EXIT_USAGE

        print(control.format_status(state, where))
        return control.EXIT_OK if state.kind == "running" else control.EXIT_NOT_RUNNING

    if command == "logs":
        count = 40

        if rest:
            if len(rest) == 2 and rest[0] == "--lines" and rest[1].isdigit():
                count = int(rest[1])
            else:
                print("Usage: excelence-server logs [--lines N]", file=sys.stderr)
                return control.EXIT_USAGE

        lines = control.tail_lines(where.log_file, count)

        if not lines:
            print(f"No log yet: {where.log_file}")
            return control.EXIT_OK

        print("\n".join(lines))
        return control.EXIT_OK

    if command == "autostart":
        choice = rest[0].lower() if rest else ""

        if choice == "on":
            return _emit(control.autostart_enable(where))

        if choice == "off":
            return _emit(control.autostart_disable(where))

        if choice == "status":
            return _emit(control.autostart_status(where))

        print("Usage: excelence-server autostart on|off|status", file=sys.stderr)
        return control.EXIT_USAGE

    if command == "config":
        return _emit(control.init_config(where))

    print(f"Unknown command: {arguments[0]}\n", file=sys.stderr)
    print(USAGE, file=sys.stderr)
    return control.EXIT_USAGE


if __name__ == "__main__":
    raise SystemExit(main())
