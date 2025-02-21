local config = require 'config'
local draw = require 'pkm/draw'
local utils = require 'pkm/utils'

local radeon = {}
radeon.last_update = nil
radeon.data = nil
radeon.history = nil

-- Draw
-- Draw this widget
function radeon:draw(origin)
  origin = origin or 0
  local height = 142

  -- Header
  -- local name = utils.trim(self.data['name']:gsub('Radeon', ''))..' - v'..self.data.driver_version
  draw.rectangle{x=0, y=origin+0, width=conky_window.width, height=40, color=config.header_bg} -- header background
  draw.rectangle{x=0, y=origin+40, width=conky_window.width, height=height-40, color=config.background} -- background
  draw.text{x=10, y=origin+17, text='AMD GPU', size=12, color=config.header} -- radeon
  draw.text{x=10, y=origin+32, text=self.gpuname, color=config.subheader} -- card name

  -- GPU Stats
  local temp, tempunit = utils.parse(self.gputemp), '°C'
  if self.temperature_unit == 'fahrenheit' then
    temp, tempunit = utils.celsius_to_fahrenheit(tonumber(temp)), '°F'
  end
  local gpufreq = math.floor(tonumber(utils.parse(self.gpufreq) or '0') / 1000000)
  local memrate = utils.round(tonumber(self.data.mclk_meta:match('^([%d%.]+)') or '0') * 1000.0)
  local memamt = self.data.vram_meta:gsub("%.%d+", "")
  draw.text{x=10, y=origin+61, text='GPU Usage', color=config.label} -- gpu usage
  draw.text{x=145, y=origin+61, text=self.data.gpu..'%', color=config.value, align='right'}
  draw.text{x=10, y=origin+76, text='GPU Temp', color=config.label} -- uptime
  draw.text{x=145, y=origin+76, text=temp..tempunit, color=config.value, align='right'}
  draw.text{x=10, y=origin+91, text='GPU Freq', color=config.label} -- gpu freq
  draw.text{x=145, y=origin+91, text=gpufreq..' MHz', color=config.value, align='right'}
  draw.text{x=10, y=origin+106, text='Mem Used', color=config.label} -- mem used
  draw.text{x=145, y=origin+106, text=self.data.vram..'% '..memamt, color=config.value, align='right'}
  draw.text{x=10, y=origin+121, text='Mem Rate', color=config.label} -- mem rate
  draw.text{x=145, y=origin+121, text=memrate..' MHz', color=config.value, align='right'}

  -- GPU Charts
  draw.graph{data=self.history, x=155, y=origin+53, width=35, height=23, color=config.accent,
    bgcolor=config.graph_bg, maxvalue=100, logscale=self.logscale} -- gpu history
  draw.ringgraph{value=self.data.vram, x=172, y=origin+109, radius=9, width=5,
    color=config.accent, bgcolor=config.graph_bg} -- memory percent

  return height
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
    self.history = self.history or utils.init_table(35, 0)
    table.insert(self.history, data.gpu)
    table.remove(self.history, 1)

    if data then self.data = data end
    self.last_update = os.time()
  end
end


return radeon