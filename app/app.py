from kivy.app import App

from ui.screens.home import HomeScreen


class ExcelenceApp(App):

    title = "Excelence"

    def build(self):
        return HomeScreen()