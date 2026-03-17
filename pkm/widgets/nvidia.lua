local config = require 'config'
local draw = require 'pkm/draw'
local utils = require 'pkm/utils'

local nvidia = {}
nvidia.QUERY_GPU = {
  'name', 'driver_version', 'clocks.current.graphics', 'clocks.current.memory',
  'clocks.current.sm', 'clocks.current.video', 'clocks.max.graphics', 'clocks.max.memory',
  'clocks.max.sm', 'fan.speed', 'memory.total', 'memory.used', 'power.draw', 'power.limit',
  'pstate', 'temperature.gpu', 'utilization.gpu', 'utilization.memory'
}
nvidia.origin = 0
nvidia.height = 0
nvidia.last_update = nil
nvidia.data = nil
nvidia.history = nil

-- Draw
-- Draw this widget
function nvidia:draw()
  self.height = 142

  -- Header
  local name = utils.trim(self.data['name']:gsub('NVIDIA', ''))..' - v'..self.data.driver_version
  draw.widget_header(self.origin, self.height, 'NVIDIA', name)

  -- GPU Stats
  local usage = tonumber(self.data.utilization_gpu:match('^(%d+)'))
  local temp = utils.format_temp(self.data.temperature_gpu, self.temperature_unit)
  local mempct = tonumber(self.data.utilization_memory:match('^(%d+)'))
  local memtotal = utils.round(tonumber(self.data.memory_total:match('^(%d+)')) / 1024)..'G'
  local memrate = (tonumber(self.data.clocks_current_memory:match('^(%d+)')) * 2)..' MHz' -- x2 for DDR
  draw.stat_row(self.origin+61, 'GPU Usage', usage..'%')
  draw.stat_row(self.origin+76, 'GPU Temp', temp)
  draw.stat_row(self.origin+91, 'GPU Freq', self.data.clocks_current_graphics)
  draw.stat_row(self.origin+106, 'Mem Used', mempct..'% of '..memtotal)
  draw.stat_row(self.origin+121, 'Mem Rate', memrate)

  -- GPU Charts
  draw.graph{data=self.history, x=155, y=self.origin+53, width=35, height=23, color=config.accent,
    bgcolor=config.graph_bg, maxvalue=100, logscale=self.logscale} -- gpu history
  local pwrpct = utils.percent(tonumber(self.data.power_draw:match('^(%d+)')), tonumber(self.data.power_limit:match('^(%d+)')))
  local pwrdraw = utils.round(tonumber(self.data.power_draw:match('^(%d+)')))
  draw.bargraph{value=pwrpct, x=155, y=self.origin+82, width=35, height=2, color=config.accent, bgcolor=config.graph_bg} -- power percent
  draw.text{x=154, y=self.origin+91, text=pwrdraw..'W', size=7, bold=false, color=config.label} -- power draw
  draw.text{x=190, y=self.origin+91, text=self.data.pstate, size=7, bold=false, color=config.label, align='right'} -- pstate
  draw.ringgraph{value=mempct, x=172, y=self.origin+109, radius=9, width=5, color=config.accent, bgcolor=config.graph_bg} -- memory percent
end

-- Update
-- Update NVIDIA Data
function nvidia:update()
  if utils.check_update(self.last_update, config.update_interval) then
    -- Fetch Stats from nvidi-smi
    local cmd = self.nvidiasmi..' --format=csv,noheader --query-gpu='..table.concat(self.QUERY_GPU, ',')
    local result = utils.run_command(cmd)
    local data, i = {}, 0
    for value in result:gmatch('[^,]+') do
      i = i + 1
      local key = self.QUERY_GPU[i]:gsub('%.','_')
      data[key] = utils.trim(value)
    end

    -- Update History
    local usage = tonumber(data.utilization_gpu:match('^(%d+)'))
    self.history = utils.push_history(self.history, usage, 35)

    if data then self.data = data end
    self.last_update = os.time()
  end
end

-- Click
-- Perform click action
function nvidia:click(event, x, y)
  if y < 40 then os.execute(self.onclick..' &') end
end

return nvidia
