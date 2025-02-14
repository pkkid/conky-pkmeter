import os
from pkm.widgets.base import BaseWidget
from pkm import CONFIG, utils


class SystemWidget(BaseWidget):
    """ Displays PC system metrics. """

    def __init__(self, wsettings, origin=0):
        super().__init__(wsettings, origin)
        self.height = 132

    def get_conkyrc(self, theme):
        """ Create the conkyrc template for the this widget. """
        return utils.clean_spaces(f"""
            ${{voffset 17}}${{goto 100}}{theme.accent}${{cpugraph cpu0 24,90 -l}}${{color}}
            ${{voffset -36}}${{goto 10}}{theme.header}System
            ${{goto 10}}{theme.subheader}${{nodename}}
            ${{voffset 17}}${{goto 10}}{theme.label}CPU Usage${{alignr 55}}{theme.value}${{cpu cpu0}}%
            ${{goto 10}}{theme.label}CPU Freq${{alignr 55}}{theme.value}${{freq}} MHz
            ${{goto 10}}{theme.label}CPU Uptime${{alignr 55}}{theme.value}${{uptime_short}}
            ${{goto 10}}{theme.label}Mem Used${{alignr 55}}{theme.value}${{mem}}
            ${{goto 10}}{theme.label}Mem Free${{alignr 55}}{theme.value}${{memeasyfree}}
            {theme.reset}\\
        """)  # noqa

    def get_lua_entries(self):
        """ Create the draw.lua entries for this widget. """
        origin = self.origin
        width = CONFIG['conky']['maximum_width']
        accent = CONFIG['conky']['color1']
        return [
            self.line(start=(100, origin), end=(100, origin+40), thickness=width, **CONFIG['headerbg']),  # header
            self.line(start=(100, origin+40), end=(100, origin+self.height), thickness=width, **CONFIG['mainbg']),  # background
            self.line(start=(100, origin+20), end=(190, origin+20), thickness=24, **CONFIG['headergraphbg']),  # cpu graph
            self.ringgraph(value='memperc', center=(173,origin+104), radius=8, color=accent, thickness=4, **CONFIG['graphbg']),  # memory ring
        ] + self.get_lua_cpu_bars()

    def get_lua_cpu_bars(self):
        """ Create the draw.lua CPU bars. """
        entries = []
        cpucount = os.cpu_count()
        barwidth = int(40 / (cpucount/2)) - 1
        barheight = 15
        fullwidth = (barwidth+1) * (cpucount/2)
        for cpu in range(1, cpucount+1):
            x = (190-fullwidth) + (cpu * (barwidth+1))
            y = self.origin + 53
            if cpu - 1 >= cpucount / 2:
                x = (190-fullwidth) + (cpu - (cpucount/2)) * (barwidth+1)
                y = self.origin + 53 + barheight + 5
            entries.append(self.bargraph(value=f'cpu cpu{cpu}', start=(x,y+barheight), end=(x,y),
                bgcolor='0xffffff', bgalpha=0.1, color=0xD79921, thickness=barwidth))
        return entries
