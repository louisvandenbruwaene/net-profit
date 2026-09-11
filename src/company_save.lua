local City = require("city")
local Graph = require("graph")
local Save = {}

local function encode(value)
  local kind = type(value)
  if kind == "number" or kind == "boolean" then return tostring(value) end
  if kind == "string" then return string.format("%q", value) end
  assert(kind == "table", "unsupported save value")
  local result = {"{"}
  for key, item in pairs(value) do
    if type(item) ~= "function" then
      result[#result + 1] = "[" .. encode(key) .. "]=" .. encode(item) .. ","
    end
  end
  result[#result + 1] = "}"
  return table.concat(result)
end

function Save.pack(city)
  local data = {}
  for k, v in pairs(city) do
    if k ~= "g" and k ~= "firstSource" and k ~= "served" and k ~= "detail" and k ~= "flowBy" then
      data[k] = v
    end
  end
  data.nodes, data.edges = city.g.nodes, city.g.edges
  data.sourceId, data.version = city.firstSource.id, 1
  return "return " .. encode(data)
end

function Save.unpack(text)
  local chunk, err
  if loadstring then
    chunk, err = loadstring(text, "company save")
    if chunk then setfenv(chunk, {}) end
  else
    chunk, err = load(text, "company save", "t", {})
  end
  if not chunk then return nil, err end
  local ok, data = pcall(chunk)
  if not ok or type(data) ~= "table" or data.version ~= 1 then return nil, "invalid company save" end
  local valid, city = pcall(function()
    assert(type(data.day) == "number" and type(data.money) == "number" and type(data.rng) == "number")
    local g = Graph.new()
    g.nodes, g.edges = data.nodes, data.edges
    for id, n in ipairs(g.nodes) do
      assert(n.id == id and Graph.KINDS[n.kind] and type(n.x) == "number" and type(n.y) == "number")
      g.adj[id] = {}
    end
    for id, e in ipairs(g.edges) do
      assert(e.id == id and g.nodes[e.a] and g.nodes[e.b] and e.cap >= 0)
      table.insert(g.adj[e.a], id)
      table.insert(g.adj[e.b], id)
    end
    data.g, data.firstSource = g, g.nodes[data.sourceId]
    assert(data.firstSource and data.firstSource.kind == "source")
    data.nodes, data.edges, data.sourceId, data.version = nil, nil, nil, nil
    setmetatable(data, City)
    data:refresh()
    return data
  end)
  if not valid then return nil, "damaged company save" end
  return city
end

function Save.write(city)
  local ok, err = love.filesystem.write("company.tmp", Save.pack(city))
  if not ok then return nil, err end
  local root = love.filesystem.getSaveDirectory()
  return os.rename(root .. "/company.tmp", root .. "/company.lua")
end

function Save.read()
  if not love.filesystem.getInfo("company.lua") then return nil end
  local text, err = love.filesystem.read("company.lua")
  if not text then return nil, err end
  return Save.unpack(text)
end

return Save
