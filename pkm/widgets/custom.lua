local config = require 'config'
local draw = require 'pkm/draw'
local utils = require 'pkm/utils'

local custom = {}
custom.origin = 0
custom.height = 0
custom.cmd_cache = {}
custom.var_cache = {}

-- Draw
-- Draw this widget
function custom:draw()
  self.height = 0
  if not self.templates or #self.templates == 0 then return end
  local y = self.origin
  for _, template in ipairs(self.templates) do
    -- Check if template requires a command to have succeeded
    if template.requires_cmd ~= nil then
      local cmd_idx = template.requires_cmd + 1  -- Lua is 1-indexed
      if not self.cmd_cache[cmd_idx] or not self.cmd_cache[cmd_idx].success then
        goto continue
      end
    end
    -- Calculate section height
    local section_height = 40  -- header
    if template.lines then
      section_height = section_height + (#template.lines * 15) + 11  -- lines + bottom padding
    end
    -- Substitute variables in template strings
    local title = self:substitute_variables(template.title or 'Custom')
    local subtitle = template.subtitle and self:substitute_variables(template.subtitle) or ''
    -- Draw header
    draw.rectangle{x=0, y=y, width=conky_window.width, height=40, color=config.header_bg}
    draw.text{x=10, y=y+17, text=title, size=12, color=config.header}
    if subtitle and #subtitle > 0 then
      draw.text{x=10, y=y+32, text=subtitle, maxwidth=180, color=config.subheader}
    end
    -- Draw lines if present
    if template.lines and #template.lines > 0 then
      draw.rectangle{x=0, y=y+40, width=conky_window.width, height=section_height-40, color=config.background}
      local line_y = y + 56
      for _, line in ipairs(template.lines) do
        local left = self:substitute_variables(line.left or '')
        local right = self:substitute_variables(line.right or '')
        -- If both left and right are empty, just add a 5px gap
        if #left == 0 and #right == 0 then
          line_y = line_y + 5
        else
          draw.text{x=10, y=line_y, text=left, color=config.label}
          draw.text{x=190, y=line_y, text=right, color=config.value, align='right'}
          line_y = line_y + 15
        end
      end
    end
    y = y + section_height
    self.height = self.height + section_height
    ::continue::
  end
end

-- Update
-- Update command cache and variables
function custom:update()
  if not self.commands then return end
  -- Update command cache based on individual frequencies
  for i, cmd_config in ipairs(self.commands) do
    local cache_entry = self.cmd_cache[i]
    if not cache_entry then
      cache_entry = {last_update = nil, output = '', success = false}
      self.cmd_cache[i] = cache_entry
    end
    local frequency = cmd_config.frequency or 60
    if utils.check_update(cache_entry.last_update, frequency) then
      cache_entry.output = utils.run_command(cmd_config.cmd, '')
      cache_entry.success = cache_entry.output and #utils.trim(cache_entry.output) > 0
      cache_entry.last_update = os.time()
    end
  end
  -- Extract variables from cached command outputs
  if self.variables then
    for _, var_config in ipairs(self.variables) do
      local cmd_idx = var_config.fromcmd
      if cmd_idx and self.cmd_cache[cmd_idx + 1] then  -- Lua is 1-indexed
        local output = self.cmd_cache[cmd_idx + 1].output
        local pattern = var_config.regex or '(.*)'
        local default = var_config.default or ''
        local value = string.match(output, pattern) or default
        self.var_cache[var_config.name] = utils.trim(value)
      end
    end
  end
end

-- Click
-- Perform click action
function custom:click()
  if self.onclick then
    os.execute(self.onclick..' &')
  end
end

-- Substitute Variables
-- Replace {varname} placeholders with actual values
function custom:substitute_variables(str)
  if not str then return '' end
  return string.gsub(str, '{([^}]+)}', function(varname)
    return self.var_cache[varname] or ('{' .. varname .. '}')
  end)
end

return custom
