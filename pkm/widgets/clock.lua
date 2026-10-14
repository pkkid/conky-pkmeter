local config = require 'config'
local draw = require 'pkm/draw'
local menu = require 'pkm/menu'
local socket = require 'socket'
local toggles = require 'pkm/toggles'
local utils = require 'pkm/utils'

local clock = {}
clock.title = 'Clock'
clock.origin = 0
clock.height = 0

-- Draw
-- Draw this widget from cached data
function clock:draw()
  self.height = 90
  draw.rectangle{x=0, y=self.origin+0, width=conky_window.width, height=self.height, color=config.background} -- Background
  draw.text{x=95, y=self.origin+63, text=self.day or '', size=58, bold=true, color=config.header, align='right'} -- Day of month
  draw.text{x=105, y=self.origin+32, text=self.month_year or '', size=12, bold=true, color=config.header} -- Month and year
  draw.text{x=105, y=self.origin+48, text=self.weekday or '', size=12, bold=true, color=config.header} -- Day of week
  draw.text{x=105, y=self.origin+64, text=self.time or '', size=12, bold=true, color=config.header} -- Current time
end

-- Update
-- Fetch clock data (gated to once per second)
function clock:update()
  if utils.check_update(self.last_update, self.update_interval) then
    self.day = utils.format_date('%d')
    self.month_year = utils.format_date('%b %Y')
    self.weekday = utils.format_date('%A')
    local hour24 = toggles.get('clock', 'hour24', false)
    self.time = utils.format_date(hour24 and '%H:%M:%S' or '%-I:%M:%S %P')
    self.last_update = socket.gettime()
  end
end

-- Click
-- Perform click action
function clock:click(event, x, y)
  os.execute(self.onclick..' &')
end

-- Menu
-- Returns right click menu items to switch the time format or open the clock and calendar
function clock:menu()
  local items = {menu.toggle('24-hour time', 'clock', 'hour24', false,
    function() self.last_update = nil end)}
  if self.calendar then table.insert(items, menu.app(self.calendar)) end
  if self.onclick then table.insert(items, menu.app(self.onclick)) end
  return items
end

return clock
