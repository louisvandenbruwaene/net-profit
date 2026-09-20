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
  -- to the well. A well answers to a trunk only, so even the "direct" plan
  -- pays for one manifold and one trunk main before a single house is
  -- reached; each house after that needs a stub of its own, and the
  -- smallest main there is carries seven.
  local function direct(n)
    local manifoldSpot = assert(c:build(src.x + 90, src.y - 90, "manifold"))
    local trunk = c:pipeQuote(src.id, manifoldSpot.id, "water", "large")
    local capex, upkeep = City.price.manifold + trunk.total,
      City.trade.water.upkeep + trunk.metres * City.trade.water.upkeepPerM
    for i = 1, n do
      local a = math.pi * 2 * i / n
      local spot = c:build(manifoldSpot.x + math.cos(a) * 260, manifoldSpot.y + math.sin(a) * 260, "junction")
      if spot then
        local q = c:pipeQuote(manifoldSpot.id, spot.id, "water", "small")
        capex = capex + q.total
        upkeep = upkeep + City.trade.water.upkeep + q.metres * City.trade.water.upkeepPerM
        c:demolishNode(spot.id)
      end
    end
    c:demolishNode(manifoldSpot.id)
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

  -- A hub is priced like the business it replaces, not like a fitting, so a
  -- dozen houses tight around one manifold still comes in under it on the
  -- cheque: a hub is not the early move any more, it is the one a company
  -- grows into.
  local d12 = direct(12)
  local h12 = hubbed(12)
  ok("a dozen is still cheaper direct, while the network is this small", d12 < h12,
    string.format("$%d against $%d", d12, h12))

  -- What it buys instead is a lower running cost once the company is large
  -- enough that the difference is worth having.
  local d100, du100 = direct(100)
  local h100, hu100 = hubbed(100)
  ok("at real scale a hub costs less to run than a hundred private mains", hu100 < du100,
    string.format("$%.1f against $%.1f a day", hu100, du100))

  -- The reason: one big main is not priced as four small ones.
  local small = c:pipeQuote(src.id, hubSpot.id, "water", "small").total
  local large = c:pipeQuote(src.id, hubSpot.id, "water", "large").total
  ok("a large main costs less than the four small ones it replaces",
    large < small * 4, string.format("$%d against $%d", large, small * 4))
  ok("and carries no more", City.sizeOf("large").cap <= City.sizeOf("small").cap * 5)
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
  -- Beer is the last trade a chain has to be built for. The internet comes
  -- after it, and only once a reactor is running.
  ok("beer is the last chain trade", City.LICENCE_ORDER[#City.LICENCE_ORDER - 1] == "beer")
  ok("and the internet waits behind it for a reactor",
    City.LICENCE_ORDER[#City.LICENCE_ORDER] == "internet" and City.LICENCE_UNLOCK.internet == "internet")
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
  local hall
  c.permits.river=true
  for _,d in ipairs(c.districts) do
    for x=d.x+50,d.x+d.w-50,70 do
      for y=d.y+50,d.y+d.h-50,70 do
        if not hall and not c:sourceError("power",x,y,"hydro") then
          hall=assert(c:buySource("power",x,y,"hydro"))
        end
      end
    end
  end
  ok("river generation can be built and has finite output",hall and hall.output==City.PLANTS.hydro.output)

end

--------------------------------------------------------------------------------
print("a main is what it was on the day it was laid")
do
  local c = fresh()
  local src = c.firstSource
  -- A well answers to a trunk only, so the small-to-large upgrade this test
  -- is about happens one hop downstream of it, between two unrestricted
  -- structures.
  local hub = assert(c:build(src.x + 90, src.y - 90, "junction"))
  assert(c:layPipe(src.id, hub.id, "water", "large"))
  local far = assert(c:build(src.x + 260, src.y + 120, "junction"))
  local main = assert(c:layPipe(hub.id, far.id, "water", "small"))
  ok("a small main carries ten", main.cap == 10)
  ok("and nothing widens it", c:replaceQuote(main.id, "small", 1) ~= nil
    and c:replaceError(main.id, "small", 1) == "that is what is already in the ground")

  local before = c.money
  assert(c:replacePipe(main.id, "large"))
  ok("a large one can take its place", main.cap == 50)
  ok("but not a massive one, before the company is big enough",
    c:replaceError(main.id, "massive", 1) ~= nil and not c:layPipe(hub.id, far.id, "water", "massive"))
  ok("at the price of the new main less scrap on the old", c.money < before)

  -- Lining is bought once and then paid for in every metre laid with it.
  ok("a bare main leaks at the base rate", c:leakChance(main) == City.rules.leakBase)
  c.money = 1e9
  while c:liningPrice() do assert(c:upgradeQuality()) end
  ok("the company can reach sealed pipe", c.lining == #City.GRADES)
  ok("but the main in the ground has not changed",
    c:leakChance(main) == City.rules.leakBase)
  local bare = c:pipeQuote(hub.id, far.id, "water", "large", false, 1).total
  local sealed = c:pipeQuote(hub.id, far.id, "water", "large", false, #City.GRADES).total
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

--------------------------------------------------------------------------------
-- The shape of a network
--
-- These are the promises that make a company grow a branching tree with a
-- heart in it rather than a field of identical stubs. Every one of them is a
-- direction, not a magic number: break one and the game still runs, and the
-- networks people build stop looking like networks.
--------------------------------------------------------------------------------
print("a branching tree with one heart in it")
do
  -- Murray's law: cost per unit carried has to fall all the way up the ladder,
  -- or the rung above is a trap nobody should ever buy.
  local previous
  for _, spec in ipairs(City.PIPE_SIZES) do
    local perUnit = spec.trench / spec.cap
    if previous then
      ok("a " .. spec.key .. " main carries more cheaply than the size below",
        perUnit < previous, string.format("%.4f vs %.4f", perUnit, previous))
    end
    previous = perUnit
  end

  -- And the exponent is the one the physics gives, within a few per cent:
  -- cross-section, and with it the dig, goes as Q^(2/3).
  local small = City.PIPE_SIZES[1]
  for i = 2, #City.PIPE_SIZES do
    local spec = City.PIPE_SIZES[i]
    local murray = (spec.cap / small.cap) ^ (2 / 3) * small.trench
    ok("a " .. spec.key .. " main is priced on Murray's law",
      math.abs(spec.trench - murray) / murray < 0.05,
      string.format("%.2f against %.2f", spec.trench, murray))
    ok("and a " .. spec.key .. " main runs further between pumps",
      spec.reach > City.PIPE_SIZES[i - 1].reach)
  end

  -- One trunk that splits has to beat mains laid side by side for the same
  -- flow, which is the entire economic argument for a hierarchy.
  local function trench(key) return (City.sizeOf(key)).trench end
  local sideBySide = 3 * 800 * trench("medium")
  local branched = 600 * trench("massive") + 3 * 200 * trench("medium")
  ok("one trunk that branches beats three mains laid side by side",
    branched < sideBySide, string.format("%.0f against %.0f", branched, sideBySide))

  -- Growing a source has to be cheaper at the margin than commissioning
  -- another one, in every trade. This is the inversion that stops sprawl.
  for _, key in ipairs({ "water", "beer", "oil" }) do
    local t = City.trade[key]
    ok(key .. " rewards growing a source over sinking another",
      t.upgradeGrowth < t.sourceGrowth,
      string.format("%.2f against %.2f", t.upgradeGrowth, t.sourceGrowth))
  end

  -- A station takes further units, and every one of them is cheaper per unit
  -- than a second station would be.
  for name, spec in pairs(City.PLANTS) do
    if spec.unitBase then
      local second = spec.base * spec.growth / spec.output
      for u = 1, (spec.maxUnits or 1) - 1 do
        local unit = spec.unitBase * spec.unitGrowth ^ (u - 1) / spec.unitStep
        ok(name .. " unit " .. (u + 1) .. " beats a second station",
          unit < second, string.format("%.0f against %.0f per unit", unit, second))
      end
    end
  end
end

print("the heart is finite, and the channel decides how big")
do
  local c = fresh()
  -- Somewhere on the bank, and somewhere well away from it.
  local bank, inland
  for _, d in ipairs(c.districts) do
    for x = d.x + 30, d.x + d.w - 30, 30 do
      for y = d.y + 30, d.y + d.h - 30, 30 do
        local cap, fed = c:intakeCap(x, y)
        if cap and fed == "river" and not bank then bank = { x = x, y = y, cap = cap } end
        if not cap and not inland then inland = { x = x, y = y } end
      end
    end
  end
  ok("there is bank to build an intake on", bank ~= nil)
  if bank then
    ok("an intake has a finite ceiling", bank.cap < Graph.INF and bank.cap > 0, tostring(bank.cap))
    ok("and it carries more than any well ever does",
      bank.cap > require("data.infrastructure").wellCap, tostring(bank.cap))
    ok("but no more than two trunks can take away from it",
      bank.cap <= 2 * City.sizeOf("massive").cap, tostring(bank.cap))
    ok("running water needs no marked deposit under it",
      c:sourceError("water", bank.x, bank.y) == nil,
      c:sourceError("water", bank.x, bank.y))
    ok("an intake costs several times what sinking a well costs",
      c:sourceCost("water", bank.x, bank.y) > 2 * City.trade.water.sourceBase,
      c:sourceCost("water", bank.x, bank.y) .. " against " .. City.trade.water.sourceBase)

    local works = assert(c:buySource("water", bank.x, bank.y))
    ok("it is an intake and not a well", works.intake == "river")
    ok("it goes deeper than a well does", c:maxLevel(works) > City.sourceMaxLevel)
    ok("and a second one costs a great deal more than the first",
      c:sourceCost("water", bank.x, bank.y) > 2 * works.paid)

    -- It grows, and then it stops, because the channel stops it.
    while c:upgradeSource(works.id) do end
    ok("an intake grows until the channel stops it",
      works.output >= works.cap or (works.level or 1) >= c:maxLevel(works),
      works.output .. " of " .. works.cap)
    ok("and it never passes its ceiling", works.output <= works.cap)
    ok("a grown intake outgrows a well many times over",
      works.output > 2 * require("data.infrastructure").wellCap,
      tostring(works.output))
  end
end

print("a station grows rather than spreading")
do
  local c = fresh()
  assert(c:buyLicence("power"))
  -- A reactor is built out of landed materials, which is a different promise
  -- from this one. The yards are filled so the question here is only price.
  c.stock = c.stock or {}
  for _, material in ipairs(Graph.ALL) do c.stock[material] = 9999 end
  local spot
  for _, d in ipairs(c.districts) do
    if not spot and not d.island then
      local x, y = d.x + d.w / 2, d.y + d.h / 2
      if not c:sourceError("power", x, y, "nuclear") then spot = { x = x, y = y } end
    end
  end
  ok("there is room for a station", spot ~= nil)
  if spot then
    local plant = assert(c:buySource("power", spot.x, spot.y, "nuclear"))
    local first = plant.output
    ok("a station is commissioned with room for more", plant.cap > first)
    local unit = c:sourceUpgradeCost(plant)
    ok("another reactor is cheaper than another station",
      unit / select(1, c:upgradeStep(plant)) < c:plantCost("nuclear") / first,
      unit .. " for " .. select(1, c:upgradeStep(plant)))
    assert(c:upgradeSource(plant.id))
    ok("and the site carries both", plant.output > first)
    while c:upgradeSource(plant.id) do end
    ok("the site fills and then refuses", plant.level == c:maxLevel(plant))
    ok("one site carries several stations' worth",
      plant.output >= 3 * first, tostring(plant.output))
  end
end

print("a bigger main reaches further")
do
  local c = fresh()
  local a = c.g:nodesOfKind("source")[1]
  ok("the widest main reaches further than the narrowest",
    City.reachFor("massive") > City.reachFor("small"))
  if a then
    local far = c:rangeBetween(a.id, a.id, nil, "water", "massive")
    local near = c:rangeBetween(a.id, a.id, nil, "water", "small")
    ok("and the range check knows it", far > near, string.format("%.0f against %.0f", far, near))
    ok("a caller that does not name a size gets the narrowest",
      math.abs(c:rangeBetween(a.id, a.id, nil, "water") - near) < 0.001)
  end
end

print("the network can be measured for its own shape")
do
  local E = require("experience")
  local c = fresh()
  ok("a company with a handful of mains has no anatomy worth describing",
    E.anatomy(c, "water") == nil)

  -- A tree built by hand, four levels deep and branching two: a trunk off the
  -- source into a manifold, two mains off that, four off those, and eight
  -- stubs into houses. Every ratio is then known in advance, which is the only
  -- way to tell whether the measurement is measuring anything.
  local src = c.g:nodesOfKind("source")[1]
  local root = assert(c:build(src.x + 140, src.y, "manifold"))
  assert(c:layPipe(src.id, root.id, "water", "large", nil, 1))
  local stubs, feeders, mains = 0, 0, 0
  for a = -1, 1, 2 do
    local one = assert(c:build(root.x + 300, root.y + a * 320, "manifold"))
    assert(c:layPipe(root.id, one.id, "water", "large", nil, 1))
    mains = mains + 1
    for b = -1, 1, 2 do
      local two = assert(c:build(one.x + 280, one.y + b * 150, "manifold"))
      assert(c:layPipe(one.id, two.id, "water", "medium", nil, 1))
      feeders = feeders + 1
      for d = -1, 1, 2 do
        local house = assert(c:addClient("house"))
        house.x, house.y = two.x + 230, two.y + d * 70
        house.demand, house.prospect = 3, nil
        assert(c:layPipe(two.id, house.id, "water", "small", nil, 1))
        stubs = stubs + 1
      end
    end
  end
  c:refresh()

  local a = E.anatomy(c, "water")
  ok("a tree four levels deep is measured as four orders", a and a.top == 4,
    a and ("top order " .. a.top) or "nothing measured")
  if a and a.top == 4 then
    ok("every stub into a building is order one", a.band[1].n == stubs,
      a.band[1].n .. " against " .. stubs)
    ok("the mains carrying those are order two", a.band[2].n == feeders)
    ok("the mains carrying those are order three", a.band[3].n == mains)
    ok("and the trunk under all of it is order four", a.band[4].n == 1)
    local carried = true
    for o = 2, a.top do
      carried = carried and a.band[o].cap / a.band[o].n >= a.band[o - 1].cap / a.band[o - 1].n
    end
    ok("no main carries less than the ones it feeds", carried)
    ok("two mains feed each one below, which is what was built",
      math.abs(a.RB - 2) < 0.001, string.format("%.3f", a.RB))
    ok("a tree filling its ground would want mains the cube root longer",
      math.abs(a.wantLength - 2 ^ (1 / 3)) < 0.001,
      string.format("%.3f", a.wantLength))
    ok("and the dimension is withheld until the mains lengthen with order",
      (a.RL > 1.02) == (a.dimension ~= nil))
  end
end

print(string.format("\n%d passed, %d failed", pass, fail))
os.exit(fail == 0 and 0 or 1)
