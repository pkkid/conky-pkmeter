local config = require 'config'
local discordrpc = require 'pkm/utils/discordrpc'
local draw = require 'pkm/draw'
local json = require 'pkm/json'
local socket = require 'socket'
local utils = require 'pkm/utils'

local discord = {}
discord.title = 'Discord'
discord.origin = 0
discord.height = 0
discord.CLIENT_ID = '207646673902501888'   -- Discord StreamKit, whose tokens allow local RPC
discord.TOKEN_URL = 'https://streamkit.discord.com/overlay/token'
discord.SCOPES = {'rpc', 'messages.read', 'rpc.notifications.read'}
discord.CHANNEL_EVENTS = {'VOICE_STATE_CREATE', 'VOICE_STATE_UPDATE', 'VOICE_STATE_DELETE',
  'SPEAKING_START', 'SPEAKING_STOP'}
discord.BUTTONS = {mute=118, deaf=146, leave=174}   -- Header button x positions (18px icons, 10px apart)
discord.ROW_HEIGHT = 22
discord.members = {}
discord.speaking = {}
discord.avatars = {}
discord.guilds = {}

-- Draw
-- Draws the header buttons and a two column list of channel members
function discord:draw()
  if not self.channel then
    self.height = 0
    return
  end
  local rows = math.ceil(#self.members / 2)
  self.height = 61 + (rows * self.ROW_HEIGHT)
  local me = self:member(self.rpc and self.rpc.user.id) or {}
  draw.widget_header(self.origin, self.height, 'Discord', nil, function()
    self:draw_subtitle(self.origin + 32, 100)
    self:draw_button(self.BUTTONS.mute, me.self_mute and 'mic_off' or 'mic')
    self:draw_button(self.BUTTONS.deaf, me.self_deaf and 'headset_off' or 'headset')
    self:draw_button(self.BUTTONS.leave, 'leave')
  end)
  for i, member in ipairs(self.members) do
    local x = 10 + ((i - 1) % 2) * 95
    local y = self.origin + 50 + math.floor((i - 1) / 2) * self.ROW_HEIGHT
    self:draw_avatar(member, x, y)
    local quiet = member.self_mute or member.self_deaf or member.mute or member.deaf
    draw.text{x=x+22, y=y+12, text=member.name, maxwidth=66, color=quiet and config.label or config.value}
  end
end

-- Draw Subtitle
-- Draws the server name (or channel name outside a server), shortened so the people count always fits
function discord:draw_subtitle(y, maxwidth)
  local guild = self.guilds[self.channel.guild_id]
  local name = guild or self.channel.name
  local count = ' ('..#self.members..')'
  local countwidth = draw.text_width{text=count}
  local width = draw.text{x=10, y=y, text=name, maxwidth=maxwidth-countwidth, color=config.subheader}
  draw.text{x=10+width, y=y, text=count, color=config.subheader}
end

-- Draw Avatar
-- Draws a round avatar with a ring while speaking and a dot when muted
function discord:draw_avatar(member, x, y)
  local cx, cy, radius = x + 8, y + 8, 8
  local image = self:avatar_surface(member)
  cairo_save(cr)
  cairo_arc(cr, cx, cy, radius, 0, 2 * math.pi)
  cairo_clip(cr)
  if image then
    local scale = (radius * 2) / cairo_image_surface_get_width(image)
    cairo_translate(cr, x, y)
    cairo_scale(cr, scale, scale)
    cairo_set_source_surface(cr, image, 0, 0)
    cairo_paint(cr)
  else
    draw.rectangle{x=x, y=y, width=16, height=16, color=config.graph_bg}
  end
  cairo_restore(cr)
  if self.speaking[member.id] then
    draw.ring{x=cx, y=cy, radius=radius+1, width=2, color=self.speaking_color}
  end
  if member.self_mute or member.self_deaf or member.mute or member.deaf then
    draw.dot{x=x+14, y=y+14, radius=3, color=self.muted_color}
  end
end

-- Draw Button
-- Draws an 18px header button icon from pkm/img/discord, centered in the header bar
function discord:draw_button(x, icon)
  draw.image{x=x, y=self.origin+11, path=pkmeter.ROOT..'/pkm/img/discord/'..icon..'.png', width=18}
end

-- Update
-- Reads listener events while in a channel, otherwise checks for a channel each interval
function discord:update()
  if self.rpc then
    for _, msg in ipairs(self.rpc:poll()) do self:handle(msg) end
    if self.rpc and self.rpc.closed then self:disconnect() end
    if self.auth_nonce and socket.gettime() > self.auth_expires then self:disconnect() end
  elseif utils.check_update(self.last_check, self.check_interval) then
    self.last_check = socket.gettime()
    self:check()
  end
end

-- Check
-- Connects to Discord and starts the listener if we are in a voice channel
function discord:check()
  local rpc, err = discordrpc.connect(self.CLIENT_ID)
  if not rpc then return end
  self.rpc = rpc
  local token = self:load_token()
  if token then
    if rpc:call('AUTHENTICATE', {access_token=token}) then return self:refresh() end
    os.remove(self.token_file)
  end
  -- Ask once per run for approval; the reply arrives later through handle()
  if self.auth_asked then return self:disconnect() end
  self.auth_asked = true
  self.auth_nonce = rpc:request('AUTHORIZE', {client_id=self.CLIENT_ID, scopes=self.SCOPES, prompt='none'})
  self.auth_expires = socket.gettime() + 120
end

-- Refresh
-- Loads the selected voice channel and subscribes to its events, or disconnects
function discord:refresh()
  local channel = self.rpc:call('GET_SELECTED_VOICE_CHANNEL')
  if not channel or not channel.id then return self:disconnect() end
  if self.channel and self.channel.id ~= channel.id then
    for _, evt in ipairs(self.CHANNEL_EVENTS) do
      self.rpc:request('UNSUBSCRIBE', {channel_id=self.channel.id}, evt)
    end
  end
  if not self.channel then self.rpc:request('SUBSCRIBE', {}, 'VOICE_CHANNEL_SELECT') end
  if self.channel == nil or self.channel.id ~= channel.id then
    for _, evt in ipairs(self.CHANNEL_EVENTS) do
      self.rpc:request('SUBSCRIBE', {channel_id=channel.id}, evt)
    end
  end
  if channel.guild_id and not self.guilds[channel.guild_id] then
    local guild = self.rpc:call('GET_GUILD', {guild_id=channel.guild_id})
    self.guilds[channel.guild_id] = guild and guild.name
  end
  self.channel = {id=channel.id, name=channel.name, guild_id=channel.guild_id}
  self.members = {}
  self.speaking = {}
  for _, state in ipairs(channel.voice_states or {}) do self:set_member(state) end
end

-- Handle
-- Applies one message from the listener to the widget state
function discord:handle(msg)
  if self.auth_nonce and msg.nonce == self.auth_nonce then
    self.auth_nonce = nil
    local token = msg.evt ~= 'ERROR' and msg.data and self:exchange_code(msg.data.code)
    if token and self.rpc:call('AUTHENTICATE', {access_token=token}) then return self:refresh() end
    return self:disconnect()
  end
  local data = msg.data or {}
  if msg.evt == 'SPEAKING_START' then
    self.speaking[data.user_id] = true
  elseif msg.evt == 'SPEAKING_STOP' then
    self.speaking[data.user_id] = nil
  elseif msg.evt == 'VOICE_STATE_CREATE' or msg.evt == 'VOICE_STATE_UPDATE' then
    self:set_member(data)
  elseif msg.evt == 'VOICE_STATE_DELETE' then
    self:remove_member(data.user.id)
  elseif msg.evt == 'VOICE_CHANNEL_SELECT' then
    if data.channel_id then self:refresh() else self:disconnect() end
  end
end

-- Stop
-- Closes the listener while the widget is hidden and checks again as soon as it is shown
function discord:stop()
  if self.rpc then self:disconnect() end
  self.last_check = nil
end

-- Disconnect
-- Stops the listener, hides the widget, and waits for the next check
function discord:disconnect()
  if self.rpc then self.rpc:close() end
  self.rpc = nil
  self.channel = nil
  self.auth_nonce = nil
  self.members = {}
  self.speaking = {}
  self.last_check = socket.gettime()
end

-- Set Member
-- Adds or updates a member from a voice state and queues their avatar
function discord:set_member(state)
  local user, voice = state.user or {}, state.voice_state or {}
  local member = self:member(user.id)
  if not member then
    member = {id=user.id}
    table.insert(self.members, member)
  end
  member.name = state.nick or user.global_name or user.username or '?'
  member.avatar = self:avatar_url(user)
  member.self_mute, member.self_deaf = voice.self_mute, voice.self_deaf
  member.mute, member.deaf = voice.mute, voice.deaf
end

-- Remove Member
-- Removes a member who left the channel
function discord:remove_member(id)
  for i, member in ipairs(self.members) do
    if member.id == id then table.remove(self.members, i); break end
  end
  self.speaking[id] = nil
end

-- Member
-- Returns the member with the given user id
function discord:member(id)
  for _, member in ipairs(self.members) do
    if member.id == id then return member end
  end
end

-- Avatar URL
-- Returns the user's avatar url, or one of Discord's default avatars
function discord:avatar_url(user)
  if user.avatar then
    return 'https://cdn.discordapp.com/avatars/'..user.id..'/'..user.avatar..'.png?size=32'
  end
  local index = (math.tointeger(tonumber(user.id)) or 0) >> 22
  return 'https://cdn.discordapp.com/embed/avatars/'..(index % 6)..'.png'
end

-- Avatar Surface
-- Returns a cached cairo surface for the avatar, downloading it in the background first
function discord:avatar_surface(member)
  local url = member.avatar
  if not url then return nil end
  local cached = self.avatars[url]
  if cached then return cached end
  local path = self.cache_dir..'/'..url:match('([^/]+/[^/?]+)%.png'):gsub('/', '-')..'.png'
  local handle = io.open(path, 'rb')
  if handle then
    handle:close()
    local image = cairo_image_surface_create_from_png(path)
    if cairo_surface_status(image) == CAIRO_STATUS_SUCCESS then
      self.avatars[url] = image
      return image
    end
    cairo_surface_destroy(image)
    os.remove(path)
  end
  self.downloading = self.downloading or {}
  if not self.downloading[url] then
    self.downloading[url] = true
    os.execute(string.format('mkdir -p %q && curl -sfL --max-time 10 -o %q %q && mv %q %q &',
      self.cache_dir, path..'.part', url, path..'.part', path))
  end
  return nil
end

-- Load Token
-- Returns the saved access token, if any
function discord:load_token()
  local handle = io.open(self.token_file, 'r')
  if not handle then return nil end
  local ok, data = pcall(json.decode, handle:read('a'))
  handle:close()
  return ok and type(data) == 'table' and data.access_token or nil
end

-- Exchange Code
-- Trades an authorization code for an access token and saves it
function discord:exchange_code(code)
  if not code then return nil end
  local https = require 'ssl.https'
  local ltn12 = require 'ltn12'
  local body, response = json.encode({code=code}), {}
  https.request{url=self.TOKEN_URL, method='POST', source=ltn12.source.string(body),
    headers={['content-type']='application/json', ['content-length']=#body},
    sink=ltn12.sink.table(response)}
  local ok, data = pcall(json.decode, table.concat(response))
  if not ok or type(data) ~= 'table' or not data.access_token then return nil end
  os.execute(string.format('mkdir -p %q', self.token_file:match('^(.*)/') or '.'))
  local handle = io.open(self.token_file, 'w')
  if handle then
    handle:write(json.encode({access_token=data.access_token}))
    handle:close()
    os.execute(string.format('chmod 600 %q', self.token_file))
  end
  return data.access_token
end

-- Toggle
-- Flips our own mute or deafen setting
function discord:toggle(key)
  local me = self:member(self.rpc.user.id) or {}
  local args = {}
  if key == 'mute' then args.mute = not me.self_mute else args.deaf = not me.self_deaf end
  self.rpc:call('SET_VOICE_SETTINGS', args)
end

-- Leave
-- Disconnects from the current voice channel
function discord:leave()
  self.rpc:call('SELECT_VOICE_CHANNEL', '{"channel_id":null}')
end

-- Click
-- Handles the mute, deafen, and leave header buttons
function discord:click(event, x, y)
  if not self.rpc or y < 7 or y > 33 then return end
  for key, bx in pairs(self.BUTTONS) do
    if bx - 5 <= x and x <= bx + 23 then
      if key == 'leave' then self:leave() else self:toggle(key) end
    end
  end
end

-- Tooltip
-- Returns the full name of the member under the pointer
function discord:tooltip(x, y)
  if y < 50 then return nil end
  local index = math.floor((y - 50) / self.ROW_HEIGHT) * 2 + (x < 105 and 1 or 2)
  local member = self.members[index]
  return member and {member.name} or nil
end

-- Menu
-- Returns right click menu items for the voice controls
function discord:menu()
  if not self.rpc then return {} end
  local me = self:member(self.rpc.user.id) or {}
  return {
    {label=me.self_mute and 'Unmute' or 'Mute', action=function() self:toggle('mute') end},
    {label=me.self_deaf and 'Undeafen' or 'Deafen', action=function() self:toggle('deaf') end},
    {label='Leave channel', action=function() self:leave() end},
  }
end

return discord
