#!/usr/bin/env python3
import json5, os, sys
import argparse, requests
import shlex, subprocess
import importlib
from datetime import datetime
from os.path import abspath, dirname, expanduser, join
from jinja2 import Template
from shutil import copyfile

sys.path.append(dirname(abspath(__file__)))
from pkmeter import utils  # noqa

ROOT = f'{dirname(abspath(__file__))}'
CACHE = f'{dirname(abspath(__file__))}/pkmeter/cache'
REQUEST_TIMEOUT = 10

EXTERNALIP_URL = 'https://api.ipify.org/?format=json'
NVIDIA_CMD = '/usr/bin/nvidia-settings'
NVIDIA_ATTRS = [
    'nvidiadriverversion',
    'gpucoretemp',
    'gpucurrentfanspeedrpm',
    'gpuutilization',
    'totaldedicatedgpumemory',
    'useddedicatedgpumemory',
]
NVIDIA_QUERY = '%s --query=%s' % (NVIDIA_CMD, ' --query='.join(NVIDIA_ATTRS))
OPENMETEO_URL = ('https://api.open-meteo.com/v1/forecast?latitude=42.20&longitude=-71.42'
    '&current_weather=1&temperature_unit=fahrenheit&windspeed_unit=mph&timezone=America%2FNew_York'
    '&daily=weathercode,apparent_temperature_max,sunrise,sunset')
OPENMETEO_WEATHERCODES = {
    0: {'text':'Clear', 'icon':'clear-day'},
    1: {'text':'Mostly Clear', 'icon':'partly-cloudy-day'},
    2: {'text':'Partly Cloudy', 'icon':'partly-cloudy-day'},
    3: {'text':'Overcast', 'icon':'cloudy'},
    45: {'text':'Fog', 'icon':'fog'},
    48: {'text':'Rime Fog', 'icon':'fog'},
    51: {'text':'Light Drizzle', 'icon':'rain'},
    53: {'text':'Drizzle', 'icon':'rain'},
    55: {'text':'Heavy Drizzle', 'icon':'rain'},
    56: {'text':'Light Freezing Drizzle', 'icon':'sleet'},
    57: {'text':'Heavy Freezing Drizzle', 'icon':'sleet'},
    61: {'text':'Light Rain', 'icon':'rain'},
    63: {'text':'Rain', 'icon':'rain'},
    65: {'text':'Heavy Rain', 'icon':'rain'},
    66: {'text':'Light Freezing Rain', 'icon':'rain'},
    67: {'text':'Heavy Freezing Rain', 'icon':'rain'},
    71: {'text':'Light Snow', 'icon':'snow'},
    73: {'text':'Snow', 'icon':'snow'},
    75: {'text':'Heavy Snow', 'icon':'snow'},
    77: {'text':'Hail', 'icon':'rain'},
    80: {'text':'Light Rain Showers', 'icon':'rain'},
    81: {'text':'Rain Showers', 'icon':'rain'},
    82: {'text':'Heavy Rain Showers', 'icon':'rain'},
    85: {'text':'Light Snow Showers', 'icon':'sleet'},
    86: {'text':'Heavy Snow Showers', 'icon':'sleet'},
    95: {'text':'Thunderstorm', 'icon':'rain'},
    96: {'text':'Thunderstorm w/ Hail', 'icon':'rain'},
    99: {'text':'Thunderstorm w/ Heavy Hail', 'icon':'rain'},
}
HEIGHT = {
    'clock': 81,
    'weather': 123,
    'system': 123,
    'nvidia': 123,
    'processes': 123,
    'network': 123,
    'filesystem': 123,
    'line': 123,
    'padding': 123,
}


def create_conkyrc():
    """ Create a new conkyrc from from config.json. """
    luaentries = []
    pconfig = utils.get_config(ROOT)
    # Generate the conky.config
    conkyrc = 'conky.config = {\n'
    for key, value in pconfig['conky'].items():
        value = value.replace('{ROOT}', ROOT) if isinstance(value, str) else value
        value = value.lstrip('#') if 'color' in key else value
        value = f'"{value}"' if isinstance(value, str) else value
        value = str(value).lower() if isinstance(value, bool) else value
        conkyrc += f'  {key}={value},\n'
    conkyrc += '}\n\n'
    # Iterate through the widgets
    conkyrc += 'conky.text = [[\n'
    for wconfig in pconfig['widgets']:
        modpath, clsname = wconfig['class'].rsplit('.', 1)
        module = importlib.import_module(modpath)
        widget = getattr(module, clsname)(pconfig, wconfig)
        conkyrc += widget.get_conkyrc()
        luaentries += widget.get_lua_entries()
    conkyrc += ']]\n'
    # Save the conkyrc file
    filepath = expanduser('~/.conkyrc')
    print(f'Creating conkyrc script at {filepath}')
    with open(filepath, 'w') as handle:
        handle.write(conkyrc)
    # Save the conflig.lua file
    filepath = f'{ROOT}/pkmeter/config.lua'
    print(f'Creating config.lua script at {filepath}')
    with open(filepath, 'w') as handle:
        handle.write('elements = [\n')
        handle.write('\n'.join(f'  {item}\n' for item in luaentries))
        handle.write(']\n')
    print(conkyrc)


    # # create the config.lua file
    # with open(join(ROOT, 'pkmeter/templates/lua.tmpl')) as handle:
    #     template = Template(handle.read())
    # dest = f'{ROOT}/pkmeter/config.lua'
    # print(f'Creating config.lua script at {dest}')
    # with open(dest, 'w') as handle:
    #     handle.write(template.render(**config))
    # # create the conkyrc file
    # with open(join(ROOT, 'pkmeter/templates/conkyrc.tmpl')) as handle:
    #     template = Template(handle.read())
    # dest = os.path.expanduser('~/.conkyrc')
    # print(f'Creating conkyrc script at {dest}')
    # with open(dest, 'w') as handle:
    #     handle.write(template.render(**config))


def get_weather(key):
    """ Fetch weather from OpenWeather and copy weather images to cache. """
    url = OPENMETEO_URL
    data = requests.get(url, timeout=REQUEST_TIMEOUT).json()
    # get current weather
    weathercode = data['current_weather']['weathercode']
    data['current_text'] = OPENMETEO_WEATHERCODES[weathercode]['text']
    iconname = OPENMETEO_WEATHERCODES[weathercode]['icon']
    copy_openweather_icon(iconname, 'current')
    # get future weather
    data['daily']['text'], data['daily']['day'] = [], []
    for i in range(4):
        weathercode = data['daily']['weathercode'][i]
        text = OPENMETEO_WEATHERCODES[weathercode]['text']
        day = datetime.strptime(data['daily']['time'][i], '%Y-%m-%d').strftime('%a')
        data['daily']['text'].append(text)
        data['daily']['day'].append(day)
        iconname = OPENMETEO_WEATHERCODES[weathercode]['icon']
        copy_openweather_icon(iconname, f'day{i}')
    with open(join(CACHE, f'{key}.json'), 'w') as handle:
        handle.write(json5.dumps(data))
        handle.write('\n')


def copy_openweather_icon(iconname, day='current'):
    """ Return the icon filepath from its code 03d, 02n etc.. """
    source = f'{ROOT}/pkmeter/img/{iconname}.png'
    dest = f'{CACHE}/{day}.png'
    copyfile(source, dest)


def get_externalip(key):
    """ Fetch external IP. """
    response = requests.get(EXTERNALIP_URL, timeout=REQUEST_TIMEOUT)
    with open(join(CACHE, f'{key}.json'), 'w') as handle:
        handle.write(response.content.decode())
        handle.write('\n')


def get_nvidia(key):
    """ Fetch NVIDIA values. To get card name run..
        /usr/bin/nvidia-settings --glxinfo | grep -i opengl.renderer
    """
    # fetch values from cmdline tool
    values = {}
    cmd = shlex.split(NVIDIA_QUERY)
    result = subprocess.check_output(cmd).decode('utf8')
    for line in result.split('\n'):
        line = line.lower().strip(' .').replace("'", '')
        for attr in NVIDIA_ATTRS:
            if line.startswith(f'attribute {attr} ') and ':0]' in line:
                value = line.split(':')[-1].strip()
                values[attr] = value
    # cleanup gpuutilization values
    for subpart in values.pop('gpuutilization').strip(' ,').split(','):
        subkey, subvalue = subpart.split('=')
        values[f'gpuutilization{subkey.strip()}'] = subvalue
    # convert and make values human readable
    memtotal = utils.to_int(values.get('totaldedicatedgpumemory'), 0)
    memused = utils.to_int(values.get('useddedicatedgpumemory'), 0)
    values['gpucoretemp'] = utils.celsius_to_fahrenheit(utils.to_int(values.get('gpucoretemp')))
    values['freededicatedgpumemory'] = utils.value_to_str(memtotal - memused, utils.MB)
    values['totaldedicatedgpumemory'] = utils.value_to_str(utils.to_int(values.get('totaldedicatedgpumemory')), utils.MB)
    values['useddedicatedgpumemory'] = utils.value_to_str(utils.to_int(values.get('useddedicatedgpumemory')), utils.MB)
    values['percentuseddedicatedgpumemory'] = int(utils.percent(memused, memtotal, 0))
    # fetch nvidia card name
    cmd = shlex.split(f'{NVIDIA_CMD} --glxinfo')
    for line in subprocess.check_output(cmd).decode('utf8').split('\n'):
        if line.strip().lower().startswith('opengl renderer string:'):
            cardname = line.split(':', 1)[1].split('/')[0]
            cardname = cardname.replace('NVIDIA', '')
            cardname = cardname.replace(' Ti', 'ti')
            values['cardname'] = cardname.strip()
    # save values to cache
    with open(join(CACHE, f'{key}.json'), 'w') as handle:
        json5.dump(values, handle)


def lookup_value(key, opts):
    """ Lookup the specified key from the cached json files. """
    try:
        key, path = key.split('.', 1)
        filepath = join(CACHE, f'{key}.json')
        with open(filepath, 'r') as handle:
            data = json5.load(handle)
        value = utils.rget(data, path, None)
        if value is None: return opts.default
        if opts.round: value = round(float(value), opts.round)
        if opts.int: value = int(value)
        if opts.format: value = datetime.fromtimestamp(int(value)).strftime(opts.format)
        return value
    except Exception:
        return opts.default


if __name__ == '__main__':
    # Command line parser. Available commands are:
    #  * conkyrc: generate new conkyrc & config.lua files from config.json
    #  * get <widget> <key>: get the specified widget value
    os.makedirs(CACHE, exist_ok=True)
    parser = argparse.ArgumentParser(description='Helper tools for pkmeter.')
    subparsers = parser.add_subparsers(title='available commands', dest='command')
    conkyrc_parser = subparsers.add_parser('conkyrc', help='generate new conkyrc & config.lua files from config.json')
    get_parser = subparsers.add_parser('get', help='get the specified widget value')
    get_parser.add_argument('widget', help='widget class name to get value from')
    get_parser.add_argument('key', help='value to lookup from the specified widget dataset')
    get_parser.add_argument('-d', dest='default', default='', help='default value if not found')
    get_parser.add_argument('-r', dest='round', type=int, help='round to nearest decimal')
    get_parser.add_argument('-i', dest='int', action='store_true', default=False, help='cast value to integer')
    get_parser.add_argument('-f', dest='format', help='format value to datetime')
    # Run the specified command
    opts = parser.parse_args()
    if opts.command == 'conkyrc':
        create_conkyrc()
    if opts.command == 'get':
        print(opts)

    # # lookup value in previous json output
    # if '.' in opts.key:
    #     print(lookup_value(opts.key, opts))
    #     raise SystemExit()
    # # run all get_ functions
    # if opts.key == 'all':
    #     for name in list(globals().keys()):
    #         if name.startswith('get_'):
    #             func = globals()[name]
    #             func(name.replace('get_', ''))
    #     raise SystemExit()
    # # run the specified get_ function
    # func = globals().get(f'get_{opts.key}', None)
    # func(opts.key, *opts.args)
