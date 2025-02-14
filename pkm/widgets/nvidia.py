import json5, re, shlex, subprocess
from pkm.widgets.base import BaseWidget
from pkm import CACHE, CONFIG, PKMETER, utils

NVIDIA_CMD = '/usr/bin/nvidia-settings'
NVIDIA_ATTRS = [
    'NvidiaDriverVersion',
    'GPUCoreTemp',
    'GPUCurrentFanSpeedRPM',
    'GPUCurrentClockFreqs',
    'GPUUtilization',
    'TotalDedicatedGPUMemory',
    'UsedDedicatedGPUMemory',
    'RefreshRate',
]


class NvidiaWidget(BaseWidget):
    """ Displays the NVIDIA gpu metrics. """

    def __init__(self, wsettings, origin=0):
        super().__init__(wsettings, origin)
        self.height = 110  # Height of the widget

    def get_conkyrc(self, theme):
        """ Create the conkyrc template for the this widget. """
        tempunit = '°F' if self.temperature_unit == 'fahrenheit' else '°C'
        return utils.clean_spaces(f"""
            ${{texeci 5 {PKMETER} update {self.name}}}\\
            ${{voffset 17}}${{goto 10}}{theme.header}NVIDIA${{font}}
            ${{goto 10}}{theme.subheader}${{execi 60 {PKMETER} get {self.name}.GPUName}} - \\
            ${{execi 60 {PKMETER} get {self.name}.NvidiaDriverVersion}}${{color}}
            ${{voffset 15}}${{goto 10}}{theme.label}GPU Usage${{alignr 55}}{theme.value}${{execi 5 {PKMETER} get {self.name}.GPUUtilization.graphics}}%
            ${{goto 10}}{theme.label}GPU Freq${{alignr 55}}{theme.value}${{execi 5 {PKMETER} get {self.name}.GPUGraphicsFreq}} MHz
            ${{goto 10}}{theme.label}GPU Temp${{alignr 55}}{theme.value}${{execi 5 {PKMETER} get {self.name}.GPUCoreTemp}}{tempunit}
            ${{goto 10}}{theme.label}Mem Used${{alignr 55}}{theme.value}${{execi 5 {PKMETER} get {self.name}.GPUUtilization.memory}}% of \\
              ${{execi 60 {PKMETER} get {self.name}.TotalDedicatedGPUMemory}}
            ${{goto 10}}{theme.label}Mem Rate${{alignr 55}}{theme.value}${{execi 5 {PKMETER} get {self.name}.MemoryTransferRate}} MHz
            ${{goto 10}}{theme.label}Refresh Rate${{alignr 55}}{theme.value}${{execi 5 {PKMETER} get {self.name}.RefreshRate}}
            ${{voffset 3}}{theme.reset}\\
        """)  # noqa

    def get_lua_entries(self):
        """ Create the draw.lua entries for this widget. """
        # origin, height = self.origin, self.height
        # mainbg, maina = utils.rget(CONFIG, 'mainbg', 0x000000), utils.rget(CONFIG, 'mainbg_alpha', 0.6)
        # width = utils.rget(CONFIG, 'conky.maximum_width', 200)
        return [
            # {kind='line', from={x=0,y=333}, to={x=200,y=333}, color='0xFFEEEE', alpha=0.15, thickness=40}, # header
            # {kind='ring_graph', conky_value='execi 5 ~/.pkmeter/pkmeter.py nvidia.percentuseddedicatedgpumemory', center={x=175, y=379}, radius=10, background_color=0xFFFFFF, background_alpha=0.1, background_thickness=5, bar_color=0x98971a, bar_thickness=4},  # gpu ring
        ]

    def update_cache(self):
        """ Fetch NVIDIA valeus from cmdline and update cache. """
        data = {}
        # Query nvidia-settings for the specified attrs
        cmd = shlex.split(f'{NVIDIA_CMD} --query=' + ' --query='.join(NVIDIA_ATTRS))
        stdout = subprocess.check_output(cmd).decode('utf8')
        for key, value in re.findall(r"Attribute '(\w+).+?\:\s(.+?)\.?\n", stdout):
            value = value.strip()
            if '=' in value:
                value = {k:v for k,v in (item.split('=') for item in value.split(','))}
                value = {k.strip():utils.cast_num(v.strip()) for k,v in value.items()}
            data[key.strip()] = utils.cast_num(value)
        # Query nvidia-settings for the GPU Name
        cmd = shlex.split(f'{NVIDIA_CMD} --query=gpus')
        stdout = subprocess.check_output(cmd).decode('utf8')
        match = re.search(r"\[gpu:\d+\] \(NVIDIA (.+?)\)", stdout, re.I)
        data['GPUName'] = match[1] if match else ''
        # Cleanup a few values
        memtotal = data.get('TotalDedicatedGPUMemory', 0)
        memused = data.get('UsedDedicatedGPUMemory', 0)
        freqs = data.get('GPUCurrentClockFreqs', '').split(',')
        data['TotalDedicatedGPUMemory'] = utils.value_to_str(memtotal, utils.MB)
        data['UsedDedicatedGPUMemory'] = utils.value_to_str(memused, utils.MB)
        if self.temperature_unit == 'fahrenheit':
            data['GPUCoreTemp'] = utils.celsius_to_fahrenheit(data.get('GPUCoreTemp', 0))
        if len(freqs) == 2:
            data['GPUGraphicsFreq'] = utils.cast_num(freqs[0])
            data['MemoryTransferRate'] = utils.cast_num(freqs[1]) * 2  # DDR
        # Save the cached response
        with open(f'{CACHE}/{self.name}.json5', 'w') as handle:
            json5.dump(data, handle, indent=2, ensure_ascii=False)
