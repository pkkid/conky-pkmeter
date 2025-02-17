
config = {}
config.widgets = {'clock', 'openmeteo', 'system'}

-- Theme
config.default_font = 'ubuntu'
config.default_font_bold = true
config.default_font_color = '#ccc'
config.default_font_size = 10
config.accent1 = '#d79921'
config.header = '#cccccc'
config.subheader = '#d79921'
config.label = '#999999'
config.value = '#cccccc'
config.background = '#000000cc'
config.header_bg = '#333333dd'
config.graph_bg = '#cccccc11'

config.openmeteo = {
  city_name = 'Holliston',             -- Display Name (only used for display)
  latitude = 42.20,                    -- Latitude of location
  longitude = -71.42,                  -- Longitude of location
  temperature_unit = 'fahrenheit',     -- Temperature unit {celsius, fahrenheit}
  timezone = 'America/New_York',       -- https://en.wikipedia.org/wiki/List_of_tz_database_time_zones
  wind_speed_unit = 'mph',             -- OpenMeteo windspeed unit {kmh, ms, mph, kn}
  update_interval = 900,               -- Update interval to call weather api
}
config.system = {
  logscale = false,                     -- Chart cpu usage in logscale
}

-- If having issues loading weather images, try setting this
-- to the root directory of the PKMeter project
config.root = nil

return config