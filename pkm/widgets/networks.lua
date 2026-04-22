local config = require 'config'
local draw = require 'pkm/draw'
local socket = require 'socket'
local utils = require 'pkm/utils'

local networks = {}
networks.origin = 0
networks.height = 0
networks.extip = nil
networks.extip_last_update = nil
networks.last_update = nil
networks.history_upspeed = nil
networks.history_downspeed = nil
networks.show_all = false


-- Draw
-- Draw this widget
function networks:draw()
  self.height = 57

  -- Header
  draw.widget_header(self.origin, self.height, 'Networks', self.extip, function()
    draw.graph{data=self.history_upspeed, x=100, y=self.origin+8, width=90, height=12, color=self.upspeed_color,
      bgcolor=config.header_graph_bg, minmaxvalue=50, logscale=self.logscale}
    draw.graph{data=self.history_downspeed, x=100, y=self.origin+20, width=90, height=12, origin='top', color=self.downspeed_color,
      bgcolor=config.header_graph_bg, minmaxvalue=50, logscale=self.logscale}
  end)

  -- Devices
  local y = self.origin + 61
  for _, dev in ipairs(self.devices) do
    if dev.ipaddr ~= 'No Address' or self.show_all then
      draw.rectangle{x=0, y=y-4, width=conky_window.width, height=55, color=config.background} -- background
      draw.text{x=10, y=y, text=dev.name, color=config.value} -- device name
      draw.text{x=190, y=y, text=dev.ipaddr, color=config.value, align='right'} -- local ip address
      draw.text{x=10, y=y+15, text='Upload', color=config.label} -- upload
      draw.text{x=190, y=y+15, text=dev.upspeed..'/s of '..dev.uptotal, color=config.value, align='right'} -- upspeed
      draw.text{x=10, y=y+30, text='Download', color=config.label} -- download
      draw.text{x=190, y=y+30, text=dev.downspeed..'/s of '..dev.downtotal, color=config.value, align='right'} -- downspeed
      self.height = self.height + 55
      y = y + 55
    end
  end
end

-- Update
-- Update External IP & Network History
function networks:update()
  -- External IP
  if utils.check_update(self.last_update_extip, self.update_interval_extip) then
    self.extip = utils.request{url=self.extip_url}
    self.last_update_extip = socket.gettime()
  end
  -- Network Devices
  
  if utils.check_update(self.last_update, self.update_interval) then
    local total_upspeed = 0
    local total_downspeed = 0
    for _, dev in ipairs(self.devices) do
      dev.name = dev.name
      dev.ipaddr = utils.parse('addr '..dev.device) or 'No Address'
      dev.upspeed = utils.parse('upspeed '..dev.device) or '0 B'
      dev.uptotal = utils.parse('totalup '..dev.device) or '0 B'
      dev.downspeed = utils.parse('downspeed '..dev.device) or '0 B'
      dev.downtotal = utils.parse('totaldown '..dev.device) or '0 B'
      total_upspeed = total_upspeed + (tonumber(utils.parse('upspeedf '..dev.device)) or 0)
      total_downspeed = total_downspeed + (tonumber(utils.parse('downspeedf '..dev.device)) or 0)
    end
    self.history_upspeed = utils.push_history(self.history_upspeed, total_upspeed, 90)
    self.history_downspeed = utils.push_history(self.history_downspeed, total_downspeed, 90)
    self.last_update = socket.gettime()
  else
    -- prime conky cache for device details. I dont use this value, but witout
    -- continuing to call addr, the values above will not update, not sure why.
    conky_parse('$addr '..self.devices[1].device) 
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
