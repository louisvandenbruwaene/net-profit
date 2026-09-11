-- Headless validation of the company: lua5.4 test/test_city.lua
package.path = "src/?.lua;../src/?.lua;" .. package.path
local Graph = require("graph")
local City  = require("city")

local pass, fail = 0, 0
local function check(name, got, want)
  if got == want then pass = pass + 1
  else fail = fail + 1
    print(string.format("  FAIL  %s: got %s want %s", name, tostring(got), tostring(want))) end
end
local function ok(name, cond)
  if cond then pass = pass + 1 else fail = fail + 1; print("  FAIL  " .. name) end
end

math.randomseed(7)

--------------------------------------------------------------------------------
print("a new company")
do
  local c = City.new({ obstacles = 0 })
  check("starts on day 1", c.day, 1)
  check("has starting cash", c.money, City.rules.startMoney)
  check("has one well", #c.g:nodesOfKind("source"), 1)
  check("has two customers", #c:clientList(), 2)
  ok("customers want water", c:clientList()[1].commodity == "water")
  check("nothing is served yet", c.served[c:clientList()[1].id] or 0, 0)
  check("no beer licence", c.licences.beer, false)
end

--------------------------------------------------------------------------------
print("supplying a customer earns money")
do
  local c = City.new({ obstacles = 0 })
  local src = c.firstSource
  local cust = c:clientList()[1]
  -- Put the customer within one pipe of the well so the test is about money.
  cust.x, cust.y = src.x + 200, src.y
  cust.demand = 3

  local e = c:layPipe(src.id, cust.id, "water")
  ok("pipe laid", e ~= nil)
  for _ = 1, 2 do c:upgradePipe(e.id) end
  check("pipe carries 3", c.served[cust.id], 3)

  local before = c.money
  local rep = c:endDay()
  ok("revenue includes the customer", rep.revenue >= 3 * cust.rate)
  ok("money rose", c.money > before)
  check("the day advanced", c.day, 2)
end

--------------------------------------------------------------------------------
print("commodities do not mix")
do
  local c = City.new({ obstacles = 0 })
  c.licences.beer = true
  local src = c.firstSource
  local cust = c:clientList()[1]
  cust.x, cust.y = src.x + 200, src.y
  cust.demand = 2

  -- A beer main between the same two points carries no water.
  local beer = c:layPipe(src.id, cust.id, "beer")
  ok("a beer main can share the route", beer ~= nil)
  check("but the water customer gets nothing", c.served[cust.id] or 0, 0)

  local water = c:layPipe(src.id, cust.id, "water")
  ok("a water main is a separate pipe", water ~= nil and water.id ~= beer.id)
  c:upgradePipe(water.id)
  check("now water arrives", c.served[cust.id], 2)
end

--------------------------------------------------------------------------------
print("pipes rot and can be repaired")
do
  local c = City.new({ obstacles = 0 })
  local src = c.firstSource
  local cust = c:clientList()[1]
  cust.x, cust.y = src.x + 200, src.y
  local e = c:layPipe(src.id, cust.id, "water")
  for _ = 1, 3 do c:upgradePipe(e.id) end
  check("built to capacity 4", e.cap, 4)
  check("and remembers it", e.capMax, 4)

  e.leaking = true
  c:endDay()
  check("a leak costs capacity every day", e.cap, 3)
  c:endDay()
  check("and keeps costing", e.cap, 2)

  local before = c.money
  local cost = c:repairPipe(e.id)
  ok("repair charges", cost ~= nil and c.money == before - cost)
  check("capacity restored", e.cap, 4)
  check("leak stopped", e.leaking, false)

  ok("quality lowers the leak rate",
     c:leakChance(e) == City.rules.leakBase)
  c.money = 10000
  c:upgradeQuality()
  ok("after a treatment upgrade", c:leakChance(e) < City.rules.leakBase)
  local g2 = c:reinforcePipe(e.id)
  ok("reinforcing halves it again", g2 ~= nil)
end

--------------------------------------------------------------------------------
print("customers leave when starved")
do
  local c = City.new({ obstacles = 0 })
  local cust = c:clientList()[1]
  local patience = City.CLIENTS[cust.clientType].patience
  local rep0 = c.reputation
  for _ = 1, patience do c:endDay() end
  local still = false
  for _, x in ipairs(c:clientList()) do if x.id == cust.id then still = true end end
  check("the customer is gone", still, false)
  ok("reputation fell", c.reputation < rep0)
  ok("the loss is counted", c.lostClients >= 1)
end

--------------------------------------------------------------------------------
print("money can be put to work")
do
  local c = City.new({ obstacles = 0 })
  c.money = 1000
  ok("investing takes the cash out of hand", c:invest(500) and c.money == 500)
  check("and is held", c:investedTotal(), 500)
  for _ = 1, City.rules.investDays - 1 do c:endDay() end
  check("still held before maturity", c:investedTotal(), 500)
  local before = c.money
  c:endDay()
  check("returned at maturity", c:investedTotal(), 0)
  ok("with interest paid", c.money > before + 400)

  -- Licences gate the trades.
  c.money = 5000
  ok("beer licence bought", c:buyLicence("beer"))
  ok("beer wells can then be sunk", c:buySource("beer") ~= nil)
  ok("oil is still locked", c:buySource("oil") == nil)
end

--------------------------------------------------------------------------------
print("ground blocks and taxes routes")
do
  local c = City.new({ obstacles = 0 })
  local src = c.firstSource
  -- Clear the randomly placed customers so this block tests only the ground.
  for _, cl in ipairs(c:clientList()) do c.g:killNode(cl.id) end
  c.money = 5000
  c.obstacles = { { x = src.x + 120, y = src.y, r = 70, kind = "bedrock" } }
  ok("cannot build on bedrock", c:build(src.x + 120, src.y, "junction") == nil)

  local far, why = c:build(src.x + 260, src.y, "junction")
  ok("can build past it" .. (far and "" or (": " .. tostring(why))), far ~= nil)
  local e, why = c:layPipe(src.id, far.id, "water")
  ok("and cannot pipe through it", e == nil)

  -- A river is crossable, but it costs.
  c.obstacles = { { x = src.x + 120, y = src.y, r = 70, kind = "river" } }
  local plain = c:pipeCost(src.id, far.id)
  c.obstacles = {}
  local bare = c:pipeCost(src.id, far.id)
  ok("crossing a river costs more", plain > bare)
end

print(string.format("\n%d passed, %d failed", pass, fail))
os.exit(fail == 0 and 0 or 1)
