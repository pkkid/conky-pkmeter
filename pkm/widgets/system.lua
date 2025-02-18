local config = require 'config'
local draw = require 'pkm/draw'
local utils = require 'pkm/utils'

local system = {}
system.history = nil
system.cpucount = 24

-- Draw clock widget
-- This widget has no options
function system:draw(origin)
  origin = origin or 0
  local height = 132
  self.cpucount = self.cpucount or utils.get_cpucount()

  -- Header
  draw.rectangle{x=0, y=origin+0, width=conky_window.width, height=40, color=config.header_bg} -- header background
  draw.rectangle{x=0, y=origin+40, width=conky_window.width, height=92, color=config.background} -- background
  draw.text{x=10, y=origin+17, text='System', size=12, color=config.header} -- system
  draw.text{x=10, y=origin+32, text=utils.parse('nodename'), color=config.subheader} -- hostname
  draw.graph{data=self.history, x=100, y=origin+8, width=90, height=24, color=config.accent1,
    bgcolor=config.header_graph_bg, maxvalue=100, logscale=self.logscale} -- cpu chart

  -- System Stats
  draw.text{x=10, y=origin+61, text='CPU Usage', color=config.label} -- cpu usage
  draw.text{x=145, y=origin+61, text=utils.parse('cpu cpu0')..'%', color=config.value, align='right'}
  draw.text{x=10, y=origin+76, text='CPU Freq', color=config.label} -- cpu freq
  draw.text{x=145, y=origin+76, text=utils.parse('freq')..' MHz', color=config.value, align='right'}
  draw.text{x=10, y=origin+91, text='Uptime', color=config.label} -- uptime
  draw.text{x=145, y=origin+91, text=utils.parse('uptime_short'), color=config.value, align='right'}
  draw.text{x=10, y=origin+106, text='Mem Used', color=config.label} -- mem used
  draw.text{x=145, y=origin+106, text=utils.parse('mem'), color=config.value, align='right'}
  draw.text{x=10, y=origin+121, text='Mem Free', color=config.label} -- mem rate
  draw.text{x=145, y=origin+121, text=utils.parse('memeasyfree'), color=config.value, align='right'}

  -- CPU Bars
  barheight = 17    -- Height of the bars
  maxwidth = 36     -- Max drawing width available
  barwidth = math.floor(maxwidth / math.floor(self.cpucount / 2)) - 1
  fullwidth = math.floor((barwidth + 1) * self.cpucount / 2)
  xstart = math.floor(155 + ((maxwidth-fullwidth) / 2))
  x, y = xstart, origin+52
  for cpu=1, self.cpucount do
    if (cpu-1) == self.cpucount / 2 then
      x, y = xstart, y+barheight+4
    end
    cpupct = tonumber(utils.parse('cpu cpu'..cpu))
    draw.bargraph{value=cpupct, x=x, y=y, origin='bottom', width=barwidth, height=barheight,
      color=config.accent1, bgcolor=config.graph_bg, fullpx=false}
    x = x+barwidth+1
  end

  -- Memory Ring
  mempct = tonumber(utils.parse('memperc'))
  draw.ringgraph{value=mempct, x=172, y=origin+109, radius=9, width=5, color=config.accent1,
    bgcolor=config.graph_bg}

  return height
end

-- Update CPU history
-- Saves each value to self.history
function system:update()
  self.history = self.history or utils.init_table(90, 0)
  local usage = tonumber(utils.parse('cpu cpu'))
  table.insert(self.history, usage)
  table.remove(self.history, 1)
end


return system