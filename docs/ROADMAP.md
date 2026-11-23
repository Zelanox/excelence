# Excelence roadmap

Kept in step with what is built. "Delivered" means written and sent, not yet confirmed by a run on Zelium's machine.

## Verified on his machine
- UI round B3 (File menu actions, friendly errors, "No document open" screen) and the greyed menu placeholders: visuals checked by hand, tests passed except one (fixed above).
- Collaboration backend (stable ids, ops, op log, live layer), live cell edits between devices, "who is here".
- Phase 5b-4 (incoming cell changes applied directly), 4f (server save scheduler).
- UI round A: toolbar scrolls sideways, Font button icon-only below 600 px (checked on an Android phone).
- UI round B1 (backend save-as / rename-open / delete-open) and B2 (client methods).
- Android over Wi-Fi works (APK built with `--dart-define=API_BASE_URL=...`).

## Delivered, waiting for test results
- Offline Whisper speech to text for PC (toolbar microphone, Tools menu item, Ctrl+Shift+M, and voice search). The multilingual small model supports Arabic, is downloaded once on first use (~460 MB), and audio is transcribed on-device. Arabic is the default recognition language. Dictated text lands in the cell editor; Enter keeps it, Esc discards it. Targets Windows and macOS; declines while a cell is already being edited (Windows voice typing, Win+H, works inside the editor). Live recognition still needs verification on the target machine.
- Fix: opening a document from the "No document open" screen now shows the spinner.

## Current focus: wrap up and package this version
Only speech to text was added before packaging (done, above). Then:
1. **Server that keeps running in the background** - delivered (`docs/BACKGROUND_SERVER.md`): start / stop / restart / status / logs, PID file, settings file `excelence.env`, optional start at Windows log-on. Tested in the sandbox including real detached processes on Linux; the Windows parts need his run.
2. Build the server as an executable (PyInstaller; never run yet) and check it starts from a clean folder.
3. Build the Windows app and the Android APK (with the server address; see "Open decisions").
4. Release checklist and a smoke test of the packaged version (create, edit, save, close, reopen; two devices).

## After packaging, in order
1. **UI round C1 - alignment and manual row height** delivered; wrap and auto-fit remain deferred. Then **C2 number format**, then **C3 borders**. Requirements: `docs/UI_REQUIREMENTS.md`.
2. Phase 5b-5: row / column / sheet changes as live ops; a sheet per person instead of one shared active sheet.
3. Phase 5b-6: send and apply formatting ops in the app.
4. Ops record the values they replaced (needed before per-user undo).

## Open decisions
- ~~A Server address field in Settings~~ - decided and built (see docs/UI_REQUIREMENTS.md, section E): address and token are entered in the app, kept on the device, no localhost default; server defaults to 0.0.0.0 and refuses to start without a token.
- Run the benchmark again with lxml installed (`benchmarks/benchmark_backend.py`) and report the 10k / 100k open times.
- Edits made while a device was offline were seen to arrive once it came back online. Unplanned; needs a proper test (conflicts, order, large batches) before it is relied on.

## Planned menu items (greyed out until built)
File: Import, Download as, Print. Edit: Find and replace, Select all, Clear formatting. View: Freeze rows and columns, Show gridlines, Zoom, Full screen. Insert: Chart, Image, Link, Comment. Data: Sort range, Create a filter, Data validation, Remove duplicates. Tools: Speech to text, Spell check. Help: Keyboard shortcuts, About.

Undo, Redo, Cut, Copy and Paste already work from the keyboard; wiring them into the Edit menu is a small later task.

## After the current version is released
Requirements are written before any of these are built.

**PC**
- Speech to text improvements: choice of language (Arabic), dictating while a cell is being edited, live partial text. (The first version is delivered; mobile keyboards already offer dictation, revisit later.)

**Mobile** (all mobile-specific work comes after this release)
- Touch gestures. Known problem from his phone test: drag-selecting cells does not work. Needs a design for select, extend selection, scroll and zoom by touch.

## Later
- Per-user undo through inverse operations (phase 6).
- Accounts, permissions, HTTPS (phase 7).
- **Find server on the network** (requirements F): built, waiting for a real-network test. **Offline editing** (requirements G, phases 1-4): confirmed, after the first packaged release; needs the server prerequisites listed there first.
- PyInstaller build never run.

## Known issues deferred (not started)
The Open dialog overflows with a long error and shows raw server HTML; every edit rewrites the whole worksheet at ~20k rows; text wrapping and automatic row-height fitting are not implemented; the font menu needs internet; the shared token is compiled into the client; last-opened document and preferences are stored server-wide; a sheet with no rows or a search with no matches shows the loading spinner.
