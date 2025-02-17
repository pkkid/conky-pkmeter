----------------------------------
-- Author: Michael Shepanski
-- Strongly derived from Zineddine SAIBI
-- Original License GPL-3.0
-- https://www.github.com/SZinedine/namoudaj-conky
----------------------------------
local http = require 'socket.http'
local json = require 'pkm/json'
local ltn12 = require 'ltn12'

utils = {}

function utils.format_date(str) return utils.parse(string.format("time %s", str)) end
function utils.parse(str) return conky_parse(string.format("${%s}", str)) end
function utils.updates() return utils.parse('updates') end


-- Check Update
-- Checks if the last update was more than the update interval
function utils.check_update(last_update, update_interval)
  return not last_update or last_update + update_interval < os.time()
end


-- Contains
-- Return true if value is in the list
function utils.contains(list, value)
  for _, v in ipairs(list) do
    if v == value then return true end
  end
  return false
end


-- Hex to RGBA
-- Converts a hex string such as #ff000088 to an rgba tuple.
function utils.hex_to_rgba(hex)
  hex = hex:gsub("#", "")
  if #hex == 3 or #hex == 4 then
    hex = hex:gsub(".", "%1%1")
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


-- Pretty Print
-- Prints a table in a human-readable format to the console
function utils.pprint(t, indent)
  indent = indent or 1
  local indentstr = string.rep("  ", indent)
  if indent == 1 then print('{') end
  for k, v in pairs(t) do
    if type(v) == "table" then
      print(indentstr..k..": {")
      utils.pprint(v, indent + 1)
    elseif type(v) == 'string' then
      print(indentstr..k..': "'..v..'"')
    else
      print(indentstr..k..': '..tostring(v))
    end
  end
  print(string.rep("  ", indent-1)..'}')
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
    print('Request failed: '..code..'; '..url)
    return
  end
  local content = table.concat(response)
  if asjson then return json.decode(content)
  else return content end
end

return utils