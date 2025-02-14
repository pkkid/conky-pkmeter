import json5, logging, socket
from logging.handlers import RotatingFileHandler
from os.path import abspath, dirname, expanduser

ROOT = f'{dirname(dirname(abspath(__file__)))}'
PKMETER = f'{ROOT}/pkmeter.py'
CACHE = f'{ROOT}/pkm/cache'


def merge(dict1, dict2):
    """ Recursively merge two dictionaries. """
    for key, value in dict2.items():
        if key in dict1 and isinstance(dict1[key], dict) and isinstance(value, dict):
            merge(dict1[key], value)
            continue
        dict1[key] = value
    return dict1


# Load DEFAULT configuration
with open(f'{ROOT}/defaults.json5', 'r') as handle:
    DEFAULTS = json5.load(handle)

# Load user CONFIG
hostname = socket.gethostname()
with open(f'{ROOT}/config.json5', 'r') as handle:
    CONFIG = merge(DEFAULTS, json5.load(handle))
    CONFIG = merge(CONFIG, CONFIG.get(f'[{hostname}]', {}))

# Logging Configuration
log = logging.getLogger('pkmeter')
logformat = '%(asctime)s %(module)12s:%(lineno)-4s %(levelname)-9s %(message)s'
loghandler = logging.NullHandler()
logfile = CONFIG.get('logfile')
if logfile:
    logfile = expanduser(logfile.replace('{ROOT}',ROOT).replace('{CACHE}',CACHE))
    loghandler = RotatingFileHandler(logfile, 'a', 5242880, 3)
loghandler.setFormatter(logging.Formatter(logformat))
log.addHandler(loghandler)
log.setLevel(logging.INFO)
