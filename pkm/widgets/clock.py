from collections import namedtuple
from pkm.widgets.base import BaseWidget
from pkm import CONFIG, utils


class ClockWidget(BaseWidget):
    """ Displays the current date and time. """

    def __init__(self, wconfig, origin=0):
        self.wconfig = wconfig      # Widget configuration object
        self.origin = origin        # Starting ypos of the widget
        self.height = 85            # Height of the widget

    def get_conkyrc(self):
        """ Create the conkyrc template for the this widget. """
        wc = namedtuple('wconfig', self.wconfig.keys())(*self.wconfig.values())
        return utils.clean_spaces(f"""
            ${{voffset 8}}${{font Ubuntu:bold:size=43}}${{alignr 105}}${{time {wc.bignum}}}${{font}}
            ${{voffset -45}}${{goto 105}}${{time {wc.line1}}}
            ${{goto 105}}${{time {wc.line2}}}
            ${{goto 105}}${{time {wc.line3}}}
            ${{font}}${{color}}${{voffset 4}}\\
        """)  # noqa

    def get_lua_entries(self):
        """ Create the draw.lua entries for this widget. """
        origin, height = self.origin, self.height
        width = utils.rget(CONFIG, 'conky.maximum_width', 200)
        mainbg = CONFIG['mainbg']
        return [
            self.line(start=(100, origin), end=(100, origin+height), thickness=width, **mainbg),
        ]
