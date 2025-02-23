local config = require 'config'
local draw = require 'pkm/draw'
local utils = require 'pkm/utils'

local clock = {}
clock.origin = 0
clock.height = 0

-- Draw
-- Draw this widget
function clock:draw()
  self.height = 90
  draw.rectangle{x=0, y=self.origin+0, width=conky_window.width, height=self.height, color=config.background} -- Background
  draw.text{x=95, y=self.origin+63, text=utils.format_date('%d'), size=58, bold=true, color=config.header, align='right'} -- Day of month
  draw.text{x=105, y=self.origin+32, text=utils.format_date('%b %Y'), size=12, bold=true, color=config.header} -- Month and year
  draw.text{x=105, y=self.origin+48, text=utils.format_date('%A'), size=12, bold=true, color=config.header} -- Day of week
  draw.text{x=105, y=self.origin+64, text=utils.format_date('%H:%M:%S %P'), size=12, bold=true, color=config.header} -- Current time
end

-- Click
-- Perform click action
function clock:click(event, x, y)
  os.execute(self.onclick..' &')
end

return clock