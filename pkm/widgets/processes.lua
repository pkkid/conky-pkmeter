local config = require 'config'
local draw = require 'pkm/draw'
local utils = require 'pkm/utils'

local processes = {}

-- Draw
-- Draw this widget
function processes:draw(origin)
  origin = origin or 0
  local height = 68 + (self.count * 15)

  -- Header
  draw.rectangle{x=0, y=origin+0, width=conky_window.width, height=40, color=config.header_bg} -- header background
  draw.rectangle{x=0, y=origin+40, width=conky_window.width, height=height-40, color=config.background} -- background
  draw.text{x=10, y=origin+17, text='Processes', size=12, color=config.header} -- processes
  draw.text{x=10, y=origin+32, text=utils.parse('processes')..' processes', color=config.subheader} -- num processes

  -- Processes
  local y = 61
  local lineheight = 15
  for i=1,self.count do
    local name = string.sub(utils.parse(self.sortby..' name '..i), 1, 13)
    draw.text{x=10, y=origin+y, text=name, color=config.label} -- process name
    draw.text{x=145, y=origin+y, text=utils.parse(self.sortby..' mem_res '..i), color=config.value, align='right'} -- cpu usage
    draw.text{x=190, y=origin+y, text=utils.parse(self.sortby..' cpu '..i)..'%', color=config.value, align='right'} -- mem usage
    y = y + lineheight
  end

  return height
end


return processes