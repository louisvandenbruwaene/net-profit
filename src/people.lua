-- people.lua -- population, trips, and the businesses that move them.
--
-- A person is not a commodity. Water goes down a main and is gone; a person
-- takes a trip and comes back tomorrow. So none of this passes through the flow
-- solver. Districts hold a population that settles where the utilities are
-- good, that population wants to travel, and the company is paid for every
-- trip its roads, routes, filling stations and resorts carry. Trips are priced
-- and routed like freight, never simulated like a person: no car is drawn
-- taking a particular road.
local Graph = require("graph")

local function km(ax, ay, bx, by)
  return math.sqrt((ax - bx) ^ 2 + (ay - by) ^ 2) / 1000
end

-- Splits a whole number across weights, the leftovers going to the largest
-- remainders, so the total is exact and the split never shuffles between days.
local function apportion(total, weights)
  local sum, out, rest, given = 0, {}, {}, 0
  for _, w in ipairs(weights) do sum = sum + w end
  for i, w in ipairs(weights) do
    local exact = sum > 0 and total * w / sum or 0
    out[i] = math.floor(exact)
    given = given + out[i]
    rest[i] = { i = i, frac = exact - out[i] }
  end
  table.sort(rest, function(x, y)
    if x.frac ~= y.frac then return x.frac > y.frac end
    return x.i < y.i
  end)
  for k = 1, math.min(#rest, total - given) do out[rest[k].i] = out[rest[k].i] + 1 end
  return out
end

return function(City)

City.PEOPLE = require("data.population").PEOPLE

-- The three bulk modes that already move freight, running seats instead.
City.ROUTES = require("data.population").ROUTES
City.ROUTE_ORDER = { "bus", "ferry", "air" }

-- Where people can board: anything on the people network standing on ground.
City.TRANSIT_NODES = { stop = true, station = true, resort = true, dc = true, terminal = true }

City.BUILD_UNLOCK = { stop = "roads", station = "fuel", resort = "resort" }
City.LICENCE_UNLOCK = { internet = "internet" }

--------------------------------------------------------------------------------
-- What has opened
--------------------------------------------------------------------------------

function City:settled()
  for _, d in ipairs(self.districts or {}) do
    if (d.population or 0) >= City.PEOPLE.tripAt then return true end
  end
  return false
end

function City:hasRoad()
  for _, l in ipairs(self.links or {}) do
    if l.alive and l.mode == "road" then return true end
  end
  for _, e in ipairs(self.g.edges) do
    if e.alive and e.bulk == "highway" then return true end
  end
  return false
end

function City:hasPassengers()
  for id, rec in pairs((self.transit or {}).byLink or {}) do
    local l = self.links[id]
    if l and l.alive and l.mode ~= "road" and rec.trips > 0 then return true end
  end
  return false
end

function City:hasReactor()
  for _, n in ipairs(self.g:nodesOfKind("source")) do
    if n.plant == "nuclear" then return true end
  end
  return false
end

--------------------------------------------------------------------------------
-- Population
--------------------------------------------------------------------------------

function City:populationCeiling(d)
  local list = City.PEOPLE.ceiling
  return math.max(list[math.min(#list, (d.ring or 0) + 1)], math.floor((d.founded or 0) * 1.6))
end

function City:customersByDistrict()
  local by = {}
  for _, c in ipairs(self:clientList()) do
    local d = self:districtAt(c.x, c.y)
    if d then
      local s = by[d.id] or { signed = 0, supplied = 0 }
      s.signed = s.signed + 1
      if self:fullyServed(c) then s.supplied = s.supplied + 1 end
      by[d.id] = s
    end
  end
  return by
end

-- Once a day. A district with enough customers to count as settled grows
-- toward what they can house, as fast as their supply is reliable, and loses
-- people for every share of them that went short. Ground nobody lives on
-- empties out, unless it was a town before the company arrived.
function City:growPopulation()
  local P = City.PEOPLE
  local by = self:customersByDistrict()
  local change = 0
  for _, d in ipairs(self.districts) do
    if d.owned and not d.island then
      local pop = d.population or 0
      local s = by[d.id]
      if s and s.signed >= P.settleAt then
        local share = s.supplied / s.signed
        local target = math.min(self:populationCeiling(d), math.max(d.founded or 0, s.signed * P.perCustomer))
        if pop < target then
          pop = pop + (target - pop) * P.growth * share
        else
          pop = pop - (pop - target) * P.growth
        end
        pop = pop - pop * P.decline * (1 - share)
      elseif not d.founded then
        pop = pop * (1 - P.decline)
      end
      local before = d.population or 0
      d.population = math.floor(pop + 0.5)
      change = change + d.population - before
    end
  end
  return change
end

function City:carShareOf(id)
  local d = self.districts[id]
  return (d and d.carShare) or City.PEOPLE.carShare
end

-- Cars reach the yards like any other delivery and are sold at the close to
-- the districts with room for more drivers. They wear out, so a district that
-- stops buying slowly goes back to taking the bus.
function City:sellCars()
  local P = City.PEOPLE
  self.stock = self.stock or {}
  local stock = self:materialStock("cars")
  local sold = 0
  for _, d in ipairs(self.districts) do
    if d.carShare then d.carShare = math.max(P.carShare, d.carShare - P.carWear) end
    local pop = d.population or 0
    if d.owned and pop >= P.tripAt and sold < stock then
      local share = d.carShare or P.carShare
      local room = math.floor(pop * (P.carShareMax - share) / P.peoplePerCar)
      local take = math.max(0, math.min(stock - sold, room))
      if take > 0 then
        d.carShare = share + take * P.peoplePerCar / pop
        sold = sold + take
      end
    end
  end
  if sold == 0 then return 0, 0 end
  self.stock.cars = stock - sold
  local income = sold * P.carPrice
  self.money = self.money + income
  self:note("%d car%s sold to the districts for $%d", sold, sold == 1 and "" or "s", income)
  return sold, income
end

--------------------------------------------------------------------------------
-- Trips
--------------------------------------------------------------------------------

-- Every trip anybody wants to take today, as groups. Commuters go to the
-- nearest populated districts, weighted by how many people live there; a
-- resort pulls leisure trips from everywhere in its reach. The list is a pure
-- function of the company, so two refreshes of the same day agree.
function City:tripDemands()
  local P = City.PEOPLE
  local places = {}
  for _, d in ipairs(self.districts or {}) do
    if not d.island and (d.population or 0) >= P.tripAt then places[#places + 1] = d end
  end
  local resorts = self.g:nodesOfKind("resort")
  local list = {}
  for _, a in ipairs(places) do
    local ax, ay = a.x + a.w / 2, a.y + a.h / 2
    local total = math.floor(a.population * P.tripsPerCapita)

    local pulls, pullWeights = {}, {}
    for _, r in ipairs(resorts) do
      local dist = km(ax, ay, r.x, r.y)
      if dist * 1000 <= P.resortPull * (r.level or 1) then
        pulls[#pulls + 1] = { node = r, km = dist }
        pullWeights[#pullWeights + 1] = (r.level or 1) / (0.5 + dist)
      end
    end
    local leisure = #pulls > 0 and math.floor(total * P.leisureShare) or 0

    local others, weights = {}, {}
    for _, b in ipairs(places) do
      if b ~= a then others[#others + 1] = { d = b, km = km(ax, ay, b.x + b.w / 2, b.y + b.h / 2) } end
    end
    table.sort(others, function(x, y)
      if x.km ~= y.km then return x.km < y.km end
      return x.d.id < y.d.id
    end)
    for i = #others, P.workReach + 1, -1 do others[i] = nil end
    for i, o in ipairs(others) do weights[i] = o.d.population / (0.5 + o.km) end

    for i, n in ipairs(apportion(#others > 0 and (total - leisure) or 0, weights)) do
      if n > 0 then
        local o = others[i]
        list[#list + 1] = { from = a.id, to = o.d.id, purpose = "work", count = n, km = o.km,
                            willingness = P.work.base + P.work.perKm * o.km }
      end
    end
    for i, n in ipairs(apportion(leisure, pullWeights)) do
      if n > 0 then
        local p = pulls[i]
        list[#list + 1] = { from = a.id, resort = p.node.id, purpose = "leisure", count = n, km = p.km,
                            willingness = P.leisure.base + P.leisure.perKm * p.km }
      end
    end
  end
  table.sort(list, function(x, y)
    if x.willingness ~= y.willingness then return x.willingness > y.willingness end
    if x.from ~= y.from then return x.from < y.from end
    return (x.to and ("d" .. x.to) or ("r" .. x.resort)) < (y.to and ("d" .. y.to) or ("r" .. y.resort))
  end)
  return list
end

-- Routes today's trips over the roads and passenger routes, best-paying first.
-- Each group takes the cheapest way there that is still worth the trip: a
-- driver compares tolls and petrol with the fares, somebody without a car can
-- only take the fares. Every road and route has a daily capacity, and what does
-- not fit waits, the way an unsupplied customer does.
function City:routeTrips()
  local P = City.PEOPLE
  local T = { trips = 0, carried = 0, waiting = 0, tolls = 0, fares = 0, fuel = 0, resorts = 0, total = 0,
              byLink = {}, byEdge = {}, byNode = {}, byDistrict = {} }
  self.transit = T
  local demands = self:tripDemands()
  for _, t in ipairs(demands) do T.trips = T.trips + t.count end
  T.waiting = T.trips
  if #demands == 0 then return T end

  local adj, any = {}, false
  local function arc(a, b, kind, ref, price, cap, road)
    local na, nb = self.g.nodes[a], self.g.nodes[b]
    if not (na and na.alive and nb and nb.alive) then return end
    local x = { a = a, b = b, kind = kind, ref = ref, price = price, left = cap, road = road,
                km = km(na.x, na.y, nb.x, nb.y) }
    adj[a] = adj[a] or {}
    adj[b] = adj[b] or {}
    table.insert(adj[a], x)
    table.insert(adj[b], x)
    any = true
  end
  for _, l in ipairs(self.links or {}) do
    if l.alive then
      if l.mode == "road" then
        -- Daily private vehicles are routed by road_model.
      elseif City.ROUTES[l.mode] and (l.mode ~= "bus" or self:roadConnected(l.a,l.b)) then
        arc(l.a, l.b, "link", l, l.fare or 0, (l.vehicles or 1) * City.ROUTES[l.mode].seats, false)
      end
    end
  end
  for _, e in ipairs(self.g.edges) do
    if e.alive and e.bulk == "highway" then
      -- A freight service is not a physical road.
    end
  end
  if not any then return T end

  local access = {}
  for _, n in ipairs(self.g:aliveNodes()) do
    if City.TRANSIT_NODES[n.kind] and adj[n.id] then
      local d = self:districtAt(n.x, n.y)
      if d then
        access[d.id] = access[d.id] or {}
        table.insert(access[d.id], n.id)
      end
    end
  end

  local tank = {}
  for _, s in ipairs(self.g:nodesOfKind("station")) do tank[s.id] = self.served[s.id] or 0 end

  local driveKm = P.fuelPerKm * P.pumpPrice
  local function cheapest(sources, goal, road)
    local dist, prev, done = {}, {}, {}
    for _, s in ipairs(sources) do dist[s] = 0 end
    while true do
      local u, best
      for id, v in pairs(dist) do
        if not done[id] and (not best or v < best or (v == best and id < u)) then u, best = id, v end
      end
      if not u then return nil end
      if goal[u] then
        local path, x = {}, u
        while prev[x] do
          path[#path + 1] = prev[x].arc
          x = prev[x].from
        end
        return best, path, x
      end
      done[u] = true
      for _, a in ipairs(adj[u]) do
        if a.road == road and a.left > 0 then
          local v = a.a == u and a.b or a.a
          local c = best + a.price + (road and a.km * driveKm or 0)
          if not done[v] and (dist[v] == nil or c < dist[v]) then
            dist[v] = c
            prev[v] = { from = u, arc = a }
          end
        end
      end
    end
  end

  local function stationsOn(path, start)
    local ids, seen = {}, {}
    local function add(id)
      if tank[id] and not seen[id] then
        seen[id] = true
        ids[#ids + 1] = id
      end
    end
    add(start)
    for i = #path, 1, -1 do
      add(path[i].a)
      add(path[i].b)
    end
    return ids
  end

  local function book(list, id, field, amount)
    local rec = list[id] or {}
    rec[field] = (rec[field] or 0) + amount
    list[id] = rec
    return rec
  end

  for _, t in ipairs(demands) do
    local sources = access[t.from]
    local goal = {}
    if t.resort then
      if adj[t.resort] then goal[t.resort] = true end
    else
      for _, id in ipairs(access[t.to] or {}) do goal[id] = true end
    end
    local carried = 0
    if sources and next(goal) then
      local drivers = math.floor(t.count * self:carShareOf(t.from) + 0.5)
      for _, party in ipairs({ { left = drivers, car = true }, { left = t.count - drivers, car = false } }) do
        for _ = 1, 12 do
          if party.left <= 0 then break end
          local options = {}
          local cost, path, start = cheapest(sources, goal, false)
          if cost and cost <= t.willingness then
            options[#options + 1] = { cost = cost, path = path, start = start, road = false }
          end
          if party.car then
            cost, path, start = cheapest(sources, goal, true)
            if cost and cost <= t.willingness then
              options[#options + 1] = { cost = cost, path = path, start = start, road = true }
            end
          end
          if #options == 0 then break end
          table.sort(options, function(x, y)
            if x.cost ~= y.cost then return x.cost < y.cost end
            return x.road and not y.road
          end)
          local pick = options[1]
          local amount = party.left
          for _, a in ipairs(pick.path) do amount = math.min(amount, a.left) end
          if amount <= 0 then break end

          local pathKm = 0
          for _, a in ipairs(pick.path) do
            a.left = a.left - amount
            pathKm = pathKm + a.km
            local rec = book(a.kind == "link" and T.byLink or T.byEdge, a.ref.id, "trips", amount)
            rec.income = (rec.income or 0) + a.price * amount
            if pick.road then T.tolls = T.tolls + a.price * amount
            else T.fares = T.fares + a.price * amount end
          end

          if pick.road then
            local want = amount * pathKm * P.fuelPerKm
            for _, id in ipairs(stationsOn(pick.path, pick.start)) do
              if want <= 0 then break end
              local s = self.g.nodes[id]
              local price = s.price or P.pumpPrice
              local keen = math.max(0, 1 - P.priceSensitivity * math.max(0, price - P.pumpPrice))
              local take = math.min(tank[id], want * keen)
              if take > 0 then
                tank[id] = tank[id] - take
                want = want - take / keen
                T.fuel = T.fuel + take * price
                book(T.byNode, id, "sold", take)
              end
            end
          end

          if t.resort then
            T.resorts = T.resorts + amount * P.resortSpend * (self.g.nodes[t.resort].level or 1)
            book(T.byNode, t.resort, "visitors", amount)
          end
          book(T.byNode, pick.start, "boarded", amount)
          party.left = party.left - amount
          carried = carried + amount
        end
      end
    end
    T.carried = T.carried + carried
    local rec = book(T.byDistrict, t.from, "trips", t.count)
    rec.carried = (rec.carried or 0) + carried
  end

  T.waiting = T.trips - T.carried
  T.total = T.tolls + T.fares + T.fuel + T.resorts
  return T
end

function City:transitIncome()
  return math.floor(((self.transit or {}).total or 0) + 0.5)
end

function City:linkUpkeep(l)
  if l.mode == "road" then
    return City.PEOPLE.roadUpkeep + self:nodeDistance(l.a, l.b) * City.PEOPLE.roadUpkeepPerM
  end
  return City.ROUTES[l.mode].running * (l.vehicles or 1)
end

function City:transitBill()
  local total = 0
  for _, l in ipairs(self.links or {}) do
    if l.alive then total = total + self:linkUpkeep(l) end
  end
  for _, n in ipairs(self.g:aliveNodes()) do
    if n.kind == "resort" then total = total + City.PEOPLE.resortUpkeep * (n.level or 1)
    elseif n.kind == "station" then total = total + City.PEOPLE.stationUpkeep end
  end
  return total
end

--------------------------------------------------------------------------------
-- Roads and routes
--------------------------------------------------------------------------------

function City:transitNode(id)
  local n = self.g.nodes[id]
  return n and n.alive and City.TRANSIT_NODES[n.kind] and n or nil
end

-- The river reaches the sea, so a berth on its bank is as good as one on the
-- coast itself: a boat does not care which water it is floating on.
function City:afloat(n)
  local d = self:districtAt(n.x, n.y)
  return self:onCoast(n.x, n.y) or (d and d.island) or self:nearRiver(n.x, n.y)
end

function City:linkBetween(a, b, mode)
  for _, l in ipairs(self.links or {}) do
    if l.alive and l.mode == mode and ((l.a == a and l.b == b) or (l.a == b and l.b == a)) then return l end
  end
  return nil
end

function City:roadConnected(a, b)
  local adj = {}
  local function join(x, y)
    adj[x] = adj[x] or {}
    adj[y] = adj[y] or {}
    table.insert(adj[x], y)
    table.insert(adj[y], x)
  end
  for _, l in ipairs(self.links or {}) do
    if l.alive and l.mode == "road" then join(l.a, l.b) end
  end
  for _, e in ipairs(self.g.edges) do
    if e.alive and e.bulk == "highway" then join(e.a, e.b) end
  end
  local seen, queue = { [a] = true }, { a }
  for _, u in ipairs(queue) do
    if u == b then return true end
    for _, v in ipairs(adj[u] or {}) do
      if not seen[v] and self.g.nodes[v].alive then
        seen[v] = true
        queue[#queue + 1] = v
      end
    end
  end
  return false
end

function City:linkQuote(a, b, mode)
  if mode == "road" then
    local na, nb = self.g.nodes[a], self.g.nodes[b]
    local mult = self:crossingCost(na.x, na.y, nb.x, nb.y) or 1
    return math.ceil(City.PEOPLE.roadTiein * 2 + self:nodeDistance(a, b) * City.PEOPLE.roadPerM * mult)
  end
  return (City.ROUTES[mode] or {}).vehicle or 0
end

function City:linkError(a, b, mode)
  local na, nb = self:transitNode(a), self:transitNode(b)
  if not (na and nb) then return "roads connect houses, businesses and road junctions; bus services connect bus stops" end
  if a == b then return "a route needs two ends" end
  if mode == "road" then
    if not self:unlocked("roads") then return "nobody travels yet" end
    if self:linkBetween(a, b, "road") then return "that road already exists" end
    if self:nodeDistance(a, b) > City.PEOPLE.roadRange then return "too far for one road: put a matching junction between" end
    local mult, blocker = self:crossingCost(na.x, na.y, nb.x, nb.y)
    if not mult then return "cannot cross " .. string.lower(City.OBSTACLES[blocker.kind].name) end
    return nil
  end
  local spec = City.ROUTES[mode]
  if not spec then return "no such route" end
  if not self:unlocked("routes") then return "passenger routes open once a road is built" end
  if self:linkBetween(a, b, mode) then return "that route already runs" end
  if spec.needs == "road" and not self:roadConnected(a, b) then
    return "a bus needs a road between its stops"
  elseif spec.needs == "water" then
    if not self:havenOf("port") then return "a ferry needs a harbour" end
    if not (self:afloat(na) and self:afloat(nb)) then return "a ferry calls at the coast, the river or an island" end
  elseif spec.needs == "air" and not (na.haven == "airfield" and nb.haven == "airfield") then
    return "an airline flies between air freight aprons"
  end
  return nil
end

function City:layLink(a, b, mode)
  local err = self:linkError(a, b, mode)
  if err then return nil, err end
  local cost = self:linkQuote(a, b, mode)
  if cost > self.money then return nil, "not enough cash" end
  self:spend(cost)
  self.links = self.links or {}
  local l = { id = #self.links + 1, a = a, b = b, mode = mode, alive = true, paid = cost }
  if mode == "road" then
    l.roadType = self.buildRoadType or "road"
    l.toll = l.roadType == "highway" and City.PEOPLE.tollDefault or 0
    self:note("Road laid for $%d; highway toll $%d per vehicle", cost, l.toll)
  else
    l.fare, l.vehicles = City.ROUTES[mode].fare, 1
    self:note("%s opened for $%d, at $%d a seat", City.ROUTES[mode].name, cost, l.fare)
  end
  self.links[l.id] = l
  self:refresh()
  return l
end

function City:setLinkPrice(id, value)
  local l = (self.links or {})[id]
  if not (l and l.alive) then return nil, "no such road or route" end
  if type(value) ~= "number" or value ~= value then return nil, "invalid price" end
  local max = l.mode == "road" and City.PEOPLE.tollMax or City.ROUTES[l.mode].max
  value = math.max(0, math.min(max, math.floor(value)))
  if l.mode == "road" then l.toll = value else l.fare = value end
  self:refresh()
  return l
end

function City:addVehicle(id)
  local l = (self.links or {})[id]
  if not (l and l.alive and City.ROUTES[l.mode]) then return nil, "only a passenger route runs vehicles" end
  if (l.vehicles or 1) >= City.PEOPLE.maxVehicles then return nil, "eight is the most one route runs" end
  local cost = City.ROUTES[l.mode].vehicle
  if cost > self.money then return nil, "not enough cash" end
  self:spend(cost)
  l.vehicles = (l.vehicles or 1) + 1
  l.paid = (l.paid or 0) + cost
  self:refresh()
  return l
end

function City:removeVehicle(id)
  local l = (self.links or {})[id]
  if not (l and l.alive and City.ROUTES[l.mode]) then return nil, "only a passenger route runs vehicles" end
  if (l.vehicles or 1) <= 1 then return nil, "a route runs at least one: lift it instead" end
  local spec = City.ROUTES[l.mode]
  l.vehicles = l.vehicles - 1
  l.paid = math.max(0, (l.paid or 0) - spec.vehicle)
  self.money = self.money + math.floor(spec.vehicle * 0.4)
  self:refresh()
  return l
end

function City:demolishLink(id)
  local l = (self.links or {})[id]
  if not (l and l.alive) then return nil, "no such road or route" end
  local refund = math.floor((l.paid or 0) * 0.4)
  l.alive = false
  self.money = self.money + refund
  self:refresh()
  return refund
end

-- A structure taken out takes every road and route tied into it, the way a
-- demolished junction takes its mains: cut, not lifted.
function City:cutLinks(id)
  for _, l in ipairs(self.links or {}) do
    if l.alive and (l.a == id or l.b == id) then l.alive = false end
  end
end

function City:setEdgeToll(id, value)
  local e = self.g.edges[id]
  if not (e and e.alive and e.bulk == "highway") then return nil, "only a highway is tolled" end
  if type(value) ~= "number" or value ~= value then return nil, "invalid toll" end
  e.toll = math.max(0, math.min(City.PEOPLE.tollMax, math.floor(value)))
  self:refresh()
  return e
end

--------------------------------------------------------------------------------
-- Filling stations and resorts
--------------------------------------------------------------------------------

function City:setStationPrice(id, value)
  local n = self.g.nodes[id]
  if not (n and n.alive and n.kind == "station") then return nil, "no such station" end
  if type(value) ~= "number" or value ~= value then return nil, "invalid price" end
  n.price = math.max(0, math.min(City.PEOPLE.tollMax, math.floor(value)))
  self:refresh()
  return n
end

function City:resortSiteError(x, y)
  local d = self:districtAt(x, y)
  if self:onCoast(x, y) or (d and d.island) or self:nearRiver(x, y) then return nil end
  return "a resort stands on the coast, an island or the riverbank"
end

function City:resortUpgradeCost(n)
  return math.ceil(City.PEOPLE.resortBase * City.PEOPLE.resortGrowth ^ ((n.level or 1) - 1))
end

function City:resortMaterials(n)
  local level = n.level or 1
  return { concrete = 40 * level, glass = 20 * level }
end

function City:upgradeResort(id)
  local n = self.g.nodes[id]
  if not (n and n.alive and n.kind == "resort") then return nil, "no such resort" end
  if (n.level or 1) >= City.PEOPLE.resortLevels then return nil, "the resort is as grand as it gets" end
  local cost = self:resortUpgradeCost(n)
  if cost > self.money then return nil, "not enough cash" end
  local bill = self:resortMaterials(n)
  local short = self:materialError(bill)
  if short then return nil, short end
  self:spend(cost)
  self:spendMaterials(bill)
  n.level = (n.level or 1) + 1
  n.paid = (n.paid or 0) + cost
  self:note("Resort %d built up to level %d for $%d", n.id, n.level, cost)
  self:refresh()
  return n
end

end
