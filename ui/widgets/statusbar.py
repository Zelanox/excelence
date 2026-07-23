from ui.widgets.base_widget import BaseWidget


class StatusBar(BaseWidget):

    def on_kv_post(self, *args):
        self.refresh()

    def refresh(self):

        controller = self.controller

        if controller.is_loaded():

            self.ids.file_label.text = controller.filename()

            self.ids.state_label.text = "Loaded"

            self.ids.rows_label.text = f"{controller.row_total()} rows"

        else:

            self.ids.file_label.text = "No document"

            self.ids.state_label.text = "Ready"

            self.ids.rows_label.text = "0 rows"