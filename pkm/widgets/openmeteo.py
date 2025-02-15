import os, re, requests
from datetime import datetime
from shutil import copyfile
from pkm.widgets.base import BaseWidget
from pkm import ROOT, CACHE, PKMETER
from pkm import utils

OPENMETEO_URL = ('https://api.open-meteo.com/v1/forecast?latitude={latitude}&longitude={longitude}'
    '&current_weather=1&temperature_unit={temperature_unit}&wind_speed_unit={wind_speed_unit}'
    '&timezone={timezone}&daily=weathercode,apparent_temperature_max,sunrise,sunset')
ICONCODES = [
    # Clear, Cloudy
    {'desc':'Clear', 'day':'32', 'night':'31', 'weathercode':[0]},
    {'desc':'Mostly Sunny', 'day':'34', 'night':'33', 'weathercode':[1]},
    {'desc':'Partly Sunny', 'day':'30', 'night':'29', 'weathercode':[2]},
    {'desc':'Mostly Cloudy', 'day':'28', 'night':'27'},
    {'desc':'Cloudy', 'day':'26'},
    {'desc':'Overcast', 'day':'26', 'weathercode':[3]},
    # Fog, Hail, Haze, Hot, Windy
    {'desc':'Fog', 'day':'20', 'weathercode':[45,48]},
    {'desc':'Haze', 'day':'19', 'night':'21'},
    {'desc':'Hot', 'day':'36'},
    {'desc':'Windy', 'day':'23'},
    # Rain & Thunderstorms
    {'desc':'Possible Rain', 'day':'39', 'night':'45'},
    {'desc':'Rain Shower', 'day':'39', 'night':'45', 'weathercode':[80,81,82]},
    {'desc':'Light Rain', 'day':'11', 'weathercode':[51,53,61]},
    {'desc':'Rain', 'day':'12', 'weathercode':[55,63]},
    {'desc':'Heavy Rain', 'day':'01', 'weathercode':[65]},
    {'desc':'Freezing Rain', 'day':'08', 'weathercode':[56,57,66,67]},
    {'desc':'Local Thunderstorms', 'day':'37', 'night':'47', 'weathercode':[95]},
    {'desc':'Thunderstorms', 'day':'00', 'weathercode':[96,99]},
    # Hail
    {'desc':'Hail', 'day':'18'},
    {'desc':'Rain & Hail', 'day':'06'},
    {'desc':'Rain Hail & Snow', 'day':'07'},
    # Snow
    {'desc':'Rain & Snow', 'day':'05'},
    {'desc':'Possible Snow', 'day':'13', 'weathercode':[71,77]},
    {'desc':'Light Snow', 'day':'14', 'weathercode':[73]},
    {'desc':'Snow Shower', 'day':'41', 'night':'46', 'weathercode':[85,86]},
    {'desc':'Snow', 'day':'16', 'weathercode':[75]},
    {'desc':'Snow Storm', 'day':'15'},
    # Not Available
    {'desc':'Not Available', 'day':'na'},
]


class OpenMeteoWidget(BaseWidget):
    """ Displays current weather from OpenMeteo. """

    def __init__(self, wsettings, origin=0):
        super().__init__(wsettings, origin)
        self.height = 125

    def get_conkyrc(self, theme):
        """ Create the conkyrc template for the clock widget. """
        tempunit = '°F' if self.temperature_unit == 'fahrenheit' else '°C'
        return utils.clean_spaces(f"""
            ${{texeci {self.update_interval} {PKMETER} update {self.name}}}\\
            ${{voffset 24}}${{goto 10}}${{font Ubuntu:bold:size=11}}{theme.header_color}{self.city_name}\\
            ${{alignr 10}}${{execi 60 {PKMETER} get -ir0 {self.name}.current_weather.temperature}}{tempunit}
            ${{voffset -2}}${{goto 10}}{theme.subheader}${{execi 60 {PKMETER} get {self.name}.current_weather.desc}}\\
            ${{alignr 10}}{theme.header_color}${{execi 60 {PKMETER} get -ir0 {self.name}.current_weather.windspeed}} {self.windspeed_unit}
            ${{voffset 46}}${{font Ubuntu:bold:size=7}}{theme.value_color}\\
            ${{goto 18}}${{execi 60 {PKMETER} get {self.name}.daily.weekday.0}}\\
            ${{goto 66}}${{execi 60 {PKMETER} get {self.name}.daily.weekday.1}}\\
            ${{goto 114}}${{execi 60 {PKMETER} get {self.name}.daily.weekday.2}}\\
            ${{goto 163}}${{execi 60 {PKMETER} get {self.name}.daily.weekday.3}}
            ${{goto 18}}${{execi 60 {PKMETER} get -ir0 {self.name}.daily.apparent_temperature_max.0}}°\\
            ${{goto 66}}${{execi 60 {PKMETER} get -ir0 {self.name}.daily.apparent_temperature_max.1}}°\\
            ${{goto 114}}${{execi 60 {PKMETER} get -ir0 {self.name}.daily.apparent_temperature_max.2}}°\\
            ${{goto 163}}${{execi 60 {PKMETER} get -ir0 {self.name}.daily.apparent_temperature_max.3}}°
        """)  # noqa

    def get_lua_entries(self, theme):
        origin, width, height = self.origin, self.width, self.height
        return [
            self.draw('line', frm=(100,origin), to=(100,origin+50), thickness=width, color=theme.header_bg),  # header bg
            self.draw('line', frm=(100,origin+50), to=(100,origin+height), thickness=width, color=theme.bg),  # main bg
            self.draw('image', filepath=f'{CACHE}/{self.name}/current.png', frm=(90,origin+3), width=45),  # current day
            self.draw('image', filepath=f'{CACHE}/{self.name}/day0.png', frm=(15,origin+59), width=25),    # day0 (today)
            self.draw('image', filepath=f'{CACHE}/{self.name}/day1.png', frm=(63,origin+59), width=25),    # day1
            self.draw('image', filepath=f'{CACHE}/{self.name}/day2.png', frm=(111,origin+59), width=25),   # day2
            self.draw('image', filepath=f'{CACHE}/{self.name}/day3.png', frm=(160,origin+59), width=25),   # day3
        ]

    def update_cache(self):
        """ Fetch weather from OpenMeteo and copy weather images to cache. """
        if self.check_skip_update(): return None
        os.makedirs(f'{CACHE}/{self.name}', exist_ok=True)
        # Make the API request to OpenMeteo
        url = OPENMETEO_URL
        for key in re.findall(r'({.*?})', OPENMETEO_URL):
            url = url.replace(key, str(self.wsettings[key[1:-1]]))
        data = requests.get(url, timeout=10).json()
        # Get current weather
        isday = data['current_weather']['is_day']
        inum, desc = self._get_icon_num(data['current_weather']['weathercode'], isday)
        self._copy_weather_icon(inum, 'current')
        data['current_weather']['desc'] = desc
        # Get future weather
        data['daily']['weekday'] = []
        for i in range(len(data['daily']['time'])):
            weathercode = data['daily']['weathercode'][i]
            inum, desc = self._get_icon_num(weathercode)
            self._copy_weather_icon(inum, f'day{i}')
            # Get the weekday
            datestr = data['daily']['time'][i]
            weekday = datetime.strptime(datestr, '%Y-%m-%d').strftime('%a')
            data['daily']['weekday'].append(weekday)
        return data

    def _get_icon_num(self, weathercode, isday=True):
        """ Get the icon code & text for the specified weather code. """
        for iconcode in ICONCODES:
            if weathercode in iconcode.get('weathercode', []):
                key = 'day' if isday else 'night'
                inum = iconcode.get(key, iconcode['day'])
                return inum, iconcode['desc']
        return 'na', 'Not Available'

    def _copy_weather_icon(self, iconcode, day='current'):
        """ Copy the icon to cache for for the specified day. """
        source = f'{ROOT}/pkm/img/weather/colorful/{iconcode}.png'
        dest = f'{CACHE}/{self.name}/{day}.png'
        copyfile(source, dest)
