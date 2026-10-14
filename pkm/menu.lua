----------------------------------
-- Author: Michael Shepanski
----------------------------------
local config = require 'config'
local draw = require 'pkm/draw'
local socket = require 'socket'
local utils = require 'pkm/utils'

local menu = {}
menu.items = nil          -- Items of the open menu, nil when closed
menu.rows = {}            -- Row positions from the last draw
menu.MARGIN = 2           -- Gap kept between the menu and the window edge
menu.ROW_HEIGHT = 18      -- Height of a title or item row
menu.SEPARATOR_HEIGHT = 7 -- Height of a separator row
menu.TIMEOUT = 10         -- Close after this many seconds without mouse activity

-- Open
-- Opens a menu at x,y; items are {label, action, checked}, {title} or {separator}
function menu.open(x, y, items)
  menu.items = items
  menu.x, menu.y = x, y
  menu.box, menu.rows, menu.hover = nil, {}, nil
  menu.touched = socket.gettime()
end

-- Close
-- Closes the open menu
function menu.close()
  menu.items, menu.box, menu.rows, menu.hover = nil, nil, {}, nil
end

-- Row At
-- Returns the row under x,y from the last draw, or nil
function menu.row_at(x, y)
  local box = menu.box
  if not box or x < box.x or x > box.x + box.width then return nil end
  for _, row in ipairs(menu.rows) do
    if row.y <= y and y < row.y + row.height then return row end
  end
end

-- Mouse
-- Handles a mouse event while the menu is open; returns true when consumed
function menu.mouse(event)
  if not menu.items then return false end
  menu.touched = socket.gettime()
  local row = menu.row_at(event.x, event.y)
  if event.type == 'mouse_move' then
    menu.hover = row and row.item.action and row.item or nil
    return true
  end
  if event.type ~= 'button_down' or not menu.box then return true end
  if row then
    if row.item.action then
      menu.close()
      local ok, err = pcall(row.item.action)
      if not ok then io.stderr:write('Menu action failed: '..tostring(err)..'\n') end
    end
    return true
  end
  -- Clicking outside closes the menu; a right click may then open a new one
  menu.close()
  return event.button ~= 'right'
end

-- Layout
-- Sizes the menu to its labels and clamps it inside the conky window
function menu.layout()
  local has_checks, width, height = false, 110, 6
  for _, item in ipairs(menu.items) do
    if item.checked ~= nil then has_checks = true end
  end
  local indent = has_checks and 24 or 10
  for _, item in ipairs(menu.items) do
    if item.separator then
      height = height + menu.SEPARATOR_HEIGHT
    else
      local text = item.label or item.title
      local textwidth = draw.text_width{text=text, size=item.title and 10 or nil}
      width = math.max(width, (item.title and 10 or indent) + textwidth + 12)
      height = height + menu.ROW_HEIGHT
    end
  end
  local winwidth, winheight = conky_window.width, conky_window.height
  width = math.min(width, winwidth - menu.MARGIN * 2)
  local x = math.min(menu.x, winwidth - menu.MARGIN - width)
  local y = menu.y
  if y + height > winheight - menu.MARGIN then y = y - height end
  y = math.min(y, winheight - menu.MARGIN - height)
  menu.box = {x=math.max(menu.MARGIN, x), y=math.max(menu.MARGIN, y), width=width,
    height=height, indent=indent}
end

-- Draw
-- Draws the open menu above the widgets
function menu.draw()
  if not menu.items then return end
  if socket.gettime() - menu.touched > menu.TIMEOUT then return menu.close() end
  menu.layout()
  local box = menu.box
  draw.rectangle{x=box.x, y=box.y, width=box.width, height=box.height, color=config.menu_bg}
  cairo_set_source_rgba(cr, utils.hex_to_rgba(config.menu_border))
  cairo_set_line_width(cr, 1)
  cairo_rectangle(cr, box.x+0.5, box.y+0.5, box.width-1, box.height-1)
  cairo_stroke(cr)
  menu.rows = {}
  local y = box.y + 3
  for _, item in ipairs(menu.items) do
    if item.separator then
      local liney = y + math.floor(menu.SEPARATOR_HEIGHT / 2) + 0.5
      draw.line{x1=box.x+6, y1=liney, x2=box.x+box.width-6, y2=liney, color=config.menu_border}
      y = y + menu.SEPARATOR_HEIGHT
    else
      local maxwidth = box.width - 20
      if item.title then
        draw.text{x=box.x+10, y=y+13, text=item.title, size=10, color=config.subheader,
          maxwidth=maxwidth}
      else
        if item == menu.hover then
          draw.rectangle{x=box.x+2, y=y, width=box.width-4, height=menu.ROW_HEIGHT,
            color=config.header_bg}
        end
        if item.checked ~= nil then
          draw.checkbox{x=box.x+10, y=y+4, size=9, checked=item.checked, color=config.label}
        end
        draw.text{x=box.x+box.indent, y=y+13, text=item.label, color=config.value,
          maxwidth=maxwidth-box.indent+10}
      end
      table.insert(menu.rows, {item=item, y=y, height=menu.ROW_HEIGHT})
      y = y + menu.ROW_HEIGHT
    end
  end
end

return menu
