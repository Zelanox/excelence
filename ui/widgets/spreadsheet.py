from kivy.properties import ListProperty

from ui.widgets.base_widget import BaseWidget
from utils.arabic_utils import arabic


class Spreadsheet(BaseWidget):

    headers = ListProperty([])

    rows = ListProperty([])

    def on_kv_post(self, *args):

        self.refresh()

    def refresh(self):

        controller = self.controller

        self.headers = controller.headers()

        self.rows = []

        for r in range(min(20, controller.row_count())):

            row = []

            for c in range(controller.column_count()):

                row.append(
                    arabic(controller.cell_value(r, c))
                )

            self.rows.append(row)