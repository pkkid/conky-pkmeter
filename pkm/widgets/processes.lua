local config = require 'config'
local draw = require 'pkm/draw'
local socket = require 'socket'
local utils = require 'pkm/utils'

local processes = {}
processes.origin = 0
processes.height = 0

-- Draw
-- Draw this widget
function processes:draw()
  self.height = 68
  
  -- Header
  draw.widget_header(self.origin, self.height, 'Processes', utils.parse('processes')..' processes')
  
  -- Processes
  local y = self.origin + 61
  local lineheight = 15
  local procs = self.sortby == 'mem' and self.procs_by_mem or self.procs_by_cpu
  self.count = self.count or self.min_count
  for i=1, math.min(self.count, #procs) do
    draw.rectangle{x=0, y=y+7, width=conky_window.width, height=lineheight, color=config.background}
    draw.text{x=10, y=y, text=procs[i].name, color=config.label} -- process name
    draw.text{x=145, y=y, text=procs[i].mem, color=config.value, align='right'} -- cpu usage
    draw.text{x=190, y=y, text=procs[i].cpu..'%', color=config.value, align='right'} -- mem usage
    self.height = self.height + lineheight
    y = y + lineheight
  end
end

-- Update
-- Fetch clock data (gated to once per second)
function processes:update()
  if utils.check_update(self.last_update, self.update_interval) then
    self.procs_by_cpu = {}
    self.procs_by_mem = {}
    for i=1, self.max_count do
      self.procs_by_cpu[i] = {
        name = utils.parse('top name '..i),
        mem = utils.parse('top mem_res '..i),
        cpu = utils.parse('top cpu '..i)
      }
      self.procs_by_mem[i] = {
        name = utils.parse('top_mem name '..i),
        mem = utils.parse('top_mem mem_res '..i),
        cpu = utils.parse('top_mem cpu '..i)
      }
    end
    self.last_update = socket.gettime()
  end
end

-- Click
-- Perform click action
function processes:click(event, x, y)
  if y < 40 then
    os.execute(self.onclick..' &')
  elseif x < 110 then
    self.count = self.count == config.processes.min_count
      and config.processes.max_count or config.processes.min_count
  elseif x >= 110 and x < 150 then
    self.sortby = 'mem'
  elseif x >= 150 then
    self.sortby = 'cpu'
  end
end

return processes
