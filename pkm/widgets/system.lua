local config = require 'config'
local draw = require 'pkm/draw'
local socket = require 'socket'
local utils = require 'pkm/utils'

local system = {}
system.origin = 0
system.height = 0
system.history = nil
system.temp_history = nil
system.cpucount = nil
system.showextra = false

-- Draw
-- Draw this widget
function system:draw()
  self.height = 142
  if self.showextra then
    self.height = self.height + 5 + (#self.extras * 15)
  end

  -- Header
  color_usage = self.color_usage or config.accent
  draw.widget_header(self.origin, self.height, 'System', self.nodename, function()
    draw.graph{data=self.history, x=100, y=self.origin+8, width=90, height=24, color=color_usage,
      bgcolor=config.header_graph_bg, maxvalue=100, logscale=self.logscale}
  end)

  -- System Stats
  draw.stat_row(self.origin+61, 'CPU Usage', self.cpuusage..'%')
  draw.stat_row(self.origin+76, 'CPU Temp', self.tempstr)
  draw.stat_row(self.origin+91, 'CPU Freq', self.cpufreq..' MHz')
  draw.stat_row(self.origin+106, 'Mem Used', self.memperc..'% of '..self.memtotal..'G')
  draw.stat_row(self.origin+121, 'Uptime', self.uptime)

  if self.showextra then
    y = self.origin + 141
    for _, sensor in ipairs(self.extras) do
      draw.text{x=10, y=y, text=sensor.name, color=config.label} -- pump speed
      draw.text{x=145, y=y, text=sensor._value..sensor.unit, color=config.value, align='right'}
      y = y + 15
    end
  end

  -- CPU Bars
  color_cpubars = self.color_cpubars or config.accent
  barheight = 12    -- Height of the bars
  bargap = 2        -- Gap between top and bottom bars
  maxwidth = 36     -- Max drawing width available
  barwidth = math.floor(maxwidth / math.floor(self.cpucount / 2)) - 1
  fullwidth = math.floor((barwidth + 1) * self.cpucount / 2)
  xstart = math.floor(155 + ((maxwidth-fullwidth) / 2))
  x, y = xstart, self.origin+51
  for cpu=1, self.cpucount do
    if (cpu-1) == self.cpucount / 2 then
      x, y = xstart, y+barheight+bargap
    end
    draw.bargraph{value=self.cpupcts[cpu], x=x, y=y, origin='bottom', width=barwidth,
      height=barheight, color=color_cpubars, bgcolor=config.graph_bg, fullpx=false, logscale=false}
    x = x+barwidth+1
  end

  -- Temp History
  color_temp = self.color_temp or config.accent
  draw.graph{data=self.temp_history, x=155, y=self.origin+81, width=35, height=12, color=color_temp,
    bgcolor=config.graph_bg, minvalue=35, maxvalue=100, logscale=false} -- temp history

  -- Memory Ring
  color_mem = self.color_mem or config.accent
  draw.ringgraph{value=self.memperc, x=172, y=self.origin+110, radius=9, width=5,
    color=color_mem, bgcolor=config.graph_bg}
end

-- Update
-- Update CPU History
function system:update()
  if utils.check_update(self.last_update, self.update_interval) then
    -- System Details
    self.cpucount = self.cpucount or utils.get_cpucount()
    self.cpuusage = utils.parse('cpu cpu0')
    self.cpufreq = utils.parse('freq')
    self.nodename = self.nodename or utils.parse('nodename')
    self.memtotal = utils.round(utils.parse('memmax'):match('^(%d+)'))
    self.memperc = tonumber(utils.parse('memperc'))
    self.coretemp = utils.parse(self.coretempstr)
    self.tempstr = utils.format_temp(self.coretemp, self.temperature_unit)
    self.uptime = utils.parse('uptime_short')
    -- Extras
    for _, sensor in ipairs(self.extras) do
      sensor._value = utils.parse(sensor.device)
    end
    -- Usage History
    local usage = tonumber(utils.parse('cpu cpu'))
    local temp = tonumber(self.coretemp)
    self.history = utils.push_history(self.history, usage, 90)
    self.temp_history = utils.push_history(self.temp_history, temp, 35)
    self.last_update = socket.gettime()
  end
  -- CPU Bars
  if utils.check_update(self.last_cpubars_update, self.cpubars_update_interval or self.update_interval) then
    self.cpupcts = {}
    for cpu=1, self.cpucount do
      local cpupct = tonumber(utils.parse('cpu cpu'..cpu))
      table.insert(self.cpupcts, cpupct)
    end
    self.last_cpubars_update = socket.gettime()
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
