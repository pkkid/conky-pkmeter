import logging, os
from logging.handlers import RotatingFileHandler
from os.path import abspath, dirname, expanduser
from pkm import utils

# Global Constants
ROOT = f'{dirname(dirname(abspath(__file__)))}'
PKMETER = f'{ROOT}/pkmeter.py'
CACHE = f'{ROOT}/pkm/cache'
config = utils.get_config(ROOT)

# Logging Configuration
os.makedirs(CACHE, exist_ok=True)
log = logging.getLogger('pkmeter')
logformat = '%(asctime)s %(module)12s:%(lineno)-4s %(levelname)-9s %(message)s'
streamhandler = logging.StreamHandler()
streamhandler.setFormatter(logging.Formatter(logformat))
log.addHandler(streamhandler)
logfile = config.get('logfile')
if logfile:
    logfile = expanduser(logfile.replace('{ROOT}',ROOT).replace('{CACHE}',CACHE))
    loghandler = RotatingFileHandler(logfile, 'a', 5242880, 3)
    loghandler.setFormatter(logging.Formatter(logformat))
    log.addHandler(loghandler)
log.setLevel(config.get('loglevel', logging.INFO))
