import json5, shlex, subprocess
from collections import namedtuple
from pkm.widgets.base import BaseWidget
from pkm import ROOT, CACHE, CONFIG, PKMETER, utils

NVIDIA_CMD = '/usr/bin/nvidia-settings'
NVIDIA_ATTRS = ['nvidiadriverversion', 'gpucoretemp', 'gpucurrentfanspeedrpm',
    'gpuutilization', 'totaldedicatedgpumemory', 'useddedicatedgpumemory']
NVIDIA_QUERY = f'{NVIDIA_CMD} --query={" --query=".join(NVIDIA_ATTRS)}'


class NvidiaWidget(BaseWidget):
    """ Displays the NVIDIA gpu metrics. """

    def __init__(self, wconfig, origin=0):
        self.wconfig = wconfig      # Widget configuration object
        self.origin = origin        # Starting ypos of the widget
        self.height = 85            # Height of the widget

    def get_conkyrc(self):
        """ Create the conkyrc template for the this widget. """
        return utils.clean_spaces(f"""
            ${{texeci 5 {PKMETER} update nvidia}}\\
            ${{voffset 17}}${{goto 10}}${{font ubuntu:bold:size=9}}NVIDIA${{font}}
            ${{goto 10}}${{color1}}${{execi 60 {PKMETER} get nvidia.cardname}}\\
              ${{execi 60 {PKMETER} get nvidia.nvidiadriverversion}}${{color}}
            ${{voffset 15}}${{goto 10}}${{color2}}GPU Usage${{color}}${{alignr 55}}${{execi 5 {PKMETER} get nvidia.gpuutilizationgraphics}}%
            ${{goto 10}}${{color2}}GPU Temp${{color}}${{alignr 55}}${{execi 5 {PKMETER} get nvidia.gpucoretemp}}°F
            ${{goto 10}}${{color2}}Mem Used${{color}}${{alignr 55}}${{execi 5 {PKMETER} get nvidia.percentuseddedicatedgpumemory}}% of \\
              ${{execi 60 {PKMETER} get nvidia.freededicatedgpumemory}}
        """)  # noqa

    def get_lua_entries(self):
        """ Create the draw.lua entries for this widget. """
        origin, height = self.origin, self.height
        mainbg, maina = utils.rget(CONFIG, 'mainbg', 0x000000), utils.rget(CONFIG, 'mainbg_alpha', 0.6)
        width = utils.rget(CONFIG, 'conky.maximum_width', 200)
        return [
            # {kind='line', from={x=0,y=333}, to={x=200,y=333}, color='0xFFEEEE', alpha=0.15, thickness=40}, # header
            # {kind='ring_graph', conky_value='execi 5 ~/.pkmeter/pkmeter.py nvidia.percentuseddedicatedgpumemory', center={x=175, y=379}, radius=10, background_color=0xFFFFFF, background_alpha=0.1, background_thickness=5, bar_color=0x98971a, bar_thickness=4},  # gpu ring
        ]

    def update_cache(self):
        """ Fetch NVIDIA valeus from cmdline and update cache.
            Note: To get card name: /usr/bin/nvidia-settings --glxinfo | grep -i opengl.renderer
        """
        # fetch values from cmdline tool
        data = {}
        cmd = shlex.split(NVIDIA_QUERY)
        result = subprocess.check_output(cmd).decode('utf8')
        for line in result.split('\n'):
            line = line.lower().strip(' .').replace("'", '')
            for attr in NVIDIA_ATTRS:
                if line.startswith(f'attribute {attr} ') and ':0]' in line:
                    value = line.split(':')[-1].strip()
                    data[attr] = value
        # cleanup gpuutilization data
        for subpart in data.pop('gpuutilization').strip(' ,').split(','):
            subkey, subvalue = subpart.split('=')
            data[f'gpuutilization{subkey.strip()}'] = subvalue
        # convert and make data human readable
        memtotal = utils.to_int(data.get('totaldedicatedgpumemory'), 0)
        memused = utils.to_int(data.get('useddedicatedgpumemory'), 0)
        data['gpucoretemp'] = utils.celsius_to_fahrenheit(utils.to_int(data.get('gpucoretemp')))
        data['freededicatedgpumemory'] = utils.value_to_str(memtotal - memused, utils.MB)
        data['totaldedicatedgpumemory'] = utils.value_to_str(utils.to_int(data.get('totaldedicatedgpumemory')), utils.MB)
        data['useddedicatedgpumemory'] = utils.value_to_str(utils.to_int(data.get('useddedicatedgpumemory')), utils.MB)
        data['percentuseddedicatedgpumemory'] = int(utils.percent(memused, memtotal, 0))
        # fetch nvidia card name
        cmd = shlex.split(f'{NVIDIA_CMD} --glxinfo')
        for line in subprocess.check_output(cmd).decode('utf8').split('\n'):
            if line.strip().lower().startswith('opengl renderer string:'):
                cardname = line.split(':', 1)[1].split('/')[0]
                cardname = cardname.replace('NVIDIA', '')
                cardname = cardname.replace(' Ti', 'ti')
                data['cardname'] = cardname.strip()
        # save the cached response
        key = utils.get_shortname(self.__class__.__name__)
        with open(f'{CACHE}/{key}.json', 'w') as handle:
            json5.dump(data, handle, indent=2, ensure_ascii=False)
