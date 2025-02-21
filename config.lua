
config = {}
-- List of widgets to display.
-- Add, remove, reorder widgets here.
-- See pkm/widgets/ for available widgets.
config.widgets = {'clock','openmeteo','system','nvidia','processes','networks','filesystems','nowplaying'}
config.update_interval = 2                -- Update interval for widgets (update conkyrc also)

-- Theme
config.default_font = 'ubuntu'
config.default_font_bold = true
config.default_font_color = '#ccc'
config.default_font_size = 11
config.accent = '#d79921'
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
  coretempstr = 'hwmon 2 temp 1',         -- Conky cmd to read coretemp (See /sys/class/hwmon/ on your pc)
  temperature_unit = 'fahrenheit',        -- Temperature unit {celsius, fahrenheit}
}
config.nvidia = {
  nvidiasmi = '/usr/bin/nvidia-smi',      -- Path to nvidia-smi
  temperature_unit = 'fahrenheit',        -- Temperature unit {celsius, fahrenheit}
  logscale = false,                       -- Chart gpu usage in logscale
}
config.radeon = {
  radeontop = '/usr/bin/radeontop',       -- Path to radeontop
  gpuname = 'Radeon HD 7750',             -- Name of the gpu to display (hard coded for now)
  gputemp = 'hwmon 1 temp 1',             -- Conky cmd to read gputemp (See /sys/class/hwmon/ on your pc)
  gpufreq = 'hwmon 1 freq 1',             -- Conky cmd to read gpufreq (See /sys/class/hwmon/ on your pc)
  temperature_unit = 'fahrenheit',        -- Temperature unit {celsius, fahrenheit}
  logscale = false,                       -- Chart gpu usage in logscale
}
config.processes = {
  count = 6,                              -- Number of processes to display
  sortby = 'top',                         -- Sort method {top, top_mem, top_io, top_time}
}
config.networks = {
  devices = {'enp4s0', 'vpn0'},           -- List of devices to display (run ifconfig to list)
  upspeed_color = '#cc2414',            -- Upload color for graph
  downspeed_color = '#98971a',          -- Download color for graph
  extip_url = 'https://ipinfo.io/ip',     -- URL to get external ip (https://ipinfo.io/ip, https://api.ipify.org, https://api.ipify.org)
  extip_update_interval = 900,            -- Update interval to grab external ip
}
config.filesystems = {
  paths = {                               -- List of filesystems to display {name, path} (run df -h to list)
    {name='Root', path='/'},
    {name='Synology', path='/media/Synology'},
  },
}
config.nowplaying = {
  playerctl = '/usr/bin/playerctl',       -- Path to playerctl
  ignore_players = '',                    -- Ignore players (comma separated list)
  max_players = 2,                        -- Maximum number of players to display
}

-- Set this if you want to be able to start conky without having to first be in
-- the pkmeter-conky directory. You will also need to update conkyrc.lua_load
-- setting to be an absolute path.
config.root = nil

-- Set true to draw call math.ceil on the graph and bargraph
-- heights making them easier to see at small values
config.fullpx = false

return config