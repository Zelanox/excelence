from kivy.properties import (
    StringProperty,
    BooleanProperty,
    NumericProperty,
)



class Cell(Label):

    value = StringProperty("")

    selected = BooleanProperty(False)

    readonly = BooleanProperty(True)

    editing = BooleanProperty(False)

    row = NumericProperty(0)

    column = NumericProperty(0)

    def on_value(self, instance, value):

        self.text = ar(value)