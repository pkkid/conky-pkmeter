local config = require 'config'
local claudepoll = require 'pkm/claudepoll'
local codexpoll = require 'pkm/codexpoll'
local draw = require 'pkm/draw'
local json = require 'pkm/json'
local socket = require 'socket'
local utils = require 'pkm/utils'

local aiusage = {origin=0, height=0}
local STATUS_COLORS = {running='#458588', waiting='#d65d0e'}
local SERVICE_ORDER = {'claude', 'codex'}
local Service = {}
Service.__index = Service

-- Service Definitions
-- Describes the poller, home directory, and cloud arguments that differ between services.
local SERVICES = {
  claude = {
    label = 'Claude',
    poller = 'pkm/claudepoll.lua',
    home_flag = '--claude-home',
    home = function(self)
      return self.claude_home or os.getenv('CLAUDE_CONFIG_DIR') or ((os.getenv('HOME') or '')..'/.claude')
    end,
    cloud_args = function(self)
      local args = string.format('--claude-home %q', self:home_path())
      if self.token_file then args = args..string.format(' --token-file %q', self.token_file) end
      return args
    end,
    status = function(self)
      return claudepoll.status(self:home_path())
    end,
  },
  codex = {
    label = 'Codex',
    poller = 'pkm/codexpoll.lua',
    home_flag = '--codex-home',
    home = function(self)
      return self.codex_home or os.getenv('CODEX_HOME') or ((os.getenv('HOME') or '')..'/.codex')
    end,
    cloud_args = function(self)
      return string.format('--limit-id %q', self.limit_id or 'codex')
    end,
    status = function(self)
      return codexpoll.status(self:home_path(), self.task_status, self.scan_timeout or 1)
    end,
  },
}

-- Format Duration
-- Formats seconds using only the largest relevant day, hour, or minute unit.
local function duration(seconds)
  seconds = math.max(0, math.floor(seconds))
  if seconds >= 86400 then return string.format('%dd', seconds // 86400) end
  if seconds >= 3600 then return string.format('%dh', seconds // 3600) end
  if seconds >= 60 then return string.format('%dm', seconds // 60) end
  return '1m'
end

-- Format Reset Time
-- Shows the local twelve-hour reset time, prefixed with the weekday when requested.
local function reset_time(resets_at, with_day)
  local reset = os.date('*t', resets_at)
  local time = string.format('%d:%02d%s', (reset.hour + 11) % 12 + 1, reset.min, reset.hour < 12 and 'a' or 'p')
  return with_day and os.date('%a ', resets_at)..time or time
end

-- Read JSON File
-- Loads a poller cache without treating a missing file or partial read as an error.
local function read_json(path)
  local handle = io.open(path, 'r')
  if not handle then return nil end
  local content = handle:read('*a')
  handle:close()
  local ok, snapshot = pcall(json.decode, content)
  return ok and type(snapshot) == 'table' and snapshot or nil
end

-- New Service
-- Creates the polling state for one service from its definition and config section.
function Service.new(key, settings)
  local service = setmetatable({key=key, definition=SERVICES[key]}, Service)
  for name, value in pairs(settings or {}) do service[name] = value end
  service.label = service.definition.label
  return service
end

-- Home Path
-- Returns the configured service home or its environment-based default.
function Service:home_path()
  return self.definition.home(self)
end

-- Snapshot Path
-- Returns the cloud usage cache written by the background Lua poller.
function Service:snapshot_path()
  return self.snapshot_file or '/tmp/pkmeter-'..self.key..'.json'
end

-- Model Snapshot Path
-- Returns the local model cache written by the background Lua poller.
function Service:model_snapshot_path()
  return self.model_snapshot_file or '/tmp/pkmeter-'..self.key..'-models.json'
end

-- Poll Delay
-- Returns the next cloud refresh delay with capped exponential backoff after errors.
function Service:poll_delay(failures)
  local base = self.update_interval or 900
  local multiplier = failures and failures > 0 and 2 ^ (failures - 1) or 1
  return math.min(base * multiplier, self.max_backoff_interval or 3600)
end

-- Maybe Spawn Poll
-- Starts a background cloud usage read when the cache is due and no poll is active.
function Service:maybe_spawn_poll(now, force)
  if self.poll_started then return end
  if not force and self.next_poll and now < self.next_poll then return end
  self.poll_started = now
  local command = string.format('cd %q && lua %s --out %q %s --timeout %q >/dev/null 2>&1 &',
    pkmeter.ROOT, self.definition.poller, self:snapshot_path(), self.definition.cloud_args(self),
    self.cloud_timeout or 10)
  os.execute(command)
end

-- Update Snapshot
-- Applies a completed cloud poll and schedules the next normal or backed-off refresh.
function Service:update_snapshot(now)
  local snapshot = read_json(self:snapshot_path())
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
function Service:model_window(now)
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
function Service:maybe_spawn_model_poll(now, window_name, start_time, force)
  if self.model_poll_started then return end
  if not force and self.next_model_poll and now < self.next_model_poll then return end
  self.model_poll_started = now
  local command = string.format(
    'cd %q && lua %s --models --out %q %s %q --start %q --end %q --window %q --timeout %q >/dev/null 2>&1 &',
    pkmeter.ROOT, self.definition.poller, self:model_snapshot_path(), self.definition.home_flag,
    self:home_path(), tostring(start_time), tostring(now), window_name, tostring(self.model_scan_timeout or 30))
  os.execute(command)
end

-- Update Model Usage
-- Reads a completed local model scan and schedules the next scan without blocking Conky.
function Service:update_model_usage(now, force)
  local window_name, start_time = self:model_window(now)
  if not window_name then return end
  if self.model_usage and (self.model_usage.window_name ~= window_name
      or self.model_usage.start ~= start_time) then
    self.model_usage = nil
  end
  local snapshot = read_json(self:model_snapshot_path())
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

-- Update Service
-- Refreshes cloud limits, local task status, and cached local model data on their own intervals.
function Service:update(now, force)
  self:update_snapshot(now)
  self:maybe_spawn_poll(now, force)
  if force or utils.check_update(self.last_status_update, self.status_update_interval or 5) then
    local task_status = self.definition.status(self)
    if task_status then self.task_status = task_status end
    self.last_status_update = now
  end
  self:update_model_usage(now, force)
end

-- Refresh Service
-- Forces an immediate cloud poll and local model scan for this service.
function Service:refresh(now)
  self:maybe_spawn_poll(now, true)
  local window_name, start_time = self:model_window(now)
  if window_name then self:maybe_spawn_model_poll(now, window_name, start_time, true) end
end

-- Enabled Services
-- Builds the service list once from the enabled entries in the widget config.
function aiusage:enabled_services()
  if not self.services then
    self.services = {}
    for _, key in ipairs(SERVICE_ORDER) do
      local settings = self[key]
      if settings and settings.enabled ~= false then
        table.insert(self.services, Service.new(key, settings))
      end
    end
  end
  return self.services
end

-- Update
-- Refreshes every enabled service on its own polling schedule.
function aiusage:update(force)
  local now = socket.gettime()
  for _, service in ipairs(self:enabled_services()) do service:update(now, force) end
end

-- Details Shown
-- Returns the clicked detail visibility, or the configured default before any toggle.
function aiusage:details_shown()
  if self.details_visible == nil then return self.show_details end
  return self.details_visible
end

-- Draw
-- Draws each service's usage windows, combined model mix, and task-state indicators.
function aiusage:draw()
  local now = os.time()
  local services = self:enabled_services()
  local right = conky_window.width - 10
  local width = conky_window.width - 20
  local windows_list, models, rows, plans, colors = {}, {}, {}, {}, {}
  local oldest

  -- Add Row
  -- Adds a labeled detail row to the widget's content area.
  local function row(text, color, value)
    table.insert(rows, {text=text, color=color or config.label, value=value})
  end

  for _, service in ipairs(services) do
    local snapshot = service.snapshot or {}
    local data = snapshot.data or {}
    local windows = data.windows or {}
    if data.plan then table.insert(plans, (utils.titleize(tostring(data.plan):gsub('_', ' ')))) end
    if snapshot.updated_at then oldest = math.min(oldest or snapshot.updated_at, snapshot.updated_at) end
    local color = service.task_status and STATUS_COLORS[service.task_status.state]
    if color then table.insert(colors, color) end
    if data.limit_reached then row(service.label..' limit reached', config.subheader) end
    if windows.five_hour then
      table.insert(windows_list, {service.label..' 5h', windows.five_hour, false})
    end
    table.insert(windows_list, {service.label..' Week', windows.weekly, true})
    local usage = service.model_usage
    local model_window = windows.five_hour or windows.weekly
    local limit_used = model_window and model_window.used_percent
    if model_window and model_window.resets_at and model_window.resets_at <= now then limit_used = 0 end
    if usage and usage.total_tokens > 0 then
      for _, model in ipairs(usage.models or {}) do
        local percent = model.percent
        if limit_used then percent = limit_used * model.tokens / usage.total_tokens end
        table.insert(models, {name=model.name, prompts=model.prompts, percent=percent})
      end
    end
  end
  if self:details_shown() then
    for _, model in ipairs(models) do
      row(model.name, config.value, string.format('%dp · %.0f%%', model.prompts, model.percent))
    end
    for _, service in ipairs(services) do
      local weekly = service.snapshot and service.snapshot.data and service.snapshot.data.windows
        and service.snapshot.data.windows.weekly
      if weekly and weekly.resets_at and weekly.resets_at > now then
        local elapsed = math.max(0, math.min(100, 100 * (1 - (weekly.resets_at - now) / weekly.duration_seconds)))
        local difference = weekly.used_percent - elapsed
        row(math.abs(difference) < 1 and service.label..' on weekly pace'
          or string.format('%s %.0f%% %s weekly pace', service.label, math.abs(difference),
            difference > 0 and 'ahead of' or 'below'))
      end
    end
  end
  self.height = 55 + #windows_list * 25 + #rows * 15
  local subtitle = #plans > 0 and table.concat(plans, ' · ') or 'AI accounts'
  if oldest then subtitle = subtitle..' · '..duration(math.max(0, now - oldest))..' ago' end
  draw.widget_header(self.origin, self.height, 'AI Usage', subtitle, function()
    for index, color in ipairs(colors) do
      draw.ring{x=conky_window.width-14-(#colors-index)*10, y=self.origin+20, radius=2, width=4,
        color=color}
    end
  end, width-4-#colors*10)
  local vertical = self.origin + 55
  for _, entry in ipairs(windows_list) do
    local label, window, weekly = entry[1], entry[2], entry[3]
    local expired = window and window.resets_at and window.resets_at <= now
    local used = expired and 0 or window and window.used_percent
    local value = used and string.format('%.0f%%', used) or 'Unavailable'
    if not expired and window and window.resets_at then
      local reset = reset_time(window.resets_at, weekly)
      value = value..' · '..reset
    end
    draw.text{x=10, y=vertical, text=label, color=config.value}
    draw.text{x=right, y=vertical, text=value, align='right', color=config.value, maxwidth=115}
    if window then
      draw.bargraph{x=10, y=vertical+5, width=width, height=2, value=used,
        maxvalue=100, color=config.accent, bgcolor=config.graph_bg}
    end
    vertical = vertical + 25
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
-- Refreshes every service from the header, or toggles usage details from the content.
function aiusage:click(event, x, y)
  if y >= 40 then
    self.details_visible = not self:details_shown()
    return
  end
  local now = socket.gettime()
  for _, service in ipairs(self:enabled_services()) do service:refresh(now) end
end

return aiusage
