"""SortService: Excel-like ordering of mixed, blank and plain columns."""

import numpy as np
import pandas as pd

from backend.services.sort_service import SortService


def order(values, ascending=True, name="v"):
    frame = pd.DataFrame({name: values})
    result = SortService().sort(frame, [{"column": name, "ascending": ascending}])
    return list(result[name]), list(result.index)


def test_numbers_text_blanks_ascending():
    values, _ = order([3, "banana", "", 1, "Apple", None, 2.5, "cherry"])
    assert values == [1, 2.5, 3, "Apple", "banana", "cherry", "", None]


def test_descending_puts_text_first_and_blanks_still_last():
    values, _ = order([3, "banana", "", 1, "Apple", None, 2.5, "cherry"], ascending=False)
    assert values == ["cherry", "banana", "Apple", 3, 2.5, 1, "", None]


def test_mixed_column_no_longer_raises():
    # the exact situation a freshly added blank row creates in a numeric column
    values, _ = order([90, 85, 95, 70, ""])
    assert values == [70, 85, 90, 95, ""]
    values, _ = order([90, 85, 95, 70, ""], ascending=False)
    assert values == [95, 90, 85, 70, ""]


def test_text_sort_is_case_insensitive_and_stable():
    values, index = order(["b", "A", "a", "B"])
    assert values == ["A", "a", "b", "B"]          # ties keep their original order
    assert index == [1, 2, 0, 3]


def test_whitespace_only_counts_as_blank():
    values, _ = order(["x", "   ", "a"])
    assert values == ["a", "x", "   "]


def test_plain_numeric_columns_use_native_order_with_nan_last():
    frame = pd.DataFrame({"n": [3.0, np.nan, 1.0, 2.0]})
    asc = SortService().sort(frame, [{"column": "n", "ascending": True}])
    desc = SortService().sort(frame, [{"column": "n", "ascending": False}])
    assert list(asc["n"])[:3] == [1.0, 2.0, 3.0] and np.isnan(list(asc["n"])[3])
    assert list(desc["n"])[:3] == [3.0, 2.0, 1.0] and np.isnan(list(desc["n"])[3])


def test_dates_sort_natively():
    frame = pd.DataFrame({"d": pd.to_datetime(["2024-03-01", "2023-01-01", None, "2024-01-01"])})
    result = SortService().sort(frame, [{"column": "d", "ascending": True}])
    assert [str(x)[:10] for x in result["d"][:3]] == ["2023-01-01", "2024-01-01", "2024-03-01"]
    assert pd.isna(result["d"].iloc[3])


def test_multi_column_sort():
    frame = pd.DataFrame({"g": ["b", "a", "b", "a", ""], "n": [1, 2, 3, 4, 5]})
    result = SortService().sort(frame, [{"column": "g", "ascending": True}, {"column": "n", "ascending": False}])
    assert list(result["g"]) == ["a", "a", "b", "b", ""]
    assert list(result["n"]) == [4, 2, 3, 1, 5]


def test_rows_keep_their_original_index_labels():
    frame = pd.DataFrame({"v": [30, 10, 20]})
    result = SortService().sort(frame, [{"column": "v", "ascending": True}])
    assert list(result.index) == [1, 2, 0]         # labels = original positions


def test_unknown_columns_and_empty_inputs():
    frame = pd.DataFrame({"v": [2, 1]})
    assert list(SortService().sort(frame, [{"column": "nope", "ascending": True}])["v"]) == [2, 1]
    assert list(SortService().sort(frame, [])["v"]) == [2, 1]
    assert SortService().sort(pd.DataFrame(), [{"column": "v"}]).empty


def test_sorting_does_not_modify_its_input():
    frame = pd.DataFrame({"v": [3, "x", 1]})
    before = frame.copy()
    SortService().sort(frame, [{"column": "v", "ascending": True}])
    assert frame.equals(before)
