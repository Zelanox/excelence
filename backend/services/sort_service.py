import pandas as pd


class SortService:

    def sort(
        self,
        dataframe: pd.DataFrame,
        rules: list[dict]
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

        return dataframe.sort_values(
            by=columns,
            ascending=ascending,
            kind="stable"
        ).reset_index(drop=True)