

class BaseWidget:

    def __init__(self, wconfig):
        self.wconfig = wconfig      # Widget configuration object
        self.origin = 0             # Starting ypos of the widget

    @property
    def height(self):
        return 0

    def get_conkyrc(self):
        return ''

    def get_lua_entries(self):
        return []

    def point(self, pos):
        return f"{{x={pos[0]},y={pos[1]}}}"

    def line(self, start, end, color, alpha, thickness):
        return f"{{kind='line', from={self.point(start)}, to={self.point(end)}, color='{color}', alpha={alpha}, thickness={thickness}}}"  # noqa
