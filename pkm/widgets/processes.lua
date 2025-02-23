local config = require 'config'
local draw = require 'pkm/draw'
local utils = require 'pkm/utils'

local processes = {}
processes.origin = 0
processes.height = 0
processes.maxlist = false

-- Draw
-- Draw this widget
function processes:draw()
  self.height = 68

  -- Header
  draw.rectangle{x=0, y=self.origin+0, width=conky_window.width, height=40, color=config.header_bg} -- header background
  draw.rectangle{x=0, y=self.origin+40, width=conky_window.width, height=self.height-40, color=config.background} -- background
  draw.text{x=10, y=self.origin+17, text='Processes', size=12, color=config.header} -- processes
  draw.text{x=10, y=self.origin+32, text=utils.parse('processes')..' processes', color=config.subheader} -- num processes

  -- Processes
  local y = self.origin + 61
  local lineheight = 15
  local count = self.maxlist and 10 or self.count
  for i=1, count do
    local name = string.sub(utils.parse(self.sortby..' name '..i), 1, 13)
    draw.rectangle{x=0, y=y+7, width=conky_window.width, height=lineheight, color=config.background}
    draw.text{x=10, y=y, text=name, color=config.label} -- process name
    draw.text{x=145, y=y, text=utils.parse(self.sortby..' mem_res '..i), color=config.value, align='right'} -- cpu usage
    draw.text{x=190, y=y, text=utils.parse(self.sortby..' cpu '..i)..'%', color=config.value, align='right'} -- mem usage
    self.height = self.height + lineheight
    y = y + lineheight
  end
end

-- Click
-- Perform click action
function processes:click(event, x, y)
  if y < 40 then
    os.execute(self.onclick..' &')
  elseif x < 110 then
    self.maxlist = not self.maxlist
  elseif x >= 110 and x < 150 then
    print('sort by mem')
    self.sortby = 'top_mem'
  elseif x >= 150 then
    print('sort by proc')
    self.sortby = 'top'
  end
end

return processes