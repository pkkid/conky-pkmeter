#!/usr/bin/env python3
import json, os, socket
import argparse, requests
import shlex, subprocess
from datetime import datetime
from os.path import join
from jinja2 import Template
from shutil import copyfile

config = None  # cached config object
ROOT = os.path.expanduser('~/.pkmeter')
CACHE = os.path.expanduser('~/.cache/pkmeter')
BYTE, KB, MB = 1, 1024, 1048576
BYTES1024 = ((2**50,'P'), (2**40,'T'), (2**30,'G'), (2**20,'M'), (2**10,'K'), (1,'B'))
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


class Bunch(dict):
    def __getattr__(self, item):
        return self.__getitem__(item)

    def __setattr__(self, item, value):
        return self.__setitem__(item, value)


def _get_config():
    global config
    if not config:
        hostname = socket.gethostname()
        with open(join(ROOT, 'config.json'), 'r') as handle:
            config = json.load(handle)
        config['default'].update(config.get(hostname, {}))
        config = Bunch(config['default'])
    return config


def _celsius_to_fahrenheit(value):
    return int(value * 9 / 5 + 32)


def _percent(numerator, denominator, precision=2, maxval=999.9, default=0.0):
    if not denominator:
        return default
    return min(maxval, round((numerator / float(denominator)) * 100.0, precision))


def _rget(obj, attrstr, default=None, delim='.'):
    try:
        parts = attrstr.split(delim, 1)
        attr = parts[0]
        attrstr = parts[1] if len(parts) == 2 else None
        if isinstance(obj, dict): value = obj[attr]
        elif isinstance(obj, list): value = obj[int(attr)]
        if attrstr: return _rget(value, attrstr, default, delim)
        return value
    except Exception:
        return default


def _to_int(value, default=None):
    try:
        return int(value)
    except Exception:
        return default


def _value_to_str(value, unit=BYTE, precision=0, separator=''):
    if value is None: return ''
    value = value * unit
    for div, unit in BYTES1024:
        if value >= div:
            conversion = round(value / div, int(precision)) if precision else int(value / div)
            return '%s%s%s' % (conversion, separator, unit)
    return '0%s%s' % (separator, unit)


def get_conkyrc(key):
    """ Create a new conkyrc from from config.json. """
    config = _get_config()
    # create the config.lua file
    with open(join(ROOT, 'templates/lua.tmpl')) as handle:
        template = Template(handle.read())
    dest = join(ROOT, 'config.lua')
    print(f'Creating config.lua script at {dest}')
    with open(dest, 'w') as handle:
        handle.write(template.render(**config))
    # create the conkyrc file
    with open(join(ROOT, 'templates/conkyrc.tmpl')) as handle:
        template = Template(handle.read())
    dest = os.path.expanduser('~/.conkyrc')
    print(f'Creating conkyrc script at {dest}')
    with open(dest, 'w') as handle:
        handle.write(template.render(**config))


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
        handle.write(json.dumps(data))
        handle.write('\n')


def copy_openweather_icon(iconname, day='current'):
    """ Return the icon filepath from its code 03d, 02n etc.. """
    source = join(ROOT, 'img', iconname + '.png')
    dest = join(CACHE, f'{day}.png')
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
    memtotal = _to_int(values.get('totaldedicatedgpumemory'), 0)
    memused = _to_int(values.get('useddedicatedgpumemory'), 0)
    values['gpucoretemp'] = _celsius_to_fahrenheit(_to_int(values.get('gpucoretemp')))
    values['freededicatedgpumemory'] = _value_to_str(memtotal - memused, MB)
    values['totaldedicatedgpumemory'] = _value_to_str(_to_int(values.get('totaldedicatedgpumemory')), MB)
    values['useddedicatedgpumemory'] = _value_to_str(_to_int(values.get('useddedicatedgpumemory')), MB)
    values['percentuseddedicatedgpumemory'] = int(_percent(memused, memtotal, 0))
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
        json.dump(values, handle)


def lookup_value(key, opts):
    """ Lookup the specified key from the cached json files. """
    try:
        key, path = key.split('.', 1)
        filepath = join(CACHE, f'{key}.json')
        with open(filepath, 'r') as handle:
            data = json.load(handle)
        value = _rget(data, path, None)
        if value is None: return opts.default
        if opts.round: value = round(float(value), opts.round)
        if opts.int: value = int(value)
        if opts.format: value = datetime.fromtimestamp(int(value)).strftime(opts.format)
        return value
    except Exception:
        return opts.default


if __name__ == '__main__':
    os.makedirs(CACHE, exist_ok=True)
    parser = argparse.ArgumentParser(description='Helper tools for pkmeter.')
    parser.add_argument('key', help='Item key to get or update')
    parser.add_argument('args', nargs='*', help='Args to pass key function')
    parser.add_argument('-d', '--default', default='', help='Default value if not found')
    parser.add_argument('-r', '--round', type=int, help='Round to nearest decimal')
    parser.add_argument('-i', '--int', action='store_true', default=False, help='Cast value to int')
    parser.add_argument('-f', '--format', help='Format datetime')
    opts = parser.parse_args()
    # lookup value in previous json output
    if '.' in opts.key:
        print(lookup_value(opts.key, opts))
        raise SystemExit()
    # run all get_ functions
    if opts.key == 'all':
        for name in list(globals().keys()):
            if name.startswith('get_'):
                func = globals()[name]
                func(name.replace('get_', ''))
        raise SystemExit()
    # run the specified get_ function
    func = globals().get(f'get_{opts.key}', None)
    func(opts.key, *opts.args)
