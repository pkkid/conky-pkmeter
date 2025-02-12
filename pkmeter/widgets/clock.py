from jinja2 import Environment, BaseLoader
from pkmeter.widgets.base import BaseWidget
from pkmeter import utils


class ClockWidget(BaseWidget):

    @property
    def height(self):
        return 81

    @property
    def yend(self):
        return self.ystart + self.height

    def get_conkyrc(self):
        """ Create the conkyrc template for the clock widget. """
        jinjatmpl = Environment(loader=BaseLoader).from_string("""
            ${voffset 8}${font Ubuntu:bold:size=40}${alignr 105}${time {{bignum|default("%d")}}}${font}
            ${voffset -41}${goto 105}${time {{line1|default("%b %Y")}}}
            ${goto 105}${time {{line2|default("%A")}}}
            ${goto 105}${time {{line3|default("%H:%M:%S %P")}}}
        """)
        conkytmpl = utils.clean_spaces(jinjatmpl.render(self.wconfig)) + '\n'
        return conkytmpl

    def get_lua_entries(self):
        return []
