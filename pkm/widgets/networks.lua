local config = require 'config'
local draw = require 'pkm/draw'
local utils = require 'pkm/utils'

local networks = {}
networks.origin = 0
networks.height = 0
networks.extip = nil
networks.extip_last_update = nil
networks.history_upspeed = nil
networks.history_downspeed = nil
networks.history_last_update = nil
networks.show_all = false

-- Draw
-- Draw this widget
function networks:draw()
  self.height = 57

  -- Header
  draw.rectangle{x=0, y=self.origin+0, width=conky_window.width, height=40, color=config.header_bg} -- header background
  draw.rectangle{x=0, y=self.origin+40, width=conky_window.width, height=self.height-40, color=config.background} -- background
  draw.text{x=10, y=self.origin+17, text='Networks', size=12, color=config.header} -- networks
  draw.text{x=10, y=self.origin+32, text=self.extip, color=config.subheader} -- external ip
  draw.graph{data=self.history_upspeed, x=100, y=self.origin+8, width=90, height=12, color=self.upspeed_color,
    bgcolor=config.header_graph_bg, minmaxvalue=50, logscale=self.logscale} -- upspeed graph
  draw.graph{data=self.history_downspeed, x=100, y=self.origin+20, width=90, height=12, origin='top', color=self.downspeed_color,
    bgcolor=config.header_graph_bg, minmaxvalue=50, logscale=self.logscale} -- downspeed graph

  -- Devices
  y = self.origin + 61
  for _, dev in ipairs(self.devices) do
    local ipaddr = utils.parse('addr '..dev.device)
    if ipaddr ~= 'No Address' or self.show_all then
      draw.rectangle{x=0, y=y-4, width=conky_window.width, height=55, color=config.background} -- background
      draw.text{x=10, y=y, text=dev.name, color=config.value} -- device name
      draw.text{x=190, y=y, text=utils.parse('addr '..dev.device), color=config.value, align='right'} -- local ip address
      draw.text{x=10, y=y+15, text='Upload', color=config.label} -- upload
      draw.text{x=190, y=y+15, text=utils.parse('upspeed '..dev.device)..'/s of '..utils.parse('totalup '..dev.device), color=config.value, align='right'} -- upspeed
      draw.text{x=10, y=y+30, text='Download', color=config.label} -- download
      draw.text{x=190, y=y+30, text=utils.parse('downspeed '..dev.device)..'/s of '..utils.parse('totaldown '..dev.device), color=config.value, align='right'} -- downspeed
      self.height = self.height + 55
      y = y + 55
    end
  end
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
    for _, dev in ipairs(self.devices) do
      upspeed = upspeed + tonumber(utils.parse('upspeedf '..dev.device))
      downspeed = downspeed + tonumber(utils.parse('downspeedf '..dev.device))
    end
    table.insert(self.history_upspeed, upspeed)
    table.remove(self.history_upspeed, 1)
    table.insert(self.history_downspeed, downspeed)
    table.remove(self.history_downspeed, 1)
    self.history_last_update = os.time()
  end
end

-- Click
-- Perform click action
function networks:click(event, x, y)
  if y < 40 then
    os.execute(self.onclick..' &')
  else
    self.show_all = not self.show_all
  end
end

return networks