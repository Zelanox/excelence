"""Run the Excelence server as a standalone program.

    python -m backend.run_server            # uses the EXCELENCE_* settings
    python -m backend.run_server --reload   # development: restart on code changes

Everything that varies between machines comes from environment variables
(see backend/utils/settings.py), so the same code runs on a laptop or on a
shared server without edits.
"""

import os
import sys

from backend.utils.logger import get_logger
from backend.utils.settings import load_settings, startup_problem

logger = get_logger("run_server")

STARTER_DOCUMENT = "test.xlsx"


def ensure_starter_document(folder: str) -> bool:
    """Make sure a fresh install has something to open.

    The client asks for ``test.xlsx`` when it has no remembered document, so
    on a machine with an empty documents folder (a first run of a packaged
    server, say) it would otherwise show nothing at all. If - and only if -
    the folder has no workbook in it, a blank starter is created. An
    existing folder is never touched.

    Returns True if a starter document was created.
    """
    os.makedirs(folder, exist_ok=True)

    for _, _, names in os.walk(folder):
        if any(name.lower().endswith(".xlsx") for name in names):
            return False

    from backend.controller.controller import Controller

    controller = Controller()
    controller.document.documents_folder = folder

    created = controller.create_document(STARTER_DOCUMENT) and controller.save_document()

    if created:
        logger.info("Created starter document %s in %s", STARTER_DOCUMENT, folder)

    return created


def main(argv: list[str] | None = None) -> int:
    arguments = sys.argv[1:] if argv is None else argv

    # Settings kept in excelence.env (next to the program) apply even when
    # the server is started without a terminal, e.g. at Windows log-on.
    from backend import service_control

    paths = service_control.default_paths()
    service_control.load_env_file(paths.env_file)

    try:
        settings = load_settings()
    except ValueError as error:
        # A configuration mistake should stop startup with a clear message.
        print(f"Configuration error: {error}", file=sys.stderr)
        return 2

    problem = startup_problem(settings)

    if problem is not None:
        print(f"Configuration error: {problem}", file=sys.stderr)
        return 2

    import uvicorn

    from backend.utils.config import DOCUMENTS_FOLDER

    try:
        ensure_starter_document(DOCUMENTS_FOLDER)
    except OSError as error:
        logger.warning("Could not prepare the documents folder %s: %s", DOCUMENTS_FOLDER, error)

    if "--reload" in arguments:
        # Development only: reloading needs uvicorn to import the app itself,
        # by name.
        uvicorn.run("backend.main:app", host=settings.host, port=settings.port, reload=True)
        return 0

    # Hand uvicorn the app OBJECT rather than an import string. A string is
    # imported dynamically at run time, which a packager such as PyInstaller
    # cannot see - so a frozen build would start and then fail to find
    # "backend.main". Importing it here makes it an ordinary, visible import.
    from backend.main import app

    # Only one server per folder: a second one would fight for the port and
    # overwrite the first one's PID file.
    already_running = service_control.claim_pid_file(paths, settings.host, settings.port)

    if already_running is not None:
        print(already_running, file=sys.stderr)
        return 3

    server = uvicorn.Server(uvicorn.Config(app, host=settings.host, port=settings.port))

    # "excelence-server stop" asks for a proper shutdown (which saves every
    # open document) by creating a file; this thread notices it.
    try:
        paths.stop_file.unlink(missing_ok=True)
    except OSError:
        pass

    watcher = service_control.StopWatcher(
        paths.stop_file,
        lambda: setattr(server, "should_exit", True),
    )
    watcher.start()

    from backend.discovery import start_discovery

    responder = start_discovery(settings)

    try:
        server.run()
    finally:
        if responder is not None:
            responder.close()

        watcher.close()
        service_control.remove_pid_file(paths, only_pid=os.getpid())

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
