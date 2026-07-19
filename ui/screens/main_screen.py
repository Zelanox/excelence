from kivy.uix.boxlayout import BoxLayout
from kivy.uix.button import Button
from kivy.uix.label import Label


class MainScreen(BoxLayout):

    def __init__(self, **kwargs):
        super().__init__(orientation="vertical", **kwargs)

        #
        # Toolbar
        #
        toolbar = BoxLayout(
            size_hint_y=None,
            height=45
        )

        toolbar.add_widget(Button(text="Open"))
        toolbar.add_widget(Button(text="Save"))
        toolbar.add_widget(Button(text="Settings"))

        self.add_widget(toolbar)

        #
        # Spreadsheet placeholder
        #
        self.add_widget(
            Label(
                text="Spreadsheet will appear here."
            )
        )

        #
        # Status bar
        #
        status = Label(
            text="Ready",
            size_hint_y=None,
            height=30
        )

        self.add_widget(status)