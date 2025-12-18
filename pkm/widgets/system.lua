local config = require 'config'
local draw = require 'pkm/draw'
local utils = require 'pkm/utils'

local system = {}
system.origin = 0
system.height = 0
system.history = nil
system.cpucount = nil
system.showextra = false

-- Draw
-- Draw this widget
function system:draw()
  self.height = 142
  if self.showextra then
    self.height = self.height + 5 + (#self.extras * 15)
  end
  self.cpucount = self.cpucount or utils.get_cpucount()

  -- Header
  draw.rectangle{x=0, y=self.origin+0, width=conky_window.width, height=40, color=config.header_bg} -- header background
  draw.rectangle{x=0, y=self.origin+40, width=conky_window.width, height=self.height-40, color=config.background} -- background
  draw.text{x=10, y=self.origin+17, text='System', size=12, color=config.header} -- system
  draw.text{x=10, y=self.origin+32, text=utils.parse('nodename'), maxwidth=80, color=config.subheader} -- hostname
  draw.graph{data=self.history, x=100, y=self.origin+8, width=90, height=24, color=config.accent,
    bgcolor=config.header_graph_bg, maxvalue=100, logscale=self.logscale} -- cpu chart

  -- System Stats
  local memtotal = utils.round(utils.parse('memmax'):match('^(%d+)'))..'G'
  local temp, tempunit = utils.parse(self.coretempstr), '°C'
  if self.temperature_unit == 'fahrenheit' then
    temp, tempunit = utils.celsius_to_fahrenheit(tonumber(temp)), '°F'
  end
  draw.text{x=10, y=self.origin+61, text='CPU Usage', color=config.label} -- cpu usage
  draw.text{x=145, y=self.origin+61, text=utils.parse('cpu cpu0')..'%', color=config.value, align='right'}
  draw.text{x=10, y=self.origin+76, text='CPU Temp', color=config.label} -- cpu temp
  draw.text{x=145, y=self.origin+76, text=temp..tempunit, color=config.value, align='right'}
  draw.text{x=10, y=self.origin+91, text='CPU Freq', color=config.label} -- cpu freq
  draw.text{x=145, y=self.origin+91, text=utils.parse('freq')..' MHz', color=config.value, align='right'}
  draw.text{x=10, y=self.origin+106, text='Mem Used', color=config.label} -- mem rate
  draw.text{x=145, y=self.origin+106, text=utils.parse('memperc')..'% of '..memtotal, color=config.value, align='right'}
  draw.text{x=10, y=self.origin+121, text='Uptime', color=config.label} -- uptime
  draw.text{x=145, y=self.origin+121, text=utils.parse('uptime_short'), color=config.value, align='right'}

  if self.showextra then
    y = self.origin + 141
    for _, sensor in ipairs(self.extras) do
      local value = utils.parse(sensor.device)
      draw.text{x=10, y=y, text=sensor.name, color=config.label} -- pump speed
      draw.text{x=145, y=y, text=value..sensor.unit, color=config.value, align='right'}
      y = y + 15
    end
  end

  -- CPU Bars
  barheight = 17    -- Height of the bars
  maxwidth = 36     -- Max drawing width available
  barwidth = math.floor(maxwidth / math.floor(self.cpucount / 2)) - 1
  fullwidth = math.floor((barwidth + 1) * self.cpucount / 2)
  xstart = math.floor(155 + ((maxwidth-fullwidth) / 2))
  x, y = xstart, self.origin+52
  for cpu=1, self.cpucount do
    if (cpu-1) == self.cpucount / 2 then
      x, y = xstart, y+barheight+4
    end
    cpupct = tonumber(utils.parse('cpu cpu'..cpu))
    draw.bargraph{value=cpupct, x=x, y=y, origin='bottom', width=barwidth, height=barheight,
      color=config.accent, bgcolor=config.graph_bg, fullpx=false}
    x = x+barwidth+1
  end

  -- Memory Ring
  mempct = tonumber(utils.parse('memperc'))
  draw.ringgraph{value=mempct, x=172, y=self.origin+109, radius=9, width=5, color=config.accent, bgcolor=config.graph_bg}
end

-- Update
-- Update CPU History
function system:update()
  if utils.check_update(self.last_update, config.update_interval) then
    self.history = self.history or utils.init_table(90, 0)
    local usage = tonumber(utils.parse('cpu cpu'))
    table.insert(self.history, usage)
    table.remove(self.history, 1)
    self.last_update = os.time()
  end
end

-- Click
-- Perform click action
function system:click(event, x, y)
  if y < 40 then
    os.execute(self.onclick..' &')
  else
    self.showextra = not self.showextra
  end
end

return system
