#!/usr/bin/env python3
import argparse, importlib, json5, os, sys
from datetime import datetime
from os.path import abspath, dirname, expanduser

sys.path.append(dirname(abspath(__file__)))
from pkm import ROOT, CACHE, CONFIG  # noqa
from pkm import utils  # noqa


class ConkyTheme:
    """ A bunch of useful and reusable variables to use when createing the conky templates.
        This helps keep everythign same same by pre-defining font and color strings. These
        variables are purley for convenience and shorter widget definitions.
    """
    accent = f"${{color {CONFIG['accent']}}}"
    accent2 = f"${{color {CONFIG['accent2']}}}"
    header_color = f"${{color {CONFIG['header_color']}}}"
    subheader_color = f"${{color {CONFIG['subheader_color']}}}"
    label_color = f"${{color {CONFIG['label_color']}}}"
    value_color = f"${{color {CONFIG['value_color']}}}"
    header_font = f"${{font {CONFIG['header_font']}}}"
    subheader_font = f"${{font {CONFIG['subheader_font']}}}"
    label_font = f"${{font {CONFIG['label_font']}}}"
    value_font = f"${{font {CONFIG['value_font']}}}"
    header = f"{header_font}{header_color}"
    subheader = f"{subheader_font}{subheader_color}"
    label = f"{label_font}{label_color}"
    value = f"{value_font}{value_color}"
    # Draw.lua Colors
    bg = CONFIG['bg']
    graph_bg = CONFIG['graph_bg']
    header_bg = CONFIG['header_bg']
    header_graph_bg = CONFIG['header_graph_bg']
    reset = '${font}${color}'
    test = 'XXX\nXXX'


def create_conky_config():
    """ Create the conky.config section from the config.json file. """
    conkyconfig = 'conky.config = {\n'
    for key, value in CONFIG['conky'].items():
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
    theme = ConkyTheme()
    conkytext = 'conky.text = [[\n'
    for wname in CONFIG['widgets']:
        wsettings = CONFIG[wname]
        modpath, clsname = wsettings['clspath'].rsplit('.', 1)
        module = importlib.import_module(modpath)
        widget = getattr(module, clsname)(wsettings, origin)
        conkytext += f'{widget.get_conkyrc(theme)}\n\\\n'
        luaentries += widget.get_lua_entries()
        origin += widget.height
    conkytext += ']]\n'
    luaentries = ',\n'.join(f'  {item}' for item in luaentries)
    luaentries = f'elements = {{\n{luaentries}\n}}\n'
    return conkytext, luaentries


def create_conkyrc():
    """ Create a new conkyrc from from config.json. """
    conkyconfig = create_conky_config()
    conkytext, luaentries = create_conky_text()
    # Save the new conkyrc file
    filepath = expanduser('~/.conkyrc')
    print(f'Saving {filepath}')
    with open(filepath, 'w') as handle:
        handle.write(conkyconfig + conkytext)
    # Save the new config.lua file
    filepath = f'{ROOT}/pkm/config.lua'
    print(f'Saving {filepath}')
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
        with open(filepath, 'r') as handle:
            data = json5.load(handle)
        value = utils.rget(data, key, None)
        if value is None: return opts.default
        if opts.round: value = round(float(value), opts.round)
        if opts.int: value = int(value)
        if opts.format: value = datetime.fromtimestamp(int(value)).strftime(opts.format)
        return value
    except Exception:
        return opts.default


def update_widget(wname):
    """ Update the specified widget cache. """
    modpath, clsname = CONFIG[wname]['clspath'].rsplit('.', 1)
    module = importlib.import_module(modpath)
    widget = getattr(module, clsname)(CONFIG[wname])
    widget.update_cache()


if __name__ == '__main__':
    # Command line parser. Available commands are:
    #  conkyrc: generate new conkyrc & config.lua files from config.json
    #  get <key>: get the specified widget value
    #  update <widget>: update the specified widget cache
    os.makedirs(CACHE, exist_ok=True)
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
    # Run the specified command
    opts = parser.parse_args()
    if opts.command == 'conkyrc': create_conkyrc()
    if opts.command == 'get': print(get_value(opts.key, opts))
    if opts.command == 'update': update_widget(opts.widget)
