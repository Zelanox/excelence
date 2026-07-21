from kivy.properties import BooleanProperty

from ui.widgets.cell import Cell


class HeaderCell(Cell):

    header = BooleanProperty(True)