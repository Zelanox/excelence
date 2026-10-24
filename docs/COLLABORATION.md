# Excelence: running server and client separately, and real-time collaboration

This document has two parts:

1. **Running the server and the client as two separate apps** - what already works and
   how to use it (this is implemented).
2. **Real-time collaboration, Google-Sheets style** - the design, what has to change in
   the current code first, and a phased roadmap (this is a plan, not yet built).

---

## 1. Where things stand

Excelence is already two programs that talk over HTTP:

| | Client | Server |
|---|---|---|
| What | Flutter app (`frontend/`) | FastAPI app (`backend/`) |
| Owns | the UI, local editing, formula evaluation, selection/scroll | the workbook (`.xlsx`) files, the document model, saving |
| Talks via | HTTP + JSON | HTTP + JSON |

What kept them from being *deployable* separately was coupling that only works on one
machine:

* the client had `http://localhost:8000` written into the code;
* the server's CORS rule only admitted pages served from `localhost`;
* there was no authentication at all;
* the server keeps **one global document in memory**, shared by whoever calls it.

The first three are solved by Part 1. The last one is the heart of Part 2.

---

## 2. Part 1 - Running as two apps

### Server settings (environment variables)

| Variable | Meaning | Default |
|---|---|---|
| `EXCELENCE_HOST` | Interface to listen on. `0.0.0.0` accepts other machines | `127.0.0.1` |
| `EXCELENCE_PORT` | Port | `8000` |
| `EXCELENCE_ALLOWED_ORIGINS` | Comma-separated origins of web clients allowed to call the API, e.g. `http://192.168.1.20:8080` | none |
| `EXCELENCE_LOCALHOST_ORIGINS` | `0` stops also accepting any `http://localhost:<port>` page | on |
| `EXCELENCE_DOCUMENTS_DIR` | Where workbooks are stored | `backend/utils/data/documents` |
| `EXCELENCE_ACCESS_TOKEN` | If set (12+ characters), every request must send `Authorization: Bearer <token>` | none |

A bad value stops startup with a message saying what to fix (a mistyped origin that is
silently ignored is far harder to diagnose).

Start it with:

```
python -m backend.run_server            # reads the variables above
python -m backend.run_server --reload   # development
```

### Client settings (build-time `--dart-define`)

```
flutter run -d chrome --dart-define=API_BASE_URL=http://192.168.1.20:8000 --dart-define=API_TOKEN=<token>
flutter build web     --dart-define=API_BASE_URL=https://sheets.example.com
```

### Example: two or more PCs on the same network (Windows)

On the PC that will be the server (say its address is `192.168.1.20`):

```
set EXCELENCE_HOST=0.0.0.0
set EXCELENCE_ALLOWED_ORIGINS=http://192.168.1.20:8080
set EXCELENCE_ACCESS_TOKEN=choose-a-long-secret-here
python -m backend.run_server
```

Allow inbound TCP on port 8000 in Windows Defender Firewall. Build the client once and
serve the result from any static web server (the `flutter build web` output is just
files; `python -m http.server 8080` run inside `build/web` is enough for a trial):

```
flutter build web --dart-define=API_BASE_URL=http://192.168.1.20:8000 --dart-define=API_TOKEN=choose-a-long-secret-here
```

Everyone on the network opens `http://192.168.1.20:8080`.

### Security - read this before exposing the server

* With no token, **anyone who can reach the server can read, change and delete every
  document.** The server logs a warning at startup if it is network-reachable without one.
* The token is a *shared secret compiled into the client*. It keeps strangers out of a
  trusted team's server. It is **not** per-user login: anyone who can load the app can
  extract it, and you cannot tell users apart or revoke one person. Real accounts are
  roadmap phase 6.
* Over the internet use **HTTPS** (put the server behind Caddy or nginx with a certificate).
  A token sent over plain HTTP can be read by anyone on the path.
* Run **one** server process. Documents live in that process's memory; several workers
  would each hold a different copy.

---

## 3. Part 2 - Real-time collaboration

### 3.1 Goal

When one person changes the sheet, everyone else who has it open sees the change
within a moment, without refreshing - cell values, formatting, rows and columns - and
people can see who else is here.

### 3.2 What the current code makes hard

These are not bugs; they are consequences of a single-user design. Each has to be
resolved before live sync can be correct, and they decide the order of the roadmap.

1. **One global document.** The server has a single in-memory document for everyone.
   Two people opening different files would replace each other's. Needs one *session* per
   open document, with its own lock.
2. **Sorting and filtering are stored on the shared sheet.** If one user searches or sorts,
   *everyone's* view would change. These must become per-user.
3. **Every edit is addressed by visible row number.** "Edit row 5" means a different row
   once someone else inserts a row above it or has a different sort. Edits must refer to
   rows by a **stable ID**, not a position.
4. **Undo is a snapshot of the whole sheet.** In a shared document, Ctrl+Z would also
   revert other people's work. Undo must become per-user: "reverse *my* last change".
5. **Formulas only exist in the browser.** The server stores computed values only, so a
   formula typed by one user would reach others as a plain number (and is lost on reload).
   Formulas must be stored as text and evaluated on every client.
6. **Every save rewrites the whole file**, and the client downloads the whole sheet after
   most operations. Fine for one user; with several people editing, saving must be batched
   and clients must receive *small changes*, not the full sheet.
7. **No identity.** The server cannot tell users apart (needed for presence, per-user undo,
   permissions).

### 3.3 Target architecture

```
  Client A ──┐                                   ┌──────────────────────────┐
  Client B ──┼── WebSocket (ops, presence) ─────▶│  Document session        │
  Client C ──┘     + HTTP (open/list/save)       │   - authoritative state  │
                                                  │   - ordered op log       │──▶ debounced save ──▶ .xlsx
                                                  │   - revision counter     │
                                                  └──────────────────────────┘
```

* The **server is the single authority** for each document. It receives operations,
  applies them one at a time in arrival order, gives each a **revision number**, and
  broadcasts it to everyone connected to that document.
* A client applies its own change **immediately** (so typing feels instant), sends it to
  the server, and later receives the server's confirmation. Changes from other people
  arrive as operations and are applied to the local model - no full reload.
* **WebSocket**, not raw sockets: a browser cannot open a raw TCP connection, so the
  existing `backend/network/` socket code cannot serve the web client. (`websockets` is
  already a dependency.)
* Ordering by one server is much simpler than OT/CRDT algorithms and is enough for a
  spreadsheet, where most edits touch independent cells. CRDT libraries (Yjs, Automerge)
  are the alternative; they cost a rewrite of the data model and are not needed at this
  scale.

### 3.4 The model

* **Rows have stable IDs** assigned by the server. Columns are referred to by a stable
  column ID (today: by name, which breaks on rename).
* **Operations** are small and in canonical terms, never in "what the screen shows":
  `set_cells`, `set_style`, `insert_rows`, `delete_rows`, `insert_column`,
  `delete_column`, `rename_column`, `set_column_width`, ...
* **Views are local to each client**: sort, filter, selection and scroll. The client already
  receives every row, so it can sort and filter them itself. This removes per-user view
  state from the server entirely, and the server's API only ever speaks canonical
  coordinates.

**Conflict rules** (what happens when two people act at once):

| Situation | Result |
|---|---|
| Two people edit the same cell | The later one (by server order) wins; both end up seeing it |
| Two people edit different cells | Both apply - no conflict |
| Someone edits a row another person just deleted | The edit is dropped and the editor is told |
| Two people insert rows at the same spot | Both rows are kept, in arrival order |
| Formatting the same cell | Merged field by field; the later change wins per field |
| Rename a column while someone edits it | Edits follow the column ID, so they still land |

### 3.5 Protocol sketch (WebSocket, JSON)

```
client → server   {"type":"hello",  "document":"budget.xlsx", "name":"Sara", "since":120}
server → client   {"type":"welcome","clientId":"c7", "revision":131, "missed":[...ops 121..131]}
                  (or {"type":"resync"} + a fresh snapshot if too far behind)
client → server   {"type":"ops", "baseRevision":131, "ops":[{"op":"set_cells", ...}]}
server → all      {"type":"ops", "revision":132, "from":"c7", "ops":[...]}      (sender uses it as the ack)
client → server   {"type":"presence", "selection":{"row":"r41","col":"c3"}}      (not stored, not saved)
server → all      {"type":"presence", "clientId":"c7", "name":"Sara", "selection":{...}}
```

Reconnecting clients send the last revision they saw and receive what they missed.

### 3.6 Per-user undo

Each client keeps a stack of *inverse operations* for its own changes. Undo sends the
inverse as a new operation, so it is ordered, broadcast and saved like any other change,
and never touches other people's edits. This replaces the sheet-snapshot undo.

### 3.7 Formulas

Store the cell's *input* (the formula text, e.g. `=SUM(A1:A3)`) as the cell value, exactly
as Excel does. Every client evaluates it with the same engine, so everyone sees the same
result and nothing needs recalculating on the server. This is a prerequisite and is
useful on its own: it also fixes formulas being lost on reload today.

### 3.8 Persistence

The `.xlsx` stays the stored form. The server applies operations to the in-memory document
and saves it a moment after activity stops (debounced, not per keystroke). The operation
log is kept only in memory, long enough to catch up reconnecting clients.

### 3.9 Accounts and permissions (later)

Per-user login, share links, and view/comment/edit roles, over HTTPS. The shared token in
Part 1 is only a stop-gap.

---

## 4. Roadmap

Each phase is useful on its own and can be checked before the next starts.

| # | Phase | Status |
|---|---|---|
| 0 | Run as two apps: configurable address, CORS, optional shared token | **done** |
| 1 | **Client-side sort/filter.** The client keeps the full ("canonical") rows and derives its own view; the server no longer sorts or filters for it. Every edit, paste, clear, format, insert and delete converts the *shown* row to the *data* row first. The row gutter shows data row numbers. | **done** (server verified; Flutter side needs a manual test) |
| 2 | **Formulas stored as text.** The cell's input (`=SUM(A1:A3)`) is what is saved, written to the `.xlsx` as a real Excel formula, and re-evaluated by every client on load. The server rewrites stored formulas when rows/columns are inserted or deleted. | **done** (same note) |
| 3 | **Document sessions**: one in-memory session per open document, per-session locks, client identity | **done** (server verified; Flutter side needs a manual test) |
| 4a | **Stable row and column IDs** in the server model and the grid payload | **done on the server** (Sheet-level tests pass; Document-level tests and the Flutter side still to be run by hand) |
| 4b | **Operation log**: revision-numbered canonical operations addressed by those IDs | **done for the first operation set** (cells, rows, columns, column width, RTL, sheets); text/cell styles, appearance and text defaults still to add |
| 4c | **Nothing slips past the log**: old routes, undo while shared, reload | **done** |
| 5a | **Server: live broadcast and presence** (log subscribers, hub, `/spreadsheet/live`, token on WebSockets) | **done**, once the route tests pass on a real machine |
| 5b-1 | **Client building blocks:** the server says which revision each grid payload matches; Flutter has the live connection (ping, reconnect), message parsing and the "is my copy out of date?" logic, all tested without a network | **in progress** (code written; Flutter tests to run) |
| 5b-2 | Wire those into the app: connect when a document is open, **reload mode** (any change by someone else reloads the document), the connection state and the "who is here" count (this also covers 5c) | **in progress** (code written; needs a manual two-window test) |
| 5b-3 | Apply incoming changes one by one by id instead of reloading | |
| 5b-4 | Send edits as operations, with optimistic apply | |
| 5c | "Who is here" in the UI | (in 5b-2: a count in the status bar, names in its tooltip) |
| 6 | **Per-user undo** via inverse operations (replaces snapshot undo) | |
| 7 | Accounts, permissions, share links, HTTPS hosting (not needed for a small trusted team) | later |

### Phase 3 in detail: sessions

A **session** is one open document together with its own lock and the list of clients in it.

* Everyone who opens the same file **joins the same in-memory document** (it is loaded from disk
  only if nobody has it open), so people see each other's unsaved changes and never overwrite
  each other. Different files are independent sessions with independent locks.
* The server now knows who is in each document: `GET /sessions` lists every open document and
  its clients (the data behind "who is here").
* A client announces itself with headers on every request:

  | Header | Meaning |
  |---|---|
  | `X-Client-Id` | random id for this running copy of the app (a new one each launch) |
  | `X-Client-Name` | display name, percent-encoded (headers are ASCII; names may be Arabic) |
  | `X-Document` | the **session id** the server returned when the document was opened |

  The session id is opaque rather than the file name, again because file names can be non-ASCII.
* **Leaving:** closing/opening another document leaves the session. When the last client leaves,
  the document is saved and released. A client silent for 2 minutes counts as gone.
* **Idle clients are re-attached transparently.** If a session was released while its client was
  idle, the next request re-opens it from disk (it was saved on release) - nothing is lost and
  no error is shown. Only a *server restart* produces a `409 SESSION_NOT_OPEN`; reopen the
  document (reload the page).
* **Safety rules:** a file open in a shared session can't be deleted, renamed or overwritten by
  an upload; creating a document won't replace an existing one (and must end in `.xlsx`, or it
  would never appear in the document list); a failed save keeps the session open instead of
  discarding work; shutting the server down saves every modified session.
* **Old clients keep working.** A request with no identity uses a single "default" session that
  behaves exactly like the old global document. Mixing old and new clients on the *same file* is
  refused, so two in-memory copies can't drift apart.

Known limits until later phases: the last-opened document and preferences are still stored
server-wide (so with several people they are shared - they need a per-user identity); autosave
is still done by every client (harmless, wasteful); the session id is not a secret, and the
shared token remains the only protection.

### Phase 4a in detail: stable row and column IDs

Every grid payload (`/spreadsheet/data` and every response that returns the grid) now carries
`row_ids` (one per row in `rows`) and `column_ids` (one per column in `headers`). Nothing in the
Flutter client reads them yet, so this phase changes no behaviour.

* **What an ID is.** A string such as `r17` or `c3`, unique within its sheet. A row's ID does not
  change when rows are inserted or deleted above it, or when the sheet is sorted or searched. A column's
  ID does not change when it is renamed or when columns are inserted or deleted before it.
* **Never reused.** Counters only go up, and undo does not rewind them, so a deleted row's or
  column's ID is never given to a new one in the same session. Undo of a delete brings back the
  same row with the same ID.
* **Reassigned on load.** IDs are not saved in the `.xlsx`. After a server restart, or when a
  document is reopened from disk, every row and column gets a fresh ID, and clients reload the
  document. (Decided: this is simpler and enough for a small trusted team.)
* **Where they live.** `Sheet.row_ids` (parallel to the dataframe rows) and `Sheet.column_ids`
  (column name to ID). Cell styles, column widths and formulas are still stored by position and
  by name, exactly as before: the IDs are a translation layer, so the server can turn an ID into a
  position or a name at the moment it applies a change. `Sheet.row_position`, `row_id_at`,
  `column_name` and `column_id` do that translation.
* **Repair rule.** `Sheet.ensure_ids()` runs before every structural edit and whenever IDs are
  read. If the number of IDs no longer matches the number of rows (a dataframe replaced from
  outside the structural methods), every row gets a fresh ID, because there is no way to know which
  row is which. Any new structural operation on `Sheet` must keep `row_ids` and `column_ids` in step.
* **Switching sheets keeps IDs.** Checked on the real Document: IDs of the sheet you leave and of
  the sheet you open are unchanged after switching back and forth, including with blank rows.
  (An earlier note here guessed that trailing blank rows would cause reassignment; that did not
  reproduce.)

### Phase 4b, step 1: stable sheet IDs, and a rename fix

* **Sheet IDs.** Every worksheet has an ID such as `s2`, unique within the document and never reused in
  a session (`Document` owns the counter; `Spreadsheet` is rebuilt too often to hold it). The grid
  payload carries `current_sheet_id`; every sheet-list response carries `sheet_ids` (parallel to
  `sheets`) and `current_sheet_id`. A rename changes the name, not the ID.
* **Why it mattered.** Sheet models are matched to worksheets by name when the spreadsheet is rebuilt, so
  renaming a sheet used to throw its model away: every row and column ID was reassigned and its
  text styles were re-read.
* **Bug fixed along the way (data loss).** Renaming a sheet that was not the open one wrote the open
  sheet's contents over it. `Document.rename_sheet` now only renames an inactive sheet and
  leaves the open sheet's data alone.

### Phase 4b in detail: operations, the revision log, and two routes

Code lives in `backend/collab/` (no web-framework dependency) and `backend/api/collab.py`.

* **`POST /spreadsheet/ops`** takes a batch: `{"client_batch_id", "base_revision", "sheet_id", "ops": [...]}`
  with the headers `X-Client-Id` and `X-Document` (the session). It always answers HTTP 200 with
  either `{"accepted": true, "revision", "duplicate", "applied", "dropped"}` or
  `{"accepted": false, "code", "message", "index", "resync_required"}`.
* **`GET /spreadsheet/ops?since=N`** returns the batches after revision N, or `resync_required: true`
  if the client is too far behind or something that can't be replayed happened in between.
* **Operations** (all by ID, see the module doc in `collab/operations.py`): `set_cells`, `insert_row`,
  `delete_row`, `insert_column`, `delete_column`, `rename_column`, `set_column_width`, `set_rtl`,
  `add_sheet`, `delete_sheet`, `rename_sheet`. `applied` is the batch as the server applied it, with the
  `id` it gave to any new row, column or sheet. Cell values are text or `null` (the document turns "7"
  into a number in a numeric column); raw numbers and booleans are refused.
* **Rules.** One sheet per batch (sheet operations alone in theirs); at most 500 changes per batch.
  Everything checkable up front (shape, IDs that never existed, column-name clashes) is checked before
  anything is applied. An ID that existed and was deleted by someone else is not an error: that change
  is *dropped*, the rest applies, and the sender gets a `dropped` list with the reason
  (`ROW_DELETED`, `COLUMN_DELETED`, `SHEET_DELETED`). A batch where everything was dropped uses no revision.
* **Revisions and resends.** Each accepted batch gets the next revision; a refused one uses none. A
  resent `client_batch_id` from the same client returns the original answer with `duplicate: true` and
  is not applied again. The log keeps at least 1,000 batches and everything from the last 10 minutes.
* **Error codes:** `BAD_REQUEST`, `EMPTY_BATCH`, `BATCH_TOO_LARGE`, `UNKNOWN_SHEET`, `UNKNOWN_ROW`,
  `UNKNOWN_COLUMN`, `NAME_TAKEN`, `INVALID_VALUE`, `REVISION_FROM_FUTURE`, `APPLY_FAILED`.
* **Verified by test:** replaying the log of 250 random batches onto a second copy of the document gives
  the same rows, headers, row/column IDs, widths and direction (and the second copy hands out the same
  new IDs).

Known limits, on purpose, to be dealt with in the next steps:

* **Applying to a sheet that is not the open one switches sheets** and back (the server still has one open
  sheet per session). That re-reads the workbook, so two people working on different sheets of a large
  document will make each other slow. Making the sheet-level methods independent of the open sheet is a
  larger change.
* **A batch that fails part-way** (the up-front checks are meant to make this impossible) is not rolled
  back; the server records a `resync` entry so every client reloads.
* Applying changes clears any server-side search or sort left by an older client, because the controller
  edits by position in the server's view.
* **Operations still to add:** text and cell styles, appearance, text defaults.

### Phase 4c: nothing slips past the log

* **Old routes.** `Document.change_count` goes up whenever the document is modified (it rides on the
  `modified` flag every editing path already sets, so no path can be missed). After every request for a
  session, `get_session` calls `collab.service.account_for_untracked_changes`: if the count moved
  without a batch going through `/spreadsheet/ops`, a `resync` entry is added to the log, so clients
  using the log reload instead of silently falling behind. Batches through the operation path are
  accounted for as they are applied, so they don't produce a second entry.
* **Undo and redo** are refused (`success: false`, "Undo is unavailable while others are editing.")
  while more than one client is in the session. They still work for one person. Per-user undo
  (phase 6) will replace this.
* **Reloading a document** resets the log, so every client must load the document again.

### Phase 5a, step 1: log subscribers and the hub

Code: `backend/collab/op_log.py` (subscribers) and `backend/collab/hub.py` (no web-framework dependency).

* **The log announces itself.** `OpLog.subscribe(callback)` / `unsubscribe(callback)`: every appended
  entry is passed to each subscriber, in the appending thread, under the session's lock. A subscriber that
  raises is logged and ignored: the change is already applied and numbered. Because *every* entry goes
  through `append`, changes made over HTTP, changes made over a live connection and `resync` entries
  (old routes, reload) all reach live clients without any route having to remember to broadcast.
* **The hub** keeps one *room* per session with live connections: client id → connection, in join order.
  `join(session, conn, since)` sends the catch-up first and registers for live messages second, under the
  session's lock, so nothing is missed and nothing is sent twice. A connection of a client id that is
  already in the room *replaces* the old one (the old one is closed with reason `replaced`), so presence
  never shows a client twice. `leave(session, conn)` ignores a connection that was already replaced.
  When the last connection leaves, the room unsubscribes from the log and disappears.
* **Messages to a client** (JSON, with a `type`): `catch_up {revision, batches}`, `resync {revision, reason}`,
  `batch {batch}` (the entry as `GET /spreadsheet/ops` returns it), `presence {clients: [{id, name}]}`,
  `result {client_batch_id, accepted, ...}` (the answer to the sender's own batch, with the `dropped`
  notices or the refusal), `error {code, message}`. The sender receives its own batch through `batch`
  (that is its acknowledgement) and then the `result`. `resync` reasons: `BEHIND` (too far behind, or
  something unreplayable in between), `AHEAD_OF_SERVER` (the client saw a revision this server never
  reached, so it was talking to an earlier run: reload), `CHANGED` (the document changed in a way the log
  can't describe).
* **A slow client can't slow anyone else.** `deliver` never waits. `QueueConnection` (for the asyncio
  server) schedules the message on the event loop with `call_soon_threadsafe` and keeps a bounded queue
  (256 messages). If the client falls further behind than that, its queue is dropped, the connection closes
  with reason `overflow`, and the client reconnects and catches up from the log.
* **Presence is the set of live connections**, nothing else (not the HTTP "last seen" list).
* A connected client sends nothing over HTTP, so the route refreshes its entry in the session registry
  on every message (see step 2).

### Phase 5a, step 2: the WebSocket route

Code: `backend/collab/live.py` (the rules, no web framework), `backend/api/live.py` (the route),
`require_access_token` in `backend/main.py`, `hub` / `get_hub` in `backend/dependencies.py`.

**Address:** `ws://<server>/spreadsheet/live?document=<session id>&client=<client id>&name=<name>&since=<revision>&token=<token>`

| Parameter | Rule |
|---|---|
| `document` | required: the session id the server returned when the document was opened (the same value as the `X-Document` header) |
| `client` | required: 8-64 letters, digits, `-` or `_` (same as `X-Client-Id`) |
| `name` | optional (default `Guest`); 1-40 characters after control characters are removed; Arabic is fine; longer or empty is refused (not cut) |
| `since` | optional (default 0): the last revision the client applied; a whole number, 0 or more |
| `token` | the shared access token, when the server has one (see below) |

**Messages from the client:** `{"type":"ping"}` (answered with `{"type":"pong"}`) and
`{"type":"ops","payload":{...}}` where `payload` is exactly the body of `POST /spreadsheet/ops`.
Anything else, or anything that is not JSON, gets an `error` (`BAD_REQUEST`) and the connection stays open.
A message over 1,000,000 characters gets `MESSAGE_TOO_LARGE`. (Uvicorn itself drops connections that send more than 16 MB.)

**Messages from the server:** see step 1. On connecting: `catch_up` (or `resync`) and then `presence`.
Problems with the parameters or the document come as an `error` followed by a close with code 1008.

**Keeping the session open:** clients should send a `ping` about every 30 seconds. Every message refreshes the
client in the session registry, whose idle limit is 120 seconds; without it the server would drop the client,
save and close the document, and re-open it as a new session with an empty log. If that happens anyway, the
next message gets `error SESSION_REPLACED` (or `SESSION_NOT_OPEN` if the server forgot the document) and the
connection is closed with 1012: reconnect, and the catch-up will say `resync`.

**Disconnecting does not leave the session.** Presence changes at once, but the client stays in the registry
until the normal idle limit, so a phone that loses Wi-Fi for a moment comes back to the same open document
(no save, close and re-open). The "Close" route still leaves at once.

**Close codes the server uses:**

| Code | Meaning | What the client should do |
|---|---|---|
| 1008 | Refused: bad parameters, document not open, or wrong/missing token | Don't retry blindly: fix the cause (or open the document again) |
| 1012 | Session closed or forgotten on the server | Reconnect (with `since`); expect `resync` |
| 1013 | The client fell more than 256 messages behind | Reconnect and catch up |
| 1011 | Unexpected error on the server | Reconnect |
| 4001 | Another connection with the same client id took over | **Do not auto-reconnect** (two would keep replacing each other) |
| 1000 | Normal | |

Suggested reconnect delays: 1, 2, 4, ... up to 15 seconds.

**The access token on a WebSocket.** Browsers cannot set headers on a WebSocket, so the token may travel as
`?token=`; a non-browser client may use the `Authorization: Bearer` header instead (the header wins if both are
sent). It is checked before the connection is accepted: a refused connection is turned away at the handshake
(HTTP 403 / close 1008). Ordinary HTTP requests do **not** accept `?token=`. Two things to know:
* A token in a URL can end up in logs: Uvicorn's access log prints the full address, query included. On a
  trusted LAN with a shared token this is acceptable; do not share those logs, and change the token if they
  leak. (An "authenticate with the first message" scheme would avoid it; not done yet.)
* Browsers do not apply CORS rules to WebSockets, so the allowed-origins setting does not protect this route;
  the token does.

**Decisions made in this step:**
* One connection per client id; a new one replaces the old one (close code 4001).
* The default (legacy, no-document) session has no live connection: `document` is required.
* A client ahead of the server gets `resync` / `AHEAD_OF_SERVER` rather than an error.

**Tests:** `test_collab_live.py` (the rules, runs anywhere), `test_collab_hub.py` (hub and queue),
`test_api_live.py` (the real route through Starlette's `TestClient`, including the token rules). The last one
can only run where FastAPI is installed, and a bug that stops a message from arriving shows up as a test that
hangs, not one that fails.

### Phase 5b, step 1: what the client needs before it can go live

**The revision comes with the data.** Every grid payload (`GET /spreadsheet/data` and every route that
returns the grid) now has a `revision` field: the revision of the operation log that this data matches.
A client that loads data and then opens `/spreadsheet/live?since=<that revision>` is told exactly what happened
in between, nothing more and nothing less. Without it, a change made between "load" and "connect" is lost or
applied twice.
* `Session.revision()` brings the log up to date first: a change made through an old route (not an operation)
  is logged as a "reload" entry *before* the number is read, so the number is never behind the data. Calling it
  again adds nothing.
* `Controller.revision()` reads it (0 when the controller is not in a session, such as in unit tests).

**Flutter, `frontend/lib/core/live/` (no Flutter widgets in it; tests in `frontend/test/live_*_test.dart`):**
* `live_messages.dart`: reads the server's messages into typed objects; skips anything it doesn't understand
  (so a newer server can add message types).
* `live_address.dart`: builds the `ws://` / `wss://` address from the server's base URL (name cut to 40 characters).
* `live_channel.dart`: the only file that touches `web_socket_channel`; a small interface so tests use a fake.
* `live_connection.dart`: opens the connection, pings every 30 s, reconnects with 1, 2, 4, 8, 15 s delays
  (starting over after a connection that worked), asks each time from the newest revision it has applied,
  and stops for good only on close code 1008 (refused) or 4001 (replaced).
* `live_sync.dart`: decides when the local copy is out of date and must be reloaded. A message not newer than
  the local copy is ignored (usually the echo of one's own change); nothing reloads while this client has a
  request of its own in flight (its response usually settles it); messages in quick succession cause one
  reload, and a message during a reload causes one more; a failed reload is reported and retried on the next
  message, never in a loop.

**Reload mode (next step).** At first every change by someone else is handled by reloading the document. It is
simple and always correct, and it already works for everything the old routes change, because those produce
a "reload" entry for everyone else. Applying changes one by one (5b-3) and sending edits as operations (5b-4)
replace it piece by piece.

### Phase 5b, step 2: reload mode in the app

* `LiveCoordinator` (`core/live/live_coordinator.dart`) bundles the connection, the reload logic and the list of
  people for one open document. `SpreadsheetController` creates one after a document has loaded (and stops it
  before another is opened), through an optional `liveFactory`; without a factory nothing changes, which is how
  all the existing tests run.
* **Hooks, so no call site has to cooperate:** `ApiClient` tells the app when any `POST`/`PUT`/`DELETE`/upload
  starts and finishes (nothing reloads while this client's own change is on its way), and
  `SpreadsheetService` reports the `revision` of every response that carries grid data.
* **What a reload does** (`_reloadFromLive`): wait for this client's own queued saves, fetch the sheet list and
  the data; if the user edited in the meantime the answer is discarded and asked for again (up to 3 times), so
  an edit never vanishes; then replace the grid.
* **Known limits of reload mode (lifted in 5b-3 / 5b-4 / 6):**
  * The server has ONE active sheet per document. A reload follows it: if someone switches sheets, everyone's
    grid shows that sheet. Two people on different sheets is not possible until edits are addressed by sheet id.
  * Any change by someone else clears your local undo history (it would otherwise undo over their work).
  * The whole sheet is fetched on every change by someone else (debounced to one reload per 150 ms burst).
* **Status bar:** a people icon with the count (names in the tooltip) while connected; "Connecting...",
  "Reconnecting..." or "Live updates off" otherwise. "Live updates off" means the server refused this window
  (for example the document is no longer open there) or another window with the same client id took over.

* **When the server forgets the document** (it was restarted, or the id is unknown to it): every HTTP call
  then answers `409 SESSION_NOT_OPEN`, and the live connection is refused with the same code. Before this
  there was no handling at all, so autosave, resync and saving appearance failed in a loop. Now
  `ApiClient.onSessionLost` (any such 409) and `LiveCoordinator.onSessionLost` (the live error) make the
  controller open the document again from what the server last saved on disk
  (`SpreadsheetController._sessionLost`). Edits made since that save are not on the server any more and are
  replaced by the saved version. It does nothing while a document is already being opened, and at most once
  every ten seconds, so it cannot loop.
* **Manual two-window test:** start the backend and leave it running; start the app (`flutter run -d chrome`),
  open a document; start a second instance (`flutter run -d edge`, or another `-d chrome`), open the same
  document. Each app launch has its own random client id, so two instances never replace each other.
  Expect the people icon to show 2 in both, an edit in one to appear in the other within about half a second,
  and "Reconnecting..." followed by recovery if the backend is stopped and started again.


### Why the order changed

The first plan put formulas first. Reading the formula engine showed formula references
like `A5` were resolved against the rows **currently on screen**, so a search or sort silently
changed what a formula referred to. That is wrong even for one user and impossible to allow
in a shared sheet, so client-side views (which keep the real rows separate from what is
shown) had to come first, and formulas were built on top of them.

### What changed for users (worth testing by hand)

* Search and sort no longer clear undo history, and survive inserting/deleting a row.
* The row numbers on the left are the **data** row numbers (the numbers formulas use). Under a
  sort they appear out of order; under a filter they leave gaps - as in Excel.
* Typing a formula and reloading the file now keeps the formula (it used to turn into a
  plain number). A formula with a function the app doesn't support shows `#ERROR!`.
* Inserting or deleting a row/column now updates formulas that refer to cells past it; a
  formula that referred to a deleted cell shows an error instead of a wrong number.
* Typing a number into a column that is mostly numbers stores a number even if the column
  also holds a formula; a mostly-text column (IDs like `007`) keeps text.

### Still true after phases 1-2 (so phases 3-6 matter)

* The server still holds one global document; undo is still a whole-sheet snapshot; and an
  edit still addresses a row by position (so a concurrent insert by someone else would
  misdirect it). Those are exactly what phases 3, 4 and 6 fix.
* Evaluating formulas on load is not memoised: very long chains of dependent formulas
  would be slow. Fine at this scale; easy to optimise later.

---

## 5. Decisions (settled)

1. **Who uses it:** a small team on one network, with one device acting as the server. The
   shared token is enough; accounts and HTTPS are deferred.
2. **Sort/filter on the client.** Accepted - the client already receives every row, so the
   extra work is sorting/filtering them in memory (fast for the sheet sizes in scope;
   optimise later if needed).
3. **First release:** live cell values and formatting, plus a "who is here" list. Live cursors,
   comments and version history can follow.

## 6. A word on testing

The server side of each phase can be verified automatically (the project's backend tests
run without a UI). The Flutter side cannot be run in the environment this work is done in, so
every client change depends on being tried by hand. Doing the phases one at a time, with a
manual check after each, is much safer than a single large change.
