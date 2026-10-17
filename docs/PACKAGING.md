# Packaging Excelence to try it on another machine

Goal: run the server and the client on a machine that has **no Python, no Flutter and no
Visual Studio**. Those are needed only on the machine that *builds* the packages.

> The server package below has **not been built or run by the person who wrote these
> steps** (the environment had no PyInstaller). The code it depends on - where it stores
> data and logs, how it starts, the first-run document - was tested by simulating a frozen
> process. Expect to fix a missing module or two on the first build (see "If it fails").

## 1. The server (`excelence-server`)

On the build machine (Windows, same version of Python you develop with), from the
project root - the folder that contains `backend\`:

```
pip install pyinstaller
pyinstaller --noconfirm --onedir --name excelence-server ^
  --paths . ^
  --collect-submodules uvicorn ^
  --collect-submodules websockets ^
  --collect-submodules backend ^
  server_entry.py
```

The result is the folder `dist\excelence-server\`. Copy **the whole folder** to the other
machine and run `excelence-server.exe`.

Why these choices:

* **`server_entry.py`, not `-m backend.run_server`**: PyInstaller wants a plain script. It just
  calls the real runner.
* **`--onedir`, not `--onefile`**: starts faster, doesn't unpack to a temp folder on every
  launch, and is less likely to be flagged by antivirus. (Data would survive either way.)
* **`--collect-submodules uvicorn`**: uvicorn picks its components (HTTP protocol, event loop,
  logging) by *name* at run time, which PyInstaller can't see. Without this the exe starts and
  then fails with "No module named ...".
* **Windows only builds Windows**: build the server on Windows to run it on Windows.

### Where things live

Next to `excelence-server.exe`:

| Folder | Contents |
|---|---|
| `data\documents\` | your workbooks (created on first run; a blank `test.xlsx` is added if the folder is empty) |
| `logs\backend.log` | the server log - look here first if something goes wrong |

Move the documents elsewhere with `EXCELENCE_DOCUMENTS_DIR`.

### Running it

Same machine as the client - just run the exe. For other machines to reach it:

```
set EXCELENCE_HOST=0.0.0.0
set EXCELENCE_ACCESS_TOKEN=choose-a-long-secret-here
excelence-server.exe
```

The first time, Windows Firewall asks whether to allow it: allow **Private networks**. The
server prints a warning if it is reachable from the network without a token.

## 2. The client (Windows desktop app)

On the build machine (needs Flutter and Visual Studio with the "Desktop development with
C++" workload), from `frontend\`:

```
flutter build windows --release ^
  --dart-define=API_BASE_URL=http://192.168.1.20:8000 ^
  --dart-define=API_TOKEN=choose-a-long-secret-here
```

Use the **server's** address and the same token. Copy the **whole folder**
`build\windows\x64\runner\Release\` to the other machine and run the `.exe` inside it. A
desktop app isn't a browser, so the server's CORS settings don't apply to it.

If it won't start and complains about a missing `VCRUNTIME140.dll` or `MSVCP140.dll`, install
Microsoft's "Visual C++ Redistributable (x64)" on that machine - most Windows 10/11 machines
already have it.

(For a *web* client instead, `flutter build web` with the same `--dart-define` flags, serve
`build\web` from any static file server, and list that address in `EXCELENCE_ALLOWED_ORIGINS`
on the server.)

## 3. Everything on one machine

Run `excelence-server.exe`, then the client built *without* `--dart-define` - it talks to
`http://localhost:8000` by default.

## If it fails

* **Window flashes and closes**: run it from a Command Prompt (`cmd`) so the error stays on
  screen, and read `logs\backend.log`.
* **`ModuleNotFoundError: No module named 'X'`**: add `--hidden-import X` to the
  `pyinstaller` command and rebuild.
* **"Configuration error: ..."**: one of the `EXCELENCE_*` variables is wrong; the message says
  which.
* **Antivirus quarantines it**: unsigned PyInstaller programs are sometimes flagged. Add an
  exclusion for the folder.
* **The client shows a spinner and nothing else**: it can't reach the server. Check the address
  and port, that the server is running, and that the firewall allows it.
* **401 / "Missing or invalid access token"**: the client's `API_TOKEN` doesn't match the
  server's `EXCELENCE_ACCESS_TOKEN`.
* **Size**: expect roughly 150-250 MB for the server (it bundles Python, pandas and numpy).
