# Excelence roadmap

Kept in step with what is built. "Delivered" means written and sent, not yet confirmed by a run on Zelium's machine.

## Verified on his machine
- Collaboration backend (stable ids, ops, op log, live layer), live cell edits between devices, "who is here".
- Phase 5b-4 (incoming cell changes applied directly), 4f (server save scheduler).
- UI round A: toolbar scrolls sideways, Font button icon-only below 600 px (checked on an Android phone).
- UI round B1 (backend save-as / rename-open / delete-open) and B2 (client methods).
- Android over Wi-Fi works (APK built with `--dart-define=API_BASE_URL=...`).

## Delivered, waiting for test results
- UI round B3: File menu actions with dialogs, friendly messages, "No document open" screen.
- Greyed placeholder items in every top menu (see `plannedMenuItems` in `app_menu_bar.dart`).

## Next, in order
1. **UI round C1 - alignment** (horizontal, vertical, wrap, auto row height), then **C2 number format**, then **C3 borders**. Requirements: `docs/UI_REQUIREMENTS.md`.
2. Phase 5b-5: row / column / sheet changes as live ops; a sheet per person instead of one shared active sheet.
3. Phase 5b-6: send and apply formatting ops in the app.
4. Ops record the values they replaced (needed before per-user undo).

## Open decisions
- A **Server address** field in Settings, so one APK works on any network and the token is not compiled in (not decided).
- Run the benchmark again with lxml installed (`benchmarks/benchmark_backend.py`) and report the 10k / 100k open times.
- Edits made while a device was offline were seen to arrive once it came back online. Unplanned; needs a proper test (conflicts, order, large batches) before it is relied on.

## Planned menu items (greyed out until built)
File: Import, Download as, Print. Edit: Find and replace, Select all, Clear formatting. View: Freeze rows and columns, Show gridlines, Zoom, Full screen. Insert: Chart, Image, Link, Comment. Data: Sort range, Create a filter, Data validation, Remove duplicates. Tools: Speech to text, Spell check. Help: Keyboard shortcuts, About.

Undo, Redo, Cut, Copy and Paste already work from the keyboard; wiring them into the Edit menu is a small later task.

## After the current version is released
Requirements are written before any of these are built.

**PC**
- Speech-to-text accessibility button, with a keyboard shortcut (PC only; mobile keyboards already offer dictation, revisit later).

**Mobile** (all mobile-specific work comes after this release)
- Touch gestures. Known problem from his phone test: drag-selecting cells does not work. Needs a design for select, extend selection, scroll and zoom by touch.

## Later
- Per-user undo through inverse operations (phase 6).
- Accounts, permissions, HTTPS; offline mode (phase 7).
- PyInstaller build never run.

## Known issues deferred (not started)
The Open dialog overflows with a long error and shows raw server HTML; every edit rewrites the whole worksheet at ~20k rows; row height is fixed; the font menu needs internet; the shared token is compiled into the client; last-opened document and preferences are stored server-wide; a sheet with no rows or a search with no matches shows the loading spinner.
