from kivy.properties import ListProperty
from kivy.uix.boxlayout import BoxLayout

from ui.widgets.cell import Cell


class Row(BoxLayout):

    values = ListProperty([])

    def on_values(self, instance, value):
        self.refresh()

    def refresh(self):

        self.clear_widgets()

        for value in self.values:
            self.add_widget(
                Cell(value=str(value))
            )