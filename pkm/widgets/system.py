import os
from pkm.widgets.base import BaseWidget
from pkm import utils


class SystemWidget(BaseWidget):
    """ Displays PC system metrics. """

    def __init__(self, wsettings, origin=0):
        super().__init__(wsettings, origin)
        self.height = 132

    def get_conkyrc(self, theme):
        """ Create the conkyrc template for the this widget. """
        return utils.clean_spaces(f"""
            ${{voffset 17}}${{goto 100}}{theme.accent1}${{cpugraph cpu0 24,90 -l}}${{color}}
            ${{voffset -36}}${{goto 10}}{theme.header}System
            ${{goto 10}}{theme.subheader}${{nodename}}
            ${{voffset 17}}${{goto 10}}{theme.label}CPU Usage${{alignr 55}}{theme.value}${{cpu cpu0}}%
            ${{goto 10}}{theme.label}CPU Freq${{alignr 55}}{theme.value}${{freq}} MHz
            ${{goto 10}}{theme.label}CPU Uptime${{alignr 55}}{theme.value}${{uptime_short}}
            ${{goto 10}}{theme.label}Mem Used${{alignr 55}}{theme.value}${{mem}}
            ${{goto 10}}{theme.label}Mem Free${{alignr 55}}{theme.value}${{memeasyfree}}
        """)  # noqa

    def get_lua_entries(self, theme):
        """ Create the draw.lua entries for this widget. """
        origin, width, height = self.origin, self.width, self.height
        return [
            self.draw('line', frm=(100,origin), to=(100,origin+40), thickness=width, color=theme.header_bg),  # header bg
            self.draw('line', frm=(100,origin+40), to=(100,origin+height), thickness=width, color=theme.bg),  # main bg
            self.draw('line', frm=(100,origin+20), to=(190, origin+20), thickness=24, color=theme.graph_bg),  # cpu graph
            self.draw('ring_graph', conky_value='memperc', center=(172,origin+104), radius=8,
                bar_color=theme.accent1, bar_thickness=4, background_color=theme.graph_bg)  # mem ring
        ] + list(self._cpu_entries(theme, origin))

    def _cpu_entries(self, theme, origin):
        """ Create the draw.lua CPU bars. """
        cpucount = os.cpu_count()                       # Number of cpus on this system
        barwidth = (40 // (cpucount // 2)) - 1          # Width of each bar for trhe given space
        barheight = 15                                  # Height of the bars
        fullwidth = ((barwidth+1) * cpucount) // 2      # Horizontal space needed
        for cpu in range(1, cpucount + 1):
            x = (190-fullwidth) + (cpu*(barwidth+1))
            y = origin + 53
            if cpu-1 >= cpucount // 2:
                x = (190-fullwidth) + (cpu-(cpucount/2)) * (barwidth+1)
                y = origin + 53 + barheight + 5
            yield self.draw('bar_graph', conky_value=f'cpu cpu{cpu}',
                frm=(x,y+barheight), to=(x,y), background_color=theme.graph_bg,
                bar_color=theme.accent1, bar_thickness=barwidth)
