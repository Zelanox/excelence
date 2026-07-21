from ui.widgets.base_widget import BaseWidget

class Toolbar(BaseWidget):

    def open_clicked(self):
        print("OPEN")

    def save_clicked(self):
        print("SAVE")

    def reload_clicked(self):
        print("RELOAD")

    def close_clicked(self):
        print("CLOSE")