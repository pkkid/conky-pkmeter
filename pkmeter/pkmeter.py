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
OPENWEATHER_URL = 'https://api.openweathermap.org/data/2.5/onecall?lat={lat}&lon={lon}&appid={apikey}&exclude=minutely,hourly&units=imperial'  # noqa
OPENWEATHER_ICONS = {
    '01': 'clear-{dn}',             # clear sky
    '02': 'partly-cloudy-{dn}',     # few clouds
    '03': 'cloudy',                 # scattered clouds
    '04': 'cloudy',                 # broken clouds
    '09': 'rain',                   # shower rain
    '10': 'rain',                   # rain (partly)
    '11': 'rain',                   # thunderstorm
    '13': 'snow',                   # snow
    '50': 'fog',                    # mist
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


def get_openweather(key):
    """ Fetch weather from OpenWeather and copy weather images to cache. """
    config = _get_config()
    coords = config.openweather_coords.split(',')
    url = OPENWEATHER_URL.replace('{apikey}', config.openweather_apikey)
    url = url.replace('{lat}', coords[0]).replace('{lon}', coords[1])
    response = requests.get(url, timeout=REQUEST_TIMEOUT)
    with open(join(CACHE, f'{key}.json'), 'w') as handle:
        handle.write(response.content.decode())
        handle.write('\n')
    # copy icons into place
    data = json.loads(response.content.decode())
    iconcode = _rget(data, 'current.weather.0.icon')
    copy_openweather_icon(iconcode, 'current')
    # copy daily icons into place
    for i, day in enumerate(_rget(data, 'daily')[:4]):
        iconcode = _rget(day, 'weather.0.icon')
        copy_openweather_icon(iconcode, f'day{i}')


def copy_openweather_icon(code, day='current'):
    """ Return the icon filepath from its code 03d, 02n etc.. """
    code = code or '01d'  # TODO: Make default icon a questionmark
    num,dn = code[:2], 'day' if code[2] == 'd' else 'night'
    source = join(ROOT, 'img', OPENWEATHER_ICONS[num].replace('{dn}',dn) + '.png')
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
