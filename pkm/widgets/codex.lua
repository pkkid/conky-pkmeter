local config = require 'config'
local codexpoll = require 'pkm/codexpoll'
local draw = require 'pkm/draw'
local socket = require 'socket'
local utils = require 'pkm/utils'

local codex = {origin=0, height=0}

-- Format Duration
-- Formats seconds using only the largest relevant day, hour, or minute unit.
local function duration(seconds)
  seconds = math.max(0, math.floor(seconds))
  if seconds >= 86400 then return string.format('%dd', seconds // 86400) end
  if seconds >= 3600 then return string.format('%dh', seconds // 3600) end
  if seconds >= 60 then return string.format('%dm', seconds // 60) end
  return '1m'
end

-- Home Path
-- Returns the configured Codex home or its environment-based default.
function codex:home_path()
  return self.codex_home or os.getenv('CODEX_HOME') or ((os.getenv('HOME') or '')..'/.codex')
end

-- Update
-- Refreshes local limit and model usage data when their intervals expire.
function codex:update(force)
  local now = socket.gettime()
  if force or utils.check_update(self.last_limit_update, self.update_interval) then
    local snapshot, err = codexpoll.limits(
      self:home_path(), self.limit_id or 'codex', self.snapshot, self.scan_timeout or 1)
    if snapshot then self.snapshot = snapshot; self.error = nil else self.error = err end
    self.last_limit_update = now
  end
  local weekly = self.snapshot and self.snapshot.data.windows.weekly
  local reset = weekly and weekly.resets_at
  local quota_week = reset and reset - 604800 <= now and now < reset
  local start_time = quota_week and reset - 604800 or now - 604800
  if force
      or utils.check_update(self.last_model_update, self.model_update_interval)
      or self.model_usage and self.model_usage.quota_week ~= quota_week
      or quota_week and self.model_usage and self.model_usage.start ~= start_time then
    self.model_usage = codexpoll.models(self:home_path(), start_time, now, self.model_scan_timeout or 3)
    self.model_usage.quota_week = quota_week
    self.last_model_update = now
  end
end

-- Draw
-- Draw this widget
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
  local function row(text, color)
    table.insert(rows, {text=text, color=color or config.label})
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
  if usage and usage.total_tokens > 0 then
    for _, model in ipairs(usage.models or {}) do
      table.insert(rows, {text=model.name, value=string.format('%.1f%%', model.percent), color=config.value})
    end
    if usage.partial then row('Partial local records') end
  else
    row(usage and 'No recorded tokens' or 'Reading local records…')
  end
  if pace_label then row(pace_label) end
  if self.error then row(self.error, config.subheader) end
  self.height = 105 + #rows * 15
  local subtitle = data.plan or 'Local usage'
  if age then subtitle = subtitle..' · '..duration(age)..' ago' end
  draw.widget_header(self.origin, self.height, 'Codex Usage', subtitle)
  local vertical = self.origin + 55
  for _, entry in ipairs({{'5 hour', 'five_hour'}, {'Weekly', 'weekly'}}) do
    local window = windows[entry[2]]
    local expired = window and window.resets_at and window.resets_at <= now
    local value = window and string.format('%.0f%%', window.used_percent) or 'Unavailable'
    if expired then value = value..' · Awaiting'
    elseif window and window.resets_at then value = value..' · Resets '..duration(window.resets_at - now) end
    draw.text{x=10, y=vertical, text=entry[1], color=config.value}
    draw.text{x=right, y=vertical, text=value, align='right', color=config.value, maxwidth=130}
    if window then
      draw.bargraph{x=10, y=vertical+5, width=width, height=2, value=window.used_percent,
        maxvalue=100, color=config.accent, bgcolor=config.graph_bg}
    end
    vertical = vertical + 25
  end
  for _, item in ipairs(rows) do
    draw.text{x=10, y=vertical, text=item.text, color=item.color, maxwidth=item.value and width-50 or width}
    if item.value then draw.text{x=right, y=vertical, text=item.value, color=config.value, align='right'} end
    vertical = vertical + 15
  end
end

-- Click
-- Forces an immediate refresh of local Codex usage data.
function codex:click(event, x, y)
  self:update(true)
end

return codex
