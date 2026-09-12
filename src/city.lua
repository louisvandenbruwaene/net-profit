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

-- Structures. These are shared ground: a manifold hosts water and oil alike, so
-- their price does not depend on what flows through them.
City.price = {
  junction = 22, manifold = 46, pump = 38, tower = 92, gate = 30, depot = 190,
  terminal = 1400,
  powerLicence = 340, beerLicence = 600, oilLicence = 1500,
  qualityBase = 140,
  ads = 90,
}

-- Everything a pipe costs, per trade.
--
-- A pipe is priced the way a contractor would price it: two tie-ins, a trench,
-- and a bore. The tie-ins are charged per end regardless of length, because
-- connecting a house to a main that runs past its door is still a day's work
-- with a digger. The trench is charged per metre. The bore -- extra capacity --
-- is charged both as fittings at the ends and as the wider pipe along the whole
-- run, so a fat trunk main across the map is the most expensive thing you can
-- build and a fat stub is nearly free.
--
-- Water is cheap and thin-margined. Beer is food-grade: sanitary fittings,
-- gentler pumps, more of everything. Oil is pressurised and hazardous, and its
-- prices say so -- which is the reason a factory pays $26 a unit and a house
-- pays $4.
City.trade = {
  water = {
    tiein = 14, trench = 0.11, bore = 7, borePerM = 0.028,
    repairBase = 14, repairPerLost = 6, repairPerM = 0.030,
    liningRate = 0.40, armourRate = 0.72,
    upkeep = 0.30, upkeepPerM = 0.0016,
    sourceBase = 260, sourceGrowth = 1.55, sourceOutput = 14,
    upgradeBase = 140, upgradeGrowth = 1.48, upgradeStep = 4,
    wholesale = 12, wholesalePerUnit = 0.55, sourceUpkeep = 6,
    importCost = 1.2,
  },
  -- Electricity sits between water and beer: cables are dearer than a water
  -- trench and cheaper than a sanitary beer main, and a workshop pays more than
  -- a household and less than a pub. It is the first trade worth expanding into.
  power = {
    tiein = 20, trench = 0.16, bore = 10, borePerM = 0.038,
    repairBase = 22, repairPerLost = 9, repairPerM = 0.044,
    liningRate = 0.40, armourRate = 0.72,
    upkeep = 0.45, upkeepPerM = 0.0023,
    sourceBase = 340, sourceGrowth = 1.46, sourceOutput = 12,
    upgradeBase = 220, upgradeGrowth = 1.48, upgradeStep = 4,
    wholesale = 18, wholesalePerUnit = 0.90, sourceUpkeep = 8,
    importCost = 3.0,
  },
  beer = {
    tiein = 26, trench = 0.21, bore = 13, borePerM = 0.050,
    repairBase = 30, repairPerLost = 13, repairPerM = 0.060,
    liningRate = 0.40, armourRate = 0.72,
    upkeep = 0.60, upkeepPerM = 0.0030,
    sourceBase = 420, sourceGrowth = 1.38, sourceOutput = 10,
    upgradeBase = 300, upgradeGrowth = 1.50, upgradeStep = 3,
    wholesale = 26, wholesalePerUnit = 1.30, sourceUpkeep = 11,
    importCost = 5.5,
  },
  oil = {
    tiein = 44, trench = 0.34, bore = 21, borePerM = 0.085,
    repairBase = 52, repairPerLost = 21, repairPerM = 0.105,
    liningRate = 0.40, armourRate = 0.72,
    upkeep = 1.00, upkeepPerM = 0.0050,
    sourceBase = 900, sourceGrowth = 1.38, sourceOutput = 10,
    upgradeBase = 620, upgradeGrowth = 1.50, upgradeStep = 3,
    wholesale = 44, wholesalePerUnit = 2.20, sourceUpkeep = 17,
    importCost = 9.0,
  },
}

-- Rail. A haven lands freight at the edge of the city and rail moves it inland,
-- which is a different problem from plumbing: the yard at each end is the
-- expensive part, the run itself is cheap by the metre once it exists, it
-- reaches across whole districts, and it does not corrode. Track never leaks,
-- so it is the one link in the game you build and then forget about.
City.rail = {
  tiein = 240, perM = 0.52, bore = 4, borePerM = 0.011,
  upkeep = 1.4, upkeepPerM = 0.0038, range = 1400,
}

-- Pipe condition. Lining is never required -- a bare pipe works exactly as well
-- on the day it is laid. It buys three things at once: a pipe that fouls far
-- less often, a cheaper repair when it does, and a player who spends the day
-- building instead of chasing burst mains. On a short water stub that is a poor
-- trade. On a 600m oil trunk it pays for itself in about a fortnight.
City.GRADES = {
  { name = "Bare",     risk = 1.00, repair = 1.00, decay = 1 },
  { name = "Lined",    risk = 0.45, repair = 0.70, decay = 1 },
  -- Armour is the luxury grade. Its money payback is slow by design; what it
  -- actually buys is a main that almost never fails and, when it does, bleeds
  -- capacity at half speed -- so it is bought for peace of mind on the trunk
  -- routes a whole district hangs off, not to save a few dollars a week.
  { name = "Armoured", risk = 0.12, repair = 0.45, decay = 2 },
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
  startMoney = 380,   -- two connections and a little room; prices are per-trade now
}

-- Customers. Rich ones pay far more and forgive far less, which is the whole
-- reason to lay a beer main instead of another row of houses.
City.CLIENTS = {
  house   = { name = "HOUSE",   commodity = "water", demand = {2, 4}, rate = 4,  patience = 3, weight = 10 },
  estate  = { name = "ESTATE",  commodity = "water", demand = {5, 7}, rate = 6,  patience = 2, weight = 3 },
  workshop= { name = "WORKSHOP",commodity = "power", demand = {3, 5}, rate = 10, patience = 2, weight = 7 },
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
  self.bounds = { x = 0, y = 0, w = City.MAP.cols * City.MAP.w, h = City.MAP.rows * City.MAP.h }
  self.g = Graph.new()
  self.day = 1
  self.money = City.rules.startMoney
  self.reputation = 50
  self.quality = 0
  self.adDaysLeft = 0
  self.investments = {}
  self.obstacles = {}
  self.deposits = {}
  self.licences = { water = true, power = false, beer = false, oil = false }
  self.permits = { park = false, river = false, bedrock = false }
  self.sourcesBought = 0
  self.log = {}
  self.history = {}
  self.bankrupt = false
  self.lostClients = 0
  self.pipeGrade = {}
  self.milestones = {}
  self.crews = 0
  self.tenders = {}
  self.tendersDone = 0
  self.nextTender = 1
  self.loan = 0
  self.event = nil
  self.districtsBought = 0

  self:layOutDistricts(opts)

  local home = self.districts[City.MAP.start]
  local cx, cy = home.x + home.w / 2, home.y + home.h / 2
  local src = self.g:addNode(cx, cy, "source")
  src.commodity = "water"
  src.output = City.trade.water.sourceOutput
  src.level = 1
  self.firstSource = src

  for i = 1, 2 do
    local c = self:addClient("house")
    c.x, c.y = cx + (i == 1 and -210 or 220), cy + (i == 1 and -70 or 65)
    c.demand = 3
  end

  self:refresh()
  return self
end

--------------------------------------------------------------------------------
-- The map: twelve districts, one of them yours
--------------------------------------------------------------------------------

-- Ground you have not bought is ground you cannot build on, and the map is
-- deliberately larger than one company can afford early. A district is the
-- single biggest cheque in the game, and buying one is the only way to reach
-- the trades that live out there.
City.MAP = { cols = 4, rows = 3, w = 1000, h = 700, start = 6 }

City.DISTRICTS = {
  { name = "Northgate",   bias = { house = 16, workshop = 5, estate = 3 },  rough = 2, haven = "highway" },
  { name = "Hillcrest",   bias = { house = 5,  estate = 12 },             rough = 2 },
  { name = "The Moors",   bias = { house = 4,  estate = 4 },              rough = 5, seams = 2 },
  { name = "Ironworks",   bias = { factory = 14, workshop = 9, house = 4 },  rough = 3, seams = 1 },
  { name = "Old Town",    bias = { house = 12, pub = 8 },                 rough = 2 },
  { name = "Millbrook",   bias = { house = 10, estate = 3, workshop = 4, pub = 4, factory = 3 }, rough = 2 },
  { name = "Brewers Row", bias = { pub = 15, house = 5 },                 rough = 2, seams = 1 },
  { name = "Docklands",   bias = { factory = 13, workshop = 7, pub = 5 },   rough = 3, haven = "port" },
  { name = "Southfield",  bias = { estate = 13, house = 6 },              rough = 2 },
  { name = "Canalside",   bias = { pub = 10, house = 8 },                 rough = 3 },
  { name = "The Flats",   bias = { house = 14, workshop = 6, estate = 5 },  rough = 2, haven = "airfield" },
  { name = "Deepcut",     bias = { factory = 12, workshop = 8, estate = 4 }, rough = 5, seams = 3 },
}

City.districtPrice = { base = 700, growth = 1.42 }

function City:layOutDistricts(opts)
  self.districts = {}
  for row = 1, City.MAP.rows do
    for col = 1, City.MAP.cols do
      local i = (row - 1) * City.MAP.cols + col
      local spec = City.DISTRICTS[i]
      self.districts[i] = {
        id = i, col = col, row = row, name = spec.name,
        x = (col - 1) * City.MAP.w, y = (row - 1) * City.MAP.h,
        w = City.MAP.w, h = City.MAP.h,
        owned = (i == City.MAP.start),
      }
    end
  end
  -- Ground features are laid out for the whole map at once, so what you are
  -- buying is visible before you buy it.
  local density = opts.obstacles
  for i, d in ipairs(self.districts) do
    local spec = City.DISTRICTS[i]
    local n = density or spec.rough
    if density and density == 0 then n = 0 end
    self:scatterObstacles(n, d)
    if not (density and density == 0) then self:scatterSeams(spec.seams or 0, d) end
  end
end

function City:districtAt(x, y)
  for _, d in ipairs(self.districts) do
    if x >= d.x and x < d.x + d.w and y >= d.y and y < d.y + d.h then return d end
  end
  return nil
end

function City:ownedDistricts()
  local t = {}
  for _, d in ipairs(self.districts) do if d.owned then t[#t + 1] = d end end
  return t
end

-- Only next door. The company grows outward from its yard, not by teleporting
-- to the far corner of the map.
function City:districtAdjacent(d)
  for _, o in ipairs(self.districts) do
    if o.owned and math.abs(o.col - d.col) + math.abs(o.row - d.row) == 1 then return true end
  end
  return false
end

function City:districtCost(d)
  return math.ceil(City.districtPrice.base * (City.districtPrice.growth ^ self.districtsBought))
end

function City:districtError(id)
  local d = self.districts[id]
  if not d then return "no such district" end
  if d.owned then return "already owned" end
  if not self:districtAdjacent(d) then return "not next to your ground" end
  if self:districtCost(d) > self.money then return "not enough cash" end
  return nil
end

function City:buyDistrict(id)
  local err = self:districtError(id)
  if err then return nil, err end
  local d = self.districts[id]
  local cost = self:districtCost(d)
  self:spend(cost)
  d.owned = true
  self.districtsBought = self.districtsBought + 1
  self:note("%s acquired for $%d: %d districts held", d.name, cost, #self:ownedDistricts())
  return d
end

--------------------------------------------------------------------------------
-- Permits: the ground you are not allowed to touch, until you are
--------------------------------------------------------------------------------

-- Each permit converts an obstacle from a wall into a toll. Parkland becomes
-- ordinary ground, the river becomes a manageable crossing, and bedrock becomes
-- expensive but passable -- which matters because the richest seams are under it.
City.PERMITS = {
  park    = { name = "Parkland easement",  cost = 760,  cross = 1.0, order = 1 },
  river   = { name = "River works charter", cost = 1500, cross = 1.6, order = 2 },
  bedrock = { name = "Blasting licence",    cost = 2900, cross = 4.0, order = 3 },
}
City.PERMIT_ORDER = { "park", "river", "bedrock" }

function City:buyPermit(kind)
  local spec = City.PERMITS[kind]
  if not spec then return nil, "unknown permit" end
  if self.permits[kind] then return nil, "already held" end
  if spec.cost > self.money then return nil, "not enough cash" end
  self:spend(spec.cost)
  self.permits[kind] = true
  self:note("%s granted: %s is now workable ground", spec.name,
    string.lower(City.OBSTACLES[kind].name))
  self:refresh()
  return true
end

function City:note(fmt, ...)
  table.insert(self.log, 1, { text = string.format(fmt, ...), day = self.day })
  for i = #self.log, 40, -1 do self.log[i] = nil end
end

--------------------------------------------------------------------------------
-- Ground
--------------------------------------------------------------------------------

function City:scatterObstacles(n, district)
  local kinds = { "bedrock", "park", "river" }
  local b = district or self.bounds
  local home = district and district.owned
  for _ = 1, n do
    for _ = 1, 40 do
      local r = self:rand(70, 140)
      local x = self:rand(b.x + r + 30, b.x + b.w - r - 30)
      local y = self:rand(b.y + r + 30, b.y + b.h - r - 30)
      local clear = true
      -- The home district keeps a wide clearing so the opening is never a maze.
      local margin = home and 340 or 150
      for _, node in ipairs(self.g:aliveNodes()) do
        if (node.x - x) ^ 2 + (node.y - y) ^ 2 < (r + margin) ^ 2 then clear = false; break end
      end
      if home and (x - (b.x + b.w / 2)) ^ 2 + (y - (b.y + b.h / 2)) ^ 2 < (r + 340) ^ 2 then
        clear = false
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

-- Seams are the reason to look at the map rather than at the sidebar. A well
-- sunk on one is cheaper and yields half again as much, and the best of them
-- sit under bedrock, where nobody can reach them without a blasting licence.
function City:scatterSeams(n, district)
  local b = district or self.bounds
  for _ = 1, n do
    for _ = 1, 60 do
      local x = self:rand(b.x + 90, b.x + b.w - 90)
      local y = self:rand(b.y + 90, b.y + b.h - 90)
      local far = true
      for _, s in ipairs(self.deposits) do
        if (s.x - x) ^ 2 + (s.y - y) ^ 2 < 300 ^ 2 then far = false; break end
      end
      for _, node in ipairs(self.g:aliveNodes()) do
        if (node.x - x) ^ 2 + (node.y - y) ^ 2 < 260 ^ 2 then far = false; break end
      end
      if far then
        local roll = self:random()
        local commodity = roll < 0.52 and "water" or roll < 0.80 and "beer" or "oil"
        local buried = self:obstacleAt(x, y)
        self.deposits[#self.deposits + 1] = {
          x = x, y = y, commodity = commodity, taken = false,
          yield = buried and 1.9 or 1.5, discount = buried and 0.45 or 0.62,
        }
        break
      end
    end
  end
end

City.seamRange = 70

function City:seamAt(x, y)
  for _, s in ipairs(self.deposits or {}) do
    if not s.taken and (s.x - x) ^ 2 + (s.y - y) ^ 2 <= City.seamRange ^ 2 then return s end
  end
  return nil
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

-- What one square of ground charges to be crossed, given the permits held.
function City:groundCross(kind)
  if self.permits and self.permits[kind] then return City.PERMITS[kind].cross end
  return City.OBSTACLES[kind].cross
end

-- Returns a cost multiplier, or nil if the route is impossible.
function City:crossingCost(ax, ay, bx, by)
  local mult = 1
  for _, o in ipairs(self.obstacles) do
    if segCircle(ax, ay, bx, by, o.x, o.y, o.r) then
      local cross = self:groundCross(o.kind)
      if not cross then return nil, o end
      mult = math.max(mult, cross)
    end
  end
  return mult
end

function City:placementError(x, y)
  local b = self.bounds
  if x < b.x or y < b.y or x > b.x + b.w or y > b.y + b.h then return "outside the map" end
  local d = self:districtAt(x, y)
  if not d then return "outside the map" end
  if not d.owned then return "you do not own " .. d.name end
  local o = self:obstacleAt(x, y)
  if o and not (self.permits and self.permits[o.kind]) then
    return "cannot build on " .. string.lower(City.OBSTACLES[o.kind].name)
  end
  for _, n in ipairs(self.g:aliveNodes()) do
    if (n.x - x) ^ 2 + (n.y - y) ^ 2 < City.rules.minSpacing ^ 2 then
      return "too close to another structure"
    end
  end
  return nil
end

function City:rangeBetween(a, b, rail)
  local ka, kb = self.g.nodes[a].kind, self.g.nodes[b].kind
  if rail then return City.rail.range end
  if ka == "pump" or kb == "pump" then return City.rules.pumpRange end
  return City.rules.linkRange
end

-- Track runs from a haven inland. One end must be a terminal, which is what
-- makes rail infrastructure rather than a second kind of pipe.
function City:railEndpoint(a, b)
  return self.g.nodes[a].kind == "terminal" or self.g.nodes[b].kind == "terminal"
end

function City:railQuote(a, b, capacity)
  capacity = capacity or 1
  local metres = self:nodeDistance(a, b)
  local na, nb = self.g.nodes[a], self.g.nodes[b]
  local mult = self:crossingCost(na.x, na.y, nb.x, nb.y) or 1
  local q = {
    metres = metres, ground = mult, capacity = capacity, rail = true,
    tiein = math.ceil(City.rail.tiein * 2),
    trench = math.ceil(metres * City.rail.perM * mult),
    bore = math.ceil(math.max(0, capacity - 1) * (City.rail.bore + metres * City.rail.borePerM)),
  }
  q.total = q.tiein + q.trench + q.bore
  return q
end

function City:pipeError(a, b, commodity, rail)
  if not self.licences[commodity] then return "no licence for that" end
  if rail and not self:railEndpoint(a, b) then return "track must start or end at a haven" end
  local ok, why = self.g:canLink(a, b)
  -- Two structures may carry one pipe of each commodity between them.
  if not ok and why ~= "link already exists" then return why end
  if self:pipeBetween(a, b, commodity) then return "that pipe already exists" end
  if self.g:freePorts(a) < 1 then return "no free ports there" end
  if self.g:freePorts(b) < 1 then return "no free ports there" end

  local na, nb = self.g.nodes[a], self.g.nodes[b]
  local d = math.sqrt((na.x - nb.x) ^ 2 + (na.y - nb.y) ^ 2)
  if d > self:rangeBetween(a, b, rail) then
    return rail and "too far even for track" or "too far: use a pump"
  end
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

-- What it costs to break into the network at a given structure. A wellhead is
-- the awkward end of the job; a manifold is a set of ports waiting for you.
City.TIEIN = {
  source = 1.6, client = 1.0, junction = 0.7, manifold = 0.7,
  pump = 1.1, tower = 1.0, gate = 0.8, depot = 1.2,
}

function City:tieinCost(id, commodity)
  local n = self.g.nodes[id]
  local trade = City.trade[commodity] or City.trade.water
  return trade.tiein * (City.TIEIN[n and n.kind] or 1.0)
end

function City:nodeDistance(a, b)
  local na, nb = self.g.nodes[a], self.g.nodes[b]
  return math.sqrt((na.x - nb.x) ^ 2 + (na.y - nb.y) ^ 2)
end

function City:pipeLength(e)
  return self:nodeDistance(e.a, e.b)
end

-- The itemised quote. The UI shows this line by line, because a price the
-- player cannot decompose is a price they cannot plan around.
function City:pipeQuote(a, b, commodity, capacity, rail)
  if rail then return self:railQuote(a, b, capacity) end
  capacity = capacity or 1
  local trade = City.trade[commodity] or City.trade.water
  local na, nb = self.g.nodes[a], self.g.nodes[b]
  local metres = self:nodeDistance(a, b)
  local mult = self:crossingCost(na.x, na.y, nb.x, nb.y) or 1
  local tiein = self:tieinCost(a, commodity) + self:tieinCost(b, commodity)
  local trench = metres * trade.trench * mult
  local extra = math.max(0, capacity - 1)
  -- Wider pipe costs more per metre and more at the fittings, so the price of
  -- capacity is a question of how far you are carrying it.
  local bore = extra * (trade.bore + metres * trade.borePerM * mult)
  local q = {
    metres = metres, ground = mult, capacity = capacity, commodity = commodity,
    tiein = math.ceil(tiein), trench = math.ceil(trench), bore = math.ceil(bore),
  }
  q.total = q.tiein + q.trench + q.bore
  return q
end

function City:pipeCost(a, b, commodity, capacity, rail)
  return self:pipeQuote(a, b, commodity, capacity, rail).total
end

-- One more unit through an existing trench: fittings at both ends plus the
-- wider bore over its whole length. Widening a long oil trunk is a real
-- decision; widening a stub is loose change.
function City:boreCost(e, units)
  units = units or 1
  if e.rail then
    return math.ceil(units * (City.rail.bore + self:pipeLength(e) * City.rail.borePerM))
  end
  local trade = City.trade[e.commodity] or City.trade.water
  local na, nb = self.g.nodes[e.a], self.g.nodes[e.b]
  local metres = self:pipeLength(e)
  local mult = self:crossingCost(na.x, na.y, nb.x, nb.y) or 1
  return math.ceil(units * (trade.bore + metres * trade.borePerM * mult))
end

function City:gradeOf(e) return City.GRADES[e.grade or 1] or City.GRADES[1] end

-- A burst main is charged by what it is and how far it runs, then discounted by
-- what it is lined with. This is where lining pays itself back.
function City:repairCost(e)
  local trade = City.trade[e.commodity] or City.trade.water
  local lost = (e.capMax or e.cap) - e.cap
  local raw = trade.repairBase
    + trade.repairPerLost * math.max(1, lost)
    + self:pipeLength(e) * trade.repairPerM
  return math.ceil(raw * self:gradeOf(e).repair)
end

-- Lining is priced off the route it protects, so the pipes worth lining are
-- exactly the long, wide, expensive ones that hurt most when they burst.
function City:liningCost(e)
  local grade = e.grade or 1
  if e.rail then return nil end
  if grade >= #City.GRADES then return nil end
  local trade = City.trade[e.commodity] or City.trade.water
  local route = self:pipeQuote(e.a, e.b, e.commodity, e.capMax or e.cap)
  local rate = (grade == 1) and trade.liningRate or trade.armourRate
  return math.ceil(math.max(18, (route.trench + route.bore) * rate + trade.tiein))
end

-- Daily running cost of one pipe: a long pressurised oil main is not the same
-- liability as a garden stub, and the ledger should say so.
function City:pipeUpkeep(e)
  if e.rail then return City.rail.upkeep + self:pipeLength(e) * City.rail.upkeepPerM end
  local trade = City.trade[e.commodity] or City.trade.water
  return trade.upkeep + self:pipeLength(e) * trade.upkeepPerM
end

function City:sourceCost(commodity, x, y)
  local trade = City.trade[commodity] or City.trade.water
  local n = (commodity == "water") and self.sourcesBought or (self.premiumBought and self.premiumBought[commodity]) or 0
  local base = math.ceil(trade.sourceBase * (trade.sourceGrowth ^ n))
  if x then
    local seam = self:seamAt(x, y)
    if seam and seam.commodity == commodity then return math.ceil(base * seam.discount), seam end
  end
  return base
end

-- Upgrading a well is the hub's reason to exist: it needs no new route, no new
-- tie-in and no new ground, so it is the cheap way to add supply until the
-- levels get steep -- at which point sinking a new well is cheaper again.
City.sourceMaxLevel = 6

function City:sourceUpgradeCost(n)
  local trade = City.trade[n.commodity] or City.trade.water
  local level = n.level or 1
  return math.ceil(trade.upgradeBase * (trade.upgradeGrowth ^ (level - 1)))
end

function City:upgradeSource(id)
  local n = self.g.nodes[id]
  if not (n and n.alive and n.kind == "source") then return nil, "no such source" end
  local level = n.level or 1
  if level >= City.sourceMaxLevel then return nil, "well is at full yield" end
  local cost = self:sourceUpgradeCost(n)
  if cost > self.money then return nil, "not enough cash" end
  local trade = City.trade[n.commodity] or City.trade.water
  self:spend(cost)
  n.level = level + 1
  n.output = (n.output or trade.sourceOutput) + trade.upgradeStep
  n.paid = (n.paid or 0) + cost
  self:note("%s well deepened to level %d: output now %d",
    string.upper(n.commodity), n.level, n.output)
  self:refresh()
  return n
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

City.BUILDABLE = { junction = true, manifold = true, pump = true, tower = true,
                   gate = true, depot = true, terminal = true }

-- Havens are not everywhere. Three districts have the ground for one -- the
-- docks, the airfield and the trunk road -- and a terminal can only be built
-- where the freight can actually arrive. It is the sharpest reason in the game
-- to buy one district rather than another.
City.HAVENS = {
  port     = { name = "NAVAL PORT",  blurb = "deep-water berths" },
  airfield = { name = "AIRFIELD",    blurb = "an air freight apron" },
  highway  = { name = "HIGHWAY HEAD", blurb = "a trunk road interchange" },
}

function City:havenAt(x, y)
  local d = self:districtAt(x, y)
  if not d then return nil end
  local spec = City.DISTRICTS[d.id]
  return spec and spec.haven, d
end

function City:havenDistricts()
  local t = {}
  for i, spec in ipairs(City.DISTRICTS) do
    if spec.haven then t[#t + 1] = { district = self.districts[i], haven = spec.haven } end
  end
  return t
end

City.terminalOutput = 24
City.terminalUpkeep = 14

function City:build(x, y, kind, commodity)
  if not City.BUILDABLE[kind] then return nil, "choose a structure" end
  local err = self:placementError(x, y)
  if err then return nil, err end
  if kind == "terminal" then
    local haven = self:havenAt(x, y)
    if not haven then return nil, "no haven here: build at the port, airfield or highway" end
    if not self.licences[commodity or "water"] then return nil, "no licence for that trade" end
  end
  local cost = self:nodeCost(kind)
  if cost > self.money then return nil, "not enough cash" end
  self:spend(cost)
  local n = self.g:addNode(x, y, kind)
  n.paid = cost
  if kind == "gate" then
    -- A gate starts wide open; the point of it is that the player narrows it.
    n.throughput = 6
  elseif kind == "depot" then
    n.throughput = 999
    n.commodity = commodity or "water"
    n.stored, n.capacityStore = 0, City.depotCapacity
  elseif kind == "terminal" then
    n.throughput = 999
    n.commodity = commodity or "water"
    n.output = City.terminalOutput
    n.haven = self:havenAt(x, y)
    self:note("%s opened: %d %s a day, billed per unit landed",
      City.HAVENS[n.haven].name, n.output, n.commodity)
  else
    n.throughput = 999
  end
  self:refresh()
  return n
end

City.depotCapacity = 18
City.depotFillRate = 8

-- A gate is the only structure whose value is in closing it. Setting it below a
-- branch's demand starves that branch on purpose, which is how scarce supply
-- gets pointed at the customers who actually pay.
function City:setGate(id, value)
  local n = self.g.nodes[id]
  if not (n and n.alive and n.kind == "gate") then return nil, "no such gate" end
  if type(value) ~= "number" or value ~= value then return nil, "invalid setting" end
  value = math.max(0, math.min(24, math.floor(value)))
  n.throughput = value
  self:refresh()
  return n
end

function City:layPipe(a, b, commodity, capacity, rail)
  capacity = capacity or 1
  if type(capacity) ~= "number" or capacity % 1 ~= 0 or capacity < 1 or capacity > 24 then
    return nil, "capacity must be between 1 and 24"
  end
  local err = self:pipeError(a, b, commodity, rail)
  if err then return nil, err end
  local cost = self:pipeCost(a, b, commodity, capacity, rail)
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
  e.rail = rail or nil
  e.leaking = false
  self:refresh()
  return e
end

function City:upgradePipe(id)
  local e = self.g.edges[id]
  if not (e and e.alive) then return nil, "no such pipe" end
  if e.capMax >= 24 then return nil, "maximum capacity reached" end
  local cost = self:boreCost(e, 1)
  if cost > self.money then return nil, "not enough cash" end
  self:spend(cost)
  e.paid = (e.paid or self:pipeCost(e.a, e.b, e.commodity, e.capMax)) + cost
  e.cap = e.cap + 1
  e.capMax = (e.capMax or e.cap) + 1
  self:refresh()
  return e
end

-- Every leak the company can afford, cheapest first, in one decision. The
-- point is not to save money -- it saves none -- but to save the twenty clicks
-- that stand between a player and the part of the game they came for.
function City:repairAll()
  local order = {}
  for _, e in ipairs(self.g.edges) do
    if e.alive and (e.leaking or e.cap < (e.capMax or e.cap)) then order[#order + 1] = e end
  end
  table.sort(order, function(a, b) return self:repairCost(a) < self:repairCost(b) end)
  local fixed, spent = 0, 0
  for _, e in ipairs(order) do
    local cost = self:repairCost(e)
    if cost <= self.money then
      self.money = self.money - cost
      e.cap = e.capMax or e.cap
      e.leaking, e.burstReported, e.decayTick = false, nil, nil
      fixed, spent = fixed + 1, spent + cost
    end
  end
  if fixed == 0 then return nil, "nothing to repair" end
  self:note("Repaired %d main%s for $%d", fixed, fixed == 1 and "" or "s", spent)
  self:refresh()
  return { fixed = fixed, spent = spent }
end

-- Total bill to put the whole network back in order, for the button that does it.
function City:repairAllCost()
  local total, count = 0, 0
  for _, e in ipairs(self.g.edges) do
    if e.alive and (e.leaking or e.cap < (e.capMax or e.cap)) then
      total, count = total + self:repairCost(e), count + 1
    end
  end
  return total, count
end

function City:repairPipe(id)
  local e = self.g.edges[id]
  if not (e and e.alive) then return nil, "no such pipe" end
  if not e.leaking and e.cap >= (e.capMax or e.cap) then return nil, "nothing to repair" end
  local cost = self:repairCost(e)
  if cost > self.money then return nil, "not enough cash" end
  self:spend(cost)
  e.cap = e.capMax or e.cap
  e.leaking, e.decayTick = false, nil
  e.burstReported = nil
  self:refresh()
  return cost
end

function City:reinforcePipe(id)
  local e = self.g.edges[id]
  if not (e and e.alive) then return nil, "no such pipe" end
  local cost = self:liningCost(e)
  if not cost then return nil, "already armoured" end
  if cost > self.money then return nil, "not enough cash" end
  self:spend(cost)
  e.grade = (e.grade or 1) + 1
  e.paid = (e.paid or 0) + cost
  self:note("A %s main was %s for $%d", e.commodity,
    string.lower(City.GRADES[e.grade].name), cost)
  return e
end

function City:demolishPipe(id)
  local e = self.g.edges[id]
  if not (e and e.alive) then return nil, "no such pipe" end
  local refund = math.floor((e.paid or self:pipeCost(e.a, e.b, e.commodity, e.capMax)) * 0.4)
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
  if px then
    local err = self:placementError(px, py)
    if err then return nil, err end
    local cost, seam = self:sourceCost(commodity, px, py)
    if cost > self.money then return nil, "not enough cash" end
    local trade = City.trade[commodity] or City.trade.water
    self:spend(cost)
    local s = self.g:addNode(px, py, "source")
    s.commodity, s.paid, s.level = commodity, cost, 1
    s.output = math.floor(trade.sourceOutput * (seam and seam.yield or 1))
    if seam then
      seam.taken = true
      s.seam = true
      self:note("A %s seam was struck: the well opens at %d output for $%d",
        commodity, s.output, cost)
    else
      self:note("New %s well sunk for $%d", commodity, cost)
    end
    self.premiumBought = self.premiumBought or {}
    if commodity == "water" then self.sourcesBought = self.sourcesBought + 1
    else self.premiumBought[commodity] = (self.premiumBought[commodity] or 0) + 1 end
    self:refresh()
    return s
  end

  -- Somewhere legal, on ground the company owns, and not on top of the works.
  local owned = self:ownedDistricts()
  for _ = 1, 300 do
    local d = owned[self:random(#owned)]
    local x = self:rand(d.x + 90, d.x + d.w - 90)
    local y = self:rand(d.y + 90, d.y + d.h - 90)
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

City.LICENSABLE = { power = true, beer = true, oil = true }

function City:buyLicence(commodity)
  if not City.LICENSABLE[commodity] then return nil, "unknown trade" end
  if self.licences[commodity] then return nil, "already held" end
  local cost = City.price[commodity .. "Licence"]
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

-- Each district has a character, so where you expand decides who comes calling.
-- Buying Brewers Row is how a company gets pubs; buying Docklands is how it
-- gets factories. This is the growth lever the map is for.
function City:pickClientType(district)
  local bias = district and City.DISTRICTS[district.id] and City.DISTRICTS[district.id].bias
  local pool = {}
  for _, key in ipairs({"house", "estate", "workshop", "pub", "factory"}) do
    local spec = City.CLIENTS[key]
    if self.licences[spec.commodity] then
      local weight = (bias and bias[key]) or (bias and 0) or spec.weight
      for _ = 1, weight do pool[#pool + 1] = key end
    end
  end
  if #pool == 0 then return "house" end
  return pool[self:random(#pool)]
end

function City:addClient(kind, prospect, district)
  local owned = self:ownedDistricts()
  district = district or owned[self:random(#owned)]
  kind = kind or self:pickClientType(district)
  local spec = City.CLIENTS[kind]
  -- Customers appear near the works, farther out as the company grows, and
  -- always on ground the company actually owns.
  local sources = {}
  for _, n in ipairs(self.g:nodesOfKind("source")) do
    if n.commodity == spec.commodity then sources[#sources + 1] = n end
  end
  local anchor = #sources > 0 and sources[self:random(#sources)] or self.firstSource
  if district and not (anchor.x >= district.x and anchor.x < district.x + district.w
      and anchor.y >= district.y and anchor.y < district.y + district.h) then
    -- A customer in a newly bought district anchors on that district instead,
    -- so buying ground actually produces enquiries there.
    anchor = { x = district.x + district.w / 2, y = district.y + district.h / 2 }
  end
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
      n.rateBase = spec.rate
      n.rate = self:offerRate(spec.rate)
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

-- Every customer negotiates their own price. Early on the spread is almost
-- nothing, so a small company cannot be killed by drawing three bad offers in a
-- row; as the company grows the spread widens until a lowball house is worth
-- refusing outright and a premium factory is worth rerouting the map for.
-- Skipping offers only becomes a strategy once there is something to skip.
function City:marketSpread()
  local scale = #self:clientList() + 2 * (self.districtsBought or 0) + (self.sourcesBought or 0)
  return 0.05 + 0.50 * math.min(1, scale / 18)
end

function City:offerRate(base)
  local spread = self:marketSpread()
  -- Two uniforms make a triangular draw: middling offers are common, extreme
  -- ones are rare, and the mean stays where the trade says it should be.
  local factor = 1 + spread * (self:random() + self:random() - 1)
  return math.max(1, math.floor(base * factor + 0.5))
end

-- How far above or below the going rate this customer is paying, as a fraction.
function City:ratePremium(c)
  local base = c.rateBase or (City.CLIENTS[c.clientType] or {}).rate
  if not base or base == 0 then return 0 end
  return c.rate / base - 1
end

--------------------------------------------------------------------------------
-- Municipal tenders: a reason to build ahead of demand
--------------------------------------------------------------------------------

-- A tender is the council asking the company to hold a delivery level it does
-- not yet have, for long enough that meeting it means building first and
-- earning later.
--
-- It is a contract, not a prize. Accepting posts a bid bond out of the till,
-- which comes back with the reward if the delivery is made and is forfeited if
-- it is not. That is what makes an ambitious tender a wager rather than free
-- money lying on the floor: the question is whether the network can be grown in
-- time, and being wrong costs something.
City.tenderRate = { water = 4, power = 10, beer = 16, oil = 26 }
City.tenderBond = 0.22         -- of the reward, posted on acceptance
City.tenderDecide = 3          -- days to accept before the offer is withdrawn
City.tenderSlack = 4           -- days beyond the required closes to deliver in

function City:rollTender()
  local pool = {}
  for _, name in ipairs(Graph.TRADES) do
    if self.licences[name] then pool[#pool + 1] = name end
  end
  if #pool == 0 then return nil end
  local commodity = pool[self:random(#pool)]
  local current = (self.flowBy or {})[commodity] or 0
  local units = math.max(3, math.ceil(current * self:rand(1.15, 1.45)) + self:random(1, 3))
  local days = self:random(4, 7)
  local reward = math.ceil(units * days * City.tenderRate[commodity] * self:rand(0.55, 0.80))
  return {
    id = (self.nextTender or 1),
    commodity = commodity, units = units, days = days, met = 0,
    reward = reward, bond = math.ceil(reward * City.tenderBond),
    status = "offered", offerExpires = self.day + City.tenderDecide,
  }
end

function City:tenderById(id)
  for _, t in ipairs(self.tenders) do
    if t.id == id then return t end
  end
  return nil
end

-- How far the network is from the level a tender asks for, right now.
function City:tenderShortfall(t)
  return math.max(0, t.units - ((self.flowBy or {})[t.commodity] or 0))
end

function City:acceptTender(id)
  local t = self:tenderById(id)
  if not t then return nil, "no such tender" end
  if t.status ~= "offered" then return nil, "already accepted" end
  if t.bond > self.money then return nil, "not enough cash for the bond" end
  self:spend(t.bond)
  t.status = "accepted"
  t.accepted = self.day
  t.expires = self.day + t.days + City.tenderSlack
  self:note("Tender accepted: %d units of %s on %d closes by day %d, $%d bond posted",
    t.units, t.commodity, t.days, t.expires, t.bond)
  return t
end

function City:declineTender(id)
  local t = self:tenderById(id)
  if not t then return nil, "no such tender" end
  if t.status ~= "offered" then return nil, "that tender is already signed" end
  for i, other in ipairs(self.tenders) do
    if other.id == id then table.remove(self.tenders, i); break end
  end
  self:note("Tender for %d units of %s declined", t.units, t.commodity)
  return true
end

function City:tenderProgress()
  local paid, lost = 0, 0
  for i = #self.tenders, 1, -1 do
    local t = self.tenders[i]
    if t.status == "offered" then
      -- An offer nobody answered is withdrawn. Nothing is lost by ignoring one.
      if self.day >= (t.offerExpires or 0) then
        self:note("Tender for %d units of %s was withdrawn unanswered", t.units, t.commodity)
        table.remove(self.tenders, i)
      end
    else
      if (self.flowBy[t.commodity] or 0) >= t.units then t.met = t.met + 1 end
      if t.met >= t.days then
        local payout = t.reward + (t.bond or 0)
        self.money = self.money + payout
        paid = paid + payout
        self.tendersDone = (self.tendersDone or 0) + 1
        self.reputation = math.min(100, self.reputation + 3)
        self:note("Tender delivered: %d units of %s held for %d closes. $%d paid, $%d bond returned",
          t.units, t.commodity, t.days, t.reward, t.bond or 0)
        table.remove(self.tenders, i)
      elseif self.day >= (t.expires or 0) then
        -- The bond is forfeited. This is the half of the wager that stings.
        lost = lost + (t.bond or 0)
        self.reputation = math.max(0, self.reputation - 4)
        self:note("Tender failed: %d of %d closes met. $%d bond forfeited",
          t.met, t.days, t.bond or 0)
        table.remove(self.tenders, i)
      end
    end
  end
  return paid, lost
end

--------------------------------------------------------------------------------
-- Flow
--------------------------------------------------------------------------------

function City:refresh()
  self.served = {}
  self.detail = { edge = {}, node = {} }
  self.flowBy = {}
  self.produced = {}
  self.spare = {}
  self.wellSpare = {}
  self.capacityBy = {}
  for _, name in ipairs(Graph.TRADES) do
    local flow, _, served, detail, produced = self.g:maxflow(false, name)
    self.flowBy[name] = flow
    for id, v in pairs(served or {}) do self.served[id] = v end
    for id, v in pairs(produced or {}) do self.produced[id] = v end
    for id, v in pairs((detail or {}).edge or {}) do self.detail.edge[id] = v end
    for id, v in pairs((detail or {}).node or {}) do
      self.detail.node[id] = (self.detail.node[id] or 0) + v
    end
    -- Two different questions share the word "spare".
    --
    -- `wellSpare` is output that was pumped for and never sold: real product
    -- sitting in the works, which is the only thing a depot can take in. A
    -- haven's unused berths are not that -- nothing was landed and nothing was
    -- billed for -- so they do not count here.
    --
    -- `spare` is headroom: everything the network could still draw on today
    -- from any feed at all. That is the number that answers "can I sign this
    -- customer", so it is the one the sidebar shows and the one a starved
    -- customer's diagnosis is judged against.
    local wells, headroom = 0, 0
    for _, n in ipairs(self.g:aliveNodes()) do
      if n.commodity == name then
        if n.kind == "source" then
          wells = wells + (n.output or 0)
          headroom = headroom + (n.output or 0)
        elseif n.kind == "terminal" then headroom = headroom + (n.output or 0)
        elseif n.kind == "depot" then headroom = headroom + (n.stored or 0) end
      end
    end
    self.capacityBy[name] = headroom
    self.wellSpare[name] = math.max(0, wells - flow)
    self.spare[name] = math.max(0, headroom - flow)
  end

  self.unserved = 0
  for _, c in ipairs(self:clientList()) do
    if (self.served[c.id] or 0) < c.demand then self.unserved = self.unserved + 1 end
  end
  return self.served
end

-- A market event multiplies what one trade pays for a few days. It is the only
-- thing in the game that changes a price without the player touching anything,
-- and it is what makes a depot full of yesterday's beer worth having.
City.EVENTS = {
  { key = "heatwave",  commodity = "water", rate = 1.45, days = 4,
    head = "Heatwave: households pay a premium for water" },
  { key = "festival",  commodity = "beer",  rate = 1.60, days = 3,
    head = "Beer festival: the pubs will take everything you have" },
  { key = "refit",     commodity = "oil",   rate = 1.55, days = 3,
    head = "Refinery refit: oil fetches a premium across the works" },
  { key = "mains",     commodity = "water", rate = 0.75, days = 3,
    head = "Rationing order: the council caps what water may be charged" },
  { key = "duty",      commodity = "beer",  rate = 0.72, days = 3,
    head = "Excise duty raised: beer margins squeezed" },
  { key = "glut",      commodity = "oil",   rate = 0.70, days = 3,
    head = "Oil glut: the factories renegotiate downward" },
}

function City:eventRate(commodity)
  if self.event and self.event.commodity == commodity and self.event.left > 0 then
    return self.event.rate
  end
  return 1
end

function City:clientIncome(c)
  return math.floor((self.served[c.id] or 0) * c.rate * self:eventRate(c.commodity) + 0.5)
end

function City:sourceIncome(n)
  if n.kind ~= "source" then return 0 end
  local trade = City.trade[n.commodity] or City.trade.water
  return math.floor(trade.wholesale + (n.output or 0) * trade.wholesalePerUnit)
end

--------------------------------------------------------------------------------
-- Why is this customer short?
--------------------------------------------------------------------------------

-- A customer showing 1/4 is a question, and the answer is almost always one
-- specific main that is already carrying everything it can. The flow solver
-- knows which one; there is no reason to make the player find it by eye.
--
-- Walks outward from the customer over mains of its own trade, in order of
-- distance, and reports the first constraint it meets: a shut valve, no route
-- to a well at all, wells already at full output, or -- most often -- the
-- nearest main running full.
function City:constraintFor(id)
  local c = self.g.nodes[id]
  if not (c and c.alive and c.kind == "client" and not c.prospect) then return nil end
  if (self.served[id] or 0) >= (c.demand or 0) then return nil end
  if c.supplyClosed then return "valve" end

  local com = c.commodity
  local seen, queue, head = { [id] = true }, { id }, 1
  local saturated, sawFeed = nil, false
  while head <= #queue do
    local u = queue[head]; head = head + 1
    local node = self.g.nodes[u]
    if node.kind == "source" or node.kind == "terminal"
       or (node.kind == "depot" and (node.stored or 0) > 0) then sawFeed = true end
    for _, ei in ipairs(self.g.adj[u] or {}) do
      local e = self.g.edges[ei]
      if e.alive and e.commodity == com then
        if not saturated and math.abs(self.detail.edge[ei] or 0) >= e.cap then saturated = ei end
        local v = (e.a == u) and e.b or e.a
        if not seen[v] and self.g.nodes[v] and self.g.nodes[v].alive then
          seen[v] = true
          queue[#queue + 1] = v
        end
      end
    end
  end

  if not sawFeed then return "unconnected" end
  -- If every well is already pumping flat out, a wider pipe changes nothing.
  if (self.spare[com] or 0) <= 0 then return "output" end
  if saturated then return "main", saturated end
  return "output"
end

-- Drawn against everything that could feed it, for one trade.
function City:supplyFor(commodity)
  return self.flowBy[commodity] or 0, self.capacityBy[commodity] or 0
end

-- The same question for the whole network, for the alert strip.
function City:shortCustomers()
  local t = {}
  for _, c in ipairs(self:clientList()) do
    if (self.served[c.id] or 0) < c.demand then t[#t + 1] = c end
  end
  return t
end

function City:dailyRevenue()
  local rev = 0
  for _, c in ipairs(self:clientList()) do
    rev = rev + self:clientIncome(c)
  end
  for _, n in ipairs(self.g:aliveNodes()) do
    if n.kind == "source" then rev = rev + self:sourceIncome(n) end
  end
  return rev
end

function City:leakChance(e)
  -- Steel track laid on ballast does not foul. Rail is the only link in the
  -- game with no maintenance story at all, which is most of what you are
  -- paying for when you lay it.
  if e.rail then return 0 end
  local q = 1 - City.rules.qualityStep * self.quality
  local g = self:gradeOf(e).risk
  local a, b = self.g.nodes[e.a], self.g.nodes[e.b]
  for _, n in ipairs(self.g:nodesOfKind("tower")) do
    if (n.x - (a.x + b.x) / 2)^2 + (n.y - (a.y + b.y) / 2)^2 <= 220^2 then
      g = g * 0.45
      break
    end
  end
  return City.rules.leakBase * q * g
end

-- What lining saves per day, in money: the repair it avoids, weighted by how
-- often it would have happened. The inspector prints this so the investment can
-- be judged rather than guessed at.
function City:liningPayback(e)
  local grade = e.grade or 1
  if grade >= #City.GRADES then return nil end
  local here = City.GRADES[grade]
  local next_ = City.GRADES[grade + 1]
  local trade = City.trade[e.commodity] or City.trade.water
  local base = trade.repairBase + trade.repairPerLost * 2 + self:pipeLength(e) * trade.repairPerM
  local risk = self:leakChance(e) / here.risk
  -- A leak also costs capacity every day until it is noticed and fixed.
  local perDay = risk * (here.risk * base * here.repair - next_.risk * base * next_.repair)
  local cost = self:liningCost(e)
  if perDay <= 0 then return nil end
  return perDay, math.ceil(cost / perDay)
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
    report.revenue = report.revenue + self:clientIncome(c)
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
    if n.kind == "source" then report.revenue = report.revenue + self:sourceIncome(n) end
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
        -- Armour buys time: the main still fails, but it bleeds out slowly
        -- enough that a crew or a player gets there first.
        e.decayTick = (e.decayTick or 0) + 1
        if e.decayTick >= self:gradeOf(e).decay then
          e.decayTick = 0
          e.cap = math.max(0, e.cap - 1)
        end
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

  -- 3b. The crews work the backlog. This is what the wage buys: the worst main
  --     on the books gets fixed without anybody clicking on it.
  report.crewFixed, report.crewCost = 0, 0
  for _ = 1, (self.crews or 0) do
    local worst, worstCost
    for _, e in ipairs(self.g.edges) do
      if e.alive and e.leaking then
        local cost = self:repairCost(e)
        if cost <= self.money and (not worst or cost > worstCost) then worst, worstCost = e, cost end
      end
    end
    if not worst then break end
    self.money = self.money - worstCost
    worst.cap = worst.capMax or worst.cap
    worst.leaking, worst.burstReported, worst.decayTick = false, nil, nil
    report.crewFixed = report.crewFixed + 1
    report.crewCost = report.crewCost + worstCost
  end
  if report.crewFixed > 0 then
    self:note("Crews repaired %d main%s for $%d", report.crewFixed,
      report.crewFixed == 1 and "" or "s", report.crewCost)
    self:refresh()
  end

  -- 3c. Depots take in the day's unsold output and give back what they lent.
  report.stored, report.drawn = 0, 0
  for _, n in ipairs(self.g:nodesOfKind("depot")) do
    local drawn = self.produced[n.id] or 0
    if drawn > 0 then
      n.stored = math.max(0, (n.stored or 0) - drawn)
      report.drawn = report.drawn + drawn
    end
  end
  for _, name in ipairs(Graph.TRADES) do
    local spare = self.wellSpare[name] or 0
    for _, n in ipairs(self.g:nodesOfKind("depot")) do
      if n.commodity == name and spare > 0 and self.g:degree(n.id) > 0 then
        local room = (n.capacityStore or City.depotCapacity) - (n.stored or 0)
        local take = math.min(spare, room, City.depotFillRate)
        if take > 0 then
          n.stored = (n.stored or 0) + take
          spare = spare - take
          report.stored = report.stored + take
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

  -- 5b. Tenders, and whatever the market decided to do this week.
  self:refresh()
  report.tender, report.tenderLost = self:tenderProgress()
  if self.event then
    self.event.left = self.event.left - 1
    if self.event.left <= 0 then self.event = nil end
  end
  if not self.event and self.day > 6 and self:random() < 0.16 then
    local spec = City.EVENTS[self:random(#City.EVENTS)]
    if self.licences[spec.commodity] then
      self.event = { key = spec.key, commodity = spec.commodity, rate = spec.rate,
                     left = spec.days, head = spec.head }
      report.event = spec.head
      self:note("%s", spec.head)
    end
  end
  if #self.tenders < 2 and self.day > 4 and (self:random() < 0.22 or (self.day % 9 == 0 and #self.tenders == 0)) then
    local t = self:rollTender()
    if t then
      self.nextTender = (self.nextTender or 1) + 1
      self.tenders[#self.tenders + 1] = t
      report.tenderNew = t
      self:note("Municipal tender posted: %d units of %s on %d closes for $%d",
        t.units, t.commodity, t.days, t.reward)
    end
  end

  report.bonus = self:awardMilestones()

  if report.unhappy == 0 and #self:clientList() > 0 then
    self.reputation = math.min(100, self.reputation + 1)
  end

  self.history[#self.history + 1] = {
    day = self.day, money = self.money, clients = #self:clientList(),
    revenue = report.revenue, expenses = report.expenses,
  }

  report.interestPaid = self:loanInterest()
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

--------------------------------------------------------------------------------
-- Bringing an older company forward
--------------------------------------------------------------------------------

-- Saves are the player's actual company, sometimes eighty days deep, so a new
-- mechanic has to arrive around them rather than in place of them. Everything
-- here is additive: missing fields get sensible defaults, and the ground the
-- company was already standing on becomes the districts it already owns.
function City:migrate()
  self.permits = self.permits or { park = false, river = false, bedrock = false }
  self.deposits = self.deposits or {}
  self.tenders = self.tenders or {}
  self.tendersDone = self.tendersDone or 0
  self.nextTender = self.nextTender or 1
  for _, t in ipairs(self.tenders) do
    -- Tenders that were already running when they were still automatic keep
    -- their progress and owe no bond.
    t.status = t.status or "accepted"
    t.bond = t.bond or 0
    t.id = t.id or self.nextTender
    self.nextTender = math.max(self.nextTender, t.id + 1)
  end
  self.crews = self.crews or 0
  self.premiumBought = self.premiumBought or {}
  self.districtsBought = self.districtsBought or 0
  self.loan = self.loan or 0
  self.licences = self.licences or { water = true }
  if self.licences.power == nil then self.licences.power = false end

  if not self.districts then
    local old = self.bounds or { x = 0, y = 0, w = 2000, h = 1400 }
    self.bounds = { x = 0, y = 0, w = City.MAP.cols * City.MAP.w, h = City.MAP.rows * City.MAP.h }
    self.districts = {}
    for row = 1, City.MAP.rows do
      for col = 1, City.MAP.cols do
        local i = (row - 1) * City.MAP.cols + col
        local d = {
          id = i, col = col, row = row, name = City.DISTRICTS[i].name,
          x = (col - 1) * City.MAP.w, y = (row - 1) * City.MAP.h,
          w = City.MAP.w, h = City.MAP.h, owned = false,
        }
        -- Whatever the old, smaller map covered is ground already paid for.
        d.owned = d.x < old.x + old.w and d.y < old.y + old.h
        self.districts[i] = d
      end
    end
    -- Any structure already standing keeps its ground, wherever it ended up.
    for _, n in ipairs(self.g:aliveNodes()) do
      local d = self:districtAt(n.x, n.y)
      if d then d.owned = true end
    end
    local owned = #self:ownedDistricts()
    self.districtsBought = math.max(0, owned - 1)
    -- The new districts have never been surveyed, so give them their ground.
    for i, d in ipairs(self.districts) do
      if not d.owned then
        local spec = City.DISTRICTS[i]
        self:scatterObstacles(spec.rough, d)
        self:scatterSeams(spec.seams or 0, d)
      end
    end
    self:note("Survey filed: %d districts held, %d more available to purchase",
      owned, #self.districts - owned)
  end

  for _, n in ipairs(self.g.nodes) do
    if n.kind == "source" then
      n.level = n.level or 1
      n.output = n.output or (City.trade[n.commodity] or City.trade.water).sourceOutput
      if n.commodity ~= "water" then
        self.premiumBought[n.commodity] = (self.premiumBought[n.commodity] or 0) + 1
      end
    elseif n.kind == "client" and n.rate then
      n.rateBase = n.rateBase or (City.CLIENTS[n.clientType] or {}).rate or n.rate
    elseif n.kind == "gate" then
      n.throughput = n.throughput or 6
    elseif n.kind == "depot" then
      n.stored = n.stored or 0
      n.capacityStore = n.capacityStore or City.depotCapacity
    end
  end
  for _, e in ipairs(self.g.edges) do e.grade = e.grade or 1 end
  return self
end

--------------------------------------------------------------------------------
-- Credit
--------------------------------------------------------------------------------

-- The bank lends against what the company owns, never against what is in the
-- till, so borrowing cannot bootstrap its own ceiling. Ten percent a week, flat
-- and knowable: unlike the investment fund, a loan has no variance at all. It
-- is the instrument for buying a district today and paying for it out of the
-- customers that district brings.
City.loanRate = 0.10          -- per week, on the outstanding balance
City.loanRatio = 0.50         -- of collateral

-- Everything the company owns except its cash: plant, ground and locked deposits.
function City:collateral()
  local v = self:investedTotal()
  for _, n in ipairs(self.g:aliveNodes()) do
    if n.kind ~= "client" then v = v + (n.paid or (n.kind == "source" and 260) or self:nodeCost(n.kind)) end
  end
  for _, e in ipairs(self.g.edges) do if e.alive then v = v + (e.paid or 0) end end
  -- Ground is an asset, and the priciest one the company owns.
  for i = 1, math.max(0, (self.districtsBought or 0)) do
    v = v + City.districtPrice.base * (City.districtPrice.growth ^ (i - 1))
  end
  return math.floor(v)
end

function City:loanLimit() return math.floor(self:collateral() * City.loanRatio) end
function City:loanAvailable() return math.max(0, self:loanLimit() - (self.loan or 0)) end
function City:loanInterest() return math.ceil((self.loan or 0) * City.loanRate / 7) end

function City:borrow(amount)
  if type(amount) ~= "number" or amount ~= amount or amount == math.huge then return nil, "invalid amount" end
  amount = math.floor(amount)
  if amount <= 0 then return nil, "nothing to borrow" end
  local room = self:loanAvailable()
  if room <= 0 then return nil, "no credit against current assets" end
  if amount > room then return nil, "only $" .. room .. " of credit available" end
  self.loan = (self.loan or 0) + amount
  self.money = self.money + amount
  self:note("Borrowed $%d at %d%% a week: $%d outstanding",
    amount, math.floor(City.loanRate * 100), self.loan)
  return true
end

function City:repay(amount)
  if (self.loan or 0) <= 0 then return nil, "nothing outstanding" end
  if type(amount) ~= "number" or amount ~= amount then return nil, "invalid amount" end
  amount = math.min(math.floor(amount), self.loan, self.money)
  if amount <= 0 then return nil, "not enough cash" end
  self.loan = self.loan - amount
  self.money = self.money - amount
  self:note("Repaid $%d: $%d outstanding", amount, self.loan)
  return true
end

-- Net worth: what is owned, less what is owed. Borrowing moves nothing here,
-- which is exactly what makes it borrowing rather than income.
function City:valuation()
  return math.floor(self.money + self:collateral() - (self.loan or 0))
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

City.crewWage = 14
City.crewHire = 340
City.crewMax = 4

-- The itemised running cost. Pipes are no longer a flat half-dollar each: a
-- pressurised oil trunk across two districts is a standing liability, and the
-- ledger has to show that before the player builds three more of them.
-- What the havens charge today. A well's output is free once it is sunk; a
-- terminal bills for every unit it lands, so a haven is supply bought rather
-- than supply owned -- fast to stand up, and a permanent bite out of the margin.
function City:importBill()
  local total, by = 0, {}
  for _, n in ipairs(self.g:nodesOfKind("terminal")) do
    local units = (self.produced or {})[n.id] or 0
    local trade = City.trade[n.commodity] or City.trade.water
    local cost = units * (trade.importCost or 1)
    total = total + cost
    by[n.id] = cost
  end
  return total, by
end

function City:expenseBreakdown()
  local b = { office = 8, sources = 0, structures = 0, pipes = 0, crews = 0 }
  for _, n in ipairs(self.g:aliveNodes()) do
    if n.kind == "source" then
      local trade = City.trade[n.commodity] or City.trade.water
      b.sources = b.sources + trade.sourceUpkeep + ((n.level or 1) - 1) * 2
    elseif n.kind == "terminal" then b.structures = b.structures + City.terminalUpkeep
    elseif n.kind == "depot" then b.structures = b.structures + 3
    elseif n.kind == "tower" then b.structures = b.structures + 2
    elseif n.kind ~= "client" then b.structures = b.structures + 1 end
  end
  b.imports = self:importBill()
  for _, e in ipairs(self.g.edges) do
    if e.alive then b.pipes = b.pipes + self:pipeUpkeep(e) end
  end
  b.crews = (self.crews or 0) * City.crewWage
  b.interest = self:loanInterest()
  b.total = math.ceil(b.office + b.sources + b.structures + b.pipes + b.crews
    + b.interest + b.imports)
  return b
end

function City:dailyExpenses()
  return self:expenseBreakdown().total
end

function City:hireCrew()
  if (self.crews or 0) >= City.crewMax then return nil, "no more crews available" end
  if City.crewHire > self.money then return nil, "not enough cash" end
  self:spend(City.crewHire)
  self.crews = (self.crews or 0) + 1
  self:note("Maintenance crew hired: %d on the books at $%d a day each",
    self.crews, City.crewWage)
  return true
end

function City:dismissCrew()
  if (self.crews or 0) <= 0 then return nil, "no crews on the books" end
  self.crews = self.crews - 1
  self:note("Maintenance crew stood down: %d remaining", self.crews)
  return true
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
