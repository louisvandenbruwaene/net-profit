-- What an endless map costs to solve: luajit test/bench_flow.lua
--
-- The promise a city with no edge makes is a promise about how fast a decision
-- settles. Every customer is a node and an edge in the flow networks, so this
-- measures a large hand-wired company and says when it stops feeling instant.
package.path = "src/?.lua;../src/?.lua;" .. package.path
local City = require("city")

-- Every customer is on a real main now (the virtual hub is gone), and a
-- refresh runs once per decision rather than once per frame, so the budget is
-- a decision that still feels instant rather than a frame.
local BUDGET_MS = 30

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

local function bench(label, city)
  city:refresh()
  local t0 = clock()
  local rounds = 8
  for _ = 1, rounds do city:refresh() end
  local ms = (clock() - t0) / rounds
  local solved = #city.g:aliveNodes()
  print(string.format("  %-22s %5d customers  %5d nodes in the solver  %6.2f ms",
    label, #city:clientList(), solved, ms))
  return ms
end

print("a full resolve, all four trades")
bench("one main each", handWired(600))
local big = bench("one main each, five thousand", handWired(5000))

print()
if big > BUDGET_MS then
  print(string.format("FAIL  5000 customers took %.2f ms, over the %d ms budget", big, BUDGET_MS))
  os.exit(1)
end
print(string.format("5000 customers resolve in %.2f ms, inside the %d ms budget", big, BUDGET_MS))
