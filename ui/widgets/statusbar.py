from ui.widgets.base_widget import BaseWidget


class StatusBar(BaseWidget):

    def set_status(self, text):
        self.ids.status_label.text = text

    def set_connection(self, text):
        self.ids.connection_label.text = text

    def set_rows(self, rows):
        self.ids.rows_label.text = f"{rows} rows"

    def refresh(self):

        controller = self.controller

        if controller.is_loaded():

            self.set_status(controller.filename())
            self.set_rows(controller.row_total())

        else:

            self.set_status("No document loaded")
            self.set_rows(0)

        if controller.document.online:
            self.set_connection("Online")
        else:
            self.set_connection("Offline")