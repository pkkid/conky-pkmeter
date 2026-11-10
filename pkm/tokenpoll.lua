local json = require 'pkm/json'
local socket = require 'socket'

local tokenpoll = {}
local HOUR = 3600

-- Shell Quote
-- Quotes a value for safe use as one POSIX shell argument.
local function shell_quote(value)
  return "'"..tostring(value):gsub("'", "'\\''").."'"
end

-- Hour Start
-- Converts the hour of an ISO 8601 UTC timestamp into its Unix epoch start, memoized per hour.
local hour_cache = {}
local function hour_start(value)
  local key = value and value:sub(1, 13)
  if not key or #key < 13 then return nil end
  if hour_cache[key] == nil then
    local year, month, day, hour = key:match('^(%d%d%d%d)%-(%d%d)%-(%d%d)T(%d%d)$')
    if not year then hour_cache[key] = false; return nil end
    local interpreted = os.time{year=tonumber(year), month=tonumber(month), day=tonumber(day),
      hour=tonumber(hour), min=0, sec=0, isdst=false}
    local utc = os.date('!*t', interpreted)
    utc.isdst = false
    hour_cache[key] = math.floor(interpreted + os.difftime(interpreted, os.time(utc)))
  end
  return hour_cache[key] or nil
end

-- List Recent Files
-- Finds JSONL transcripts under the given directories modified since a time.
local function recent_files(directories, since)
  local quoted = {}
  for _, directory in ipairs(directories) do table.insert(quoted, shell_quote(directory)) end
  local minutes = math.max(1, math.ceil((os.time() - since) / 60))
  local handle = io.popen('find '..table.concat(quoted, ' ')..' -type f -name "*.jsonl" -mmin -'
    ..minutes.." -printf '%s|%p\\n' 2>/dev/null")
  if not handle then return {} end
  local files = {}
  for line in handle:lines() do
    local size, path = line:match('^(%d+)|(.*)$')
    if size then table.insert(files, {size=tonumber(size), path=path}) end
  end
  handle:close()
  return files
end

-- Claude Line Tokens
-- Returns the hour, tokens, and dedupe key of a Claude Code assistant row, or nil.
local function claude_line(line)
  if not line:find('"type":"assistant"', 1, true) then return nil end
  local usage = line:match('"usage":(%b{})')
  if not usage then return nil end
  usage = usage:gsub('"iterations":%b[]', '')
  local tokens = 0
  for _, field in ipairs({'input_tokens', 'output_tokens', 'cache_creation_input_tokens',
      'cache_read_input_tokens'}) do
    tokens = tokens + (tonumber(usage:match('"'..field..'":(%d+)')) or 0)
  end
  local stamp
  for value in line:gmatch('"timestamp":"([^"]+)"') do stamp = value end
  local key = (line:match('"id":"(msg_[^"]+)"') or '')..':'..(line:match('"requestId":"([^"]+)"') or '')
  return hour_start(stamp), tokens, key ~= ':' and key or nil
end

-- Codex Line Tokens
-- Returns the hour and cumulative session total of a Codex token_count row, or nil.
local function codex_line(line)
  if not line:find('"type":"token_count"', 1, true) then return nil end
  local total = line:match('"total_token_usage":(%b{})')
  local last = line:match('"last_token_usage":(%b{})')
  total = total and tonumber(total:match('"total_tokens":(%d+)'))
  last = last and tonumber(last:match('"total_tokens":(%d+)'))
  if not total then return nil end
  return hour_start(line:match('"timestamp":"([^"]+)"')), total, last
end

-- Add Tokens
-- Adds tokens to a service's hourly bucket when the hour is inside the history span.
local function add_tokens(buckets, hour, tokens, since)
  if not hour or not tokens or tokens <= 0 or hour < since then return end
  local key = tostring(hour)
  buckets[key] = (buckets[key] or 0) + tokens
end

-- Scan File
-- Reads complete lines appended to a transcript since the last scan and buckets their tokens.
local function scan_file(service, file, state, buckets, since, deadline)
  if file.size < (state.offset or 0) then state.offset, state.key, state.total = 0, nil, nil end
  if file.size == (state.offset or 0) then return true end
  local handle = io.open(file.path, 'rb')
  if not handle then return true end
  handle:seek('set', state.offset or 0)
  local offset = state.offset or 0
  local seen = {}
  local complete = true
  while true do
    local line = handle:read('L')
    if not line or line:sub(-1) ~= '\n' then break end
    offset = offset + #line
    if service == 'claude' then
      local hour, tokens, key = claude_line(line)
      if hour and not (key and (seen[key] or key == state.key)) then
        if key then seen[key] = true; state.key = key end
        add_tokens(buckets, hour, tokens, since)
      end
    else
      local hour, total, last = codex_line(line)
      if total then
        local delta = state.total and total >= state.total and total - state.total or last
        state.total = total
        add_tokens(buckets, hour, delta, since)
      end
    end
    if socket.gettime() > deadline then complete = false; break end
  end
  handle:close()
  state.offset = offset
  return complete
end

-- Protobuf Fields
-- Decodes one protobuf message into a table of field number to a list of integer or byte string values.
local function protobuf(bytes)
  local fields, offset, length = {}, 1, #bytes
  local function varint()
    local value, shift = 0, 0
    while offset <= length and shift < 64 do
      local byte = bytes:byte(offset)
      offset = offset + 1
      value = value | ((byte & 127) << shift)
      if byte < 128 then return value end
      shift = shift + 7
    end
    error('Invalid protobuf varint')
  end
  while offset <= length do
    local tag = varint()
    local number, wire = tag >> 3, tag & 7
    local value
    if wire == 0 then
      value = varint()
    elseif wire == 2 then
      local size = varint()
      if size < 0 or offset + size - 1 > length then error('Truncated protobuf field') end
      value = bytes:sub(offset, offset + size - 1)
      offset = offset + size
    elseif wire == 1 or wire == 5 then
      offset = offset + (wire == 1 and 8 or 4)
    else
      error('Unsupported protobuf wire type')
    end
    if value ~= nil then
      fields[number] = fields[number] or {}
      table.insert(fields[number], value)
    end
  end
  return fields
end

-- Protobuf Number
-- Returns the first integer value of a decoded protobuf field, or zero.
local function pb_number(fields, key)
  local value = fields[key] and fields[key][1]
  return math.type(value) == 'integer' and value or 0
end

-- Protobuf Bytes
-- Returns the first byte string value of a decoded protobuf field, or nil.
local function pb_bytes(fields, key)
  local value = fields[key] and fields[key][1]
  return type(value) == 'string' and value or nil
end

-- Protobuf Nested
-- Decodes the first byte string value of a protobuf field as a nested message.
local function pb_nested(fields, key)
  local value = pb_bytes(fields, key)
  return value and protobuf(value) or {}
end

-- Antigravity Usages
-- Returns the token usage messages and timestamp of one generation or step metadata blob,
-- following the field layout in T3 Code's antigravityUsageReader.ts.
local function antigravity_usages(blob, step)
  local root = protobuf(blob)
  local data = step and root or pb_nested(root, 1)
  local usages = {}
  local usage = pb_bytes(data, step and 9 or 4)
  if usage then table.insert(usages, protobuf(usage)) end
  for _, retry in ipairs(data[step and 28 or 17] or {}) do
    if type(retry) == 'string' then
      local retry_usage = pb_bytes(protobuf(retry), 2)
      if retry_usage then table.insert(usages, protobuf(retry_usage)) end
    end
  end
  local stamp = step and (pb_number(pb_nested(data, 8), 1) > 0 and pb_nested(data, 8) or pb_nested(data, 1))
    or pb_nested(pb_nested(data, 9), 4)
  local seconds = pb_number(stamp, 1)
  return usages, seconds > 0 and seconds or nil
end

-- Antigravity Database Tokens
-- Totals the tokens in one Antigravity conversation database into hourly buckets. Steps and
-- generations repeat the same usage, so readings sharing an id count once at their largest.
local function antigravity_database(path, fallback_time, since)
  local query = "SELECT 't', hex(data) FROM trajectory_metadata_blob;"
    .."SELECT 'g', hex(data) FROM gen_metadata;"
    .."SELECT 's', hex(metadata) FROM steps WHERE metadata IS NOT NULL;"
  local handle = io.popen('sqlite3 -readonly -separator "|" -cmd ".timeout 200" '
    ..shell_quote(path)..' '..shell_quote(query)..' 2>/dev/null')
  if not handle then return nil end
  local readings, order, default_time = {}, {}, fallback_time
  for line in handle:lines() do
    local kind, hex = line:match('^(%a)|(%x*)$')
    if kind and #hex > 0 then
      local blob = hex:gsub('%x%x', function(pair) return string.char(tonumber(pair, 16)) end)
      local ok, usages, seconds = pcall(function()
        if kind == 't' then return {}, pb_number(pb_nested(protobuf(blob), 2), 1) end
        return antigravity_usages(blob, kind == 's')
      end)
      if ok and kind == 't' and seconds and seconds > 0 and default_time == fallback_time then
        default_time = seconds
      elseif ok then
        for index, usage in ipairs(usages) do
          local output = math.max(pb_number(usage, 3), pb_number(usage, 9) + pb_number(usage, 10))
          local tokens = pb_number(usage, 2) + pb_number(usage, 5) + pb_number(usage, 4) + output
          if tokens > 0 then
            local key = pb_bytes(usage, 11) or pb_bytes(usage, 12) or pb_bytes(usage, 7)
              or (kind..#order..':'..index)
            local reading = readings[key]
            if not reading then
              reading = {tokens=0}
              readings[key] = reading
              table.insert(order, reading)
            end
            reading.tokens = math.max(reading.tokens, tokens)
            reading.time = reading.time or seconds
          end
        end
      end
    end
  end
  handle:close()
  local buckets = {}
  for _, reading in ipairs(order) do
    local time = reading.time or default_time
    add_tokens(buckets, time - time % HOUR, reading.tokens, since)
  end
  return buckets
end

-- Scan Antigravity
-- Rereads Antigravity conversation databases that changed since the last scan, from both the
-- agy CLI and T3 Code's Antigravity profile, and sums their hourly tokens.
local function scan_antigravity(entry, since)
  local home = os.getenv('HOME') or ''
  local minutes = math.max(1, math.ceil((os.time() - since) / 60))
  local handle = io.popen('find '..shell_quote(home..'/.gemini')..' '
    ..shell_quote(home..'/.t3/userdata/providers/antigravity')
    .." -path '*/conversations/*' \\( -name '*.db' -o -name '*.db-wal' \\) -mmin -"..minutes
    .." -printf '%T@|%s|%p\\n' 2>/dev/null")
  if not handle then return entry end
  local stamps = {}
  for line in handle:lines() do
    local modified, size, file = line:match('^([%d%.]+)|(%d+)|(.*)$')
    if file then
      local database = file:gsub('%-wal$', '')
      stamps[database] = (stamps[database] or '')..modified..':'..size..';'
      stamps[database..'@time'] = math.max(stamps[database..'@time'] or 0, math.floor(tonumber(modified)))
    end
  end
  handle:close()
  local files, buckets = {}, {}
  for database, stamp in pairs(stamps) do
    if not database:find('@time$') then
      local state = (entry.files or {})[database]
      if not state or state.stamp ~= stamp then
        local scanned = antigravity_database(database, stamps[database..'@time'], since)
        state = scanned and {stamp=stamp, buckets=scanned} or state
      end
      if state then
        files[database] = state
        for key, tokens in pairs(state.buckets or {}) do
          if tonumber(key) >= since - HOUR then buckets[key] = (buckets[key] or 0) + tokens end
        end
      end
    end
  end
  return {buckets=buckets, files=files}
end

-- Scan Tokens
-- Updates the cached hourly token totals with transcript lines written since the last scan.
function tokenpoll.scan(cached, homes, days, timeout)
  local now = os.time()
  local since = now - days * 86400
  local deadline = socket.gettime() + (timeout or 30)
  local sources = {
    claude = homes.claude and {homes.claude..'/projects'},
    codex = homes.codex and {homes.codex..'/sessions', homes.codex..'/archived_sessions'},
  }
  -- Lines already read were only counted inside the old span, so a longer span starts over
  if (tonumber(cached.days) or 0) < days then cached.services = nil end
  cached.days = days
  cached.services = cached.services or {}
  local complete = true
  for service, directories in pairs(sources) do
    local entry = cached.services[service] or {}
    local buckets, files, states = {}, {}, entry.files or {}
    for key, tokens in pairs(entry.buckets or {}) do
      if tonumber(key) >= since - HOUR then buckets[key] = tokens end
    end
    for _, file in ipairs(recent_files(directories, since)) do
      local state = states[file.path] or {}
      files[file.path] = state
      if complete and not scan_file(service, file, state, buckets, since, deadline) then
        complete = false
      end
    end
    cached.services[service] = {buckets=buckets, files=files}
  end
  if homes.antigravity then
    cached.services.gemini = scan_antigravity(cached.services.gemini or {}, since)
  end
  cached.complete = complete
  return cached
end

-- Read Cache
-- Reads a previously written scan result without treating a bad cache as fatal.
local function read_cache(path)
  local handle = io.open(path, 'r')
  if not handle then return nil end
  local content = handle:read('*a')
  handle:close()
  local ok, cached = pcall(json.decode, content)
  return ok and type(cached) == 'table' and cached or nil
end

-- Write Cache
-- Atomically replaces the scan result cache.
local function write_cache(path, cached)
  local temporary = path..'.tmp'
  local handle, err = io.open(temporary, 'w')
  if not handle then return nil, err end
  handle:write(json.encode(cached))
  handle:close()
  return os.rename(temporary, path)
end

-- Run Poller
-- Parses the command line, scans new transcript lines, and saves the hourly totals.
local function run_poller(arguments)
  local options = {out='/tmp/pkmeter-tokens.json', days=7, timeout=30, homes={}}
  for index=1,#arguments,2 do
    local option, value = arguments[index], arguments[index + 1]
    if option == '--out' then options.out = value
    elseif option == '--claude-home' then options.homes.claude = value
    elseif option == '--codex-home' then options.homes.codex = value
    elseif option == '--antigravity' then options.homes.antigravity = value == 'yes'
    elseif option == '--days' then options.days = tonumber(value) or 7
    elseif option == '--timeout' then options.timeout = tonumber(value) or 30
    else
      io.stderr:write('Usage: tokenpoll.lua --out PATH [--claude-home PATH] [--codex-home PATH] [--antigravity yes] [--days N] [--timeout SECONDS]\n')
      return false
    end
  end
  local cached = tokenpoll.scan(read_cache(options.out) or {}, options.homes, options.days, options.timeout)
  cached.checked_at = os.time()
  local written, err = write_cache(options.out, cached)
  if not written then io.stderr:write('Unable to write token cache: '..tostring(err)..'\n') end
  return written
end

-- Is Standalone
-- Returns true when Lua is executing this module as the background poller script.
local function is_standalone()
  return arg and type(arg[0]) == 'string' and arg[0]:match('pkm/tokenpoll%.lua$') ~= nil
end

if is_standalone() and not run_poller(arg) then os.exit(1) end

return tokenpoll
