"""The contract the client relies on once sorting/filtering are client-local.

The client keeps the full ("canonical") rows, computes its own sorted/filtered
view, and converts any SHOWN row to the canonical row before telling the
server anything. The server therefore never has a view of its own and treats
every row number as a position in the real data.

This file plays the client: a tiny model that mirrors the Dart controller's
mapping (SheetView.apply + sourceRowOf), driving the real backend, and checks
the backend ends up exactly where the user's action meant.
"""

import functools
import math
import re
import tempfile

from backend.tests.test_text_styles import make_controller, styles

FLOAT = re.compile(r"^[+-]?(\d+\.?\d*|\.\d+)([eE][+-]?\d+)?$")


def view_apply(rows, headers, query="", sort_column=None, ascending=True):
    """Port of SheetView.apply: indices into rows, in display order (None = identity)."""
    q = query.strip().lower()
    column = headers.index(sort_column) if sort_column in headers else -1
    if not q and column < 0:
        return None
    idx = list(range(len(rows)))
    if q:
        idx = [i for i in idx if any(q in str(v).lower() for v in rows[i])]
    if column >= 0:
        def key(raw):
            t = str(raw).strip()
            if not t:
                return (2, 0.0, "")
            if FLOAT.match(t):
                return (0, float(t), "")
            return (1, 0.0, t.lower())
        keys = {i: key(rows[i][column]) for i in idx}
        def rank(k):
            return 2 if k[0] == 2 else ((0 if ascending else 1) if k[0] == 0 else (1 if ascending else 0))
        def cmp(a, b):
            ka, kb = keys[a], keys[b]
            if rank(ka) != rank(kb):
                return -1 if rank(ka) < rank(kb) else 1
            w = 0
            if ka[0] == 0:
                w = (ka[1] > kb[1]) - (ka[1] < kb[1]) if ascending else (kb[1] > ka[1]) - (kb[1] < ka[1])
            elif ka[0] == 1:
                w = (ka[2] > kb[2]) - (ka[2] < kb[2]) if ascending else (kb[2] > ka[2]) - (kb[2] < ka[2])
            return w if w else (a > b) - (a < b)
        idx.sort(key=functools.cmp_to_key(cmp))
    return idx


class Client:
    """What the Dart controller does: hold canonical rows, view them, translate to canonical."""

    def __init__(self, controller):
        self.c = controller
        self.view = {"query": "", "sort": None, "asc": True}

    def canonical(self):
        return [list(r.values()) for r in self.c.data()]

    def headers(self):
        return list(self.c.headers())

    def shown(self):
        rows, headers = self.canonical(), self.headers()
        mapping = view_apply(rows, headers, self.view["query"], self.view["sort"], self.view["asc"])
        return rows if mapping is None else [rows[i] for i in mapping], mapping

    def source_row(self, shown_row):
        _, mapping = self.shown()
        return shown_row if mapping is None else mapping[shown_row]

    # --- the operations, each converting shown -> canonical first ---
    def edit(self, shown_row, column, value):
        return self.c.edit_cells([(self.source_row(shown_row), column, value)])

    def paste_down(self, start_shown_row, column, values):
        shown, mapping = self.shown()
        edits = []
        for offset, value in enumerate(values):
            r = start_shown_row + offset
            if r >= len(shown):
                break
            edits.append((self.source_row(r), column, value))
        return self.c.edit_cells(edits)

    def delete_row(self, shown_row):
        return self.c.delete_row(self.source_row(shown_row))

    def insert_row_above(self, shown_row):
        shown, _ = self.shown()
        n_all = len(self.canonical())
        index = self.source_row(shown_row) if shown_row < len(shown) else n_all
        return self.c.insert_row(index)

    def style(self, first_shown, last_shown, column, values):
        rows = sorted(self.source_row(r) for r in range(first_shown, last_shown + 1))
        runs, start, prev = [], rows[0], rows[0]
        for r in rows[1:]:
            if r == prev + 1:
                prev = r
                continue
            runs.append((start, prev)); start = prev = r
        runs.append((start, prev))
        return self.c.set_cell_style_ranges([(a, column, b, column) for a, b in runs], values)


def names(client):
    return [row[0] for row in client.canonical()]


def test_edit_under_sort_changes_the_row_shown():
    with tempfile.TemporaryDirectory() as folder:
        client = Client(make_controller(folder))                    # Alice 90, Bob 85, Charlie 95, Dana 70
        client.view.update(sort="Score", asc=False)                 # Charlie, Alice, Bob, Dana
        assert [r[0] for r in client.shown()[0]] == ["Charlie", "Alice", "Bob", "Dana"]
        assert client.edit(2, 0, "Robert") is True                  # the row labelled Bob on screen
        assert names(client) == ["Alice", "Robert", "Charlie", "Dana"]


def test_edit_under_filter_changes_the_row_shown():
    with tempfile.TemporaryDirectory() as folder:
        client = Client(make_controller(folder))
        client.view.update(query="dana")
        assert [r[0] for r in client.shown()[0]] == ["Dana"]
        assert client.edit(0, 2, "71") is True
        assert [r[2] for r in client.canonical()] == [90, 85, 95, 71]


def test_paste_down_a_sorted_column_lands_on_the_rows_shown():
    with tempfile.TemporaryDirectory() as folder:
        client = Client(make_controller(folder))
        client.view.update(sort="Age", asc=True)                    # Charlie 22, Alice 25, Bob 30, Dana 41
        assert client.paste_down(1, 0, ["X", "Y"]) is True          # onto Alice and Bob
        assert names(client) == ["X", "Y", "Charlie", "Dana"]


def test_delete_and_insert_use_the_row_shown():
    with tempfile.TemporaryDirectory() as folder:
        client = Client(make_controller(folder))
        client.view.update(sort="Score", asc=True)                  # Dana 70, Bob 85, Alice 90, Charlie 95
        assert client.delete_row(1) is True                          # Bob
        assert names(client) == ["Alice", "Charlie", "Dana"]

        assert client.insert_row_above(0) is True                    # above Dana (the first shown row)
        assert names(client) == ["Alice", "Charlie", "", "Dana"]
        assert client.insert_row_above(len(client.shown()[0])) is True   # one past the last shown: the end
        assert names(client)[-1] == ""


def test_insert_and_delete_while_filtered():
    with tempfile.TemporaryDirectory() as folder:
        client = Client(make_controller(folder))
        client.view.update(query="a")                                # Alice, Charlie, Dana (contain 'a')
        assert [r[0] for r in client.shown()[0]] == ["Alice", "Charlie", "Dana"]
        assert client.delete_row(1) is True                          # Charlie
        assert names(client) == ["Alice", "Bob", "Dana"]
        assert [r[0] for r in client.shown()[0]] == ["Alice", "Dana"]   # Bob never matched
        assert client.insert_row_above(1) is True                    # above Dana, as shown
        assert names(client) == ["Alice", "Bob", "", "Dana"]
        assert client.insert_row_above(len(client.shown()[0])) is True   # one past the last SHOWN row: the end
        assert names(client)[-1] == ""


def test_style_of_a_shown_selection_that_is_scattered_in_the_data():
    with tempfile.TemporaryDirectory() as folder:
        c = make_controller(folder)
        client = Client(c)
        client.view.update(sort="Score", asc=False)                  # Charlie(2), Alice(0), Bob(1), Dana(3)
        assert client.style(0, 1, 0, {"bold": True}) is True         # first two SHOWN: Charlie and Alice
        assert set(styles(c)) == {(0, 0), (2, 0)}                    # canonical rows 0 and 2, in ONE undo step
        assert len(c.document.undo_stack) == 1


def test_formulas_refer_to_data_rows_not_shown_rows():
    with tempfile.TemporaryDirectory() as folder:
        c = make_controller(folder)
        client = Client(c)
        # the formula is written against DATA row numbers: Score of row 1 + Score of row 3
        assert client.c.edit_cells([(0, 1, "=C1+C3")]) is True
        client.view.update(sort="Score", asc=False)                  # rows reshuffled on screen
        # the formula text is untouched by the client's view...
        assert [r[1] for r in client.canonical()][0] == "=C1+C3"
        # ...and still refers to the same data cells (row 1 = Alice 90, row 3 = Charlie 95)
        assert client.canonical()[0][2] + client.canonical()[2][2] == 185


def test_structural_edit_under_a_view_rewrites_formulas_in_data_terms():
    with tempfile.TemporaryDirectory() as folder:
        c = make_controller(folder)
        client = Client(c)
        client.c.edit_cell(0, 1, "=C2+C3")                           # Age column holds a formula
        client.view.update(sort="Score", asc=True)                   # Dana 70 is shown first (data row 4)
        assert client.insert_row_above(0) is True                    # inserts at data position 3
        # rows 2 and 3 sit above the insertion point, so the formula is unchanged
        assert client.canonical()[0][1] == "=C2+C3"

        # now delete data row 2 (Bob) via the view: the formula's first reference points at it
        shown, mapping = client.shown()
        bob_shown_row = [r[0] for r in shown].index("Bob")
        assert client.delete_row(bob_shown_row) is True
        assert client.canonical()[0][1] == "=#REF!+C2"               # C2 gone; old C3 slid up to C2
