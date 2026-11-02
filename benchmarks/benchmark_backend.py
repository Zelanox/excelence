"""How fast is the backend at different document sizes?

Run from the project root:

    python benchmarks/benchmark_backend.py            # 1,000 / 10,000 / 50,000 rows
    python benchmarks/benchmark_backend.py 100000     # chosen sizes

For each size it builds a workbook (10 columns of text, numbers and a few
formulas), then times what the app does most: opening, building the data the
client downloads (and how big that is), one cell edit, a 500-cell paste, a
row insert and delete, styling a block, saving. Times are the median of a few
runs, in milliseconds. Compare them with the targets in docs/COLLABORATION.md
(a change on another device within 500 ms; 10,000 rows open in 3 s).

Numbers depend on the machine, so run it on the device that will be the
server. It uses a temporary folder and touches none of your documents.
"""

import json
import os
import statistics
import sys
import tempfile
import time

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))

from openpyxl import Workbook                                  # noqa: E402

from backend.collab.operations import apply_batch, parse_batch  # noqa: E402
from backend.controller.controller import Controller            # noqa: E402
from backend.document.document import Document                  # noqa: E402
from backend.network.client import NetworkClient                # noqa: E402
from backend.storage.excel_storage import ExcelStorage          # noqa: E402
from backend.utils.config import SERVER_IP, SERVER_PORT         # noqa: E402

COLUMNS = 10


def build_workbook(path: str, rows: int) -> None:
    workbook = Workbook(write_only=True)
    sheet = workbook.create_sheet("Sheet1")
    sheet.append([f"Column{i + 1}" for i in range(COLUMNS)])

    for r in range(rows):
        sheet.append([
            f"name {r}", r, r * 1.5, f"city {r % 50}", r % 7,
            "yes" if r % 2 else "no", f"note about row {r}", r % 1000, f"code-{r % 97}",
            f"=B{r + 2}+C{r + 2}" if r % 20 == 0 else r * 3,
        ])

    workbook.save(path)


def open_controller(folder: str, name: str) -> Controller:
    document = Document(ExcelStorage(), NetworkClient(SERVER_IP, SERVER_PORT))
    document.documents_folder = folder
    controller = Controller(document)

    assert controller.open_document(name), "could not open the benchmark workbook"
    return controller


def timed(function, repeat: int = 3) -> float:
    """Median milliseconds of ``function`` over ``repeat`` runs."""
    runs = []

    for _ in range(repeat):
        started = time.perf_counter()
        function()
        runs.append((time.perf_counter() - started) * 1000)

    return statistics.median(runs)


def batch(sheet_id: str, *ops, number: int = 0) -> dict:
    return {"client_batch_id": f"bench-{number}", "base_revision": 0, "sheet_id": sheet_id, "ops": list(ops)}


def measure(rows: int) -> dict[str, float]:
    results: dict[str, float] = {}

    with tempfile.TemporaryDirectory() as folder:
        path = os.path.join(folder, "bench.xlsx")
        build_workbook(path, rows)
        results["file size (MB)"] = os.path.getsize(path) / 1_000_000

        started = time.perf_counter()
        controller = open_controller(folder, "bench.xlsx")
        results["open document"] = (time.perf_counter() - started) * 1000

        data = controller.grid_data()
        results["build grid data"] = timed(controller.grid_data)
        results["payload JSON (MB)"] = len(json.dumps(
            {"headers": data.headers, "rows": data.rows, "row_ids": data.row_ids, "column_ids": data.column_ids},
            default=str,
        )) / 1_000_000
        results["serialize payload"] = timed(lambda: json.dumps(
            {"headers": data.headers, "rows": data.rows, "row_ids": data.row_ids, "column_ids": data.column_ids},
            default=str,
        ))

        sheet_id = data.sheet_id
        rows_ids, columns = data.row_ids, data.column_ids
        counter = iter(range(1, 10_000))

        def one_cell():
            apply_batch(controller, parse_batch(batch(
                sheet_id,
                {"op": "set_cells", "cells": [{"row": rows_ids[rows // 2], "column": columns[0], "value": "edited"}]},
                number=next(counter),
            )))

        results["edit 1 cell (op)"] = timed(one_cell)

        def five_hundred_cells():
            cells = [
                {"row": rows_ids[i % rows], "column": columns[1 + i % 3], "value": str(i)}
                for i in range(500)
            ]
            apply_batch(controller, parse_batch(batch(
                sheet_id, {"op": "set_cells", "cells": cells}, number=next(counter),
            )))

        results["paste 500 cells (op)"] = timed(five_hundred_cells)

        def insert_and_delete_row():
            apply_batch(controller, parse_batch(batch(
                sheet_id, {"op": "insert_row", "before": rows_ids[rows // 2]}, number=next(counter),
            )))

        results["insert a row (op)"] = timed(insert_and_delete_row)

        def style_block():
            apply_batch(controller, parse_batch(batch(
                sheet_id,
                {"op": "set_cell_style", "ranges": [{
                    "start_row": rows_ids[0], "end_row": rows_ids[min(rows, 1000) - 1],
                    "start_column": columns[0], "end_column": columns[2],
                }], "style": {"bold": True}},
                number=next(counter),
            )))

        results["style 1,000 x 3 cells (op)"] = timed(style_block)
        # What autosave does while somebody types: an edit, then a save.
        def edit_then_save():
            one_cell()
            controller.save_document()

        results["edit a cell, then save"] = timed(edit_then_save)

        # A save after a change of structure (the whole worksheet is written).
        def structure_then_save():
            insert_and_delete_row()
            controller.save_document()

        results["insert a row, then save"] = timed(structure_then_save, repeat=2)

    return results


def main() -> None:
    sizes = [int(arg) for arg in sys.argv[1:]] or [1_000, 10_000, 50_000]
    table = {size: measure(size) for size in sizes}
    labels = list(next(iter(table.values())))

    print()
    print(f"{'':32}" + "".join(f"{size:>14,} rows" for size in sizes))

    for label in labels:
        cells = "".join(f"{table[size][label]:>18,.1f}" for size in sizes)
        print(f"{label:32}{cells}")

    print("\nTimes in milliseconds unless the label says otherwise.")


if __name__ == "__main__":
    main()
