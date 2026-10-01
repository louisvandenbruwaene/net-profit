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

return function(City)
  -- Vehicles: how much one carries, how fast it goes on the map (metres a
  -- second of play), and which freight rate it is billed at.
  City.HAUL = require("data.freight").HAUL
  local BULK = { rail = "train", highway = "semi", sea = "ship", air = "plane" }

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
  function City:haulRoute(from, tx, ty, to)
    if to then
      for _, e in ipairs(self.g:edgesAt(from.id)) do
        if e.alive and e.rail and (e.a == to.id or e.b == to.id) and BULK[e.bulk or "rail"] then
          return { mode = BULK[e.bulk or "rail"], pts = { from.x, from.y, to.x, to.y } }
        end
      end
    end
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
    -- Overland only where a lorry can drive: not through water.
    if self:waterAlong(from.x, from.y, tx, ty) > 0 then return nil end
    return { mode = "lorry", pts = { from.x, from.y, tx, ty } }
  end

  function City:haulCost(route, units)
    local rate = City.MODES[City.HAUL[route.mode].rate] or City.MODES.highway
    return math.ceil(units * (rate.haulPerUnit + polyLength(route.pts) * rate.haulPerM))
  end

  local function convoy(self, key, units, from, tx, ty, to, stock, day)
    local route = self:haulRoute(from, tx, ty, to)
    if not route then return nil end
    local c = { key = key, units = units, from = from.id, to = to and to.id or nil, mode = route.mode,
      pts = route.pts, len = polyLength(route.pts), day = day or self.day, stock = stock or nil }
    self.convoys = self.convoys or {}
    self.convoys[#self.convoys + 1] = c
    return c, route
  end

  -- Materials spent on a building at (x, y): driven there from the nearest store.
  function City:deliverToSite(bill, scale, x, y)
    if not x then return end
    local from = self:nearestStore(x, y)
    if not from then return end
    for _, key in ipairs(Graph.ALL) do
      local amount = bill and bill[key]
      if amount and amount > 0 then convoy(self, key, math.ceil(amount * (scale or 1)), from, x, y, nil) end
    end
  end

  -- An order landed at a haven: onward to the nearest yard, billed at the mode
  -- it goes by, in stock tomorrow. With no yard it stays on the quay, which is
  -- stock already.
  function City:haulInland(havenId, key, units, today)
    today = today or self.day
    local haven = self.g.nodes[havenId]
    local yard, bd
    for _, n in ipairs(self.g:nodesOfKind("dc")) do
      if n.alive then
        local d = haven and (n.x - haven.x) ^ 2 + (n.y - haven.y) ^ 2 or 0
        if not bd or d < bd then yard, bd = n, d end
      end
    end
    if not (haven and haven.alive and yard) then
      self.stock = self.stock or {}
      self.stock[key] = (self.stock[key] or 0) + units
      return nil
    end
    local c, route = convoy(self, key, units, haven, yard.x, yard.y, yard, true, today)
    if not c then
      -- No way inland the company has built: the quay keeps it.
      self.stock = self.stock or {}
      self.stock[key] = (self.stock[key] or 0) + units
      self:note("%d %s kept on the quay: no way inland", units, string.lower(Graph.COMMODITIES[key].name))
      return nil
    end
    c.arrive = today + 1
    -- Haulage is a bill like any other day's cost: it is paid even short.
    local cost = self:haulCost(route, units)
    self.money = self.money - cost
    c.cost = cost
    self:note("%d %s on to the yard by %s for $%d", units, string.lower(Graph.COMMODITIES[key].name),
      City.HAUL[route.mode].name, cost)
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
