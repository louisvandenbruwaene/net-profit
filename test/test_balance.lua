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

local function fresh()
  local c = City.new({ seed = 31, obstacles = 0 })
  c.money = 1e9
  for _, d in ipairs(c.districts) do d.owned = true end
  return c
end

--------------------------------------------------------------------------------
print("one wide main into a hub beats a main to every house")
do
  local c = fresh()
  for _, cl in ipairs(c:clientList()) do c.g:killNode(cl.id) end
  local src = c.firstSource
  local hubSpot = assert(c:build(src.x + 700, src.y, "junction"))

  -- What n houses cost connected one by one, all the way back to the well.
  local function direct(n)
    local capex, upkeep = 0, 0
    for i = 1, n do
      local a = math.pi * 2 * i / n
      local spot = c:build(hubSpot.x + math.cos(a) * 260, hubSpot.y + math.sin(a) * 260, "junction")
      if spot then
        local q = c:pipeQuote(src.id, spot.id, "water", 3)
        capex = capex + q.total
        upkeep = upkeep + City.trade.water.upkeep + q.metres * City.trade.water.upkeepPerM
        c:demolishNode(spot.id)
      end
    end
    return capex, upkeep
  end

  -- What they cost behind a hub: one trunk, the hub, and a joining fee each.
  local function hubbed(n)
    local trunk = c:pipeQuote(src.id, hubSpot.id, "water", math.min(24, 3 * n))
    local capex = City.price.exchange + trunk.total + n * City.hub.connect
    local upkeep = City.hub.upkeep + n * City.hub.perClient
      + City.trade.water.upkeep + trunk.metres * City.trade.water.upkeepPerM
    return capex, upkeep
  end

  local d4 = direct(4)
  local h4 = hubbed(4)
  ok("a handful of houses is cheaper connected directly", d4 < h4,
    string.format("$%d direct against $%d hubbed", d4, h4))

  local d9, du9 = direct(9)
  local h9, hu9 = hubbed(9)
  ok("nine is cheaper behind a hub", h9 < d9, string.format("$%d against $%d", h9, d9))
  ok("and cheaper to run", hu9 < du9, string.format("$%.1f against $%.1f a day", hu9, du9))

  local d20 = direct(20)
  local h20 = hubbed(20)
  ok("twenty is far cheaper behind a hub", h20 < d20 * 0.6,
    string.format("$%d against $%d", h20, d20))

  -- The reason: a wide main is not priced as a bundle of narrow ones.
  local one = c:pipeQuote(src.id, hubSpot.id, "water", 1).total
  local wide = c:pipeQuote(src.id, hubSpot.id, "water", 12).total
  ok("twelve units of bore cost less than twelve mains", wide < one * 12 * 0.5,
    string.format("$%d against $%d", wide, one * 12))
end

--------------------------------------------------------------------------------
print("a new trade needs the licence, one building and water")
do
  -- Every trade a company can take on must be startable with what it already
  -- has: water, and one building that needs nothing else.
  for _, trade in ipairs({ "power", "beer", "food" }) do
    local c = fresh()
    local recipe = City.RECIPES[City.MADE_BY[trade] or ""]
    ok(trade .. " has a building that makes it", recipe ~= nil)
    if recipe then
      local needs = {}
      for key in pairs(recipe.base) do needs[#needs + 1] = key end
      ok(trade .. " is made from water and nothing else",
        #needs == 1 and needs[1] == "water", table.concat(needs, "+"))
      local bill = 0
      for _, amount in pairs(recipe.materials or {}) do bill = bill + amount end
      ok(trade .. " needs no materials to enter", bill == 0)

      -- And the money works out from a modest bank balance.
      c.money = 2600
      ok(trade .. " licence and building fit in $2600",
        City.price[trade .. "Licence"] + recipe.cost <= 2600,
        "$" .. (City.price[trade .. "Licence"] + recipe.cost))
      assert(c:buyLicence(trade))
      local src = c.firstSource
      src.output, src.cap = 40, 40
      local works = assert(c:build(src.x + 240, src.y, "works", City.MADE_BY[trade]))
      assert(c:layPipe(src.id, works.id, "water", 12))
      c:refresh()
      ok(trade .. " is being made on water alone", (works.ready or 0) > 0,
        tostring(works.ready))
    end
  end
end

--------------------------------------------------------------------------------
print("the chain is a reward, not an entry fee")
do
  local c = fresh()
  assert(c:buyLicence("beer"))
  local src = c.firstSource
  src.output, src.cap = 60, 60
  local brew = assert(c:build(src.x + 240, src.y, "works", "brewery"))
  assert(c:layPipe(src.id, brew.id, "water", 24))
  c:refresh()
  local plain = brew.ready
  ok("water alone makes beer", plain == City.RECIPES.brewery.rate, tostring(plain))

  -- Add power and the same building makes more of it.
  assert(c:buyLicence("power"))
  local hall = assert(c:build(src.x + 180, src.y + 200, "works", "turbine"))
  assert(c:layPipe(src.id, hall.id, "water", 16))
  assert(c:layPipe(hall.id, brew.id, "power", 8))
  c:refresh()
  ok("and power makes more of it", brew.ready > plain,
    string.format("%d against %d", brew.ready, plain))
end

--------------------------------------------------------------------------------
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
