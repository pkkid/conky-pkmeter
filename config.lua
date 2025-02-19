
config = {}
-- List of widgets to display.
-- See pkm/widgets/ for available widgets.
config.widgets = {'clock', 'openmeteo', 'system', 'nvidia', 'processes'}
config.update_interval = 2                -- Update interval for widgets (update conkyrc also)

-- Theme
config.default_font = 'ubuntu'
config.default_font_bold = true
config.default_font_color = '#ccc'
config.default_font_size = 11
config.accent1 = '#d79921'
config.header = '#cccccc'
config.subheader = '#d79921'
config.label = '#999999'
config.value = '#cccccc'
config.background = '#000000cc'
config.header_bg = '#333333dd'
config.graph_bg = '#cccccc33'
config.header_graph_bg = '#cccccc11'

-- Widgets
config.openmeteo = {
  city_name = 'Holliston',                -- Display Name (only used for display)
  latitude = 42.20,                       -- Latitude of location
  longitude = -71.42,                     -- Longitude of location
  temperature_unit = 'fahrenheit',        -- Temperature unit {celsius, fahrenheit}
  timezone = 'America/New_York',          -- https://en.wikipedia.org/wiki/List_of_tz_database_time_zones
  wind_speed_unit = 'mph',                -- OpenMeteo windspeed unit {kmh, ms, mph, kn}
  icon_theme = 'colorful',                -- Icon theme {colorful,dark,flat-black,flat-colorful,flat-white,light}
  update_interval = 900,                  -- Update interval to call weather api
}
config.system = {
  logscale = false,                       -- Chart cpu usage in logscale
  coretempstr = 'hwmon 2 temp 1',         -- Conky cmd to read coretemp
  temperature_unit = 'fahrenheit',        -- Temperature unit {celsius, fahrenheit}
  update_interval = 1,                    -- Update interval for history
}
config.nvidia = {
  temperature_unit = 'fahrenheit',        -- Temperature unit {celsius, fahrenheit}
  update_interval = 1,                    -- Update interval to run nvidia-smi
  logscale = false,                       -- Chart gpu usage in logscale
}
config.processes = {
  count = 6,                              -- Number of processes to display
  sortby = 'top',                         -- Sort method {top, top_mem, top_io, top_time}
}

-- If having issues loading weather images, try setting this
-- to the root directory of the PKMeter project
config.root = nil

-- Set true to draw call math.ceil on the graph and bargraph
-- heights making them easier to see at small values
config.fullpx = false

return config