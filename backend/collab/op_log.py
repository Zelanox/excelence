"""The revision log of one document session.

Every accepted change gets the next revision number and is remembered for a
while, so that a client which missed some changes (a dropped connection, a
phone that went to sleep) can ask "what happened since revision N?" and catch
up without reloading the whole document.

The log is in memory only and is NOT thread-safe on its own: it belongs to a
Session, and every request for a session already runs under that session's
lock (see dependencies.get_session).
"""

from __future__ import annotations

import time
from collections import OrderedDict, deque
from collections.abc import Callable
from dataclasses import dataclass, field
from typing import Any

# R3: keep at least this many batches, and anything younger than this many
# seconds, whichever is more.
DEFAULT_MIN_ENTRIES = 1000
DEFAULT_MIN_AGE_SECONDS = 600.0

KIND_OPS = "ops"

# "Something changed that this log can't describe as operations - fetch the
# whole document again." Written after a change that bypassed the operation
# path, or after a batch failed half way.
KIND_RESYNC = "resync"


@dataclass(frozen=True)
class LogEntry:

    revision: int
    kind: str
    client_id: str = ""
    client_batch_id: str = ""
    sheet_id: str | None = None
    ops: tuple[dict[str, Any], ...] = ()
    dropped: tuple[dict[str, Any], ...] = ()
    time: float = 0.0

    def to_dict(self) -> dict[str, Any]:
        """What is sent to clients (the drop notices are only for the sender)."""
        return {
            "revision": self.revision,
            "kind": self.kind,
            "client_id": self.client_id,
            "client_batch_id": self.client_batch_id,
            "sheet_id": self.sheet_id,
            "ops": list(self.ops),
        }


@dataclass
class OpLog:

    min_entries: int = DEFAULT_MIN_ENTRIES
    min_age: float = DEFAULT_MIN_AGE_SECONDS
    clock: Callable[[], float] = time.monotonic

    # The newest revision handed out (0 = nothing yet).
    revision: int = 0

    # Revisions up to and including this one are no longer available:
    # a client that has only seen this much, or less, must reload.
    floor: int = 0

    _entries: deque[LogEntry] = field(default_factory=deque, repr=False)
    _by_batch: "OrderedDict[tuple[str, str], LogEntry]" = field(default_factory=OrderedDict, repr=False)

    def append(
        self,
        kind: str,
        client_id: str = "",
        client_batch_id: str = "",
        sheet_id: str | None = None,
        ops: list[dict[str, Any]] | None = None,
        dropped: list[dict[str, Any]] | None = None,
    ) -> LogEntry:
        """Record one accepted batch under the next revision number."""
        self.revision += 1

        entry = LogEntry(
            revision=self.revision,
            kind=kind,
            client_id=client_id,
            client_batch_id=client_batch_id,
            sheet_id=sheet_id,
            ops=tuple(ops or ()),
            dropped=tuple(dropped or ()),
            time=self.clock(),
        )

        self._entries.append(entry)

        if client_id and client_batch_id:
            self._by_batch[(client_id, client_batch_id)] = entry

        self._trim()
        return entry

    def find_batch(self, client_id: str, client_batch_id: str) -> LogEntry | None:
        """The entry for a batch this client already sent, if still remembered.

        A client that never saw the reply (the connection dropped) resends
        the same batch; finding it here means "already applied" instead of
        applying it twice.
        """
        return self._by_batch.get((client_id, client_batch_id))

    def since(self, revision: int) -> list[LogEntry] | None:
        """Every entry after ``revision``, oldest first.

        Returns None when some of them are no longer remembered (the client
        is too far behind and must reload the document). ``revision`` newer
        than the log's own is the caller's mistake to report; it is treated
        here as "nothing new".
        """
        if revision < self.floor:
            return None

        return [entry for entry in self._entries if entry.revision > revision]

    def reset(self) -> None:
        """Forget everything: the document was replaced, so every client must reload.

        The revision number keeps counting, so an old client can tell it is behind.
        """
        self._entries.clear()
        self._by_batch.clear()
        self.floor = self.revision

    def _trim(self) -> None:
        cutoff = self.clock() - self.min_age

        while len(self._entries) > self.min_entries and self._entries[0].time < cutoff:
            old = self._entries.popleft()
            self.floor = old.revision

            if old.client_id and old.client_batch_id:
                self._by_batch.pop((old.client_id, old.client_batch_id), None)
