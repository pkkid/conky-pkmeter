local config = require 'config'
local draw = require 'pkm/draw'
local utils = require 'pkm/utils'

local networks = {}
networks.extip = nil
networks.extip_last_update = nil
networks.history_upspeed = nil
networks.history_downspeed = nil
networks.history_last_update = nil

-- Draw
-- Draw this widget
function networks:draw(origin)
  origin = origin or 0
  local height = 57 + (#self.devices * 55)

  -- Header
  draw.rectangle{x=0, y=origin+0, width=conky_window.width, height=40, color=config.header_bg} -- header background
  draw.rectangle{x=0, y=origin+40, width=conky_window.width, height=height-40, color=config.background} -- background
  draw.text{x=10, y=origin+17, text='Networks', size=12, color=config.header} -- networks
  draw.text{x=10, y=origin+32, text=self.extip, color=config.subheader} -- external ip
  draw.graph{data=self.history_upspeed, x=100, y=origin+8, width=90, height=12, color=self.upspeed_color,
    bgcolor=config.header_graph_bg, minmaxvalue=100, logscale=self.logscale} -- upspeed graph
    draw.graph{data=self.history_downspeed, x=100, y=origin+20, width=90, height=12, origin='top', color=self.downspeed_color,
    bgcolor=config.header_graph_bg, minmaxvalue=100, logscale=self.logscale} -- downspeed graph

  -- Devices
  y = origin + 61
  for _, device in ipairs(self.devices) do
    draw.text{x=10, y=y, text=device, color=config.value} -- device name
    draw.text{x=190, y=y, text=utils.parse('addr '..device), color=config.value, align='right'} -- local ip address
    draw.text{x=10, y=y+15, text='Upload', color=config.label} -- upload
    draw.text{x=190, y=y+15, text=utils.parse('upspeed '..device)..'/s of '..utils.parse('totalup '..device), color=config.value, align='right'} -- upspeed
    draw.text{x=10, y=y+30, text='Download', color=config.label} -- download
    draw.text{x=190, y=y+30, text=utils.parse('downspeed '..device)..'/s of '..utils.parse('totaldown '..device), color=config.value, align='right'} -- downspeed
    y = y + 55
  end

  return height
end

-- Update
-- Update External IP & Network History
function networks:update()
  -- External IP
  if utils.check_update(self.extip_last_update, self.extip_update_interval) then
    self.extip = utils.request{url=self.extip_url}
    self.extip_last_update = os.time()
  end
  -- Network History
  if utils.check_update(self.history_last_update, config.update_interval) then
    self.history_upspeed = self.history_upspeed or utils.init_table(90, 0)
    self.history_downspeed = self.history_downspeed or utils.init_table(90, 0)
    local upspeed = 0
    local downspeed = 0
    for _, device in ipairs(self.devices) do
      upspeed = upspeed + tonumber(utils.parse('upspeedf '..device))
      downspeed = downspeed + tonumber(utils.parse('downspeedf '..device))
    end
    table.insert(self.history_upspeed, upspeed)
    table.remove(self.history_upspeed, 1)
    table.insert(self.history_downspeed, downspeed)
    table.remove(self.history_downspeed, 1)
    self.history_last_update = os.time()
  end
end

return networks