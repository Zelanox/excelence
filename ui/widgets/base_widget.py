from kivy.app import App
from kivy.uix.boxlayout import BoxLayout


class BaseWidget(BoxLayout):

    @property
    def controller(self):
        return App.get_running_app().controller