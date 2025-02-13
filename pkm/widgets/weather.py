import json5, requests
from collections import namedtuple
from datetime import datetime
from shutil import copyfile
from pkm.widgets.base import BaseWidget
from pkm import ROOT, CACHE, CONFIG, PKMETER, utils

OPENMETEO_URL = ('https://api.open-meteo.com/v1/forecast?latitude={latitude}&longitude={longitude}'
    '&current_weather=1&temperature_unit={temperature_unit}&windspeed_unit={windspeed_unit}'
    '&timezone={timezone}&daily=weathercode,apparent_temperature_max,sunrise,sunset')
OPENMETEO_WEATHERCODES = {
    0: {'text':'Clear', 'icon':'clear-day'},
    1: {'text':'Mostly Clear', 'icon':'partly-cloudy-day'},
    2: {'text':'Partly Cloudy', 'icon':'partly-cloudy-day'},
    3: {'text':'Overcast', 'icon':'cloudy'},
    45: {'text':'Fog', 'icon':'fog'},
    48: {'text':'Rime Fog', 'icon':'fog'},
    51: {'text':'Light Drizzle', 'icon':'rain'},
    53: {'text':'Drizzle', 'icon':'rain'},
    55: {'text':'Heavy Drizzle', 'icon':'rain'},
    56: {'text':'Light Freezing Drizzle', 'icon':'sleet'},
    57: {'text':'Heavy Freezing Drizzle', 'icon':'sleet'},
    61: {'text':'Light Rain', 'icon':'rain'},
    63: {'text':'Rain', 'icon':'rain'},
    65: {'text':'Heavy Rain', 'icon':'rain'},
    66: {'text':'Light Freezing Rain', 'icon':'rain'},
    67: {'text':'Heavy Freezing Rain', 'icon':'rain'},
    71: {'text':'Light Snow', 'icon':'snow'},
    73: {'text':'Snow', 'icon':'snow'},
    75: {'text':'Heavy Snow', 'icon':'snow'},
    77: {'text':'Hail', 'icon':'rain'},
    80: {'text':'Light Rain Showers', 'icon':'rain'},
    81: {'text':'Rain Showers', 'icon':'rain'},
    82: {'text':'Heavy Rain Showers', 'icon':'rain'},
    85: {'text':'Light Snow Showers', 'icon':'sleet'},
    86: {'text':'Heavy Snow Showers', 'icon':'sleet'},
    95: {'text':'Thunderstorm', 'icon':'rain'},
    96: {'text':'Thunderstorm w/ Hail', 'icon':'rain'},
    99: {'text':'Thunderstorm w/ Heavy Hail', 'icon':'rain'},
}


class WeatherWidget(BaseWidget):
    """ Displays current weather from OpenMeteo. """

    @property
    def height(self):
        return 81

    @property
    def yend(self):
        return self.ystart + self.height

    def get_conkyrc(self):
        """ Create the conkyrc template for the clock widget. """
        _ = namedtuple('wconfig', self.wconfig.keys())(*self.wconfig.values())
        return utils.clean_spaces(f"""
            ${{texeci 1800 {PKMETER} update weather}}\\
            ${{image {CACHE}/current.png -p 87,87 -s 35x35}}\\
            ${{voffset 30}}${{goto 10}}${{font Ubuntu:bold:size=11}}Holliston${{font}}
            ${{goto 10}}${{color1}}${{execi 60 {PKMETER} get weather.current_text}}${{color}}
            ${{voffset -30}}${{alignr 10}}${{font Ubuntu:bold:size=12}}${{execi 60 {PKMETER} get -ir0 weather.current_weather.temperature}}°F${{font}}
            ${{alignr 10}}${{execi 60 {PKMETER} get -ir0 weather.current_weather.windspeed}} mph
            ${{image {CACHE}/day0.png -p 15,140 -s 20x20}}\\
            ${{image {CACHE}/day1.png -p 65,140 -s 20x20}}\\
            ${{image {CACHE}/day2.png -p 115,140 -s 20x20}}\\
            ${{image {CACHE}/day3.png -p 165,140 -s 20x20}}\\
            ${{font Ubuntu:bold:size=7}}${{voffset 42}}${{color2}}\\
            ${{goto 17}}${{execi 60 {PKMETER} get weather.daily.day.0}}\\
            ${{goto 67}}${{execi 60 {PKMETER} get weather.daily.day.1}}\\
            ${{goto 117}}${{execi 60 {PKMETER} get weather.daily.day.2}}\\
            ${{goto 167}}${{execi 60 {PKMETER} get weather.daily.day.3}}
            ${{goto 17}}${{execi 60 {PKMETER} get -ir0 weather.daily.apparent_temperature_max.0}}°\\
            ${{goto 67}}${{execi 60 {PKMETER} get -ir0 weather.daily.apparent_temperature_max.1}}°\\
            ${{goto 117}}${{execi 60 {PKMETER} get -ir0 weather.daily.apparent_temperature_max.2}}°\\
            ${{goto 167}}${{execi 60 {PKMETER} get -ir0 weather.daily.apparent_temperature_max.3}}°\\
            ${{color}}${{font}}
        """)

    def get_lua_entries(self):
        return []

    @classmethod
    def update_cache(self):
        """ Fetch weather from OpenMeteo and copy weather images to cache. """
        # Fetch weather from OpenMeteo
        url = OPENMETEO_URL
        url = url.replace('{latitude}', CONFIG['latitude'])
        url = url.replace('{longitude}', CONFIG['longitude'])
        url = url.replace('{temperature_unit}', CONFIG['temperature_unit'])
        url = url.replace('{timezone}', CONFIG['timezone'])
        url = url.replace('{windspeed_unit}', CONFIG['windspeed_unit'])
        data = requests.get(url, timeout=10).json()
        # get current weather
        weathercode = data['current_weather']['weathercode']
        data['current_text'] = OPENMETEO_WEATHERCODES[weathercode]['text']
        iconname = OPENMETEO_WEATHERCODES[weathercode]['icon']
        self._copy_weather_icon(iconname, 'current')
        # get future weather
        data['daily']['text'], data['daily']['day'] = [], []
        for i in range(4):
            weathercode = data['daily']['weathercode'][i]
            text = OPENMETEO_WEATHERCODES[weathercode]['text']
            day = datetime.strptime(data['daily']['time'][i], '%Y-%m-%d').strftime('%a')
            data['daily']['text'].append(text)
            data['daily']['day'].append(day)
            iconname = OPENMETEO_WEATHERCODES[weathercode]['icon']
            self._copy_weather_icon(iconname, f'day{i}')
        # save the cached response
        key = utils.get_shortname(self.__class__.__name__)
        utils.save_file(f'{CACHE}/{key}.json', json5.dumps(data))

    def _copy_weather_icon(self, iconname, day='current'):
        """ Copy the icon to cache for for the specified day. """
        source = f'{ROOT}/img/{iconname}.png'
        dest = f'{CACHE}/{day}.png'
        copyfile(source, dest)
