from dataclasses import dataclass, field

from backend.models.spreadsheet_row import SpreadsheetRow


@dataclass(slots=True)
class Sheet:

    name: str

    rows: list[SpreadsheetRow] = field(default_factory=list)

    @property
    def row_count(self):

        return len(self.rows)

    @property
    def column_count(self):

        if not self.rows:
            return 0

        return len(self.rows[0].values)

    @property
    def headers(self):

        if not self.rows:

            return []

        return list(

            self.rows[0].values.keys()

        )

    def row(self, index):

        if index < 0:

            return None

        if index >= len(self.rows):

            return None

        return self.rows[index]

    def cell(self, row, column):

        current = self.row(row)

        if current is None:

            return None

        headers = self.headers

        if column >= len(headers):

            return None

        return current.values.get(

            headers[column]

        )

    def insert_row(self, index=None):

        if index is None:

            index = len(self.rows)

        values = {

            header: ""

            for header in self.headers

        }

        self.rows.insert(

            index,

            SpreadsheetRow(values)

        )

        return True

    def delete_row(self, index):

        if index < 0:

            return False

        if index >= len(self.rows):

            return False

        del self.rows[index]

        return True

    def edit_cell(self, row, column, value):
        current = self.row(row)

        if current is None:

            return False

        headers = self.headers

        if column >= len(headers):

            return False

        current.values[headers[column]] = value

        return True

    def insert_column(self, name, index=None):
        if not self.rows:

            self.rows.append(

                SpreadsheetRow(

                    {name: ""}

                )

            )

            return True

        for row in self.rows:

            items = list(

                row.values.items()

            )

            if index is None:

                index = len(items)

            items.insert(

                index,

                (name, "")

            )

            row.values = dict(items)