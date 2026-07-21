from ui.widgets.base_widget import BaseWidget


class SearchBar(BaseWidget):

    def search_clicked(self):

        text = self.ids.search_input.text

        controller = self.controller

        if text.strip():
            controller.search(text)
        else:
            controller.clear_search()

        self.parent.ids.spreadsheet.refresh()
        self.parent.ids.statusbar.refresh()