----------------------------------
-- Author: Michael Shepanski
----------------------------------
local http = require 'socket.http'
local json = require 'pkm/json'
local ltn12 = require 'ltn12'

utils = {}

function utils.format_date(str) return utils.parse(string.format('time %s', str)) end
function utils.parse(str) return conky_parse(string.format('${%s}', str)) end
function utils.updates() return utils.parse('updates') end


-- Celsius To Fahrenheit
-- Converts a temperature from Celsius to Fahrenheit.
function utils.celsius_to_fahrenheit(value)
  return math.floor((value * 9 / 5 + 32) + 0.5)
end


-- Check Update
-- Checks if the last update was more than the update interval
function utils.check_update(last_update, update_interval)
  return not last_update or last_update + (update_interval * 0.9) < os.time()
end


-- Contains
-- Return true if value is in the list
function utils.contains(list, value)
  for _, v in ipairs(list) do
    if v == value then return true end
  end
  return false
end


-- Download Image
-- Download and returns the image data
function utils.download_image(url, filepath)
  local data = {}
  print('Downloading '..url)
  local _, code = http.request{url=url, sink=ltn12.sink.table(data)}
  if code ~= 200 then
    io.stderr:write('Failed to download image: HTTP '..code)
    return nil
  end
  filepath = filepath or os.tmpname()
  local handle = io.open(filepath, 'wb')
  if not handle then error('Failed to open file: '..filepath) end
  print('Saving '..filepath)
  handle:write(table.concat(data))
  handle:close()
  return filepath
end


-- Duration
-- Convert seconds to mm:ss format
function utils.duration(seconds)
  local minstr = math.floor(seconds / 60)
  local secstr = seconds % 60
  return string.format('%d:%02d', minstr, secstr)
end


-- Get CPU Count
-- Returns the number of 
function utils.get_cpucount()
  local cpucount = 0
  for line in io.lines('/proc/stat') do
    if line:match('cpu%d+') then cpucount = cpucount + 1 end
  end
  return cpucount
end


-- Hex to RGBA
-- Converts a hex string such as #ff000088 to an rgba tuple.
function utils.hex_to_rgba(hex)
  hex = hex:gsub('#', '')
  if #hex == 3 or #hex == 4 then
    hex = hex:gsub('.', '%1%1')
  end
  local has_alpha = #hex == 8
  local r = tonumber(hex:sub(1, 2), 16) / 255
  local g = tonumber(hex:sub(3, 4), 16) / 255
  local b = tonumber(hex:sub(5, 6), 16) / 255
  local a = has_alpha and tonumber(hex:sub(7, 8), 16) / 255 or 1
  return r, g, b, a
end


-- Init Table
-- Initialize a table with the specified value
function utils.init_table(size, value)
  local table = {}
  for i=1,size do table[i] = value end
  return table
end

-- Merge
-- Recursivly merge two tables applying values from the second table
-- into the first. Dicts will be merged; Lists replaced.
function utils.merge(t1, t2)
  for key, val in pairs(t2) do
    if type(val) == 'table' and not val[1] then
      utils.merge(t1[key], t2[key])
    else
      t1[key] = val
    end
  end
  return t1
end


-- Percent
-- Calculates the percentage of numerator over denominator.
--  numerator: The numerator value.
--  denominator: The denominator value.
--  precision: The number of decimal places to round to.
--  maxval: The maximum value to return.
--  default: The default value to return if denominator is zero.
function utils.percent(numerator, denominator, precision, maxval, default)
  precision = precision or 2
  maxval = maxval or 999.9
  default = default or 0.0
  if denominator == 0 then return default end
  local result = math.min(maxval, math.floor((numerator / denominator) * 100 * 10^precision + 0.5) / 10^precision)
  if precision == 0 then return math.floor(result)
  else return result end
end


-- Pretty Print
-- Prints a table in a human-readable format to the console
function utils.pprint(t, indent)
  indent = indent or 1
  local indentstr = string.rep('  ', indent)
  if indent == 1 then print('{') end
  for key, val in pairs(t) do
    if type(val) == 'table' then
      print(indentstr..key..': {')
      utils.pprint(val, indent + 1)
    elseif string.sub(key, 1, 1) == '_' then
      print(indentstr..key..': <size:'..#val..'>')
    elseif type(val) == 'string' then
      print(indentstr..key..': "'..val..'"')
    else
      print(indentstr..key..': '..tostring(val))
    end
  end
  print(string.rep('  ', indent-1)..'}')
end


-- Request
-- Makes an HTTP request returns the response
function utils.request(args)
  url = args.url
  asjson = args.json or false
  print('Requesting: '..url)
  local response = {}
  local result, code, headers, status = http.request{
    url=url, sink=ltn12.sink.table(response)}
  if not result then
    io.stderr:write('Request failed: '..code..'; '..url)
    return
  end
  local content = table.concat(response)
  -- Check return JSON
  if asjson then return json.decode(content)
  else return content end
end


-- Round
-- Rounds a number to the nearest integer
function utils.round(value)
  return math.floor(value + 0.5)
end


-- Run Command
-- Runs a command and returns the output lines
function utils.run_command(cmd, default)
  default = default or ''
  cmd = cmd..' 2>/dev/null'
  local handle = io.popen(cmd)
  if handle ~= nil then
    local content = handle:read('*a')
    if content ~= nil then
      handle:close()
      return content
    end
  end
  return default
end


-- Titleize
-- Capitalize the first letter of each word
function utils.titleize(str)
  return str:gsub("(%a)([%w_']*)", function(first, rest)
    return first:upper() .. rest:lower()
  end)
end


-- Trim
-- Trim white space from the string
function utils.trim(str)
  return str:match('^%s*(.-)%s*$')
end


return utils