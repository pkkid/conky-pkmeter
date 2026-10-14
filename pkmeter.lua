require "cairo"
require "cairo_xlib"
require "imlib2"
local config = require 'config'
local menu = require 'pkm/menu'
local toggles = require 'pkm/toggles'
local utils = require 'pkm/utils'

pkmeter = {}
pkmeter.ROOT = config.root or io.popen('pwd'):read('*l')
config = utils.merge(config, config['['..utils.parse('nodename')..']'] or {})

-- Draw Widgets
-- Draw the PKMeter widgets
function pkmeter:draw_widgets()
  local origin = 0
  for _, name in ipairs(self:widget_names()) do
    local widget = require('pkm/widgets/'..name)
    for k,v in pairs(config[name] or {}) do
      widget[k] = widget[k] or v
    end
    widget.origin = origin
    if not self:is_hidden(name) then
      local ok, err = pcall(function()
        if widget.update then widget:update() end
        widget:draw()
      end)
      if not ok then
        io.stderr:write('Widget '..name..' failed: '..tostring(err)..'\n')
      end
      origin = origin + (widget.height or 0)
    end
  end
end

-- Widget Names
-- Returns widget names in the saved order, or the config order before any change
function pkmeter:widget_names()
  local names, seen = {}, {}
  for _, name in ipairs(toggles.get('pkmeter', 'order', {})) do
    if utils.contains(config.widgets, name) and not seen[name] then
      table.insert(names, name)
      seen[name] = true
    end
  end
  for _, name in ipairs(config.widgets) do
    if not seen[name] then table.insert(names, name) end
  end
  return names
end

-- Is Hidden
-- Returns true when the widget was turned off from the menu
function pkmeter:is_hidden(name)
  return utils.contains(toggles.get('pkmeter', 'hidden', {}), name)
end

-- Save Layout
-- Saves the widget order and hidden widgets so they replace the config order
function pkmeter:save_layout(names, hidden)
  toggles.set('pkmeter', 'order', names)
  toggles.set('pkmeter', 'hidden', hidden)
end

-- Set Hidden
-- Turns a widget on or off and saves the layout
function pkmeter:set_hidden(name, hidden)
  local list = {}
  for _, other in ipairs(toggles.get('pkmeter', 'hidden', {})) do
    if other ~= name then table.insert(list, other) end
  end
  if hidden then table.insert(list, name) end
  self:save_layout(self:widget_names(), list)
end

-- Move Target
-- Returns the position of the nearest shown widget in the step direction
function pkmeter:move_target(names, name, step)
  local index
  for i, other in ipairs(names) do
    if other == name then index = i end
  end
  local target = index + step
  while names[target] and self:is_hidden(names[target]) do target = target + step end
  return index, names[target] and target
end

-- Move Widget
-- Moves a widget past its nearest shown neighbor and saves the layout
function pkmeter:move_widget(name, step)
  local names = self:widget_names()
  local index, target = self:move_target(names, name, step)
  if not target then return end
  table.remove(names, index)
  table.insert(names, target, name)
  self:save_layout(names, toggles.get('pkmeter', 'hidden', {}))
end

-- Widget At
-- Returns the name, widget, and widget relative y under a window y position
function pkmeter:widget_at(y)
  for _, name in ipairs(self:widget_names()) do
    local widget = require('pkm/widgets/'..name)
    if (not self:is_hidden(name) and widget.origin <= y
        and y < (widget.origin + (widget.height or 0))) then
      return name, widget, y - widget.origin
    end
  end
end

-- Widget Title
-- Returns the display name of a widget
function pkmeter:widget_title(name)
  return require('pkm/widgets/'..name).title or utils.titleize(name)
end

-- Widgets Menu
-- Returns items to turn each widget on or off and to reset the layout
function pkmeter:widgets_menu()
  local items = {}
  for _, name in ipairs(self:widget_names()) do
    local hidden = self:is_hidden(name)
    table.insert(items, {label=self:widget_title(name), checked=not hidden, keep_open=true,
      action=function() self:set_hidden(name, not hidden) end})
  end
  if toggles.get('pkmeter', 'order') then
    table.insert(items, {separator=true})
    table.insert(items, {label='Reset layout', keep_open=true, action=function()
      self:save_layout(nil, nil) end})
  end
  return items
end

-- Menu Items
-- Returns the clicked widget's items followed by global items
function pkmeter:menu_items(name, widget)
  local items = {}
  if widget then
    table.insert(items, {title=self:widget_title(name)})
    if widget.menu then
      for _, item in ipairs(widget:menu()) do table.insert(items, item) end
    elseif widget.onclick then
      table.insert(items, menu.app(widget.onclick))
    end
    local names = self:widget_names()
    if select(2, self:move_target(names, name, -1)) then
      table.insert(items, {label='Move up', action=function() self:move_widget(name, -1) end})
    end
    if select(2, self:move_target(names, name, 1)) then
      table.insert(items, {label='Move down', action=function() self:move_widget(name, 1) end})
    end
    table.insert(items, {label='Hide widget', action=function() self:set_hidden(name, true) end})
    table.insert(items, {separator=true})
  end
  table.insert(items, {title='PKMeter'})
  table.insert(items, {label='Widgets', items=function() return self:widgets_menu() end})
  table.insert(items, {label='Edit config', action=function()
    os.execute("xdg-open '"..self.ROOT:gsub("'", "'\\''").."/config.lua' &") end})
  table.insert(items, {label='Reload', action=function() self:signal('USR1') end})
  table.insert(items, {label='Quit', action=function() self:signal('TERM') end})
  return items
end

-- Open Menu
-- Opens the right click menu for the widget under x,y and returns true. Empty
-- space only opens it when no widget is shown, so hidden widgets can return.
function pkmeter:open_menu(x, y)
  local name, widget = self:widget_at(y)
  if not widget and self:widget_at(0) then return false end
  menu.open(x, y, function() return self:menu_items(name, widget) end)
  return true
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
      return pkmeter:open_menu(event.x, event.y)
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
