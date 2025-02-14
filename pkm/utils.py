import os, time

BYTE, KB, MB = 1, 1024, 1048576
BYTES1024 = ((2**50,'P'), (2**40,'T'), (2**30,'G'), (2**20,'M'), (2**10,'K'), (1,'B'))


def celsius_to_fahrenheit(value):
    """ Converts a temperature from Celsius to Fahrenheit. """
    return int(value * 9 / 5 + 32)


def clean_spaces(value):
    """ Clean leading spaces from each line. """
    return '\n'.join([line.lstrip() for line in value.splitlines()]).strip()


def get_modtime_ago(filepath):
    """ Return the number of seconds since the file was last modified. """
    try:
        return int(time.time() - os.path.getmtime(filepath))
    except Exception:
        return 999999


def get_widget_name(clsname):
    """ Given a widget name or path string, return it's short name.
        clsname: The widget name or path string.
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
    result = min(maxval, round((numerator / float(denominator)) * 100.0, precision))
    return int(result) if precision == 0 else result


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
