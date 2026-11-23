# Toolbar and UI requirements

The overall plan and what is delivered or waiting is in `docs/ROADMAP.md`.

Three work items, in this order: **A** toolbar fits any width, **B** File menu, **C** formatting buttons (C1 alignment, C2 number format, C3 borders). Each ships as its own round with tests.

## What exists today (read from the code)

- Toolbar (`toolbar.dart`): one fixed `Row`, 48 px high: bold, italic, underline, strikethrough, text color, fill color, "Font..." button, spacer, Settings. It overflows on a phone.
- File menu (`app_menu_bar.dart`): New, Open..., Save only. Edit, View, Insert, Data, Tools, Help are plain text.
- Backend document routes: create, upload, open, rename, save, reload, close, delete. **No "save as" / copy route.** Rename and delete are refused while the file is open in a shared session.
- Cell style (`CellStyle`, `TextStyleSpec`): bold, italic, underline, strikethrough, font family, font size, color, background. **No alignment, number format or borders anywhere** (backend model, xlsx read/write, ops, client, grid).

---

## A. Toolbar fits any width

**Purpose:** every toolbar action is reachable at 360 px wide and above; nothing overflows.

**Inputs:** window width (any), selection state.

**Behavior:**
1. Buttons are grouped (text style, colors, font, settings).
2. When the groups don't fit, the toolbar scrolls horizontally (no hidden actions, no overflow stripe). Settings stays pinned at the end.
3. The "Font..." label is shortened to its icon below 600 px width; the tooltip keeps the full text.
4. Touch targets are at least 40 px.

**Edge cases:** width changes while open (rotation, window resize); RTL sheet (toolbar order does not flip, only the grid does); no selection (buttons disabled, as now); very large text scale (accessibility setting).

**Acceptance criteria:**
- Widget test at widths 320, 360, 600, 1200 with text scale 1.0 and 2.0: no `RenderFlex overflowed` error, every button findable and tappable.
- Existing toolbar tests still pass.

## B. File menu

**Purpose:** File menu offers the usual document actions.

| Item | Behavior |
|---|---|
| New | as now |
| Open... | as now |
| Save | as now; shows "Saved" when done (new) |
| Save as... | pick a new name; the document is saved first (so original and copy hold the same content), then copied under the new name, and the app switches to the copy |
| Rename... | new name for the open document; refused with a clear message while other people are in it |
| Close | saves, then returns to the empty state (no document) |
| Delete... | confirmation dialog naming the file; refused while other people are in it |

**Backend (B1, built):** the old rename and delete routes refuse any file open in a shared session, including the caller's own, and rename gives no reason when it fails. So three new session-aware routes: `POST /documents/save-as`, `POST /documents/rename-open`, `POST /documents/delete-open`. They check everything first, never overwrite, and refuse with a message safe to show. Rename and delete only work while the caller is alone in the document. If the rename fails after the session closed, the document is saved under its old name and the client opens it again. Delete removes the file first, so a failed delete loses nothing.

**Build steps:** B1 backend routes + tests (done), B2 client service/controller methods + tests, B3 menu items, dialogs, empty state + tests.

**Inputs:** file name (same validation as New: not empty, no path characters, `.xlsx` added if missing).

**Errors (designed, no raw server text):**
- Name already exists: "A document named X already exists. Choose another name."
- Open in a shared session: "Other people are working in this document. Ask them to leave first."
- Server unreachable: "Can't reach the server. Check the connection and try again."
- Each message has a recovery action (button or hint) and the technical detail goes to the log.

**Edge cases:** save as to the same name; rename to the same name; delete the only document; close with unsaved edits (save first, and if that fails, ask: Retry / Close anyway / Cancel); last-opened document pointer after delete/rename; two clients rename at once.

**Acceptance criteria:**
- Backend tests: save-as copies content and styles; refuses existing name; refuses invalid name; leaves original unchanged.
- Flutter tests: each action calls the right service method; each error message shows; delete needs confirmation; cancel does nothing.
- Manual: two windows, rename in A while B is in the document is refused with the message.

## C. Formatting buttons

Order: C1 alignment, C2 number format, C3 borders. Each needs the same chain: backend `CellStyle` field and validation, xlsx read/write, sheet defaults if applicable, collab op (`set_cell_style` already validates through `apply_patch`), client model, grid rendering, toolbar button.

### C1. Alignment and row height
- Horizontal alignment: left, center, right. Vertical alignment: top, middle, bottom. Explicit left/right mean physical sides, including in an RTL sheet.
- Toolbar: separate compact menus for horizontal and vertical alignment; each applies to the selected cells and can reset to the sheet default.
- Row height: drag a row header's bottom edge or use its context menu to enter a value from 16 to 500 display pixels. Unset rows use the 28-pixel grid default; saved workbooks use native Excel row heights.
- Text wrapping and automatic row-height fitting are not included yet; resizing is manual.
- Acceptance: alignment and row heights round-trip through .xlsx; invalid values are rejected; sorted/filtered rows keep their own heights.
- Live formatting operations and formatting undo/redo remain tracked in the collaboration follow-up below.

### C2. Number format
- Presets: General, Number (2 decimals), Percent, Currency, Date, Text. Plus custom format string later.
- Display only: the stored value never changes; formulas keep using the raw value.
- Edge: text in a number-formatted cell shows as is; formula errors show the error; very large and very small numbers; negative numbers; empty cells; Arabic-Indic digits (decision below).
- Acceptance: formatting table tests (value, format, expected text) for each preset including 0, negative, 1e15, 0.000001, empty, text, error; .xlsx round trip keeps the format code.

### C3. Borders
- Per cell: top, right, bottom, left, each with style (thin, medium, none) and color. Presets: all, outer, none.
- RTL: sides are physical.
- Edge: shared edge between two cells (the later write wins, stored on both so removal is clean); grid line color interaction; performance with 100k bordered cells.
- Acceptance: round trip through .xlsx; render test; remote sync; benchmark shows no regression on open of 10k rows.

---

## Impact analysis (rule 9)
- New style fields touch: `CellStyle`, `apply_patch`, `excel_storage.py` read/write, `set_cell_style` / `set_text_defaults` ops, `TextStyleSpec`, grid cell painting, copy/paste of styles, sort (styles must move with rows), undo snapshots, file size of the grid payload.
- Regression list for every round: formulas, bold/italic/colors, sort, filter, copy/paste, undo/redo, RTL, live sync, save/reopen.

## Decisions needed from you (proposed defaults in bold)
1. Toolbar below 600 px: **scroll sideways** (alternative: overflow "..." menu).
2. Close with failed save: **ask Retry / Close anyway / Cancel**.
3. Save as switches to the copy: **yes**.
4. Row height with wrap text: **manual row-height editing only; defer wrapping and automatic fit**.
5. Number format digits: **always Western digits (0-9)** (alternative: follow sheet direction).
6. Currency symbol: **a setting with a default of none** (alternative: fixed EGP).

## Definition of Done per round
Requirements met, tests written with the code, backend and Flutter suites green on your machine, regression list checked, no silent failures, this file and `docs/` updated, you accept it.

## D. Top menus (placeholders)

Every top menu (File, Edit, View, Insert, Data, Tools, Help) opens. Items whose features are not built yet are greyed out and do nothing; the list is `plannedMenuItems` in `app_menu_bar.dart`. When a feature is built its item is removed from that list and becomes a working item. The menu bar scrolls sideways instead of overflowing on a narrow screen.

## E. Server connection (address and token set after the build)

**Purpose.** One build works on any network; nothing can fall back to localhost.

**Inputs.** Server address, access token (optional), typed on the device.

**Behavior.**
1. Kept on the device, not on the server. With nothing saved the app shows "Connect to your Excelence server" (no default address). `--dart-define=API_BASE_URL` only pre-fills; the token is never compiled in.
2. Settings > Connection, the first-run screen and "Change server address" (shown when the server cannot be reached) share one form: **Test connection** and **Save/Connect**. Save checks the connection first; if the check fails it says why and the button becomes **Save anyway**.
3. Address rules: `http://` is added if missing; plain http needs a port; nothing may follow the port; `localhost`, `127.x.x.x`, `::1`, `0.0.0.0` are refused ("Use the network address of the PC that runs the server"). A saved address that breaks these rules is ignored.
4. Test results: connected / cannot reach / timed out (5 s) / token refused / not an Excelence server.
5. Saving a new address first saves the open document to the old server; if that fails the address is not changed and the user is told. Then the whole app is rebuilt against the new server.
6. Server: default host `0.0.0.0`; refuses to start on the network without a token (message says to run `setup`). `excelence-server setup | config show | config set | config unset | config token` change settings; `start`, `status` and `config show` print the address for the app (never localhost).

**Error/edge cases.** Empty address; localhost; no port; path after port; port out of range; wrong token; wrong server; server off; token too short (server side); settings file with a bad value (reported, nothing saved); setup cancelled (nothing changed); device cannot store the address (works for the session, asked again next start).

**Acceptance.** A fresh install contains no localhost address on the client or in the server's output; typing the address and token once connects; changing them in Settings reconnects without a restart; the server will not start on the network without a token.

**Known limits.** The token is stored in plain text on the device and travels over plain HTTP (trusted LAN). Edits that cannot be saved to the old server block an address change.

## F. Find the server on the network (BUILT - needs a test on a real network)

**Purpose.** A moved server (new PC, new IP) needs no change on any client.

**How.** The server answers a UDP "who is an Excelence server?" broadcast (default port 8765, `EXCELENCE_DISCOVERY_PORT`, can be turned off). The question carries a random number; the answer carries the server's name, its HTTP port and a proof that it knows the access token (an HMAC of that number), never the token itself. A client only accepts answers whose proof matches its own token, so a stranger on the Wi-Fi cannot collect tokens by pretending to be the server.

**Behavior.**
1. "Find server" button in the connection form and on the first-run screen: searches for 3 seconds, fills in the address of the single match, or lists several to pick from.
2. At start, if the saved address does not answer, the app searches by itself. One match: it keeps working and shows "Server found at <address>" with Keep / Ignore; the new address is saved only after Keep. No match: the usual "cannot reach" screen with Retry, Find server and Change server address.
3. Setup prints the one-time Windows firewall rule for UDP 8765 (needs administrator); without it the button reports "No server found" and the address can still be typed.

**Error/edge cases.** No reply; several servers; wrong token (silently ignored, reported as "no server found with this token"); broadcast blocked (guest Wi-Fi, other subnet, VPN); firewall closed; port in use; two servers with the same name.

**As built.** Server: `backend/discovery.py` (UDP responder thread, at most 20 answers a second, only started when the server listens on the network, has a token and discovery is on); settings `EXCELENCE_DISCOVERY` (on/off) and `EXCELENCE_DISCOVERY_PORT` (8765), also `config set discovery|discovery-port`. App: `core/connection/server_discovery.dart` (+ `discovery_io.dart`; the browser build cannot search); "Find server" in the connection form (token must be typed first) and `ServerFinderPanel` on the "No document open" screen, which searches once by itself and only switches after "Use it". Needs `flutter pub get` (new package `crypto`).

**Acceptance.** Move the server to another PC, open a client, press Find server: connected without typing an address. Tests: discovery message encode/decode, proof check, wrong token ignored, several answers, timeout.

## G. Offline editing, syncing later (PROPOSED - not built, confirm first)

**Purpose.** The app opens and works with the server switched off or out of reach; changes made meanwhile reach the server when it is back.

**Phases (each releasable):**
1. **Offline start.** Every opened document is kept on the device (last 5, setting). When the server cannot be reached, the app opens the last document from that copy, with a banner "Offline - changes will be sent when the server is back" and automatic retry every few seconds.
2. **Offline cell edits.** Values, formulas and formatting can be edited offline. Every change goes into a queue stored on the device (survives closing the app). When the server returns the queue is sent in order, in batches of up to 500; the banner shows progress; the queue is only cleared after the server accepts a batch.
3. **Conflicts.** If someone changed the same cell on the server meanwhile, the device's change wins (last writer wins) and the app lists the overwritten cells afterwards ("12 cells you changed replaced newer values; review"), so nothing is lost silently.
4. **Structure.** Inserting/deleting rows, columns and sheets, Save as, Rename and Delete stay disabled offline (greyed, with the reason) until they exist as live operations (roadmap 5b-5).

**Needs first (prerequisites on the server).** A document revision number that survives restarts; operations that record the value they replaced (also on the roadmap); a persistent operation log (today it is in memory and a restart loses it). Without them the client cannot tell what changed on the server while it was away.

**Error/edge cases.** Server never returns; app closed with a non-empty queue; two offline devices edit the same cell; document deleted or renamed on the server while offline; queue sent partly (batch fails half-way); disk full on the device; very large document (the 10,000 / 100,000 row targets apply to the cached copy); token changed while offline.

**Acceptance.** Switch the server off, start the app: the last document opens with the banner. Edit 100 cells, close and reopen the app (edits still there), switch the server on: all 100 arrive, the banner clears, a second device sees them. Same cell edited on the server and offline: the offline value wins and is listed.

**Size.** Phase 1 is moderate, phase 2 large, phases 3 and the server prerequisites large. Recommended as its own release after the first packaged version.

## H. Updates served by the server (PROPOSED - not built, confirm first)

**Purpose.** Publish a new client once, on the server; every Windows PC and Android phone fetches and installs it by itself. No copying files by hand.

**Must be part of the first packaged release**: a client without the updater cannot update itself later.

**Flow.**
1. On the server PC: `excelence-server publish-update --version 1.2.0 --build 7 --notes "..." --windows <zip of the Release folder> --android <apk>` copies the packages into the server's `updates` folder and writes a manifest (version, build number, notes, file name, size, SHA-256 per platform, minimum client build).
2. Server routes (behind the usual access token): `GET /updates/manifest`, `GET /updates/files/<name>`.
3. The app checks the manifest at start and on "Check for updates" (Settings > About); if the published build is newer: "Version 1.2.0 is available - Install now / Later" (with the notes). A manifest `minimum client build` above the app's own makes the update required (the app explains why and offers only Install).
4. Download shows progress; the file's SHA-256 is checked against the manifest; a bad or partial file is deleted and reported ("Download failed, nothing was changed. Try again.").
5. **Windows:** the zip is unpacked beside the app, a small helper waits for the app to close, copies the files over the install folder, and starts the new version. If the folder is not writable the user is told where and why.
6. **Android:** the APK is handed to the system installer (the user taps Install; Android asks once to allow installs from this app). It only installs over the existing app if signed with the **same release key**, so the APK must always be built with the same keystore (keep a backup of it).
7. The server itself is updated by hand on its PC (`excelence-server stop`, replace, `start`); a later step can automate it.

**Error/edge cases.** Server unreachable (skip silently, retry later); no update published; downloaded file truncated or altered; disk full; app opened from a read-only place; two updates published in a row; update published for one platform only; the user chooses Later (asked again at the next start, not more often); downgrade (never offered); phone on mobile data away from the LAN (no check).

**Trust.** Integrity is the SHA-256 in the manifest, delivered by your own server over the LAN with the access token. A stronger step, for later: sign every package with a key kept on the developer's PC and build the public key into the app, so even a tampered server cannot push code.

**Acceptance.** Publish build 2 on the server; a client running build 1 shows the offer, installs and restarts as build 2 with its saved address and token intact; a corrupted download is refused; a phone does the same with the APK. Tests: manifest read/write and the publish command, hash check, newer-build comparison, required-update rule, download failure handling.

**Phases (each releasable).** (1) Server: publish command, manifest and file routes - testable here. (2) App: check, offer, download, verify, Windows install. (3) Android install.
