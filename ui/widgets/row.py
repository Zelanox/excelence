from kivy.properties import (
    ListProperty,
    NumericProperty,
    BooleanProperty,
)

from kivy.uix.boxlayout import BoxLayout

from ui.widgets.cell import Cell


class Row(BoxLayout):

    values = ListProperty([])

    row_index = NumericProperty(-1)

    header = BooleanProperty(False)

    def on_kv_post(self, *args):
        self.refresh()

    def on_values(self, *args):
        self.refresh()

    def refresh(self):

        self.clear_widgets()

        for column, value in enumerate(self.values):

            self.add_widget(
                Cell(
                    value=str(value),
                    row=self.row_index,
                    column=column,
                    readonly=self.header
                )
            )