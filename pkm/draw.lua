----------------------------------
-- Author: Michael Shepanski
-- Derivative from Zineddine SAIBI
-- Original License GPL-3.0
-- https://www.github.com/SZinedine/namoudaj-conky
----------------------------------
require "cairo"
require "imlib2"
local config = require 'config'
local utils = require 'pkm/utils'

draw = {}

-- Draw Bar Graph
--  args.value (number): Value of the bar. Default is 0.
--  args.x (number): x-coordinate where the rectangle will be drawn. Default is 0.
--  args.y (number): y-coordinate where the rectangle will be drawn. Default is 0.
--  args.width (number): Width of the rectangle. Default is 10.
--  args.height (number): Height of the rectangle. Default is 10.
--  args.origin (string): Origin of the bar {bottom, top, left, right}. Default is left.
--  args.color (string): Color of the rectangle in hex. Default is #ffffff.
--  args.maxvalue (number): Max value of the chart (defaults to max args.data).
--  args.bgcolor (string): Color of the background rectangle. Default is #00000000.
function draw.bargraph(args)
  local value = args.value or 0
  if value == nil then error('value is required') end
  local x = args.x or 0
  local y = args.y or 0
  local width = args.width or 10
  local height = args.height or 10
  local origin = args.origin or 'left'
  local color = args.color or '#ffffff'
  local maxvalue = args.maxvalue or 100
  local bgcolor = args.bgcolor or '#00000000'
  local fullpx = args.fullpx

  if value > maxvalue then value = maxvalue end
  if fullpx == nil then fullpx = config.fullpx end
  draw.rectangle{x=x, y=y, width=width, height=height, color=bgcolor}
  cairo_set_source_rgba(cr, utils.hex_to_rgba(color))
  if origin == 'bottom' then
    local barheight = (height / maxvalue) * value
    if fullpx then barheight = math.ceil(barheight) end
    cairo_rectangle(cr, x, y+height-barheight, width, barheight)
  elseif origin == 'top' then
    local barheight = (height / maxvalue) * value
    if fullpx then barheight = math.ceil(barheight) end
    cairo_rectangle(cr, x, y, width, barheight)
  elseif origin == 'left' then
    local barwidth = (width / maxvalue) * value
    if fullpx then barwidth = math.ceil(barwidth) end
    cairo_rectangle(cr, x, y, barwidth, height)
  elseif origin == 'right' then
    local barwidth = (width / maxvalue) * value
    if fullpx then barwidth = math.ceil(barwidth) end
    cairo_rectangle(cr, x+width-barwidth, y, barheight, height)
  end
  cairo_fill(cr)
end

-- Draw Graph
--  args.data (table): Table of numbers representing data (oldest first).
--  args.x (number): x-coordinate where the rectangle will be drawn. Default is 0.
--  args.y (number): y-coordinate where the rectangle will be drawn. Default is 0.
--  args.width (number): Width of the rectangle. Default is 10.
--  args.height (number): Height of the rectangle. Default is 10.
--  args.origin (string): Origin of the bar {bottomright, topright}. Default is bottomright.
--  args.color (string): Color of the rectangle in hex format. Default is #ffffff.
--  args.linewidth (number): Width of the line. Default is 1.
--  args.maxvalue (number): Max value of the chart (defaults to max args.data).
--  args.minmaxvalue (number): Minimum Max-value of the chart (so small numbers are not blown out).
--  args.logscale (boolean): Set true for log scale.
--  args.bgcolor (string): Color of the background rectangle. Default is #00000000.
function draw.graph(args)
  local data = args.data
  if data == nil then error('data is required') end
  local x = args.x or 0
  local y = args.y or 0
  local width = args.width or 10
  local height = args.height or 10
  local origin = args.origin or 'bottom'
  local color = args.color or '#ffffff'
  local linewidth = args.linewidth or 1
  local maxvalue = args.maxvalue or math.max(table.unpack(data))
  local minmaxvalue = args.minmaxvalue or nil
  local logscale = args.logscale or false
  local bgcolor = args.bgcolor or '#00000000'
  local fullpx = args.fullpx

  if minmaxvalue then maxvalue = math.max(maxvalue, minmaxvalue) end
  if fullpx == nil then fullpx = config.fullpx end
  draw.rectangle{x=x, y=y, width=width, height=height, color=bgcolor}
  cairo_set_source_rgba(cr, utils.hex_to_rgba(color))
  cairo_set_line_width(cr, linewidth)
  for i=1, #data do
    if logscale then
      local value = data[i] > 0 and math.log(data[i]) or 0
      if value > maxvalue then value = maxvalue end
      local logmax = maxvalue > 0 and math.log(maxvalue) or 1
      barheight = (height / logmax) * value
    else
      barheight = (height / maxvalue) * data[i]
    end
    if fullpx then
      barheight = math.ceil(barheight)
    end
    if origin == 'bottom' then
      local cx, cy = x+(linewidth/2) + ((i-1)*linewidth), y+height
      cairo_move_to(cr, cx, cy)
      cairo_rel_line_to(cr, 0, barheight*-1)
    elseif origin == 'top' then
      local cx, cy = x+(linewidth/2) + ((i-1)*linewidth), y
      cairo_move_to(cr, cx, cy)
      cairo_rel_line_to(cr, 0, barheight)
    end
    cairo_stroke(cr)
  end
end

-- Draw Image
--  args.x (number): x-coordinate where the image will be rendered.
--  args.y (number): y-coordinate where the image will be rendered.
--  args.path (string): Path to image to be rendered.
--  args.width (number): Width of the image. Default is nil
--  args.height (number): Height of the image. Default is nil
function draw.image(args)
  local x = args.x or 0
  local y = args.y or 0
  local path = args.path or error('path is required')
  local width = args.width
  local height = args.height

  local img = imlib_load_image(path)
  if img == nil then return end
  imlib_context_set_image(img)
  if width or height then
    local origwidth = imlib_image_get_width()
    local origheight = imlib_image_get_height()
    local aspectratio = origwidth / origheight
    if width and not height then
      width, height = width, width / aspectratio
    elseif height and not width then
      width, height = height * aspectratio, height
    else
      width, height = width or origwidth, height or origheight
    end
    img = imlib_create_cropped_scaled_image(0, 0, origwidth, origheight, width, height)
    imlib_context_set_image(img)
  end
  imlib_render_image_on_drawable(x, y)
  imlib_free_image()
  img = nil
end

-- Draw Rectangle
--  args.x (number): x-coordinate where the rectangle will be drawn. Default is 0.
--  args.y (number): y-coordinate where the rectangle will be drawn. Default is 0.
--  args.width (number): Width of the rectangle. Default is 10.
--  args.height (number): Height of the rectangle. Default is 10.
--  args.color (string): Color of the rectangle in hex. Default is #ffffff.
function draw.rectangle(args)
  local x = args.x or 0
  local y = args.y or 0
  local width = args.width or 10
  local height = args.height or 10
  local color = args.color or '#ffffff'

  cairo_set_source_rgba(cr, utils.hex_to_rgba(color))
  cairo_rectangle(cr, x, y, width, height)
  cairo_fill(cr)
end

-- Draw Ring
--  args.x (number): x-coordinate where the ring will be drawn. Default is 0.
--  args.y (number): y-coordinate where the ring will be drawn. Default is 0.
--  args.radius (number): Radius of the ring. Default is 100.
--  args.width (number): Width of the ring. Default is 10.
--  args.angle_start (number): Starting angle of the ring. Default is 0.
--  args.angle_end (number): Ending angle of the ring. Default is 360.
--  args.color (string): Color of the ring in hex. Default is #ffffff.
function draw.ring(args)
  local x = args.x or 0
  local y = args.y or 0
  local radius = args.radius or 100
  local width = args.width or 10
  local angle_start = args.angle_start or 0
  local angle_end = args.angle_end or 360
  local color = args.color or '#ffffff'

  angle_start = angle_start * (2 * math.pi / 360) - (math.pi / 2)
  angle_end = angle_end * (2 * math.pi / 360) - (math.pi / 2)
  cairo_set_line_width(cr, width)
  cairo_set_source_rgba(cr, utils.hex_to_rgba(color))
  cairo_arc(cr, x, y, radius, angle_start, angle_end)
  cairo_stroke(cr)
end

-- Draw Ring Graph
--  args.value (number): Value of the ring. Default is 0.
--  args.x (number): x-coordinate where the ring will be drawn. Default is 0.
--  args.y (number): y-coordinate where the ring will be drawn. Default is 0.
--  args.radius (number): Radius of the ring. Default is 100.
--  args.width (number): Width of the ring. Default is 10.
--  args.angle_start (number): Starting angle of the ring. Default is 0.
--  args.angle_end (number): Ending angle of the ring. Default is 360.
--  args.color (string): Color of the ring in hex. Default is #ffffff.
--  args.maxvalue (number): Max value of the chart (defaults to max args.data).
--  args.bgcolor (string): Color of the background ring. Default is #00000000.
function draw.ringgraph(args)
  local value = args.value or 0
  local x = args.x or 0
  local y = args.y or 0
  local radius = args.radius or 100
  local width = args.width or 10
  local angle_start = args.angle_start or 0
  local angle_end = args.angle_end or 360
  local color = args.color or '#ffffff'
  local maxvalue = args.maxvalue or 100
  local bgcolor = args.bgcolor or '#00000000'

  if value > maxvalue then value = maxvalue end
  local progress = (value / maxvalue) * (angle_end - angle_start)
  draw.ring{x=x, y=y, radius=radius, width=width, angle_start=angle_start, angle_end=angle_end, color=bgcolor}
  draw.ring{x=x, y=y, radius=radius, width=width, angle_start=angle_start, angle_end=angle_start+progress, color=color}
end


-- Draw Text
-- x (number): x-coordinate where the text will be written. Default is 0
-- y (number): y-coordinate where the text will be written. Default is 0
-- text (string): Text to be written. Default is an empty string
-- font (string): Name of the font to be used. Default is "DejaVu Sans"
-- size (number): Size of the font. Default is 12
-- color (number): Color of the text in hexadecimal format. Default is 0xffffff
-- bold (boolean): Set true for bold
-- italic (boolean): Set true for italic
-- align (string): Alignment of the text {left, center, right}
-- maxwidth (number): Maximum width of the text. Default is nil (no limit)
function draw.text(args)
  local x = args.x or 0
  local y = args.y or 0
  local text = args.text or ""
  local font = args.font or config.default_font
  local size = args.size or config.default_font_size
  local color = args.color or config.default_font_color
  local bold = args.bold == nil and config.default_font_bold or args.bold
  local italic = args.italic == nil and config.default_font_italic or args.italic
  local align = args.align or 'left'
  local maxwidth = args.maxwidth

  local font_face = bold and CAIRO_FONT_WEIGHT_BOLD or CAIRO_FONT_WEIGHT_NORMAL
  local font_slant = italic and CAIRO_FONT_SLANT_ITALIC or CAIRO_FONT_SLANT_NORMAL
  cairo_select_font_face(cr, font, font_slant, font_face)
  cairo_set_font_size(cr, size)
  cairo_set_source_rgba(cr, utils.hex_to_rgba(color))
  local x_align
  local extents = cairo_text_extents_t:create()
  tolua.takeownership(extents)
  cairo_text_extents(cr, text, extents)

  -- Truncate text if it exceeds max_width
  if maxwidth and extents.width > maxwidth then
    local truncated_text = text
    while extents.width > maxwidth and #truncated_text > 0 do
      truncated_text = truncated_text:sub(1, -2)
      local newextents = cairo_text_extents_t:create()
      tolua.takeownership(newextents)
      cairo_text_extents(cr, truncated_text..'...', newextents)
      extents = newextents
    end
    text = truncated_text..'...'
  end

  -- Set alignment
  if align == 'left' or align == 'l' then
    x_align = x
  elseif align == 'center' or align == 'c' then
    x_align = x - ((extents.width + extents.x_bearing) / 2)
  elseif align == 'right' or align == 'r' then
    x_align = x - (extents.width + extents.x_bearing)
  else
    x_align = x
  end
  cairo_move_to(cr, x_align, y)
  cairo_show_text(cr, text)
  cairo_stroke(cr)
end

return draw
