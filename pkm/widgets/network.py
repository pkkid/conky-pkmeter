import json5, requests
from pkm.widgets.base import BaseWidget
from pkm import CACHE, PKMETER
from pkm import log, utils

EXTERNALIP_URL = 'https://api.ipify.org/?format=json'
NEWLINE = '${voffset 10}\n'


class NetworkWidget(BaseWidget):
    """ Displays the NVIDIA gpu metrics. """

    def __init__(self, wsettings, origin=0):
        super().__init__(wsettings, origin)
        # Header and footer are 67px
        # Each network row adds 49px
        # Subtract 10px no voffset on last device
        self.height = 67 + (len(self.devices) * 49) - 10

    def get_conkyrc(self, theme):
        """ Create the conkyrc template for the this widget. """
        rows = []
        for device in self.devices:
            rows.append(utils.clean_spaces(f"""
                ${{goto 10}}{theme.value}{device}${{alignr 10}}${{addr {device}}}
                ${{goto 10}}{theme.label}Upload{theme.value}${{alignr 10}}${{upspeed {device}}}/s of ${{totalup {device}}}
                ${{goto 10}}{theme.label}Download{theme.value}${{alignr 10}}${{downspeed {device}}}/s of ${{totaldown {device}}}
            """))
        device = self.graph_device or self.devices[0]
        return utils.clean_spaces(f"""
            ${{texeci {self.update_interval} {PKMETER} update {self.name}}}\\
            ${{voffset 22}}${{goto 100}}${{color {self.upload_color}}}${{upspeedgraph {device} 12,90}}
            ${{voffset -2}}${{goto 100}}${{color {self.download_color}}}${{downspeedgraph {device} -11,90}}
            ${{voffset -30}}${{goto 10}}{theme.header}Network
            ${{goto 10}}{theme.subheader}${{execi 60 {PKMETER} get {self.name}.ip}}
            ${{voffset 17}}{NEWLINE.join(rows)}
        """)  # noqa

    def get_lua_entries(self, theme):
        """ Create the draw.lua entries for this widget. """
        origin, width, height = self.origin, self.width, self.height
        return [
            self.draw('line', frm=(100,origin), to=(100,origin+40), thickness=width, color=theme.header_bg),  # header bg
            self.draw('line', frm=(100,origin+40), to=(100,origin+height), thickness=width, color=theme.bg),  # main bg
            self.draw('line', frm=(100,origin+20), to=(190, origin+20), thickness=24, color=theme.graph_bg),  # network graph
        ]

    def update_cache(self):
        """ Fetches the external IP address. """
        log.info(f'Updating {self.name} cache')
        data = requests.get(EXTERNALIP_URL, timeout=10).json()
        filepath = f'{CACHE}/{self.name}.json5'
        with open(filepath, 'w') as handle:
            json5.dump(data, handle, indent=2, ensure_ascii=False)
