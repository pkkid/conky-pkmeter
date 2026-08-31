local config = require 'config'
local draw = require 'pkm/draw'
local json = require 'pkm/json'
local socket = require 'socket'
local utils = require 'pkm/utils'

local bambu = {}
bambu.origin = 0
bambu.height = 0
bambu.data = nil                -- parsed `print` object from the last poll
bambu.state_ok = false          -- did the last poll succeed
bambu.last_error = nil
bambu.data_timestamp = nil      -- epoch seconds from the JSON file
bambu.last_spawn = nil          -- when we last kicked off the background poll
bambu.min_spawn_gap = 15        -- floor on spawn frequency (seconds)
bambu.update_interval = 30      -- how old data must be before we repoll
bambu.status_file = '/tmp/bambu_status.json'
bambu.thumbnail_file = '/tmp/bambu_thumb.png'
bambu.name = 'Bambu P2S'
bambu.temperature_unit = 'celsius'

bambu.STATE_LABEL = {
  IDLE='Idle', PREPARE='Preparing', RUNNING='Printing',
  PAUSE='Paused', FINISH='Finished', FAILED='Failed',
  SLICING='Slicing', UNKNOWN='Unknown',
}
-- States we consider "actively printing" — anything else hides the widget.
bambu.ACTIVE_STATES = {RUNNING=true, PAUSE=true, PREPARE=true, SLICING=true}

-- Draw
-- Draw this widget
function bambu:draw()
  if not self.host or not self.serial or not self.access_code then
    self.height = 0
    return
  end
  -- Hide entirely unless the printer is actively printing. That covers
  -- both "no data yet" and IDLE/FINISH/FAILED.
  local state = self.data and self.data.gcode_state
  if not state or not self.ACTIVE_STATES[state] then
    self.height = 0
    return
  end

  self.height = 51 + 67
  local d = self.data

  -- Header title + state subtitle
  local label = self.STATE_LABEL[state] or state
  local subtitle = label
  if state == 'RUNNING' and d.mc_percent then
    subtitle = string.format('%s %d%%', label, d.mc_percent)
  end
  draw.widget_header(self.origin, self.height, self.name, subtitle, function()
    -- Top-right: nozzle / bed temps as a compact status line.
    if d.nozzle_temper then
      local t = utils.format_temp(d.nozzle_temper, self.temperature_unit)
      draw.text{x=190, y=self.origin+17, text='N '..t, color=config.value, align='right'}
    end
    if d.bed_temper then
      local t = utils.format_temp(d.bed_temper, self.temperature_unit)
      draw.text{x=190, y=self.origin+32, text='B '..t, color=config.value, align='right'}
    end
  end)

  -- Content area
  local y = self.origin + 50
  draw.rectangle{x=0, y=y-1, width=conky_window.width, height=67, color=config.background}

  -- Progress bar.
  local pct = tonumber(d.mc_percent) or 0
  draw.bargraph{x=10, y=y, width=120, height=2, value=pct, maxvalue=100,
    color=config.accent, bgcolor=config.graph_bg}

  -- Print name
  local title = d.subtask_name
  if title == nil or title == '' then title = '—' end
  draw.text{x=10, y=y+17, text=title, maxwidth=120, color=config.value}

  -- Layer info
  local layer_text
  if d.total_layer_num and tonumber(d.total_layer_num) and tonumber(d.total_layer_num) > 0 then
    layer_text = string.format('Layer %s of %s', d.layer_num or 0, d.total_layer_num)
  else
    layer_text = ''
  end
  draw.text{x=10, y=y+32, text=layer_text, maxwidth=120, color=config.label}

  -- Remaining time / state.
  local secondary
  local remaining = tonumber(d.mc_remaining_time)
  if state == 'RUNNING' and remaining and remaining > 0 then
    if remaining >= 60 then
      secondary = string.format('%dh %dm remaining', remaining // 60, remaining % 60)
    else
      secondary = string.format('%d min remaining', remaining)
    end
  elseif state == 'PAUSE' then
    secondary = 'Paused'
  else
    secondary = label
  end
  draw.text{x=10, y=y+47, text=secondary, maxwidth=120, color=config.label}

  -- Right side: plate thumbnail if the poller has cached one; otherwise
  -- a faint framed square that preserves the layout.
  local thumb = self.thumbnail_file
  if thumb and self:file_exists(thumb) then
    draw.image{x=140, y=y, path=thumb, width=50, height=50}
  else
    draw.rectangle{x=140, y=y, width=50, height=50, color=config.header_graph_bg}
  end
end


-- Update
-- Read cached status; if stale, spawn a background poll.
function bambu:update()
  if not self.host or not self.serial or not self.access_code then return end
  local now = socket.gettime()
  local data = self:read_status()
  if data and data.timestamp then
    self.data_timestamp = data.timestamp
    self.state_ok = data.ok == true
    self.last_error = data.error
    if data.ok and type(data['print']) == 'table' then
      self.data = data['print']
    end
    -- Age is measured against the file's own timestamp so we repoll even
    -- if the last attempt failed hours ago.
    local age = now - data.timestamp
    if age > self.update_interval then
      self:maybe_spawn_poll(now)
    end
  else
    -- No status file yet (fresh start) — kick off a poll.
    self:maybe_spawn_poll(now)
  end
end


-- Click
-- Manual refresh on click.
function bambu:click(event, x, y)
  self:maybe_spawn_poll(socket.gettime(), true)
end


-- Read Status
-- Load and decode the status JSON written by pkm/bambupoll.lua.
function bambu:read_status()
  local fh = io.open(self.status_file, 'r')
  if not fh then return nil end
  local content = fh:read('*a')
  fh:close()
  if not content or content == '' then return nil end
  local ok, decoded = pcall(json.decode, content)
  if not ok then return nil end
  return decoded
end


-- File Exists
-- Returns true when a file can be opened for reading.
function bambu:file_exists(path)
  local fh = io.open(path, 'r')
  if fh then fh:close(); return true end
  return false
end


-- Maybe Spawn Poll
-- Spawn the poll script in the background if we're outside the min gap.
function bambu:maybe_spawn_poll(now, force)
  if not force and self.last_spawn and (now - self.last_spawn) < self.min_spawn_gap then
    return
  end
  self.last_spawn = now
  local thumb_arg = ''
  if self.thumbnail_file and self.thumbnail_file ~= '' then
    thumb_arg = string.format(' --thumb-out %q', self.thumbnail_file)
  end
  local cmd = string.format(
    'cd %q && lua pkm/bambupoll.lua --host %q --serial %q --code %q --out %q%s >/dev/null 2>&1 &',
    pkmeter.ROOT, self.host, self.serial, self.access_code, self.status_file, thumb_arg)
  os.execute(cmd)
end


return bambu
