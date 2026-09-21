-- rounds.lua -- Rounds mode: build between rounds, then let the houses come.
--
-- A run is forty rounds on one map. Between rounds the player builds wells,
-- junctions, towers and mains with the money they have. A round then drops a
-- batch of houses into the open zones, one at a time, and every house either
-- gets its full demand or goes dry and costs lives. Each round has more houses
-- than the last, so a network that coped last time is the minimum, not enough.
--
-- The round is read the way the company game reads a day: one Dinic solve over
-- a node-split graph. Arrival order matters and is kept on purpose. A house that
-- is served keeps its water for the rest of the round, so a later arrival can
-- only use what is left, and a round is lost house by house rather than all at
-- once. That is also what lets the screen show it happening.
--
-- Pure Lua with no love dependency, so the whole mode runs headless in tests.
local Graph = require("graph")
local D = require("data.rounds")

local Rounds = {}
Rounds.__index = Rounds
Rounds.D = D

local INF = Graph.INF
local DROP_CAP = 1e6

--------------------------------------------------------------------------------
-- Randomness
--
-- Two kinds of stream, and neither is ever shared. The map comes from the seed.
-- Each round's houses and shocks come from a stream mixed out of the seed and
-- the round number, so a round is the same round however the player built
-- towards it, and saving and reloading before it cannot reroll it.
--------------------------------------------------------------------------------

local function stream(seed)
  local s = { state = math.floor(seed) % 2147483646 + 1 }
  function s.next(lo, hi)
    s.state = (s.state * 16807) % 2147483647
    local v = (s.state - 1) / 2147483646
    if hi then return math.floor(lo + v * (hi - lo + 1)) end
    if lo then return math.floor(1 + v * lo) end
    return v
  end
  function s.range(lo, hi) return lo + s.next() * (hi - lo) end
  -- Warm the generator up: nearby seeds otherwise open on nearby numbers.
  for _ = 1, 4 do s.next() end
  return s
end
Rounds.stream = stream

local function roundSeed(seed, r)
  return (seed * 7919 + r * 104729 + 12345) % 2147483646
end

local function dist(ax, ay, bx, by) return math.sqrt((ax - bx) ^ 2 + (ay - by) ^ 2) end

local function segCircle(ax, ay, bx, by, cx, cy, r)
  local dx, dy = bx - ax, by - ay
  local len2 = dx * dx + dy * dy
  local t = len2 > 0 and math.max(0, math.min(1, ((cx - ax) * dx + (cy - ay) * dy) / len2)) or 0
  return dist(ax + t * dx, ay + t * dy, cx, cy) < r
end

--------------------------------------------------------------------------------
-- The map
--------------------------------------------------------------------------------

-- The river runs north to south, a little east of centre. Its course is a sum
-- of two sines, kept as parameters so a save never has to store it.
function Rounds:riverX(y)
  local r = self.river
  return r.x + r.a1 * math.sin(y * r.f1 + r.p1) + r.a2 * math.sin(y * r.f2 + r.p2)
end

function Rounds:onRiver(x, y, margin)
  return math.abs(x - self:riverX(y)) < self.river.w / 2 + (margin or 0)
end

-- How many times a straight main crosses the river. Sampled, because the course
-- bends and a main may cross, run alongside and cross back.
function Rounds:crossings(ax, ay, bx, by)
  local steps = math.max(2, math.ceil(dist(ax, ay, bx, by) / 16))
  local count, last = 0, nil
  for i = 0, steps do
    local t = i / steps
    local x, y = ax + (bx - ax) * t, ay + (by - ay) * t
    local side = x < self:riverX(y) and -1 or 1
    if last and side ~= last then count = count + 1 end
    last = side
  end
  return count
end

function Rounds:rockAt(x, y, margin)
  for _, r in ipairs(self.rocks) do
    if dist(x, y, r.x, r.y) < r.r + (margin or 0) then return r end
  end
end

function Rounds:inBounds(x, y, margin)
  margin = margin or 0
  return x >= margin and y >= margin and x <= self.w - margin and y <= self.h - margin
end

local function generate(self)
  local rng = stream(self.seed)
  local W, H = self.w, self.h
  self.river = {
    x = W * 0.6, w = 56,
    a1 = rng.range(40, 80), f1 = rng.range(0.0022, 0.0034), p1 = rng.range(0, 6.28),
    a2 = rng.range(15, 35), f2 = rng.range(0.006, 0.009), p2 = rng.range(0, 6.28),
  }

  -- Zones first: they are the track the houses run on. The first opens west of
  -- the river near the middle, so the opening is readable; the rest alternate
  -- banks so crossing the river becomes a question around round twelve.
  local sides = { "west", "west", "east", "west", "east", "east", "west" }
  self.zones = {}
  for i, spec in ipairs(D.ZONES) do
    local placed
    for attempt = 1, 4000 do
      local r = rng.range(145, 185)
      local x, y
      if i == 1 then
        x, y = rng.range(W * 0.24, W * 0.34), rng.range(H * 0.40, H * 0.60)
      else
        x, y = rng.range(r + 60, W - r - 60), rng.range(r + 60, H - r - 60)
      end
      local rx = self:riverX(y)
      local side = x < rx and "west" or "east"
      local ok = side == sides[i] and math.abs(x - rx) > r + 90
        and math.abs(x - self:riverX(y - r)) > r * 0.7 + 90
        and math.abs(x - self:riverX(y + r)) > r * 0.7 + 90
      -- Late in the search the spacing relaxes rather than failing the map.
      local spacing = attempt < 3000 and 560 or 460
      for _, z in ipairs(self.zones) do
        if dist(x, y, z.x, z.y) < spacing then ok = false end
      end
      if ok then placed = { x = x, y = y, r = r }; break end
    end
    placed = placed or { x = W * 0.2, y = H * (i / 8), r = 150 }
    placed.name, placed.opens, placed.index = spec.name, spec.opens, i
    placed.letter = string.char(64 + i)
    self.zones[i] = placed
  end

  local function clearOfZones(x, y, pad)
    for _, z in ipairs(self.zones) do
      if dist(x, y, z.x, z.y) < z.r + pad then return false end
    end
    return true
  end

  -- Springs sit outside the zones, so every house is fed by a main and never
  -- by a well dropped into the middle of the estate. The first two sit close
  -- to the first zone and the next to the first zone over the river, so the
  -- opening and the first crossing both have water within reach.
  self.springs = {}
  local near = { 1, 1, 3, 2, 4 }
  for i = 1, D.SPRINGS do
    for attempt = 1, 3000 do
      local x, y
      local z = self.zones[near[i] or 0]
      if z and attempt < 2000 then
        local a, d = rng.range(0, math.pi * 2), z.r + rng.range(70, 230)
        x, y = z.x + math.cos(a) * d, z.y + math.sin(a) * d
      else
        x, y = rng.range(80, W - 80), rng.range(80, H - 80)
      end
      local ok = self:inBounds(x, y, 70) and clearOfZones(x, y, 45)
        and not self:onRiver(x, y, 60)
      for _, s in ipairs(self.springs) do
        if dist(x, y, s.x, s.y) < 260 then ok = false end
      end
      if ok then
        -- How deep the spring is: the highest level a well on it can reach.
        local depth = (i <= 2) and (i == 1 and 4 or 3) or rng.next(2, 4)
        self.springs[#self.springs + 1] = { x = x, y = y, depth = depth, index = #self.springs + 1 }
        break
      end
    end
  end

  -- Bedrock: nothing is built on it and no main crosses it.
  self.rocks = {}
  for _ = 1, D.ROCKS do
    for _ = 1, 400 do
      local r = rng.range(40, 95)
      local x, y = rng.range(r, W - r), rng.range(r, H - r)
      local ok = clearOfZones(x, y, r + 20) and not self:onRiver(x, y, r + 20)
      for _, s in ipairs(self.springs) do
        if dist(x, y, s.x, s.y) < r + 60 then ok = false end
      end
      for _, o in ipairs(self.rocks) do
        if dist(x, y, o.x, o.y) < r + o.r + 60 then ok = false end
      end
      if ok then self.rocks[#self.rocks + 1] = { x = x, y = y, r = r }; break end
    end
  end
end

--------------------------------------------------------------------------------
-- A run
--------------------------------------------------------------------------------

function Rounds.new(opts)
  opts = opts or {}
  local self = setmetatable({}, Rounds)
  self.seed = opts.seed or os.time()
  self.strict = opts.strict and true or false
  self.w, self.h = D.MAP.w, D.MAP.h
  self.round = 1
  self.money = D.START.money
  self.maxLives = self.strict and D.START.strictLives or D.START.lives
  self.lives = self.maxLives
  self.buildings, self.pipes = {}, {}
  self.nextId = 1
  self.streak = 0
  self.history = {}
  self.phase = "build"          -- build | round | lost
  self.won = false
  generate(self)
  return self
end

function Rounds:byId(id)
  for _, b in ipairs(self.buildings) do if b.id == id then return b end end
end

function Rounds:pipeById(id)
  for _, p in ipairs(self.pipes) do if p.id == id then return p end end
end

function Rounds:zoneOpen(z, r) return z.opens <= (r or self.round) end

function Rounds:openZones(r)
  local t = {}
  for _, z in ipairs(self.zones) do if self:zoneOpen(z, r) then t[#t + 1] = z end end
  return t
end

--------------------------------------------------------------------------------
-- Buildings
--------------------------------------------------------------------------------

function Rounds.spec(kind) return D.BUILDINGS[kind] end

function Rounds:stat(b, key, level)
  local list = D.BUILDINGS[b.kind][key]
  return list and list[level or b.level]
end

function Rounds:output(b)
  local out = self:stat(b, "output") or 0
  if b.kind == "well" and self.shocks and self.shocks.drought then
    out = math.floor(out * D.SHOCKS.drought.factor)
  end
  return out
end

function Rounds:portsUsed(b)
  local n = 0
  for _, p in ipairs(self.pipes) do if p.a == b.id or p.b == b.id then n = n + 1 end end
  return n
end

function Rounds:freePorts(b) return self:stat(b, "ports") - self:portsUsed(b) end

function Rounds:springAt(x, y)
  local best, bd
  for _, s in ipairs(self.springs) do
    local d = dist(x, y, s.x, s.y)
    if d < 40 and (not bd or d < bd) then best, bd = s, d end
  end
  return best
end

function Rounds:springTaken(s)
  for _, b in ipairs(self.buildings) do if b.spring == s.index then return b end end
end

-- Where a building would land and why it cannot, in the player's words.
function Rounds:placeError(kind, x, y)
  local spec = D.BUILDINGS[kind]
  if not spec then return "choose something to build" end
  if self.phase ~= "build" then return "wait for the round to finish" end
  if spec.onSpring then
    local s = self:springAt(x, y)
    if not s then return "a well goes on a spring" end
    if self:springTaken(s) then return "that spring already has a well" end
    x, y = s.x, s.y
  end
  if not self:inBounds(x, y, 20) then return "off the map" end
  if self:rockAt(x, y, 14) then return "bedrock: nothing is built here" end
  if self:onRiver(x, y, 14) then return "not in the river" end
  for _, b in ipairs(self.buildings) do
    if dist(x, y, b.x, b.y) < 34 then return "too close to another building" end
  end
  if spec.cost[1] > self.money then return "not enough cash" end
  return nil, x, y
end

function Rounds:build(kind, x, y)
  local err, px, py = self:placeError(kind, x, y)
  if err then return nil, err end
  local spec = D.BUILDINGS[kind]
  local b = { id = self.nextId, kind = kind, x = px, y = py, level = 1,
              paid = spec.cost[1], builtRound = self.round }
  self.nextId = self.nextId + 1
  if spec.onSpring then b.spring = self:springAt(px, py).index end
  self.money = self.money - spec.cost[1]
  self.buildings[#self.buildings + 1] = b
  return b
end

function Rounds:maxLevel(b)
  local top = #D.BUILDINGS[b.kind].cost
  if b.kind == "well" then top = math.min(top, self.springs[b.spring].depth) end
  return top
end

function Rounds:upgradeCost(b)
  if b.level >= self:maxLevel(b) then return nil end
  return D.BUILDINGS[b.kind].cost[b.level + 1]
end

function Rounds:upgradeError(b)
  if self.phase ~= "build" then return "wait for the round to finish" end
  local cost = self:upgradeCost(b)
  if not cost then
    if b.kind == "well" and b.level < #D.BUILDINGS.well.cost then
      return "this spring is too shallow for more"
    end
    return "fully upgraded"
  end
  if cost > self.money then return "not enough cash" end
end

function Rounds:upgrade(id)
  local b = self:byId(id)
  if not b then return nil, "nothing selected" end
  local err = self:upgradeError(b)
  if err then return nil, err end
  local cost = self:upgradeCost(b)
  self.money = self.money - cost
  b.paid = b.paid + cost
  b.level = b.level + 1
  -- A level bought in the same break is still refundable in full.
  if b.builtRound ~= self.round then b.upgradedRound = self.round end
  return b
end

-- Anything bought since the last round sells back at full price: moving a
-- junction twice before committing is planning, not waste. After a round it
-- is the usual share.
function Rounds:refund(thing)
  if thing.builtRound == self.round then return thing.paid end
  return math.floor(thing.paid * D.SELL_BACK)
end

function Rounds:sellValue(b)
  local total = self:refund(b)
  for _, p in ipairs(self.pipes) do
    if p.a == b.id or p.b == b.id then total = total + self:refund(p) end
  end
  return total
end

function Rounds:sell(id)
  if self.phase ~= "build" then return nil, "wait for the round to finish" end
  local b = self:byId(id)
  if not b then return nil, "nothing selected" end
  local value = self:sellValue(b)
  for i = #self.pipes, 1, -1 do
    local p = self.pipes[i]
    if p.a == b.id or p.b == b.id then table.remove(self.pipes, i) end
  end
  for i, o in ipairs(self.buildings) do
    if o == b then table.remove(self.buildings, i); break end
  end
  self.money = self.money + value
  return value
end

--------------------------------------------------------------------------------
-- Mains
--------------------------------------------------------------------------------

function Rounds.pipeSpec(size) return D.PIPES[size] end

function Rounds:pipeCost(a, b, size)
  local spec = D.PIPES[size]
  local len = dist(a.x, a.y, b.x, b.y)
  local cross = self:crossings(a.x, a.y, b.x, b.y)
  return math.ceil(spec.base + spec.perM * len + cross * D.RIVER_CROSSING * (1 + 0.5 * (size - 1))), cross
end

function Rounds:pipeBetween(a, b)
  for _, p in ipairs(self.pipes) do
    if (p.a == a and p.b == b) or (p.a == b and p.b == a) then return p end
  end
end

function Rounds:pipeError(aid, bid, size)
  if self.phase ~= "build" then return "wait for the round to finish" end
  local a, b = self:byId(aid), self:byId(bid)
  if not (a and b) then return "join two buildings" end
  if a == b then return "a main needs two ends" end
  if self:pipeBetween(aid, bid) then return "already joined" end
  local spec = D.PIPES[size]
  if not spec then return "choose a size" end
  if dist(a.x, a.y, b.x, b.y) > spec.reach then
    for i = size + 1, #D.PIPES do
      if dist(a.x, a.y, b.x, b.y) <= D.PIPES[i].reach then
        return "too far for " .. spec.name .. ": " .. D.PIPES[i].name .. " reaches"
      end
    end
    return "too far: put a junction between"
  end
  for _, r in ipairs(self.rocks) do
    if segCircle(a.x, a.y, b.x, b.y, r.x, r.y, r.r) then return "bedrock in the way" end
  end
  if self:freePorts(a) < 1 then return D.BUILDINGS[a.kind].name .. " has no free port" end
  if self:freePorts(b) < 1 then return D.BUILDINGS[b.kind].name .. " has no free port" end
  if self:pipeCost(a, b, size) > self.money then return "not enough cash" end
end

function Rounds:layPipe(aid, bid, size)
  local err = self:pipeError(aid, bid, size)
  if err then return nil, err end
  local a, b = self:byId(aid), self:byId(bid)
  local cost, cross = self:pipeCost(a, b, size)
  local p = { id = self.nextId, a = aid, b = bid, size = size, paid = cost,
              crossings = cross, builtRound = self.round }
  self.nextId = self.nextId + 1
  self.money = self.money - cost
  self.pipes[#self.pipes + 1] = p
  return p
end

-- Widening pays the difference between the two mains, nothing lost.
function Rounds:widenCost(p)
  if p.size >= #D.PIPES then return nil end
  local a, b = self:byId(p.a), self:byId(p.b)
  return self:pipeCost(a, b, p.size + 1) - self:pipeCost(a, b, p.size)
end

function Rounds:widenError(p)
  if self.phase ~= "build" then return "wait for the round to finish" end
  local cost = self:widenCost(p)
  if not cost then return "already the widest main" end
  if cost > self.money then return "not enough cash" end
end

function Rounds:widen(id)
  local p = self:pipeById(id)
  if not p then return nil, "nothing selected" end
  local err = self:widenError(p)
  if err then return nil, err end
  local cost = self:widenCost(p)
  self.money = self.money - cost
  p.paid = p.paid + cost
  p.size = p.size + 1
  return p
end

function Rounds:sellPipe(id)
  if self.phase ~= "build" then return nil, "wait for the round to finish" end
  for i, p in ipairs(self.pipes) do
    if p.id == id then
      local value = self:refund(p)
      table.remove(self.pipes, i)
      self.money = self.money + value
      return value
    end
  end
  return nil, "nothing selected"
end

-- Whether any of these buildings reaches a well or a tower over mains that are
-- standing. Used to tell "not joined up" apart from "joined up but short".
function Rounds:watered(ids)
  local seen, queue = {}, {}
  for _, id in ipairs(ids) do seen[id] = true; queue[#queue + 1] = id end
  while #queue > 0 do
    local id = table.remove(queue)
    local b = self:byId(id)
    if b and b.kind ~= "junction" then return true end
    for _, p in ipairs(self.pipes) do
      if not (self.burst and self.burst[p.id]) then
        local other = (p.a == id and p.b) or (p.b == id and p.a)
        if other and not seen[other] then seen[other] = true; queue[#queue + 1] = other end
      end
    end
  end
  return false
end

--------------------------------------------------------------------------------
-- Coverage
--------------------------------------------------------------------------------

function Rounds:radius(b) return self:stat(b, "radius") end

function Rounds:coveredBy(x, y)
  local t = {}
  for _, b in ipairs(self.buildings) do
    if dist(x, y, b.x, b.y) <= self:radius(b) then t[#t + 1] = b end
  end
  return t
end

-- Where a house may stand: inside the zone, on dry, open ground.
function Rounds:sitable(z, x, y)
  return dist(x, y, z.x, z.y) <= z.r and not self:rockAt(x, y, 10)
    and not self:onRiver(x, y, 12) and self:inBounds(x, y, 12)
end

-- The share of a zone's ground that at least one ring reaches. A house lands
-- anywhere in the zone with equal chance, so this is the chance that a house
-- there can be served at all. Sampled on a fixed grid, so it never flickers.
function Rounds:coverage(z)
  local inside, covered = 0, 0
  local step = z.r / 9
  for gx = -9, 9 do
    for gy = -9, 9 do
      local x, y = z.x + gx * step, z.y + gy * step
      if self:sitable(z, x, y) then
        inside = inside + 1
        for _, b in ipairs(self.buildings) do
          if dist(x, y, b.x, b.y) <= self:radius(b) then covered = covered + 1; break end
        end
      end
    end
  end
  return inside > 0 and covered / inside or 0
end

--------------------------------------------------------------------------------
-- What a round holds
--------------------------------------------------------------------------------

function Rounds.houseCount(r) return 3 + r + math.floor(r * r / 60) end

local function typeWeights(r)
  local w = {}
  for _, key in ipairs(D.HOUSE_ORDER) do
    local h = D.HOUSES[key]
    if h.from and r >= h.from then
      if key == "cottage" then w[key] = math.max(1.5, 10 - r * 0.28)
      elseif key == "house" then w[key] = 6
      elseif key == "terrace" then w[key] = 4 + (r - h.from) * 0.12
      elseif key == "estate" then w[key] = 2 + (r - h.from) * 0.18 end
    end
  end
  return w
end

local function pick(rng, weights)
  local total = 0
  for _, key in ipairs(D.HOUSE_ORDER) do total = total + (weights[key] or 0) end
  local x = rng.next() * total
  for _, key in ipairs(D.HOUSE_ORDER) do
    x = x - (weights[key] or 0)
    if x <= 0 and weights[key] then return key end
  end
  for i = #D.HOUSE_ORDER, 1, -1 do
    if weights[D.HOUSE_ORDER[i]] then return D.HOUSE_ORDER[i] end
  end
end

-- The whole of round r, decided before the player sees it: its houses (kind,
-- zone and spot, in arrival order) and its shocks. Only the counts and the
-- shocks are shown ahead; where exactly the houses land is the surprise.
function Rounds:plan(r)
  r = r or self.round
  if self.planCache and self.planCache.round == r then return self.planCache end
  local rng = stream(roundSeed(self.seed, r))
  local plan = { round = r, houses = {}, shocks = {}, byZone = {}, demand = 0 }
  local zones = self:openZones(r)

  for _, key in ipairs(D.SHOCK_ORDER) do
    local s = D.SHOCKS[key]
    -- Always drawn, so turning a shock on never shifts the houses after it.
    local roll = rng.next()
    if r >= s.from and roll < s.chance then plan.shocks[key] = true end
  end
  if plan.shocks.burst then plan.bursts = 1 + math.floor(r / 20) end
  local heat = plan.shocks.heatwave and D.SHOCKS.heatwave.factor or 1

  local weights = typeWeights(r)
  local kinds = {}
  for _ = 1, Rounds.houseCount(r) do kinds[#kinds + 1] = pick(rng, weights) end
  if r % D.BOSS_EVERY == 0 then
    for _ = 1, r / D.BOSS_EVERY do
      -- The block comes somewhere in the second half, once the round has
      -- already taken a share of what the network holds.
      table.insert(kinds, rng.next(math.floor(#kinds / 2) + 1, #kinds + 1), "block")
    end
    plan.boss = true
  end

  for _, kind in ipairs(kinds) do
    -- A zone opening this round gets a double share, so a new zone is a real
    -- test the round it appears and not a trickle.
    local total = 0
    for _, z in ipairs(zones) do total = total + (z.opens == r and 2 or 1) end
    local x = rng.next() * total
    local zone = zones[#zones]
    for _, z in ipairs(zones) do
      x = x - (z.opens == r and 2 or 1)
      if x <= 0 then zone = z; break end
    end
    local hx, hy = zone.x, zone.y
    for _ = 1, 200 do
      local a, d = rng.range(0, math.pi * 2), zone.r * math.sqrt(rng.next())
      local cx, cy = zone.x + math.cos(a) * d, zone.y + math.sin(a) * d
      if self:sitable(zone, cx, cy) then hx, hy = cx, cy; break end
    end
    local demand = math.ceil(D.HOUSES[kind].demand * heat)
    plan.houses[#plan.houses + 1] = { kind = kind, zone = zone.index, x = hx, y = hy, demand = demand }
    plan.demand = plan.demand + demand
    local counts = plan.byZone[zone.index] or {}
    counts[kind] = (counts[kind] or 0) + 1
    plan.byZone[zone.index] = counts
  end
  -- Drawn last, so the number of pipes the player owns never moves a house.
  plan.burstRoll = rng.next()
  self.planCache = plan
  return plan
end

--------------------------------------------------------------------------------
-- The solve
--------------------------------------------------------------------------------

function Rounds:supply()
  local total = 0
  for _, b in ipairs(self.buildings) do total = total + self:output(b) end
  return total
end

-- One flow network: buildings, mains, and every house that has arrived with a
-- service drop to each ring it stands in. A house is a node whose throughput
-- is its own demand, so a house in two rings can never become a free main
-- between them: all it can pass is what it drinks. A dry house passes nothing.
function Rounds:solve(candidate)
  local g = Graph.new()
  local nodeOf, pipeOf = {}, {}
  for _, b in ipairs(self.buildings) do
    local n = g:addNode(b.x, b.y, b.kind == "junction" and "junction" or "source")
    n.ports = INF
    n.commodity = "water"
    if b.kind == "junction" then
      n.throughput = self:stat(b, "throughput")
    else
      n.throughput = INF
      n.output = self:output(b)
    end
    nodeOf[b.id] = n
  end
  local function edge(a, b, cap)
    local e = { id = #g.edges + 1, a = a.id, b = b.id, cap = cap, alive = true, commodity = "water" }
    g.edges[e.id] = e
    table.insert(g.adj[a.id], e.id)
    table.insert(g.adj[b.id], e.id)
    return e
  end
  for _, p in ipairs(self.pipes) do
    if not (self.burst and self.burst[p.id]) then
      local e = edge(nodeOf[p.a], nodeOf[p.b], D.PIPES[p.size].cap)
      pipeOf[e.id] = p.id
    end
  end
  local houseOf = {}
  for _, h in ipairs(self.houses or {}) do
    local want = h.served or h == candidate
    if want and #h.cover > 0 then
      local n = g:addNode(h.x, h.y, "client")
      n.commodity, n.demand, n.throughput = "water", h.demand, h.demand
      houseOf[n.id] = h
      for _, id in ipairs(h.cover) do
        if nodeOf[id] then edge(nodeOf[id], n, DROP_CAP) end
      end
    end
  end
  local flow, cut, served, detail = g:maxflow(false, "water")
  -- Translate the solver's ids back to the run's own.
  local out = { flow = flow, pipeFlow = {}, cutPipes = {}, cutBuildings = {}, houseServed = {} }
  for eid, f in pairs(detail.edge) do
    if pipeOf[eid] then out.pipeFlow[pipeOf[eid]] = f end
  end
  for nid, h in pairs(houseOf) do out.houseServed[h] = served[nid] or 0 end
  for _, c in ipairs(cut) do
    if c.kind == "edge" and pipeOf[c.id] then out.cutPipes[pipeOf[c.id]] = true end
    if c.kind == "node" then
      for id, n in pairs(nodeOf) do
        if n.id == c.id then out.cutBuildings[id] = true end
      end
    end
  end
  -- pipeFlow is signed: positive runs from the pipe's `a` end to its `b` end,
  -- because every main was added to the graph in that order.
  return out
end

--------------------------------------------------------------------------------
-- Playing a round
--------------------------------------------------------------------------------

function Rounds:startRound()
  if self.phase ~= "build" then return nil, "a round is already running" end
  local plan = self:plan(self.round)
  self.phase = "round"
  self.shocks = plan.shocks
  self.houses = {}
  for i, spec in ipairs(plan.houses) do
    self.houses[i] = { kind = spec.kind, zone = spec.zone, x = spec.x, y = spec.y,
                       demand = spec.demand, index = i }
  end
  self.arrived = 0
  -- Bursts land on real mains, chosen from what the player owns now. The widest
  -- mains are the likeliest to go: they carry the most, so losing one is the
  -- test a loop or a second feed exists to pass.
  self.burst = {}
  if plan.bursts and #self.pipes > 0 then
    local rng = stream(math.floor(plan.burstRoll * 2147483646) + self.round)
    local pool = {}
    for _, p in ipairs(self.pipes) do
      for _ = 1, p.size do pool[#pool + 1] = p.id end
    end
    for _ = 1, math.min(plan.bursts, #self.pipes) do
      for _ = 1, 50 do
        local id = pool[rng.next(1, #pool)]
        if not self.burst[id] then self.burst[id] = true; break end
      end
    end
  end
  self.roundLog = { dry = 0, lost = 0, delivered = 0, served = 0 }
  self.lastSolve = self:solve()
  return plan
end

function Rounds:pendingHouses() return #(self.houses or {}) - (self.arrived or 0) end

-- The next house arrives. It is served if the network can give it its full
-- demand on top of everything already promised this round, and dry otherwise.
-- A dry house takes lives equal to what it wanted.
function Rounds:arrive()
  if self.phase ~= "round" then return nil end
  local h = self.houses[self.arrived + 1]
  if not h then return nil end
  self.arrived = self.arrived + 1
  h.cover = {}
  for _, b in ipairs(self:coveredBy(h.x, h.y)) do h.cover[#h.cover + 1] = b.id end
  local promised = 0
  for _, o in ipairs(self.houses) do if o.served then promised = promised + o.demand end end
  local result = self:solve(h)
  if #h.cover > 0 and result.flow >= promised + h.demand - 1e-6 then
    h.served = true
    self.roundLog.served = self.roundLog.served + 1
    self.roundLog.delivered = self.roundLog.delivered + h.demand
  else
    h.dry = true
    if #h.cover == 0 then
      h.reason = "no ring reaches it"
    elseif not self:watered(h.cover) then
      h.reason = "its ring is not joined to any water"
    elseif next(result.cutPipes) then
      h.reason = "a main on its way is full"
    elseif next(result.cutBuildings) then
      h.reason = "a junction on its way is at its limit"
    else
      h.reason = "every source it can reach is spent"
    end
    h.cutPipes, h.cutBuildings = result.cutPipes, result.cutBuildings
    self.roundLog.dry = self.roundLog.dry + 1
    self.roundLog.lost = self.roundLog.lost + h.demand
    self.lives = math.max(0, self.lives - h.demand)
  end
  self.lastSolve = h.served and result or self:solve()
  if self.lives <= 0 then self:lose() end
  return h
end

function Rounds:lose()
  self.phase = "lost"
  self.roundLog.lostRound = self.round
  self.history[#self.history + 1] = { round = self.round, dry = self.roundLog.dry,
    lost = self.roundLog.lost, delivered = self.roundLog.delivered, income = 0 }
end

-- What a round pays, itemised the way the results banner shows it.
function Rounds:payout()
  local P = D.PAY
  local log = self.roundLog
  local items = {}
  items[#items + 1] = { label = "Round " .. self.round, amount = P.base + P.perRound * self.round }
  items[#items + 1] = { label = log.delivered .. " units delivered", amount = P.perUnit * log.delivered }
  local spare = math.max(0, self:supply() - log.delivered)
  local cap = P.spareCap.base + P.spareCap.perRound * self.round
  local reserve = math.min(cap, spare * P.sparePerUnit)
  if reserve > 0 then
    items[#items + 1] = { label = spare .. " units in reserve", amount = reserve }
  end
  if log.dry == 0 then
    local streak = math.min(P.streakMax, self.streak + 1)
    local run = self.streak + 1
    items[#items + 1] = { label = run == 1 and "No dry houses" or ("No dry houses, " .. run .. " rounds running"),
      amount = P.streak * streak }
  end
  local total = 0
  for _, it in ipairs(items) do total = total + it.amount end
  return total, items
end

function Rounds:finishRound()
  if self.phase ~= "round" then return nil end
  while self:pendingHouses() > 0 and self.phase == "round" do self:arrive() end
  if self.phase == "lost" then return nil end
  local total, items = self:payout()
  self.money = self.money + total
  self.streak = self.roundLog.dry == 0 and self.streak + 1 or 0
  self.history[#self.history + 1] = { round = self.round, dry = self.roundLog.dry,
    lost = self.roundLog.lost, delivered = self.roundLog.delivered, income = total,
    houses = #self.houses }
  local result = { round = self.round, total = total, items = items, log = self.roundLog }
  if self.round == D.FINAL_ROUND and not self.won then self.won = true; result.won = true end
  self.round = self.round + 1
  self.phase = "build"
  self.houses, self.shocks, self.burst, self.lastSolve = nil, nil, nil, nil
  self.arrived = nil
  self.planCache = nil
  return result
end

-- The whole round at once, for tests and anything else without a screen.
function Rounds:playRound()
  local ok, err = self:startRound()
  if not ok then return nil, err end
  while self.phase == "round" and self:pendingHouses() > 0 do self:arrive() end
  if self.phase == "lost" then return nil, "lost" end
  return self:finishRound()
end

--------------------------------------------------------------------------------
-- Saving
--
-- Only what the player did is written down. The map comes back from the seed,
-- and a round in progress is never saved: the break before it is.
--------------------------------------------------------------------------------

Rounds.VERSION = 1

function Rounds:pack()
  return {
    version = Rounds.VERSION, seed = self.seed, strict = self.strict,
    round = self.round, money = self.money, lives = self.lives, maxLives = self.maxLives,
    buildings = self.buildings, pipes = self.pipes, nextId = self.nextId,
    streak = self.streak, history = self.history, won = self.won,
    lost = self.phase == "lost" or nil,
  }
end

-- Plain data to Lua source and back. The file is loaded in an empty
-- environment, the same way the company save is, so it can only ever be data.
local function encode(value)
  local kind = type(value)
  if kind == "number" or kind == "boolean" then return tostring(value) end
  if kind == "string" then return string.format("%q", value) end
  assert(kind == "table", "unsupported save value")
  local out = { "{" }
  for key, item in pairs(value) do
    if type(item) ~= "function" then out[#out + 1] = "[" .. encode(key) .. "]=" .. encode(item) .. "," end
  end
  out[#out + 1] = "}"
  return table.concat(out)
end

function Rounds.serialize(data) return "return " .. encode(data) .. "\n" end

function Rounds.deserialize(text)
  if type(text) ~= "string" then return nil end
  local chunk
  if loadstring then
    chunk = loadstring(text, "rounds save")
    if chunk then setfenv(chunk, {}) end
  else
    chunk = load(text, "rounds save", "t", {})
  end
  if not chunk then return nil end
  local ok, data = pcall(chunk)
  return ok and type(data) == "table" and data or nil
end

function Rounds.unpack(data)
  if type(data) ~= "table" or data.version ~= Rounds.VERSION or type(data.seed) ~= "number" then
    return nil, "not a rounds save"
  end
  local self = Rounds.new({ seed = data.seed, strict = data.strict })
  for _, key in ipairs({ "round", "money", "lives", "maxLives", "nextId", "streak" }) do
    if type(data[key]) ~= "number" then return nil, "damaged rounds save" end
    self[key] = data[key]
  end
  self.buildings = data.buildings or {}
  self.pipes = data.pipes or {}
  self.history = data.history or {}
  self.won = data.won and true or false
  if data.lost then self.phase = "lost" end
  for _, b in ipairs(self.buildings) do
    if not D.BUILDINGS[b.kind] then return nil, "damaged rounds save" end
  end
  return self
end

return Rounds
