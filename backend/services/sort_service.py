from typing import Any

import pandas as pd


class SortService:

    def sort(
        self,
        dataframe: pd.DataFrame,
        rules: list[dict[str, Any]]
    ) -> pd.DataFrame:

        if dataframe.empty:
            return dataframe.copy()

        if not rules:
            return dataframe.copy()

        columns = []
        ascending = []

        for rule in rules:

            column = rule.get("column")

            if column not in dataframe.columns:
                continue

            columns.append(column)
            ascending.append(
                rule.get("ascending", True)
            )

        if not columns:
            return dataframe.copy()

        # Deliberately NOT reset_index(): each row keeps its original
        # dataframe position as its index label, which is how a sorted
        # (and/or filtered) view row is mapped back to the underlying
        # row - see Sheet._view_positions. Nothing consumes the view's
        # index otherwise (rows are emitted via to_dict("records")).
        return dataframe.sort_values(
            by=columns,
            ascending=ascending,
            kind="stable"
        )