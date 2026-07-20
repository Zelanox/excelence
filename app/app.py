from kivy.app import App
from kivy.uix.screenmanager import ScreenManager
from kivy.lang import Builder

from ui.widgets.toolbar import Toolbar
from ui.widgets.searchbar import SearchBar
from ui.widgets.spreadsheet import Spreadsheet
from ui.widgets.statusbar import StatusBar

from app.controller import Controller
from ui.widgets.cell import Cell

from ui.screens.main_screen import MainScreen
from pathlib import Path

def load_kv_files():
    kv_root = Path(__file__).parent.parent / "ui"

    Builder.load_file(str(kv_root / "screens" / "main_screen.kv"))

    Builder.load_file(str(kv_root / "widgets" / "toolbar.kv"))

    Builder.load_file(str(kv_root / "widgets" / "searchbar.kv"))

    Builder.load_file(str(kv_root / "widgets" / "spreadsheet.kv"))

    Builder.load_file(str(kv_root / "widgets" / "cell.kv"))

    Builder.load_file(str(kv_root / "widgets" / "statusbar.kv"))

class ExcelenceApp(App):

    title = "Excelence"

    def build(self):

        load_kv_files()

        self.controller = Controller()
        self.controller.open_document("فهرس.xlsx")

        sm = ScreenManager()

        main_screen = MainScreen(name="main")

        sm.add_widget(main_screen)

        return sm