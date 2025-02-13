import json5, socket
from os.path import abspath, dirname

ROOT = f'{dirname(dirname(abspath(__file__)))}'
PKMETER = f'{ROOT}/pkmeter.py'
CACHE = f'{ROOT}/pkm/cache'

with open(f'{ROOT}/config.json', 'r') as handle:
    CONFIG = json5.load(handle)
    hostname = socket.gethostname()
    CONFIG.update(CONFIG.get(f'[{hostname}]', {}))
