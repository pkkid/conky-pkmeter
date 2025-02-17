local config = require 'config'
local draw = require 'pkm/draw'
local utils = require 'pkm/utils'

local system = {}
system.history = nil

-- Draw clock widget
-- This widget has no options
function system:draw(origin)
  origin = origin or 0
  local height = 132

  -- Header
  draw.rectangle{x=0, y=origin+0, width=conky_window.width, height=40, color=config.header_bg} -- header background
  draw.rectangle{x=0, y=origin+40, width=conky_window.width, height=92, color=config.background} -- background
  draw.text{x=10, y=origin+17, text='System', size=12, color=config.header} -- system
  draw.text{x=10, y=origin+32, text=utils.parse('nodename'), size=10, color=config.subheader} -- hostname
  draw.graph{data=self.history, x=100, y=origin+8, width=90, height=24, color=config.accent1,
    bgcolor=config.graph_bg, maxvalue=100, logscale=self.logscale} -- cpu chart

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