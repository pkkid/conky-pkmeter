local config = require 'config'
local draw = require 'pkm/draw'
local utils = require 'pkm/utils'

local nowplaying = {}
nowplaying.PLAYERCTL_FORMAT = {'playername={{playerName}}', 'status={{status}}',
  'title={{title}}', 'artist={{artist}}', 'album={{album}}', 'length={{mpris:length}}',
  'position={{position}}', 'arturl={{mpris:artUrl}}'}
nowplaying.origin = 0
nowplaying.height = 0
nowplaying.players = {}
nowplaying.last_update = nil

-- Draw
-- Draw this widget
function nowplaying:draw()
  if #self.players == 0 then return 0 end
  self.height = 51

  -- Header
  local playernames = self:list_playernames(self.players, self.max_players)
  draw.rectangle{x=0, y=self.origin+0, width=conky_window.width, height=40, color=config.header_bg} -- header background
  draw.rectangle{x=0, y=self.origin+40, width=conky_window.width, height=self.height-40, color=config.background} -- background
  draw.text{x=10, y=self.origin+17, text='Now Playing', size=12, color=config.header} -- now playing
  draw.text{x=10, y=self.origin+32, text=playernames, color=config.subheader, maxwidth=180} -- player names

  -- Player Info
  local y = self.origin + 50
  for _, player in ipairs(self.players) do
    local duration = utils.duration(player.position)..' of '..utils.duration(player.length)
    draw.rectangle{x=0, y=y-1, width=conky_window.width, height=67, color=config.background} -- background
    draw.bargraph{x=10, y=y, width=120, height=2, value=player.position, maxvalue=player.length,
      color=config.accent, bgcolor=config.graph_bg} -- progress
    draw.text{x=10, y=y+17, text=player.title, maxwidth=120, color=config.value} -- title
    draw.text{x=10, y=y+32, text=player.artist, maxwidth=120, color=config.label} -- artist
    draw.text{x=10, y=y+47, text=duration, color=config.label} -- duration
    draw.image{x=140, y=y+0, path=player.artpath, width=50}
    self.height = self.height + 67
    y = y + 67
  end
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
        if player.length then player.length = math.floor(tonumber(player.length) / 1000000) end
        if player.position then player.position = math.floor(tonumber(player.position) / 1000000) end
        if player.arturl then player.artpath = self:get_artpath(player.playername, player.arturl) end
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
function nowplaying:get_artpath(playername, arturl)
  local player = self:get_player_by_name(playername)
  if player and player.arturl == arturl then
    return player.artpath
  elseif string.sub(arturl, 1, 7) == 'file://' then
    return string.sub(arturl, 7)
  else
    return utils.download_image(arturl)
  end
end

-- Get Player by Name
-- Returns the player object by playername
function nowplaying:get_player_by_name(playername)
  for _, player in ipairs(self.players) do
    if player.playername == playername then return player end
  end
  return nil
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