import json5, requests
from datetime import datetime
from shutil import copyfile
from pkm.widgets.base import BaseWidget
from pkm import ROOT, CACHE, CONFIG, PKMETER, utils

OPENMETEO_URL = ('https://api.open-meteo.com/v1/forecast?latitude={latitude}&longitude={longitude}'
    '&current_weather=1&temperature_unit={temperature_unit}&windspeed_unit={windspeed_unit}'
    '&timezone={timezone}&daily=weathercode,apparent_temperature_max,sunrise,sunset')
ICONCODES = [
    # Clear, Cloudy
    {'text':'Clear', 'day':'32', 'night':'31', 'openmeteo':[0]},
    {'text':'Mostly Sunny', 'day':'34', 'night':'33', 'openmeteo':[1]},
    {'text':'Partly Sunny', 'day':'30', 'night':'29', 'openmeteo':[2]},
    {'text':'Mostly Cloudy', 'day':'28', 'night':'27'},
    {'text':'Cloudy', 'day':'26'},
    {'text':'Overcast', 'day':'26', 'openmeteo':[3]},
    # Fog, Hail, Haze, Hot, Windy
    {'text':'Fog', 'day':'20', 'openmeteo':[45,48]},
    {'text':'Haze', 'day':'19', 'night':'21'},
    {'text':'Hot', 'day':'36'},
    {'text':'Windy', 'day':'23'},
    # Rain & Thunderstorms
    {'text':'Possible Rain', 'day':'39', 'night':'45'},
    {'text':'Rain Shower', 'day':'39', 'night':'45', 'openmeteo':[80,81,82]},
    {'text':'Light Rain', 'day':'11', 'openmeteo':[51,53,61]},
    {'text':'Rain', 'day':'12', 'openmeteo':[55,63]},
    {'text':'Heavy Rain', 'day':'01', 'openmeteo':[65]},
    {'text':'Freezing Rain', 'day':'08', 'openmeteo':[56,57,66,67]},
    {'text':'Local Thunderstorms', 'day':'37', 'night':'47', 'openmeteo':[95]},
    {'text':'Thunderstorms', 'day':'00', 'openmeteo':[96,99]},
    # Hail
    {'text':'Hail', 'day':'18'},
    {'text':'Rain & Hail', 'day':'06'},
    {'text':'Rain Hail & Snow', 'day':'07'},
    # Snow
    {'text':'Rain & Snow', 'day':'05'},
    {'text':'Possible Snow', 'day':'13', 'openmeteo':[71,77]},
    {'text':'Light Snow', 'day':'14', 'openmeteo':[73]},
    {'text':'Snow Shower', 'day':'41', 'night':'46', 'openmeteo':[85,86]},
    {'text':'Snow', 'day':'16', 'openmeteo':[75]},
    {'text':'Snow Storm', 'day':'15'},
    # Not Available
    {'text':'Not Available', 'day':'na'},
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
            ${{texeci 1800 {PKMETER} update {self.name}}}\\
            ${{voffset 24}}${{goto 10}}${{font Ubuntu:bold:size=11}}{theme.header_color}{self.city_name}\\
            ${{alignr 10}}${{execi 60 {PKMETER} get -ir0 {self.name}.current_weather.temperature}}{tempunit}
            ${{voffset -2}}${{goto 10}}{theme.subheader}${{execi 60 {PKMETER} get {self.name}.current_text}}\\
            ${{alignr 10}}{theme.header_color}${{execi 60 {PKMETER} get -ir0 {self.name}.current_weather.windspeed}} {self.windspeed_unit}
            ${{voffset 46}}${{font Ubuntu:bold:size=7}}{theme.value_color}\\
            ${{goto 18}}${{execi 60 {PKMETER} get {self.name}.daily.day.0}}\\
            ${{goto 66}}${{execi 60 {PKMETER} get {self.name}.daily.day.1}}\\
            ${{goto 114}}${{execi 60 {PKMETER} get {self.name}.daily.day.2}}\\
            ${{goto 163}}${{execi 60 {PKMETER} get {self.name}.daily.day.3}}
            ${{goto 18}}${{execi 60 {PKMETER} get -ir0 {self.name}.daily.apparent_temperature_max.0}}°\\
            ${{goto 66}}${{execi 60 {PKMETER} get -ir0 {self.name}.daily.apparent_temperature_max.1}}°\\
            ${{goto 114}}${{execi 60 {PKMETER} get -ir0 {self.name}.daily.apparent_temperature_max.2}}°\\
            ${{goto 163}}${{execi 60 {PKMETER} get -ir0 {self.name}.daily.apparent_temperature_max.3}}°\\
            ${{voffset 11}}{theme.reset}\\
        """)  # noqa

    def get_lua_entries(self):
        origin = self.origin
        width = CONFIG['conky']['maximum_width']
        return [
            self.line(start=(100,origin), end=(100, origin+50), thickness=width, **CONFIG['headerbg']),  # header
            self.line(start=(100,origin+50), end=(100, origin+self.height), thickness=width, **CONFIG['mainbg']),  # background
            self.image(filepath=f'{CACHE}/current.png', start=(90,origin+3), width=45),  # current day
            self.image(filepath=f'{CACHE}/day0.png', start=(15,origin+59), width=25),  # today
            self.image(filepath=f'{CACHE}/day1.png', start=(63,origin+59), width=25),  # tomorrow
            self.image(filepath=f'{CACHE}/day2.png', start=(111,origin+59), width=25),  # 2 days out
            self.image(filepath=f'{CACHE}/day3.png', start=(160,origin+59), width=25),  # 3 days out
        ]

    def update_cache(self):
        """ Fetch weather from OpenMeteo and copy weather images to cache. """
        # Check the modtime of the cahce file before making another request
        filepath = f'{CACHE}/{self.name}.json5'
        if utils.get_modtime_ago(filepath) < 1700:
            return None
        # Make the API request to OpenMeteo
        url = OPENMETEO_URL
        url = url.replace('{latitude}', str(self.wsettings['latitude']))
        url = url.replace('{longitude}', str(self.wsettings['longitude']))
        url = url.replace('{temperature_unit}', self.wsettings['temperature_unit'])
        url = url.replace('{timezone}', self.wsettings['timezone'])
        url = url.replace('{windspeed_unit}', self.wsettings['windspeed_unit'])
        data = requests.get(url, timeout=10).json()
        # Get current weather
        weathercode = data['current_weather']['weathercode']
        iconcode, icontext = self.get_icon('openmeteo', weathercode)
        data['current_text'] = icontext
        self._copy_weather_icon(iconcode, 'current')
        # Get future weather
        data['daily']['text'], data['daily']['day'] = [], []
        for i in range(4):
            weathercode = data['daily']['weathercode'][i]
            iconcode, icontext = self.get_icon('openmeteo', weathercode)
            day = datetime.strptime(data['daily']['time'][i], '%Y-%m-%d').strftime('%a')
            data['daily']['text'].append(icontext)
            data['daily']['day'].append(day)
            self._copy_weather_icon(iconcode, f'day{i}')
        # Save the cached response
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
