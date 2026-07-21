from ui.widgets.base_widget import BaseWidget
from ui.widgets.row import Row


class Spreadsheet(BaseWidget):

    def on_kv_post(self, *args):
        self.refresh()

    def refresh(self):

        # Get the layout that holds all rows
        container = self.ids.rows_container
        container.clear_widgets()

        # Get the application's controller
        controller = self.controller

        # ----------------------------
        # Header
        # ----------------------------

        container.add_widget(
            self.create_row(
                controller.headers(),
                header=True
            )
        )

        # ----------------------------
        # Data
        # ----------------------------

        for r in range(controller.row_count()):

            values = []

            for c in range(controller.column_count()):

                values.append(
                    controller.cell_value(r, c)
                )

            container.add_widget(
                self.create_row(values)
            )

    def create_row(self, values, header=False):

        row = Row()
        row.header = header
        row.values = values

        return row

    def reload(self):
        self.refresh()