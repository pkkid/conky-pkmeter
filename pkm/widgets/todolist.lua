local config = require 'config'
local draw = require 'pkm/draw'
local socket = require 'socket'
local utils = require 'pkm/utils'

local todolist = {}
todolist.origin = 0
todolist.height = 0
todolist.items = {}

-- Read Lines
-- Returns the file's lines, or nil when the file cannot be read
local function read_lines(path)
  local handle = io.open(path, 'r')
  if not handle then return nil end
  local content = handle:read('a')
  handle:close()
  local lines = {}
  for line in (content..'\n'):gmatch('(.-)\n') do table.insert(lines, line) end
  return lines
end

-- Parse Line
-- Returns the check mark and text of a checklist line, or nil
local function parse_line(line)
  local mark, text = line:match('^%s*[-*+]%s+%[([ xX])%]%s+(.-)%s*$')
  if not mark then mark, text = line:match('^%s*%d+[.)]%s+%[([ xX])%]%s+(.-)%s*$') end
  if mark and text ~= '' then return mark, text end
end

-- Draw
-- Draw this widget, or nothing when there are no items
function todolist:draw()
  self.height = 0
  if #self.items == 0 then return end
  self.height = 67 + (#self.items * 15)
  local subtitle = #self.items..(#self.items == 1 and ' item' or ' items')
  draw.widget_header(self.origin, self.height, 'To Do List', subtitle)

  -- Items
  local y = self.origin + 61
  for _, item in ipairs(self.items) do
    local boxcolor = item.checked and self:dim(config.label) or config.label
    local textcolor = item.checked and self:dim(config.value) or config.value
    draw.checkbox{x=10, y=y-9, size=9, checked=item.checked, color=boxcolor}
    local width = draw.text{x=26, y=y, text=item.text, color=textcolor, maxwidth=164}
    if item.checked then
      draw.line{x1=26, y1=y-3.5, x2=26+width, y2=y-3.5, color=textcolor}
    end
    y = y + 15
  end
end

-- Update
-- Reread the checklist items from the markdown file
function todolist:update()
  if utils.check_update(self.last_update, self.update_interval) then
    self.items = self:parse(self:path())
    self.last_update = socket.gettime()
  end
end

-- Click
-- Open the file when the header is clicked, or toggle the clicked item
function todolist:click(event, x, y)
  if y < 40 then
    local path = "'"..self:path():gsub("'", "'\\''").."'"
    os.execute((self.onclick or 'xdg-open')..' '..path..' &')
  elseif y >= 50 then
    local item = self.items[math.floor((y - 50) / 15) + 1]
    if item then self:toggle(item) end
  end
end

-- Toggle
-- Check or uncheck an item in the markdown file and reload the list
function todolist:toggle(item)
  local path = self:path()
  local lines = read_lines(path)
  local line = lines and lines[item.line]
  local _, text = parse_line(line or '')
  if text == item.text then
    lines[item.line] = line:gsub('%[[ xX]%]', item.checked and '[ ]' or '[x]', 1)
    local handle = io.open(path, 'w')
    if handle then
      handle:write(table.concat(lines, '\n'))
      handle:close()
    end
  end
  self.items = self:parse(path)
  self.last_update = socket.gettime()
end

-- Path
-- Returns the configured file, or todolist.md beside the loaded conkyrc
function todolist:path()
  if self.file then return (self.file:gsub('^~', os.getenv('HOME') or '~')) end
  local dir = (conky_config or ''):match('^(.*)/')
  if not dir then dir = pkmeter.ROOT
  elseif dir:sub(1, 1) ~= '/' then dir = pkmeter.ROOT..'/'..dir end
  return dir..'/todolist.md'
end

-- Parse
-- Returns unchecked then checked items from every checklist in the file
function todolist:parse(path)
  local unchecked, checked, infence = {}, {}, false
  for num, line in ipairs(read_lines(path) or {}) do
    if line:match('^%s*```') or line:match('^%s*~~~') then infence = not infence end
    local mark, text = parse_line(line)
    if mark and not infence then
      local item = {text=text, checked=(mark ~= ' '), line=num}
      table.insert(item.checked and checked or unchecked, item)
    end
  end
  for _, item in ipairs(checked) do table.insert(unchecked, item) end
  return unchecked
end

-- Dim
-- Returns the hex color at the configured checked item opacity
function todolist:dim(hex)
  local alpha = math.floor((self.checked_opacity or 0.4) * 255 + 0.5)
  return '#'..hex:gsub('#', ''):sub(1, 6)..string.format('%02x', alpha)
end

return todolist
