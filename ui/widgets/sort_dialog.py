from kivy.app import App
from kivy.uix.popup import Popup

from utils.arabic_utils import arabic

class SortDialog(Popup):

    @property
    def controller(self):
        return App.get_running_app().controller

    @property
    def app(self):
        return App.get_running_app()

    def on_open(self):

        columns = self.controller.sortable_columns()

        display = [""]

        self.column_map = {}

        for column in columns:

            shown = arabic(column)

            display.append(shown)

            self.column_map[shown] = column

        self.ids.column1.values = display
        self.ids.column2.values = display
        self.ids.column3.values = display

    def apply(self):

        rules = []

        for i in range(1, 4):

            shown = self.ids[f"column{i}"].text

            if not shown:
                continue

            column = self.column_map[shown]

            if not column:
                continue

            ascending = (
                self.ids[f"order{i}"].text == "Ascending"
            )

            rules.append({
                "column": column,
                "ascending": ascending
            })

        if not rules:
            return

        self.controller.sort(rules)

        self.dismiss()

        self.app.root.get_screen(
            "main"
        ).ids.spreadsheet.reload()

        self.app.root.get_screen(
            "main"
        ).ids.statusbar.refresh()