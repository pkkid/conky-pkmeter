local config = require 'config'
local draw = require 'pkm/draw'
local socket = require 'socket'
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
nvidia.history_usage = nil
nvidia.history_temp = nil

-- Draw
-- Draw this widget
function nvidia:draw()
  self.height = 157

  -- Header
  color_usage = self.color_usage or config.accent
  draw.widget_header(self.origin, self.height, 'NVIDIA', self.cardname, function()
    draw.graph{data=self.history_usage, x=100, y=self.origin+8, width=90, height=24, color=color_usage,
      bgcolor=config.header_graph_bg, maxvalue=100, logscale=self.logscale}
  end)

  -- GPU Stats
  draw.stat_row(self.origin+61, 'GPU Usage', self.usage..'%')
  draw.stat_row(self.origin+76, 'GPU Temp', self.temp)
  draw.stat_row(self.origin+91, 'GPU Freq', self.freq)
  draw.stat_row(self.origin+106, 'Mem Used', self.mempct..'% of '..self.memtotal..'G')
  draw.stat_row(self.origin+121, 'Mem Rate', self.memrate)
  draw.stat_row(self.origin+136, 'Driver', self.driver)

  -- GPU Charts
  color_pwrpct = self.color_pwrpct or config.accent
  color_temp = self.color_temp or config.accent
  color_mem = self.color_mem or config.accent
  draw.bargraph{value=self.pwrpct, x=155, y=self.origin+53, width=35, height=3, color=color_pwrpct, bgcolor=config.graph_bg} -- power percent
  draw.text{x=154, y=self.origin+64, text=self.pwrdraw..'W', size=8, bold=false, color=config.label, font='tiny5'} -- power draw
  draw.text{x=190, y=self.origin+64, text=self.pstate, size=8, bold=false, color=config.label, align='right', font='tiny5'} -- pstate
  draw.graph{data=self.history_temp, x=155, y=self.origin+74, width=35, height=12, color=color_temp,
    bgcolor=config.graph_bg, minvalue=35, maxvalue=100, logscale=false} -- temp history
  draw.ringgraph{value=self.mempct, x=172, y=self.origin+109, radius=9, width=5, color=color_mem, bgcolor=config.graph_bg} -- memory percent
end

-- Update
-- Update NVIDIA Data
function nvidia:update()
  if utils.check_update(self.last_update, self.update_interval) then
    -- Fetch Stats from nvidi-smi
    local cmd = self.nvidiasmi..' --format=csv,noheader --query-gpu='..table.concat(self.QUERY_GPU, ',')
    local result = utils.run_command(cmd)
    local data, i = {}, 0
    for value in result:gmatch('[^,]+') do
      i = i + 1
      local key = self.QUERY_GPU[i]:gsub('%.','_')
      data[key] = utils.trim(value)
    end

    self.cardname = utils.trim(data['name']:gsub('NVIDIA GeForce', ''))
    self.driver = 'v'..data.driver_version
    self.usage = tonumber(data.utilization_gpu:match('^(%d+)'))
    self.freq = data.clocks_current_graphics
    self.temp = utils.format_temp(data.temperature_gpu, self.temperature_unit)
    self.mempct = tonumber(data.utilization_memory:match('^(%d+)'))
    self.memtotal = utils.round(tonumber(data.memory_total:match('^(%d+)')) / 1024)
    self.memrate = (tonumber(data.clocks_current_memory:match('^(%d+)')) * 2)..' MHz' -- x2 for DDR
    self.pwrpct = utils.percent(tonumber(data.power_draw:match('^(%d+)')), tonumber(data.power_limit:match('^(%d+)')))
    self.pwrdraw = utils.round(tonumber(data.power_draw:match('^(%d+)')))
    self.pstate = data.pstate

    -- Update History
    local usage = tonumber(data.utilization_gpu:match('^(%d+)'))
    local temp = tonumber(data.temperature_gpu)
    self.history_usage = utils.push_history(self.history_usage, usage, 90)
    self.history_temp = utils.push_history(self.history_temp, temp, 35)
    self.last_update = socket.gettime()
  end
end

-- Click
-- Perform click action
function nvidia:click(event, x, y)
  if y < 40 then os.execute(self.onclick..' &') end
end

return nvidia
