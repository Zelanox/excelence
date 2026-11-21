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

The first time, Windows Firewall asks whether to allow it: allow **Private networks**.

**Before the first start, run the setup** (it asks for an access token and port, saves them, and
prints the address and token to type into each device):

```
excelence-server.exe setup
```

The server listens on the network by default and **refuses to start without an access token**.
To see the address and token again later: `excelence-server.exe config show`.

To keep it running after the window is closed, use the commands in
[BACKGROUND_SERVER.md](BACKGROUND_SERVER.md): `excelence-server.exe start`, `stop`, `status`, and
`autostart on` to start it when you log in. Put the settings above in `excelence.env` (create it
with `excelence-server.exe config`) instead of `set` lines, so they survive.

> `run_server.spec` and `dist\run_server.exe` in the project are an older one-file build. Build
> with the `pyinstaller` command above (it uses `server_entry.py`, which now also understands
> these commands).

## 2. The client (Windows desktop app)

On the build machine (needs Flutter and Visual Studio with the "Desktop development with
C++" workload), from `frontend\`:

```
flutter build windows --release
```

No address or token is built in. Copy the **whole folder** `build\windows\x64\runner\Release\`
to the other machine and run the `.exe` inside it. On first start the app asks for the **server
address** (`http://<server PC's network address>:8000`) and the **access token**; both are kept on
that device and can be changed later in **Settings > Connection**. `localhost` is refused on
purpose, also on the server PC: use its network address. A desktop app isn't a browser, so the
server's CORS settings don't apply to it.

If it won't start and complains about a missing `VCRUNTIME140.dll` or `MSVCP140.dll`, install
Microsoft's "Visual C++ Redistributable (x64)" on that machine - most Windows 10/11 machines
already have it.

(For a *web* client instead, `flutter build web`, serve `build\web` from any static file
server, and list that address in `EXCELENCE_ALLOWED_ORIGINS` on the server.)

The Android APK is built the same way (`flutter build apk`) and is configured on the phone in the
same screen, so one APK works on any network.

## 3. Everything on one machine

Run `excelence-server.exe setup`, start the server, then enter the PC's own network address
(shown by `excelence-server.exe config show`) in the app. There is no localhost shortcut.

For development only, `--dart-define=API_BASE_URL=http://192.168.1.20:8000` pre-fills the address
on a device that has none saved. The token is never built in.

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
* **401 / "Missing or invalid access token"**: the token entered in the app (Settings >
  Connection) doesn't match the server's. See it with `excelence-server.exe config show`.
* **"The server listens on the network but has no access token"**: run
  `excelence-server.exe setup`.
* **Size**: expect roughly 150-250 MB for the server (it bundles Python, pandas and numpy).
