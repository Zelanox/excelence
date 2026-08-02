import pandas as pd


class SearchService:

    def search(
        self,
        dataframe: pd.DataFrame,
        text: str
    ) -> pd.DataFrame:

        text = text.strip()

        if not text:
            return dataframe.copy()

        search = text.lower()

        mask = dataframe.astype(str).apply(

            lambda column:

            column.str.lower().str.contains(

                search,

                na=False

            )

        ).any(axis=1)

        return dataframe[mask].copy()