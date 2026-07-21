from kivy.uix.boxlayout import BoxLayout
from kivy.app import App


class BaseWidget(BoxLayout):

    @property
    def controller(self):
        return App.get_running_app().controller

    @property
    def app(self):
        return App.get_running_app()