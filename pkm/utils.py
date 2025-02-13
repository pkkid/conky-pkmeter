import json5, socket
from pkm import ROOT

BYTE, KB, MB = 1, 1024, 1048576
BYTES1024 = ((2**50,'P'), (2**40,'T'), (2**30,'G'), (2**20,'M'), (2**10,'K'), (1,'B'))


def celsius_to_fahrenheit(value):
    """ Converts a temperature from Celsius to Fahrenheit.
        value: Temperature in Celsius.
    """
    return int(value * 9 / 5 + 32)


def clean_spaces(value):
    """ Clean leading spaces from each line.
        value: The string to clean.
    """
    return '\n'.join([line.lstrip() for line in value.splitlines()]).strip()


def get_config():
    """ Loads the configuration from a JSON file and updates it with
        hostname-specific settings.
        root directory where the configuration file is located.
    """
    with open(f'{ROOT}/config.json', 'r') as handle:
        config = json5.load(handle)
    hostname = socket.gethostname()
    config.update(config.get(f'[{hostname}]', {}))
    return config


def get_shortname(clsname):
    """ Given a widget name or path string, return it's short name.
        * clsname: The widget name or path string.
    """
    return clsname.split('.')[-1].replace('Widget','').lower()


def percent(numerator, denominator, precision=2, maxval=999.9, default=0.0):
    """ Calculates the percentage of numerator over denominator.
        numerator: The numerator value.
        denominator: The denominator value.
        precision: The number of decimal places to round to.
        maxval: The maximum value to return.
        default: The default value to return if denominator is zero.
    """
    if not denominator:
        return default
    return min(maxval, round((numerator / float(denominator)) * 100.0, precision))


def rget(obj, attrstr, default=None, delim='.'):
    """ Recursively gets a value from a nested object (dict or list) using a delimiter-separated string.
        obj: The object to get the value from.
        attrstr: The delimiter-separated string of attributes/keys.
        default: The default value to return if any attribute/key is not found.
        delim: The delimiter used in the attrstr.
    """
    try:
        parts = attrstr.split(delim, 1)
        attr = parts[0]
        attrstr = parts[1] if len(parts) == 2 else None
        if isinstance(obj, dict): value = obj[attr]
        elif isinstance(obj, list): value = obj[int(attr)]
        if attrstr: return rget(value, attrstr, default, delim)
        return value
    except Exception:
        return default


def to_int(value, default=None):
    """ Converts a value to an integer.
        value: The value to convert.
        default: The default value to return if conversion fails.
    """
    try:
        return int(value)
    except Exception:
        return default


def value_to_str(value, unit=BYTE, precision=0, separator=''):
    """ Converts a value to a human-readable string with units.
        value: The value to convert.
        unit: The unit of the value (default is BYTE).
        precision: The number of decimal places to round to.
        separator: The separator between the value and the unit.
    """
    if value is None: return ''
    value = value * unit
    for div, unit in BYTES1024:
        if value >= div:
            conversion = round(value / div, int(precision)) if precision else int(value / div)
            return '%s%s%s' % (conversion, separator, unit)
    return '0%s%s' % (separator, unit)
