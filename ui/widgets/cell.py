from kivy.properties import (
    StringProperty,
    BooleanProperty,
    NumericProperty,
)

from kivy.uix.label import Label

from utils.arabic_utils import arabic


class Cell(Label):

    value = StringProperty("")

    row = NumericProperty(0)

    column = NumericProperty(0)

    selected = BooleanProperty(False)

    readonly = BooleanProperty(True)

    editing = BooleanProperty(False)

    def on_value(self, instance, value):

        self.text = arabic(value)