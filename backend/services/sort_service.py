from typing import Any

import pandas as pd


class SortService:
    """
    Sorts a dataframe by one or more columns, ordering cells like Excel.

    Within a column: numbers, then text (case-insensitive), then blanks -
    and blanks always last, whichever direction is chosen. In descending
    order the number/text groups swap (text first), as Excel does.

    Real data is messy: a column can hold numbers, text and blank cells at
    once (a freshly added row is blank in every column, and a typed value
    can be text in a column of numbers). Handing such a column to pandas'
    own sort raises TypeError, so object/text columns are sorted through
    explicit keys instead. Columns with a single native type (numbers,
    dates) keep pandas' native ordering, with missing values last.
    """

    def sort(
        self,
        dataframe: pd.DataFrame,
        rules: list[dict[str, Any]]
    ) -> pd.DataFrame:

        if dataframe.empty:
            return dataframe.copy()

        if not rules:
            return dataframe.copy()

        keys: dict[str, pd.Series] = {}
        by: list[str] = []
        ascending: list[bool] = []

        for rule_index, rule in enumerate(rules):

            column = rule.get("column")

            if column not in dataframe.columns:
                continue

            rule_ascending = bool(rule.get("ascending", True))

            # iloc, not dataframe[column]: tolerant of duplicate names.
            series = dataframe.iloc[:, list(dataframe.columns).index(column)]

            for key_index, (key, key_ascending) in enumerate(
                self._keys_for(series, rule_ascending)
            ):
                name = f"__sort_{rule_index}_{key_index}"
                keys[name] = key
                by.append(name)
                ascending.append(key_ascending)

        if not by:
            return dataframe.copy()

        keyed = pd.DataFrame(keys, index=dataframe.index)

        # Deliberately NOT reset_index(): each row keeps its original
        # dataframe position as its index label, which is how a sorted
        # (and/or filtered) view row is mapped back to the underlying
        # row - see Sheet._view_positions. Nothing consumes the view's
        # index otherwise (rows are emitted via to_dict("records")).
        #
        # Sorting happens on positions so duplicate index labels (which
        # shouldn't occur, but cost nothing to tolerate) can't misorder.
        order = keyed.reset_index(drop=True).sort_values(
            by=by,
            ascending=ascending,
            kind="stable",
            na_position="last",
        ).index

        return dataframe.iloc[order]

    def _keys_for(
        self,
        series: pd.Series,
        ascending: bool,
    ) -> list[tuple[pd.Series, bool]]:
        """The (key, ascending) columns that order one rule's column."""
        is_native = (
            pd.api.types.is_numeric_dtype(series)
            or pd.api.types.is_datetime64_any_dtype(series)
            or pd.api.types.is_timedelta64_dtype(series)
        ) and not pd.api.types.is_object_dtype(series)

        if is_native:
            rank = series.isna().astype(int) * 2
            return [(rank, True), (series, ascending)]

        ranks: list[int] = []
        numbers: list[float] = []
        texts: list[str] = []

        for value in series:
            kind, number, text = self._classify(value)

            if kind == "blank":
                rank = 2
            elif kind == "number":
                rank = 0 if ascending else 1
            else:
                rank = 1 if ascending else 0

            ranks.append(rank)
            numbers.append(number)
            texts.append(text)

        return [
            (pd.Series(ranks, index=series.index), True),
            (pd.Series(numbers, index=series.index, dtype="float64"), ascending),
            (pd.Series(texts, index=series.index, dtype=object), ascending),
        ]

    @staticmethod
    def _classify(value: Any) -> tuple[str, float, str]:
        """Return (kind, number, text) for one cell; kind is blank/number/text."""
        if value is None:
            return "blank", float("nan"), ""

        if isinstance(value, str):
            if not value.strip():
                return "blank", float("nan"), ""

            return "text", float("nan"), value.casefold()

        if isinstance(value, bool):
            return "text", float("nan"), str(value).casefold()

        try:
            if pd.isna(value):
                return "blank", float("nan"), ""
        except (TypeError, ValueError):
            pass

        if isinstance(value, (int, float)) or hasattr(value, "__float__"):
            try:
                number = float(value)
            except (TypeError, ValueError):
                return "text", float("nan"), str(value).casefold()

            if number != number:
                return "blank", float("nan"), ""

            return "number", number, ""

        return "text", float("nan"), str(value).casefold()
