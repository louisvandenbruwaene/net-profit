-- haulage.lua -- the last leg: from where goods land to where they are used.
--
-- A ship or a plane brings an order to a haven; it is not in the yards until
-- something carries it inland. And a building that takes materials takes
-- them on site, so they are driven out to it. Both are convoys: a load, a
-- start and an end, the way it goes, and the vehicles it needs.
--
-- The way a load goes is the best the company has built between the two:
--   1. its own freight line between them (train, semi, ship or plane),
--   2. its roads (a semi along them),
--   3. the river, when both ends stand by it (a barge),
--   4. the air, from an air freight apron (a freighter),
--   5. otherwise a lorry overland.
-- Inland legs of an order are billed at that mode's haulage rate and land in
-- stock the next morning; deliveries to a site are part of what the building
-- cost, and are only shown.
--
-- `city.convoys` holds them. Nothing here reads City:random().
local Graph = require("graph")
local Shape = require("terrain_shape")

return function(City)
  -- Vehicles: how much one carries, how fast it goes on the map (metres a
  -- second of play), and which freight rate it is billed at.
  City.HAUL = require("data.freight").HAUL
  local BULK = { rail = "train", highway = "semi", sea = "ship", air = "plane" }
  local landRoute

  -- Where a boat calls at a place: a harbour or anything else on the coast is
  -- reached at the head of its jetty, out at sea; anything already on the
  -- water (an island, the river) where it stands.
  function City:quayPoint(n)
    if n.y >= 0 and n.y <= City.havenReach + 60 and not self:riverAt(n.x, n.y) then
      return n.x + 24, (City.JETTY_HEAD or -210) - 40
    end
    return n.x, n.y
  end

  -- A rail terminal sits on a main line that runs off the map both ways; its
  -- heading is hashed from where it stands.
  function City:railAxis(n)
    local a = Shape.hash(n.x, n.y, 92) * math.pi
    return math.cos(a), math.sin(a)
  end

  -- A river wharf's berth: the nearest point of the river, a little in from
  -- the bank on the wharf's side, and that sample's index along the course.
  local berths = setmetatable({}, { __mode = "k" })
  function City:wharfBerth(n)
    local p = self:riverPath()
    if not (p and p.n and p.n > 1) then return n.x, n.y, nil end
    local c = berths[n]
    if c and c.p == p and c.x == n.x and c.y == n.y then return c.bx, c.by, c.i end
    local best, bd = 1, math.huge
    for i = 1, p.n do
      local d = (p.x[i] - n.x) ^ 2 + (p.y[i] - n.y) ^ 2
      if d < bd then best, bd = i, d end
    end
    local cx, cy = p.x[best], p.y[best]
    local dx, dy = n.x - cx, n.y - cy
    local len = math.max(1, math.sqrt(dx * dx + dy * dy))
    local hw = (p.hw and p.hw[best]) or 60
    local off = math.max(0, hw - 28)
    local bx, by = cx + dx / len * off, cy + dy / len * off
    berths[n] = { p = p, x = n.x, y = n.y, bx = bx, by = by, i = best }
    return bx, by, best
  end

  -- Where materials are kept: the yards, or failing any, the havens' quays.
  function City:nearestStore(x, y)
    local best, bd
    for _, kind in ipairs({ "dc", "terminal" }) do
      for _, n in ipairs(self.g:nodesOfKind(kind)) do
        if n.alive then
          local d = (n.x - x) ^ 2 + (n.y - y) ^ 2
          if not bd or d < bd then best, bd = n, d end
        end
      end
      if best then return best end
    end
    return nil
  end

  local function polyLength(pts)
    local len = 0
    for i = 3, #pts, 2 do len = len + math.sqrt((pts[i] - pts[i - 2]) ^ 2 + (pts[i + 1] - pts[i - 1]) ^ 2) end
    return len
  end

  -- The river between two points, as the samples of its course.
  local function alongRiver(self, ax, ay, bx, by)
    local p = self:riverPath()
    if not (p and p.n and p.n > 2) then return nil end
    local function nearest(x, y)
      local best, bd = 1, math.huge
      for i = 1, p.n do
        local d = (p.x[i] - x) ^ 2 + (p.y[i] - y) ^ 2
        if d < bd then best, bd = i, d end
      end
      return best
    end
    local i, j = nearest(ax, ay), nearest(bx, by)
    local pts = { ax, ay }
    local step = i <= j and 1 or -1
    for k = i, j, step do pts[#pts + 1] = p.x[k]; pts[#pts + 1] = p.y[k] end
    pts[#pts + 1] = bx; pts[#pts + 1] = by
    return pts
  end

  -- The way from a building to a point (and the building there, if any).
  -- What a rail line can still carry today: its wagons, less the freight it
  -- already runs every day.
  function City:railSpare(e)
    local used = 0
    for _, flows in pairs(self.edgeFlowBy or {}) do used = used + math.abs(flows[e.id] or 0) end
    return math.max(0, math.floor((e.cap or 0) - used))
  end

  -- The company's railway from one freight building to another: the shortest
  -- run of rail lines between them, through any yards or havens on the way,
  -- using only lines with room today. Returns the stops in order and the
  -- most it can carry in a day (the tightest line).
  function City:railPath(from, to)
    local dist, prev, done = { [from.id] = 0 }, {}, {}
    while true do
      local u, best
      for id, d in pairs(dist) do
        if not done[id] and (not best or d < best or (d == best and id < u)) then u, best = id, d end
      end
      if not u then return nil end
      if u == to.id then break end
      done[u] = true
      for _, e in ipairs(self.g:edgesAt(u)) do
        if e.alive and e.rail and (e.bulk or "rail") == "rail" and self:railSpare(e) > 0 then
          local v = e.a == u and e.b or e.a
          local n = self.g.nodes[v]
          if n and n.alive and not done[v] then
            local d = best + self:nodeDistance(u, v)
            if not dist[v] or d < dist[v] then dist[v], prev[v] = d, e end
          end
        end
      end
    end
    local stops, cap, at = { to }, math.huge, to.id
    while prev[at] do
      local e = prev[at]
      cap = math.min(cap, self:railSpare(e))
      at = e.a == at and e.b or e.a
      table.insert(stops, 1, self.g.nodes[at])
    end
    return stops, cap
  end

  -- The way over land (and, failing that, the river or the air) from a
  -- building to a point: the company's roads, a barge where both ends stand
  -- by the river, a freighter from an air apron, else a lorry overland.
  landRoute = function(self, from, tx, ty, to)
    -- Roads: to the building itself, or to the road-side place nearest the site.
    local target = to
    if not target then
      local bd
      for _, n in ipairs(self.g.nodes) do
        if n.alive and n ~= from and City.TRANSIT_NODES[n.kind] then
          local d = (n.x - tx) ^ 2 + (n.y - ty) ^ 2
          if d < 400 * 400 and (not bd or d < bd) then target, bd = n, d end
        end
      end
    end
    local path = target and self.roadPath and self:roadPath(from.id, target.id, "truck")
    if path and #path > 0 then
      local pts, at = { from.x, from.y }, from.id
      for _, l in ipairs(path) do
        at = l.a == at and l.b or l.a
        local n = self.g.nodes[at]
        pts[#pts + 1] = n.x; pts[#pts + 1] = n.y
      end
      if not to then pts[#pts + 1] = tx; pts[#pts + 1] = ty end
      return { mode = "semi", pts = pts }
    end
    if self:nearRiver(from.x, from.y) and self:nearRiver(tx, ty) then
      local pts = alongRiver(self, from.x, from.y, tx, ty)
      if pts then return { mode = "barge", pts = pts } end
    end
    if from.haven == "airfield" then return { mode = "plane", pts = { from.x, from.y, tx, ty } } end
    -- Overland only where a lorry can drive: not through water, and not over
    -- ground that nothing may cross (a range without a blasting licence).
    if self:waterAlong(from.x, from.y, tx, ty) > 0 then return nil end
    if not self:crossingCost(from.x, from.y, tx, ty) then return nil end
    return { mode = "lorry", pts = { from.x, from.y, tx, ty } }
  end


  -- The river between two places, as a barge sails it: from the berth by the
  -- first, along the course, to the berth by the second.
  local function riverLeg(self, from, tx, ty, to)
    local p = self:riverPath()
    if not (p and p.n and p.n > 2) then return nil end
    local ax, ay, ai = self:wharfBerth(from)
    local target = to or { x = tx, y = ty }
    local bx, by, bi = self:wharfBerth(target)
    if not (ai and bi) then return nil end
    -- Berth to berth: a barge never leaves the water.
    local pts = { ax, ay }
    local step = ai <= bi and 1 or -1
    for k = ai + step, bi - step, step do pts[#pts + 1] = p.x[k]; pts[#pts + 1] = p.y[k] end
    pts[#pts + 1] = bx; pts[#pts + 1] = by
    if #pts < 4 then pts[#pts + 1] = bx + 1; pts[#pts + 1] = by end
    return pts
  end

  function City:bargeRoute(from, tx, ty, to)
    if self:nearRiver(tx, ty) then
      local pts = riverLeg(self, from, tx, ty, to)
      if pts then return { mode = "barge", pts = pts } end
    end
    -- By barge to the company's wharf nearest the yard, then on by land.
    local best, bd
    for _, w in ipairs(self.g:nodesOfKind("terminal")) do
      if w.alive and w.haven == "wharf" and w ~= from then
        local d = (w.x - tx) ^ 2 + (w.y - ty) ^ 2
        if not bd or d < bd then best, bd = w, d end
      end
    end
    if not best then return nil end
    local leg1 = riverLeg(self, from, best.x, best.y, best)
    local leg2 = leg1 and landRoute(self, best, tx, ty, to)
    if not (leg1 and leg2) or leg2.mode == "barge" then return nil end
    return { mode = "barge", pts = leg1, legs = { { mode = "barge", pts = leg1 }, { mode = leg2.mode, pts = leg2.pts } } }
  end

  function City:haulRoute(from, tx, ty, to)
    -- The company's own railway, where it reaches.
    if to then
      local stops, cap = self:railPath(from, to)
      if stops and #stops > 1 and cap > 0 then
        local pts = {}
        for _, n in ipairs(stops) do pts[#pts + 1] = n.x; pts[#pts + 1] = n.y end
        return { mode = "train", pts = pts, cap = cap }
      end
    end
    if to then
      for _, e in ipairs(self.g:edgesAt(from.id)) do
        if e.alive and e.rail and (e.a == to.id or e.b == to.id) and BULK[e.bulk or "rail"] then
          local mode = BULK[e.bulk or "rail"]
          if mode == "ship" then
            local ax, ay = self:quayPoint(from)
            local bx, by = self:quayPoint(to)
            return { mode = mode, pts = { ax, ay, bx, by } }
          end
          return { mode = mode, pts = { from.x, from.y, to.x, to.y } }
        end
      end
    end
    -- From a river wharf, the river: a barge to the bank by the yard, or to
    -- the company's wharf nearest it and on by land from there.
    if from.haven == "wharf" then
      local barge = self:bargeRoute(from, tx, ty, to)
      if barge then return barge end
    end
    return landRoute(self, from, tx, ty, to)
  end

  function City:haulCost(route, units)
    local total = 0
    for _, leg in ipairs(route.legs or { route }) do
      local rate = City.MODES[City.HAUL[leg.mode].rate] or City.MODES.highway
      total = total + units * (rate.haulPerUnit + polyLength(leg.pts) * rate.haulPerM)
    end
    return math.ceil(total)
  end

  local function convoy(self, key, units, from, tx, ty, to, stock, day, route)
    route = route or self:haulRoute(from, tx, ty, to)
    if not route then return nil end
    local c = { key = key, units = units, from = from.id, to = to and to.id or nil, mode = route.mode,
      pts = route.pts, len = polyLength(route.pts), day = day or self.day, stock = stock or nil }
    if route.legs then
      c.legs = {}
      for i, leg in ipairs(route.legs) do c.legs[i] = { mode = leg.mode, pts = leg.pts, len = polyLength(leg.pts) } end
    end
    self.convoys = self.convoys or {}
    self.convoys[#self.convoys + 1] = c
    return c, route
  end

  -- Materials spent on a building at (x, y): driven there from the nearest store.
  function City:deliverToSite(bill, scale, x, y)
    if not x then return end
    -- The nearest store with a way to the site: yards first, then havens.
    local stores = {}
    for _, kind in ipairs({ "dc", "terminal" }) do
      for _, n in ipairs(self.g:nodesOfKind(kind)) do
        if n.alive then stores[#stores + 1] = { n = n, d = (n.x - x) ^ 2 + (n.y - y) ^ 2 + (kind == "dc" and 0 or 1e12) } end
      end
    end
    table.sort(stores, function(a, b) return a.d < b.d end)
    local from
    for _, s in ipairs(stores) do
      if self:haulRoute(s.n, x, y, nil) then from = s.n; break end
    end
    if not from then return end
    for _, key in ipairs(Graph.ALL) do
      local amount = bill and bill[key]
      if amount and amount > 0 then convoy(self, key, math.ceil(amount * (scale or 1)), from, x, y, nil) end
    end
  end

  -- An order landed at a haven: onward to the nearest yard, billed at the mode
  -- it goes by, in stock tomorrow. With no yard it stays on the quay, which is
  -- stock already.
  function City:haulInland(havenId, key, units, today, yardId)
    today = today or self.day
    local haven = self.g.nodes[havenId]
    -- The yard it was sent to, or else the nearest one there is a way to.
    local yard
    local chosen = yardId and self.g.nodes[yardId]
    if chosen and chosen.alive and chosen.kind == "dc" then
      yard = chosen
    elseif haven and haven.alive then
      local yards = {}
      for _, n in ipairs(self.g:nodesOfKind("dc")) do
        if n.alive then yards[#yards + 1] = { n = n, d = (n.x - haven.x) ^ 2 + (n.y - haven.y) ^ 2 } end
      end
      table.sort(yards, function(a, b) return a.d < b.d end)
      for _, y in ipairs(yards) do
        if self:haulRoute(haven, y.n.x, y.n.y, y.n) then yard = y.n; break end
      end
      yard = yard or (yards[1] and yards[1].n)
    end
    if not (haven and haven.alive and yard) then
      self.stock = self.stock or {}
      self.stock[key] = (self.stock[key] or 0) + units
      return nil
    end
    local route = self:haulRoute(haven, yard.x, yard.y, yard)
    -- A railway carries what its spare wagons hold in a day; a bigger order
    -- goes up the line a trainload a day until it is all in.
    local loads = { units }
    if route and route.cap and units > route.cap then
      loads = {}
      local left = units
      while left > 0 do loads[#loads + 1] = math.min(route.cap, left); left = left - loads[#loads] end
    end
    local c
    for k, load in ipairs(loads) do
      local cv = convoy(self, key, load, haven, yard.x, yard.y, yard, true, today + k - 1, route)
      if cv then cv.arrive = today + k; c = c or cv end
    end
    if not c then
      -- No way inland the company has built: the quay keeps it.
      self.stock = self.stock or {}
      self.stock[key] = (self.stock[key] or 0) + units
      self:note("%d %s kept on the quay: no way inland", units, string.lower(Graph.COMMODITIES[key].name))
      return nil
    end
    -- Haulage is a bill like any other day's cost: it is paid even short.
    local cost = self:haulCost(route, units)
    self.money = self.money - cost
    c.cost = cost
    if #loads > 1 then
      self:note("%d %s on to the yard by %s for $%d, %d trainloads over %d days", units,
        string.lower(Graph.COMMODITIES[key].name), City.HAUL[route.mode].name, cost, #loads, #loads)
    else
      self:note("%d %s on to the yard by %s for $%d", units, string.lower(Graph.COMMODITIES[key].name),
        City.HAUL[route.mode].name, cost)
    end
    return c
  end

  -- At the close: inland loads due today reach the yards; yesterday's site
  -- deliveries are done.
  function City:settleConvoys(today)
    today = today or self.day
    local keep, landed = {}, {}
    for _, c in ipairs(self.convoys or {}) do
      if c.stock and (c.arrive or 0) <= today then
        self.stock = self.stock or {}
        self.stock[c.key] = (self.stock[c.key] or 0) + c.units
        landed[c.key] = (landed[c.key] or 0) + c.units
      elseif c.stock or c.day >= today then
        keep[#keep + 1] = c
      end
    end
    self.convoys = keep
    return landed
  end

  function City:inlandUnits(key)
    local total = 0
    for _, c in ipairs(self.convoys or {}) do
      if c.stock and (not key or c.key == key) then total = total + c.units end
    end
    return total
  end
end
