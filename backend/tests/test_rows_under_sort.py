"""Row operations (delete / insert / append) while a sort or filter is active."""

import tempfile

from backend.tests.test_text_styles import make_controller, reopen, styles


def sheet(controller):
    return controller.document.spreadsheet.current_sheet()


def names(controller):
    """Underlying (unsorted) data order."""
    return list(sheet(controller).dataframe["Name"])


def shown(controller):
    """What the grid shows, top to bottom."""
    return [row["Name"] for row in controller.data()]


# make_controller data: Alice 25/90, Bob 30/85, Charlie 22/95, Dana 41/70

def test_delete_row_removes_the_row_that_is_shown_when_sorted():
    with tempfile.TemporaryDirectory() as folder:
        c = make_controller(folder)
        assert c.sort([{"column": "Score", "ascending": False}]) is True
        assert shown(c) == ["Charlie", "Alice", "Bob", "Dana"]

        assert c.delete_row(2) is True                     # the row labelled Bob on screen
        assert names(c) == ["Alice", "Charlie", "Dana"]    # Bob - not whatever sat at index 2
        assert shown(c) == ["Charlie", "Alice", "Dana"]    # sort still in place


def test_delete_row_removes_the_row_that_is_shown_when_filtered():
    with tempfile.TemporaryDirectory() as folder:
        c = make_controller(folder)
        assert c.search("Dana") is True
        assert shown(c) == ["Dana"]

        assert c.delete_row(0) is True
        assert names(c) == ["Alice", "Bob", "Charlie"]


def test_delete_row_out_of_view_range_fails_even_if_the_data_has_more_rows():
    with tempfile.TemporaryDirectory() as folder:
        c = make_controller(folder)
        assert c.search("Dana") is True                    # 1 visible row, 4 underlying
        assert c.delete_row(1) is False
        assert c.delete_row(3) is False
        assert len(names(c)) == 4


def test_delete_row_under_sort_keeps_styles_with_their_rows():
    with tempfile.TemporaryDirectory() as folder:
        c = make_controller(folder)
        c.set_cell_style(3, 0, 3, 0, {"bold": True})       # Dana
        c.sort([{"column": "Score", "ascending": False}])  # Charlie, Alice, Bob, Dana
        assert c.delete_row(1) is True                     # Alice
        assert shown(c) == ["Charlie", "Bob", "Dana"]
        assert styles(c) == {(2, 0): {"bold": True}}       # still on Dana


def test_delete_row_under_sort_is_undoable_exactly():
    with tempfile.TemporaryDirectory() as folder:
        c = make_controller(folder)
        before = sheet(c).dataframe.copy()
        c.sort([{"column": "Score", "ascending": False}])
        c.edit_cell(0, 0, "Chuck")                          # makes history non-empty after the sort cleared it
        assert c.delete_row(1) is True
        assert c.undo() is True
        assert "Alice" in names(c)
        assert c.undo() is True
        assert sheet(c).dataframe.equals(before)


def test_insert_row_above_a_visible_row_when_sorted():
    with tempfile.TemporaryDirectory() as folder:
        c = make_controller(folder)
        c.sort([{"column": "Score", "ascending": False}])   # Charlie, Alice, Bob, Dana
        assert c.insert_row(2) is True                      # above Bob, as shown
        # underlying order: Bob (index 1) was displaced, so the blank is just before Bob
        assert names(c) == ["Alice", "", "Bob", "Charlie", "Dana"]


def test_insert_row_at_the_end_appends_even_when_filtered():
    with tempfile.TemporaryDirectory() as folder:
        c = make_controller(folder)
        c.search("Dana")
        assert c.insert_row(1) is True                      # one past the last VISIBLE row
        assert names(c) == ["Alice", "Bob", "Charlie", "Dana", ""]


def test_insert_row_rejects_bad_positions():
    with tempfile.TemporaryDirectory() as folder:
        c = make_controller(folder)
        c.search("Dana")
        assert c.insert_row(2) is False                     # beyond the visible rows
        assert c.insert_row(-1) is False
        assert len(names(c)) == 4


def test_append_row_with_first_value_when_unsorted():
    with tempfile.TemporaryDirectory() as folder:
        c = make_controller(folder)
        assert c.append_row("Zed") is True
        assert names(c)[-1] == "Zed"
        row = list(sheet(c).dataframe.iloc[-1])
        assert row[1] == "" and row[2] == ""                # other cells blank


def test_append_row_blank():
    with tempfile.TemporaryDirectory() as folder:
        c = make_controller(folder)
        assert c.append_row("") is True and c.append_row(None) is True and c.append_row("   ") is True
        assert names(c)[-3:] == ["", "", ""]


def test_append_row_writes_the_value_into_the_new_row_even_when_sorted_and_filtered():
    with tempfile.TemporaryDirectory() as folder:
        c = make_controller(folder)
        c.sort([{"column": "Score", "ascending": True}])
        assert c.append_row("Eve") is True
        assert names(c) == ["Alice", "Bob", "Charlie", "Dana", "Eve"]   # at the end of the DATA
        assert "Eve" in shown(c)                                         # and the sort is still applied

        c.search("Bob")
        assert c.append_row("Frank") is True
        assert names(c)[-1] == "Frank"
        assert names(c)[:5] == ["Alice", "Bob", "Charlie", "Dana", "Eve"]


def test_append_row_is_one_undo_step_and_persists():
    with tempfile.TemporaryDirectory() as folder:
        c = make_controller(folder)
        c.append_row("Zed")
        assert len(c.document.undo_stack) == 1
        fresh = reopen(c, folder)
        assert names(fresh)[-1] == "Zed"
        assert c.undo() is True
        assert names(c) == ["Alice", "Bob", "Charlie", "Dana"]


def test_append_row_coerces_numbers_in_a_numeric_first_column():
    with tempfile.TemporaryDirectory() as folder:
        c = make_controller(
            folder,
            rows=[[1, "a"], [2, "b"]],
            header=("Id", "Label"),
        )
        assert c.append_row("3") is True
        column = list(sheet(c).dataframe["Id"])
        assert column == [1, 2, 3] and isinstance(column[-1], int)


def test_append_row_needs_a_document():
    from backend.controller.controller import Controller
    assert Controller().append_row("x") is False
