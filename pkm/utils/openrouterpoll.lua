local json = require 'pkm/json'

local openrouterpoll = {}
local CREDITS_URL = 'https://openrouter.ai/api/v1/credits'

-- Is Number
-- Returns true for a finite Lua number that is safe to use in calculations.
local function number(value)
  return type(value) == 'number' and value == value and value > -math.huge and value < math.huge
end

-- Read API Key
-- Reads a KEY=value line from an env file, falling back to the environment variable.
function openrouterpoll.api_key(key_file, key_name)
  local handle = key_file and io.open(key_file, 'r')
  if handle then
    for line in handle:lines() do
      local name, value = line:match('^%s*export%s+([%w_]+)%s*=%s*(.-)%s*$')
      if not name then name, value = line:match('^%s*([%w_]+)%s*=%s*(.-)%s*$') end
      if name == key_name and value ~= '' then
        handle:close()
        return value:match('^"(.*)"$') or value:match("^'(.*)'$") or value
      end
    end
    handle:close()
  end
  local value = os.getenv(key_name)
  return value ~= '' and value or nil
end

-- Read Credits
-- Requests the account's purchased and used credits and returns the remaining balance.
function openrouterpoll.credits(api_key, timeout)
  local ok_https, https = pcall(require, 'ssl.https')
  if not ok_https then return nil, 'LuaSec (ssl.https) is not installed' end
  local ltn12 = require 'ltn12'
  https.TIMEOUT = timeout or 10
  local response = {}
  local result, code = https.request{
    url=CREDITS_URL, sink=ltn12.sink.table(response),
    headers={Authorization='Bearer '..api_key, Accept='application/json'},
  }
  if not result then return nil, 'OpenRouter request failed: '..tostring(code) end
  if tonumber(code) ~= 200 then return nil, 'OpenRouter returned HTTP '..tostring(code) end
  local ok, decoded = pcall(json.decode, table.concat(response))
  local data = ok and type(decoded) == 'table' and decoded.data or nil
  if type(data) ~= 'table' or not number(data.total_credits) or not number(data.total_usage) then
    return nil, 'OpenRouter returned an unexpected response'
  end
  return {updated_at=os.time(), data={
    total_credits=data.total_credits,
    total_usage=data.total_usage,
    remaining=data.total_credits - data.total_usage,
  }}
end

-- Read Cache
-- Reads a previously written poll result without treating a bad cache as fatal.
local function read_cache(path)
  local handle = io.open(path, 'r')
  if not handle then return nil end
  local content = handle:read('*a')
  handle:close()
  local ok, cached = pcall(json.decode, content)
  return ok and type(cached) == 'table' and cached or nil
end

-- Write Cache
-- Atomically replaces the poll result cache after a completed poll attempt.
local function write_cache(path, cached)
  local temporary = path..'.tmp'
  local handle, err = io.open(temporary, 'w')
  if not handle then return nil, err end
  local ok, encoded = pcall(json.encode, cached)
  if ok then handle:write(encoded) end
  handle:close()
  if not ok then os.remove(temporary); return nil, encoded end
  local renamed, rename_error = os.rename(temporary, path)
  if not renamed then os.remove(temporary); return nil, rename_error end
  return true
end

-- Parse Poll Arguments
-- Reads the cache path, key location, and timeout accepted by the standalone poller.
local function parse_poll_arguments(arguments)
  local options = {out='/tmp/pkmeter-openrouter.json', key_name='OPENROUTER_API_KEY', timeout=10}
  local index = 1
  while index <= #arguments do
    local option = arguments[index]
    local value = arguments[index + 1]
    if option == '--out' and value then
      options.out = value
    elseif option == '--key-file' and value then
      options.key_file = value
    elseif option == '--key-name' and value then
      options.key_name = value
    elseif option == '--timeout' and value and tonumber(value) then
      options.timeout = tonumber(value)
    else
      return nil, 'Usage: openrouterpoll.lua --out PATH [--key-file PATH] [--key-name NAME] [--timeout SECONDS]'
    end
    index = index + 2
  end
  return options
end

-- Run Poller
-- Refreshes the credits cache while keeping the last successful balance on errors.
local function run_poller(arguments)
  local options, argument_error = parse_poll_arguments(arguments)
  if not options then io.stderr:write(argument_error..'\n'); return false end
  local cached = read_cache(options.out) or {}
  local api_key = openrouterpoll.api_key(options.key_file, options.key_name)
  local snapshot, refresh_error
  if api_key then
    snapshot, refresh_error = openrouterpoll.credits(api_key, options.timeout)
  else
    refresh_error = 'OpenRouter API key not found'
  end
  cached.checked_at = os.time()
  if snapshot then
    cached.updated_at = snapshot.updated_at
    cached.data = snapshot.data
    cached.error = nil
    cached.failures = 0
  else
    cached.error = tostring(refresh_error)
    cached.failures = (tonumber(cached.failures) or 0) + 1
  end
  local written, write_error = write_cache(options.out, cached)
  if not written then io.stderr:write('Unable to write OpenRouter cache: '..tostring(write_error)..'\n') end
  return written
end

-- Is Standalone
-- Returns true when Lua is executing this module as the background poller script.
local function is_standalone()
  return arg and type(arg[0]) == 'string' and arg[0]:match('pkm/utils/openrouterpoll%.lua$') ~= nil
end

if is_standalone() and not run_poller(arg) then os.exit(1) end

return openrouterpoll
