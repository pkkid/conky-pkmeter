local config = require 'config'
local draw = require 'pkm/draw'
local utils = require 'pkm/utils'

local filesystems = {}
local history = nil
local last_update = nil

-- Draw
-- Draw this widget
function filesystems:draw(origin)
  origin = origin or 0
  local height = 57 + (#self.paths * 40)

  -- Header
  draw.rectangle{x=0, y=origin+0, width=conky_window.width, height=40, color=config.header_bg} -- header background
  draw.rectangle{x=0, y=origin+40, width=conky_window.width, height=height-40, color=config.background} -- background
  draw.text{x=10, y=origin+17, text='File Systems', size=12, color=config.header} -- file systems
  draw.text{x=10, y=origin+32, text='IO: '..utils.parse('diskio')..'/s', color=config.subheader} -- io
  draw.graph{data=self.history, x=100, y=origin+8, width=90, height=24, color=config.accent1,
    bgcolor=config.header_graph_bg, minmaxvalue=100*1024, logscale=self.logscale} -- io chart

  -- filesystems
  y = origin + 61
  for _, fs in ipairs(self.paths) do
    local fspct = tonumber(utils.parse('fs_used_perc '..fs.path))
    draw.text{x=10, y=y, text=fs.name, color=config.value} -- name
    draw.text{x=145, y=y, text=utils.parse('fs_free '..fs.path)..' free', color=config.value, align='right'} -- fs free
    draw.text{x=10, y=y+15, text=utils.parse('fs_used_perc '..fs.path)..'%', color=config.value} -- fs percent
    draw.text{x=145, y=y+15, text=utils.parse('fs_size '..fs.path)..' total', color=config.value, align='right'} -- fs size
    draw.ringgraph{value=fspct, x=172, y=y+3, radius=9, width=5, color=config.accent1, bgcolor=config.graph_bg} -- fs percent
    y = y + 40
  end

  return height
end

-- Update
-- Update External IP & Network History
function filesystems:update()
  if utils.check_update(self.history_last_update, config.update_interval) then
    self.history = self.history or utils.init_table(90, 0)
    local iostr = utils.parse('diskio')
    local io, unit = iostr:match('^(%d+).*(%a+)$')
    io = tonumber(io)
    if unit == 'K' then io = io * 1024 end
    if unit == 'M' then io = io * 1024^2 end
    if unit == 'G' then io = io * 1024^3 end
    table.insert(self.history, io)
    table.remove(self.history, 1)
    self.history_last_update = os.time()
  end
end

return filesystems