# Performance

Performance is a requirement here (rule 6), so it is measured, not guessed.

## How to measure

```
python benchmarks/benchmark_backend.py                 # 1,000 / 10,000 / 50,000 rows
python benchmarks/benchmark_backend.py 100000          # chosen sizes
```

It builds a workbook (10 columns of text, numbers and a few formulas) in a temporary folder and times what the
server does most. Times are medians, in milliseconds. **Run it on the device that will be the server**: the numbers
below come from a development sandbox, not from the target hardware, so compare the *shape* (how time grows
with rows) rather than the exact figures.

## Targets (decisions made earlier)

A change on another device within 500 ms on the LAN · 10,000 rows open in 3 s · 100,000 rows in 15 s · 500
changes per batch · 10 clients.

## Measured (sandbox)

| | 1,000 rows | 10,000 rows | 50,000 rows | before this round (10k / 50k) |
|---|---|---|---|---|
| open document | 155 | 1,560 | 9,319 | |
| build the grid data | 5 | 48 | 276 | |
| the data a client downloads (MB) | 0.2 | 2.2 | 11.0 | |
| **edit one cell** | **2** | **5** | **27** | 309 / 1,974 |
| **paste 500 cells** | **93** | **131** | **293** | 425 / 2,185 |
| insert a row | 25 | 339 | 2,142 | 332 / 1,865 |
| style 1,000 x 3 cells | 64 | 341 | 2,137 | 390 / 1,908 |
| save document | 136 | 994 | 5,248 | 993 / 5,743 |

Everything grows in direct proportion to the number of rows, except the two edits that were fixed.

## What was found, and what changed

**Why edits were slow:** after every change the document rewrote the *entire* worksheet from its data (all rows,
all cells), even when one cell changed. That was 99% of the time of an edit.

**The fix (`Document._sync_changed_rows`):** after any full write the document remembers that the worksheet
mirrors its data (same worksheet, row count and column names). While that is still true, a change that only
alters values writes just the changed rows, converting them exactly as the full write does, and leaves styles
alone (a value edit doesn't change them). If the worksheet is not known to match (the first edit after opening,
or anything that changed its shape), it falls back to the full rewrite, so it can only be skipped when it is
safe. Saving always rewrites the whole worksheet anyway, so even a wrong in-between state could never reach the
file.

**Proof:** `backend/tests/test_fast_value_sync.py` runs the old path (full rewrite, via
`fast_value_sync = False`) and the new path side by side on identical documents and demands identical worksheets
(every cell's value and type, fonts, fills) and identical grid data after every step: varied batches, long
random sequences (6 seeds x 40 steps), styles, inserts/deletes/renames, undo/redo, search and sort active,
save and reload. A deliberate sabotage of the fast path (writing to the wrong row) fails 7 of its 11 tests.
One side effect, harmless and arguably better: formatting the app doesn't model (a number format, a border)
now survives value edits instead of being wiped by the next full rewrite.

## Measured on the development PC (terminal, no debugger), 10,000 rows

| | ms | target |
|---|---|---|
| open document | 3,946 | 3,000 (missed) |
| build the grid data | 151 | |
| edit one cell | 15 | 500 (met) |
| paste 500 cells | 399 | 500 (met, narrowly) |
| insert a row | 864 | 500 (missed) |
| style 1,000 x 3 cells | 994 | 500 (missed) |
| save document (before the save change below) | 3,006 | holds the session lock |

(An earlier run through the VS Code debugger was 2-4 times slower; never benchmark under a debugger.) The
development PC is roughly 2.5 times slower than the sandbox on this Python-bound work, so scale the sandbox
table above accordingly.

## lxml: measured on the development PC (10,000 rows, terminal)

`pip install lxml` makes openpyxl parse and write faster, with no code change. Same machine, same run, before and after:

| | before | with lxml |
|---|---|---|
| open document | 4,649 | 3,422 (-26%) |
| insert a row | 1,196 | 785 (-34%) |
| style 1,000 x 3 cells | 1,289 | 860 (-33%) |
| edit a cell, then save | 3,535 | 2,072 (-41%) |
| insert a row, then save | 5,680 | 3,626 (-36%) |

It is now in `backend/requirements.txt`. (If it is missing openpyxl simply falls back to its slower parser.)
Not yet checked: the PyInstaller build with it (PyInstaller follows openpyxl's optional import, so it should be
bundled).

## The server decides when to save (backend/save_scheduler.py)

Even at about 2 s per save, a save that every client triggers after every pause in its typing would freeze a busy
document. Now the server decides, once for everybody:

* saved after **2 s of quiet** (the usual case);
* saved anyway once the oldest unsaved change is **30 s old** (so a crash loses at most about that much);
* never closer together than **4 times as long as the last save took** (and 2 s): a 2 s save happens at most every
  8 s, so saving can use at most about a fifth of the time;
* a document someone is working in (lock busy) is skipped and tried again a second later.

A client's autosave now sends `POST /documents/save?auto=true`. While the scheduler is running the server answers
at once (`deferred: true`, nothing written) and the scheduler saves when it is due. The Save command (no `auto`),
closing a document, the last person leaving and server shutdown still write immediately. Without a running
scheduler an `auto` request saves immediately, as before. The numbers are constants in `SaveScheduler`
(`debounce`, `max_wait`, `factor`, `min_interval`); say if they should be settings.

## Saving no longer rewrites the worksheet when it already holds everything

`Document.save_local` used to rewrite the whole worksheet (about 40% of a save) before writing the file. It now
skips that when the worksheet is *known current*: an earlier save wrote all of it, and since then there have
been only value-only edits (which update the worksheet in place). Any other change (structure, a width, rtl,
a style, text defaults, appearance, undo, a new sheet) turns the knowledge off until the next save rewrites in
full. The rule is deliberately conservative: it lives in the `modified` setter, which every editing path goes
through, so a future path that forgets to update the worksheet can only cost speed, never correctness.

Proof: the saved file (every cell's value, type, font and fill, column widths, direction, hidden defined names)
is compared with the old always-rewrite behaviour across a scripted sequence of every kind of change with saves
in between and 5 random mixes of 45 steps; counting tests pin exactly when a rewrite happens. A deliberate
"always skip" sabotage is caught by the counting tests, but not by the file comparison: every existing change
path already keeps the worksheet up to date by itself, so the save-time rewrite was redundant for all of them.
Effect: a save after editing a cell (what autosave does) drops by about the cost of the rewrite; what remains is
openpyxl writing the file.

## What is still slow, in order of how much it matters

1. **Writing the file during a save holds the session lock** (about 1.2 s per 10,000 rows on the development PC with
   lxml). Saves are now rare and spaced out (see above), so this is felt once per pause in typing, not once per
   client per pause. If it still matters: write the file from a copy outside the lock (a copy is itself costly).
2. **Insert/delete a row or column, styling a block:** still a full rewrite (about 340 ms at 10,000 rows, 2.1 s at
   50,000). Fine for small sheets; the next candidate if big sheets matter.
3. **Opening:** about 85% is openpyxl parsing the file (not our code). 100,000 rows will take roughly 19 s by
   extrapolation, over the 15 s target. **Worth trying first, no code change:** `pip install lxml`; openpyxl uses
   it for reading and writing when it is present. Re-run the benchmark before and after.
4. **The data a client downloads** (about 220 bytes per row: 2.2 MB at 10,000 rows): every reload and every
   document open transfers it. JSON compresses roughly ten-fold; adding gzip to the server (Starlette's
   `GZipMiddleware`, one line) would cut a reload over Wi-Fi from seconds to well under one. Not done yet
   because it changes every HTTP response, so it deserves its own test on a real device.
5. Reload mode (everything except a cell edit) fetches the whole sheet; the incremental apply in 5b-4/5b-5 is what
   removes that for edits, rows and columns.
