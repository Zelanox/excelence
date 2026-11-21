"""Entry point for the server (also what PyInstaller packages).

    python server_entry.py [command]     during development
    excelence-server.exe [command]       packaged

With no command it runs the server in this window, as it always did. The
commands (start, stop, status, ...) are described in
backend/service_cli.py and docs/BACKGROUND_SERVER.md.

PyInstaller works best with a plain script at the project root rather than a
module inside a package, so this just calls the real code.
"""

from backend.service_cli import main

if __name__ == "__main__":
    raise SystemExit(main())
