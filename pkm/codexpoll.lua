local json = require 'pkm/json'
local socket = require 'socket'

local codexpoll = {}

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
-- Converts a recorded Codex limit bucket into the widget's stable data shape.
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

-- Scan Limit File
-- Reads new records from one session file and returns its latest matching limits.
local function scan_limit_file(file, limit_id, offset, deadline)
  local handle = io.open(file.path, 'r')
  if not handle then return nil, offset or 0 end
  if offset and offset > 0 then handle:seek('set', offset) end
  local latest
  for line in handle:lines() do
    if socket.gettime() > deadline then
      handle:close()
      return latest, nil, 'Local session scan timed out'
    end
    local ok, row = pcall(json.decode, line)
    local payload = ok and type(row) == 'table' and row.payload or nil
    if type(payload) == 'table' and row.type == 'event_msg' and payload.type == 'token_count' then
      local limits = payload.rate_limits or payload.rateLimits
      local found_id = type(limits) == 'table' and pick(limits, 'limit_id', 'limitId') or nil
      if type(limits) == 'table' and (not found_id or found_id == limit_id) then
        local event_time = timestamp(row.timestamp)
        if event_time then latest = {updated_at=event_time, data=normalize_limits(limits)} end
      end
    end
  end
  local final_offset = handle:seek()
  handle:close()
  return latest, final_offset
end

-- Read Limits
-- Finds the latest local limit snapshot and incrementally updates a previous result.
function codexpoll.limits(codex_home, limit_id, previous, timeout)
  local files = session_files(codex_home)
  local deadline = socket.gettime() + (timeout or 1)
  if previous and previous.source_file then
    for _, file in ipairs(files) do
      if file.path == previous.source_file then
        if file.modified <= (previous.source_modified or 0) then return previous end
        local latest, offset, err = scan_limit_file(file, limit_id, previous.source_offset, deadline)
        if err then return nil, err end
        previous.source_modified = file.modified
        previous.source_offset = offset
        if latest then previous.updated_at = latest.updated_at; previous.data = latest.data end
        return previous
      end
      if file.modified > (previous.source_modified or 0) then
        local latest, offset, err = scan_limit_file(file, limit_id, nil, deadline)
        if err then return nil, err end
        if latest and latest.updated_at > previous.updated_at then
          latest.source_file = file.path
          latest.source_modified = file.modified
          latest.source_offset = offset
          return latest
        end
      end
    end
    return previous
  end
  for _, file in ipairs(files) do
    local latest, offset, err = scan_limit_file(file, limit_id, nil, deadline)
    if err then return nil, err end
    if latest then
      latest.source_file = file.path
      latest.source_modified = file.modified
      latest.source_offset = offset
      return latest
    end
  end
  return nil, 'No local Codex usage found'
end

-- Read Model Usage
-- Totals locally recorded tokens by model within a time window and returns the top three.
function codexpoll.models(codex_home, start_time, end_time, timeout)
  local totals = {}
  local seen = {}
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
    table.insert(ranked, {name=model, tokens=tokens})
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

return codexpoll
