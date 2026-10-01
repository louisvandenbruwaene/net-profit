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

-- Today's travel. Every resident of a home picks another building to go to,
-- the same pick all day and after a save (it is hashed from the day, never
-- drawn from the RNG), and goes the cheapest way there they have: driving if
-- they have a car and the roads join up, or walking to a stop, a quay or an
-- airfield and riding a bus, a ferry or a plane, or driving to one, parking
-- and riding on. On the way they pay what the company charges: highway and
-- bridge tolls per car, a fare per seat, petrol at the stations they pass. A
-- trip that would cost more than it is worth to them, or that nothing joins
-- up, they do not make.
local HOUSEHOLD = { house = true, home = true, estate = true, subscriber = true }
local function pick(seed)
  seed = (seed * 48271) % 2147483647
  return seed, (seed - 1) / 2147483646
end

-- The network people travel on, keyed so it is rebuilt only when a road,
-- route, toll, fare or fleet changes.
local netCache = setmetatable({}, { __mode = "k" })
local function travelNetwork(self)
  local sig = { #self.g.nodes }
  for _, l in ipairs(self.links or {}) do
    sig[#sig + 1] = l.alive and (l.id .. (l.toll or 0) .. "/" .. (l.fare or 0) .. "/" .. (l.vehicles or 1)) or "x"
  end
  sig = table.concat(sig, ",")
  local c = netCache[self]
  if c and c.sig == sig then return c end
  local P = City.PEOPLE
  local net = { sig = sig, car = {}, ride = {}, boards = {}, nodes = {}, trees = {}, near = {} }
  local function add(list, a, b, arc)
    list[a] = list[a] or {}; list[b] = list[b] or {}
    table.insert(list[a], arc); table.insert(list[b], arc)
    net.nodes[a] = true; net.nodes[b] = true
  end
  for _, l in ipairs(self.links or {}) do
    local na, nb = self.g.nodes[l.a], self.g.nodes[l.b]
    if l.alive and na and nb and na.alive and nb.alive then
      local km_ = self:nodeDistance(l.a, l.b) / 1000
      if l.mode == "road" then
        local toll = City.tolled(l) and (l.toll or P.tollDefault) or 0
        local fuel = km_ * P.fuelPerKm * P.pumpPrice
        add(net.car, l.a, l.b, { l = l, km = km_, money = toll, cost = toll + fuel + km_ * P.timeCost.car })
      elseif City.ROUTES[l.mode] and (l.mode ~= "bus" or self:roadConnected(l.a, l.b)) then
        local fare = l.fare or City.ROUTES[l.mode].fare
        add(net.ride, l.a, l.b, { l = l, km = km_, money = fare, cost = fare + km_ * (P.timeCost[l.mode] or 0.5),
          seats = (l.vehicles or 1) * City.ROUTES[l.mode].seats })
        net.boards[l.a] = true; net.boards[l.b] = true
      end
    end
  end
  -- Where the network can be reached on foot, by 500 m cell.
  net.cells = {}
  for id in pairs(net.nodes) do
    local n = self.g.nodes[id]
    local k = math.floor(n.x / 500) * 65536 + math.floor(n.y / 500)
    net.cells[k] = net.cells[k] or {}
    table.insert(net.cells[k], id)
  end
  netCache[self] = net
  return net
end

-- The network places within walking distance of a building, and the walk.
local function walkable(self, net, n)
  local cached = net.near[n.id]
  if cached then return cached end
  local P = City.PEOPLE
  local out = {}
  local cx, cy = math.floor(n.x / 500), math.floor(n.y / 500)
  for ix = cx - 1, cx + 1 do
    for iy = cy - 1, cy + 1 do
      for _, id in ipairs(net.cells[ix * 65536 + iy] or {}) do
        local m = self.g.nodes[id]
        local d = math.sqrt((m.x - n.x) ^ 2 + (m.y - n.y) ^ 2)
        if d <= P.walkReach then out[#out + 1] = { id = id, cost = d / 1000 * P.timeCost.walk } end
      end
    end
  end
  net.near[n.id] = out
  return out
end

-- Cheapest ways from one home, with and without its car, to every place on
-- the network. State 1 is at the wheel (roads only), state 2 on foot or in a
-- seat (routes only); a driver may park anywhere and carry on as a passenger.
local function tree(self, net, home, withCar)
  local key = home.id * 2 + (withCar and 1 or 0)
  if net.trees[key] then return net.trees[key] end
  local dist, prev = { {}, {} }, { {}, {} }
  local heap = Graph.heap()
  local function push(state, id, cost, from)
    if dist[state][id] == nil or cost < dist[state][id] then
      dist[state][id] = cost; prev[state][id] = from
      heap.push(cost, state * 1e7 + id)
    end
  end
  if withCar and net.car[home.id] then push(1, home.id, 0, false) end
  for _, w in ipairs(walkable(self, net, home)) do
    if net.boards[w.id] then push(2, w.id, w.cost, false) end
  end
  local done = {}
  while true do
    local cost, key2 = heap.pop()
    if not cost then break end
    local state, u = math.floor(key2 / 1e7), key2 % 1e7
    if not done[key2] and cost == dist[state][u] then
      done[key2] = true
      if state == 1 then
        for _, a in ipairs(net.car[u] or {}) do
          local v = a.l.a == u and a.l.b or a.l.a
          push(1, v, cost + a.cost, { state = 1, node = u, arc = a })
        end
        if net.boards[u] then push(2, u, cost, { state = 1, node = u }) end
      else
        for _, a in ipairs(net.ride[u] or {}) do
          local v = a.l.a == u and a.l.b or a.l.a
          push(2, v, cost + a.cost, { state = 2, node = u, arc = a })
        end
      end
    end
  end
  local t = { dist = dist, prev = prev }
  net.trees[key] = t
  return t
end

-- The places worth going to, each with how strongly it draws people.
local function destinations(self)
  local P = City.PEOPLE
  local list, total = {}, 0
  for _, n in ipairs(self.g:aliveNodes()) do
    if not n.prospect and (n.kind == "client" or n.kind == "works" or n.kind == "resort") then
      local w = n.kind == "resort" and P.pull.resort * (n.level or 1) or n.kind == "works" and P.pull.works
        or n.shop and P.pull.shop or (City.PROJECT_BY and City.PROJECT_BY[n.clientType or ""]) and P.pull.project or P.pull.other
      total = total + w
      list[#list + 1] = { n = n, upto = total }
    end
  end
  return list, total
end
local function choose(list, total, u)
  local lo, hi, want = 1, #list, u * total
  while lo < hi do
    local mid = math.floor((lo + hi) / 2)
    if list[mid].upto < want then lo = mid + 1 else hi = mid end
  end
  return list[lo] and list[lo].n
end

local function residentTrips(self, T, travel)
  local P = City.PEOPLE
  local residents = require("data.shops").RESIDENTS
  local net = travelNetwork(self)
  if not next(net.nodes) then return end
  local list, total = destinations(self)
  if #list < 2 then return end
  local seats = {}
  local function book(tbl, id, field, amount)
    local rec = tbl[id] or {}
    rec[field] = (rec[field] or 0) + amount
    tbl[id] = rec
    return rec
  end
  for _, home in ipairs(self:clientList()) do
    if HOUSEHOLD[home.clientType] and not home.prospect then
      local near = walkable(self, net, home)
      if net.car[home.id] or #near > 0 then
        local d = self:districtAt(home.x, home.y)
        local share = math.max(P.carFloor, d and d.carShare or 0)
        local seed = (((self.seed or 1) + home.id * 104729 + (self.day or 1) * 13007) % 2147483646) + 1
        local count = residents[home.clientType] or 3
        for r = 1, count do
          local u, hasCar
          seed, u = pick(seed)
          local target = choose(list, total, u)
          if target == home then target = choose(list, total, (u + 0.5) % 1) end
          seed, hasCar = pick(seed)
          hasCar = hasCar < share
          if target and target ~= home then
            T.trips = T.trips + 1
            if r == 1 then book(T.byNode, home.id, "destination", 0).destination = target.id end
            local t = tree(self, net, home, hasCar)
            -- Arrive at the door by car, or anywhere within a walk of it.
            local best, bestState, bestNode, walk = nil, nil, nil, 0
            local c = t.dist[1][target.id]
            if c then best, bestState, bestNode = c, 1, target.id end
            for _, w in ipairs(walkable(self, net, target)) do
              for state = 1, 2 do
                local c2 = t.dist[state][w.id]
                if c2 and (not best or c2 + w.cost < best) then best, bestState, bestNode, walk = c2 + w.cost, state, w.id, w.cost end
              end
            end
            local km_ = math.sqrt((target.x - home.x) ^ 2 + (target.y - home.y) ^ 2) / 1000
            local worth = P.tripBase + P.tripPerKm * km_
            if best and best <= worth then
              -- Back along the tree: the legs, newest first.
              local legs, state, at = {}, bestState, bestNode
              while true do
                local p = t.prev[state][at]
                if not p then break end
                if p.arc then legs[#legs + 1] = { state = p.state, arc = p.arc, from = p.node } end
                state, at = p.state, p.node
              end
              -- Walking the whole way is no trip on anything the company runs.
              local full = #legs == 0
              for _, leg in ipairs(legs) do
                if leg.state == 2 and (seats[leg.arc.l.id] or leg.arc.seats) <= 0 then full = true end
              end
              if not full then
                local road, roadFrom = {}, nil
                for i = #legs, 1, -1 do
                  local leg = legs[i]
                  local l = leg.arc.l
                  if leg.state == 1 then road[#road + 1] = l; roadFrom = roadFrom or leg.from
                  else
                    seats[l.id] = (seats[l.id] or leg.arc.seats) - 1
                    local rec = book(T.byLink, l.id, "trips", 1)
                    rec.income = (rec.income or 0) + leg.arc.money
                    T.fares = T.fares + leg.arc.money
                    -- Boarded where the ride began: the first seat after a walk or a drive.
                    if i == #legs or legs[i + 1].state == 1 then book(T.byNode, leg.from, "boarded", 1) end
                  end
                end
                if #road > 0 then travel(road, 1, "car", roadFrom) end
                if target.kind == "resort" then
                  T.resorts = T.resorts + P.resortSpend * (target.level or 1)
                  book(T.byNode, target.id, "visitors", 1)
                end
                T.carried = T.carried + 1
                if d then local rec = book(T.byDistrict, d.id, "carried", 1) end
              end
            end
            if d then book(T.byDistrict, d.id, "trips", 1) end
          end
        end
      end
    end
  end
end

-- The day's travel: every resident's trip, then every truck and bus driven
-- over the road network it actually has, paying tolls and buying fuel.
function City:routeTrips()
  local T = { trips = 0, carried = 0, waiting = 0, tolls = 0, fares = 0, fuel = 0, resorts = 0, total = 0,
              byLink = {}, byEdge = {}, byNode = {}, byDistrict = {}, journeys = {} }
  -- Every drive as the way it went, for the map: the roads in order from
  -- where it set out, and how many made it.
  local journeyAt = {}
  local function journey(path, count, vehicle, from)
   if not from then return end
   local ids = {}
   for i, l in ipairs(path) do ids[i] = l.id end
   local key = vehicle .. ":" .. from .. ":" .. table.concat(ids, ",")
   local j = journeyAt[key]
   if not j then j = { links = ids, from = from, vehicle = vehicle, count = 0 }; journeyAt[key] = j; T.journeys[#T.journeys + 1] = j end
   j.count = j.count + count
  end
  self.transit = T
  local tank={}
  for _,n in ipairs(self.g:nodesOfKind('station')) do tank[n.id]=self.served[n.id] or 0 end
  local function travel(path,count,vehicle,from)
   journey(path,count,vehicle,from)
   local distance,stations,seen=0,{},{}
   for _,l in ipairs(path) do
    distance=distance+self:nodeDistance(l.a,l.b)/1000
    for _,id in ipairs({l.a,l.b}) do if tank[id] and not seen[id] then stations[#stations+1]=id; seen[id]=true end end
    local rec=T.byLink[l.id] or {trips=0,income=0}; T.byLink[l.id]=rec
    rec.trips=(rec.trips or 0)+count; rec[vehicle]=(rec[vehicle] or 0)+count
    local toll=City.tolled(l) and (l.toll or City.PEOPLE.tollDefault)*count or 0
    rec.income=(rec.income or 0)+toll; T.tolls=T.tolls+toll
   end
   -- Drivers fill up at the going rate without a second thought; every dollar
   -- over it turns a share of them away, to try the next station on the way.
   local P=City.PEOPLE
   local want=distance*count*P.fuelPerKm
   for _,id in ipairs(stations) do
    if want<=0 then break end
    local price=self.g.nodes[id].price or P.pumpPrice
    local keen=math.max(0,1-P.priceSensitivity*math.max(0,price-P.pumpPrice))
    local take=math.min(tank[id],want*keen)
    T.byNode[id]=T.byNode[id] or {}
    if take>0 then
     tank[id]=tank[id]-take; want=want-take
     T.fuel=T.fuel+take*price
     T.byNode[id].sold=(T.byNode[id].sold or 0)+take
    end
   end
  end
  residentTrips(self, T, travel)
  -- Works, depots and shops on the roads send a van out to somewhere they
  -- trade with, the way they always have.
  local places={}; local attached={}
  for _,l in ipairs(self.links or {}) do if l.alive and l.mode=='road' then attached[l.a]=true; attached[l.b]=true end end
  for _,n in ipairs(self.g:aliveNodes()) do if attached[n.id] and City.TRANSIT_NODES[n.kind] and not City.ROAD_JUNCTIONS[n.kind] and not n.prospect then places[#places+1]=n end end
  for _,n in ipairs(places) do
   local vehicle=(n.kind=='works' or n.kind=='depot' or n.kind=='dc' or n.kind=='client' and (n.clientType=='factory' or n.clientType=='market')) and 'truck'
   if vehicle and #places>1 then
    local seed=(((self.seed or 1)+n.id*104729+(self.day or 1)*13007)*48271)%2147483647
    local choices={}
    for _,d in ipairs(places) do
     if d.id~=n.id and self:dailyDestinationAllowed(d,vehicle) then choices[#choices+1]=d end
    end
    local target=#choices>0 and choices[seed%#choices+1]
    local path=target and self:roadPath(n.id,target.id,vehicle)
    if path then travel(path,1,vehicle,n.id) end
   end
  end
  for _,e in ipairs(self.g.edges) do
   if e.alive and (e.bulk=='highway' or e.goodsRoad) and not e.transportBlocked then
    local trucks=0; for key in pairs(e.wagons or {[e.commodity]=e.cap}) do trucks=trucks+math.ceil(math.abs((self.edgeFlowBy[key] or {})[e.id] or 0)/City.MODES.highway.wagonCap) end
    local path=self:roadPath(e.a,e.b,'truck'); if path and trucks>0 then travel(path,trucks,'truck',e.a) end
   end
  end
  for _,l in ipairs(self.links) do if l.alive and l.mode=='bus' then local path=self:roadPath(l.a,l.b,'bus'); if path then travel(path,l.vehicles or 1,'bus',l.a) end end end
  T.waiting=T.trips-T.carried; T.total=T.tolls+T.fares+T.fuel+T.resorts; return T
end

function City:transitIncome()
  return math.floor(((self.transit or {}).total or 0) + 0.5)
end

function City:linkUpkeep(l)
  -- A goods road is paid for as the freight line it carries.
  if l.goodsEdge then return 0 end
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

function City:linkQuote(a, b, mode)
  if mode == "road" then
    local na, nb = self.g.nodes[a], self.g.nodes[b]
    local variant = self.buildRoadType or 'road'
    local mult = self:crossingCost(na.x, na.y, nb.x, nb.y, variant == 'bridge') or 1
    local cost = math.ceil(City.PEOPLE.roadTiein * 2 + self:nodeDistance(a, b) * City.PEOPLE.roadPerM * mult)
    if variant == 'bridge' then cost = cost + self:waterAlong(na.x, na.y, nb.x, nb.y) * City.BRIDGE.perWaterM end
    local grow = self:roadNodeUpgrade(na, { variant == 'bridge' and 'road' or variant }) + self:roadNodeUpgrade(nb, { variant == 'bridge' and 'road' or variant })
    return math.ceil(cost * (City.ROAD_TYPES[variant] or City.ROAD_TYPES.road).factor) + grow
  end
  return (City.ROUTES[mode] or {}).vehicle or 0
end

function City:linkError(a, b, mode)
  do
    local na,nb=self.g.nodes[a],self.g.nodes[b]
    if not (na and nb and na.alive and nb.alive) then return 'choose two live buildings' end
    if mode=='road' then
      -- Each road variant meets its own kind of junction.
      local variant=self.buildRoadType or 'road'
      if not City.ROAD_TYPES[variant] then return 'choose a road variant' end
      for _,n in ipairs({na,nb}) do
        if n.kind=='stop' and variant~='road' then return 'bus stops attach to normal roads only' end
        -- A road node becomes whatever junction its roads call for.
        if variant=='highway' and not City.ROAD_JUNCTIONS[n.kind] then return 'a highway reaches buildings through a normal road' end
      end
    elseif mode=='bus' then
      if na.kind~='stop' or nb.kind~='stop' then return 'buses board only at bus stops' end
    elseif na.kind=='stop' or nb.kind=='stop' then return 'bus stops work only for buses' end
  end
  local na, nb = self:transitNode(a), self:transitNode(b)
  if not (na and nb) then return "roads connect houses, businesses and road junctions; bus services connect bus stops" end
  if a == b then return "a route needs two ends" end
  if mode == "road" then
    if not self:unlocked("roads") then return "nobody travels yet" end
    if self:linkBetween(a, b, "road") then return "that road already exists" end
    if self:nodeDistance(a, b) > City.PEOPLE.roadRange then return "too far for one road: put a matching junction between" end
    local wet = self:waterAlong(na.x, na.y, nb.x, nb.y)
    local variant = self.buildRoadType or "road"
    if variant == "bridge" and wet <= 0 then return "a bridge has to cross water" end
    if variant ~= "bridge" and wet > 0 then return "water in the way: build a bridge" end
    local mult, blocker = self:crossingCost(na.x, na.y, nb.x, nb.y, variant == "bridge")
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
    l.toll = l.roadType == "highway" and City.PEOPLE.tollDefault or l.roadType == "bridge" and City.BRIDGE.toll or 0
    if l.roadType == "bridge" then self:note("Bridge built for $%d; toll $%d per vehicle", cost, l.toll)
    else self:note("Road laid for $%d; highway toll $%d per vehicle", cost, l.toll) end
  else
    l.fare, l.vehicles = City.ROUTES[mode].fare, 1
    self:note("%s opened for $%d, at $%d a seat", City.ROUTES[mode].name, cost, l.fare)
  end
  self.links[l.id] = l
  if mode == "road" then self:fitRoadNode(a); self:fitRoadNode(b) end
  self:refresh()
  return l
end

function City:setLinkPrice(id, value)
  local l = (self.links or {})[id]
  if l and l.mode=='road' and not City.tolled(l) then return nil,'only highways and bridges charge tolls' end
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
  self.money = self.money + math.floor(spec.vehicle * City.REFUND)
  self:refresh()
  return l
end

function City:demolishLink(id)
  local l = (self.links or {})[id]
  if not (l and l.alive) then return nil, "no such road or route" end
  local refund = math.floor((l.paid or 0) * City.REFUND)
  l.alive = false
  self.money = self.money + refund
  if l.mode == "road" then self:clearRoadEnds(l) end
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
  self:spendMaterials(bill, 1, n.x, n.y)
  n.level = (n.level or 1) + 1
  n.paid = (n.paid or 0) + cost
  self:note("Resort %d built up to level %d for $%d", n.id, n.level, cost)
  self:refresh()
  return n
end

end
