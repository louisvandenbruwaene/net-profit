-- The play assistant, scenario by scenario: every kind of thing a person does
-- in this game, the assistant is seen doing it with the company's own cash and
-- the game's own rules. Isolated companies only; no save is read or written.
package.path = "src/?.lua;" .. package.path
local City = require("city")
local Save = require("company_save")
local A = require("autoplay")
-- Planning time depends on the machine; unlimited planning makes every run the
-- same run.
A.budget = math.huge

local checks = 0
local function check(value, message)
  assert(value, message)
  checks = checks + 1
end
local function copy(c) return assert(Save.unpack(Save.pack(c))) end

-- Steps the assistant until `done` holds, or gives up after `limit` steps.
local function play(c, limit, done)
  for _ = 1, limit do
    if done and done(c) then return c, true end
    local stop
    c, _, stop = A.step(c)
    if stop then break end
  end
  return c, done and done(c) or false
end
local function has(kind) return function(c) return #c.g:nodesOfKind(kind) > 0 end end

print("a fresh company, played for a month")
local base = City.new({ seed = 3 })
base = play(base, 4000, function(c) return c.day > 30 end)
check(base.day > 30 and not base.bankrupt, "the assistant keeps closing days without going under")
check(#base:clientList() >= 20, "it signs and connects offers as they arrive")
check(#base:shortCustomers() == 0 and base.reputation >= 70, "and keeps its customers supplied")
check(#base.g:nodesOfKind("source") >= 2, "it sinks more wells as demand grows")
check(rawget(base, "refresh") == nil and rawget(base, "stale") == nil, "a planning copy never leaks into the company")

print("electricity")
do
  local c = copy(base)
  c.money = c.money + 40000
  c = play(c, 600, function(c) return c.licences.power and #c.g:nodesOfKind("source") > 0
    and (function() for _, n in ipairs(c:clientList()) do if (n.demands or {}).power and c:fullyServed(n) then return true end end end)() end)
  check(c.licences.power, "it buys the electricity licence once the company can carry a grid")
  local plant, tower, pole
  for _, n in ipairs(c.g:aliveNodes()) do
    plant = plant or (n.kind == "source" and n.commodity == "power")
    tower = tower or (n.kind == "hvtower" and n.upgrade == "transformer")
    pole = pole or (n.kind == "pole" and n.upgrade == "transformer")
  end
  check(plant and tower and pole, "it builds a turbine, a substation and poles with transformers")
  local lit = 0
  for _, n in ipairs(c:clientList()) do if (n.demands or {}).power and c:fullyServed(n) then lit = lit + 1 end end
  check(lit > 0, "and households are supplied with electricity")
end

print("a freight hub, imported steel and an area hub")
local freight
do
  local c = copy(base)
  c.money = c.money + 30000
  c = play(c, 400, has("terminal"))
  local line
  for _, e in ipairs(c.g.edges) do if e.alive and e.bulk then line = e end end
  check(#c.g:nodesOfKind("terminal") == 1 and #c.g:nodesOfKind("dc") == 1, "it opens a road head and a freight yard")
  check(line and line.wagons.steel, "with trucks landing steel")
  c = play(c, 600, function(c) return c:materialStock("steel") >= 10 end)
  check(c:materialStock("steel") >= 10, "steel reaches the yard")
  freight = copy(c)
  -- Four enquiries in one neighbourhood are cheaper to take with a hub.
  -- Somewhere on owned ground a short way from the water network, clear enough
  -- for four houses and a hub between them.
  local cx, cy
  for _, f in ipairs(c.g:nodesOfKind("manifold")) do
    for a = 0, 11 do
      local x, y = f.x + math.cos(a * math.pi / 6) * 480, f.y + math.sin(a * math.pi / 6) * 480
      local clear = true
      for i = 0, 4 do
        local px, py = x + (i == 0 and 0 or math.cos(i * 1.57) * 140), y + (i == 0 and 0 or math.sin(i * 1.57) * 110)
        clear = clear and c:placementError(px, py) == nil
      end
      if clear then cx, cy = x, y; break end
    end
    if cx then break end
  end
  check(cx, "the fixture finds room for a neighbourhood")
  for i = 1, 4 do
    local n = assert(c:addClient("house", true))
    n.x, n.y, n.expires = cx + math.cos(i * 1.57) * 140, cy + math.sin(i * 1.57) * 110, c.day + 5
  end
  -- Pubs and factories nearby would ride on the hub too; clear them out so
  -- the neighbourhood is households.
  for _, n in ipairs(c:clientList(true)) do
    if n.clientType ~= "house" and n.clientType ~= "estate" then c:declineClient(n.id) end
  end
  c:refresh()
  c.money = c.money + 20000
  c = play(c, 300, has("exchange"))
  local hub = c.g:nodesOfKind("exchange")[1]
  check(hub and #(hub.covered or {}) >= 3, "it builds an area hub that serves a neighbourhood of offers")
end

print("an imported trade")
do
  local c = copy(freight)
  c.money = c.money + 60000
  c = play(c, 800, function(c) return c.licences.beer end)
  check(c.licences.beer, "it takes the beer licence once beer can be landed")
  local yard = c.g:nodesOfKind("dc")[1]
  local pub = assert(c:addClient("pub", true))
  pub.x, pub.y, pub.expires = yard.x + 180, yard.y + 120, c.day + 5
  c:refresh()
  c = play(c, 300, function(c) return pub.alive and not pub.prospect and c:fullyServed(pub) end)
  local signed = c.g.nodes[pub.id]
  check(signed and not signed.prospect and c:fullyServed(signed), "and serves a pub with beer from the yard")
end

print("wind, oil rigs and environment labs")
do
  local c = copy(freight)
  c.money = c.money + 80000
  c.licences.power, c.licences.oil = true, true
  c.stock.steel, c.stock.concrete = 400, 400
  -- Turbines have grown dear enough that wind is the cheaper electricity.
  c.plantsBuilt = { hydro = 6 }
  c:refresh()
  c = play(c, 600, function(c)
    for _, n in ipairs(c.g:nodesOfKind("source")) do if n.plant == "wind" then return true end end
  end)
  local wind
  for _, n in ipairs(c.g:nodesOfKind("source")) do if n.plant == "wind" then wind = n end end
  check(wind, "it builds a wind park from landed steel and concrete when that is the cheaper power")

  c = copy(freight)
  c.money = c.money + 60000
  c.licences.oil = true
  -- The oil field nearest the yard, in a district without wells.
  local field, depot = nil, c.g:nodesOfKind("dc")[1]
  for _, d in ipairs(c.deposits) do
    local land = c:districtAt(d.x, d.y)
    if d.commodity == "oil" and not d.taken and land and not land.island then
      local wells = false
      for _, w in ipairs(c.g:nodesOfKind("source")) do wells = wells or c:districtAt(w.x, w.y) == land end
      local far = math.sqrt((d.x - depot.x) ^ 2 + (d.y - depot.y) ^ 2)
      if not wells and far < 1300 and (not field or far < math.sqrt((field.x - depot.x) ^ 2 + (field.y - depot.y) ^ 2)) then field = d end
    end
  end
  if field then c:districtAt(field.x, field.y).owned = true end
  check(field, "the fixture owns an oil field")
  c:refresh()
  c = play(c, 600, function(c)
    for _, n in ipairs(c.g:nodesOfKind("source")) do if n.commodity == "oil" then return true end end
  end)
  local rig
  for _, n in ipairs(c.g:nodesOfKind("source")) do if n.commodity == "oil" then rig = n end end
  check(rig and c.g:degree(rig.id) > 0, "it sinks an oil rig on its own field and pipes it in")

  c = copy(freight)
  c.money = c.money + 40000
  c.licences.oil = true
  check(c:unlocked("works"), "two trades open the works and the lab")
  c:ownedDistricts()[1].pollution = 20
  c = play(c, 400, has("lab"))
  check(#c.g:nodesOfKind("lab") > 0, "it builds an environment lab where the ground is being fouled")
end

print("roads, highways and filling stations")
do
  local c = copy(freight)
  c.money = c.money + 40000
  check(c:unlocked("roads"), "a settled company can build roads")
  c = play(c, 600, function(c) return #c.g:nodesOfKind("interchange") >= 2 end)
  local offroads = 0
  for _, l in ipairs(c.links) do if l.alive and l.roadType == "offroad" then offroads = offroads + 1 end end
  check(#c.g:nodesOfKind("interchange") >= 2 and offroads >= 6, "it puts households on offroads to interchanges")
  c = play(c, 300, function(c)
    for _, l in ipairs(c.links) do if l.alive and l.roadType == "highway" then return true end end
  end)
  local tolled
  for _, l in ipairs(c.links) do if l.alive and l.roadType == "highway" and (l.toll or 0) > 0 then tolled = l end end
  check(tolled, "and joins the interchanges with a tolled highway")
  c:refresh()
  check((c.transit.tolls or 0) > 0, "tolls are collected on it")
  check(c:unlocked("fuel"), "people and a road open filling stations")
  c = play(c, 400, has("station"))
  local station = c.g:nodesOfKind("station")[1]
  check(station, "it opens a filling station once petrol can be landed")
  local line
  for _, e in ipairs(c.g.edges) do if e.alive and e.bulk then line = e end end
  check(line.wagons.gasoline, "with petrol trucked in for it")
end

print("buses and resorts")
do
  local c = copy(freight)
  c.money = c.money + 60000
  -- A second town next door.
  local next
  for _, d in ipairs(c.districts) do if not d.owned and not d.island and c:districtAdjacent(d) then next = d; break end end
  next.owned = true
  for _, d in ipairs(c:ownedDistricts()) do d.population = 600 end
  c:refresh()
  c = play(c, 600, function(c) for _, l in ipairs(c.links) do if l.alive and l.mode == "bus" then return true end end end)
  local bus
  for _, l in ipairs(c.links) do if l.alive and l.mode == "bus" then bus = l end end
  check(bus and #c.g:nodesOfKind("stop") >= 2, "it opens a bus route between two towns")
  c:refresh()
  check((((c.transit.byLink or {})[bus.id] or {}).trips or 0) > 0, "and people ride it")
  c.stock.concrete, c.stock.glass = 200, 200
  c:refresh()
  check(c:unlocked("resort"), "passengers on a route open resorts")
  c = play(c, 600, has("resort"))
  check(#c.g:nodesOfKind("resort") > 0, "it builds a resort once passengers travel")
end

print("long-lived networks, staff and ground")
do
  local c = copy(base)
  c.day = 70
  c.money = c.money + 60000
  local owned = #c:ownedDistricts()
  c = play(c, 1500, function(c)
    return #c.g:nodesOfKind("filtration") > 0 and #c:ownedDistricts() > owned and c:workerCount("surveyors") > 0
      and (c.crews or 0) > 0 and (c.lining or 1) > 1 and c.permits.park
  end)
  check(#c.g:nodesOfKind("filtration") > 0, "it puts filters after its wells")
  check(#c:ownedDistricts() > owned, "it buys more ground")
  check((c.crews or 0) > 0 and c:workerCount("surveyors") > 0, "it hires crews and surveyors")
  check((c.lining or 1) > 1, "it unlocks better pipe lining")
  check(c.permits.park, "it buys a terrain permit")
end

print("cash")
do
  local c = copy(base)
  c.money = c.money + 200000
  c = play(c, 600, function(c) return c:investedTotal() > 0 and c:workerCount("analysts") > 0 end)
  check(c:investedTotal() > 0 and c:workerCount("analysts") > 0, "a large surplus is invested, with an analyst")
end

print(checks .. " autoplay checks passed")
