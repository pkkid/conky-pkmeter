from pkm.widgets.base import BaseWidget
from pkm import utils


class ClockWidget(BaseWidget):
    """ Displays the current date and time. """

    def __init__(self, wsettings, origin=0):
        super().__init__(wsettings, origin)
        self.height = 85

    def get_conkyrc(self, theme):
        """ Create the conkyrc template for the this widget. """
        return utils.clean_spaces(f"""
            ${{voffset 8}}${{alignr 105}}${{font Ubuntu:bold:size=43}}{theme.header_color}${{time {self.bignum}}}
            ${{voffset -95}}${{goto 105}}{theme.header}${{time {self.line1}}}
            ${{goto 105}}${{time {self.line2}}}
            ${{goto 105}}${{time {self.line3}}}
            ${{voffset 4}}{theme.reset}\\
        """)  # noqa

    def get_lua_entries(self, theme):
        """ Create the draw.lua entries for this widget. """
        origin, width, height = self.origin, self.width, self.height
        return [
            self.draw('line', frm=(100,origin), to=(100,origin+height), thickness=width, color=theme.bg),  # main bg
        ]
