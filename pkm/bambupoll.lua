#!/usr/bin/env lua
-- Bambu Labs printer — one-shot MQTT poller (pure Lua, no external deps
-- beyond LuaSocket + LuaSec, which the pkmeter Lua widgets already use).
--
-- Connects to the printer's local MQTT broker over TLS, requests a full
-- status snapshot ("pushall"), collects any reports for ~3 seconds, and
-- writes them as JSON to the given output path (atomic rename).
--
-- Usage:
--   lua pkm/bambupoll.lua --host IP --serial SN --code ACCESS_CODE \
--       [--out /tmp/bambu_status.json] [--duration 3]
--
-- Exit code:
--   0 on success (JSON written)
--   non-zero on any failure (an error JSON is still written to --out)
--
-- Intended to be spawned in the background from the Conky widget every
-- ~30 seconds. Blocking for the whole duration is fine because we are
-- not the Conky process.

local socket = require 'socket'
local ssl = require 'ssl'

-- Make pkm/json.lua importable regardless of cwd.
local script_dir = (arg[0] or ''):match('(.*/)') or './'
package.path = script_dir .. '../?.lua;' .. package.path
local json = require 'pkm.json'


-- ---------------------------------------------------------------------
-- Args
-- ---------------------------------------------------------------------
-- Parse Args
-- Parses command-line options and falls back to Bambu environment variables.
local function parse_args()
  local opts = {
    host=nil, port=8883, serial=nil, code=nil,
    out='/tmp/bambu_status.json',
    thumb_out=nil,
    duration=3.0,
    verbose=false,
  }
  local i = 1
  while i <= #arg do
    local a = arg[i]
    if a == '--host' then opts.host = arg[i+1]; i = i + 2
    elseif a == '--port' then opts.port = tonumber(arg[i+1]); i = i + 2
    elseif a == '--serial' then opts.serial = arg[i+1]; i = i + 2
    elseif a == '--code' then opts.code = arg[i+1]; i = i + 2
    elseif a == '--out' then opts.out = arg[i+1]; i = i + 2
    elseif a == '--thumb-out' then opts.thumb_out = arg[i+1]; i = i + 2
    elseif a == '--duration' then opts.duration = tonumber(arg[i+1]); i = i + 2
    elseif a == '--verbose' or a == '-v' then opts.verbose = true; i = i + 1
    elseif a == '-h' or a == '--help' then
      io.write('Usage: lua pkm/bambupoll.lua --host IP --serial SN --code CODE ',
               '[--out PATH] [--thumb-out PATH] [--duration SEC] [--verbose]\n')
      os.exit(0)
    else
      io.stderr:write('unknown arg: '..a..'\n'); os.exit(2)
    end
  end
  opts.host = opts.host or os.getenv('BAMBU_HOST')
  opts.serial = opts.serial or os.getenv('BAMBU_SERIAL')
  opts.code = opts.code or os.getenv('BAMBU_CODE')
  for _, name in ipairs({'host','serial','code'}) do
    if not opts[name] then
      io.stderr:write('missing --'..name..' (or BAMBU_'..name:upper()..')\n')
      os.exit(2)
    end
  end
  return opts
end


-- ---------------------------------------------------------------------
-- MQTT 3.1.1 wire format helpers
-- ---------------------------------------------------------------------
-- Encode Unsigned 16-Bit Integer
-- Encodes an integer as two network-order bytes.
local function u16(n)
  return string.char((n >> 8) & 0xFF, n & 0xFF)
end

-- Encode MQTT String
-- Prefixes a string with its two-byte MQTT length.
local function mqtt_string(s)
  return u16(#s) .. s
end

-- Encode Variable Integer
-- Encodes an MQTT remaining length as a one-to-four-byte variable integer.
local function encode_varint(n)
  local out = {}
  repeat
    local b = n & 0x7F
    n = n >> 7
    if n > 0 then b = b | 0x80 end
    out[#out+1] = string.char(b)
  until n == 0
  return table.concat(out)
end

-- Read Variable Integer
-- Reads an MQTT remaining length from a socket one byte at a time.
local function read_varint(sock)
  local value = 0
  local mult = 1
  for _ = 1, 4 do
    local chunk, err = sock:receive(1)
    if not chunk then return nil, err end
    local b = string.byte(chunk)
    value = value + (b & 0x7F) * mult
    if (b & 0x80) == 0 then return value end
    mult = mult * 128
  end
  return nil, 'varint too long'
end


-- ---------------------------------------------------------------------
-- Packet builders
-- ---------------------------------------------------------------------
-- Build Connect Packet
-- Builds an MQTT CONNECT packet with credentials, a clean session, and a 60-second keepalive.
local function build_connect(client_id, username, password)
  local variable_header = mqtt_string('MQTT')
    .. string.char(0x04)   -- Protocol Level 4 (MQTT 3.1.1)
    .. string.char(0xC2)   -- Flags: Username | Password | CleanSession
    .. u16(60)             -- Keep Alive seconds
  local payload = mqtt_string(client_id)
    .. mqtt_string(username)
    .. mqtt_string(password)
  local body = variable_header .. payload
  return string.char(0x10) .. encode_varint(#body) .. body
end

-- Build Subscribe Packet
-- Builds an MQTT SUBSCRIBE packet for one QoS 0 topic filter.
local function build_subscribe(packet_id, topic)
  local body = u16(packet_id) .. mqtt_string(topic) .. string.char(0)
  return string.char(0x82) .. encode_varint(#body) .. body
end

-- Build Publish Packet
-- Builds an MQTT QoS 0 PUBLISH packet for a topic and payload.
local function build_publish(topic, payload)
  local body = mqtt_string(topic) .. payload
  return string.char(0x30) .. encode_varint(#body) .. body
end

-- Build Disconnect Packet
-- Builds an MQTT DISCONNECT packet.
local function build_disconnect()
  return string.char(0xE0, 0x00)
end


-- ---------------------------------------------------------------------
-- Packet reader
-- ---------------------------------------------------------------------
-- Read Packet
-- Reads and decodes one MQTT packet header and body from an SSL socket.
local function read_packet(sock)
  local head, err = sock:receive(1)
  if not head then return nil, err end
  local b1 = string.byte(head)
  local remaining, verr = read_varint(sock)
  if not remaining then return nil, verr end
  local body = ''
  if remaining > 0 then
    body, err = sock:receive(remaining)
    if not body then return nil, err end
  end
  return { type=(b1 >> 4) & 0x0F, flags=b1 & 0x0F, body=body }
end


-- ---------------------------------------------------------------------
-- Connection
-- ---------------------------------------------------------------------
-- Connect TLS
-- Opens a TCP connection and wraps it in an unverified local TLS session.
local function connect_tls(host, port, timeout)
  local sock, err = socket.tcp()
  if not sock then return nil, err end
  sock:settimeout(timeout)
  local ok, cerr = sock:connect(host, port)
  if not ok then sock:close(); return nil, cerr end
  local params = {
    mode = 'client',
    protocol = 'any',
    verify = 'none',
    options = 'all',
  }
  local ssock, werr = ssl.wrap(sock, params)
  if not ssock then sock:close(); return nil, werr end
  ssock:settimeout(timeout)
  local hok, herr = ssock:dohandshake()
  if not hok then ssock:close(); return nil, herr end
  return ssock
end


-- ---------------------------------------------------------------------
-- Body parsers
-- ---------------------------------------------------------------------
-- Parse Publish Packet
-- Extracts the topic and payload from an MQTT PUBLISH packet body.
local function parse_publish(pkt)
  local body = pkt.body
  if #body < 2 then return nil, 'publish body too short' end
  local topic_len = (string.byte(body, 1) << 8) | string.byte(body, 2)
  if #body < 2 + topic_len then return nil, 'publish topic runs past body' end
  local topic = body:sub(3, 2 + topic_len)
  local rest_start = 3 + topic_len
  local qos = (pkt.flags >> 1) & 0x03
  if qos > 0 then rest_start = rest_start + 2 end
  return topic, body:sub(rest_start)
end


-- ---------------------------------------------------------------------
-- Output
-- ---------------------------------------------------------------------
-- Merge Print State
-- Copies fields from a partial printer report into the accumulated state.
local function merge_print(acc, delta)
  if type(delta) ~= 'table' then return end
  for k, v in pairs(delta) do
    acc[k] = v
  end
end

-- Write Atomic
-- Writes content to a temporary file and atomically renames it into place.
local function write_atomic(path, content)
  local tmp = path .. '.tmp'
  local fh, err = io.open(tmp, 'wb')
  if not fh then return nil, err end
  fh:write(content)
  fh:close()
  local ok, rerr = os.rename(tmp, path)
  if not ok then return nil, rerr end
  return true
end

-- Write Result
-- Serializes a timestamped poll result and writes it atomically as JSON.
local function write_result(path, ok, print_state, extra)
  local out = {
    ok = ok,
    timestamp = os.time(),
    ['print'] = print_state,
  }
  if extra then
    for k, v in pairs(extra) do out[k] = v end
  end
  local encoded = json.encode(out)
  write_atomic(path, encoded)
end


-- ---------------------------------------------------------------------
-- Thumbnail (FTPS to printer, extract Metadata/plate_1_small.png from
-- the current .gcode.3mf, cache to disk).
-- ---------------------------------------------------------------------
-- URL Encode
-- Percent-encodes a string for use in an FTPS URL path.
local function urlencode(s)
  return (s:gsub('[^%w%-_%.~]', function(c)
    return string.format('%%%02X', string.byte(c))
  end))
end

-- File Exists
-- Returns true when a path can be opened for reading.
local function file_exists(path)
  local fh = io.open(path, 'r')
  if fh then fh:close(); return true end
  return false
end

-- Read File
-- Reads and returns an entire text file, or nil when it cannot be opened.
local function read_file(path)
  local fh = io.open(path, 'r')
  if not fh then return nil end
  local content = fh:read('*a')
  fh:close()
  return content
end

-- Fetch Thumbnail
-- Downloads and caches the current plate thumbnail when the print name changes.
local function fetch_thumbnail(host, code, subtask_name, out_path, log)
  if not subtask_name or subtask_name == '' then
    log('no subtask_name; skipping thumbnail')
    return
  end
  local marker = out_path .. '.marker'
  if file_exists(out_path) and read_file(marker) == subtask_name then
    log('thumbnail already cached for "'..subtask_name..'"')
    return
  end

  local tmp_3mf = out_path .. '.3mf.tmp'
  local tmp_png = out_path .. '.tmp'
  local url = string.format('ftps://%s:990/%s.gcode.3mf',
    host, urlencode(subtask_name))

  local dl = string.format(
    'curl --ftp-ssl --insecure --ftp-pasv -k -s --connect-timeout 5 ' ..
    '--user %q %q -o %q',
    'bblp:'..code, url, tmp_3mf)
  local ok, _, rc = os.execute(dl)
  if not ok or (rc and rc ~= 0) then
    log('curl failed (rc='..tostring(rc)..') for '..url)
    os.remove(tmp_3mf)
    return
  end

  -- Prefer the smaller preview when present; fall back to plate_1.png.
  local extract = string.format(
    '(unzip -p %q Metadata/plate_1_small.png 2>/dev/null || ' ..
    'unzip -p %q Metadata/plate_1.png 2>/dev/null) > %q',
    tmp_3mf, tmp_3mf, tmp_png)
  os.execute(extract)
  os.remove(tmp_3mf)

  local size = 0
  local fh = io.open(tmp_png, 'r')
  if fh then size = fh:seek('end') or 0; fh:close() end
  if size == 0 then
    log('no thumbnail found in 3mf')
    os.remove(tmp_png)
    return
  end

  os.rename(tmp_png, out_path)
  -- Marker written last so the sidecar only reflects a fully-cached image.
  local mfh = io.open(marker, 'w')
  if mfh then mfh:write(subtask_name); mfh:close() end
  log(string.format('cached thumbnail (%d bytes) for "%s"', size, subtask_name))
end


-- ---------------------------------------------------------------------
-- Main
-- ---------------------------------------------------------------------
-- Main
-- Connects to the printer, collects its status, writes the result, and fetches its thumbnail.
local function main()
  local opts = parse_args()
  local report_topic = 'device/'..opts.serial..'/report'
  local request_topic = 'device/'..opts.serial..'/request'

  -- Log
  -- Writes a poller message to stderr when verbose output is enabled.
  local function log(msg)
    if opts.verbose then io.stderr:write('[bambu_poll] '..msg..'\n') end
  end

  local sock, err = connect_tls(opts.host, opts.port, 5)
  if not sock then
    io.stderr:write('connect failed: '..tostring(err)..'\n')
    write_result(opts.out, false, nil, {error='connect: '..tostring(err)})
    os.exit(1)
  end
  log('TLS handshake OK')

  -- CONNECT
  local client_id = 'conkypkm-'..tostring(socket.gettime()):gsub('%.','')
  local pkt = build_connect(client_id, 'bblp', opts.code)
  local sent, serr = sock:send(pkt)
  if not sent then
    io.stderr:write('CONNECT send failed: '..tostring(serr)..'\n')
    write_result(opts.out, false, nil, {error='send connect: '..tostring(serr)})
    os.exit(1)
  end
  local connack, cerr = read_packet(sock)
  if not connack or connack.type ~= 2 then
    io.stderr:write('CONNACK missing: '..tostring(cerr)..'\n')
    write_result(opts.out, false, nil, {error='connack: '..tostring(cerr)})
    os.exit(1)
  end
  local rc = string.byte(connack.body, 2) or 0xFF
  if rc ~= 0 then
    io.stderr:write('CONNACK rc='..rc..' (bad user/pass or not authorized)\n')
    write_result(opts.out, false, nil, {error='connack rc='..rc})
    os.exit(1)
  end
  log('CONNACK OK')

  -- SUBSCRIBE
  sock:send(build_subscribe(1, report_topic))
  local suback, sberr = read_packet(sock)
  if not suback or suback.type ~= 9 then
    io.stderr:write('SUBACK missing: '..tostring(sberr)..'\n')
    write_result(opts.out, false, nil, {error='suback'})
    os.exit(1)
  end
  log('SUBACK OK')

  -- Ask for full state
  local pushall = '{"pushing":{"sequence_id":"0","command":"pushall"}}'
  sock:send(build_publish(request_topic, pushall))
  log('pushall requested')

  -- Collect messages until deadline
  local print_state = {}
  local deadline = socket.gettime() + opts.duration
  local received = 0
  while socket.gettime() < deadline do
    local remaining = deadline - socket.gettime()
    sock:settimeout(math.max(0.05, math.min(remaining, 2.0)))
    local msg, rerr = read_packet(sock)
    if msg then
      if msg.type == 3 then -- PUBLISH
        local topic, payload = parse_publish(msg)
        if topic == report_topic and payload then
          received = received + 1
          local ok, decoded = pcall(json.decode, payload)
          if ok and type(decoded) == 'table' and type(decoded['print']) == 'table' then
            merge_print(print_state, decoded['print'])
          else
            log('non-print payload or decode failure')
          end
        end
      end
      -- ignore PINGRESP/others
    else
      if rerr == 'timeout' or rerr == 'wantread' then
        -- retry until deadline
      else
        log('read error: '..tostring(rerr))
        break
      end
    end
  end

  -- Politely disconnect
  pcall(function() sock:send(build_disconnect()); sock:close() end)

  if received == 0 or next(print_state) == nil then
    write_result(opts.out, false, nil,
      {error='no report received in '..opts.duration..'s'})
    io.stderr:write('no report received\n')
    os.exit(1)
  end

  write_result(opts.out, true, print_state)
  log(string.format('wrote %s (%d messages merged)', opts.out, received))

  if opts.thumb_out then
    fetch_thumbnail(opts.host, opts.code, print_state.subtask_name,
      opts.thumb_out, log)
  end
end

main()
