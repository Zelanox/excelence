"""A value-only edit updates just the changed worksheet rows (Document._sync_changed_rows)
instead of rewriting the whole worksheet. These tests run the OLD behaviour (a full
rewrite, switched on by fast_value_sync = False) and the new one side by side on the
same document and demand identical worksheets after every step.

Plain functions like the other tests here; each builds its own workbooks in a temp folder.
"""

import os
import random
import tempfile

from openpyxl import load_workbook

from backend.tests.test_text_styles import make_controller

ROWS = [
    ["Alice", 25, 90.5, "x"],
    ["Bob", 30, 85, ""],
    ["Charlie", 22, 95, "z"],
    ["Dana", 41, 70, "w"],
    ["Eve", 19, 60, "v"],
    ["Fay", 33, 77, "u"],
]
HEADER = ("Name", "Age", "Score", "Note")


def pair(folder: str):
    """The same document twice: first rewritten fully on every edit (the old way), then the new way."""
    a_folder, b_folder = os.path.join(folder, "a"), os.path.join(folder, "b")
    os.makedirs(a_folder)
    os.makedirs(b_folder)

    old = make_controller(a_folder, rows=ROWS, header=HEADER)
    new = make_controller(b_folder, rows=ROWS, header=HEADER)
    old.document.fast_value_sync = False

    return old, new


def color_of(color):
    return None if color is None else str(color.rgb)


def snapshot(controller, styles=False):
    """Everything the worksheet holds: each cell's value and type (and its font and fill)."""
    document = controller.document
    cells = []

    for row in document.sheet.iter_rows():
        line = []

        for cell in row:
            entry = (cell.value, cell.data_type)

            if styles:
                fill = cell.fill.fgColor.rgb if cell.fill is not None and cell.fill.fill_type else None
                entry += (cell.font.b, cell.font.i, cell.font.sz, color_of(cell.font.color), str(fill))

            line.append(entry)

        cells.append(line)

    return cells, document.df.where(document.df.notna(), None).values.tolist(), list(map(str, document.df.columns))


def same(old, new, styles=False, note=""):
    assert snapshot(old, styles) == snapshot(new, styles), note
    assert old.grid_data().rows == new.grid_data().rows, note


def both(old, new, method, *args):
    results = (getattr(old, method)(*args), getattr(new, method)(*args))
    assert results[0] == results[1], (method, args, results)
    return results[0]


def test_value_edits_give_the_same_worksheet_as_a_full_rewrite():
    with tempfile.TemporaryDirectory() as folder:
        old, new = pair(folder)

        batches = [
            [(0, 0, "Alicia")],                                      # first edit: always a full rewrite
            [(1, 1, "31")],
            [(2, 2, "=B1+C1")],
            [(0, 3, "")],                                            # clear a cell
            [(3, 0, "007"), (4, 0, "1e3"), (5, 0, "  padded  ")],    # text that looks like numbers
            [(0, 1, "-5.25"), (1, 1, "1000000000000")],
            [(2, 0, "سلمى أحمد"), (3, 3, "😀")],
            [(4, 1, "abc")],                                         # text into a number column
            [(4, 1, "12")],                                          # and back
            [(5, 2, "")],                                            # clear in a numeric column
            [(0, 0, "a"), (0, 0, "b"), (0, 0, "c")],                 # the same cell three times in one batch
            [(r, c, f"{r}-{c}") for r in range(6) for c in range(4)],  # the whole sheet
        ]

        for number, edits in enumerate(batches):
            both(old, new, "edit_cells", edits)
            same(old, new, note=f"after batch {number}: {edits}")


def test_single_cell_edits_match_too():
    with tempfile.TemporaryDirectory() as folder:
        old, new = pair(folder)

        for row, column, value in [(0, 0, "x"), (1, 1, "9"), (2, 2, "=A1"), (3, 1, ""), (5, 0, "end")]:
            both(old, new, "edit_cell", row, column, value)
            same(old, new, note=f"{(row, column, value)}")


def test_random_edit_sequences_match_a_full_rewrite():
    pool = ["", "0", "1", "42", "-7", "3.14", "text", "A B", "=A1", "=B2+1", "007", "سلام", "x" * 40, "1e3", "TRUE"]

    for seed in range(6):
        generator = random.Random(seed)

        with tempfile.TemporaryDirectory() as folder:
            old, new = pair(folder)

            for step in range(40):
                edits = [
                    (generator.randrange(len(ROWS)), generator.randrange(len(HEADER)), generator.choice(pool))
                    for _ in range(generator.randint(1, 5))
                ]
                both(old, new, "edit_cells", edits)
                same(old, new, note=f"seed {seed}, step {step}: {edits}")


def test_text_styles_survive_value_edits_exactly_as_with_a_full_rewrite():
    with tempfile.TemporaryDirectory() as folder:
        old, new = pair(folder)

        both(old, new, "set_text_defaults", {"font_size": 13.0, "italic": True}, None)
        both(old, new, "set_cell_style_ranges", [(0, 0, 2, 1)], {"bold": True, "color": "FF0000", "background": "FFFF00"}, None)
        same(old, new, styles=True, note="after styling")

        for edits in ([(0, 0, "styled")], [(5, 3, "plain")], [(1, 1, "9"), (2, 0, "")], [(0, 0, "again")]):
            both(old, new, "edit_cells", edits)
            same(old, new, styles=True, note=f"{edits}")


def test_edits_between_structural_changes_undo_and_redo_match():
    with tempfile.TemporaryDirectory() as folder:
        old, new = pair(folder)

        steps = [
            ("edit_cells", [(0, 0, "one")]),
            ("edit_cells", [(1, 1, "2")]),
            ("insert_row", 2),
            ("edit_cells", [(2, 0, "inserted")]),
            ("edit_cells", [(6, 3, "last")]),
            ("delete_row", 0),
            ("edit_cells", [(0, 1, "77")]),
            ("insert_column", "Extra", 1),
            ("edit_cells", [(0, 1, "extra"), (1, 2, "30")]),
            ("rename_column", "Extra", "Renamed"),
            ("edit_cells", [(2, 1, "after rename")]),
            ("delete_column", "Note"),
            ("edit_cells", [(3, 1, "after delete")]),
            ("undo",),
            ("edit_cells", [(1, 0, "after undo")]),
            ("undo",),
            ("undo",),
            ("redo",),
            ("edit_cells", [(0, 0, "after redo")]),
        ]

        for number, (method, *args) in enumerate(steps):
            both(old, new, method, *args)
            same(old, new, note=f"step {number}: {method} {args}")


def test_edits_through_a_search_and_a_sort_match():
    with tempfile.TemporaryDirectory() as folder:
        old, new = pair(folder)
        both(old, new, "edit_cells", [(0, 0, "warm up")])

        both(old, new, "search", "a")
        for edits in ([(0, 1, "100")], [(1, 0, "viewed")]):
            both(old, new, "edit_cells", edits)
            same(old, new, note=f"search: {edits}")

        both(old, new, "clear_search")
        both(old, new, "sort", [{"column": "Age", "ascending": False}])
        for edits in ([(0, 3, "top")], [(5, 3, "bottom")]):
            both(old, new, "edit_cells", edits)
            same(old, new, note=f"sort: {edits}")


def test_a_saved_and_reloaded_file_is_the_same_either_way():
    with tempfile.TemporaryDirectory() as folder:
        old, new = pair(folder)

        for edits in ([(0, 0, "first")], [(1, 1, "50")], [(2, 2, "=B1+1")], [(3, 3, "")], [(4, 0, "سلام")]):
            both(old, new, "edit_cells", edits)

        both(old, new, "save_document")

        def contents(controller):
            workbook = load_workbook(controller.document._resolve_path(controller.document.filename))
            return [[cell.value for cell in row] for row in workbook.active.iter_rows()]

        assert contents(old) == contents(new)
        assert contents(new)[1][0] == "first"


def count_full_rewrites(controller):
    """Count how often the whole worksheet is rewritten from now on."""
    document = controller.document
    counter = {"full": 0}
    original = type(document)._sync_active_sheet

    def counting(self):
        counter["full"] += 1
        return original(self)

    document._sync_active_sheet = counting.__get__(document)
    return counter


def test_only_the_first_edit_rewrites_everything_and_a_change_of_shape_does_it_once_more():
    with tempfile.TemporaryDirectory() as folder:
        controller = make_controller(folder, rows=ROWS, header=HEADER)
        counter = count_full_rewrites(controller)

        controller.edit_cells([(0, 0, "a")])
        assert counter["full"] == 1                      # nothing known about the worksheet yet

        controller.edit_cells([(1, 1, "2")])
        controller.edit_cells([(2, 2, "3"), (3, 3, "4")])
        assert counter["full"] == 1                      # now only the changed rows are written

        controller.insert_row(1)
        assert counter["full"] == 2

        controller.edit_cells([(0, 0, "b")])
        assert counter["full"] == 2

        controller.delete_column("Note")
        controller.edit_cells([(0, 0, "c")])
        assert counter["full"] == 3


def test_when_the_worksheet_is_not_known_to_match_everything_is_rewritten():
    with tempfile.TemporaryDirectory() as folder:
        controller = make_controller(folder, rows=ROWS, header=HEADER)
        counter = count_full_rewrites(controller)
        controller.edit_cells([(0, 0, "a")])
        controller.edit_cells([(1, 1, "2")])
        assert counter["full"] == 1

        controller.document._worksheet_state = None
        controller.edit_cells([(2, 2, "3")])

        assert counter["full"] == 2

        controller.edit_cells([(3, 3, "4")])             # known again after the rewrite
        assert counter["full"] == 2


def test_a_worksheet_that_changed_shape_behind_its_back_is_rewritten():
    with tempfile.TemporaryDirectory() as folder:
        controller = make_controller(folder, rows=ROWS, header=HEADER)
        counter = count_full_rewrites(controller)
        controller.edit_cells([(0, 0, "a")])

        # Pretend another path swapped the worksheet for a different one.
        document = controller.document
        document._worksheet_state = (object(), *document._worksheet_state[1:])
        controller.edit_cells([(1, 1, "2")])

        assert counter["full"] == 2


def test_the_fast_path_leaves_formatting_it_does_not_know_about_alone():
    with tempfile.TemporaryDirectory() as folder:
        controller = make_controller(folder, rows=ROWS, header=HEADER)
        controller.edit_cells([(0, 0, "warm up")])                      # a full rewrite: the worksheet is now known

        cell = controller.document.sheet.cell(row=3, column=3)
        cell.number_format = "0.00%"                                    # something the app does not model

        controller.edit_cells([(1, 2, "0.5")])                          # row 1 -> worksheet row 3

        assert controller.document.sheet.cell(row=3, column=3).value in (0.5, "0.5")
        assert controller.document.sheet.cell(row=3, column=3).number_format == "0.00%"


# ----------------------------------------------------------------------
# Saving: the worksheet is not rewritten again when it is known to be current
# ----------------------------------------------------------------------

def saved_file(controller):
    """What a saved file holds: per sheet every cell's value, type, font and fill, the column widths and
    direction, and every defined name (the text-style defaults and appearance are stored in hidden ones)."""
    document = controller.document
    workbook = load_workbook(document._resolve_path(document.filename))
    sheets = {}

    for worksheet in workbook.worksheets:
        cells = []

        for row in worksheet.iter_rows():
            line = []

            for cell in row:
                fill = cell.fill.fgColor.rgb if cell.fill is not None and cell.fill.fill_type else None
                line.append((cell.value, cell.data_type, cell.font.b, cell.font.i, cell.font.sz, color_of(cell.font.color), str(fill)))

            cells.append(line)

        widths = {key: round(dimension.width or 0, 3) for key, dimension in worksheet.column_dimensions.items()}
        names = {name: defined.attr_text for name, defined in worksheet.defined_names.items()}
        sheets[worksheet.title] = (cells, widths, worksheet.sheet_view.rightToLeft, names)

    return sheets, {name: defined.attr_text for name, defined in workbook.defined_names.items()}


def count_worksheet_writes(controller):
    counter = {"writes": 0}
    storage = controller.document.storage
    original = storage.write_sheet

    def counting(sheet, dataframe):
        counter["writes"] += 1
        return original(sheet, dataframe)

    storage.write_sheet = counting
    return counter


def rewrites_during_save(controller, counter):
    """How many times saving rewrote the worksheet (0 = skipped)."""
    before = counter["writes"]
    assert controller.save_document() is True
    return counter["writes"] - before


def test_a_save_after_only_value_edits_does_not_rewrite_the_worksheet():
    with tempfile.TemporaryDirectory() as folder:
        controller = make_controller(folder, rows=ROWS, header=HEADER)
        counter = count_worksheet_writes(controller)

        controller.edit_cells([(0, 0, "a")])
        assert rewrites_during_save(controller, counter) == 1        # nothing is known yet: write everything

        controller.edit_cells([(1, 1, "2")])
        controller.edit_cells([(2, 2, "3")])
        assert rewrites_during_save(controller, counter) == 0        # only value edits since: skipped
        assert rewrites_during_save(controller, counter) == 0        # nothing changed at all

        controller.set_column_width("Name", 30)
        assert rewrites_during_save(controller, counter) == 1        # a width is not a value edit

        controller.edit_cells([(0, 0, "b")])
        assert rewrites_during_save(controller, counter) == 0        # current again after that rewrite

        controller.insert_row(0)
        assert rewrites_during_save(controller, counter) == 1

        controller.edit_cells([(0, 0, "c")])
        controller.undo()
        assert rewrites_during_save(controller, counter) == 1        # undo is not a value edit either


def test_every_other_kind_of_change_makes_the_next_save_rewrite_the_worksheet():
    changes = {
        "insert_column": lambda c: c.insert_column("New", 1),
        "delete_column": lambda c: c.delete_column("Note"),
        "rename_column": lambda c: c.rename_column("Note", "Remark"),
        "delete_row": lambda c: c.delete_row(0),
        "column width": lambda c: c.set_column_width("Age", 22),
        "rtl": lambda c: c.set_rtl(True),
        "cell style": lambda c: c.set_cell_style_ranges([(0, 0, 1, 1)], {"bold": True}, None),
        "text defaults": lambda c: c.set_text_defaults({"font_size": 15.0}, None),
        "appearance": lambda c: c.set_appearance({"banding": True}, None),
        "add sheet": lambda c: c.add_sheet("Another"),
    }

    for name, change in changes.items():
        with tempfile.TemporaryDirectory() as folder:
            controller = make_controller(folder, rows=ROWS, header=HEADER)
            counter = count_worksheet_writes(controller)
            controller.edit_cells([(0, 0, "warm up")])
            rewrites_during_save(controller, counter)
            controller.edit_cells([(1, 1, "9")])
            assert rewrites_during_save(controller, counter) == 0, name

            assert change(controller) is not False, name

            assert rewrites_during_save(controller, counter) == 1, name


def test_the_saved_file_is_the_same_with_and_without_skipping_the_rewrite():
    with tempfile.TemporaryDirectory() as folder:
        old, new = pair(folder)
        first = new.document.workbook.sheetnames[0]

        steps = [
            ("edit_cells", [(0, 0, "a")]), ("save_document",),
            ("edit_cells", [(1, 1, "2")]), ("edit_cells", [(2, 3, "")]), ("save_document",),
            ("set_column_width", "Name", 31), ("edit_cells", [(0, 1, "7")]), ("save_document",),
            ("set_rtl", True), ("edit_cells", [(3, 0, "rtl")]), ("save_document",),
            ("set_cell_style_ranges", [(0, 0, 2, 1)], {"bold": True, "color": "FF0000"}, None),
            ("edit_cells", [(0, 0, "styled again")]), ("save_document",),
            ("set_text_defaults", {"font_size": 14.0, "italic": True}, None),
            ("edit_cells", [(4, 2, "=A1+1")]), ("edit_cells", [(5, 0, "x")]), ("save_document",),
            ("set_appearance", {"banding": True, "banding_color": "DDEEFF"}, None), ("save_document",),
            ("edit_cells", [(0, 3, "after appearance")]), ("save_document",),
            ("insert_row", 1), ("edit_cells", [(1, 0, "new row")]), ("save_document",),
            ("rename_column", "Note", "Remark"), ("edit_cells", [(0, 3, "renamed")]), ("save_document",),
            ("edit_cells", [(2, 0, "before undo")]), ("undo",), ("edit_cells", [(2, 1, "5")]), ("save_document",),
            ("add_sheet", "Second"), ("edit_cells", [(0, 0, "on the second sheet")]), ("save_document",),
            ("set_sheet", first), ("edit_cells", [(0, 0, "back on the first")]), ("save_document",),
            ("delete_column", "Remark"), ("edit_cells", [(0, 0, "after delete")]), ("save_document",),
        ]

        for number, (method, *args) in enumerate(steps):
            both(old, new, method, *args)

            if method == "save_document":
                assert saved_file(old) == saved_file(new), f"after step {number}: {steps[number - 1]}"

        same(old, new, styles=True)


def test_random_mixes_of_every_kind_of_change_and_saves_give_the_same_files():
    kinds = [
        lambda g: ("edit_cells", [(g.randrange(5), g.randrange(3), g.choice(["", "1", "t", "=A1", "007", "سلام"]))]),
        lambda g: ("edit_cells", [(g.randrange(5), 0, "p"), (g.randrange(5), 1, "q")]),
        lambda g: ("set_column_width", "Name", g.choice([12, 20, 40])),
        lambda g: ("set_rtl", g.choice([True, False])),
        lambda g: ("set_cell_style_ranges", [(0, 0, g.randrange(5), g.randrange(3))], {"bold": g.choice([True, False])}, None),
        lambda g: ("set_text_defaults", {"font_size": float(g.choice([10, 12, 16]))}, None),
        lambda g: ("insert_row", g.randrange(4)),
        lambda g: ("delete_row", g.randrange(4)),
        lambda g: ("undo",),
        lambda g: ("redo",),
        lambda g: ("save_document",),
        lambda g: ("save_document",),
    ]

    for seed in range(5):
        generator = random.Random(seed)

        with tempfile.TemporaryDirectory() as folder:
            old, new = pair(folder)

            for step in range(45):
                method, *args = generator.choice(kinds)(generator)
                both(old, new, method, *args)

                if method == "save_document":
                    assert saved_file(old) == saved_file(new), f"seed {seed}, step {step}"

            both(old, new, "save_document")
            assert saved_file(old) == saved_file(new), f"seed {seed}, final"
