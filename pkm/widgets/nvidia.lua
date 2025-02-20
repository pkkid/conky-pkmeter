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
nvidia.last_update = nil
nvidia.data = nil
nvidia.history = nil

-- Draw
-- Draw this widget
function nvidia:draw(origin)
  origin = origin or 0
  local height = 142

  -- Header
  local name = utils.trim(self.data['name']:gsub('NVIDIA', ''))..' - v'..self.data.driver_version
  draw.rectangle{x=0, y=origin+0, width=conky_window.width, height=40, color=config.header_bg} -- header background
  draw.rectangle{x=0, y=origin+40, width=conky_window.width, height=height-40, color=config.background} -- background
  draw.text{x=10, y=origin+17, text='NVIDIA', size=12, color=config.header} -- nvidia
  draw.text{x=10, y=origin+32, text=name, color=config.subheader} -- card name

  -- GPU Stats
  local usage = tonumber(self.data.utilization_gpu:match('^(%d+)'))
  local temp, tempunit = self.data.temperature_gpu, '°C'
  if self.temperature_unit == 'fahrenheit' then
    temp, tempunit = utils.celsius_to_fahrenheit(tonumber(temp)), '°F'
  end
  local mempct = tonumber(self.data.utilization_memory:match('^(%d+)')) -- %
  local memtotal = utils.round(tonumber(self.data.memory_total:match('^(%d+)')) / 1024)..'G'
  local memrate = (tonumber(self.data.clocks_current_memory:match('^(%d+)')) * 2)..' MHz' -- x2 for DDR
  draw.text{x=10, y=origin+61, text='GPU Usage', color=config.label} -- gpu usage
  draw.text{x=145, y=origin+61, text=usage..'%', color=config.value, align='right'}
  draw.text{x=10, y=origin+76, text='GPU Temp', color=config.label} -- uptime
  draw.text{x=145, y=origin+76, text=temp..tempunit, color=config.value, align='right'}
  draw.text{x=10, y=origin+91, text='GPU Freq', color=config.label} -- gpu freq
  draw.text{x=145, y=origin+91, text=self.data.clocks_current_graphics, color=config.value, align='right'}
  draw.text{x=10, y=origin+106, text='Mem Used', color=config.label} -- mem used
  draw.text{x=145, y=origin+106, text=mempct..'% of '..memtotal, color=config.value, align='right'}
  draw.text{x=10, y=origin+121, text='Mem Rate', color=config.label} -- mem rate
  draw.text{x=145, y=origin+121, text=memrate, color=config.value, align='right'}

  -- GPU Charts
  
  draw.graph{data=self.history, x=155, y=origin+53, width=35, height=23, color=config.accent,
    bgcolor=config.graph_bg, maxvalue=100, logscale=self.logscale} -- gpu history

  -- GPU Utilization
  local pwrpct = utils.percent(tonumber(self.data.power_draw:match('^(%d+)')), tonumber(self.data.power_limit:match('^(%d+)')))
  local pwrdraw = utils.round(tonumber(self.data.power_draw:match('^(%d+)')))
  draw.bargraph{value=pwrpct, x=155, y=origin+82, width=35, height=2, color=config.accent, bgcolor=config.graph_bg} -- power percent
  draw.text{x=154, y=origin+91, text=pwrdraw..'W', size=8, bold=false, color=config.label} -- power draw
  draw.text{x=190, y=origin+91, text=self.data.pstate, size=8, bold=false, color=config.label, align='right'} -- pstate
  draw.ringgraph{value=mempct, x=172, y=origin+109, radius=9, width=5, color=config.accent, bgcolor=config.graph_bg} -- memory percent

  return height
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
    self.history = self.history or utils.init_table(35, 0)
    usage = tonumber(data.utilization_gpu:match('^(%d+)'))
    table.insert(self.history, usage)
    table.remove(self.history, 1)

    if data then self.data = data end
    self.last_update = os.time()
  end
end


return nvidia