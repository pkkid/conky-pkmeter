
config = {}
-- List of widgets to display.
-- Add, remove, reorder widgets here.
-- See pkm/widgets/ for available widgets.
config.widgets = {'clock','openmeteo','system','nvidia','processes','networks','filesystems','nowplaying','custom'}
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
config.background = '#11111199'
config.header_bg = '#444444bb'
config.graph_bg = '#cccccc33'
config.header_graph_bg = '#cccccc11'
config.tempunit = 'celsius'

-- Widgets
config.clock = {
  onclick = 'gnome-clocks',               -- Click action
}
config.openmeteo = {
  city_name = 'Holliston',                -- Display Name (only used for display)
  latitude = 42.20,                       -- Latitude of location
  longitude = -71.42,                     -- Longitude of location
  temperature_unit = config.tempunit,     -- Temperature unit {celsius, fahrenheit}
  timezone = 'America/New_York',          -- https://en.wikipedia.org/wiki/List_of_tz_database_time_zones
  wind_speed_unit = 'mph',                -- OpenMeteo windspeed unit {kmh, ms, mph, kn}
  icon_theme = 'colorful',                -- Icon theme {colorful,dark,flat-black,flat-colorful,flat-white,light}
  onclick = 'x-www-browser https://www.google.com/search?q=Holliston+weather', -- Click action
  update_interval = 900,                  -- Update interval to call weather api
}
config.system = {
  logscale = false,                       -- Chart cpu usage in logscale
  coretempstr = 'hwmon 5 temp 1',         -- Conky cmd to read coretemp (See /sys/class/hwmon/ on your pc)
  temperature_unit = config.tempunit,     -- Temperature unit {celsius, fahrenheit}
  onclick = 'gnome-system-monitor -r',    -- Click action
  extras = {
    {name='Mem Temp', device='hwmon 3 temp 1', unit='°C'},
    {name='Pump Temp', device='hwmon 7 temp 1', unit='°C'},
    {name='Pump Speed', device='hwmon 7 fan 1', unit=' RPM'},
  }
}
config.nvidia = {
  nvidiasmi = '/usr/bin/nvidia-smi',      -- Path to nvidia-smi
  temperature_unit = config.tempunit,     -- Temperature unit {celsius, fahrenheit}
  logscale = false,                       -- Chart gpu usage in logscale
  onclick = 'nvidia-settings',            -- Click action
}
config.radeon = {
  radeontop = '/usr/bin/radeontop',       -- Path to radeontop
  gpuname = 'Radeon HD 7750',             -- Name of the gpu to display (hard coded for now)
  gputemp = 'hwmon 1 temp 1',             -- Conky cmd to read gputemp (See /sys/class/hwmon/ on your pc)
  gpufreq = 'hwmon 1 freq 1',             -- Conky cmd to read gpufreq (See /sys/class/hwmon/ on your pc)
  temperature_unit = config.tempunit,     -- Temperature unit {celsius, fahrenheit}
  logscale = false,                       -- Chart gpu usage in logscale
}
config.processes = {
  count = 6,                              -- Number of processes to display
  sortby = 'top',                         -- Sort method {top, top_mem, top_io, top_time}
  onclick = 'gnome-system-monitor -p',    -- Click action
}
config.networks = {
  devices = {                             -- List of devices to display {name, device} (run ip a to list)
    {name='Ethernet', device='enp4s0'},
    {name='Nasuni VPN', device='vpn0'},
    {name='PIA', device='tun0'},
  },
  upspeed_color = '#cc2414',            -- Upload color for graph
  downspeed_color = '#98971a',          -- Download color for graph
  extip_url = 'https://ipinfo.io/ip',     -- URL to get external ip (https://ipinfo.io/ip, https://api.ipify.org, https://api.ipify.org)
  extip_update_interval = 900,            -- Update interval to grab external ip
  onclick = 'gnome-system-monitor -r',    -- Click action
}
config.filesystems = {
  paths = {                               -- List of filesystems to display {name, path} (run df -h to list)
    {name='Root', path='/'},
    {name='Synology', path='/media/Synology'},
  },
  onclick = 'nautilus',  -- Click action
}
config.nowplaying = {
  playerctl = '/usr/bin/playerctl',       -- Path to playerctl
  ignore_players = '',                    -- Ignore players (comma separated list)
  max_players = 2,                        -- Maximum number of players to display
}

-- Custom Widget
-- Checking Game Server Status
config.custom = {
  commands = {
    {cmd='/home/pkkid/Projects/scripts/factorio.sh status', frequency=60},
    {cmd='/home/pkkid/Projects/scripts/hytale.sh status', frequency=60},
  },
  variables = {
    {name='factorio_players', fromcmd=0, regex='Online:%s+(%d+) players', default='--'},
    {name='factorio_uptime', fromcmd=0, regex='Uptime:%s+([%d:]+)', default='--'},
    {name='factorio_memory', fromcmd=0, regex='Memory:%s+([^%s]+)', default='--'},
    {name='hytale_players', fromcmd=1, regex='Online:%s+(%d+) players', default='--'},
    {name='hytale_uptime', fromcmd=1, regex='Uptime:%s+([%d:]+)', default='--'},
    {name='hytale_memory', fromcmd=1, regex='Memory:%s+([^%s]+)', default='--'},
  },
  templates = {
    {
      title = 'Game Servers',
      subtitle = 'Factorio & Hytale',
      lines = {
        {left = 'Factorio Server', right='{factorio_uptime}'},
        {left = '   Memory', right='{factorio_memory}'},
        {left = '   Online', right='{factorio_players} players'},
        {},
        {left = 'Hytale Server', right = '{hytale_uptime}'},
        {left = '   Memory', right='{hytale_memory}'},
        {left = '   Online', right='{hytale_players} players'},
      }
    },
  }
}

-- Set this if you want to be able to start conky without having to first be in
-- the pkmeter-conky directory. You will also need to update conkyrc.lua_load
-- setting to be an absolute path.
config.root = nil

-- Set true to draw call math.ceil on the graph and bargraph
-- heights making them easier to see at small values
config.fullpx = false

-- Work Desktop
-- Adding an entry for [<hostname>] will override
-- any configuration variables above.
config['[pkkid-laptop]'] = {
  widgets = {'clock','openmeteo','system','processes','networks','filesystems','nowplaying'},
  system = {
    logscale = false,                       -- Chart cpu usage in logscale
    coretempstr = 'hwmon 5 temp 1',         -- Conky cmd to read coretemp (See /sys/class/hwmon/ on your pc)
    temperature_unit = config.tempunit,     -- Temperature unit {celsius, fahrenheit}
    onclick = 'gnome-system-monitor -r',    -- Click action
  },
  networks = {
    devices={
      {name='Ethernet', device='enp3s0u2u4'},
      {name='Wifi', device='wlp113s0f0'},
    }
  },
  filesystems = {
    paths={
      {name='Root', path='/'}
    }
  },
  custom = {},
}

return config
