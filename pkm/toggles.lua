----------------------------------
-- Author: Michael Shepanski
----------------------------------
local json = require 'pkm/json'
local utils = require 'pkm/utils'

local toggles = {}
toggles.data = nil    -- Saved values by section, loaded on first use

-- Path
-- Returns toggles.json beside the loaded conkyrc
function toggles.path()
  return utils.config_dir()..'/toggles.json'
end

-- Load
-- Returns the saved values, reading toggles.json on first use
function toggles.load()
  if toggles.data then return toggles.data end
  toggles.data = {}
  local handle = io.open(toggles.path(), 'r')
  if handle then
    local ok, data = pcall(json.decode, handle:read('a'))
    handle:close()
    if ok and type(data) == 'table' then toggles.data = data end
  end
  return toggles.data
end

-- Get
-- Returns the saved value for a section key, or the default when unset
function toggles.get(section, key, default)
  local value = (toggles.load()[section] or {})[key]
  if value == nil then return default end
  return value
end

-- Set
-- Saves the value for a section key; nil removes it
function toggles.set(section, key, value)
  local data = toggles.load()
  data[section] = data[section] or {}
  data[section][key] = value
  if next(data[section]) == nil then data[section] = nil end
  toggles.save()
end

-- Save
-- Writes the saved values to toggles.json
function toggles.save()
  local path = toggles.path()
  local handle = io.open(path..'.tmp', 'w')
  if not handle then
    io.stderr:write('Failed to save '..path..'\n')
    return
  end
  handle:write(json.encode(toggles.data))
  handle:close()
  os.rename(path..'.tmp', path)
end

return toggles
