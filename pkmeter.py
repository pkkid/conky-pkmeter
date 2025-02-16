#!/usr/bin/python3
import argparse, importlib
import json5, sys, time
from datetime import datetime
from os.path import abspath, dirname

sys.path.append(dirname(abspath(__file__)))
from pkm import ROOT, CACHE   # noqa
from pkm import config, log, themes, utils  # noqa


def create_conky_config():
    """ Create the conky.config section from the config.json file. """
    conkyconfig = 'conky.config = {\n'
    for key, value in config['conky'].items():
        value = value.replace('{ROOT}', ROOT) if isinstance(value, str) else value
        value = value.lstrip('#') if 'color' in key else value
        value = f'"{value}"' if isinstance(value, str) else value
        value = str(value).lower() if isinstance(value, bool) else value
        conkyconfig += f'  {key}={value},\n'
    conkyconfig += '}\n\n'
    return conkyconfig


def create_conky_text():
    """ Create conky.text and config.lua from the config.json file. """
    origin = 0
    luaentries = []
    conkytheme = themes.ConkyTheme(config)
    luatheme = themes.LuaTheme(config)
    debug = conkytheme.debug if config['debugui'] else ''
    conkytext = 'conky.text = [[\n'
    for name in config['widgets']:
        try:
            wsettings = config[name]
            modpath, clsname = wsettings['clspath'].rsplit('.', 1)
            module = importlib.import_module(modpath)
            widget = getattr(module, clsname)(wsettings, origin)
            widgettext = widget.get_conkyrc(conkytheme)
            conkytext += f'{widgettext}\n{conkytheme.reset}{debug}\\\n\\\n'
            luaentries += widget.get_lua_entries(luatheme)
            origin += widget.height
            if update_cache := getattr(widget, 'widget.update_cache', None):
                update_cache()
        except Exception:
            log.exception(f'Error creating widget {name}')
    conkytext += ']]\n'
    luaentries = ',\n'.join(f'  {item}' for item in luaentries)
    luaentries = f'elements = {{\n{luaentries}\n}}\n'
    return conkytext, luaentries


def create_conkyrc(opts):
    """ Create a new conkyrc from from config.json. """
    log.info('Creating new conkyrc file')
    conkyconfig = create_conky_config()
    conkytext, luaentries = create_conky_text()
    # Save the new conkyrc file
    filepath = f'{ROOT}/conkyrc'
    log.info(f'Saving {filepath}')
    with open(filepath, 'w') as handle:
        handle.write(conkyconfig + conkytext)
    # Save the new config.lua file
    filepath = f'{ROOT}/pkm/config.lua'
    log.info(f'Saving {filepath}')
    with open(filepath, 'w') as handle:
        handle.write(luaentries)


def get_value(key, opts):
    """ Lookup the specified key from the cached json files.
        widget: Short name of the widget to get the value from.
        key: Dict lookup key to get the value from.
    """
    try:
        widget, key = key.split('.', 1)
        filepath = f'{CACHE}/{widget}.json5'
        data = utils.load_cached_data(filepath)
        value = utils.rget(data, key, None)
        if value is None: return opts.default
        if opts.round: value = round(float(value), opts.round)
        if opts.int: value = int(value)
        if opts.format: value = datetime.fromtimestamp(int(value)).strftime(opts.format)
        log.debug(f'Get {key} = {value}')
        print(value)
    except Exception:
        return opts.default


def update_widget(name, opts):
    """ Update the specified widget cache. """
    starttime = time.time()
    modpath, clsname = config[name]['clspath'].rsplit('.', 1)
    module = importlib.import_module(modpath)
    widget = getattr(module, clsname)(config[name])
    if data := widget.update_cache():
        with open(widget.cachepath, 'w') as handle:
            json5.dump(data, handle, indent=2, ensure_ascii=False)
        loglvl = log.info if getattr(widget, 'update_interval', 0) >= 300 else log.debug
        loglvl(f'Update {name} cache took {time.time()-starttime:.2f} seconds')


if __name__ == '__main__':
    # Command line parser. Available commands are:
    #  conkyrc: generate new conkyrc & config.lua files from config.json
    #  get <key>: get the specified widget value
    #  update <widget>: update the specified widget cache
    parser = argparse.ArgumentParser(description='Helper tools for pkmeter.')
    subparsers = parser.add_subparsers(title='available commands', dest='command')
    conkyrc_parser = subparsers.add_parser('conkyrc', help='generate new conkyrc & config.lua files from config.json')
    get_parser = subparsers.add_parser('get', help='get the specified widget value')
    get_parser.add_argument('key', help='value to lookup from the specified widget dataset')
    get_parser.add_argument('-d', dest='default', default='', help='default value if not found')
    get_parser.add_argument('-i', dest='int', action='store_true', default=False, help='cast value to integer')
    get_parser.add_argument('-r', dest='round', type=int, help='round to nearest decimal')
    get_parser.add_argument('-f', dest='format', help='format value to datetime')
    update_parser = subparsers.add_parser('update', help='Update cache for the specified widget')
    update_parser.add_argument('widget', help='widget class name to get value from')
    opts = parser.parse_args()
    # Run the specified command
    try:
        if opts.command == 'conkyrc': create_conkyrc(opts)
        if opts.command == 'get': get_value(opts.key, opts)
        if opts.command == 'update': update_widget(opts.widget, opts)
    except KeyboardInterrupt:
        raise SystemExit(0)
    except Exception as err:
        log.exception(err)
        raise SystemExit(1)
