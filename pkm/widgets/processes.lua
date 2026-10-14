local config = require 'config'
local draw = require 'pkm/draw'
local menu = require 'pkm/menu'
local socket = require 'socket'
local toggles = require 'pkm/toggles'
local utils = require 'pkm/utils'

local processes = {}
processes.title = 'Processes'
processes.origin = 0
processes.height = 0
processes.SORTS = {
  {label='CPU', sortby='top', value='cpu', suffix='%'},
  {label='Memory', sortby='top_mem', value='cpu', suffix='%'},
  {label='I/O', sortby='top_io', value='io_perc', suffix='%'},
  {label='Time', sortby='top_time', value='time', suffix=''},
}

-- Draw
-- Draw this widget
function processes:draw()
  self.height = 68

  -- Header
  draw.widget_header(self.origin, self.height, 'Processes', utils.parse('processes')..' processes')

  -- Processes
  local y = self.origin + 61
  local lineheight = 15
  local procs = self.procs or {}
  local count = toggles.get('processes', 'show_more', false) and self.max_count or self.min_count
  for i=1, math.min(count, #procs) do
    draw.rectangle{x=0, y=y+7, width=conky_window.width, height=lineheight, color=config.background}
    draw.text{x=10, y=y, text=procs[i].name, color=config.label} -- process name
    draw.text{x=145, y=y, text=procs[i].mem, color=config.value, align='right'} -- mem usage
    draw.text{x=190, y=y, text=procs[i].value, color=config.value, align='right'} -- sort value
    self.height = self.height + lineheight
    y = y + lineheight
  end
end

-- Update
-- Fetch the top processes for the saved sort. Conky starts collecting a sort
-- the first time it is read, so an empty list is read again next frame.
function processes:update()
  if utils.check_update(self.last_update, self.update_interval) then
    local sort = self:sort()
    self.procs = {}
    for i=1, self.max_count do
      self.procs[i] = {
        name = utils.parse(sort.sortby..' name '..i),
        mem = utils.parse(sort.sortby..' mem_res '..i),
        value = utils.parse(sort.sortby..' '..sort.value..' '..i)..sort.suffix,
      }
    end
    if utils.trim(self.procs[1].name) ~= '' then self.last_update = socket.gettime() end
  end
end

-- Sort
-- Returns the saved sort, sorting by CPU by default
function processes:sort()
  local sortby = toggles.get('processes', 'sortby', 'top')
  for _, sort in ipairs(self.SORTS) do
    if sort.sortby == sortby then return sort end
  end
  return self.SORTS[1]
end

-- Set Sort
-- Saves the sort and refreshes the list
function processes:set_sort(sortby)
  toggles.set('processes', 'sortby', sortby)
  self.last_update = nil
end

-- Click
-- Perform click action
function processes:click(event, x, y)
  if y < 40 then
    os.execute(self.onclick..' &')
  elseif x < 110 then
    toggles.set('processes', 'show_more', not toggles.get('processes', 'show_more', false))
  elseif x >= 110 and x < 150 then
    self:set_sort('top_mem')
  elseif x >= 150 then
    self:set_sort('top')
  end
end

-- Menu
-- Returns right click menu items to change the sort or number of processes
function processes:menu()
  local sorts = function()
    local items = {}
    for _, sort in ipairs(self.SORTS) do
      table.insert(items, menu.choice(sort.label, 'processes', 'sortby', sort.sortby, 'top',
        function() self.last_update = nil end))
    end
    return items
  end
  return {
    {label='Sort by', items=sorts},
    menu.toggle('Show more', 'processes', 'show_more', false),
    menu.app(self.onclick),
  }
end

return processes
