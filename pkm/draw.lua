----------------------------------
-- Author: Michael Shepanski
-- Strongly derived from Zineddine SAIBI
-- Original License GPL-3.0
-- https://www.github.com/SZinedine/namoudaj-conky
----------------------------------
require "cairo"
require "imlib2"
local config = require 'config'
local utils = require 'pkm/utils'

draw = {}

-- Writes text on the screen at specified coordinates with given font properties and alignment
-- x (number): x-coordinate where the text will be written. Default is 0
-- y (number): y-coordinate where the text will be written. Default is 0
-- text (string): Text to be written. Default is an empty string
-- font (string): Name of the font to be used. Default is "DejaVu Sans"
-- size (number): Size of the font. Default is 12
-- color (number): Color of the text in hexadecimal format. Default is 0xffffff
-- bold (boolean): Set true for bold
-- italic (boolean): Set true for italic
-- alignment (string): Alignment of the text {left, center, right}
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

  local font_face = bold and CAIRO_FONT_WEIGHT_BOLD or CAIRO_FONT_WEIGHT_NORMAL
  local font_slant = italic and CAIRO_FONT_SLANT_ITALIC or CAIRO_FONT_SLANT_NORMAL
  cairo_select_font_face(cr, font, font_slant, font_face)
  cairo_set_font_size(cr, size)
  cairo_set_source_rgba(cr, utils.hex_to_rgba(color))
  local x_align
  local extents = cairo_text_extents_t:create()
  tolua.takeownership(extents)
  cairo_text_extents(cr, text, extents)
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

-- Draw Image
--  args.x (number): x-coordinate where the image will be rendered.
--  args.y (number): y-coordinate where the image will be rendered.
--  args.path (string): Path to image to be rendered.
--  args.width (number): Width of the image. Default is 0
--  args.height (number): Height of the image. Default is 0
function draw.image(args)
  local x = args.x or 0
  local y = args.y or 0

  if args.path == nil then error('path is required') end
  local img = imlib_load_image(args.path)
  if img == nil then return end
  imlib_context_set_image(img)
  if args.width or args.height then
    local origwidth = imlib_image_get_width()
    local origheight = imlib_image_get_height()
    local aspectratio = origwidth / origheight
    if args.width and not args.height then
      width = args.width
      height = width / aspectratio
    elseif args.height and not args.width then
      height = args.height
      width = height * aspectratio
    else
      width = args.width or origwidth
      height = args.height or origheight
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
--  args.color (number): Color of the rectangle in hexadecimal format. Default is 0xffffff.
function draw.rectangle(args)
  local x = args.x or 0
  local y = args.y or 0
  local width = args.width or 10
  local height = args.height or 10
  local color = args.color or 0xffffff

  cairo_set_source_rgba(cr, utils.hex_to_rgba(color))
  cairo_rectangle(cr, x, y, width, height)
  cairo_fill(cr)
end


function bar_right(args)
    local x = args.x or 0
    local y = args.y or 0
    local len = args.len or 10
    local thickness = args.thickness or 10
    local value = tonumber(args.value or 100)
    local maxvalue = args.maxvalue or 100
    local color = args.color or '#ffffff'
    local bgcolor = args.bgcolor or '#00000000'

    if value > maxvalue then value = maxvalue end
    local progress = (len / maxvalue) * value
    draw.rectangle({x=x, y=y, width=len, height=thickness, color=color})
    draw.rectangle({x=x, y=y, width=progress, height=thickness, color=bgcolor})
end

return draw