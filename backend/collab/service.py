"""Submitting a batch of changes to a document session, and catching up.

This is the part the web routes call. Both functions expect the caller to hold
the session's lock (every route does, through dependencies.get_session), so a
batch is applied, numbered and logged as one uninterrupted step.
"""

from __future__ import annotations

from typing import Any

from backend.collab import op_log
from backend.collab.operations import (
    APPLY_FAILED,
    REVISION_FROM_FUTURE,
    OpError,
    apply_batch,
    parse_batch,
)
from backend.sessions import valid_client_id
from backend.utils.logger import get_logger

logger = get_logger("collab")


def _rejected(error: OpError) -> dict[str, Any]:
    return {
        "accepted": False,
        "code": error.code,
        "message": error.message,
        "index": error.index,
        "resync_required": error.resync_required,
    }


def submit(session, client_id: str, payload: Any) -> dict[str, Any]:
    """Apply a client's batch and record it.

    Returns a dict for the client:
      accepted: {"accepted": True, "revision", "duplicate", "applied", "dropped"}
      refused:  {"accepted": False, "code", "message", "index", "resync_required"}
    ``applied`` is the batch as the server applied it (with the IDs it gave to
    anything new), ``dropped`` lists changes skipped because their target was
    deleted by someone else.
    """
    log = session.oplog

    if not valid_client_id(client_id):
        return _rejected(OpError("BAD_REQUEST", "A valid X-Client-Id is required."))

    try:
        batch = parse_batch(payload)
    except OpError as error:
        return _rejected(error)

    # The same batch again (the reply was lost and the client resent it).
    previous = log.find_batch(client_id, batch.client_batch_id)

    if previous is not None:
        return {
            "accepted": True,
            "revision": previous.revision,
            "duplicate": True,
            "applied": list(previous.ops),
            "dropped": list(previous.dropped),
        }

    if batch.base_revision > log.revision:
        return _rejected(OpError(
            REVISION_FROM_FUTURE,
            f"base_revision {batch.base_revision} is newer than the server's {log.revision}.",
        ))

    try:
        try:
            outcome = apply_batch(session.controller, batch)
        finally:
            # Whatever happened, the changes made so far are accounted for
            # by what is logged below (or by the resync entry on failure).
            session.accounted_changes = session.controller.document.change_count
    except OpError as error:
        if error.resync_required:
            # Some of the batch is in the document and none of it is in the
            # log: tell everyone to reload instead of letting them diverge.
            log.append(op_log.KIND_RESYNC, client_id=client_id, client_batch_id=batch.client_batch_id)
            logger.warning("Batch %s failed part-way (%s); resync requested", batch.client_batch_id, error.message)

        return _rejected(error)

    if not outcome.applied:
        # Everything was dropped: nothing changed, so no new revision.
        return {
            "accepted": True,
            "revision": log.revision,
            "duplicate": False,
            "applied": [],
            "dropped": outcome.dropped,
        }

    entry = log.append(
        op_log.KIND_OPS,
        client_id=client_id,
        client_batch_id=batch.client_batch_id,
        sheet_id=outcome.sheet_id,
        ops=outcome.applied,
        dropped=outcome.dropped,
    )

    return {
        "accepted": True,
        "revision": entry.revision,
        "duplicate": False,
        "applied": list(entry.ops),
        "dropped": list(entry.dropped),
    }


def changes_since(session, since: int) -> dict[str, Any]:
    """Everything that happened after revision ``since``.

    {"revision": newest, "resync_required": False, "batches": [...]}, or with
    resync_required True (and no batches) if the client is too far behind, or
    some change in between can't be replayed (see op_log.KIND_RESYNC).
    """
    log = session.oplog

    if not isinstance(since, int) or isinstance(since, bool) or since < 0:
        return {"accepted": False, "code": "BAD_REQUEST", "message": "since must be a whole number, 0 or more."}

    if since > log.revision:
        return {
            "accepted": False,
            "code": REVISION_FROM_FUTURE,
            "message": f"since {since} is newer than the server's {log.revision}.",
        }

    entries = log.since(since)

    if entries is None or any(entry.kind == op_log.KIND_RESYNC for entry in entries):
        return {"accepted": True, "revision": log.revision, "resync_required": True, "batches": []}

    return {
        "accepted": True,
        "revision": log.revision,
        "resync_required": False,
        "batches": [entry.to_dict() for entry in entries],
    }


def account_for_untracked_changes(session) -> bool:
    """Record a resync if the document changed without going through submit().

    Called after every request for a session, under its lock. A change made
    through one of the older routes (edit a cell, insert a row, undo, ...) is
    not in the log, so the other clients can't replay it; this adds a
    "reload" entry so they fetch the whole document instead of silently
    falling behind. Returns True if an entry was added.
    """
    count = session.controller.document.change_count

    if count == session.accounted_changes:
        return False

    session.accounted_changes = count
    mark_resync(session)
    return True


def restart_log(session) -> int:
    """The document was replaced (reloaded from disk): every client must load it again.

    Forgets the log, then records a resync entry. The entry matters: a client
    that was fully up to date is not "behind" as far as the log can tell, yet
    what it holds is the OLD document. Returns the new revision.
    """
    session.oplog.reset()
    return mark_resync(session)


def mark_resync(session, client_id: str = "") -> int:
    """Record that the document changed in a way the log can't describe.

    For a change made through a route that doesn't go through submit(), or a
    document that was reloaded: every client must fetch the whole document.
    Returns the new revision.
    """
    return session.oplog.append(op_log.KIND_RESYNC, client_id=client_id).revision
