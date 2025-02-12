

class BaseWidget:

    def __init__(self, pconfig, wconfig):
        self.pconfig = pconfig      # PKMeter configuration object
        self.wconfig = wconfig      # Widget configuration object
        self.ystart = 0             # Starting ypos of the widget

    @property
    def height(self):
        return 0

    def get_conkyrc(self):
        return ''

    def get_lua_entries(self):
        return []
