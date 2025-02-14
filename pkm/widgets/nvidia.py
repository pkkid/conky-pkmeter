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

NVIDIA_SMI = '/usr/bin/nvidia-smi --format=csv'
QUERY_GPU = [
    'name',
    'driver_version',
    'clocks.current.graphics',
    'clocks.current.memory',
    'clocks.current.sm',
    'clocks.current.video',
    'clocks.max.graphics',
    'clocks.max.memory',
    'clocks.max.sm',
    # 'clocks.max.video',
    'fan.speed',
    'memory.total',
    'memory.used',
    'power.draw',
    'power.limit',
    'pstate',
    'temperature.gpu',
    'utilization.gpu',
    'utilization.memory',
]


class NvidiaWidget(BaseWidget):
    """ Displays the NVIDIA gpu metrics. """

    def __init__(self, wsettings, origin=0):
        super().__init__(wsettings, origin)
        self.height = 110  # Height of the widget

    def get_conkyrc(self, theme):
        """ Create the conkyrc template for the this widget. """
        return utils.clean_spaces(f"""
            ${{texeci 2 {PKMETER} update {self.name}}}\\
            ${{voffset 20}}${{goto 10}}{theme.header}NVIDIA${{font}}
            ${{goto 10}}{theme.subheader}${{execi 60 {PKMETER} get {self.name}.name}} - \\
            ${{execi 60 {PKMETER} get {self.name}.driver_version}}${{color}}
            ${{voffset 15}}${{goto 10}}{theme.label}GPU Usage${{alignr 55}}{theme.value}${{execi 5 {PKMETER} get {self.name}.utilization_gpu}}%
            ${{goto 10}}{theme.label}GPU Freq${{alignr 55}}{theme.value}${{execi 5 {PKMETER} get {self.name}.clocks_current_graphics}}
            ${{goto 10}}{theme.label}GPU Temp${{alignr 55}}{theme.value}${{execi 5 {PKMETER} get {self.name}.temperature_gpu}}
            ${{goto 10}}{theme.label}Mem Used${{alignr 55}}{theme.value}${{execi 5 {PKMETER} get {self.name}.utilization_memory}}% of \\
              ${{execi 60 {PKMETER} get {self.name}.memory_total_gb}}
            ${{goto 10}}{theme.label}Mem Rate${{alignr 55}}{theme.value}${{execi 5 {PKMETER} get {self.name}.memory_transfer_rate}}
            ${{goto 10}}{theme.label}Power Draw${{alignr 55}}{theme.value}${{execi 5 {PKMETER} get {self.name}.power_draw}}
            ${{voffset 3}}{theme.reset}\\
        """)  # noqa

    def get_lua_entries(self):
        """ Create the draw.lua entries for this widget. """
        origin = self.origin
        width = CONFIG['conky']['maximum_width']
        memvalue = f'execi 5 {PKMETER} get {self.name}.utilization_memory'
        accent = CONFIG['conky']['color4']
        return [
            self.line(start=(100, origin), end=(100, origin+40), thickness=width, **CONFIG['headerbg']),  # header
            self.ringgraph(value=memvalue, center=(173,origin+104), radius=10, color=accent, thickness=4, **CONFIG['graphbg'])  # memory ring
        ]

    def update_cache(self):
        """ Fetch NVIDIA valeus from cmdline and update cache. """
        data = {}
        # Query nvidia-settings for the specified attrs
        cmd = shlex.split(f'{NVIDIA_SMI} --query-gpu={",".join(QUERY_GPU)}')
        stdout = subprocess.check_output(cmd).decode('utf8').strip().split('\n')
        keys = [k.strip().replace('.','_').split(' [')[0] for k in stdout[0].split(',')]
        values = [v.strip() for v in stdout[1].split(',')]
        data = dict(zip(keys, values))
        # Clean up a few vaslues
        data['name'] = data['name'].replace('NVIDIA','').strip()
        data['memory_transfer_rate'] = str(int(data['clocks_current_memory'].split()[0]) * 2) + ' MHz'
        data['memory_total_gb'] = str(int(round(int(data['memory_total'].split()[0]) / 1024, 0))) + ' GB'
        data['utilization_gpu'] = int(data['utilization_gpu'].split()[0])
        data['utilization_memory'] = int(data['utilization_memory'].split()[0])
        data['utilization_power'] = utils.percent(float(data['power_draw'].split()[0]), float(data['power_limit'].split()[0]), 0)
        if self.temperature_unit == 'fahrenheit':
            data['temperature_gpu'] = utils.celsius_to_fahrenheit(int(data['temperature_gpu']))
            data['temperature_gpu'] = str(data['temperature_gpu']) + f'°{self.temperature_unit[0].upper()}'
        # Save the cached response
        with open(f'{CACHE}/{self.name}.json5', 'w') as handle:
            json5.dump(data, handle, indent=2, ensure_ascii=False)
