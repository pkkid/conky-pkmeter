local config = require 'config'
local draw = require 'pkm/draw'
local utils = require 'pkm/utils'

local openmeteo = {}
openmeteo.URL = 'https://api.open-meteo.com/v1/forecast?latitude={latitude}&longitude={longitude}'
openmeteo.URL = openmeteo.URL..'&current_weather=1&temperature_unit={temperature_unit}&wind_speed_unit={wind_speed_unit}'
openmeteo.URL = openmeteo.URL..'&timezone={timezone}&daily=weathercode,apparent_temperature_max,sunrise,sunset'
openmeteo.ICONCODES = {
    -- Clear, Cloudy
    {desc='Clear', day='32', night='31', weathercodes={0}},
    {desc='Mostly Clear', day='34', night='33', weathercodes={1}},
    {desc='Partly Clear', day='30', night='29', weathercodes={2}},
    {desc='Mostly Cloudy', day='28', night='27'},
    {desc='Cloudy', day='26'},
    {desc='Overcast', day='26', weathercodes={3}},
    -- Fog, Hail, Haze, Hot, Windy
    {desc='Fog', day='20', weathercodes={45,48}},
    {desc='Haze', day='19', night='21'},
    {desc='Hot', day='36'},
    {desc='Windy', day='23'},
    -- Rain & Thunderstorms
    {desc='Possible Rain', day='39', night='45'},
    {desc='Rain Shower', day='39', night='45', weathercodes={80,81,82}},
    {desc='Light Rain', day='11', weathercodes={51,53,61}},
    {desc='Rain', day='12', weathercodes={55,63}},
    {desc='Heavy Rain', day='01', weathercodes={65}},
    {desc='Freezing Rain', day='08', weathercodes={56,57,66,67}},
    {desc='Local Thunderstorms', day='37', night='47', weathercodes={95}},
    {desc='Thunderstorms', day='00', weathercodes={96,99}},
    -- Hail
    {desc='Hail', day='18'},
    {desc='Rain & Hail', day='06'},
    {desc='Rain Hail & Snow', day='07'},
    -- Snow
    {desc='Rain & Snow', day='05'},
    {desc='Possible Snow', day='13', weathercodes={71,77}},
    {desc='Light Snow', day='14', weathercodes={73}},
    {desc='Snow Shower', day='41', night='46', weathercodes={85,86}},
    {desc='Snow', day='16', weathercodes={75}},
    {desc='Snow Storm', day='15'},
    -- Not Available
    {desc='Not Available', day='na'},
}
openmeteo.last_update = nil
openmeteo.data = nil

-- Draw
-- Draw this widget
function openmeteo:draw(origin)
  origin = origin or 0
  local height = 131

  -- Current Weather
  local isnight = not self.data.current_weather.is_day == 1
  local ipath, idesc = self:get_iconpath(self.data.current_weather.weathercode, isnight)
  local tempunit = self.temperature_unit == 'fahrenheit' and '°F' or '°C'
  local temp = math.floor(self.data.current_weather.temperature + 0.5)
  local windspeed = math.floor(self.data.current_weather.windspeed + 0.5)..' '..self.wind_speed_unit
  draw.rectangle{x=0, y=origin, width=conky_window.width, height=50, color=config.header_bg} -- header background
  draw.rectangle{x=0, y=origin+50, width=conky_window.width, height=height-50, color=config.background} -- main background
  draw.image{x=93, y=origin+3, path=ipath, width=45} -- current icon
  draw.text{x=10, y=origin+23, text=self.city_name, size=15, color=config.header, align='left'} -- city name
  draw.text{x=190, y=origin+23, text=temp..tempunit, size=15, color=config.header, align='right'} -- current temp
  draw.text{x=10, y=origin+38, text=idesc, color=config.subheader, align='left'} -- current desc
  draw.text{x=190, y=origin+38, text=windspeed, color=config.value, align='right'} -- current wind

  -- Forecast
  for i=0,3 do
    local weekday = self:get_weekday(self.data.daily.time[i+1])
    temp = self.data.daily.apparent_temperature_max[i+1]..'°'
    ipath, idesc = self:get_iconpath(self.data.daily.weathercode[i+1])
    draw.image{x=15+(48*i), y=origin+59, path=ipath, width=25} -- icon
    draw.text{x=25+(48*i), y=origin+98, text=weekday, size=9, color=config.label, align='center'} -- day of week
    draw.text{x=25+(48*i), y=origin+110, text=temp, size=9, color=config.value, align='center'} -- day of week  
  end

  return height
end

-- Update
-- Update weather data; config.lua options:
--  openmeteo.city_name:         Display Name (only used for display)
--  openmeteo.latitude:          Latitude of location
--  openmeteo.longitude:         Longitude of location
--  openmeteo.temperature_unit:  Temperature unit {celsius, fahrenheit}
--  openmeteo.timezone:          https://en.wikipedia.org/wiki/List_of_tz_database_time_zones
--  openmeteo.wind_speed_unit:   OpenMeteo windspeed unit {kmh, ms, mph, kn}
--  openmeteo.update_interval:   Update interval to call weather api
function openmeteo:update()
  if utils.check_update(self.last_update, self.update_interval) then
    local url = string.gsub(self.URL, '{latitude}', self.latitude)
    url = string.gsub(url, '{longitude}', self.longitude)
    url = string.gsub(url, '{temperature_unit}', self.temperature_unit)
    url = string.gsub(url, '{wind_speed_unit}', self.wind_speed_unit)
    url = string.gsub(url, '{timezone}', self.timezone)
    local data = utils.request{url=url, json=true}
    if data then self.data = data end
    self.last_update = os.time()
  end
end

-- Get Icon Path
-- Return iconpath and description for the specified weathercode
-- weathercode: Weather code from OpenMeteo API
-- night: Set true to get night icon
function openmeteo:get_iconpath(weathercode, isnight)
  isnight = isnight or false
  for _, idata in ipairs(self.ICONCODES) do
    if utils.contains(idata.weathercodes or {}, weathercode) then
      local key = isnight and 'night' or 'day'
      local inum = idata[key] or idata['day']
      local ipath = pkmeter.ROOT..'/pkm/img/weather/'..self.icon_theme..'/'..inum..'.png'
      return ipath, idata.desc
    end
  end
  return 'na', 'Not Available'
end

-- Get Weekday
-- Returns the weekday for the specified datestr
function openmeteo:get_weekday(datestr)
  local pattern = "(%d+)-(%d+)-(%d+)"
  local year, month, day = datestr:match(pattern)
  local date_table = {year = year, month = month, day = day}
  local timestamp = os.time(date_table)
  return os.date('%a', timestamp)
end

return openmeteo
