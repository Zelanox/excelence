from ui.widgets.base_widget import BaseWidget
from ui.widgets.sort_dialog import SortDialog


class Toolbar(BaseWidget):

    def open_clicked(self):

        filename = "sample/test.xlsx"

        if self.controller.open_document(filename):

            self.app.root.get_screen("main").ids.spreadsheet.reload()

            self.app.root.get_screen("main").ids.statusbar.refresh()

        print("OPEN")

    def save_clicked(self):

        self.controller.save_document()

        self.app.root.get_screen("main").ids.statusbar.refresh()

        print("SAVE")

    def reload_clicked(self):

        self.controller.reload_document()

        self.app.root.get_screen("main").ids.spreadsheet.reload()

        self.app.root.get_screen("main").ids.statusbar.refresh()

        print("RELOAD")

    def sort_clicked(self):

        SortDialog().open()

    def close_clicked(self):

        self.controller.close_document()

        self.app.root.get_screen("main").ids.spreadsheet.reload()

        self.app.root.get_screen("main").ids.statusbar.refresh()

        print("CLOSE")