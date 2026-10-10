"""Small app-level state that must survive restarts: which document was
open last, and per-user preferences.

Why this lives on the backend rather than in the browser: Flutter web's
key-value storage is browser localStorage, which belongs to a single
ORIGIN (host + port). ``flutter run -d chrome`` serves the app on a new
random port every launch, so anything stored there looks empty next time.
The backend is the same process, reading the same folder, every time.

It is stored as one hidden JSON file inside the documents folder, so
"last document" (a path relative to that folder) is always scoped to the
folder it makes sense in. State is a convenience, never a requirement: it
is read leniently and written atomically, and every failure is logged and
swallowed so a broken or unwritable state file can never stop a document
from opening or saving.
"""

import json
import os
import re
import tempfile
from collections.abc import Callable
from typing import Any

from backend.utils.logger import get_logger

logger = get_logger("app_state")

STATE_FILENAME = ".excelence_state.json"

_KEY_PATTERN = re.compile(r"^[a-z0-9_]{1,64}$")
_MAX_STRING_LENGTH = 256


def _valid_preference_value(value: Any) -> bool:
    """Preferences are small JSON scalars - never nested data or blobs."""
    if value is None or isinstance(value, bool):
        return True

    if isinstance(value, (int, float)):
        return value == value and value not in (float("inf"), float("-inf"))

    if isinstance(value, str):
        return len(value) <= _MAX_STRING_LENGTH

    return False


class AppState:
    """Reads and writes the state file in whatever folder ``folder()`` names.

    The folder is looked up on every call (not captured once) so it follows
    the document store if that is ever repointed.
    """

    def __init__(self, folder: Callable[[], str]) -> None:
        self._folder = folder

    def _path(self) -> str:
        return os.path.join(self._folder(), STATE_FILENAME)

    def _load(self) -> dict[str, Any]:
        """The stored state, or {} if it is missing, unreadable or malformed."""
        try:
            with open(self._path(), "r", encoding="utf-8") as handle:
                data = json.load(handle)
        except FileNotFoundError:
            return {}
        except (OSError, ValueError) as error:
            logger.warning("Ignoring unreadable app state: %s", error)
            return {}

        return data if isinstance(data, dict) else {}

    def _save(self, data: dict[str, Any]) -> bool:
        """Write atomically: a crash mid-write must not leave a torn file."""
        path = self._path()
        temp_path = None

        try:
            os.makedirs(os.path.dirname(path), exist_ok=True)

            handle, temp_path = tempfile.mkstemp(
                prefix=".excelence_state.",
                suffix=".tmp",
                dir=os.path.dirname(path),
            )

            with os.fdopen(handle, "w", encoding="utf-8") as stream:
                json.dump(data, stream, indent=2, sort_keys=True)

            os.replace(temp_path, path)
            return True
        except OSError as error:
            logger.warning("Could not save app state: %s", error)

            if temp_path is not None:
                try:
                    os.remove(temp_path)
                except OSError:
                    pass

            return False

    # -- last document -------------------------------------------------

    def get_last_document(self) -> str | None:
        value = self._load().get("last_document")
        return value if isinstance(value, str) and value.strip() else None

    def set_last_document(self, filename: str) -> bool:
        data = self._load()

        if data.get("last_document") == filename:
            return True

        data["last_document"] = filename
        return self._save(data)

    # -- preferences ---------------------------------------------------

    def get_preferences(self) -> dict[str, Any]:
        stored = self._load().get("preferences")

        if not isinstance(stored, dict):
            return {}

        return {
            key: value
            for key, value in stored.items()
            if isinstance(key, str)
            and _KEY_PATTERN.match(key)
            and _valid_preference_value(value)
        }

    def set_preference(self, key: str, value: Any) -> bool:
        """Set one preference. Rejects odd keys/values rather than storing them."""
        if not isinstance(key, str) or not _KEY_PATTERN.match(key):
            return False

        if not _valid_preference_value(value):
            return False

        data = self._load()
        preferences = data.get("preferences")

        if not isinstance(preferences, dict):
            preferences = {}

        preferences[key] = value
        data["preferences"] = preferences

        return self._save(data)
