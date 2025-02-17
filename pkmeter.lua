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
      widget[k] = v
    end
    if widget.update then widget:update() end
    height = widget:draw(origin)
    origin = origin + height
  end
end


-- Conky Main
-- This function is called by Conky to render the widgets
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
