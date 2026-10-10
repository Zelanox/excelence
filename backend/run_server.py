"""Run the Excelence server as a standalone program.

    python -m backend.run_server            # uses the EXCELENCE_* settings
    python -m backend.run_server --reload   # development: restart on code changes

Everything that varies between machines comes from environment variables
(see backend/utils/settings.py), so the same code runs on a laptop or on a
shared server without edits.
"""

import sys

from backend.utils.logger import get_logger
from backend.utils.settings import load_settings

logger = get_logger("run_server")


def main(argv: list[str] | None = None) -> int:
    arguments = sys.argv[1:] if argv is None else argv

    try:
        settings = load_settings()
    except ValueError as error:
        # A configuration mistake should stop startup with a clear message.
        print(f"Configuration error: {error}", file=sys.stderr)
        return 2

    if settings.is_network_exposed and settings.access_token is None:
        logger.warning(
            "Listening on %s with NO access token: anyone who can reach this "
            "address can read, change and delete every document. Set "
            "EXCELENCE_ACCESS_TOKEN (and see docs/COLLABORATION.md).",
            settings.host,
        )

    import uvicorn

    uvicorn.run(
        "backend.main:app",
        host=settings.host,
        port=settings.port,
        reload="--reload" in arguments,
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
