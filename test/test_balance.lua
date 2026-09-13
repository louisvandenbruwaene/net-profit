-- The promises the economy makes: luajit test/test_balance.lua
--
-- These are not checks that the code runs. They are checks that the game still
-- rewards the things it is meant to reward: that good network design is cheaper
-- than bad, that a new trade is reachable with what the player already has, and
-- that the map's prices point the way the map wants you to go. A rebalance that
-- breaks one of these has broken the game whether or not anything crashes.
package.path = "src/?.lua;../src/?.lua;" .. package.path
local City = require("city")
local Graph = require("graph")

local pass, fail = 0, 0
local function ok(name, cond, detail)
  if cond then pass = pass + 1
  else fail = fail + 1; print("  FAIL  " .. name .. (detail and ("  (" .. detail .. ")") or "")) end
end

-- A company that has been through its first day: the well is in and the first
-- household is signed, which is where every one of these checks starts from.
local function fresh()
  local c = City.new({ seed = 31, obstacles = 0 })
  c.money = 1e9
  for _, d in ipairs(c.districts) do d.owned = true end
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
  assert(c:buySource("water", spring.x, spring.y))
  for _, offer in ipairs(c:clientList(true)) do c:acceptClient(offer.id) end
  c:rebaseOrigin()
  return c
end

--------------------------------------------------------------------------------
print("one wide main into a hub beats a main to every house")
do
  local c = fresh()
  for _, cl in ipairs(c:clientList()) do c.g:killNode(cl.id) end
  local src = c.firstSource
  local hubSpot = assert(c:build(src.x + 700, src.y, "junction"))

  -- What n houses of demand three cost connected one by one, all the way back
  -- to the well. Each needs a main of its own, and the smallest there is
  -- carries five.
  local function direct(n)
    local capex, upkeep = 0, 0
    for i = 1, n do
      local a = math.pi * 2 * i / n
      local spot = c:build(hubSpot.x + math.cos(a) * 260, hubSpot.y + math.sin(a) * 260, "junction")
      if spot then
        local q = c:pipeQuote(src.id, spot.id, "water", "small")
        capex = capex + q.total
        upkeep = upkeep + City.trade.water.upkeep + q.metres * City.trade.water.upkeepPerM
        c:demolishNode(spot.id)
      end
    end
    return capex, upkeep
  end

  -- What they cost behind a hub: as many trunk mains as their demand needs, the
  -- hub itself, and a joining fee each.
  local function hubbed(n)
    local trunk = c:pipeQuote(src.id, hubSpot.id, "water", "large")
    local trunks = math.ceil(3 * n / trunk.capacity)
    local capex = City.price.exchange + trunks * trunk.total + n * City.hub.connect
    local upkeep = City.hub.upkeep + n * City.hub.perClient
      + trunks * (City.trade.water.upkeep + trunk.metres * City.trade.water.upkeepPerM)
    return capex, upkeep
  end

  local d4 = direct(4)
  local h4 = hubbed(4)
  ok("a handful of houses is cheaper connected directly", d4 < h4,
    string.format("$%d direct against $%d hubbed", d4, h4))

  local d12, du12 = direct(12)
  local h12, hu12 = hubbed(12)
  ok("a dozen is cheaper behind a hub", h12 < d12, string.format("$%d against $%d", h12, d12))
  ok("and cheaper to run", hu12 < du12, string.format("$%.1f against $%.1f a day", hu12, du12))

  local d20, du20 = direct(20)
  local h20, hu20 = hubbed(20)
  ok("twenty is much cheaper behind a hub", h20 < d20 * 0.8,
    string.format("$%d against $%d", h20, d20))
  ok("and half the running cost", hu20 < du20 * 0.7,
    string.format("$%.1f against $%.1f a day", hu20, du20))

  -- The reason: one big main is not priced as four small ones.
  local small = c:pipeQuote(src.id, hubSpot.id, "water", "small").total
  local large = c:pipeQuote(src.id, hubSpot.id, "water", "large").total
  ok("a large main costs less than the four small ones it replaces",
    large < small * 4, string.format("$%d against $%d", large, small * 4))
  ok("and carries the same", City.sizeOf("large").cap == City.sizeOf("small").cap * 4)
end

--------------------------------------------------------------------------------
print("the trades arrive in an order their chains can support")
do
  -- Each trade must be reachable when it is offered: everything its works eats
  -- is either water, or something an earlier trade already made possible.
  local reached = { water = true }
  for _, trade in ipairs(City.LICENCE_ORDER) do
    local recipe = City.RECIPES[City.MADE_BY[trade] or ""]
    if recipe then
      local missing = {}
      for key in pairs(recipe.inputs) do
        -- Anything a haven lands counts as reachable: that is what a haven is.
        local landed = Graph.COMMODITIES[key].landed ~= false
        local dug = City.EXTRACTOR_OF[key] ~= nil
        if not (reached[key] or landed or dug) then missing[#missing + 1] = key end
      end
      ok(trade .. " can be made when it is offered", #missing == 0,
        table.concat(missing, ", "))
    end
    reached[trade] = true
  end

  -- Power is first because it needs nothing but water, and everything else
  -- needs power.
  ok("power comes first", City.LICENCE_ORDER[1] == "power")
  local turbine = City.RECIPES.turbine
  local inputs = {}
  for key in pairs(turbine.inputs) do inputs[#inputs + 1] = key end
  ok("and a turbine hall runs on water alone",
    #inputs == 1 and inputs[1] == "water", table.concat(inputs, "+"))
  ok("beer comes last", City.LICENCE_ORDER[#City.LICENCE_ORDER] == "beer")
  ok("and it genuinely needs malt", City.RECIPES.brewery.inputs.malt ~= nil)
  ok("food genuinely needs something imported", City.RECIPES.foodworks.inputs.salt ~= nil)
  ok("and salt cannot be dug", City.EXTRACTOR_OF.salt == nil)

  -- The first trade is affordable out of an early company's takings.
  local c = fresh()
  ok("the power licence and a turbine hall fit in $1800",
    City.price.powerLicence + City.RECIPES.turbine.cost <= 1800,
    "$" .. (City.price.powerLicence + City.RECIPES.turbine.cost))
  assert(c:buyLicence("power"))
  local src = c.firstSource
  src.output, src.cap = 40, 40
  local hall = assert(c:build(src.x + 240, src.y, "works", "turbine"))
  assert(c:layPipe(src.id, hall.id, "water", "medium"))
  c:refresh()
  ok("and it is making electricity out of water", (hall.ready or 0) > 0, tostring(hall.ready))
end

--------------------------------------------------------------------------------
print("a main is what it was on the day it was laid")
do
  local c = fresh()
  local src = c.firstSource
  local far = assert(c:build(src.x + 260, src.y + 120, "junction"))
  local main = assert(c:layPipe(src.id, far.id, "water", "small"))
  ok("a small main carries five", main.cap == 5)
  ok("and nothing widens it", c:replaceQuote(main.id, "small", 1) ~= nil
    and c:replaceError(main.id, "small", 1) == "that is what is already in the ground")

  local before = c.money
  assert(c:replacePipe(main.id, "large"))
  ok("a large one can take its place", main.cap == 20)
  ok("at the price of the new main less scrap on the old", c.money < before)

  -- Lining is bought once and then paid for in every metre laid with it.
  ok("a bare main leaks at the base rate", c:leakChance(main) == City.rules.leakBase)
  c.money = 1e9
  while c:liningPrice() do assert(c:upgradeQuality()) end
  ok("the company can reach sealed pipe", c.lining == #City.GRADES)
  ok("but the main in the ground has not changed",
    c:leakChance(main) == City.rules.leakBase)
  local bare = c:pipeQuote(src.id, far.id, "water", "large", false, 1).total
  local sealed = c:pipeQuote(src.id, far.id, "water", "large", false, #City.GRADES).total
  ok("sealed pipe costs far more to lay", sealed > bare * 2.5,
    string.format("$%d against $%d", sealed, bare))
  assert(c:replacePipe(main.id, "large", #City.GRADES))
  ok("and once relaid it almost never leaks",
    c:leakChance(main) <= City.rules.leakBase * 0.05,
    string.format("%.4f", c:leakChance(main)))
end

print("the map's prices point north")
do
  local c = City.new({ seed = 31 })
  local coast, inland = c:cellAt(2, 1), c:cellAt(2, 3)
  ok("coastal ground is cheaper than ground three rows in",
    c:districtCost(coast) < c:districtCost(inland),
    string.format("$%d against $%d", c:districtCost(coast), c:districtCost(inland)))
  ok("and the frontier costs more than the core",
    c:districtCost({ ring = 3, row = 2 }) > c:districtCost({ ring = 0, row = 2 }))
end

--------------------------------------------------------------------------------
print("the game opens one door at a time")
do
  local c = City.new({ seed = 31, obstacles = 0 })
  ok("a new company is offered exactly one new trade", c:nextLicence() == "power")
  ok("hubs are not offered on day one", not c:unlocked("hub"))
  ok("havens are not offered on day one", not c:unlocked("haven"))
  ok("works are not offered on day one", not c:unlocked("works"))
  ok("and the reason is on record", c:unlockHint("hub") ~= nil)

  -- Grow the company and they arrive.
  c.money = 1e9
  for _, d in ipairs(c.districts) do d.owned = true end
  for i = 1, 8 do
    local cl = assert(c:addClient("house"))
    cl.x, cl.y = c.firstSource.x + 200 + i * 60, c.firstSource.y + 300
  end
  c:refresh()
  ok("hubs arrive with the customers", c:unlocked("hub"))
  ok("departments arrive with them too", c:unlocked("orders"))
  assert(c:buyLicence("power"))
  ok("works arrive with the second trade", c:unlocked("works"))
  ok("yards wait for a haven", not c:unlocked("yard"))

  -- And each of those has something to say the first time.
  c.guideDismissed = true
  local lesson = c:pendingLesson()
  ok("there is a lesson waiting", lesson ~= nil, lesson and lesson.key)
  if lesson then
    c:teach(lesson.key)
    ok("and it is not shown twice", c:pendingLesson() ~= lesson)
  end
end

print(string.format("\n%d passed, %d failed", pass, fail))
os.exit(fail == 0 and 0 or 1)
