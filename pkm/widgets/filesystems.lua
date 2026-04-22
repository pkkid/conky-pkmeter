local config = require 'config'
local draw = require 'pkm/draw'
local socket = require 'socket'
local utils = require 'pkm/utils'

local filesystems = {}
filesystems.origin = 0
filesystems.height = 0
filesystems.history = nil

-- Draw
-- Draw this widget
function filesystems:draw()
  self.height = 57

  -- Header
  draw.widget_header(self.origin, self.height, 'File Systems', 'IO: '..self.diskio..'/s', function()
    draw.graph{data=self.history, x=100, y=self.origin+8, width=90, height=24, color=config.accent,
      bgcolor=config.header_graph_bg, minmaxvalue=100*1024, logscale=self.logscale}
  end)

  -- filesystems
  y = self.origin + 61
  for _, fs in ipairs(self.paths) do
    draw.rectangle{x=0, y=y-4, width=conky_window.width, height=40, color=config.background} -- background
    draw.text{x=10, y=y, text=fs.name, color=config.value} -- name
    draw.text{x=145, y=y, text=fs.free..' free', color=config.value, align='right'} -- fs free
    draw.text{x=10, y=y+15, text=fs.usedpct..'%', color=config.value} -- fs percent
    draw.text{x=145, y=y+15, text=fs.size..' total', color=config.value, align='right'} -- fs size
    draw.ringgraph{value=fs.usedpct, x=172, y=y+3, radius=9, width=5, color=config.accent, bgcolor=config.graph_bg} -- fs percent
    self.height = self.height + 40
    y = y + 40
  end
end

-- Update
-- Update IO History
function filesystems:update()
  if utils.check_update(self.last_update, self.update_interval) then
    -- Filesystem Info
    for _, fs in ipairs(self.paths) do
      fs.free = utils.parse('fs_free '..fs.path)
      fs.usedpct = tonumber(utils.parse('fs_used_perc '..fs.path))
      fs.size = utils.parse('fs_size '..fs.path)
    end
    -- Disk IO History
    self.diskio = utils.parse('diskio')
    local io, unit = self.diskio:match('^(%d+).*(%a+)$')
    io = tonumber(io)
    if unit == 'K' then io = io * 1024 end
    if unit == 'M' then io = io * 1024^2 end
    if unit == 'G' then io = io * 1024^3 end
    self.history = utils.push_history(self.history, io, 90)
    self.last_update = socket.gettime()
  end
end

-- Click
-- Perform click action
function filesystems:click(event, x, y)
  os.execute(self.onclick..' &')
end

return filesystems
