local config = require 'config'
local draw = require 'pkm/draw'
local json = require 'pkm/json'
local menu = require 'pkm/menu'
local socket = require 'socket'
local toggles = require 'pkm/toggles'
local utils = require 'pkm/utils'

local aiusage = {origin=0, height=0, title='AI Usage'}
local SERVICE_ORDER = {'claude', 'codex', 'gemini', 'openrouter'}
local LOW_REMAINING = 15            -- Remaining percent drawn in color_low
local PIN_SECONDS = 6               -- How long a clicked reset tooltip stays open
local COLUMNS = {{key='five_hour', right=137}, {key='weekly', right=190}}  -- 5 hour, then weekly
local COLUMN_WIDTH = 47
local PERCENT_SIZE = 10             -- Font size of the remaining limit percentages
local ROW_HEIGHT = 20
local DETAILS_GAP = 6               -- Space above the model rows when details are shown
local Service = {}
Service.__index = Service

-- Service Definitions
-- Describes the poller, home directory, and cloud arguments that differ between services.
-- Claude and Codex ask their signed in CLIs for limits, so no credentials are read here.
-- Gemini is a workaround that reuses T3 Code's Antigravity login; see pkm/geminipoll.lua.
-- OpenRouter reports a credit balance instead of usage windows.
local SERVICES = {
  claude = {
    label = 'Claude',
    color = '#d79921',
    poller = 'pkm/claudepoll.lua',
    home_flag = '--claude-home',
    home = function(self)
      return self.claude_home or os.getenv('CLAUDE_CONFIG_DIR') or ((os.getenv('HOME') or '')..'/.claude')
    end,
    cloud_args = function(self) return '' end,
  },
  codex = {
    label = 'Codex',
    color = '#83a598',
    poller = 'pkm/codexpoll.lua',
    home_flag = '--codex-home',
    home = function(self)
      return self.codex_home or os.getenv('CODEX_HOME') or ((os.getenv('HOME') or '')..'/.codex')
    end,
    cloud_args = function(self)
      return string.format('--limit-id %q', self.limit_id or 'codex')
    end,
  },
  gemini = {
    label = 'Gemini',
    color = '#d3869b',
    poller = 'pkm/geminipoll.lua',
    token_args = '--antigravity yes',
    cloud_args = function(self)
      return self.token_file and string.format('--token-file %q', self.token_file) or ''
    end,
  },
  openrouter = {
    label = 'OpenRouter',
    credits = true,
    poller = 'pkm/openrouterpoll.lua',
    cloud_args = function(self)
      local args = string.format('--key-name %q', self.key_name or 'OPENROUTER_API_KEY')
      if self.key_file then args = args..string.format(' --key-file %q', self.key_file) end
      return args
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

-- Format Countdown
-- Formats seconds with the two largest units, such as 4d 3h or 2h 14m.
local function countdown(seconds)
  seconds = math.max(0, math.floor(seconds))
  local days, hours, minutes = seconds // 86400, seconds % 86400 // 3600, seconds % 3600 // 60
  if days > 0 then return string.format('%dd %dh', days, hours) end
  if hours > 0 then return string.format('%dh %dm', hours, minutes) end
  return string.format('%dm', math.max(1, minutes))
end

-- Format Tokens
-- Shortens a token count to K, M, or B with one decimal place.
local function tokens(count)
  if count >= 1e9 then return string.format('%.1fB', count / 1e9) end
  if count >= 1e6 then return string.format('%.1fM', count / 1e6) end
  if count >= 1e3 then return string.format('%.0fK', count / 1e3) end
  return string.format('%d', count)
end

-- Window Name
-- Names a limit window by its length, such as 5 hour, weekly, or 30 day.
local function window_name(window)
  local seconds = window.duration_seconds or 0
  if seconds == 604800 then return 'weekly' end
  if seconds >= 86400 then return string.format('%d day', seconds // 86400) end
  return string.format('%d hour', seconds // 3600)
end

-- Format Reset Date
-- Shows the local reset weekday, date, and time using the clock's 12 or 24 hour choice.
local function reset_date(resets_at)
  local hour24 = toggles.get('clock', 'hour24', false)
  local time = os.date(hour24 and '%H:%M' or '%I:%M %p', resets_at):gsub('^0(%d:)', '%1')
  return os.date('%a %b ', resets_at)..tonumber(os.date('%d', resets_at))..' at '..time
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
  service.color = service.color or service.definition.color
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

-- Windows
-- Returns the service's usage windows from its latest snapshot, or an empty table.
function Service:windows()
  return self.snapshot and self.snapshot.data and self.snapshot.data.windows or {}
end

-- Poll Delay
-- Returns the next cloud refresh delay with capped exponential backoff after errors.
function Service:poll_delay(failures)
  local base = self.update_interval or 900
  local multiplier = failures and failures > 0 and 2 ^ (failures - 1) or 1
  return math.min(base * multiplier, self.max_backoff_interval or 3600)
end

-- Maybe Spawn Poll
-- Starts a background cloud read when the cache is due and no poll is active.
function Service:maybe_spawn_poll(now, force)
  if self.poll_started or not self.definition.cloud_args then return end
  if not force and self.next_poll and now < self.next_poll then return end
  self.poll_started = now
  local command = string.format('cd %q && lua %s --out %q %s --timeout %q >/dev/null 2>&1 &',
    pkmeter.ROOT, self.definition.poller, self:snapshot_path(), self.definition.cloud_args(self),
    self.cloud_timeout or 10)
  os.execute(command)
end

-- Update Snapshot
-- Applies a completed cloud poll and schedules the next refresh from when that poll ran.
function Service:update_snapshot(now)
  local snapshot = read_json(self:snapshot_path())
  if snapshot and snapshot.checked_at ~= self.checked_at then
    self.checked_at = snapshot.checked_at
    self.snapshot = snapshot
    self.poll_started = nil
    self.next_poll = (tonumber(snapshot.checked_at) or now) + self:poll_delay(tonumber(snapshot.failures) or 0)
  end
  if self.poll_started and now - self.poll_started > (self.cloud_timeout or 10) + 5 then
    self.poll_started = nil
    self.next_poll = now + self:poll_delay(1)
  end
end

-- Model Window
-- Returns the current cloud-reported quota window and its local record start time.
function Service:model_window(now)
  if not self.definition.home_flag then return nil end
  local windows = self:windows()
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
-- Refreshes cloud limits and cached local model data on their own intervals.
function Service:update(now, force)
  self:update_snapshot(now)
  self:maybe_spawn_poll(now, force)
  self:update_model_usage(now, force)
end

-- Refresh Service
-- Forces an immediate cloud poll or status reread and a local model scan for this service.
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

-- Service Shown
-- Returns true unless the service was hidden from the right click menu.
function aiusage:service_shown(service)
  return service.definition.credits or toggles.get('aiusage', 'show_'..service.key, true)
end

-- Shown Services
-- Returns the enabled services that are not hidden from the right click menu.
function aiusage:shown_services()
  local services = {}
  for _, service in ipairs(self:enabled_services()) do
    if self:service_shown(service) then table.insert(services, service) end
  end
  return services
end

-- History Days
-- Returns the number of days drawn in the header token graph.
function aiusage:graph_days()
  return math.max(2, math.floor(tonumber(self.history_days) or 7))
end

-- Day Start
-- Returns the local midnight that starts the given graph day, where the last day is today.
function aiusage:day_start(now, index)
  local date = os.date('*t', math.floor(now))
  date.day = date.day - (self:graph_days() - index)
  date.hour, date.min, date.sec, date.isdst = 0, 0, 0, nil
  return os.time(date)
end

-- Token Path
-- Returns the hourly token cache written by the background transcript scanner.
function aiusage:token_path()
  return self.token_file or '/tmp/pkmeter-tokens.json'
end

-- Update Tokens
-- Reads the latest transcript token scan and starts a new one in the background when due.
function aiusage:update_tokens(now, force)
  if utils.check_update(self.last_token_read, 5) then
    self.token_snapshot = read_json(self:token_path()) or self.token_snapshot
    self.last_token_read = now
  end
  if self.token_poll_started and now - self.token_poll_started < (self.token_scan_timeout or 30) + 5
      and not force then
    return
  end
  if not force and self.next_token_poll and now < self.next_token_poll then return end
  local homes = ''
  for _, service in ipairs(self:enabled_services()) do
    if service.definition.home_flag then
      homes = homes..string.format(' %s %q', service.definition.home_flag, service:home_path())
    elseif service.definition.token_args then
      homes = homes..' '..service.definition.token_args
    end
  end
  if homes == '' then return end
  self.token_poll_started = now
  self.next_token_poll = now + (self.token_update_interval or 300)
  os.execute(string.format('cd %q && lua pkm/tokenpoll.lua --out %q%s --days %d --timeout %d >/dev/null 2>&1 &',
    pkmeter.ROOT, self:token_path(), homes, self:graph_days() + 1, self.token_scan_timeout or 30))
end

-- Token Totals
-- Returns each shown service's tokens over the graph's days, in service order.
function aiusage:token_totals(now)
  local services = self.token_snapshot and self.token_snapshot.services or {}
  local since = self:day_start(now, 1)
  local totals = {}
  for _, service in ipairs(self:shown_services()) do
    local entry = services[service.key]
    if entry then
      local total = 0
      for hour, count in pairs(entry.buckets or {}) do
        if tonumber(hour) >= since then total = total + count end
      end
      table.insert(totals, {label=service.label, tokens=total})
    end
  end
  return totals
end

-- History Series
-- Sums each shown service's hourly token counts into one total per local day, and returns
-- the series with the largest daily total so every line shares one scale.
function aiusage:history_series(now)
  local days = self:graph_days()
  local starts, series, maxvalue = {}, {}, 1
  for index=1,days do starts[index] = self:day_start(now, index) end
  local services = self.token_snapshot and self.token_snapshot.services or {}
  for _, service in ipairs(self:shown_services()) do
    local entry = services[service.key]
    if entry then
      local buckets = utils.init_table(days, 0)
      for key, count in pairs(entry.buckets or {}) do
        local hour = tonumber(key)
        for index=days,1,-1 do
          if hour >= starts[index] then buckets[index] = buckets[index] + count; break end
        end
      end
      for _, value in ipairs(buckets) do maxvalue = math.max(maxvalue, value) end
      table.insert(series, {color=service.color or config.accent, data=buckets})
    end
  end
  return series, maxvalue
end

-- Log Scale Series
-- Converts daily token totals to a log scale that starts just below the smallest non-zero day,
-- so providers with far fewer tokens still show their shape. Days without use stay at zero.
local function log_series(series, maxvalue)
  local smallest = maxvalue
  for _, line in ipairs(series) do
    for _, value in ipairs(line.data) do
      if value > 0 then smallest = math.min(smallest, value) end
    end
  end
  local floor = math.log(smallest / 2, 10)
  local scaled = {}
  for _, line in ipairs(series) do
    local data = {}
    for index, value in ipairs(line.data) do
      data[index] = value > 0 and math.log(value, 10) - floor or 0
    end
    table.insert(scaled, {color=line.color, data=data})
  end
  return scaled, math.max(math.log(maxvalue, 10) - floor, 1)
end

-- Update
-- Refreshes every enabled service and the token history on their own polling schedules.
function aiusage:update(force)
  local now = socket.gettime()
  for _, service in ipairs(self:enabled_services()) do service:update(now, force) end
  self:update_tokens(now, force)
end

-- Details Shown
-- Returns the saved detail visibility, hidden by default.
function aiusage:details_shown()
  return toggles.get('aiusage', 'show_details', false)
end

-- Detail Rows
-- Returns the combined model mix and weekly pacing rows shown with details.
function aiusage:detail_rows(services, now)
  local rows = {}
  for _, service in ipairs(services) do
    local windows = service:windows()
    local usage = service.model_usage
    local model_window = windows.five_hour or windows.weekly
    local limit_used = model_window and model_window.used_percent
    if model_window and model_window.resets_at and model_window.resets_at <= now then limit_used = 0 end
    if usage and usage.total_tokens > 0 then
      for _, model in ipairs(usage.models or {}) do
        local percent = model.percent
        if limit_used then percent = limit_used * model.tokens / usage.total_tokens end
        table.insert(rows, {text=model.name, color=config.value,
          value=string.format('%dp · %.0f%%', model.prompts, percent)})
      end
    end
  end
  for _, service in ipairs(services) do
    local weekly = service:windows().weekly
    if weekly and weekly.resets_at and weekly.resets_at > now then
      local elapsed = math.max(0, math.min(100, 100 * (1 - (weekly.resets_at - now) / weekly.duration_seconds)))
      local difference = weekly.used_percent - elapsed
      table.insert(rows, {color=config.label, text=math.abs(difference) < 1
        and service.label..' on '..window_name(weekly)..' pace'
        or string.format('%s %.0f%% %s %s pace', service.label, math.abs(difference),
          difference > 0 and 'ahead of' or 'below', window_name(weekly))})
    end
  end
  return rows
end

-- Draw
-- Draws remaining five-hour and weekly limits as a table, the usage graph, and credits.
function aiusage:draw()
  local now = os.time()
  local services, limits, credits = self:shown_services(), {}, nil
  local oldest
  for _, service in ipairs(services) do
    if service.definition.credits then credits = service else table.insert(limits, service) end
    local updated = service.snapshot and service.snapshot.updated_at
    if updated then oldest = math.min(oldest or updated, updated) end
  end
  local rows = self:details_shown() and self:detail_rows(limits, now) or {}
  local details_gap = #rows > 0 and DETAILS_GAP or 0
  self.height = 52 + #limits * ROW_HEIGHT + details_gap + #rows * 15 + (credits and ROW_HEIGHT or 0)
  self.regions = {}
  local subtitle = oldest and duration(now - oldest)..' ago' or 'Waiting for data'
  draw.widget_header(self.origin, self.height, 'AI Usage', subtitle, function()
    draw.rectangle{x=100, y=self.origin+8, width=90, height=24, color=config.header_graph_bg}
    local series, maxvalue = self:history_series(now)
    if toggles.get('aiusage', 'log_scale', true) then series, maxvalue = log_series(series, maxvalue) end
    for _, line in ipairs(series) do
      draw.curve{data=line.data, x=100, y=self.origin+8, width=90, height=24,
        color=line.color, maxvalue=maxvalue}
    end
  end, 85)
  local graph_lines = {'Tokens used, last '..self:graph_days()..' days'}
  for _, total in ipairs(self:token_totals(now)) do
    table.insert(graph_lines, total.label..': '..tokens(total.tokens))
  end
  if not self.token_snapshot then table.insert(graph_lines, 'Scanning transcripts') end
  table.insert(self.regions, {x1=100, y1=8, x2=190, y2=32, lines=graph_lines})

  -- Limits Table
  local vertical = self.origin + 38
  for _, service in ipairs(limits) do
    vertical = vertical + ROW_HEIGHT
    local windows = service:windows()
    draw.text{x=10, y=vertical, text=service.label, color=config.value, maxwidth=60}
    for _, column in ipairs(COLUMNS) do
      local window = windows[column.key]
      local expired = window and window.resets_at and window.resets_at <= now
      local remaining = window and (expired and 100 or 100 - window.used_percent)
      local color = not remaining and config.label
        or remaining < LOW_REMAINING and (self.color_low or '#cc2414') or config.value
      draw.text{x=column.right, y=vertical, text=remaining and string.format('%.0f%%', remaining) or '--',
        color=color, align='right', size=PERCENT_SIZE}
      if remaining then
        draw.bargraph{x=column.right-COLUMN_WIDTH, y=vertical+4, width=COLUMN_WIDTH, height=2,
          value=remaining, maxvalue=100, bgcolor=config.graph_bg,
          color=remaining < LOW_REMAINING and color or service.color or config.accent}
      end
      local lines
      if window and window.resets_at and not expired then
        lines = {service.label..' '..window_name(window)..' limit resets', reset_date(window.resets_at),
          'in '..countdown(window.resets_at - now)}
      elseif expired then
        lines = {service.label..' '..window_name(window)..' limit has reset'}
      elseif window then
        lines = {service.label..' '..window_name(window)..' limit not started'}
      end
      if lines and column.key == 'weekly' then
        local data = service.snapshot and service.snapshot.data or {}
        for _, model in ipairs(data.model_limits or {}) do
          table.insert(lines, string.format('%s weekly: %.0f%% left', model.name, 100 - model.used_percent))
        end
      end
      if lines then
        table.insert(self.regions, {x1=column.right-COLUMN_WIDTH, x2=column.right,
          y1=vertical-self.origin-12, y2=vertical-self.origin+7, lines=lines, pin=true})
      end
    end
  end

  -- Credits
  if credits then
    local data = credits.snapshot and credits.snapshot.data
    vertical = vertical + ROW_HEIGHT
    draw.text{x=10, y=vertical, text=credits.label, color=config.value}
    draw.text{x=190, y=vertical, align='right', color=data and config.value or config.label,
      text=data and string.format('$%.2f', data.remaining) or '--'}
    local lines = data and {string.format('Used $%.2f of $%.2f', data.total_usage, data.total_credits)}
      or {credits.snapshot and credits.snapshot.error or 'Waiting for data'}
    table.insert(self.regions, {x1=10, x2=190, y1=vertical-self.origin-12,
      y2=vertical-self.origin+5, lines=lines})
  end

  -- Details
  vertical = vertical + details_gap
  for _, item in ipairs(rows) do
    vertical = vertical + 15
    draw.text{x=10, y=vertical, text=item.text, color=item.color, maxwidth=item.value and 105 or 180}
    if item.value then
      draw.text{x=190, y=vertical, text=item.value, color=config.value, align='right'}
    end
  end
end

-- Region At
-- Returns the tooltip region under x,y, if any.
function aiusage:region_at(x, y)
  for _, region in ipairs(self.regions or {}) do
    if x >= region.x1 and x <= region.x2 and y >= region.y1 and y <= region.y2 then
      return region
    end
  end
end

-- Tooltip
-- Returns the reset time lines for the limit under x,y, or the graph and credit details.
function aiusage:tooltip(x, y)
  local region = self:region_at(x, y)
  return region and region.lines
end

-- Click
-- Pins the reset time tooltip of a clicked limit, refreshes from the header, or toggles details.
function aiusage:click(event, x, y)
  local region = self:region_at(x, y)
  if region and region.pin then return {lines=region.lines, seconds=PIN_SECONDS} end
  if y >= 40 then
    toggles.set('aiusage', 'show_details', not self:details_shown())
    return
  end
  self:refresh()
end

-- Refresh
-- Refreshes every enabled service now.
function aiusage:refresh()
  local now = socket.gettime()
  for _, service in ipairs(self:enabled_services()) do service:refresh(now) end
  self.last_token_read = nil
  self:update_tokens(now, true)
end

-- Menu
-- Returns right click menu items to refresh usage, toggle details, and show or hide providers.
function aiusage:menu()
  local items = {
    {label='Refresh now', action=function() self:refresh() end},
    menu.toggle('Show details', 'aiusage', 'show_details', false),
    menu.toggle('Log scale graph', 'aiusage', 'log_scale', true),
  }
  table.insert(items, {label='Providers', items=function()
    local providers = {}
    for _, service in ipairs(self:enabled_services()) do
      if not service.definition.credits then
        local item = menu.toggle(service.label, 'aiusage', 'show_'..service.key, true)
        item.keep_open = true
        table.insert(providers, item)
      end
    end
    return providers
  end})
  return items
end

return aiusage
