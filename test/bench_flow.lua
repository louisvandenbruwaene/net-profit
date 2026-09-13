-- What an endless map costs to solve: luajit test/bench_flow.lua
--
-- The promise a city with no edge makes is a promise about frame time. Hubs are
-- what keeps it: a customer on a hub is a number in a sum rather than a node
-- and an edge in four flow networks. This measures both sides of that so the
-- day the aggregation breaks, the number says so.
package.path = "src/?.lua;../src/?.lua;" .. package.path
local City = require("city")

local BUDGET_MS = 16

local function clock()
  return os.clock() * 1000
end

-- A company of the given size, wired the old way: one main per customer.
-- A company with a well in the ground and nothing else, which is where both
-- shapes of network start from.
local function opened()
  local c = City.new({ seed = 5150, obstacles = 0 })
  c.money = 1e9
  local house = c:clientList(true)[1]
  local spring, best
  for _, d in ipairs(c.deposits) do
    local ground = c:districtAt(d.x, d.y)
    if not d.taken and d.commodity == "water" and ground and ground.owned then
      local far = d.opening and -1 or (d.x - house.x) ^ 2 + (d.y - house.y) ^ 2
      if not best or far < best then spring, best = d, far end
    end
  end
  local well = assert(c:buySource("water", spring.x, spring.y))
  well.output, well.cap = 1e6, 1e6
  c:rebaseOrigin()
  for _, cl in ipairs(c.g.nodes) do
    if cl.alive and cl.kind == "client" then c.g:killNode(cl.id) end
  end
  return c, well
end

local function handWired(clients)
  local c, src = opened()
  local ring = 0
  for i = 1, clients do
    -- Chains of manifolds out from the well, with customers hung off them.
    if i % 5 == 1 then
      ring = ring + 1
    end
    local a = (i % 5) / 5 * math.pi * 2
    local node = c.g:addNode(src.x + math.cos(a) * 240 * ring, src.y + math.sin(a) * 240 * ring, "manifold")
    node.throughput = 999
    local cl = c.g:addNode(node.x + 40, node.y + 40, "client")
    cl.commodity, cl.demand, cl.rate, cl.clientType = "water", 2, 5, "house"
    cl.grace, cl.patience = 3, 3
    c.g:addEdge(src.id, node.id, 8)
    c.g:addEdge(node.id, cl.id, 4)
  end
  return c
end

-- The same company, hubbed: customers are covered rather than connected.
local function hubbed(clients)
  local c, src = opened()
  -- Hubs laid out the way a company actually grows: one to a neighbourhood,
  -- spread across the map, each with its own customers around it.
  local perHub = 40
  local hubs = math.ceil(clients / perHub)
  local side = math.ceil(math.sqrt(hubs))
  local trunk = src.id
  for h = 1, hubs do
    local col, row = (h - 1) % side, math.floor((h - 1) / side)
    local hub = c.g:addNode(src.x + col * 1500, src.y + row * 1500, "exchange")
    hub.throughput, hub.floor, hub.covered, hub.demandBy = 999, 0, {}, {}
    c.g:addEdge(trunk, hub.id, 120)
    trunk = hub.id
    for i = 1, math.min(perHub, clients - (h - 1) * perHub) do
      local t = i / perHub * math.pi * 2
      local reach = 200 + (i % 4) * 90
      local cl = c.g:addNode(hub.x + math.cos(t) * reach, hub.y + math.sin(t) * reach, "client")
      cl.commodity, cl.demand, cl.rate, cl.clientType = "water", 2, 5, "house"
      cl.grace, cl.patience = 3, 3
    end
  end
  return c
end

local function bench(label, city)
  city:refresh()
  local t0 = clock()
  local rounds = 8
  for _ = 1, rounds do city:refresh() end
  local ms = (clock() - t0) / rounds
  local solved = 0
  for _, n in ipairs(city.g:aliveNodes()) do
    if not n.hub then solved = solved + 1 end
  end
  print(string.format("  %-22s %5d customers  %5d nodes in the solver  %6.2f ms",
    label, #city:clientList(), solved, ms))
  return ms
end

print("a full resolve, all four trades")
local slow = bench("one main each", handWired(600))
local fast = bench("on hubs", hubbed(600))
local big = bench("on hubs, five thousand", hubbed(5000))

print()
if fast >= slow then
  print("FAIL  hubs did not make the solve cheaper")
  os.exit(1)
end
print(string.format("hubs solve %.1fx faster at 600 customers", slow / fast))
if big > BUDGET_MS then
  print(string.format("FAIL  5000 customers took %.2f ms, over the %d ms budget", big, BUDGET_MS))
  os.exit(1)
end
print(string.format("5000 customers resolve in %.2f ms, inside the %d ms budget", big, BUDGET_MS))
