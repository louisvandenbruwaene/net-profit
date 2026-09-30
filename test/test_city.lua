-- Headless validation of the company: lua5.4 test/test_city.lua
package.path = "test/?.lua;src/?.lua;../src/?.lua;" .. package.path
local Graph = require("graph")
local City  = require("city")
City.FLAT_USAGE = true -- these checks are about flow: customers draw their whole contract

local T = require("support")
local check, ok = T.same, T.ok


-- Most of these checks are about a company that is already trading, so this
-- plays the opening for them: the well goes in on the marked spring and the
-- household that asked for water is signed.
local function opened(opts)
  local c = City.new(opts or { obstacles = 0 })
  -- The spring the opening put there, which is the one within reach of the
  -- household that asked for water.
  local house = c:clientList(true)[1]
  local spring, best
  for _, d in ipairs(c.deposits) do
    local ground = c:districtAt(d.x, d.y)
    if not d.taken and d.commodity == "water" and ground and ground.owned then
      local far = d.opening and -1 or (d.x - house.x) ^ 2 + (d.y - house.y) ^ 2
      if not best or far < best then spring, best = d, far end
    end
  end
  c.money = c.money + 600
  assert(c:buySource("water", spring.x, spring.y))
  for _, offer in ipairs(c:clientList(true)) do c:acceptClient(offer.id) end
  c:rebaseOrigin()
  c.money = City.rules.startMoney
  return c
end

-- A well answers to a trunk main only; most of these checks are about what a
-- main itself does, not about that rule, so they route through a junction
-- built beside the well rather than test the rule over and over.
local function trunk(c, src)
  local hub = assert(c:build(src.x + 90, src.y - 90, "manifold"))
  assert(c:layPipe(src.id, hub.id, "water", "large"))
  return hub
end

math.randomseed(7)

--------------------------------------------------------------------------------
print("a new company")
do
  local c = City.new({ obstacles = 0 })
  check("starts on day 1", c.day, 1)
  check("has starting cash", c.money, City.rules.startMoney)
  -- A company starts as a job rather than a business: a marked spring, one
  -- household asking to be connected, and nothing built.
  check("has no well yet", #c.g:nodesOfKind("source"), 0)
  check("has nobody signed", #c:clientList(), 0)
  check("but somebody has asked", #c:clientList(true), 1)
  ok("and they want water", c:clientList(true)[1].commodity == "water")
  local spring
  for _, d in ipairs(c.deposits) do
    local ground = c:districtAt(d.x, d.y)
    if d.commodity == "water" and ground and ground.owned then spring = d; break end
  end
  ok("the survey marked water on the home ground", spring ~= nil)
  ok("and the opening step is to sink a well", c:tutorialStep().key == "well")
  check("no beer licence", c.licences.beer, false)
end

--------------------------------------------------------------------------------
print("supplying a customer earns money")
do
  local c = opened()
  local src = c.firstSource
  local hub = trunk(c, src)
  local cust = c:clientList()[1]
  -- Put the customer within one pipe of the well so the test is about money.
  cust.x, cust.y = src.x + 200, src.y
  cust.demand = 3

  local e = c:layPipe(hub.id, cust.id, "water", "small")
  ok("pipe laid", e ~= nil)
  check("a small main carries ten", e.cap, 10)
  check("the customer takes what they asked for", c.served[cust.id], 3)

  local before = c.money
  local rep = c:endDay()
  ok("revenue includes the customer", rep.revenue >= 3 * cust.rate)
  ok("money rose", c.money > before)
  check("the day advanced", c.day, 2)
end

--------------------------------------------------------------------------------
print("commodities do not mix")
do
  local c = opened()
  c.licences.beer = true
  c.money = c.money + 1000
  local src = c.firstSource
  local hub = trunk(c, src)
  -- The well has one water outlet. A beer stub still must not carry its water.
  local cust = c:clientList()[1]
  cust.x, cust.y = src.x + 200, src.y
  cust.demand = 2

  -- A beer main between the same two points carries no water.
  local beer = c:layPipe(hub.id, cust.id, "beer")
  ok("a beer main can share the route", beer ~= nil)
  check("but the water customer gets nothing", c.served[cust.id] or 0, 0)

  local water = c:layPipe(hub.id, cust.id, "water")
  ok("a water main is a separate pipe", water ~= nil and water.id ~= beer.id)
  check("now water arrives", c.served[cust.id], 2)
end

--------------------------------------------------------------------------------
print("pipes rot and can be repaired")
do
  local c = opened()
  local src = c.firstSource
  local hub = trunk(c, src)
  -- A house only ever takes the smallest main there is, and this test is
  -- about what a main does as it wears and grows, not about serving a
  -- customer, so it runs the check on an ordinary junction instead.
  local far = assert(c:build(src.x + 260, src.y + 120, "junction"))
  local e = c:layPipe(hub.id, far.id, "water", "medium")
  check("built as a medium main", e.cap, 30)
  check("and remembers it", e.capMax, 30)

  e.leaking = true
  c:endDay()
  check("a leak costs capacity every day", e.cap, 29)
  c:endDay()
  check("and keeps costing", e.cap, 28)

  local before = c.money
  local cost = c:repairPipe(e.id)
  ok("repair charges", cost ~= nil and c.money == before - cost)
  check("capacity restored", e.cap, 30)
  check("leak stopped", e.leaking, false)

  -- Nothing widens a main. A bigger one goes in its place, and the old one is
  -- worth something as scrap.
  c.money = 10000
  local was = e.paid
  ok("a medium main can be replaced with a large one", c:replacePipe(e.id, "large") ~= nil)
  check("which carries fifty", e.cap, 50)
  ok("and cost less than the whole job", e.paid > was)

  -- Lining is fixed when the main is laid, and only better lining lowers risk.
  ok("a bare main leaks at the base rate", c:leakChance(e) == City.rules.leakBase)
  ok("the company cannot lay lined pipe yet", c.lining == 1)
  c.money = 40000
  ok("until it buys the knowledge", c:upgradeQuality() ~= nil)
  ok("which does nothing to pipe already in the ground",
     c:leakChance(e) == City.rules.leakBase)
  assert(c:replacePipe(e.id, "large", 2))
  ok("but a main relaid with it leaks far less", c:leakChance(e) < City.rules.leakBase)
end

--------------------------------------------------------------------------------
print("customers leave when starved")
do
  local c = opened()
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
  local c = opened()
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
  -- The licence buys the right to lay beer mains and to run a brewery. Beer
  -- still does not come out of the ground, whatever is done to it.
  local brewed, why = c:buySource("beer")
  ok("but beer is brewed, never dug", brewed == nil and why:find("brewery") ~= nil)
  ok("oil is still locked", c:buySource("oil") == nil)

  -- Water and oil come out of marked ground and nowhere else.
  -- The map is seeded from the clock, so the test picks a deposit that is
  -- actually clear rather than assuming the first one is.
  local free
  for _, d in ipairs(c.deposits) do
    local ground = c:districtAt(d.x, d.y)
    if not d.taken and d.commodity == "water" and ground and ground.owned
       and not c:placementError(d.x, d.y) then free = d; break end
  end
  ok("the survey marked water on the home ground", free ~= nil)
  -- Somewhere on the same ground, well clear of the mark.
  local home = c:districtAt(free.x, free.y)
  local dry
  for _, spot in ipairs({ { free.x, home.y + 110 }, { free.x, home.y + home.h - 110 },
                          { home.x + 110, free.y }, { home.x + home.w - 110, free.y } }) do
    if not c:placementError(spot[1], spot[2]) and not c:seamAt(spot[1], spot[2]) then
      dry = { x = spot[1], y = spot[2] }; break
    end
  end
  ok("there is dry ground to try", dry ~= nil)
  ok("a well off the mark finds nothing",
    select(2, c:buySource("water", dry.x, dry.y)) == "no water here: sink on a marked deposit")
  local dug, dugWhy = c:buySource("water", free.x, free.y)
  ok("and a well on the mark opens it" .. (dug and "" or (": " .. tostring(dugWhy))),
    dug ~= nil and dug.seam == true)
  ok("the deposit caps what it can ever give", dug and dug.cap == 50)
end

--------------------------------------------------------------------------------
print("ground blocks and taxes routes")
do
  local c = opened()
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
  local plain = c:pipeCost(src.id, far.id, "water")
  c.obstacles = {}
  local bare = c:pipeCost(src.id, far.id, "water")
  ok("crossing a river costs more", plain > bare)
end

T.finish()
