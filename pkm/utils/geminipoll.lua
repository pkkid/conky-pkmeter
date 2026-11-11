local json = require 'pkm/json'

-- WORKAROUND: Gemini limits are read with T3 Code's saved Antigravity login.
-- Claude and Codex limits come from asking their signed in CLIs, so pkmeter never touches a
-- credential for them. The Antigravity CLI (agy) has no usage command yet, so this poller does
-- what T3 Code does (apps/server/src/provider/antigravityUsageLimits.ts): it reads the Google
-- refresh token T3 Code saved in acp_token.json, trades it for a short-lived access token, and
-- asks Google's Cloud Code quota service for the summary. The token is only sent to Google and
-- is never printed, logged, or written anywhere. Replace this with an agy call once agy can
-- report usage itself, and delete the token handling below.
local geminipoll = {}
local TOKEN_URL = 'https://oauth2.googleapis.com/token'
local ENDPOINTS = {'https://daily-cloudcode-pa.googleapis.com', 'https://cloudcode-pa.googleapis.com'}
local USER_AGENT = 'antigravity/hub/2.24.0 (aidev_client; os_type=linux; arch=x64; cl=963137146)'
local WINDOW_SECONDS = {['5h']=18000, weekly=604800}

-- Is Number
-- Returns true for a finite Lua number that is safe to use in calculations.
local function number(value)
  return type(value) == 'number' and value == value and value > -math.huge and value < math.huge
end

-- Parse Timestamp
-- Converts an ISO 8601 UTC timestamp into Unix epoch seconds, rounding fractional seconds.
local function timestamp(value)
  if type(value) ~= 'string' then return nil end
  local year, month, day, hour, minute, second, fraction = value:match(
    '^(%d%d%d%d)%-(%d%d)%-(%d%d)T(%d%d):(%d%d):(%d%d)(%.?%d*)')
  if not year then return nil end
  local interpreted = os.time{year=tonumber(year), month=tonumber(month), day=tonumber(day),
    hour=tonumber(hour), min=tonumber(minute), sec=tonumber(second), isdst=false}
  local utc = os.date('!*t', interpreted)
  utc.isdst = false
  local seconds = interpreted + os.difftime(interpreted, os.time(utc)) + (tonumber('0'..fraction) or 0)
  return math.floor(seconds + 0.5)
end

-- URL Encode
-- Percent-encodes a value for an application/x-www-form-urlencoded body.
local function url_encode(value)
  return (tostring(value):gsub('[^%w%-_%.~]', function(char) return string.format('%%%02X', char:byte()) end))
end

-- Find Token File
-- Returns the configured token file, or the first acp_token.json saved by T3 Code.
function geminipoll.token_file(path)
  if path then return path end
  local home = os.getenv('HOME') or ''
  local handle = io.popen('ls -t '..home..'/.t3/userdata/providers/antigravity/*/antigravity-acp/acp_token.json 2>/dev/null')
  if not handle then return nil end
  local found = handle:read('*l')
  handle:close()
  return found
end

-- Post
-- Sends a POST request and returns the decoded JSON reply, or nil and an error without secrets.
local function post(url, body, headers, timeout)
  local https = require 'ssl.https'
  local ltn12 = require 'ltn12'
  https.TIMEOUT = timeout or 10
  headers['Content-Length'] = tostring(#body)
  local response = {}
  local result, code = https.request{url=url, method='POST', headers=headers,
    source=ltn12.source.string(body), sink=ltn12.sink.table(response)}
  local host = url:match('^https://([^/]+)')
  if not result then return nil, 'Request to '..host..' failed' end
  if tonumber(code) ~= 200 then return nil, host..' returned HTTP '..tostring(code) end
  local ok, decoded = pcall(json.decode, table.concat(response))
  if not ok or type(decoded) ~= 'table' then return nil, host..' returned an unexpected response' end
  return decoded
end

-- Access Token
-- Trades the saved refresh token for a short-lived access token.
local function access_token(token, timeout)
  local body = 'client_id='..url_encode(token.client_id)..'&client_secret='..url_encode(token.client_secret)
    ..'&refresh_token='..url_encode(token.refresh_token)..'&grant_type=refresh_token'
  local reply, err = post(TOKEN_URL, body, {['Content-Type']='application/x-www-form-urlencoded'}, timeout)
  if not reply then return nil, err end
  if type(reply.access_token) ~= 'string' then return nil, 'Google did not return an access token' end
  return reply.access_token
end

-- Bucket Family
-- Groups a quota bucket like T3 Code: default Gemini, Gemini Argon, or the shared Claude and GPT pool.
local function bucket_family(bucket, group)
  local id = bucket.bucketId
  if id:find('^gemini%-argon%-') then
    return 'argon', type(group.displayName) == 'string' and group.displayName or 'Gemini Argon'
  end
  if id:find('^gemini%-') then return 'gemini', 'Gemini' end
  if id:find('^3p%-') then return 'shared', 'Claude & GPT' end
  return 'other', type(group.displayName) == 'string' and group.displayName or id
end

-- Summary Buckets
-- Flattens one quota summary into usable buckets keyed by id, keeping the most used reading.
local function summary_buckets(summary, requested_at, buckets)
  local groups = {}
  for _, group in ipairs(type(summary.groups) == 'table' and summary.groups or {}) do
    if type(group) == 'table' and type(group.buckets) == 'table' and #group.buckets > 0 then
      table.insert(groups, group)
    end
  end
  if #groups == 0 then groups = {{buckets=summary.buckets}} end
  for _, group in ipairs(groups) do
    for _, bucket in ipairs(type(group.buckets) == 'table' and group.buckets or {}) do
      if type(bucket) == 'table' and type(bucket.bucketId) == 'string' and not bucket.disabled
          and number(bucket.remainingFraction) then
        local duration = WINDOW_SECONDS[bucket.window]
        local resets_at = timestamp(bucket.resetTime)
        -- Untouched buckets report a rolling full window reset, so they have no real reset time
        if bucket.remainingFraction == 1 and bucket.description == nil and duration and resets_at
            and math.abs(resets_at - requested_at - duration) <= 60 then
          resets_at = nil
        end
        local family, name = bucket_family(bucket, group)
        local used = (1 - math.max(0, math.min(1, bucket.remainingFraction))) * 100
        local previous = buckets[bucket.bucketId]
        if not previous or used > previous.used_percent then
          buckets[bucket.bucketId] = {family=family, name=name, window=bucket.window,
            used_percent=used, duration_seconds=duration, resets_at=resets_at}
        end
      end
    end
  end
end

-- Read Cloud Limits
-- Reads the Gemini five-hour and weekly limits, plus other weekly pools for the tooltip.
function geminipoll.cloud_limits(token_path, timeout)
  local path = geminipoll.token_file(token_path)
  local handle = path and io.open(path, 'r')
  if not handle then return nil, 'Sign in to Antigravity in T3 Code to see Gemini limits' end
  local ok, token = pcall(json.decode, handle:read('*a'))
  handle:close()
  if not ok or type(token) ~= 'table' or type(token.refresh_token) ~= 'string' then
    return nil, 'T3 Code Antigravity login could not be read'
  end
  local ok_https = pcall(require, 'ssl.https')
  if not ok_https then return nil, 'LuaSec (ssl.https) is not installed' end
  local access, token_error = access_token(token, timeout)
  if not access then return nil, token_error end
  local body = json.encode(type(token.project_id) == 'string' and {project=token.project_id} or {})
  if body == '[]' then body = '{}' end
  local headers = {Authorization='Bearer '..access, ['Content-Type']='application/json', ['User-Agent']=USER_AGENT}
  local buckets, last_error = {}, nil
  for _, endpoint in ipairs(ENDPOINTS) do
    local requested_at = os.time()
    local summary, err = post(endpoint..'/v1internal:retrieveUserQuotaSummary', body, headers, timeout)
    if summary then summary_buckets(summary, requested_at, buckets) else last_error = err end
  end
  local windows, others = {}, {}
  for _, bucket in pairs(buckets) do
    local slot = bucket.window == '5h' and 'five_hour' or bucket.window == 'weekly' and 'weekly'
    if bucket.family == 'gemini' and slot then
      if not windows[slot] or bucket.used_percent > windows[slot].used_percent then
        windows[slot] = {used_percent=bucket.used_percent, duration_seconds=bucket.duration_seconds,
          resets_at=bucket.resets_at}
      end
    elseif bucket.window == 'weekly' then
      table.insert(others, {name=bucket.name, used_percent=bucket.used_percent, resets_at=bucket.resets_at})
    end
  end
  if not next(windows) and #others == 0 then
    return nil, last_error or 'Google did not return Gemini quota information'
  end
  table.sort(others, function(left, right) return left.name < right.name end)
  return {updated_at=os.time(), data={windows=windows, model_limits=others}}
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
  handle:write(json.encode(cached))
  handle:close()
  return os.rename(temporary, path)
end

-- Run Poller
-- Refreshes the limits cache while keeping the last successful snapshot on errors.
local function run_poller(arguments)
  local options = {out='/tmp/pkmeter-gemini.json', timeout=10}
  for index=1,#arguments,2 do
    local option, value = arguments[index], arguments[index + 1]
    if option == '--out' and value then options.out = value
    elseif option == '--token-file' and value then options.token_file = value
    elseif option == '--timeout' and tonumber(value) then options.timeout = tonumber(value)
    else
      io.stderr:write('Usage: geminipoll.lua --out PATH [--token-file PATH] [--timeout SECONDS]\n')
      return false
    end
  end
  local cached = read_cache(options.out) or {}
  local ok, snapshot, refresh_error = pcall(geminipoll.cloud_limits, options.token_file, options.timeout)
  if not ok then snapshot, refresh_error = nil, 'Gemini usage refresh failed' end
  cached.checked_at = os.time()
  if snapshot then
    cached.updated_at = snapshot.updated_at
    cached.data = snapshot.data
    cached.error = nil
    cached.failures = 0
  else
    cached.error = tostring(refresh_error or 'Gemini usage refresh failed')
    cached.failures = (tonumber(cached.failures) or 0) + 1
  end
  local written, write_error = write_cache(options.out, cached)
  if not written then io.stderr:write('Unable to write Gemini cache: '..tostring(write_error)..'\n') end
  return written
end

-- Is Standalone
-- Returns true when Lua is executing this module as the background poller script.
local function is_standalone()
  return arg and type(arg[0]) == 'string' and arg[0]:match('pkm/utils/geminipoll%.lua$') ~= nil
end

if is_standalone() and not run_poller(arg) then os.exit(1) end

return geminipoll
