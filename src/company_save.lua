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
  data.sourceId, data.version = city.firstSource.id, 2
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
  if not ok or type(data) ~= "table" or not (data.version == 1 or data.version == 2) then
    return nil, "invalid company save"
  end
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
    data:migrate()
    data:refresh()
    return data
  end)
  if not valid then return nil, "damaged company save" end
  return city
end

-- Writing the company. The primary write goes through LOVE, which creates the
-- directory and lets the rename be atomic.
--
-- It is then mirrored into any other save directory this game is known to use,
-- but only one that already exists. Finding the company in the other location
-- (below) is enough to rescue it once; mirroring is what stops the two copies
-- drifting apart afterwards, so playing the app and running the checkout are
-- always the same company rather than two that slowly diverge.
function Save.write(city)
  local text = Save.pack(city)
  local ok, err = love.filesystem.write("company.tmp", text)
  if not ok then return nil, err end
  local root = love.filesystem.getSaveDirectory()
  local moved, moveErr = os.rename(root .. "/company.tmp", root .. "/company.lua")
  if not moved then return nil, moveErr end
  Save.mirror(text, root)
  return true
end

function Save.mirror(text, root)
  for _, dir in ipairs(Save.candidates()) do
    if dir ~= root then
      -- Only mirror where the game has actually saved before. Creating the
      -- other directory would invent a company nobody asked for.
      local probe = io.open(dir .. "/" .. Save.SAVE_NAME, "r")
      if probe then
        probe:close()
        local out = io.open(dir .. "/" .. Save.SAVE_NAME, "w")
        if out then
          out:write(text)
          out:close()
        end
      end
    end
  end
end

--------------------------------------------------------------------------------
-- Finding the company, wherever the last build left it
--------------------------------------------------------------------------------

-- LOVE puts a fused game's save directory in a different place from a game run
-- out of a source folder: ~/Library/Application Support/net-profit rather than
-- ~/Library/Application Support/LOVE/net-profit, and the equivalent on Windows
-- and Linux. That is an implementation detail of how the game happened to be
-- launched, and it must never cost anybody their company. So a save directory
-- with nothing in it falls back to the other one, and the next write adopts the
-- company into the current location while leaving the original untouched.
--
-- Written against injected lookups so the fallback can be tested without LOVE.
Save.SAVE_NAME = "company.lua"

function Save.locate(env)
  if env.primaryExists(Save.SAVE_NAME) then
    return env.primaryRead(Save.SAVE_NAME), nil
  end
  local here = env.saveDirectory or ""
  for _, dir in ipairs(env.candidates or {}) do
    -- Never re-read the directory we have already found to be empty.
    if dir ~= here then
      local text = env.fileRead(dir .. "/" .. Save.SAVE_NAME)
      if text and #text > 0 then return text, dir end
    end
  end
  return nil, nil
end

-- Every directory this game has ever kept a company in, on this platform.
function Save.candidates()
  local base = love.filesystem.getAppdataDirectory()
  local id = love.filesystem.getIdentity() or "net-profit"
  return { base .. "/LOVE/" .. id, base .. "/" .. id }
end

function Save.read()
  local text, adopted = Save.locate({
    saveDirectory = love.filesystem.getSaveDirectory(),
    candidates = Save.candidates(),
    primaryExists = function(name) return love.filesystem.getInfo(name) ~= nil end,
    primaryRead = function(name) return (love.filesystem.read(name)) end,
    fileRead = function(path)
      local f = io.open(path, "r")
      if not f then return nil end
      local data = f:read("*a")
      f:close()
      return data
    end,
  })
  if not text then return nil end
  local city, err = Save.unpack(text)
  if city and adopted then
    city:note("Company found in the previous save location and carried over")
    city.adoptedFrom = adopted
  end
  return city, err
end

return Save
