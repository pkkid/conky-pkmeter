#!/usr/bin/env python3
import json, os, socket
import argparse, requests
import shlex, subprocess
from datetime import datetime, timedelta
from os.path import join
from jinja2 import Template
from shutil import copyfile
from plexapi.server import PlexServer

ROOT = os.path.expanduser('~/.pkmeter')
CACHE = os.path.expanduser('~/.cache/pkmeter')
BYTE, KB, MB = 1, 1024, 1048576
BYTES1024 = ((2**50,'P'), (2**40,'T'), (2**30,'G'), (2**20,'M'), (2**10,'K'), (1,'B'))
DARKSKY_URL = 'https://api.darksky.net/forecast/{apikey}/{coords}'
EXTERNALIP_URL = 'https://api6.ipify.org/?format=json'
SICKRAGE_URL = '{host}/api/{apikey}/?cmd=future&limit=10'
NVIDIA_CMD = '/usr/bin/nvidia-settings'
NVIDIA_ATTRS = ('nvidiadriverversion', 'gpucoretemp', 'gpucurrentfanspeedrpm',
    'gpuutilization', 'totaldedicatedgpumemory', 'useddedicatedgpumemory')
NVIDIA_QUERY = '%s --query=%s' % (NVIDIA_CMD, ' --query='.join(NVIDIA_ATTRS))
REQUEST_TIMEOUT = 10
config = None  # cached config object


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


def _datetime_to_str(dt):
    if (datetime.now() - dt) < timedelta(hours=23):
        return dt.strftime('%-I:%M%p').lower().replace('m','')
    if (datetime.now() - dt) < timedelta(days=6):
        return dt.strftime('%a')
    return dt.strftime('%b %-d')


def _celsius_to_fahrenheit(value):
    return int(value * 9 / 5 + 32)


def _ignored(title, ignored):
    for ignore in ignored:
        if ignore.lower() in title.lower():
            return True
    return False


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


def _safe_unlink(path):
    try:
        os.unlink(path)
    except Exception:
        pass


def _sickrage_datestr(stype, show):
    if stype == 'missed': return 'Missed'
    if stype == 'later': return datetime.strptime(show['airdate'], '%Y-%m-%d').strftime('%b %d')
    airday = show['airs'].split(' ', 1)[0][:3]
    airtime = show['airs'].split(' ', 1)[1].replace(':00','')
    airtime = airtime.replace(' AM','a').replace(' PM','p')
    return 'Today %s' % airtime if stype == 'today' else '%s %s' % (airday, airtime)


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


def _video_length(length):
    hours = int(length / 3600000)
    minutes = int((length - (hours * 3600000)) / 60000)
    return '%s:%02d' % (hours, minutes)


def _video_title(video):
    if video.type == 'season':
        episode = video.episodes()[-1]
        title = f'{episode.grandparentTitle} {episode.seasonEpisode}'
    elif video.type == 'episode':
        title = f'{video.grandparentTitle} {video.seasonEpisode}'
    else:
        title = f'{video.title} {video.year}'
    title = title.replace('s0','s').replace('e0','e')
    return title[:20]


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


def get_darksky(key):
    """ Fetch weather from DarkSky and copy weather images to cache. """
    config = _get_config()
    url = DARKSKY_URL.replace('{apikey}', config.darksky_apikey)
    url = url.replace('{coords}', config.darksky_coords)
    response = requests.get(url, timeout=REQUEST_TIMEOUT)
    with open(join(CACHE, f'{key}.json'), 'w') as handle:
        handle.write(response.content.decode())
        handle.write('\n')
    # copy icons into place
    data = json.loads(response.content.decode())
    source = join(ROOT, 'img', _rget(data, 'currently.icon')) + '.png'
    dest = join(CACHE, 'current.png')
    copyfile(source, dest)
    # copy daily icons into place
    for i, day in enumerate(_rget(data, 'daily.data')[:4]):
        source = join(ROOT, 'img', _rget(day, 'icon')) + '.png'
        dest = join(CACHE, f'day{i}.png')
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
            values['cardname'] = line.split(':', 1)[1].split('/')[0].strip()
    # save values to cache
    with open(join(CACHE, f'{key}.json'), 'w') as handle:
        json.dump(values, handle)


def get_plexadded(key):
    """ Fetch plex recently added. """
    values = []
    plex = PlexServer()
    config = _get_config()
    recent = plex.library.recentlyAdded()
    recent = sorted(recent, key=lambda v:v.addedAt, reverse=True)
    for vdata in recent[:10]:
        video = {}
        video['type'] = vdata.type
        video['added'] = _datetime_to_str(vdata.addedAt)
        video['title'] = _video_title(vdata)
        if not _ignored(video['title'], config.plexadded_ignore):
            values.append(video)
    with open(join(CACHE, f'{key}.json'), 'w') as handle:
        json.dump(values, handle)


def get_plexhistory(key):
    """ Fetch plex recently added. """
    values = {'items':[]}
    plex = PlexServer()
    config = _get_config()
    accounts = {a.accountID:a.name for a in plex.systemAccounts()}
    mindate = datetime.now() - timedelta(days=30)
    history = plex.history(150, mindate=mindate)
    for vdata in history:
        video = {}
        video['type'] = vdata.type
        video['viewed'] = _datetime_to_str(vdata.viewedAt)
        video['title'] = _video_title(vdata)[:15]
        video['account'] = accounts.get(vdata.accountID, 'Unknown')
        video['account'] = config.plexhistory_names.get(video['account'], video['account'])[:6]
        if not _ignored(video['account'], config.plexhistory_ignore):
            values['items'].append(video)
    values['total'] = len(values['items'])
    with open(join(CACHE, f'{key}.json'), 'w') as handle:
        json.dump(values, handle)


def get_plexsessions(key):
    """ Fetch Plex recently added, recently played and now playing. """
    values = []
    plex = PlexServer()
    for i, vdata in enumerate(plex.sessions()):
        video = {}
        video['user'] = vdata.usernames[0]
        video['type'] = vdata.type
        video['year'] = vdata.year
        video['duration'] = _video_length(vdata.duration)
        video['viewoffset'] = _video_length(vdata.viewOffset)
        video['percent'] = round((vdata.viewOffset / vdata.duration) * 100)
        video['player'] = vdata.players[0].device if vdata.players else 'NA'
        video['state'] = vdata.players[0].state if vdata.players else 'NA'
        video['playstate'] = f'{video["viewoffset"]} of {video["duration"]} ({video["percent"]}%)'
        video['title'] = _video_title(vdata)
        if video['state'] == 'playing':
            values.append(video)
        # Download the thumbnail to cache
        url = vdata.show().thumbUrl if vdata.type == 'episode' else vdata.thumbUrl
        response = requests.get(url, timeout=REQUEST_TIMEOUT)
        with open(join(CACHE, f'session{i}.jpg'), 'wb') as handle:
            handle.write(response.content)
    if len(values) < 1: _safe_unlink(join(CACHE, 'session0.jpg'))
    if len(values) < 2: _safe_unlink(join(CACHE, 'session1.jpg'))
    # save values to cache
    with open(join(CACHE, f'{key}.json'), 'w') as handle:
        json.dump(values, handle)


def get_sickrage(key):
    """ Fetch upcoming episodes from Sickrage. """
    values = []
    config = _get_config()
    url = SICKRAGE_URL.replace('{host}', config.sickrage_host)
    url = url.replace('{apikey}', config.sickrage_apikey)
    response = requests.get(url, timeout=REQUEST_TIMEOUT)
    data = json.loads(response.content.decode('utf8'))
    for stype in ('missed','today','soon','later'):
        for show in _rget(data, f'data.{stype}', []):
            show['datestr'] = _sickrage_datestr(stype, show)
            show['show_name'] = show['show_name'][:20]
            show['episode'] = f's{show.get("season","")}e{show.get("episode","")}'
            if ((not values or (show['show_name'] != values[-1]['show_name']))
              and not _ignored(show['show_name'], config.sickrage_ignore)):
                values.append(show)
    # save values to cache
    with open(join(CACHE, f'{key}.json'), 'w') as handle:
        json.dump(values[:10], handle)


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
