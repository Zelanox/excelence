from kivy.app import App
from kivy.uix.screenmanager import Screen


class MainScreen(Screen):

    @property
    def controller(self):
        return App.get_running_app().controller

    @property
    def spreadsheet(self):
        return self.ids.spreadsheet

    @property
    def toolbar(self):
        return self.ids.toolbar

    @property
    def searchbar(self):
        return self.ids.searchbar

    @property
    def statusbar(self):
        return self.ids.statusbar