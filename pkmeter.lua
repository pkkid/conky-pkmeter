require "cairo"
require "cairo_xlib"
require "imlib2"
local config = require 'config'
local draw = require 'pkm/draw'
local menu = require 'pkm/menu'
local utils = require 'pkm/utils'

pkmeter = {}
pkmeter.ROOT = config.root or io.popen('pwd'):read('*l')
pkmeter.hidden = {}
config = utils.merge(config, config['['..utils.parse('nodename')..']'] or {})

-- Draw Widgets
-- Draw the PKMeter widgets
function pkmeter:draw_widgets()
  local origin = 0
  for _, name in ipairs(config.widgets) do
    local widget = require('pkm/widgets/'..name)
    for k,v in pairs(config[name] or {}) do
      widget[k] = widget[k] or v
    end
    widget.origin = origin
    if not self.hidden[name] then
      draw.header_title = nil
      local ok, err = pcall(function()
        if widget.update then widget:update() end
        widget:draw()
      end)
      if not ok then
        io.stderr:write('Widget '..name..' failed: '..tostring(err)..'\n')
      end
      widget.title = draw.header_title or utils.titleize(name)
      origin = origin + (widget.height or 0)
    end
  end
end

-- Widget At
-- Returns the name, widget, and widget relative y under a window y position
function pkmeter:widget_at(y)
  for _, name in ipairs(config.widgets) do
    local widget = require('pkm/widgets/'..name)
    if (not self.hidden[name] and widget.origin <= y
        and y < (widget.origin + (widget.height or 0))) then
      return name, widget, y - widget.origin
    end
  end
end

-- Open Menu
-- Opens the right click menu with the widget's items followed by global items
function pkmeter:open_menu(x, y)
  local items = {}
  local name, widget = self:widget_at(y)
  if widget then
    table.insert(items, {title=widget.title})
    if widget.menu then
      for _, item in ipairs(widget:menu()) do table.insert(items, item) end
    elseif widget.onclick then
      local command = widget.onclick:match('^%S+'):match('[^/]+$')
      table.insert(items, {label='Open '..command, action=function()
        os.execute(widget.onclick..' &') end})
    end
    table.insert(items, {label='Hide widget', action=function() self.hidden[name] = true end})
    table.insert(items, {separator=true})
  end
  table.insert(items, {title='PKMeter'})
  if next(self.hidden) then
    table.insert(items, {label='Show hidden widgets', action=function() self.hidden = {} end})
  end
  table.insert(items, {label='Edit config', action=function()
    os.execute("xdg-open '"..self.ROOT:gsub("'", "'\\''").."/config.lua' &") end})
  table.insert(items, {label='Reload', action=function() self:signal('USR1') end})
  table.insert(items, {label='Quit', action=function() self:signal('TERM') end})
  menu.open(x, y, items)
end

-- Signal
-- Sends a signal to this conky process; USR1 reloads and TERM quits
function pkmeter:signal(signal)
  local handle = io.open('/proc/self/stat', 'r')
  local pid = handle and handle:read('n')
  if handle then handle:close() end
  if pid then os.execute('kill -'..signal..' '..math.floor(pid)) end
end

-- Conky Mouse Event
-- Called on conky mouse events
function conky_mouse_event(event)
  if menu.mouse(event) then return true end
  if event.type == 'button_down' then
    print("Mouse event: ".. event.type .." x=".. event.x .." y=".. event.y)
    -- Ignore events too close to the window edge
    local margin = 2
    if event.x < margin or event.x > (conky_window.width - margin) then return end
    if event.y < margin or event.y > (conky_window.height - margin) then return end
    -- Open the menu on right click
    if event.button == 'right' then
      pkmeter:open_menu(event.x, event.y)
      return true
    end
    -- Process the event
    local _, widget, y = pkmeter:widget_at(event.y)
    if widget and widget.click then widget:click(event, event.x, y) end
  end
end

-- Conky Main
-- Called by Conky to render the widgets
function conky_main()
  if conky_window == nil then return end
  local cs = cairo_xlib_surface_create(conky_window.display, conky_window.drawable,
      conky_window.visual, conky_window.width, conky_window.height)
  cr = cairo_create(cs)
  -- Draw the widgets and menu
  pkmeter:draw_widgets()
  local ok, err = pcall(menu.draw)
  if not ok then io.stderr:write('Menu failed: '..tostring(err)..'\n') end
  -- Clean up
  cairo_destroy(cr)
  cairo_surface_destroy(cs)
  cr = nil
end
