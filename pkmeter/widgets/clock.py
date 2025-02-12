from jinja2 import Environment, BaseLoader
from pkmeter.widgets.base import BaseWidget


class ClockWidget(BaseWidget):

    def __init__(self, pconfig, wconfig):
        super().__init__(self)
        self.pconfig = pconfig      # PKMeter configuration object
        self.wconfig = wconfig      # Widget configuration object
        self.ystart = 0             # Starting ypos of the widget
        self.height = 81            # Height of this widget

    @property
    def yend(self):
        return self.ystart + self.height

    def get_conky_tmpl(self, config):
        """ Create the conkyrc template for the clock widget. """
        jinjatmpl = Environment(loader=BaseLoader).from_string("""
            ${voffset 8}${font Ubuntu:bold:size=40}${alignr 105}${time {{clock.bignum|default("%d")}}}${font}
            ${voffset -41}${goto 105}${time {{clock.line1|default("%b %Y")}}}
            ${goto 105}${time {{clock.line2|default("%A")}}}
            ${goto 105}${time {{clock.line3|default("%H:%M:%S %P")}}}
        """)
        conkytmpl = jinjatmpl.render(self.config)
        return conkytmpl

    def get_draw_entries(self):
        return ""
