-- rounds.lua -- Rounds mode, played on the company game's own city.
--
-- A rounds run is an ordinary City with a `rounds` table on it. Everything the
-- company game has -- the map, the districts and their springs, every building,
-- mains and their sizes, levels, repairs, undo, the inspector, the drawing --
-- is the same code. What changes is time: there are no days, only breaks and
-- rounds. In a break the player builds. In a round a batch of houses arrives in
-- the open zones one at a time, and every house either gets its whole demand
-- or goes dry and costs lives. Each round has more houses than the last.
--
-- Houses are served by automation hubs: a hub serves every house inside its
-- radius, so where the houses land does not have to be known in advance. That
-- makes the hub the tower of this tower defence, and its radius the range.
--
-- Arrival order matters and is kept on purpose. A house is accepted only if
-- the network can serve it on top of every house already accepted this round,
-- so a round is lost house by house. One refresh per arrival: the solve the
-- company runs every time anything is built.
--
-- Nothing here draws from City:random(). A round comes from a stream hashed
-- out of the seed and the round number, so it is the same round however the
-- player built towards it, and saving before it cannot reroll it.
local D = require("data.rounds")

return function(City)
  City.ROUNDS = D

  local SHOCK_HEAD = {
    drought = "Drought: wells give " .. math.floor(D.SHOCKS.drought.output * 100) .. "% of their yield this round",
  }

  local function stream(seed)
    local s = { state = math.floor(seed) % 2147483646 + 1 }
    function s.next(lo, hi)
      s.state = (s.state * 16807) % 2147483647
      local v = (s.state - 1) / 2147483646
      if hi then return math.floor(lo + v * (hi - lo + 1)) end
      return v
    end
    for _ = 1, 4 do s.next() end
    return s
  end

  local HOUSE = {}
  for _, h in ipairs(D.HOUSES) do HOUSE[h.key] = h end
  City.ROUND_HOUSE = HOUSE

  --------------------------------------------------------------------------
  -- Starting a run
  --------------------------------------------------------------------------

  function City.newRounds(opts)
    opts = opts or {}
    local c = City.new({ seed = opts.seed })
    c:setupRounds(opts.strict)
    return c
  end

  function City:setupRounds(strict)
    -- The company opening puts a household on the map to connect first. A
    -- round brings its own houses, so it goes.
    for _, n in ipairs(self.g.nodes) do
      if n.alive and n.kind == "client" then self.g:killNode(n.id) end
    end
    self.money = D.START.money
    self.guideDismissed = true
    self.companyName = strict and "Strict run" or "Rounds run"
    local lives = strict and D.START.strictLives or D.START.lives
    self.rounds = {
      round = 1, lives = lives, maxLives = lives, strict = strict and true or false,
      streak = 0, best = 0, history = {}, phase = "build", won = false,
    }
    for i, id in ipairs(D.ZONE_ORDER) do
      local d = self.districts[id]
      if d then d.zoneOpens = D.ZONE_OPENS[i] end
    end
    self:openZones()
    self:refresh()
  end

  function City:isRounds() return self.rounds ~= nil end

  -- Zones that are open by round r, in the order they opened.
  function City:zones(r)
    r = r or (self.rounds and self.rounds.round) or 1
    local t = {}
    for _, id in ipairs(D.ZONE_ORDER) do
      local d = self.districts[id]
      if d and d.zoneOpens and d.zoneOpens <= r then t[#t + 1] = d end
    end
    return t
  end

  -- The next zone to open, and when.
  function City:nextZone()
    local r = self.rounds.round
    for _, id in ipairs(D.ZONE_ORDER) do
      local d = self.districts[id]
      if d and d.zoneOpens and d.zoneOpens > r then return d end
    end
  end

  -- An open zone is ground the company holds, for free: nobody pays for the
  -- street the houses are about to land on.
  function City:openZones()
    for _, d in ipairs(self:zones()) do
      if not d.owned then d.owned = true; self:note("%s opens: houses will arrive there", d.name) end
    end
  end

  --------------------------------------------------------------------------
  -- The company's gates, read the Rounds way
  --------------------------------------------------------------------------

  -- What the company counts in signed customers, a run counts in the most
  -- houses it has ever served in one round.
  function City:progress()
    if self.rounds then return self.rounds.best or 0 end
    return #self:clientList()
  end

  local unlocked = City.unlocked
  function City:unlocked(key)
    if self.rounds and D.ALWAYS_OPEN[key] then return true end
    if not self.rounds then return unlocked(self, key) end
    local spec = City.UNLOCKS[key]
    if spec and spec.clients and not spec.haven and not spec.licences and not spec.intake
       and not spec.population and not spec.road and not spec.passengers and not spec.reactor then
      return self:progress() >= spec.clients
    end
    return unlocked(self, key)
  end

  local unlockHint = City.unlockHint
  function City:unlockHint(key)
    local spec = City.UNLOCKS[key]
    if self.rounds and spec and spec.clients and not self:unlocked(key) and not spec.haven then
      return "Opens once a round serves " .. spec.clients .. " houses"
    end
    return unlockHint(self, key)
  end

  -- Steel and concrete come from yards and freight, which is the company's
  -- industry game. A run is about water, so it builds for cash alone.
  local materialsFor = City.materialsFor
  function City:materialsFor(...)
    if self.rounds then return {} end
    return materialsFor(self, ...)
  end

  local lesson = City.pendingLesson
  function City:pendingLesson()
    if self.rounds then return nil end
    return lesson(self)
  end

  --------------------------------------------------------------------------
  -- What a round holds
  --------------------------------------------------------------------------

  function City.houseCount(r) return 3 + r + math.floor(r * r / 60) end

  local function weights(r)
    local w = {}
    for _, h in ipairs(D.HOUSES) do
      if h.from and r >= h.from then
        if h.key == "cottage" then w[h.key] = math.max(1.5, 10 - r * 0.28)
        elseif h.key == "house" then w[h.key] = 6
        elseif h.key == "terrace" then w[h.key] = 4 + (r - h.from) * 0.12
        else w[h.key] = 2 + (r - h.from) * 0.18 end
      end
    end
    return w
  end

  local function pick(rng, w)
    local total = 0
    for _, h in ipairs(D.HOUSES) do total = total + (w[h.key] or 0) end
    local x = rng.next() * total
    for _, h in ipairs(D.HOUSES) do
      x = x - (w[h.key] or 0)
      if x <= 0 and w[h.key] then return h.key end
    end
    return "cottage"
  end

  -- Plans are never saved: they come back from the seed.
  local plans = setmetatable({}, { __mode = "k" })

  -- Everything about round r, decided before the player sees it: its houses
  -- (kind, zone and spot, in arrival order) and its shocks. The preview shows
  -- the counts and the shocks. Where exactly each house lands is the surprise.
  function City:roundPlan(r)
    r = r or self.rounds.round
    local cached = plans[self]
    if cached and cached.round == r then return cached end
    local rng = stream(self:cellSeed(7000 + r, 911))
    local plan = { round = r, houses = {}, shocks = {}, byZone = {}, demand = 0 }
    local zones = self:zones(r)

    for _, key in ipairs(D.SHOCK_ORDER) do
      local s = D.SHOCKS[key]
      -- Always drawn, so a shock appearing never moves the houses after it.
      local roll = rng.next()
      if r >= s.from and roll < s.chance then plan.shocks[key] = true end
    end
    if plan.shocks.burst then plan.bursts = 1 + math.floor(r / 20) end
    local heat = plan.shocks.heatwave and D.SHOCKS.heatwave.factor or 1

    local w = weights(r)
    local kinds = {}
    for _ = 1, City.houseCount(r) do kinds[#kinds + 1] = pick(rng, w) end
    if r % D.BOSS_EVERY == 0 then
      for _ = 1, r / D.BOSS_EVERY do
        table.insert(kinds, rng.next(math.floor(#kinds / 2) + 1, #kinds + 1), "block")
      end
      plan.boss = true
    end

    for _, kind in ipairs(kinds) do
      -- A zone gets a double share in the round it opens.
      local total = 0
      for _, z in ipairs(zones) do total = total + (z.zoneOpens == r and 2 or 1) end
      local x = rng.next() * total
      local zone = zones[#zones]
      for _, z in ipairs(zones) do
        x = x - (z.zoneOpens == r and 2 or 1)
        if x <= 0 then zone = z; break end
      end
      local demand = math.ceil(HOUSE[kind].demand * heat)
      -- Half the houses land anywhere in the zone, half gather towards its
      -- middle the way a neighbourhood grows. A hub in the middle reaches
      -- most of them and never quite all.
      local u, a, b, c, e = rng.next(), rng.next(), rng.next(), rng.next(), rng.next()
      local fx, fy
      if u < D.SPREAD then fx, fy = a, b else fx, fy = (a + c) / 2, (b + e) / 2 end
      plan.houses[#plan.houses + 1] = { kind = kind, zone = zone.id, fx = fx, fy = fy, demand = demand }
      plan.demand = plan.demand + demand
      local counts = plan.byZone[zone.id] or { demand = 0 }
      counts[kind] = (counts[kind] or 0) + 1
      counts.demand = counts.demand + demand
      plan.byZone[zone.id] = counts
    end
    plan.burstRoll = rng.next()
    plans[self] = plan
    return plan
  end

  -- Where a planned house stands: its spot in the zone, moved off anything it
  -- cannot stand on.
  function City:houseSpot(spec)
    local d = self.districts[spec.zone]
    local x = d.x + D.EDGE + spec.fx * (d.w - 2 * D.EDGE)
    local y = d.y + D.EDGE + spec.fy * (d.h - 2 * D.EDGE)
    for r = 0, 150, 15 do
      for i = 0, (r == 0 and 0 or 11) do
        local a = i * math.pi / 6
        local px, py = x + math.cos(a) * r, y + math.sin(a) * r
        if not self:placementError(px, py) then return px, py end
      end
    end
    return x, y
  end

  --------------------------------------------------------------------------
  -- Coverage
  --------------------------------------------------------------------------

  function City:hubsCovering(x, y)
    local t = {}
    for _, h in ipairs(self.g:nodesOfKind("exchange")) do
      if (h.x - x) ^ 2 + (h.y - y) ^ 2 <= self:hubRadius(h) ^ 2 then t[#t + 1] = h end
    end
    return t
  end

  -- The chance a house arriving in this zone lands where a hub reaches it:
  -- the zone sampled on a fixed grid, each point weighted by how likely a
  -- house is to land there. Fixed, so the number never flickers.
  -- Density of the two ways a house lands: flat, or peaked in the middle.
  local function tri(t) return 2 * (1 - math.abs(2 * t - 1)) end
  function City:zoneCoverage(d)
    local inside, covered = 0, 0
    local hubs = self.g:nodesOfKind("exchange")
    -- Cell midpoints, not a grid that includes the edges: counting the edge
    -- rows at full weight overcounts the corners, which are exactly where a
    -- hub does not reach.
    for gx = 0, 19 do
      for gy = 0, 13 do
        local fx, fy = (gx + 0.5) / 20, (gy + 0.5) / 14
        local w = D.SPREAD + (1 - D.SPREAD) * tri(fx) * tri(fy)
        local x = d.x + D.EDGE + fx * (d.w - 2 * D.EDGE)
        local y = d.y + D.EDGE + fy * (d.h - 2 * D.EDGE)
        inside = inside + w
        for _, h in ipairs(hubs) do
          if (h.x - x) ^ 2 + (h.y - y) ^ 2 <= self:hubRadius(h) ^ 2 then covered = covered + w; break end
        end
      end
    end
    return inside > 0 and covered / inside or 0
  end

  -- Water the wells, intakes and depots could give this round.
  function City:roundSupply(plan)
    local total = 0
    local dry = plan and plan.shocks.drought and D.SHOCKS.drought.output or 1
    for _, n in ipairs(self.g:nodesOfKind("source")) do
      if n.commodity == "water" then total = total + math.floor((n.output or 0) * dry) end
    end
    return total
  end

  --------------------------------------------------------------------------
  -- Playing a round
  --------------------------------------------------------------------------

  function City:roundHouses()
    local t = {}
    for _, id in ipairs((self.rounds and self.rounds.houses) or {}) do
      local n = self.g.nodes[id]
      if n and n.alive then t[#t + 1] = n end
    end
    return t
  end

  function City:pendingHouses()
    local rs = self.rounds
    if rs.phase ~= "round" then return 0 end
    return #rs.queue - rs.arrived
  end

  -- Bursts land on real water mains. A main is as likely to go as its lining
  -- says it is: an armoured main is the one that stays whole.
  local function burstMains(self, count, roll)
    local pool, total = {}, 0
    for _, e in ipairs(self.g.edges) do
      if e.alive and not e.bulk and e.commodity == "water" and not e.leaking then
        local w = self:gradeOf(e).risk * (e.capMax or e.cap)
        pool[#pool + 1] = { e = e, w = w }
        total = total + w
      end
    end
    local rng = stream(math.floor(roll * 2147483646) + 1)
    local hit = {}
    for _ = 1, math.min(count, #pool) do
      local x = rng.next() * total
      for i, item in ipairs(pool) do
        x = x - item.w
        if x <= 0 then
          local e = item.e
          e.leaking, e.cap, e.burstReported = true, 0, true
          hit[#hit + 1] = e
          total = total - item.w
          table.remove(pool, i)
          break
        end
      end
    end
    return hit
  end

  function City:startRound()
    local rs = self.rounds
    if not rs or rs.phase ~= "build" then return nil, "a round is already running" end
    local plan = self:roundPlan(rs.round)
    rs.phase = "round"
    rs.queue = plan.houses
    rs.arrived = 0
    rs.houses = {}
    rs.mark = #self.g.nodes
    rs.shocks = plan.shocks
    rs.log = { served = 0, dry = 0, lost = 0, delivered = 0, reasons = {} }
    self.day = rs.round
    if plan.shocks.drought then
      self.shock = { key = "drought", commodity = "water", output = D.SHOCKS.drought.output,
                     left = 1, head = SHOCK_HEAD.drought }
    end
    local bursts = {}
    if plan.bursts then
      bursts = burstMains(self, plan.bursts, plan.burstRoll)
      if #bursts > 0 then self:note("%d water main%s burst", #bursts, #bursts == 1 and "" or "s") end
    end
    self:refresh()
    return plan, bursts
  end

  local function allServed(self)
    for _, n in ipairs(self:roundHouses()) do
      if n.roundServed and not self:fullyServed(n) then return false end
    end
    return true
  end

  -- What holds a hub back, the way constraintFor answers for a customer:
  -- "unconnected", "repair" (a burst main on the way), "output" (every well
  -- it reaches is spent), "main" (a full main, the one to widen) or "hub" (the
  -- hub's own throughput). Nil when it gets everything it asks for.
  function City:hubConstraint(h)
    local got = ((self.detail.hub or {})[h.id] or {}).water or 0
    local want = (h.demandBy or {}).water or 0
    local seen, queue, feed, spare = { [h.id] = true }, { h.id }, false, 0
    local full, widenable, burst
    for _, id in ipairs(queue) do
      local node = self.g.nodes[id]
      if node.kind == "source" or node.kind == "terminal" then feed = true end
      if node.kind == "terminal" then spare = math.huge end
      if node.kind == "source" and node.commodity == "water" then
        spare = spare + math.max(0, (node.effectiveOutput or node.output or 0) - (self.produced[node.id] or 0))
      end
      for _, e in ipairs(self.g:edgesAt(id)) do
        if e.commodity == "water" and not e.bulk then
          if e.cap <= 0 or e.leaking then burst = burst or e end
          if e.cap > 0 then
            if math.abs(self.detail.edge[e.id] or 0) >= e.cap then
              full = full or e
              if not widenable and self:biggerSize(e) then widenable = e end
            end
            local o = e.a == id and e.b or e.a
            if not seen[o] then seen[o] = true; queue[#queue + 1] = o end
          end
        end
      end
    end
    if got >= want then return nil end
    if not feed then return burst and "repair" or "unconnected", burst end
    -- Spare water counts only on the hub's own network: a full well across
    -- the river is no help to it.
    if spare <= 0 then return "output" end
    if widenable or full then return "main", widenable or full end
    if burst then return "repair", burst end
    return "hub"
  end

  local REASON = {
    unconnected = "its hub is not joined to any water",
    repair = "a burst main cut its hub off",
    output = "every well it can reach is spent",
    main = "a main on the way is full",
    hub = "its hub is at its limit",
  }

  -- Why a house went dry, in the player's words, and the main to blame if
  -- there is one.
  local function why(self, n)
    if not n.hub then return "no hub reaches it" end
    local verdict, edge = self:hubConstraint(self.g.nodes[n.hub])
    return REASON[verdict or "hub"], edge
  end

  -- The next house arrives. It is accepted if the network can serve it on top
  -- of every house already accepted this round; otherwise it goes dry, its
  -- valve is shut so it takes nothing, and it costs its demand in lives.
  function City:roundArrive()
    local rs = self.rounds
    if not rs or rs.phase ~= "round" then return nil end
    local spec = rs.queue[rs.arrived + 1]
    if not spec then return nil end
    rs.arrived = rs.arrived + 1
    local kind = HOUSE[spec.kind]
    local client = City.CLIENTS[kind.client]
    local x, y = self:houseSpot(spec)
    local n = self.g:addNode(x, y, "client")
    n.clientType, n.commodity, n.demand = kind.client, "water", spec.demand
    n.rateBase, n.rate = client.rate, client.rate
    n.patience, n.grace, n.joined, n.prospect = client.patience, client.patience, self.day, false
    n.roundHouse, n.roundKind = true, spec.kind
    rs.houses[#rs.houses + 1] = n.id
    self:refresh()
    if self:fullyServed(n) and allServed(self) then
      n.roundServed = true
      rs.log.served = rs.log.served + 1
      rs.log.delivered = rs.log.delivered + n.demand
    else
      local reason, edge = why(self, n)
      n.dry, n.dryReason, n.dryEdge = true, reason, edge and edge.id or nil
      n.supplyClosed = true
      rs.log.dry = rs.log.dry + 1
      rs.log.lost = rs.log.lost + n.demand
      rs.log.reasons[reason] = (rs.log.reasons[reason] or 0) + 1
      rs.lives = math.max(0, rs.lives - n.demand)
      self:refresh()
      if rs.lives <= 0 then self:loseRun() end
    end
    return n
  end

  function City:clearRoundHouses()
    local rs = self.rounds
    local mark = rs.mark or #self.g.nodes
    for id = #self.g.nodes, mark + 1, -1 do
      self.g.nodes[id] = nil
      self.g.adj[id] = nil
    end
    rs.mark = nil
  end

  function City:loseRun()
    local rs = self.rounds
    rs.phase = "lost"
    rs.history[#rs.history + 1] = { round = rs.round, houses = rs.arrived, dry = rs.log.dry,
      lost = rs.log.lost, delivered = rs.log.delivered, income = 0 }
    self.shock = nil
    self:note("The taps ran dry in round %d", rs.round)
  end

  -- What a round pays, itemised the way the results show it. Upkeep is the
  -- company's own: what the network costs to run for a day, charged once.
  function City:roundPayout()
    local rs, P = self.rounds, D.PAY
    local log = rs.log
    local items = {}
    items[#items + 1] = { label = "Round " .. rs.round, amount = P.base + P.perRound * rs.round }
    items[#items + 1] = { label = log.delivered .. " water delivered", amount = P.perUnit * log.delivered }
    local spare = math.max(0, self:roundSupply() - log.delivered)
    local reserve = math.min(P.spareCap.base + P.spareCap.perRound * rs.round, spare * P.sparePerUnit)
    if reserve > 0 then items[#items + 1] = { label = spare .. " water in reserve", amount = reserve } end
    if log.dry == 0 then
      local run = rs.streak + 1
      items[#items + 1] = { label = run == 1 and "No dry houses" or ("No dry houses, " .. run .. " rounds running"),
        amount = P.streak * math.min(P.streakMax, run) }
    end
    local upkeep = math.floor(self:roundUpkeep() * P.upkeep + 0.5)
    if upkeep > 0 then items[#items + 1] = { label = "Upkeep", amount = -upkeep } end
    local total = 0
    for _, it in ipairs(items) do total = total + it.amount end
    return total, items
  end

  -- The running costs that still mean something without days: mains, wells,
  -- hubs and anything landed at a haven. Customers' credits, wages and rent
  -- belong to a company.
  function City:roundUpkeep()
    local total = 0
    for _, e in ipairs(self.g.edges) do
      if e.alive and not e.bulk and e.commodity then total = total + (self:pipeUpkeep(e) or 0) end
    end
    local trade = City.trade.water
    for _, n in ipairs(self.g:nodesOfKind("source")) do total = total + (trade.sourceUpkeep or 0) end
    for _ in ipairs(self.g:nodesOfKind("exchange")) do total = total + City.hub.upkeep end
    total = total + (self:importBill() or 0)
    return total
  end

  function City:finishRound()
    local rs = self.rounds
    if not rs or rs.phase ~= "round" then return nil end
    while rs.phase == "round" and self:pendingHouses() > 0 do self:roundArrive() end
    if rs.phase == "lost" then return nil end
    local total, items = self:roundPayout()
    self.money = self.money + total
    rs.streak = rs.log.dry == 0 and rs.streak + 1 or 0
    rs.best = math.max(rs.best or 0, rs.log.served)
    rs.history[#rs.history + 1] = { round = rs.round, houses = #rs.queue, dry = rs.log.dry,
      lost = rs.log.lost, delivered = rs.log.delivered, income = total }
    local result = { round = rs.round, total = total, items = items, log = rs.log,
      houses = self:roundHouses() }
    -- The houses leave with the round. Nothing can be built during one, so
    -- every node past the mark is a house, and the graph is cut back to what
    -- it was: forty rounds of houses would otherwise be thousands of dead
    -- nodes in every save and every solve.
    self:clearRoundHouses()
    if rs.round == D.FINAL_ROUND and not rs.won then rs.won = true; result.won = true end
    rs.round = rs.round + 1
    rs.phase = "build"
    rs.queue, rs.houses, rs.arrived, rs.shocks = nil, nil, nil, nil
    self.shock = nil
    self.day = rs.round
    self:openZones()
    self:refresh()
    return result
  end

  function City:playRound()
    local ok, err = self:startRound()
    if not ok then return nil, err end
    while self.rounds.phase == "round" and self:pendingHouses() > 0 do self:roundArrive() end
    if self.rounds.phase == "lost" then return nil, "lost" end
    return self:finishRound()
  end
end
