local json = require 'pkm/json'
local socket = require 'socket'

local codexpoll = {}
local STATUS_STALE_SECONDS = 900
local TASK_STATES = {task_started='running', task_complete='idle'}

-- Shell Quote
-- Quotes a value for safe use as one POSIX shell argument.
local function shell_quote(value)
  return "'"..tostring(value):gsub("'", "'\\''").."'"
end

-- Is Number
-- Returns true for a finite Lua number that is safe to use in calculations.
local function number(value)
  return type(value) == 'number' and value == value and value > -math.huge and value < math.huge
end

-- Pick Field
-- Reads a field using either its snake_case or camelCase name.
local function pick(value, snake, camel)
  return value[snake] ~= nil and value[snake] or value[camel]
end

-- Waits for User
-- Returns true when a tool call requests user input or elevated permission.
local function waits_for_user(payload)
  local name = tostring(payload.name or ''):lower()
  if name:find('request_user_input', 1, true) or name:find('approval', 1, true) then return true end
  local arguments = payload.input or payload.arguments
  return type(arguments) == 'string'
    and arguments:match("[,{]%s*['\"]?sandbox_permissions['\"]?%s*:%s*['\"]require_escalated['\"]") ~= nil
end

-- Parse Timestamp
-- Converts an ISO 8601 UTC timestamp into Unix epoch seconds.
local function timestamp(value)
  if type(value) ~= 'string' then return nil end
  local year, month, day, hour, minute, second = value:match(
    '^(%d%d%d%d)%-(%d%d)%-(%d%d)T(%d%d):(%d%d):(%d%d)')
  if not year then return nil end
  local year_number = math.tointeger(tonumber(year))
  local month_number = math.tointeger(tonumber(month))
  local day_number = math.tointeger(tonumber(day))
  local hour_number = math.tointeger(tonumber(hour))
  local minute_number = math.tointeger(tonumber(minute))
  local second_number = math.tointeger(tonumber(second))
  if not year_number or not month_number or not day_number
      or not hour_number or not minute_number or not second_number then
    return nil
  end
  local interpreted = os.time{
    year=year_number, month=month_number, day=day_number,
    hour=hour_number, min=minute_number, sec=second_number, isdst=false,
  }
  local utc = os.date('!*t', interpreted)
  if type(utc) ~= 'table' then return nil end
  utc.isdst = false
  return interpreted + os.difftime(interpreted, os.time(utc))
end

-- List Session Files
-- Finds Codex JSONL session files and returns them newest first.
local function session_files(codex_home)
  local directories = {
    shell_quote(codex_home..'/sessions'),
    shell_quote(codex_home..'/archived_sessions'),
  }
  local command = 'find '..table.concat(directories, ' ')
    .." -type f -name '*.jsonl' -printf '%T@|%p\\n' 2>/dev/null"
  local handle = io.popen(command)
  if not handle then return {} end
  local files = {}
  for line in handle:lines() do
    local modified, path = line:match('^(%d+%.?%d*)|(.*)$')
    if modified and path then
      table.insert(files, {modified=tonumber(modified), path=path})
    end
  end
  handle:close()
  table.sort(files, function(left, right) return left.modified > right.modified end)
  return files
end

-- Normalize Limits
-- Converts an App Server rate-limit bucket into the widget's stable data shape.
local function normalize_limits(bucket)
  local windows = {}
  for _, source in ipairs({'primary', 'secondary'}) do
    local window = bucket[source]
    if type(window) == 'table' then
      local used = pick(window, 'used_percent', 'usedPercent')
      local minutes = pick(window, 'window_minutes', 'windowDurationMins')
      local name = ({[300]='five_hour', [10080]='weekly'})[minutes]
      if name and number(used) then
        local reset = pick(window, 'resets_at', 'resetsAt')
        windows[name] = {
          used_percent=math.max(0, math.min(100, used)),
          duration_seconds=minutes * 60,
          resets_at=number(reset) and reset > 0 and reset or nil,
        }
      end
    end
  end
  return {
    windows=windows,
    plan=pick(bucket, 'plan_type', 'planType'),
    limit_reached=pick(bucket, 'rate_limit_reached_type', 'rateLimitReachedType'),
  }
end

-- Select Limit
-- Selects the configured rate-limit bucket from an App Server response.
local function select_limit(result, limit_id)
  local buckets = result.rateLimitsByLimitId or result.rate_limits_by_limit_id
  if type(buckets) == 'table' then return buckets[limit_id] end
  return result.rateLimits or result.rate_limits
end

-- App Server Command
-- Builds the short-lived JSONL App Server request for one rate-limit snapshot.
local function app_server_command(timeout)
  local messages = {
    json.encode({method='initialize', id=0, params={clientInfo={
      name='pkmeter', title='PKMeter', version='1.0',
    }}}),
    json.encode({method='initialized', params={}}),
    json.encode({method='account/rateLimits/read', id=1, params={
      excludeResetCreditDetails=true,
    }}),
  }
  local quoted = {}
  for _, message in ipairs(messages) do table.insert(quoted, shell_quote(message)) end
  timeout = math.max(1, math.floor(tonumber(timeout) or 10))
  return '{ printf '..shell_quote('%s\\n')..' '..table.concat(quoted, ' ')
    ..'; tail -f /dev/null; } | timeout '..timeout..'s codex app-server 2>&1'
end

-- Read Cloud Limits
-- Queries the authenticated local Codex App Server for one current rate-limit snapshot.
function codexpoll.cloud_limits(limit_id, timeout)
  local handle = io.popen(app_server_command(timeout))
  if not handle then return nil, 'Unable to start Codex App Server' end
  local response
  local app_error
  for line in handle:lines() do
    local ok, message = pcall(json.decode, line)
    if ok and type(message) == 'table' and message.id == 1 then
      if type(message.result) == 'table' then
        response = message.result
      elseif type(message.error) == 'table' then
        app_error = message.error.message or 'Codex App Server rejected the request'
      end
    end
  end
  handle:close()
  if not response then return nil, app_error or 'Codex usage refresh failed' end
  local bucket = select_limit(response, limit_id)
  if type(bucket) ~= 'table' then return nil, 'Configured Codex limit is unavailable' end
  return {updated_at=os.time(), data=normalize_limits(bucket)}
end

-- Read Task Status
-- Infers the latest local Codex task state from session lifecycle and pending input events.
function codexpoll.status(codex_home, previous, timeout)
  local files = session_files(codex_home)
  local file = files[1]
  if not file then return {state='idle'} end
  local stale = os.time() - file.modified > STATUS_STALE_SECONDS
  if previous and previous.source_file == file.path
      and file.modified <= (previous.source_modified or 0) and not previous.partial then
    if previous.state == 'running' and stale then previous.state = 'idle' end
    return previous
  end
  local status = previous and previous.source_file == file.path and previous
    or {state='idle', waiting_calls={}}
  local handle = io.open(file.path, 'r')
  if not handle then return nil, 'Unable to read local Codex status' end
  if status.source_offset and status.source_offset > 0 then handle:seek('set', status.source_offset) end
  local deadline = socket.gettime() + (timeout or 1)
  local complete = true
  while true do
    local line_offset = handle:seek()
    local line = handle:read('*L')
    if not line then break end
    local ok, row = pcall(json.decode, line)
    if not ok and line:sub(-1) ~= '\n' then
      handle:seek('set', line_offset)
      complete = false
      break
    end
    local payload = ok and type(row) == 'table' and row.payload or nil
    if type(payload) == 'table' then
      local task_state = row.type == 'event_msg' and TASK_STATES[payload.type]
      if task_state then
        status.state = task_state
        status.waiting_calls = {}
      elseif row.type == 'response_item'
          and (payload.type == 'custom_tool_call' or payload.type == 'function_call') then
        if waits_for_user(payload) then
          status.waiting_calls[payload.call_id or payload.name] = true
          status.state = 'waiting'
        end
      elseif row.type == 'response_item'
          and (payload.type == 'custom_tool_call_output' or payload.type == 'function_call_output') then
        if payload.call_id then status.waiting_calls[payload.call_id] = nil end
        if status.state == 'waiting' and next(status.waiting_calls) == nil then
          status.state = 'running'
        end
      end
    end
    if socket.gettime() > deadline then complete = false; break end
  end
  status.source_file = file.path
  status.source_modified = file.modified
  status.source_offset = handle:seek()
  status.partial = not complete
  handle:close()
  if status.state == 'running' and stale then status.state = 'idle' end
  return status
end

-- Read Model Usage
-- Totals locally recorded tokens by model within a time window and returns the top three.
function codexpoll.models(codex_home, start_time, end_time, timeout)
  local totals = {}
  local seen = {}
  local prompts = {}
  local seen_prompts = {}
  local files_read = 0
  local partial = false
  local deadline = socket.gettime() + (timeout or 3)
  local files = session_files(codex_home)
  for index=#files,1,-1 do
    local file = files[index]
    if socket.gettime() > deadline then partial = true; break end
    if file.modified >= start_time then
      local handle = io.open(file.path, 'r')
      if handle then
        files_read = files_read + 1
        local model = 'Unknown'
        local session_id = file.path
        local turn_id
        local previous_total
        for line in handle:lines() do
          if socket.gettime() > deadline then partial = true; break end
          local ok, row = pcall(json.decode, line)
          local payload = ok and type(row) == 'table' and row.payload or nil
          if type(payload) == 'table' then
            if row.type == 'session_meta' then
              session_id = payload.session_id or payload.id or session_id
            elseif row.type == 'turn_context' then
              model = payload.model or 'Unknown'
              turn_id = payload.turn_id or turn_id
            elseif row.type == 'event_msg' and payload.type == 'task_started' then
              turn_id = payload.turn_id or row.timestamp or turn_id
            elseif row.type == 'event_msg' and payload.type == 'token_count' then
              local info = payload.info or {}
              local total = (info.total_token_usage or {}).total_tokens
              local last = (info.last_token_usage or {}).total_tokens or 0
              if number(total) and total >= 0 then
                local delta = previous_total and total >= previous_total and total - previous_total or last
                previous_total = total
                local event_time = timestamp(row.timestamp)
                local identity = table.concat({session_id, row.timestamp or '', model, total}, '|')
                if number(delta) and delta > 0 and event_time and event_time >= start_time
                    and event_time <= end_time and not seen[identity] then
                  totals[model] = (totals[model] or 0) + delta
                  seen[identity] = true
                  local prompt_identity = table.concat({session_id, turn_id or 'Unknown', model}, '|')
                  if not seen_prompts[prompt_identity] then
                    prompts[model] = (prompts[model] or 0) + 1
                    seen_prompts[prompt_identity] = true
                  end
                end
              end
            end
          end
        end
        handle:close()
      else
        partial = true
      end
    end
  end
  local ranked = {}
  local total = 0
  for model, tokens in pairs(totals) do
    total = total + tokens
    table.insert(ranked, {name=model, tokens=tokens, prompts=prompts[model] or 0})
  end
  table.sort(ranked, function(left, right) return left.tokens > right.tokens end)
  local models = {}
  for index=1,math.min(3, #ranked) do
    local entry = ranked[index]
    entry.percent = total > 0 and 100 * entry.tokens / total or 0
    table.insert(models, entry)
  end
  return {
    updated_at=end_time,
    start=start_time,
    total_tokens=total,
    files=files_read,
    partial=partial,
    models=models,
  }
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
-- Atomically replaces a poll result cache after a completed poll attempt.
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
-- Reads the cloud-limit or local-model arguments accepted by the standalone poller.
local function parse_poll_arguments(arguments)
  local options = {mode='limits', out='/tmp/pkmeter-codex.json', limit_id='codex', timeout=10}
  local index = 1
  while index <= #arguments do
    local option = arguments[index]
    local value = arguments[index + 1]
    if option == '--models' then
      options.mode = 'models'
      index = index + 1
    elseif option == '--out' and value then
      options.out = value
      index = index + 2
    elseif option == '--limit-id' and value then
      options.limit_id = value
      index = index + 2
    elseif option == '--timeout' and value and tonumber(value) then
      options.timeout = tonumber(value)
      index = index + 2
    elseif option == '--codex-home' and value then
      options.codex_home = value
      index = index + 2
    elseif option == '--start' and value and tonumber(value) then
      options.start_time = tonumber(value)
      index = index + 2
    elseif option == '--end' and value and tonumber(value) then
      options.end_time = tonumber(value)
      index = index + 2
    elseif option == '--window' and value then
      options.window_name = value
      index = index + 2
    else
      return nil, 'Usage: codexpoll.lua [--models --codex-home PATH --start TIME --end TIME --window NAME] --out PATH [--limit-id ID] [--timeout SECONDS]'
    end
  end
  if options.mode == 'models'
      and (not options.codex_home or not options.start_time or not options.end_time or not options.window_name) then
    return nil, 'Model polling requires --codex-home, --start, --end, and --window'
  end
  return options
end

-- Run Limit Poller
-- Refreshes the cloud cache while preserving the most recent successful limit snapshot.
local function run_limit_poller(options, cached)
  local snapshot, refresh_error = codexpoll.cloud_limits(options.limit_id, options.timeout)
  cached.checked_at = os.time()
  if snapshot then
    cached.updated_at = snapshot.updated_at
    cached.data = snapshot.data
    cached.error = nil
    cached.failures = 0
  else
    cached.error = tostring(refresh_error or 'Codex usage refresh failed')
    cached.failures = (tonumber(cached.failures) or 0) + 1
  end
  local written, write_error = write_cache(options.out, cached)
  if not written then io.stderr:write('Unable to write Codex cache: '..tostring(write_error)..'\n') end
  return written
end

-- Run Model Poller
-- Refreshes the local model cache without blocking Conky's draw cycle.
local function run_model_poller(options, cached)
  local ok, usage = pcall(
    codexpoll.models, options.codex_home, options.start_time, options.end_time, options.timeout)
  cached.checked_at = os.time()
  cached.start_time = options.start_time
  cached.window_name = options.window_name
  if ok then
    usage.window_name = options.window_name
    cached.usage = usage
    cached.error = nil
  else
    cached.error = tostring(usage)
  end
  local written, write_error = write_cache(options.out, cached)
  if not written then io.stderr:write('Unable to write Codex model cache: '..tostring(write_error)..'\n') end
  return written
end

-- Run Poller
-- Dispatches the configured cloud-limit or local-model background poll.
local function run_poller(arguments)
  local options, argument_error = parse_poll_arguments(arguments)
  if not options then io.stderr:write(argument_error..'\n'); return false end
  local cached = read_cache(options.out) or {}
  if options.mode == 'models' then return run_model_poller(options, cached) end
  return run_limit_poller(options, cached)
end

-- Is Standalone
-- Returns true when Lua is executing this module as the background poller script.
local function is_standalone()
  return arg and type(arg[0]) == 'string' and arg[0]:match('pkm/codexpoll%.lua$') ~= nil
end

if is_standalone() and not run_poller(arg) then os.exit(1) end

return codexpoll
