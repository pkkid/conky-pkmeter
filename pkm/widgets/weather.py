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
        return 125

    @property
    def yend(self):
        return self.ystart + self.height

    def get_conkyrc(self):
        """ Create the conkyrc template for the clock widget. """
        wc = namedtuple('wconfig', self.wconfig.keys())(*self.wconfig.values())
        tempunit = '°F' if wc.temperature_unit == 'fahrenheit' else '°C'
        return utils.clean_spaces(f"""
            ${{texeci 1800 {PKMETER} update weather}}\\
            ${{image {CACHE}/current.png -p 87,90 -s 35x35}}\\
            ${{voffset 28}}${{font Ubuntu:bold:size=11}}\\
            ${{goto 10}}{wc.city_name}\\
            ${{alignr 10}}${{execi 60 {PKMETER} get -ir0 weather.current_weather.temperature}}{tempunit}
            ${{voffset -2}}${{font Ubuntu:bold:size=8}}\\
            ${{goto 10}}${{color1}}${{execi 60 {PKMETER} get weather.current_text}}\\
            ${{alignr 10}}${{color}}${{execi 60 {PKMETER} get -ir0 weather.current_weather.windspeed}} {wc.windspeed_unit}
            ${{image {CACHE}/day0.png -p 15,145 -s 20x20}}\\
            ${{image {CACHE}/day1.png -p 65,145 -s 20x20}}\\
            ${{image {CACHE}/day2.png -p 115,145 -s 20x20}}\\
            ${{image {CACHE}/day3.png -p 165,145 -s 20x20}}\\
            ${{voffset 46}}${{font Ubuntu:bold:size=7}}${{color2}}\\
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
        return [self.line(
            start=(100, self.origin),  # top
            end=(100, self.origin + 50),  # header bottom
            color=utils.rget(CONFIG, 'headerbg', '0x000000'),
            alpha=utils.rget(CONFIG, 'headerbg_alpha', 0.6),
            thickness=utils.rget(CONFIG, 'conky.maximum_width', 200),
        ), self.line(
            start=(100, self.origin + 50),  # forcast top
            end=(100, self.origin + self.height),  # forcast bottom
            color=utils.rget(CONFIG, 'mainbg', '0x000000'),
            alpha=utils.rget(CONFIG, 'mainbg_alpha', 0.6),
            thickness=utils.rget(CONFIG, 'conky.maximum_width', 200),
        )]

    def update_cache(self):
        """ Fetch weather from OpenMeteo and copy weather images to cache. """
        url = OPENMETEO_URL
        url = url.replace('{latitude}', str(self.wconfig['latitude']))
        url = url.replace('{longitude}', str(self.wconfig['longitude']))
        url = url.replace('{temperature_unit}', self.wconfig['temperature_unit'])
        url = url.replace('{timezone}', self.wconfig['timezone'])
        url = url.replace('{windspeed_unit}', self.wconfig['windspeed_unit'])
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
        with open(f'{CACHE}/{key}.json', 'w') as handle:
            json5.dump(data, handle)

    def _copy_weather_icon(self, iconname, day='current'):
        """ Copy the icon to cache for for the specified day. """
        source = f'{ROOT}/pkm/img/{iconname}.png'
        dest = f'{CACHE}/{day}.png'
        copyfile(source, dest)
