import os
from pkm.widgets.base import BaseWidget
from pkm import CONFIG, utils


class SystemWidget(BaseWidget):
    """ Displays PC system metrics. """

    def __init__(self, wconfig, origin=0):
        self.wconfig = wconfig      # Widget configuration object
        self.origin = origin        # Starting ypos of the widget
        self.height = 123           # Height of the widget

    def get_conkyrc(self):
        """ Create the conkyrc template for the this widget. """
        # wc = namedtuple('wconfig', self.wconfig.keys())(*self.wconfig.values())
        return utils.clean_spaces(f"""
            ${{voffset 17}}${{goto 100}}${{color1}}${{cpugraph cpu0 24,90 -l}}${{color}}
            ${{voffset -36}}${{goto 10}}${{font ubuntu:bold:size=9}}System${{font}}
            ${{goto 10}}${{color1}}${{font ubuntu:bold:size=8}}${{nodename}}${{color}}
            ${{voffset 17}}${{goto 10}}${{color2}}CPU Usage${{color}}${{alignr 55}}${{cpu cpu0}}%
            ${{goto 10}}${{color2}}CPU Uptime${{color}}${{alignr 55}}${{uptime_short}}
            ${{goto 10}}${{color2}}Mem Used${{color}}${{alignr 55}}${{mem}}
            ${{goto 10}}${{color2}}Mem Free${{color}}${{alignr 55}}${{memeasyfree}}
            ${{font}}${{color}}${{voffset 3}}\\
        """)  # noqa

    def get_lua_entries(self):
        """ Create the draw.lua entries for this widget. """
        origin, height = self.origin, self.height
        mainbg, maina = utils.rget(CONFIG, 'mainbg', 0x000000), utils.rget(CONFIG, 'mainbg_alpha', 0.6)
        headbg, heada = utils.rget(CONFIG, 'headerbg', 0x000000), utils.rget(CONFIG, 'headerbg_alpha', 0.6)
        width = utils.rget(CONFIG, 'conky.maximum_width', 200)
        # Create the CPU Bars
        cpuentries = []
        cpucount = os.cpu_count()
        barwidth = int(40 / (cpucount/2)) - 1
        barheight = 9
        fullwidth = (barwidth+1) * (cpucount/2)
        for cpu in range(1, cpucount+1):
            x = (190-fullwidth) + (cpu * (barwidth+1))
            y = origin + 53
            if cpu - 1 >= cpucount / 2:
                x = (190-fullwidth) + (cpu - (cpucount/2)) * (barwidth+1)
                y = origin + 65
            cpuentries.append(self.bargraph(value=f'cpu cpu{cpu}', start=(x,y+barheight), end=(x,y),
                bgcolor='0xffffff', bgalpha=0.1, color=0xD79921, thickness=barwidth))
        # Build and return the entries
        return [
            self.line(start=(100, origin), end=(100, origin+40), color=headbg, alpha=heada, thickness=width),  # header
            self.line(start=(100, origin+40), end=(100, origin+height), color=mainbg, alpha=maina, thickness=width),  # background
            self.line(start=(100, origin+20), end=(190, origin+20), color=0x000000, alpha=0.2, thickness=24),  # cpu graph
            self.ringgraph(value='memperc', center=(173,origin+91), radius=8, bgcolor=0xffffff, bgalpha=0.1, color=0xD79921, thickness=4),  # memory ring
        ] + cpuentries
