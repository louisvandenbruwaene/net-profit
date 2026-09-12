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
    -- Everything refresh() recomputes stays out of the file.
    if k ~= "g" and k ~= "firstSource" and k ~= "served" and k ~= "detail"
       and k ~= "flowBy" and k ~= "produced" and k ~= "spare" and k ~= "wellSpare"
       and k ~= "capacityBy" and k ~= "unserved" and k ~= "adoptedFrom" then
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
    -- The origin is only an anchor for the camera and for new enquiries. It
    -- starts as the first well, but that well can be capped or removed like any
    -- other structure, so the save must not insist it is still a well.
    assert(data.firstSource)
    data.nodes, data.edges, data.sourceId, data.version = nil, nil, nil, nil
    setmetatable(data, City)
    data:migrate()
    data:refresh()
    return data
  end)
  if not valid then return nil, "damaged company save" end
  return city
end

--------------------------------------------------------------------------------
-- Six companies
--------------------------------------------------------------------------------

-- Six slots, so a company can be put down and come back to, and so an
-- experiment -- a big loan, a district bought early, a network built entirely
-- on havens -- does not have to be played out on the run you care about.
--
-- The slots sit beside each other as company1.lua .. company6.lua, and
-- current.lua remembers which one was last played, so the game still opens
-- straight into a company rather than into a menu.
Save.SLOTS = 6
Save.SAVE_NAME = "company.lua"      -- what the game used before there were slots
Save.LEGACY_NAME = "company.lua"
Save.CURRENT_NAME = "current.lua"

function Save.slotName(slot) return "company" .. tostring(slot) .. ".lua" end

function Save.validSlot(slot)
  return type(slot) == "number" and slot % 1 == 0 and slot >= 1 and slot <= Save.SLOTS
end

--------------------------------------------------------------------------------
-- Finding a company, wherever the last build left it
--------------------------------------------------------------------------------

-- LOVE puts a fused game's save directory in a different place from a game run
-- out of a source folder: ~/Library/Application Support/net-profit rather than
-- ~/Library/Application Support/LOVE/net-profit, and the equivalent on Windows
-- and Linux. That is an implementation detail of how the game happened to be
-- launched, and it must never cost anybody their company. So a slot that is
-- empty here falls back to the same slot in the other location.
--
-- Written against injected lookups so the fallback can be tested without LOVE.
function Save.locate(env, name)
  name = name or Save.LEGACY_NAME
  if env.primaryExists(name) then return env.primaryRead(name), nil end
  local here = env.saveDirectory or ""
  for _, dir in ipairs(env.candidates or {}) do
    -- Never re-read the directory we have already found to be empty.
    if dir ~= here then
      local text = env.fileRead(dir .. "/" .. name)
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

function Save.env()
  return {
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
  }
end

--------------------------------------------------------------------------------
-- Reading and writing a slot
--------------------------------------------------------------------------------

-- Filenames a slot will answer to, in order of preference. The company that
-- existed before there were slots is the first slot: it is adopted rather than
-- moved, so nothing is rewritten until it is actually played.
function Save.namesForSlot(slot)
  if slot == 1 then return { Save.slotName(1), Save.LEGACY_NAME } end
  return { Save.slotName(slot) }
end

function Save.readSlot(slot)
  if not Save.validSlot(slot) then return nil, "no such slot" end
  local env = Save.env()
  local text, adopted
  for _, name in ipairs(Save.namesForSlot(slot)) do
    text, adopted = Save.locate(env, name)
    if text then break end
  end
  if not text then return nil end
  local city, err = Save.unpack(text)
  if not city then return nil, err end
  city.slot = slot
  if adopted then
    city:note("Company carried over from the previous save location")
    city.adoptedFrom = adopted
  end
  return city
end

-- The primary write goes through LOVE, which creates the directory and lets the
-- rename be atomic. It is then mirrored into the other save directory when that
-- one already holds companies, so playing the app and running the checkout stay
-- one company rather than two that slowly drift apart.
function Save.writeSlot(city, slot)
  slot = slot or city.slot or 1
  if not Save.validSlot(slot) then return nil, "no such slot" end
  city.slot = slot
  local name = Save.slotName(slot)
  local text = Save.pack(city)
  local ok, err = love.filesystem.write("company.tmp", text)
  if not ok then return nil, err end
  local root = love.filesystem.getSaveDirectory()
  local moved, moveErr = os.rename(root .. "/company.tmp", root .. "/" .. name)
  if not moved then return nil, moveErr end
  Save.mirror(text, root, name)
  Save.writeCurrent(slot)
  return true
end

function Save.deleteSlot(slot)
  if not Save.validSlot(slot) then return nil, "no such slot" end
  local name = Save.slotName(slot)
  love.filesystem.remove(name)
  -- Slot one may still be standing on the pre-slot file; leaving it behind
  -- would make the deleted company reappear on the next launch.
  if slot == 1 then love.filesystem.remove(Save.LEGACY_NAME) end
  local root = love.filesystem.getSaveDirectory()
  for _, dir in ipairs(Save.candidates()) do
    if dir ~= root then
      os.remove(dir .. "/" .. name)
      if slot == 1 then os.remove(dir .. "/" .. Save.LEGACY_NAME) end
    end
  end
  return true
end

-- Does this directory hold any company at all? Used to decide where a mirror is
-- welcome: writing into a directory that has never held a save would invent a
-- company nobody asked for.
local function dirHoldsCompany(dir)
  local names = { Save.LEGACY_NAME }
  for slot = 1, Save.SLOTS do names[#names + 1] = Save.slotName(slot) end
  for _, name in ipairs(names) do
    local f = io.open(dir .. "/" .. name, "r")
    if f then f:close(); return true end
  end
  return false
end

function Save.mirror(text, root, name)
  name = name or Save.SAVE_NAME
  for _, dir in ipairs(Save.candidates()) do
    if dir ~= root and dirHoldsCompany(dir) then
      local out = io.open(dir .. "/" .. name, "w")
      if out then
        out:write(text)
        out:close()
      end
    end
  end
end

--------------------------------------------------------------------------------
-- Which slot is being played, and what is in the others
--------------------------------------------------------------------------------

function Save.writeCurrent(slot)
  if not Save.validSlot(slot) then return nil end
  local text = "return " .. tostring(slot) .. "\n"
  love.filesystem.write(Save.CURRENT_NAME, text)
  Save.mirror(text, love.filesystem.getSaveDirectory(), Save.CURRENT_NAME)
  return true
end

-- Read by pattern rather than by executing the file: it is one small integer,
-- and there is no reason to hand it an interpreter.
function Save.readCurrent()
  local text = Save.locate(Save.env(), Save.CURRENT_NAME)
  local slot = text and tonumber(string.match(text, "%d+"))
  if Save.validSlot(slot) then return slot end
  return 1
end

-- Enough of a company to choose between six of them, without the caller having
-- to know that reading a summary means loading the whole thing.
function Save.summarize(slot)
  local city = Save.readSlot(slot)
  if not city then return { slot = slot, empty = true } end
  local clients = 0
  for _, n in ipairs(city.g.nodes) do
    if n.alive and n.kind == "client" and not n.prospect then clients = clients + 1 end
  end
  local trades = {}
  for _, name in ipairs({ "water", "power", "beer", "oil" }) do
    if city.licences and city.licences[name] then trades[#trades + 1] = name end
  end
  return {
    slot = slot, empty = false,
    day = city.day, money = city.money, clients = clients,
    worth = city:valuation(), bankrupt = city.bankrupt,
    districts = #city:ownedDistricts(), trades = trades,
  }
end

function Save.summaries()
  local t = {}
  for slot = 1, Save.SLOTS do t[slot] = Save.summarize(slot) end
  return t
end

function Save.firstEmptySlot()
  for slot = 1, Save.SLOTS do
    if not Save.readSlot(slot) then return slot end
  end
  return nil
end

--------------------------------------------------------------------------------

function Save.read(slot) return Save.readSlot(slot or Save.readCurrent()) end
function Save.write(city) return Save.writeSlot(city, city.slot) end

return Save
