-- city.lua -- the company: a persistent network, a ledger, and a day that ends.
--
-- You are the CEO of a utility. Wells produce, pipes carry, customers pay, and
-- pipes rot. Every day the same question is asked in a slightly different shape:
-- the money in hand can be spent on capacity, on resilience, on reputation, or
-- on nothing at all so it can earn interest. There is no single right answer,
-- which is the point.
local Graph = require("graph")

local City = {}
City.__index = City

City.price = {
  junction = 22, manifold = 46, pump = 38, tower = 92,
  pipeBase = 8, pipePerUnit = 0.12,
  capacity = 12,
  repairBase = 10, repairPerLost = 6,
  waterSource = 260, sourceGrowth = 1.55,
  beerLicence = 600, oilLicence = 1500,
  beerSource = 420, oilSource = 900,
  qualityBase = 140,
  ads = 90,
  reinforce = 26,          -- upgrade a pipe so it rots half as fast
}

City.rules = {
  linkRange = 300,
  pumpRange = 520,
  minSpacing = 46,
  leakBase = 0.07,          -- per pipe per day, before quality and grade
  qualityStep = 0.13,       -- each quality level removes this fraction
  adDays = 5,
  adBoost = 0.25,
  arriveBase = 0.14,
  investDays = 7,
  investMean = 0.10,
  investSd = 0.05,
  sourceIncome = 12,        -- wholesale, per well per day
  repLoss = 8,
  startMoney = 300,
}

-- Customers. Rich ones pay far more and forgive far less, which is the whole
-- reason to lay a beer main instead of another row of houses.
City.CLIENTS = {
  house   = { name = "HOUSE",   commodity = "water", demand = {2, 4}, rate = 4,  patience = 3, weight = 10 },
  estate  = { name = "ESTATE",  commodity = "water", demand = {5, 7}, rate = 6,  patience = 2, weight = 3 },
  pub     = { name = "PUB",     commodity = "beer",  demand = {2, 4}, rate = 16, patience = 2, weight = 6 },
  factory = { name = "FACTORY", commodity = "oil",   demand = {4, 6}, rate = 26, patience = 1, weight = 5 },
}

City.OBSTACLES = {
  bedrock = { name = "BEDROCK", cross = nil, color = {0.30, 0.28, 0.34} },
  park    = { name = "PARKLAND", cross = 2, color = {0.32, 0.52, 0.36} },
  river   = { name = "RIVER",   cross = 3, color = {0.30, 0.48, 0.72} },
}

--------------------------------------------------------------------------------

function City:random(lo, hi)
  self.rng = (self.rng * 16807) % 2147483647
  local value = (self.rng - 1) / 2147483646
  if hi then return math.floor(lo + value * (hi - lo + 1)) end
  if lo then return math.floor(1 + value * lo) end
  return value
end

function City:rand(lo, hi) return lo + self:random() * (hi - lo) end

-- Box-Muller: investment returns are normal, so a bad run of luck is possible
-- and a good one is not a bug.
local function gauss(self, mean, sd)
  local u1 = math.max(1e-9, self:random())
  local u2 = self:random()
  return mean + sd * math.sqrt(-2 * math.log(u1)) * math.cos(2 * math.pi * u2)
end

function City.new(opts)
  opts = opts or {}
  local self = setmetatable({}, City)
  self.rng = (opts.seed or os.time()) % 2147483646 + 1
  self.bounds = { x = 0, y = 0, w = 2000, h = 1400 }
  self.g = Graph.new()
  self.day = 1
  self.money = City.rules.startMoney
  self.reputation = 50
  self.quality = 0
  self.adDaysLeft = 0
  self.investments = {}
  self.obstacles = {}
  self.licences = { water = true, beer = false, oil = false }
  self.sourcesBought = 0
  self.log = {}
  self.history = {}
  self.bankrupt = false
  self.lostClients = 0
  self.pipeGrade = {}
  self.milestones = {}

  local cx, cy = self.bounds.w / 2, self.bounds.h / 2
  local src = self.g:addNode(cx, cy, "source")
  src.commodity = "water"
  src.output = 14
  self.firstSource = src

  self:scatterObstacles(opts.obstacles or 7)
  for i = 1, 2 do
    local c = self:addClient("house")
    c.x, c.y = cx + (i == 1 and -210 or 220), cy + (i == 1 and -70 or 65)
    c.demand = 3
  end

  self:refresh()
  return self
end

function City:note(fmt, ...)
  table.insert(self.log, 1, { text = string.format(fmt, ...), day = self.day })
  for i = #self.log, 40, -1 do self.log[i] = nil end
end

--------------------------------------------------------------------------------
-- Ground
--------------------------------------------------------------------------------

function City:scatterObstacles(n)
  local kinds = { "bedrock", "park", "river" }
  for _ = 1, n do
    for _ = 1, 40 do
      local r = self:rand(70, 140)
      local x = self:rand(r + 40, self.bounds.w - r - 40)
      local y = self:rand(r + 40, self.bounds.h - r - 40)
      local clear = true
      for _, node in ipairs(self.g:aliveNodes()) do
        if (node.x - x) ^ 2 + (node.y - y) ^ 2 < (r + 340) ^ 2 then clear = false; break end
      end
      for _, o in ipairs(self.obstacles) do
        if (o.x - x) ^ 2 + (o.y - y) ^ 2 < (o.r + r + 40) ^ 2 then clear = false; break end
      end
      if clear then
        self.obstacles[#self.obstacles + 1] =
          { x = x, y = y, r = r, kind = kinds[self:random(#kinds)] }
        break
      end
    end
  end
end

local function segCircle(ax, ay, bx, by, cx, cy, r)
  local dx, dy = bx - ax, by - ay
  local l2 = dx * dx + dy * dy
  local t = 0
  if l2 > 1e-9 then
    t = math.max(0, math.min(1, ((cx - ax) * dx + (cy - ay) * dy) / l2))
  end
  local px, py = ax + dx * t, ay + dy * t
  return (px - cx) ^ 2 + (py - cy) ^ 2 <= r * r
end

function City:obstacleAt(x, y)
  for _, o in ipairs(self.obstacles) do
    if (x - o.x) ^ 2 + (y - o.y) ^ 2 <= o.r * o.r then return o end
  end
  return nil
end

-- Returns a cost multiplier, or nil if the route is impossible.
function City:crossingCost(ax, ay, bx, by)
  local mult = 1
  for _, o in ipairs(self.obstacles) do
    if segCircle(ax, ay, bx, by, o.x, o.y, o.r) then
      local spec = City.OBSTACLES[o.kind]
      if not spec.cross then return nil, o end
      mult = math.max(mult, spec.cross)
    end
  end
  return mult
end

function City:placementError(x, y)
  local b = self.bounds
  if x < b.x or y < b.y or x > b.x + b.w or y > b.y + b.h then return "outside the map" end
  local o = self:obstacleAt(x, y)
  if o then return "cannot build on " .. string.lower(City.OBSTACLES[o.kind].name) end
  for _, n in ipairs(self.g:aliveNodes()) do
    if (n.x - x) ^ 2 + (n.y - y) ^ 2 < City.rules.minSpacing ^ 2 then
      return "too close to another structure"
    end
  end
  return nil
end

function City:rangeBetween(a, b)
  local ka, kb = self.g.nodes[a].kind, self.g.nodes[b].kind
  if ka == "pump" or kb == "pump" then return City.rules.pumpRange end
  return City.rules.linkRange
end

function City:pipeError(a, b, commodity)
  if not self.licences[commodity] then return "no licence for that" end
  local ok, why = self.g:canLink(a, b)
  -- Two structures may carry one pipe of each commodity between them.
  if not ok and why ~= "link already exists" then return why end
  if self:pipeBetween(a, b, commodity) then return "that pipe already exists" end
  if self.g:freePorts(a) < 1 then return "no free ports there" end
  if self.g:freePorts(b) < 1 then return "no free ports there" end

  local na, nb = self.g.nodes[a], self.g.nodes[b]
  local d = math.sqrt((na.x - nb.x) ^ 2 + (na.y - nb.y) ^ 2)
  if d > self:rangeBetween(a, b) then return "too far: use a pump" end
  local mult, blocker = self:crossingCost(na.x, na.y, nb.x, nb.y)
  if not mult then return "cannot cross " .. string.lower(City.OBSTACLES[blocker.kind].name) end
  return nil
end

function City:pipeBetween(a, b, commodity)
  for _, ei in ipairs(self.g.adj[a] or {}) do
    local e = self.g.edges[ei]
    if e.alive and e.commodity == commodity
       and ((e.a == a and e.b == b) or (e.a == b and e.b == a)) then return ei end
  end
  return nil
end

--------------------------------------------------------------------------------
-- Prices
--------------------------------------------------------------------------------

function City:nodeCost(kind) return City.price[kind] or 0 end

function City:pipeCost(a, b, capacity)
  local na, nb = self.g.nodes[a], self.g.nodes[b]
  local d = math.sqrt((na.x - nb.x) ^ 2 + (na.y - nb.y) ^ 2)
  local mult = self:crossingCost(na.x, na.y, nb.x, nb.y) or 1
  return math.ceil((City.price.pipeBase + d * City.price.pipePerUnit) * mult)
    + math.max(0, (capacity or 1) - 1) * City.price.capacity
end

function City:repairCost(e)
  local lost = (e.capMax or e.cap) - e.cap
  return City.price.repairBase + City.price.repairPerLost * math.max(1, lost)
end

function City:sourceCost(commodity)
  if commodity == "beer" then return City.price.beerSource end
  if commodity == "oil" then return City.price.oilSource end
  return math.ceil(City.price.waterSource * (City.price.sourceGrowth ^ self.sourcesBought))
end

function City:qualityCost() return City.price.qualityBase * (self.quality + 1) end

function City:spend(amount)
  if amount > self.money then return false end
  self.money = self.money - amount
  return true
end

--------------------------------------------------------------------------------
-- Building
--------------------------------------------------------------------------------

function City:build(x, y, kind)
  if kind ~= "junction" and kind ~= "manifold" and kind ~= "pump" and kind ~= "tower" then
    return nil, "choose a structure"
  end
  local err = self:placementError(x, y)
  if err then return nil, err end
  local cost = self:nodeCost(kind)
  if cost > self.money then return nil, "not enough cash" end
  self:spend(cost)
  local n = self.g:addNode(x, y, kind)
  n.throughput = 999
  self:refresh()
  return n
end

function City:layPipe(a, b, commodity, capacity)
  capacity = capacity or 1
  if type(capacity) ~= "number" or capacity % 1 ~= 0 or capacity < 1 or capacity > 24 then
    return nil, "capacity must be between 1 and 24"
  end
  local err = self:pipeError(a, b, commodity)
  if err then return nil, err end
  local cost = self:pipeCost(a, b, capacity)
  if cost > self.money then return nil, "not enough cash" end
  self:spend(cost)
  local e = self.g:addEdge(a, b, capacity)
  -- canLink refuses a duplicate, so a second commodity needs the raw insert.
  if not e then
    e = { id = #self.g.edges + 1, a = a, b = b, cap = capacity, alive = true }
    self.g.edges[e.id] = e
    table.insert(self.g.adj[a], e.id)
    table.insert(self.g.adj[b], e.id)
  end
  e.commodity = commodity
  e.capMax = capacity
  e.paid = cost
  e.grade = 1
  e.leaking = false
  self:refresh()
  return e
end

function City:upgradePipe(id)
  local e = self.g.edges[id]
  if not (e and e.alive) then return nil, "no such pipe" end
  if e.capMax >= 24 then return nil, "maximum capacity reached" end
  local cost = City.price.capacity
  if cost > self.money then return nil, "not enough cash" end
  self:spend(cost)
  e.paid = (e.paid or self:pipeCost(e.a, e.b, e.capMax)) + cost
  e.cap = e.cap + 1
  e.capMax = (e.capMax or e.cap) + 1
  self:refresh()
  return e
end

function City:repairPipe(id)
  local e = self.g.edges[id]
  if not (e and e.alive) then return nil, "no such pipe" end
  if not e.leaking and e.cap >= (e.capMax or e.cap) then return nil, "nothing to repair" end
  local cost = self:repairCost(e)
  if cost > self.money then return nil, "not enough cash" end
  self:spend(cost)
  e.cap = e.capMax or e.cap
  e.leaking = false
  e.burstReported = nil
  self:refresh()
  return cost
end

function City:reinforcePipe(id)
  local e = self.g.edges[id]
  if not (e and e.alive) then return nil, "no such pipe" end
  if (e.grade or 1) >= 2 then return nil, "already reinforced" end
  if City.price.reinforce > self.money then return nil, "not enough cash" end
  self:spend(City.price.reinforce)
  e.grade = 2
  return e
end

function City:demolishPipe(id)
  local e = self.g.edges[id]
  if not (e and e.alive) then return nil, "no such pipe" end
  local refund = math.floor((e.paid or self:pipeCost(e.a, e.b, e.capMax)) * 0.4)
  self.g:killEdge(id)
  self.money = self.money + refund
  self:refresh()
  return refund
end

function City:demolishNode(id)
  local n = self.g.nodes[id]
  if not (n and n.alive) then return nil, "no such structure" end
  if n.kind == "source" or n.kind == "client" then return nil, "cannot demolish that" end
  local refund = math.floor((n.paid or self:nodeCost(n.kind)) * 0.4)
  self.g:killNode(id)
  self.money = self.money + refund
  self:refresh()
  return refund
end

--------------------------------------------------------------------------------
-- Company decisions
--------------------------------------------------------------------------------

function City:buySource(commodity, px, py)
  if not self.licences[commodity] then return nil, "no licence" end
  local cost = self:sourceCost(commodity)
  if cost > self.money then return nil, "not enough cash" end
  if px then
    local err = self:placementError(px, py)
    if err then return nil, err end
    self:spend(cost)
    local s = self.g:addNode(px, py, "source")
    s.commodity, s.output, s.paid = commodity, commodity == "water" and 14 or 10, cost
    if commodity == "water" then self.sourcesBought = self.sourcesBought + 1 end
    self:note("New %s source opened for $%d", commodity, cost)
    self:refresh()
    return s
  end

  -- Somewhere legal, and not on top of the existing works.
  for _ = 1, 200 do
    local x = self:rand(120, self.bounds.w - 120)
    local y = self:rand(120, self.bounds.h - 120)
    if not self:placementError(x, y) then
      local near = false
      for _, n in ipairs(self.g:aliveNodes()) do
        if (n.x - x) ^ 2 + (n.y - y) ^ 2 < 620 ^ 2 then near = true; break end
      end
      if near then
        return self:buySource(commodity, x, y)
      end
    end
  end
  return nil, "no room for a new well"
end

function City:buyLicence(commodity)
  if commodity ~= "beer" and commodity ~= "oil" then return nil, "unknown trade" end
  if self.licences[commodity] then return nil, "already held" end
  local cost = (commodity == "beer") and City.price.beerLicence or City.price.oilLicence
  if cost > self.money then return nil, "not enough cash" end
  self:spend(cost)
  self.licences[commodity] = true
  self:note("%s licence acquired: that trade can now be served",
    string.upper(commodity))
  return true
end

function City:upgradeQuality()
  if self.quality >= 5 then return nil, "already at the top grade" end
  local cost = self:qualityCost()
  if cost > self.money then return nil, "not enough cash" end
  self:spend(cost)
  self.quality = self.quality + 1
  self:note("Treatment upgraded to grade %d: pipes will foul more slowly", self.quality)
  return true
end

function City:buyAds()
  if self.adDaysLeft > 0 then return nil, "campaign already running" end
  if City.price.ads > self.money then return nil, "not enough cash" end
  self:spend(City.price.ads)
  self.adDaysLeft = City.rules.adDays
  self:note("Advertising campaign booked for %d days", City.rules.adDays)
  return true
end

function City:invest(amount)
  if type(amount) ~= "number" or amount ~= amount or amount == math.huge then return nil, "invalid amount" end
  amount = math.floor(amount)
  if amount <= 0 then return nil, "nothing to invest" end
  if amount > self.money then return nil, "not enough cash" end
  self:spend(amount)
  -- Pays out at the end of the seventh day, counting today as the first, so
  -- "set aside for 7 days" ties the money up for exactly seven closes.
  self.investments[#self.investments + 1] = {
    amount = amount,
    matures = self.day + City.rules.investDays - 1,
  }
  self:note("$%d placed for %d days", amount, City.rules.investDays)
  return true
end

function City:daysToMaturity(inv)
  return math.max(0, inv.matures - self.day + 1)
end

function City:investedTotal()
  local t = 0
  for _, inv in ipairs(self.investments) do t = t + inv.amount end
  return t
end

--------------------------------------------------------------------------------
-- Customers
--------------------------------------------------------------------------------

function City:clientList(prospects)
  local t = {}
  for _, n in ipairs(self.g.nodes) do
    if n.alive and n.kind == "client" and (not not n.prospect) == (not not prospects) then t[#t + 1] = n end
  end
  return t
end

function City:pickClientType()
  local pool = {}
  for _, key in ipairs({"house", "estate", "pub", "factory"}) do
    local spec = City.CLIENTS[key]
    if self.licences[spec.commodity] then
      for _ = 1, spec.weight do pool[#pool + 1] = key end
    end
  end
  if #pool == 0 then return "house" end
  return pool[self:random(#pool)]
end

function City:addClient(kind, prospect)
  kind = kind or self:pickClientType()
  local spec = City.CLIENTS[kind]
  -- Customers appear near the works, farther out as the company grows.
  local sources = {}
  for _, n in ipairs(self.g:nodesOfKind("source")) do
    if n.commodity == spec.commodity then sources[#sources + 1] = n end
  end
  local anchor = #sources > 0 and sources[self:random(#sources)] or self.firstSource
  local reach = 260 + #self:clientList() * 45
  for _ = 1, 160 do
    local ang = self:random() * math.pi * 2
    local r = self:rand(180, math.min(600, reach))
    local x = math.max(70, math.min(self.bounds.w - 70, anchor.x + math.cos(ang) * r))
    local y = math.max(70, math.min(self.bounds.h - 70, anchor.y + math.sin(ang) * r * 0.78))
    if not self:placementError(x, y) then
      local n = self.g:addNode(x, y, "client")
      n.clientType = kind
      n.commodity = spec.commodity
      n.demand = self:random(spec.demand[1], spec.demand[2])
      n.rate = spec.rate
      n.patience = spec.patience
      n.grace = spec.patience
      n.joined = self.day
      n.prospect = prospect or false
      n.expires = self.day + 5
      self:refresh()
      return n
    end
  end
  return nil
end

--------------------------------------------------------------------------------
-- Flow
--------------------------------------------------------------------------------

function City:refresh()
  self.served = {}
  self.detail = { edge = {}, node = {} }
  self.flowBy = {}
  for name in pairs(Graph.COMMODITIES) do
    local flow, _, served, detail = self.g:maxflow(false, name)
    self.flowBy[name] = flow
    for id, v in pairs(served or {}) do self.served[id] = v end
    for id, v in pairs((detail or {}).edge or {}) do self.detail.edge[id] = v end
    for id, v in pairs((detail or {}).node or {}) do
      self.detail.node[id] = (self.detail.node[id] or 0) + v
    end
  end

  self.unserved = 0
  for _, c in ipairs(self:clientList()) do
    if (self.served[c.id] or 0) < c.demand then self.unserved = self.unserved + 1 end
  end
  return self.served
end

function City:dailyRevenue()
  local rev = 0
  for _, c in ipairs(self:clientList()) do
    rev = rev + (self.served[c.id] or 0) * c.rate
  end
  for _, n in ipairs(self.g:aliveNodes()) do
    if n.kind == "source" then rev = rev + City.rules.sourceIncome end
  end
  return rev
end

function City:leakChance(e)
  local q = 1 - City.rules.qualityStep * self.quality
  local g = ((e.grade or 1) >= 2) and 0.5 or 1
  local a, b = self.g.nodes[e.a], self.g.nodes[e.b]
  for _, n in ipairs(self.g:nodesOfKind("tower")) do
    if (n.x - (a.x + b.x) / 2)^2 + (n.y - (a.y + b.y) / 2)^2 <= 220^2 then
      g = g * 0.45
      break
    end
  end
  return City.rules.leakBase * q * g
end

--------------------------------------------------------------------------------
-- The day ends
--------------------------------------------------------------------------------

function City:endDay()
  if self.bankrupt then return nil end
  self:refresh()

  local report = {
    day = self.day, revenue = 0, interest = 0, leaks = {}, burst = {}, expenses = self:dailyExpenses(),
    left = {}, arrived = nil, unhappy = 0,
  }

  -- 1. Customers pay for what arrived, and lose patience for what did not.
  for _, c in ipairs(self:clientList()) do
    local got = self.served[c.id] or 0
    report.revenue = report.revenue + got * c.rate
    if got >= c.demand then
      c.grace = City.CLIENTS[c.clientType].patience
    else
      c.grace = c.grace - 1
      report.unhappy = report.unhappy + 1
      if c.grace <= 0 then
        report.left[#report.left + 1] = { name = City.CLIENTS[c.clientType].name, x = c.x, y = c.y }
        self:retireClient(c)
        self.reputation = math.max(0, self.reputation - City.rules.repLoss)
        self.lostClients = self.lostClients + 1
        self:note("%s left: unsupplied too long. Reputation %d",
          City.CLIENTS[c.clientType].name, self.reputation)
      end
    end
  end

  -- 2. Wholesale from the wells.
  for _, n in ipairs(self.g:aliveNodes()) do
    if n.kind == "source" then report.revenue = report.revenue + City.rules.sourceIncome end
  end
  self.money = self.money + report.revenue - report.expenses

  -- 3. Pipes foul. A leak is a condition, not an event: it keeps costing
  --    capacity every day until somebody pays to fix it.
  for _, e in ipairs(self.g.edges) do
    if e.alive then
      if not e.leaking and self:random() < self:leakChance(e) then
        e.leaking = true
        self:note("Leak found on a %s main", e.commodity)
      end
      if e.leaking then
        e.cap = math.max(0, e.cap - 1)
        local na, nb = self.g.nodes[e.a], self.g.nodes[e.b]
        if e.cap <= 0 then
          report.burst[#report.burst + 1] = { x = (na.x + nb.x) / 2, y = (na.y + nb.y) / 2 }
          if not e.burstReported then self:note("A %s main is out of service: repair required", e.commodity) end
          e.burstReported = true
        else
          report.leaks[#report.leaks + 1] = { x = (na.x + nb.x) / 2, y = (na.y + nb.y) / 2 }
        end
      end
    end
  end

  -- 4. Investments mature.
  for i = #self.investments, 1, -1 do
    local inv = self.investments[i]
    if self.day >= inv.matures then
      local r = gauss(self, City.rules.investMean, City.rules.investSd)
      local payout = math.floor(inv.amount * (1 + r))
      self.money = self.money + payout
      report.interest = report.interest + (payout - inv.amount)
      self:note("Investment returned $%d on $%d (%+.1f%%)", payout, inv.amount, r * 100)
      table.remove(self.investments, i)
    end
  end

  -- 5. Word gets around.
  local chance = City.rules.arriveBase + self.reputation / 500
                 + ((self.adDaysLeft > 0) and City.rules.adBoost or 0)
  if #self:clientList(true) < 4 and (self:random() < chance or self.day % 3 == 0) then
    local c = self:addClient(nil, true)
    if c then
      report.arrived = { name = City.CLIENTS[c.clientType].name, x = c.x, y = c.y }
      self:note("%s requested a connection", City.CLIENTS[c.clientType].name)
    end
  end
  if self.adDaysLeft > 0 then self.adDaysLeft = self.adDaysLeft - 1 end
  for _, c in ipairs(self:clientList(true)) do
    if c.expires <= self.day then self:retireClient(c) end
  end

  report.bonus = self:awardMilestones()

  if report.unhappy == 0 and #self:clientList() > 0 then
    self.reputation = math.min(100, self.reputation + 1)
  end

  self.history[#self.history + 1] = {
    day = self.day, money = self.money, clients = #self:clientList(),
    revenue = report.revenue, expenses = report.expenses,
  }

  self.day = self.day + 1
  if self.money < 0 and self:investedTotal() == 0 then
    self.bankrupt = true
    self:note("The company is insolvent.")
  end

  self:refresh()
  report.money = self.money
  report.bankrupt = self.bankrupt
  self.lastReport = report
  return report
end

function City:valuation()
  local v = self.money + self:investedTotal()
  for _, n in ipairs(self.g:aliveNodes()) do
    if n.kind ~= "client" then v = v + (n.paid or (n.kind == "source" and 260) or self:nodeCost(n.kind)) end
  end
  for _, e in ipairs(self.g.edges) do if e.alive then v = v + (e.paid or 0) end end
  return math.floor(v)
end

function City:acceptClient(id)
  local c = self.g.nodes[id]
  if not (c and c.alive and c.prospect) then return nil, "no open offer" end
  c.prospect, c.joined = false, self.day
  self:note("%s contract signed: %d days to deliver", City.CLIENTS[c.clientType].name, c.grace)
  self:refresh()
  return c
end

function City:toggleSupply(id)
  local c = self.g.nodes[id]
  if not (c and c.alive and c.kind == "client" and not c.prospect) then
    return nil, "no active customer"
  end
  c.supplyClosed = not c.supplyClosed
  self:note("%s %d service valve %s", City.CLIENTS[c.clientType].name, id,
    c.supplyClosed and "closed" or "opened")
  self:refresh()
  return c
end

function City:retireClient(c)
  if self.g:degree(c.id) == 0 then
    self.g:killNode(c.id)
  else
    -- The customer leaves the company; their installed through-pipes remain.
    c.kind, c.paid = "junction", 0
    c.commodity, c.demand, c.prospect, c.supplyClosed = nil, nil, nil, nil
  end
end

function City:declineClient(id)
  local c = self.g.nodes[id]
  if not (c and c.alive and c.prospect) then return nil, "no open offer" end
  self:retireClient(c)
  self:refresh()
  return true
end

function City:dailyExpenses()
  local total = 8
  for _, n in ipairs(self.g:aliveNodes()) do
    if n.kind == "source" then total = total + 6
    elseif n.kind ~= "client" then total = total + 1 end
  end
  for _, e in ipairs(self.g.edges) do if e.alive then total = total + 0.5 end end
  return math.ceil(total)
end

City.MILESTONES = {
  {name = "First supply", target = 2, reward = 60},
  {name = "Neighbourhood utility", target = 5, reward = 150},
  {name = "City supplier", target = 10, reward = 350},
  {name = "Utility empire", target = 20, reward = 800},
}

function City:awardMilestones()
  local count, total = 0, 0
  for _, c in ipairs(self:clientList()) do
    if c.alive and (self.served[c.id] or 0) >= c.demand then count = count + 1 end
  end
  for i, m in ipairs(City.MILESTONES) do
    if not self.milestones[i] and count >= m.target then
      self.milestones[i] = true
      self.money = self.money + m.reward
      total = total + m.reward
      self:note("%s: $%d municipal grant", m.name, m.reward)
    end
  end
  return total
end

return City
