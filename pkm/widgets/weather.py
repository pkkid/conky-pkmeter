import json5, requests
from collections import namedtuple
from datetime import datetime
from shutil import copyfile
from pkm.widgets.base import BaseWidget
from pkm import ROOT, CACHE, CONFIG, PKMETER, utils

OPENMETEO_URL = ('https://api.open-meteo.com/v1/forecast?latitude={latitude}&longitude={longitude}'
    '&current_weather=1&temperature_unit={temperature_unit}&windspeed_unit={windspeed_unit}'
    '&timezone={timezone}&daily=weathercode,apparent_temperature_max,sunrise,sunset')
ICONCODES = [
    # Clear, Cloudy
    {'text':'Clear', 'day':'32', 'night':'31', 'meteosource':[2,26], 'openmeteo':[0]},
    {'text':'Mostly Sunny', 'day':'34', 'night':'33', 'meteosource':[3,27], 'openmeteo':[1]},
    {'text':'Partly Sunny', 'day':'30', 'night':'29', 'meteosource':[4,28], 'openmeteo':[2]},
    {'text':'Mostly Cloudy', 'day':'28', 'night':'27', 'meteosource':[5,29]},
    {'text':'Cloudy', 'day':'26', 'meteosource':[6,30]},
    {'text':'Overcast', 'day':'26', 'meteosource':[7,8,31], 'openmeteo':[3]},
    # Fog, Hail, Haze, Hot, Windy
    {'text':'Fog', 'day':'20', 'meteosource':[9], 'openmeteo':[45,48]},
    {'text':'Haze', 'day':'19', 'night':'21'},
    {'text':'Hot', 'day':'36'},
    {'text':'Windy', 'day':'23'},
    # Rain & Thunderstorms
    {'text':'Possible Rain', 'day':'39', 'night':'45', 'meteosource':[12]},
    {'text':'Rain Shower', 'day':'39', 'night':'45', 'meteosource':[13,32], 'openmeteo':[80,81,82]},
    {'text':'Light Rain', 'day':'11', 'meteosource':[10], 'openmeteo':[51,53,61]},
    {'text':'Rain', 'day':'12', 'meteosource':[11], 'openmeteo':[55,63]},
    {'text':'Heavy Rain', 'day':'01', 'openmeteo':[65]},
    {'text':'Freezing Rain', 'day':'08', 'meteosource':[23,24,36], 'openmeteo':[56,57,66,67]},
    {'text':'Local Thunderstorms', 'day':'37', 'night':'47', 'meteosource':[15,33], 'openmeteo':[95]},
    {'text':'Thunderstorms', 'day':'00', 'meteosource':[14], 'openmeteo':[96,99]},
    # Hail
    {'text':'Hail', 'day':'18', 'meteosource':[25]},
    {'text':'Rain & Hail', 'day':'06'},
    {'text':'Rain Hail & Snow', 'day':'07'},
    # Snow
    {'text':'Rain & Snow', 'day':'05', 'meteosource':[20,21,22,35]},
    {'text':'Possible Snow', 'day':'13', 'meteosource':[18], 'openmeteo':[71,77]},
    {'text':'Light Snow', 'day':'14', 'meteosource':[16], 'openmeteo':[73]},
    {'text':'Snow Shower', 'day':'41', 'night':'46', 'meteosource':[19,34], 'openmeteo':[85,86]},
    {'text':'Snow', 'day':'16', 'meteosource':[17], 'openmeteo':[75]},
    {'text':'Snow Storm', 'day':'15'},
    # Not Available
    {'text':'Not Available', 'day':'na', 'meteosource':[1]},
]


class WeatherWidget(BaseWidget):
    """ Displays current weather from OpenMeteo. """

    def __init__(self, wconfig, origin=0):
        self.wconfig = wconfig      # Widget configuration object
        self.origin = origin        # Starting ypos of the widget
        self.height = 125           # Height of the widget

    def get_conkyrc(self):
        """ Create the conkyrc template for the clock widget. """
        wc = namedtuple('wconfig', self.wconfig.keys())(*self.wconfig.values())
        tempunit = '°F' if wc.temperature_unit == 'fahrenheit' else '°C'
        return utils.clean_spaces(f"""
            ${{texeci 1800 {PKMETER} update weather}}\\
            ${{voffset 24}}${{font Ubuntu:bold:size=11}}\\
            ${{goto 10}}{wc.city_name}\\
            ${{alignr 10}}${{execi 60 {PKMETER} get -ir0 weather.current_weather.temperature}}{tempunit}
            ${{voffset -2}}${{font Ubuntu:bold:size=8}}\\
            ${{goto 10}}${{color1}}${{execi 60 {PKMETER} get weather.current_text}}\\
            ${{alignr 10}}${{color}}${{execi 60 {PKMETER} get -ir0 weather.current_weather.windspeed}} {wc.windspeed_unit}
            ${{voffset 46}}${{font Ubuntu:bold:size=7}}${{color2}}\\
            ${{goto 18}}${{execi 60 {PKMETER} get weather.daily.day.0}}\\
            ${{goto 66}}${{execi 60 {PKMETER} get weather.daily.day.1}}\\
            ${{goto 114}}${{execi 60 {PKMETER} get weather.daily.day.2}}\\
            ${{goto 163}}${{execi 60 {PKMETER} get weather.daily.day.3}}
            ${{goto 18}}${{execi 60 {PKMETER} get -ir0 weather.daily.apparent_temperature_max.0}}°\\
            ${{goto 66}}${{execi 60 {PKMETER} get -ir0 weather.daily.apparent_temperature_max.1}}°\\
            ${{goto 114}}${{execi 60 {PKMETER} get -ir0 weather.daily.apparent_temperature_max.2}}°\\
            ${{goto 163}}${{execi 60 {PKMETER} get -ir0 weather.daily.apparent_temperature_max.3}}°\\
            ${{font}}${{color}}${{voffset 11}}\\
        """)  # noqa

    def get_lua_entries(self):
        origin, height = self.origin, self.height
        mainbg, maina = utils.rget(CONFIG, 'mainbg', 0x000000), utils.rget(CONFIG, 'mainbg_alpha', 0.6)
        headbg, heada = utils.rget(CONFIG, 'headerbg', 0x000000), utils.rget(CONFIG, 'headerbg_alpha', 0.6)
        width = utils.rget(CONFIG, 'conky.maximum_width', 200)
        return [
            self.line(start=(100,origin), end=(100, origin+50), color=headbg, alpha=heada, thickness=width),  # header
            self.line(start=(100,origin+50), end=(100, origin+height), color=mainbg, alpha=maina, thickness=width),  # background
            self.image(filepath=f'{CACHE}/current.png', start=(95,origin+3), width=45),  # current day
            self.image(filepath=f'{CACHE}/day0.png', start=(15,origin+59), width=25),  # today
            self.image(filepath=f'{CACHE}/day1.png', start=(63,origin+59), width=25),  # tomorrow
            self.image(filepath=f'{CACHE}/day2.png', start=(111,origin+59), width=25),  # 2 days out
            self.image(filepath=f'{CACHE}/day3.png', start=(160,origin+59), width=25),  # 3 days out
        ]

    def update_cache(self):
        """ Fetch weather from OpenMeteo and copy weather images to cache. """
        # Check the modtime of the cahce file before making another request
        filepath = f'{CACHE}/{utils.get_shortname(self.__class__.__name__)}.json'
        if utils.get_modtime_ago(filepath) < 1700:
            return None
        # Make the API request to OpenMeteo
        url = OPENMETEO_URL
        url = url.replace('{latitude}', str(self.wconfig['latitude']))
        url = url.replace('{longitude}', str(self.wconfig['longitude']))
        url = url.replace('{temperature_unit}', self.wconfig['temperature_unit'])
        url = url.replace('{timezone}', self.wconfig['timezone'])
        url = url.replace('{windspeed_unit}', self.wconfig['windspeed_unit'])
        data = requests.get(url, timeout=10).json()
        # get current weather
        weathercode = data['current_weather']['weathercode']
        iconcode, icontext = self.get_icon('openmeteo', weathercode)
        data['current_text'] = icontext
        self._copy_weather_icon(iconcode, 'current')
        # get future weather
        data['daily']['text'], data['daily']['day'] = [], []
        for i in range(4):
            weathercode = data['daily']['weathercode'][i]
            iconcode, icontext = self.get_icon('openmeteo', weathercode)
            day = datetime.strptime(data['daily']['time'][i], '%Y-%m-%d').strftime('%a')
            data['daily']['text'].append(icontext)
            data['daily']['day'].append(day)
            self._copy_weather_icon(iconcode, f'day{i}')
        # save the cached response
        with open(filepath, 'w') as handle:
            json5.dump(data, handle, indent=2, ensure_ascii=False)

    def get_icon(self, service, weathercode):
        """ Get the icon code & text for the specified weather code. """
        for icon in ICONCODES:
            if weathercode in icon.get(service, []):
                return icon['day'], icon['text']
        return 'na', 'Not Available'

    def _copy_weather_icon(self, iconcode, day='current'):
        """ Copy the icon to cache for for the specified day. """
        source = f'{ROOT}/pkm/img/weather/colorful/{iconcode}.png'
        dest = f'{CACHE}/{day}.png'
        copyfile(source, dest)
