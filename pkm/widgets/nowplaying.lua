local config = require 'config'
local draw = require 'pkm/draw'
local utils = require 'pkm/utils'

local nowplaying = {}
nowplaying.PLAYERCTL_FORMAT = {'playername={{playerName}}', 'status={{status}}',
  'title={{title}}', 'artist={{artist}}', 'album={{album}}', 'length={{mpris:length}}',
  'position={{position}}', 'arturl={{mpris:artUrl}}'}
nowplaying.players = {}
nowplaying.last_update = nil

-- Draw
-- Draw this widget
function nowplaying:draw(origin)
  if #self.players == 0 then return 0 end
  origin = origin or 0
  local height = 51 + (#self.players * 67)

  -- Header
  local playernames = self:list_playernames(self.players, self.max_players)
  draw.rectangle{x=0, y=origin+0, width=conky_window.width, height=40, color=config.header_bg} -- header background
  draw.rectangle{x=0, y=origin+40, width=conky_window.width, height=height-40, color=config.background} -- background
  draw.text{x=10, y=origin+17, text='Now Playing', size=12, color=config.header} -- now playing
  draw.text{x=10, y=origin+32, text=playernames, color=config.subheader} -- player names

  -- Player Info
  y = origin + 50
  for _, player in ipairs(self.players) do
    local duration = utils.duration(player.position)..' of '..utils.duration(player.length)
    draw.bargraph{x=10, y=y, width=120, height=2, value=player.position, maxvalue=player.length,
      color=config.accent, bgcolor=config.graph_bg} -- progress
    draw.text{x=10, y=y+17, text=string.sub(player.title, 1, 23), color=config.value} -- title
    draw.text{x=10, y=y+32, text=string.sub(player.artist, 1, 23), color=config.label} -- artist
    draw.text{x=10, y=y+47, text=duration, color=config.label} -- duration
    draw.image{x=140, y=y+0, path=player.artpath, width=50}
    y = y + 67
  end

  return height
end

-- Update
-- Update Playerctl info
function nowplaying:update()
  if utils.check_update(self.last_update, config.update_interval) then
    players = {}
    cmd = self.playerctl..' metadata -af "'..table.concat(self.PLAYERCTL_FORMAT, ';;')..'"'
    if self.ignore_players and #self.ignore_players > 0 then
      cmd = cmd..' -i '..self.ignore_players
    end
    local result = utils.run_command(cmd)
    i = 1
    for line in string.gmatch(result, "[^\r\n]+") do
      local player = {}
      for keyval in string.gmatch(line, "([^;;]+)") do
        local key, val = string.match(keyval, "^(%S+)=(.+)$")
        if key and val then player[key] = val end
      end
      if player.status == 'Playing' then
        if player.length then player.length = tonumber(player.length) end
        if player.position then player.position = tonumber(player.position) end
        if player.arturl then player.artpath = self:get_artpath(i, player.arturl) end
        table.insert(players, player)
        if #players >= self.max_players then break end
      end
      i = i + 1
    end
    -- Clenaup old _art objects (in case it leaks memory)
    for _, player in ipairs(self.players) do player._art = nil end
    self.players = players
    self.last_update = os.time()
  end
end

-- Get Image Data
-- Check we need to download the image for this player
function nowplaying:get_artpath(i, arturl)
  prefix = string.sub(arturl, 1, 7)
  if self.players[i] and self.players[i].arturl == arturl then
    return self.players[i].artpath
  elseif string.sub(arturl, 1, 7) == 'file://' then
    return string.sub(arturl, 7)
  else
    return utils.download_image(arturl)
  end
end

-- List Playernames
-- Returns a comma seperated string of player names
function nowplaying:list_playernames(players, max_players)
  local names = {}
  for _, player in ipairs(players) do
    local name = utils.titleize(player.playername)
    table.insert(names, name)
  end
  return table.concat(names, ', ')
end

return nowplaying