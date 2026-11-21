# Running the server in the background

By default the server runs in a terminal window and stops when the window is closed. These commands run it on its own instead.

## Requirements (what "done" means)

1. `start` launches the server without a terminal and returns; closing the window afterwards does not stop it.
2. `stop` shuts it down properly, so every open document is saved first; it is ended by force only if it does not exit in 20 seconds, and the message says so.
3. A second server is never started on top of a running one (one PID file, port checked first).
4. Every failure says what to do: port taken, bad setting, server died at start (shows the end of its output), no answer in time.
5. Settings survive closing the terminal (`excelence.env`), and the server can start by itself when you log in to Windows.
6. `status` can be used in scripts: exit code 0 when running, 1 when not.

## Commands

During development use `python server_entry.py <command>`; the packaged program is `excelence-server.exe <command>`.

| Command | What it does |
|---|---|
| *(none)* or `run` | run in this window, as before |
| `start` | run in the background, wait until it answers, print the addresses |
| `stop` | stop it (documents are saved first) |
| `restart` | stop, then start |
| `status` | running or not, PID, how long, addresses (exit code 0 / 1) |
| `logs [--lines N]` | the end of the server log (default 40 lines) |
| `autostart on` / `off` / `status` | start in the background when you log in to Windows |
| `config` | create `excelence.env` with every option commented out |

When the server listens on the network (`EXCELENCE_HOST=0.0.0.0`), `start` and `status` also print the address other devices should use, for example `http://192.168.1.20:8000`.

## Settings: `excelence.env`

Run `config` once, then edit the file next to the program. Lines are `KEY=value`; lines starting with `#` are ignored:

```
EXCELENCE_HOST=0.0.0.0
EXCELENCE_PORT=8000
EXCELENCE_ACCESS_TOKEN=choose-a-long-secret-here
EXCELENCE_DOCUMENTS_DIR=D:\Excelence\documents
```

A variable that is already set in the environment wins over the file. Run `restart` after changing it.

Speech transcription runs on the user's device with an offline Whisper model. The first use needs
an internet connection to download the roughly 460 MB model; subsequent transcription does not
send audio to this backend or require a speech API key.

## Files

| File | Meaning |
|---|---|
| `excelence.env` | settings (you create it with `config`) |
| `run\server.pid` | written by the running server; says which process it is |
| `run\server.stop` | created by `stop`; the server notices it and shuts down properly |
| `logs\server.out` | everything the background server prints (kept to about 5 MB, then rotated) |
| `logs\backend.log` | the server's own log |

When packaged these are next to `excelence-server.exe`; in development `excelence.env` and `run\` are in the project folder and the logs in `backend\logs\`.

## Start at Windows log-on

`excelence-server autostart on` adds a per-user entry (no administrator rights needed) that runs `start` when you log in. `autostart off` removes it. The server then reads `excelence.env`, so put the host, port and token there.

## Limits (be aware)

* It runs as **you**: logging out of Windows ends it (it comes back at the next log-on if autostart is on). Restarting or putting the PC to sleep stops it too.
* For a server that must run with nobody logged in, a Windows service would be needed. Not built.
* Two `start` commands within the first seconds (before the server has written its PID file) can briefly launch two processes; the second one fails with "port in use" and exits.
* The Windows-specific parts (detaching from the console, the log-on entry, ending a process by force) are written from the documentation and have not been run on Windows yet.

## Checking it by hand (Windows)

1. `python server_entry.py start` (or the exe). It should print `running in the background` and an address.
2. Close the terminal window. Open `http://localhost:8000/docs` in a browser: still there.
3. `python server_entry.py status` from a new window: running, with the PID.
4. Open a document in the app, edit a cell, then `stop`. Open the file: the edit is saved.
5. `status` again: not running (exit code 1).
6. `start`, then `start` again: the second says it is already running.
7. `autostart on`, log out and in: the server is running; `autostart off` afterwards.
