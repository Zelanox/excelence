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
