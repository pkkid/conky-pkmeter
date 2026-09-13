local config = require 'config'
local codexpoll = require 'pkm/codexpoll'
local draw = require 'pkm/draw'
local json = require 'pkm/json'
local socket = require 'socket'
local utils = require 'pkm/utils'

local codex = {origin=0, height=0}
local STATUS_COLORS = {running='#458588', waiting='#d65d0e'}

-- Format Duration
-- Formats seconds using only the largest relevant day, hour, or minute unit.
local function duration(seconds)
  seconds = math.max(0, math.floor(seconds))
  if seconds >= 86400 then return string.format('%dd', seconds // 86400) end
  if seconds >= 3600 then return string.format('%dh', seconds // 3600) end
  if seconds >= 60 then return string.format('%dm', seconds // 60) end
  return '1m'
end

-- Format Weekly Reset
-- Shows the local weekday, or a compact twelve-hour time when the reset is today.
local function weekly_reset(resets_at, now)
  local reset = os.date('*t', resets_at)
  local today = os.date('*t', now)
  if reset.year ~= today.year or reset.yday ~= today.yday then
    return os.date('%a', resets_at)
  end
  return string.format('%d:%02d%s', (reset.hour + 11) % 12 + 1, reset.min, reset.hour < 12 and 'a' or 'p')
end

-- Home Path
-- Returns the configured Codex home or its environment-based default.
function codex:home_path()
  return self.codex_home or os.getenv('CODEX_HOME') or ((os.getenv('HOME') or '')..'/.codex')
end

-- Snapshot Path
-- Returns the cloud usage cache written by the background Lua poller.
function codex:snapshot_path()
  return self.snapshot_file or '/tmp/pkmeter-codex.json'
end

-- Model Snapshot Path
-- Returns the local model cache written by the background Lua poller.
function codex:model_snapshot_path()
  return self.model_snapshot_file or '/tmp/pkmeter-codex-models.json'
end

-- Read Snapshot
-- Loads the latest cloud usage cache without treating a partial read as an error.
function codex:read_snapshot()
  local handle = io.open(self:snapshot_path(), 'r')
  if not handle then return nil end
  local content = handle:read('*a')
  handle:close()
  local ok, snapshot = pcall(json.decode, content)
  return ok and type(snapshot) == 'table' and snapshot or nil
end

-- Read Model Snapshot
-- Loads the latest local model cache without treating a partial read as an error.
function codex:read_model_snapshot()
  local handle = io.open(self:model_snapshot_path(), 'r')
  if not handle then return nil end
  local content = handle:read('*a')
  handle:close()
  local ok, snapshot = pcall(json.decode, content)
  return ok and type(snapshot) == 'table' and snapshot or nil
end

-- Poll Delay
-- Returns the next cloud refresh delay with capped exponential backoff after errors.
function codex:poll_delay(failures)
  local base = self.update_interval or 900
  local multiplier = failures and failures > 0 and 2 ^ (failures - 1) or 1
  return math.min(base * multiplier, self.max_backoff_interval or 3600)
end

-- Maybe Spawn Poll
-- Starts a background App Server read when the cache is due and no poll is active.
function codex:maybe_spawn_poll(now, force)
  if self.poll_started then return end
  if not force and self.next_poll and now < self.next_poll then return end
  self.poll_started = now
  local command = string.format(
    'cd %q && lua pkm/codexpoll.lua --out %q --limit-id %q --timeout %q >/dev/null 2>&1 &',
    pkmeter.ROOT, self:snapshot_path(), self.limit_id or 'codex', self.cloud_timeout or 10)
  os.execute(command)
end

-- Update Snapshot
-- Applies a completed cloud poll and schedules the next normal or backed-off refresh.
function codex:update_snapshot(now)
  local snapshot = self:read_snapshot()
  if snapshot and snapshot.checked_at ~= self.checked_at then
    self.checked_at = snapshot.checked_at
    self.snapshot = snapshot
    self.poll_started = nil
    self.next_poll = now + self:poll_delay(tonumber(snapshot.failures) or 0)
  end
  if self.poll_started and now - self.poll_started > (self.cloud_timeout or 10) + 5 then
    self.poll_started = nil
    self.next_poll = now + self:poll_delay(1)
  end
end

-- Model Window
-- Returns the current cloud-reported quota window and its local record start time.
function codex:model_window(now)
  local windows = self.snapshot and self.snapshot.data and self.snapshot.data.windows or {}
  local window_name = windows.five_hour and 'five_hour' or windows.weekly and 'weekly'
  local window = window_name and windows[window_name]
  if not window then return nil end
  local reset = window.resets_at
  local quota_window = reset and reset - window.duration_seconds <= now and now < reset
  local start_time
  if quota_window then
    start_time = reset - window.duration_seconds
  else
    local interval = self.model_update_interval or 300
    start_time = math.floor((now - window.duration_seconds) / interval) * interval
  end
  return window_name, start_time
end

-- Maybe Spawn Model Poll
-- Starts a background local model scan when the current quota window is due.
function codex:maybe_spawn_model_poll(now, window_name, start_time, force)
  if self.model_poll_started then return end
  if not force and self.next_model_poll and now < self.next_model_poll then return end
  self.model_poll_started = now
  local command = string.format(
    'cd %q && lua pkm/codexpoll.lua --models --out %q --codex-home %q --start %q --end %q --window %q --timeout %q >/dev/null 2>&1 &',
    pkmeter.ROOT, self:model_snapshot_path(), self:home_path(), tostring(start_time), tostring(now),
    window_name, tostring(self.model_scan_timeout or 30))
  os.execute(command)
end

-- Update Model Usage
-- Reads a completed local model scan and schedules the next scan without blocking Conky.
function codex:update_model_usage(now, force)
  local window_name, start_time = self:model_window(now)
  if not window_name then return end
  if self.model_usage and (self.model_usage.window_name ~= window_name
      or self.model_usage.start ~= start_time) then
    self.model_usage = nil
  end
  local snapshot = self:read_model_snapshot()
  if snapshot and snapshot.checked_at ~= self.model_checked_at then
    self.model_checked_at = snapshot.checked_at
    self.model_poll_started = nil
    if snapshot.window_name == window_name and snapshot.start_time == start_time then
      self.model_usage = snapshot.usage
      self.next_model_poll = now + (self.model_update_interval or 300)
    else
      self.next_model_poll = nil
    end
  end
  if self.model_poll_started and now - self.model_poll_started > (self.model_scan_timeout or 30) + 5 then
    self.model_poll_started = nil
    self.next_model_poll = now + (self.model_update_interval or 300)
  end
  self:maybe_spawn_model_poll(now, window_name, start_time, force)
end

-- Update
-- Refreshes cloud limits, local task status, and cached local model data on their own intervals.
function codex:update(force)
  local now = socket.gettime()
  self:update_snapshot(now)
  self:maybe_spawn_poll(now, force)
  if force or utils.check_update(self.last_status_update, self.status_update_interval or 5) then
    local task_status = codexpoll.status(
      self:home_path(), self.task_status, self.scan_timeout or 1)
    if task_status then self.task_status = task_status end
    self.last_status_update = now
  end
  self:update_model_usage(now, force)
end

-- Draw
-- Draws the current cloud usage snapshot and the local Codex task-state indicator.
function codex:draw()
  local now = os.time()
  local snapshot = self.snapshot or {}
  local data = snapshot.data or {}
  local age = snapshot.updated_at and math.max(0, now - snapshot.updated_at)
  local windows = data.windows or {}
  local right = conky_window.width - 10
  local width = conky_window.width - 20
  local rows = {}

  -- Add Row
  -- Adds a labeled detail row to the widget's content area.
  local function row(text, color, value)
    table.insert(rows, {text=text, color=color or config.label, value=value})
  end

  local weekly = windows.weekly
  local pace_label
  if weekly and weekly.resets_at and weekly.resets_at > now then
    local elapsed = math.max(0, math.min(100, 100 * (1 - (weekly.resets_at - now) / weekly.duration_seconds)))
    local difference = weekly.used_percent - elapsed
    pace_label = math.abs(difference) < 1 and 'On weekly pace'
      or string.format('%.0f%% %s weekly pace', math.abs(difference), difference > 0 and 'ahead of' or 'below')
  end
  if data.limit_reached then row('Account limit reached', config.subheader) end
  local usage = self.model_usage
  local model_window = windows.five_hour or windows.weekly
  local limit_used = model_window and model_window.used_percent
  if model_window and model_window.resets_at and model_window.resets_at <= now then limit_used = 0 end
  if usage and usage.total_tokens > 0 then
    for _, model in ipairs(usage.models or {}) do
      local percent = model.percent
      if limit_used then percent = limit_used * model.tokens / usage.total_tokens end
      row(model.name, config.value, string.format('%dp · %.0f%%', model.prompts, percent))
    end
  end
  if pace_label then row(pace_label) end
  local window_rows = (windows.five_hour and 1 or 0) + 1
  self.height = 55 + window_rows * 25 + #rows * 15
  local subtitle = data.plan or 'Codex account'
  if age then subtitle = subtitle..' · '..duration(age)..' ago' end
  draw.widget_header(self.origin, self.height, 'Codex Usage', subtitle, function()
    local color = self.task_status and STATUS_COLORS[self.task_status.state]
    if color then
      draw.ring{x=conky_window.width-14, y=self.origin+20, radius=2, width=4,
        color=color}
    end
  end, width-14)
  local vertical = self.origin + 55
  for _, entry in ipairs({{'5 hour', 'five_hour'}, {'Weekly', 'weekly'}}) do
    local window = windows[entry[2]]
    if entry[2] ~= 'five_hour' or window then
      local expired = window and window.resets_at and window.resets_at <= now
      local used = expired and 0 or window and window.used_percent
      local value = used and string.format('%.0f%%', used) or 'Unavailable'
      if not expired and window and window.resets_at then
        local reset = entry[2] == 'weekly' and weekly_reset(window.resets_at, now)
          or duration(window.resets_at - now)
        value = value..' · reset '..reset
      end
      draw.text{x=10, y=vertical, text=entry[1], color=config.value}
      draw.text{x=right, y=vertical, text=value, align='right', color=config.value, maxwidth=130}
      if window then
        draw.bargraph{x=10, y=vertical+5, width=width, height=2, value=used,
          maxvalue=100, color=config.accent, bgcolor=config.graph_bg}
      end
      vertical = vertical + 25
    end
  end
  for _, item in ipairs(rows) do
    draw.text{x=10, y=vertical, text=item.text, color=item.color,
      maxwidth=item.value and width-75 or width}
    if item.value then
      draw.text{x=right, y=vertical, text=item.value, color=config.value, align='right'}
    end
    vertical = vertical + 15
  end
end

-- Click
-- Forces immediate cloud and local model refreshes when no poll is already running.
function codex:click(event, x, y)
  local now = socket.gettime()
  self:maybe_spawn_poll(now, true)
  local window_name, start_time = self:model_window(now)
  if window_name then self:maybe_spawn_model_poll(now, window_name, start_time, true) end
end

return codex
