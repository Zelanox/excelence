from ui.widgets.base_widget import BaseWidget


class SearchBar(BaseWidget):

    def search_changed(self, text):

        self.controller.search(text)

        self.app.root.get_screen("main").ids.spreadsheet.reload()

        self.app.root.get_screen("main").ids.statusbar.refresh()