"""Entry point for packaging the server with PyInstaller.

PyInstaller works best with a plain script at the project root rather than a
module inside a package, so this just calls the real runner:

    pyinstaller server_entry.py --name excelence-server ...

See docs/PACKAGING.md for the full command.
"""

from backend.run_server import main

if __name__ == "__main__":
    raise SystemExit(main())
