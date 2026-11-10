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
    elseif option == '--days' then options.days = tonumber(value) or 7
    elseif option == '--timeout' then options.timeout = tonumber(value) or 30
    else
      io.stderr:write('Usage: tokenpoll.lua --out PATH [--claude-home PATH] [--codex-home PATH] [--days N] [--timeout SECONDS]\n')
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
