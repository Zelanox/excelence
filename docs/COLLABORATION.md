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
| 3 | **Document sessions**: one in-memory session per open document, per-session locks, client identity | next |
| 4 | **Stable row IDs and an operation log** (revision-numbered, canonical operations) | |
| 5 | **WebSocket broadcast**, optimistic apply, reconnect catch-up, presence ("who is here") | |
| 6 | **Per-user undo** via inverse operations (replaces snapshot undo) | |
| 7 | Accounts, permissions, share links, HTTPS hosting (not needed for a small trusted team) | later |

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
