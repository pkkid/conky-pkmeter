local config = require 'config'
local draw = require 'pkm/draw'
local utils = require 'pkm/utils'

local radeon = {}
radeon.origin = 0
radeon.height = 0
radeon.last_update = nil
radeon.data = nil
radeon.history = nil

-- Draw
-- Draw this widget
function radeon:draw()
  self.height = 142

  -- Header
  draw.widget_header(self.origin, self.height, 'AMD GPU', self.gpuname)

  -- GPU Stats
  local temp = utils.format_temp(utils.parse(self.gputemp), self.temperature_unit)
  local gpufreq = math.floor(tonumber(utils.parse(self.gpufreq) or '0') / 1000000)
  local memrate = utils.round(tonumber(self.data.mclk_meta:match('^([%d%.]+)') or '0') * 1000.0)
  local memamt = self.data.vram_meta:gsub("%.%d+", "")
  draw.stat_row(self.origin+61, 'GPU Usage', self.data.gpu..'%')
  draw.stat_row(self.origin+76, 'GPU Temp', temp)
  draw.stat_row(self.origin+91, 'GPU Freq', gpufreq..' MHz')
  draw.stat_row(self.origin+106, 'Mem Used', self.data.vram..'% '..memamt)
  draw.stat_row(self.origin+121, 'Mem Rate', memrate..' MHz')

  -- GPU Charts
  draw.graph{data=self.history, x=155, y=self.origin+53, width=35, height=23, color=config.accent,
    bgcolor=config.graph_bg, maxvalue=100, logscale=self.logscale} -- gpu history
  draw.ringgraph{value=self.data.vram, x=172, y=self.origin+109, radius=9, width=5,
    color=config.accent, bgcolor=config.graph_bg} -- memory percent
end

-- Update
-- Update AMD GPU Data
function radeon:update()
  if utils.check_update(self.last_update, config.update_interval) then
    -- Fetch stats from radeontop. Example output:
    -- Dumping to -, line limit 1.
    -- 1740072917.256376: bus 01, gpu 51.67%, ee 0.00%, vgt 22.50%, ta 30.83%, sx 34.17%, \
    --   sh 0.00%, spi 47.50%, sc 39.17%, pa 23.33%, db 39.17%, cb 35.83%, vram 99.92% 876.18mb, \
    --   gtt 4.03% 645.77mb, mclk 100.00% 0.800ghz, sclk 37.50% 0.300ghz
    local data = {}
    local cmd = self.radeontop..' -l 1 -d -'
    local result = utils.run_command(cmd)..','
    for key, value in result:gmatch('(%l+) ([%d%.%%%l%s]+),') do
      if string.find(value, ' ') then
        value, meta = value:match('([^ ]+) (.+)')
        meta = meta:gsub('mb', 'M'):gsub('gb', 'G'):gsub('ghz', ' GHz')
        data[key..'_meta'] = meta
      end
      value = value:gsub('%%', '')
      data[key] = utils.round(tonumber(value))
    end

    -- Update History
    self.history = utils.push_history(self.history, data.gpu, 35)

    if data then self.data = data end
    self.last_update = os.time()
  end
end

return radeon