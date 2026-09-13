-- Headless checks for people, trips and the businesses that move them:
-- luajit test/test_people.lua
package.path = "src/?.lua;../src/?.lua;" .. package.path
local Graph = require("graph")
local City = require("city")
local Save = require("company_save")

local pass, fail = 0, 0
local function ok(name, cond)
  if cond then pass = pass + 1 else fail = fail + 1; print("  FAIL  " .. name) end
end

-- Two neighbouring districts of six hundred people, a stop in each, and money
-- enough that none of these checks are about cash.
local function town()
  local c = City.new({ seed = 31, obstacles = 0 })
  c.money = 1e6
  c.stock = { steel = 2000, concrete = 2000, glass = 2000 }
  local west, home = c.districts[5], c.districts[6]
  west.owned = true
  west.population, home.population = 600, 600
  c:refresh()
  local a = assert(c:build(1500, 900, "stop"))
  local b = assert(c:build(500, 900, "stop"))
  return c, a, b, west, home
end

local P = City.PEOPLE
local function drivers(share) return math.floor(18 * (share or P.carShare) + 0.5) end

--------------------------------------------------------------------------------
print("people settle where the service is good")
do
  local c = City.new({ seed = 31, obstacles = 0 })
  local home = c.districts[City.MAP.start]
  ok("a new company's ground is empty", (home.population or 0) == 0)
  ok("and nothing about travel is offered yet", not c:unlocked("roads"))
  ok("so a stop cannot be built", c:build(1500, 900, "stop") == nil)
  c.money = 1e6
  local signed = {}
  for i = 1, 4 do signed[i] = assert(c:addClient("house", false, home)) end
  local function supply(amount)
    for _, n in ipairs(signed) do c.served[n.id] = amount or n.demand end
  end
  supply()
  c:growPopulation()
  local first = home.population
  ok("a district with its customers supplied gains people", first > 0)
  for _ = 1, 40 do supply(); c:growPopulation() end
  ok("and grows toward what its customers can house",
    home.population > first and home.population <= 4 * P.perCustomer)
  local full = home.population
  supply(0)
  c:growPopulation()
  ok("a district left dry loses people", home.population < full)
  ok("travel opens once a district has people enough", c:unlocked("roads"))
end

--------------------------------------------------------------------------------
print("people travel, and pay tolls on the way")
do
  local c, a, b = town()
  local total, commutes = 0, true
  for _, t in ipairs(c:tripDemands()) do
    total = total + t.count
    if t.purpose ~= "work" then commutes = false end
  end
  ok("with no resort, every trip is a commute", commutes)
  ok("six hundred people want eighteen trips a day each way", total == 36)
  ok("with no road, nobody is carried", c.transit.carried == 0 and c.transit.waiting == 36)
  local road = assert(c:layLink(a.id, b.id, "road"))
  local T = c.transit
  ok("a road carries the drivers both ways", T.carried == 2 * drivers())
  ok("and every one of them pays the toll", T.tolls == 2 * drivers() * road.toll)
  ok("the people without a car are left waiting", T.waiting == 36 - 2 * drivers())
  ok("the tolls are part of the day's revenue", c:transitIncome() == T.total and c:dailyRevenue() >= T.total)
  assert(c:setLinkPrice(road.id, 3))
  ok("a toll above what a commute is worth empties the road", c.transit.carried == 0)
  assert(c:setLinkPrice(road.id, 1))
  local capacity = P.roadCapacity
  P.roadCapacity = 3
  c:refresh()
  ok("a road carries no more than its capacity", c.transit.carried == 3)
  P.roadCapacity = capacity
  c:refresh()
  ok("the road costs something to keep", c:expenseBreakdown().transit > 0)
  local report = c:endDay()
  ok("the close books what was carried", report.tripsCarried == 2 * drivers() and report.transitIncome > 0)
end

--------------------------------------------------------------------------------
print("buses carry the people who do not drive")
do
  local c, a, b = town()
  ok("a bus needs a road first", c:layLink(a.id, b.id, "bus") == nil)
  assert(c:layLink(a.id, b.id, "road"))
  local bus = assert(c:layLink(a.id, b.id, "bus"))
  local T = c.transit
  local riders = 2 * (18 - drivers())
  ok("a bus carries everyone without a car", T.byLink[bus.id].trips == riders)
  ok("at the fare", T.fares == riders * bus.fare)
  ok("so nobody is left waiting", T.waiting == 0)
  local lone = assert(c:build(500, 1250, "stop"))
  ok("a bus will not run to a stop no road reaches",
    select(2, c:layLink(a.id, lone.id, "bus")) == "a bus needs a road between its stops")
  local cash = c.money
  assert(c:addVehicle(bus.id))
  ok("a second bus is bought", bus.vehicles == 2 and c.money == cash - City.ROUTES.bus.vehicle)
  assert(c:removeVehicle(bus.id))
  ok("and sold back", bus.vehicles == 1)
  ok("the last bus is not sold, the route is lifted", c:removeVehicle(bus.id) == nil)
end

--------------------------------------------------------------------------------
print("a filling station on the road sells petrol to the drivers")
do
  local c, a, b = town()
  ok("a station is not offered before there is a road", c:build(1000, 950, "station") == nil)
  local direct = assert(c:layLink(a.id, b.id, "road"))
  ok("it is once there is one", c:unlocked("fuel"))
  local s = assert(c:build(1000, 950, "station"))
  assert(c:layLink(a.id, s.id, "road"))
  assert(c:layLink(s.id, b.id, "road"))
  assert(c:demolishLink(direct.id))
  ok("with no petrol piped to it, a station sells nothing", c.transit.fuel == 0)
  c.served[s.id] = 30
  c:routeTrips()
  local T = c.transit
  ok("drivers get through by way of the station", T.carried == 2 * drivers())
  ok("and fill up there", T.fuel > 0 and (T.byNode[s.id].sold or 0) > 0)
  ok("never more than the tank held", T.byNode[s.id].sold <= 30)
  assert(c:setStationPrice(s.id, P.tollMax))
  c.served[s.id] = 30
  c:routeTrips()
  ok("priced far above the pump, nobody fills up", c.transit.fuel == 0)
  local feed = assert(c:build(1000, 1150, "junction"))
  assert(c:layPipe(feed.id, s.id, "gasoline", "small"))
  ok("with a petrol main tied in, a station is a customer for its tank", (function()
    local net = c.g:buildNetwork(false, "gasoline")
    for _, arc in ipairs(net.arcs) do
      if arc.cap0 == s.fuelWanted then return true end
    end
    return false
  end)())
end

--------------------------------------------------------------------------------
print("resorts pull leisure trips to the coast")
do
  local c, a, b = town()
  assert(c:layLink(a.id, b.id, "road"))
  ok("a resort is not offered before anyone rides a route", not c:unlocked("resort"))
  assert(c:layLink(a.id, b.id, "bus"))
  ok("once a route carries somebody, it is", c:unlocked("resort"))
  c.districts[2].owned = true
  ok("a resort will not stand inland",
    select(2, c:build(1500, 600, "resort")) == "a resort stands on the coast, an island or the riverbank")
  local r = assert(c:build(1500, 100, "resort"))
  assert(c:layLink(a.id, r.id, "road"))
  local T = c.transit
  ok("people travel to it for the day", ((T.byNode[r.id] or {}).visitors or 0) > 0)
  ok("and spend money there", T.resorts > 0)
  local cash = c.money
  assert(c:upgradeResort(r.id))
  ok("a resort can be built up", r.level == 2 and c.money < cash)
end

--------------------------------------------------------------------------------
print("cars sell where people live")
do
  local c, a, b, west = town()
  ok("the car works is hidden before anyone drives", c:build(1300, 1200, "works", "carworks") == nil)
  assert(c:layLink(a.id, b.id, "road"))
  c.stock.cars = 50
  local sold, income = c:sellCars()
  ok("cars in the yards are sold to the districts", sold == 50 and income == 50 * P.carPrice)
  ok("and more of a district drives", c:carShareOf(west.id) > P.carShare)
  local before = c:carShareOf(west.id)
  c:sellCars()
  ok("cars wear out, so a district keeps buying", c:carShareOf(west.id) < before)
  c:refresh()
  ok("and more drivers pay more tolls",
    c.transit.byDistrict[west.id].carried == drivers(c:carShareOf(west.id)))
  ok("a car works can be built once there is a road", c:build(1300, 1200, "works", "carworks") ~= nil)
  ok("cars are taken in at the yards", Graph.COMMODITIES.cars.role == "vehicle")
end

--------------------------------------------------------------------------------
print("later regions are towns already")
do
  local c = City.new({ seed = 77 })
  local found, near = nil, false
  for col = -6, 10 do
    for row = 4, 14 do
      local d = c:surveyCell(col, row)
      if d and d.spec and d.spec.key == "city" then
        found = found or d
        if (d.ring or 0) < 2 then near = true end
      end
    end
  end
  ok("somewhere past the second ring there is a town", found ~= nil)
  ok("and none any closer", not near)
  if found then
    ok("it arrives with people in it", (found.population or 0) >= 900 and found.founded == found.population)
    local pop = found.population
    c:growPopulation()
    ok("and nobody leaves a town the company has not bought", found.population == pop)
    ok("its ceiling is its own, not the ring's", c:populationCeiling(found) > found.population)
  end
end

--------------------------------------------------------------------------------
print("the internet waits for a reactor")
do
  local c = City.new({ seed = 31, obstacles = 0 })
  c.money = 1e6
  c.stock = { steel = 2000, concrete = 2000 }
  for _, name in ipairs({ "power", "oil", "food", "beer" }) do c.licences[name] = true end
  ok("with every other trade held, nothing is offered next", c:nextLicence() == nil)
  ok("the internet licence cannot be bought yet", c:buyLicence("internet") == nil)
  ok("and no data centre can be built", c:build(1300, 1200, "works", "datacentre") == nil)
  assert(c:buySource("power", 1300, 900, "nuclear"))
  ok("a running reactor opens it", c:nextLicence() == "internet")
  assert(c:buyLicence("internet"))
  ok("a data centre can then be built", c:build(1300, 1200, "works", "datacentre") ~= nil)
  local sub = assert(c:addClient("subscriber", true))
  ok("subscribers want the internet", sub.commodity == "internet")
  ok("and it travels by fibre", Graph.formOf("internet") == "data" and City.trade.internet.tiein ~= nil)
  ok("it is the fifth trade", Graph.TRADES[5] == "internet")
end

--------------------------------------------------------------------------------
print("a freight highway carries people as well as lorries")
do
  local c = City.new({ seed = 31, obstacles = 0 })
  c.money = 1e6
  c.districts[5].owned = true
  c.districts[5].population, c.districts[6].population = 600, 600
  local yardA = assert(c:build(1500, 900, "dc"))
  local yardB = assert(c:build(500, 900, "dc"))
  local hwy = assert(c:layPipe(yardA.id, yardB.id, "water", 1, "highway"))
  ok("drivers use the highway", ((c.transit.byEdge[hwy.id] or {}).trips or 0) == 2 * drivers())
  assert(c:setEdgeToll(hwy.id, 2))
  ok("and pay the toll set on it", c.transit.tolls == c.transit.byEdge[hwy.id].trips * 2)
end

--------------------------------------------------------------------------------
print("roads survive a save, a stop takes its roads with it, and older saves load")
do
  local c, a, b = town()
  local road = assert(c:layLink(a.id, b.id, "road"))
  assert(c:setLinkPrice(road.id, 2))
  local clone = assert(Save.unpack(Save.pack(c)))
  ok("roads come back from a save", clone.links[road.id] and clone.links[road.id].toll == 2)
  ok("with the same trips carried", clone.transit.carried == c.transit.carried)
  ok("and the population kept", clone.districts[5].population == 600)
  ok("the day's trips are worked out again, not saved", not Save.pack(c):find("byDistrict"))

  assert(c:demolishNode(a.id))
  ok("taking the stop out cuts its road", not road.alive and c.transit.carried == 0)

  c.links = nil
  for _, d in ipairs(c.districts) do d.population = nil end
  c.licences.internet = nil
  local old = assert(Save.unpack(Save.pack(c)))
  ok("a save from before people existed loads with none",
    #old.links == 0 and (old.districts[5].population or 0) == 0 and old.licences.internet == false)
end

print(string.format("\n%d passed, %d failed", pass, fail))
os.exit(fail == 0 and 0 or 1)
