----------------------------------
-- Discord RPC client
-- Talks to the running Discord app over its local IPC socket. Frames are a
-- little endian opcode and length followed by a JSON body.
----------------------------------
local json = require 'pkm/json'
local socket = require 'socket'
local unix = require 'socket.unix'
local utils = require 'pkm/utils'

local discordrpc = {}
discordrpc.__index = discordrpc
discordrpc.OP_HANDSHAKE = 0
discordrpc.OP_FRAME = 1
discordrpc.OP_CLOSE = 2

-- Socket Paths
-- Returns the IPC socket paths used by the native and Flatpak Discord builds
function discordrpc.socket_paths()
  local runtime = os.getenv('XDG_RUNTIME_DIR') or '/run/user/'..utils.run_command('id -u'):gsub('%s', '')
  local paths = {}
  for i=0, 9 do
    table.insert(paths, runtime..'/discord-ipc-'..i)
    table.insert(paths, runtime..'/app/com.discordapp.Discord/discord-ipc-'..i)
  end
  return paths
end

-- Connect
-- Opens the IPC socket and completes the handshake; returns the client or nil, err
function discordrpc.connect(client_id)
  for _, path in ipairs(discordrpc.socket_paths()) do
    local sock = unix()
    sock:settimeout(2)
    if sock:connect(path) then
      local self = setmetatable({sock=sock, buffer='', queue={}, nonce=0}, discordrpc)
      self:send(discordrpc.OP_HANDSHAKE, json.encode({v=1, client_id=client_id}))
      local msg = self:wait(function(m) return m.evt == 'READY' or m.closed end, 3)
      if msg and msg.evt == 'READY' then
        self.user = msg.data.user
        return self
      end
      self:close()
      return nil, msg and msg.data and msg.data.message or 'handshake failed'
    end
    sock:close()
  end
  return nil, 'Discord is not running'
end

-- Send
-- Writes one frame with the given opcode and JSON body
function discordrpc:send(op, body)
  local ok, err = self.sock:send(string.pack('<I4I4', op, #body)..body)
  if not ok then self.closed = true end
  return ok, err
end

-- Request
-- Sends a command without waiting and returns its nonce. Args may be a table
-- or a JSON string, since pkm/json cannot encode null values.
function discordrpc:request(cmd, args, evt)
  self.nonce = self.nonce + 1
  local nonce = tostring(self.nonce)
  local argstr = type(args) == 'string' and args or json.encode(args or {})
  local evtstr = evt and (',"evt":'..json.encode(evt)) or ''
  self:send(discordrpc.OP_FRAME, '{"cmd":'..json.encode(cmd)..',"args":'..argstr..evtstr..
    ',"nonce":"'..nonce..'"}')
  return nonce
end

-- Call
-- Sends a command and waits for its reply, queueing any events that arrive first
function discordrpc:call(cmd, args, evt, timeout)
  local nonce = self:request(cmd, args, evt)
  local msg = self:wait(function(m) return m.nonce == nonce end, timeout or 3)
  if not msg then return nil, 'no reply to '..cmd end
  if msg.evt == 'ERROR' then return nil, msg.data and msg.data.message or 'error' end
  return msg.data or {}
end

-- Wait
-- Reads frames until match(msg) is true or the timeout passes; others are queued
function discordrpc:wait(match, timeout)
  local deadline = socket.gettime() + timeout
  while not self.closed do
    local messages = self:read()
    for i, msg in ipairs(messages) do
      if match(msg) then
        table.move(messages, i + 1, #messages, #self.queue + 1, self.queue)
        return msg
      end
      table.insert(self.queue, msg)
    end
    local remaining = deadline - socket.gettime()
    if remaining <= 0 then return nil end
    socket.select({self.sock}, nil, remaining)
  end
end

-- Read
-- Reads whatever is available without blocking and returns the decoded messages
function discordrpc:read()
  self.sock:settimeout(0)
  local data, err, partial = self.sock:receive(65536)
  self.buffer = self.buffer..(data or partial or '')
  if err == 'closed' then self.closed = true end
  local messages = {}
  while #self.buffer >= 8 do
    local op, len = string.unpack('<I4I4', self.buffer)
    if #self.buffer < 8 + len then break end
    local body = self.buffer:sub(9, 8 + len)
    self.buffer = self.buffer:sub(9 + len)
    local ok, msg = pcall(json.decode, body)
    if ok and type(msg) == 'table' then
      if op == discordrpc.OP_CLOSE then msg.closed = true; self.closed = true end
      table.insert(messages, msg)
    end
  end
  return messages
end

-- Poll
-- Returns queued and newly arrived messages without blocking
function discordrpc:poll()
  local messages = self.queue
  self.queue = {}
  for _, msg in ipairs(self:read()) do table.insert(messages, msg) end
  return messages
end

-- Close
-- Closes the IPC socket
function discordrpc:close()
  self.closed = true
  if self.sock then self.sock:close() end
end

return discordrpc
