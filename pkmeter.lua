require "cairo"
require "imlib2"
local config = require 'config'

pkmeter = {}
pkmeter.ROOT = config.root or io.popen('pwd'):read('*l')

-- Draw Widgets
-- Draw the PKMeter widgets
function pkmeter:draw_widgets()
  local origin = 0
  for _, name in ipairs(config.widgets) do
    local widget = require('pkm/widgets/'..name)
    for k,v in pairs(config[name] or {}) do
      widget[k] = widget[k] or v
    end
    if widget.update then widget:update() end
    widget.origin = origin
    widget:draw()
    origin = origin + widget.height
  end
end

-- Conky Mouse Event
-- Called on conky mouse events
 function conky_mouse_event(event)
  if event.type == 'button_down' then
    for _, name in ipairs(config.widgets) do
      local widget = require('pkm/widgets/'..name)
      if (widget.click and widget.origin <= event.y
          and event.y < (widget.origin + widget.height)) then
        y = event.y - widget.origin
        widget:click(event, event.x, y)
      end
    end
  end
end

-- Conky Main
-- Called by Conky to render the widgets
function conky_main()
  if conky_window == nil then return end
  local cs = cairo_xlib_surface_create(conky_window.display, conky_window.drawable,
      conky_window.visual, conky_window.width, conky_window.height)
  cr = cairo_create(cs)
  -- Draw the widgets
  pkmeter:draw_widgets()
  -- Clean up
  cairo_destroy(cr)
  cairo_surface_destroy(cs)
  cr = nil
end
