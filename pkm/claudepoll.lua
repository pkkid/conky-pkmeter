local json = require 'pkm/json'
local socket = require 'socket'

local claudepoll = {}
local USAGE_URL = 'https://api.anthropic.com/api/oauth/usage'
local SESSION_STATES = {busy='running', waiting='waiting'}
local WINDOWS = {five_hour=18000, seven_day=604800}

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

-- Parse Timestamp
-- Converts an ISO 8601 UTC timestamp into Unix epoch seconds.
local function timestamp(value)
  if type(value) ~= 'string' then return nil end
  local year, month, day, hour, minute, second = value:match(
    '^(%d%d%d%d)%-(%d%d)%-(%d%d)T(%d%d):(%d%d):(%d%d)')
  if not year then return nil end
  local interpreted = os.time{
    year=tonumber(year), month=tonumber(month), day=tonumber(day),
    hour=tonumber(hour), min=tonumber(minute), sec=tonumber(second), isdst=false,
  }
  local utc = os.date('!*t', interpreted)
  if type(utc) ~= 'table' then return nil end
  utc.isdst = false
  return interpreted + os.difftime(interpreted, os.time(utc))
end

-- Read JSON File
-- Reads and decodes a JSON file without treating a missing or bad file as fatal.
local function read_json(path)
  local handle = io.open(path, 'r')
  if not handle then return nil end
  local content = handle:read('*a')
  handle:close()
  local ok, decoded = pcall(json.decode, content)
  return ok and type(decoded) == 'table' and decoded or nil
end

-- List Session Files
-- Finds Claude Code JSONL transcripts, including subagents, and returns them newest first.
local function session_files(claude_home)
  local command = 'find '..shell_quote(claude_home..'/projects')
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

-- Content Type
-- Returns the first content block type of a transcript message, or text for plain strings.
local function content_type(message)
  local content = message.content
  if type(content) == 'string' then return 'text' end
  return type(content) == 'table' and type(content[1]) == 'table' and content[1].type or nil
end

-- Is Prompt
-- Returns true when a transcript row is a prompt typed by the user in the main session.
local function is_prompt(row, message)
  return row.type == 'user' and not row.isSidechain and not row.isMeta
    and content_type(message) == 'text'
end

-- Normalize Limits
-- Converts the OAuth usage response into the widget's stable data shape.
local function normalize_limits(response, plan)
  local windows = {}
  local limit_reached = false
  for source, duration in pairs(WINDOWS) do
    local window = response[source]
    if type(window) == 'table' and number(window.utilization) then
      local name = source == 'seven_day' and 'weekly' or source
      windows[name] = {
        used_percent=math.max(0, math.min(100, window.utilization)),
        duration_seconds=duration,
        resets_at=timestamp(window.resets_at),
      }
      if window.utilization >= 100 then limit_reached = true end
    end
  end
  return {windows=windows, plan=plan, limit_reached=limit_reached}
end

-- Credentials Path
-- Returns the Claude Code OAuth credentials file within the configured home.
function claudepoll.credentials_path(claude_home)
  return claude_home..'/.credentials.json'
end

-- Read Cloud Limits
-- Queries the account usage endpoint with Claude Code's stored OAuth login.
function claudepoll.cloud_limits(claude_home, timeout)
  local credentials = read_json(claudepoll.credentials_path(claude_home)) or {}
  local oauth = credentials.claudeAiOauth
  if type(oauth) ~= 'table' or type(oauth.accessToken) ~= 'string' then
    return nil, 'Claude Code is not logged in'
  end
  if number(oauth.expiresAt) and oauth.expiresAt / 1000 < os.time() then
    return nil, 'Claude Code login expired'
  end
  local headers_path = os.tmpname()
  local headers = io.open(headers_path, 'w')
  if not headers then return nil, 'Unable to write request headers' end
  headers:write('Authorization: Bearer '..oauth.accessToken..'\n')
  headers:write('anthropic-beta: oauth-2025-04-20\n')
  headers:close()
  timeout = math.max(1, math.floor(tonumber(timeout) or 10))
  local handle = io.popen(string.format('curl -sf -m %d -H @%s %s 2>/dev/null',
    timeout, shell_quote(headers_path), shell_quote(USAGE_URL)))
  local content = handle and handle:read('*a')
  if handle then handle:close() end
  os.remove(headers_path)
  local ok, response = pcall(json.decode, content or '')
  if not ok or type(response) ~= 'table' then return nil, 'Claude usage refresh failed' end
  local plan = type(oauth.subscriptionType) == 'string' and oauth.subscriptionType or nil
  if plan then plan = plan:sub(1, 1):upper()..plan:sub(2) end
  return {updated_at=os.time(), data=normalize_limits(response, plan)}
end

-- Process Start
-- Returns a process start time from /proc so reused process IDs can be detected.
local function process_start(pid)
  local handle = io.open('/proc/'..pid..'/stat', 'r')
  if not handle then return nil end
  local stat = handle:read('*l') or ''
  handle:close()
  local fields = {}
  for field in (stat:match('%) (.*)$') or ''):gmatch('%S+') do table.insert(fields, field) end
  return fields[20]
end

-- Read Task Status
-- Combines the live status Claude Code records for each running interactive process.
function claudepoll.status(claude_home)
  local handle = io.popen('find '..shell_quote(claude_home..'/sessions')
    .." -maxdepth 1 -type f -name '*.json' 2>/dev/null")
  if not handle then return nil, 'Unable to list Claude sessions' end
  local state = 'idle'
  for path in handle:lines() do
    local pid = path:match('/(%d+)%.json$')
    local session = pid and read_json(path)
    local started = pid and process_start(pid)
    if session and started and (session.procStart == nil or tostring(session.procStart) == started) then
      local session_state = SESSION_STATES[session.status]
      if session_state == 'waiting' then state = 'waiting' end
      if session_state == 'running' and state == 'idle' then state = 'running' end
    end
  end
  handle:close()
  return {state=state}
end

-- Read Model Usage
-- Totals locally recorded tokens by model within a time window and returns the top three.
function claudepoll.models(claude_home, start_time, end_time, timeout)
  local totals = {}
  local seen = {}
  local prompts = {}
  local files_read = 0
  local partial = false
  local deadline = socket.gettime() + (timeout or 3)
  local files = session_files(claude_home)
  for index=#files,1,-1 do
    local file = files[index]
    if socket.gettime() > deadline then partial = true; break end
    if file.modified >= start_time then
      local handle = io.open(file.path, 'r')
      if handle then
        files_read = files_read + 1
        local model
        local pending_prompts = 0
        for line in handle:lines() do
          if socket.gettime() > deadline then partial = true; break end
          local ok, row = pcall(json.decode, line)
          local message = ok and type(row) == 'table' and row.message or nil
          local event_time = type(message) == 'table' and timestamp(row.timestamp)
          if event_time and event_time >= start_time and event_time <= end_time then
            if is_prompt(row, message) then
              pending_prompts = pending_prompts + 1
            elseif row.type == 'assistant' and type(message.usage) == 'table'
                and type(message.model) == 'string' and message.model ~= '<synthetic>' then
              model = message.model
              local identity = tostring(message.id or row.uuid)
              local usage = message.usage
              local tokens = 0
              for _, field in ipairs({'input_tokens', 'output_tokens',
                  'cache_creation_input_tokens', 'cache_read_input_tokens'}) do
                if number(usage[field]) then tokens = tokens + usage[field] end
              end
              if tokens > 0 and not seen[identity] then
                seen[identity] = true
                totals[model] = (totals[model] or 0) + tokens
              end
              if pending_prompts > 0 then
                prompts[model] = (prompts[model] or 0) + pending_prompts
                pending_prompts = 0
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
  local options = {mode='limits', out='/tmp/pkmeter-claude.json', timeout=10}
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
    elseif option == '--timeout' and value and tonumber(value) then
      options.timeout = tonumber(value)
      index = index + 2
    elseif option == '--claude-home' and value then
      options.claude_home = value
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
      return nil, 'Usage: claudepoll.lua [--models --start TIME --end TIME --window NAME] --claude-home PATH --out PATH [--timeout SECONDS]'
    end
  end
  if not options.claude_home then return nil, 'Polling requires --claude-home' end
  if options.mode == 'models'
      and (not options.start_time or not options.end_time or not options.window_name) then
    return nil, 'Model polling requires --start, --end, and --window'
  end
  return options
end

-- Run Limit Poller
-- Refreshes the cloud cache while preserving the most recent successful limit snapshot.
local function run_limit_poller(options, cached)
  local snapshot, refresh_error = claudepoll.cloud_limits(options.claude_home, options.timeout)
  cached.checked_at = os.time()
  if snapshot then
    cached.updated_at = snapshot.updated_at
    cached.data = snapshot.data
    cached.error = nil
    cached.failures = 0
  else
    cached.error = tostring(refresh_error or 'Claude usage refresh failed')
    cached.failures = (tonumber(cached.failures) or 0) + 1
  end
  local written, write_error = write_cache(options.out, cached)
  if not written then io.stderr:write('Unable to write Claude cache: '..tostring(write_error)..'\n') end
  return written
end

-- Run Model Poller
-- Refreshes the local model cache without blocking Conky's draw cycle.
local function run_model_poller(options, cached)
  local ok, usage = pcall(
    claudepoll.models, options.claude_home, options.start_time, options.end_time, options.timeout)
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
  if not written then io.stderr:write('Unable to write Claude model cache: '..tostring(write_error)..'\n') end
  return written
end

-- Run Poller
-- Dispatches the configured cloud-limit or local-model background poll.
local function run_poller(arguments)
  local options, argument_error = parse_poll_arguments(arguments)
  if not options then io.stderr:write(argument_error..'\n'); return false end
  local cached = read_json(options.out) or {}
  if options.mode == 'models' then return run_model_poller(options, cached) end
  return run_limit_poller(options, cached)
end

-- Is Standalone
-- Returns true when Lua is executing this module as the background poller script.
local function is_standalone()
  return arg and type(arg[0]) == 'string' and arg[0]:match('pkm/claudepoll%.lua$') ~= nil
end

if is_standalone() and not run_poller(arg) then os.exit(1) end

return claudepoll
