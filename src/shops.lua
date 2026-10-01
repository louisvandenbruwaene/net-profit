-- shops.lua -- shops on the streets, and the people who walk past them.
--
-- A street is a normal road the company laid. Each one is walked every day
-- by the residents of the buildings within reach of it, more at the weekend and in sunshine, fewer in the rain. The
-- walkers go both ways, and pass the street's shops in order: each one may go
-- in, and a full shop sends the rest on to the next. So where a shop stands,
-- what it charges, how big it is and whether a bench keeps people nearby all
-- decide how many come in.
--
-- A shop is a client node the company owns (`n.shop`). It pays no contract:
-- it earns its visitors times its price, and draws a little water or power
-- per visitor from the company's own networks, so a short shop serves fewer.
-- Everything is hashed from the day and the street, never City:random().
local D = require("data.shops")

return function(City)
  City.SHOPS = D.SHOPS
  City.SHOP_BY = {}
  City.SHOP_DATA = D
  for _, spec in ipairs(D.SHOPS) do
    City.SHOP_BY[spec.key] = spec
    local main
    for _, key in ipairs({ "water", "power" }) do if spec.needs[key] and not main then main = key end end
    spec.main = main
    City.CLIENTS[spec.key] = City.CLIENTS[spec.key] or {
      name = spec.name, commodity = main, demand = { 1, 1 }, rate = 0, patience = 99, weight = 0, shop = true,
    }
  end

  function City.isShop(n) return n and n.kind == "client" and City.SHOP_BY[n.clientType or ""] ~= nil end

  -- The street a point stands on: the nearest normal road the company laid,
  -- if it is close enough. Plot edges are hedges, not streets. Returns a key
  -- for the road, the position along it, and its ends.
  function City:streetAt(x, y)
    local best
    for _, l in ipairs(self.links or {}) do
      local na, nb = self.g.nodes[l.a], self.g.nodes[l.b]
      if l.alive and l.mode == "road" and (l.roadType or "road") == "road" and na and nb and na.alive and nb.alive then
        local dx, dy = nb.x - na.x, nb.y - na.y
        local len2 = math.max(1e-9, dx * dx + dy * dy)
        local t = ((x - na.x) * dx + (y - na.y) * dy) / len2
        if t > 0 and t < 1 then
          local qx, qy = na.x + dx * t - x, na.y + dy * t - y
          local dist = math.sqrt(qx * qx + qy * qy)
          if dist <= D.STREET and (not best or dist < best.dist) then
            best = { dist = dist, key = "road:" .. l.id, link = l, s = t * math.sqrt(len2),
              ax = na.x, ay = na.y, bx = nb.x, by = nb.y }
          end
        end
      end
    end
    return best
  end

  local function hashKey(s)
    local h = 7
    for i = 1, #s do h = (h * 31 + s:byte(i)) % 1000003 end
    return h
  end

  local function segDist(px, py, ax, ay, bx, by)
    local dx, dy = bx - ax, by - ay
    local t = math.max(0, math.min(1, ((px - ax) * dx + (py - ay) * dy) / math.max(1e-9, dx * dx + dy * dy)))
    local qx, qy = ax + dx * t - px, ay + dy * t - py
    return math.sqrt(qx * qx + qy * qy)
  end

  function City:shops()
    local out = {}
    for _, n in ipairs(self.g.nodes) do
      if n.alive and City.isShop(n) then out[#out + 1] = n end
    end
    return out
  end

  -- How many walk a street on a day, and with what ceiling on a peak.
  -- Every resident within reach of a street walks it.
  function City:streetWalkers(street, day, peak)
    day = day or self.day
    local total = 0
    local residents = {}
    for _, c in ipairs(self:clientList()) do
      if not City.isShop(c) then
        local r = D.RESIDENTS[c.clientType or ""] or 3
        if r > 0 and segDist(c.x, c.y, street.ax, street.ay, street.bx, street.by) <= D.REACH then
          total = total + r * D.OUTINGS
        end
      end
    end
    local w = self:weatherOn(day)
    local factor = D.WEEK[City.weekday(day)] * (D.WEATHER[w.key] or 1)
    local mood = peak and 1 + D.SPREAD or 1 + D.SPREAD * (2 * self:unit(hashKey(street.key), day + 7000) - 1)
    local walkers = total * factor * mood
    -- A stadium within reach fills the streets on its big days.
    local stadium = self.projectNode and self:projectNode("stadium")
    if stadium and self:fullyServed(stadium)
       and segDist(stadium.x, stadium.y, street.ax, street.ay, street.bx, street.by) <= D.REACH then
      local crowd = City.USAGE.WEEK.stadium[City.weekday(day)]
      if crowd > 1 then walkers = walkers + D.MATCH * crowd end
    end
    return math.floor(walkers + 0.5)
  end

  -- The chance a passer-by goes into this shop today.
  function City:shopChance(n)
    local spec = City.SHOP_BY[n.clientType]
    local over = (n.price or spec.price) / spec.price - 1
    local p = spec.attract * math.max(0, 1 - D.SENSITIVITY * over)
    -- Under the base price draws more, up to half as many again.
    if over < 0 then p = spec.attract * math.min(1.5, 1 - over) end
    for _, b in ipairs(self.benches or {}) do
      if (b.x - n.x) ^ 2 + (b.y - n.y) ^ 2 <= D.BENCH.reach ^ 2 then p = p * (1 + D.BENCH.boost); break end
    end
    return math.min(0.95, p)
  end

  function City:shopCapacity(n)
    local spec = City.SHOP_BY[n.clientType]
    return spec.levels[n.level or 1]
  end

  -- The day on every street with a shop: walkers split both ways and pass the
  -- shops in order, each taking its share until full. Sets `n.visitors`
  -- (who would come in), `n.passing` (who walked by) on every shop.
  function City:walkStreets(day, peak)
    day = day or self.day
    local streets = {}
    for _, n in ipairs(self:shops()) do
      local st = self:streetAt(n.x, n.y)
      n.visitors, n.passing, n.street = 0, 0, st and st.key or nil
      if st then
        streets[st.key] = streets[st.key] or { info = st, shops = {} }
        table.insert(streets[st.key].shops, { n = n, s = st.s })
      end
    end
    for key, street in pairs(streets) do
      local walkers = self:streetWalkers(street.info, day, peak)
      table.sort(street.shops, function(a, b) return a.s < b.s or (a.s == b.s and a.n.id < b.n.id) end)
      local room = {}
      for _, item in ipairs(street.shops) do
        room[item.n.id] = self:shopCapacity(item.n)
        item.n.passing = walkers
      end
      for dir = 1, 2 do
        local left = dir == 1 and math.ceil(walkers / 2) or math.floor(walkers / 2)
        local first, last, step = 1, #street.shops, 1
        if dir == 2 then first, last, step = #street.shops, 1, -1 end
        for i = first, last, step do
          local n = street.shops[i].n
          local want = left * self:shopChance(n)
          local whole = math.floor(want)
          if self:unit(n.id * 17 + dir, day + 9000) < want - whole then whole = whole + 1 end
          local take = math.min(whole, room[n.id], left)
          room[n.id] = room[n.id] - take
          left = left - take
          n.visitors = n.visitors + take
        end
      end
    end
  end

  -- What a shop draws today: its visitors times what each one uses.
  function City:shopUse(n)
    local spec = City.SHOP_BY[n.clientType]
    n.uses = {}
    for key, per in pairs(spec.needs) do n.uses[key] = math.max(1, math.ceil((n.visitors or 0) * per)) end
    n.use = n.uses[spec.main]
  end

  -- Visitors actually served: as many as what arrived can cover.
  function City:shopServed(n)
    local spec = City.SHOP_BY[n.clientType]
    local served = n.visitors or 0
    for key, per in pairs(spec.needs) do
      local got = key == n.commodity and (self.served or {})[n.id] or (((self.servedBy or {})[n.id] or {})[key] or 0)
      served = math.min(served, math.floor((got or 0) / per + 1e-9))
    end
    return served
  end

  function City:shopIncome(n)
    return self:shopServed(n) * (n.price or City.SHOP_BY[n.clientType].price)
  end

  function City:shopLocked(key)
    local spec = City.SHOP_BY[key]
    if not spec then return "no such shop" end
    local clients = 0
    for _, c in ipairs(self:clientList()) do if not City.isShop(c) then clients = clients + 1 end end
    if clients < spec.clients then return spec.clients .. " customers first" end
    for _, l in ipairs(self.links or {}) do
      if l.alive and l.mode == "road" and (l.roadType or "road") == "road" then return nil end
    end
    return "lay a road first"
  end

  -- Where a shop put down at (x, y) actually stands: squared up to the
  -- road, a fixed step back from its kerb on the side it was put, so its
  -- door faces the pavement.
  function City:shopSpot(x, y)
    local st = self:streetAt(x, y)
    if not st then return x, y end
    local dx, dy = st.bx - st.ax, st.by - st.ay
    local len = math.max(1e-9, math.sqrt(dx * dx + dy * dy))
    local ux, uy = dx / len, dy / len
    local side = ((x - st.ax) * -uy + (y - st.ay) * ux) >= 0 and 1 or -1
    local back = City.ROAD_WIDTH.road / 2 + City.PAVEMENT + D.SETBACK
    local fx, fy = st.ax + ux * st.s, st.ay + uy * st.s
    return fx - uy * back * side, fy + ux * back * side
  end

  function City:shopError(key, x, y)
    x, y = self:shopSpot(x, y)
    local why = self:shopLocked(key)
    if why then return why end
    why = self:placementError(x, y, "client")
    if why then return why end
    if not self:streetAt(x, y) then return "build beside a road" end
    if City.SHOP_BY[key].cost > self.money then return "not enough cash" end
    return nil
  end

  function City:buildShop(key, x, y)
    local why = self:shopError(key, x, y)
    if why then return nil, why end
    local spec = City.SHOP_BY[key]
    x, y = self:shopSpot(x, y)
    self:spend(spec.cost)
    local n = self.g:addNode(x, y, "client")
    n.clientType, n.commodity, n.shop = key, spec.main, true
    n.level, n.price, n.rate = 1, spec.price, 0
    n.patience, n.grace, n.prospect = 99, 99, false
    self:setShopContract(n)
    self:note("%s opened for $%d", spec.name, spec.cost)
    self:refresh()
    return n
  end

  -- The contract of a shop is what it could ever draw: full, at its level.
  function City:setShopContract(n)
    local spec = City.SHOP_BY[n.clientType]
    local cap = self:shopCapacity(n)
    n.demand = math.max(1, math.ceil(cap * spec.needs[spec.main]))
    n.demands = nil
    local extra = false
    for key in pairs(spec.needs) do if key ~= spec.main then extra = true end end
    if extra then
      n.demands = {}
      for key, per in pairs(spec.needs) do n.demands[key] = math.max(1, math.ceil(cap * per)) end
    end
  end

  function City:expandShop(id)
    local n = self.g.nodes[id]
    if not City.isShop(n) then return nil, "not a shop" end
    local spec = City.SHOP_BY[n.clientType]
    local next = (n.level or 1) + 1
    if not spec.levels[next] then return nil, "already the largest" end
    local price = spec.levelCost[next]
    if price > self.money then return nil, "not enough cash" end
    self:spend(price)
    n.level = next
    self:setShopContract(n)
    self:refresh()
    return n
  end

  function City:setShopPrice(id, price)
    local n = self.g.nodes[id]
    if not City.isShop(n) then return nil, "not a shop" end
    n.price = math.max(1, math.min(99, math.floor(price)))
    self:refresh()
    return n
  end

  function City:benchError(x, y)
    local d = self:districtAt(x, y)
    if not (d and d.owned) then return "on your own ground" end
    local st = self:streetAt(x, y)
    if not st then return "beside a road" end
    if st.dist < City.ROAD_WIDTH.road / 2 + City.PAVEMENT then return "not on the road" end
    if self:obstacleAt(x, y) then return "not on rough ground" end
    for _, b in ipairs(self.benches or {}) do
      if (b.x - x) ^ 2 + (b.y - y) ^ 2 < 30 ^ 2 then return "too close to another bench" end
    end
    if D.BENCH.cost > self.money then return "not enough cash" end
    return nil
  end

  function City:buildBench(x, y)
    local why = self:benchError(x, y)
    if why then return nil, why end
    self:spend(D.BENCH.cost)
    self.benches = self.benches or {}
    local b = { x = x, y = y }
    self.benches[#self.benches + 1] = b
    self:refresh()
    return b
  end
end
