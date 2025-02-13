from collections import namedtuple
from pkm.widgets.base import BaseWidget
from pkm import CONFIG, utils


class ClockWidget(BaseWidget):
    """ Displays the current date and time. """

    @property
    def height(self):
        return 85

    def get_conkyrc(self):
        """ Create the conkyrc template for the clock widget. """
        wc = namedtuple('wconfig', self.wconfig.keys())(*self.wconfig.values())
        return utils.clean_spaces(f"""
            ${{voffset 8}}${{font Ubuntu:bold:size=43}}${{alignr 105}}${{time {wc.bignum}}}${{font}}
            ${{voffset -45}}${{goto 105}}${{time {wc.line1}}}
            ${{goto 105}}${{time {wc.line2}}}
            ${{goto 105}}${{time {wc.line3}}}
        """)

    def get_lua_entries(self):
        return [self.line(
            start=(100, self.origin),  # top
            end=(100, self.origin + self.height),  # bottom
            color=utils.rget(CONFIG, 'mainbg', '0x000000'),
            alpha=utils.rget(CONFIG, 'mainbg_alpha', 0.6),
            thickness=utils.rget(CONFIG, 'conky.maximum_width', 200),
        )]
