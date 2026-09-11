-- game.lua -- run state, economy, wave pacing and the adversary.
-- Pure logic, no love dependencies, so the rules are testable headless.

local Graph = require("graph")

local Game = {}
Game.__index = Game

-- All tuning lives here. Nothing below this table hardcodes a number that
-- matters for balance.
Game.balance = {
  startEnergy      = 130,
  baseIncome       = 60,
  incomePerFlow    = 12,
  nodeCostGrowth   = 1.025,   -- compounding per node already built
  linkCostBase     = 5,
  linkCostPerUnit  = 0.035,  -- per world unit of length
  maxLinkRange     = 280,    -- forces chained expansion instead of one long wire
  minNodeSpacing   = 52,
  capUpgradeBase   = 2,
  capUpgradePerCap = 1,
  tpUpgradeBase    = 5,
  tpUpgradePerTp   = 2,
  repairCost       = 18,
  demandSlope      = 0.35,
  terminalEvery    = 6,
  terminalRadius0  = 290,
  terminalRadiusK  = 130,      -- waves between new terminals
  firstStrikeWave  = 2,
  maxStrikes       = 3,
  nodeStrikeWave   = 8,      -- before this the adversary only severs links
  fieldW           = 2400,
  fieldH           = 1600,
}

-- Demand is per terminal, not pooled. Every terminal must be served on its own,
-- so surviving means physically reaching new ground rather than thickening one
-- trunk. This is what makes the network grow.
-- Demand is per terminal and scales with that terminal's own age, not the
-- global wave. A terminal that has just appeared asks for little and ramps up,
-- so expansion is a slope rather than a cliff: arriving at full current demand
-- would cost more in one wave than the whole network earns.
function Game.terminalDemand(age)
  return math.ceil(1 + math.max(0, age) * Game.balance.demandSlope)
end

-- Strikes are capped deliberately. Redundancy is bounded above by ports, so a
-- strike count that grows without limit would eventually exceed any achievable
-- cut width and kill even perfect play. The pressure has to come from the
-- economy of rebuilding, not from an unwinnable arithmetic.
function Game.strikesFor(wave)
  if wave < Game.balance.firstStrikeWave then return 0 end
  return math.min(Game.balance.maxStrikes, 1 + math.floor((wave - 2) / 6))
end

--------------------------------------------------------------------------------

function Game.new(meta, opts)
  local self = setmetatable({}, Game)
  self.meta = meta or { unlocked = {} }
  self.opts = opts or {}
  self.g = Graph.new()
  self.wave = 1
  self.phase = "build"           -- build | report | dead
  self.log = {}
  self.builtNodes = 0
  self.peakFlow = 0
  self.terminalsPlaced = 0
  self.strikeShield = self:has("euler")
  self.lastReport = nil

  local b = Game.balance
  self.energy = b.startEnergy + (self:has("konig") and 40 or 0)

  local cx, cy = b.fieldW / 2, b.fieldH / 2
  self.source = self.g:addNode(cx, cy, "source")
  if self.opts.tutorial then
    -- Deterministic and inside link range, so "drag source to terminal" is
    -- always a single link. A random spawn can land out of reach and make the
    -- first instruction impossible to follow.
    local t = self.g:addNode(cx + 215, cy, "sink")
    t.bornWave = 1
    t.demand = Game.terminalDemand(1)
    self.terminalsPlaced = 1
  else
    self:spawnTerminal()
  end

  -- Menger's theorem: begin with a relay already standing, pre-linked.
  if self:has("menger") then
    local r = self.g:addNode(cx + 110, cy, "relay")
    self:applyNodePerks(r)
    self.g:addEdge(self.source.id, r.id, 1)
  end

  self:updateDemands()
  self:refresh()
  return self
end

-- Push the current wave's demand onto every terminal and total it up.
function Game:updateDemands()
  local total, peak = 0, 0
  for _, t in ipairs(self.g:nodesOfKind("sink")) do
    local age = self.wave - (t.bornWave or 1) + 1
    t.demand = Game.terminalDemand(age)
    t.age = age
    total = total + t.demand
    peak = math.max(peak, t.demand)
  end
  self.perTerminal = peak
  self.demand = total
  return total
end

function Game:has(theorem)
  return self.meta and self.meta.unlocked and self.meta.unlocked[theorem] or false
end

function Game:applyNodePerks(node)
  -- Dirac's theorem: every relay carries an extra port.
  if node.kind == "relay" and self:has("dirac") then node.ports = node.ports + 1 end
end

function Game:note(fmt, ...)
  table.insert(self.log, 1, string.format(fmt, ...))
  for i = #self.log, 25, -1 do self.log[i] = nil end
end

-- Recompute the live flow and min cut. Called after every mutation so the
-- player always sees their current bottleneck highlighted.
-- Two different questions, two different flows:
--   delivery  -- terminals capped at demand. Decides whether the wave holds.
--   capacity  -- terminals uncapped. The network's real throughput, and the
--               cut the adversary attacks. Without this split, exactly meeting
--               demand would leave the min cut empty and make you untouchable.
function Game:refresh()
  local flow, dcut, served, detail = self.g:maxflow(false)
  self.detail = detail or { edge = {}, node = {} }
  self.flow = flow
  self.served = served or {}
  -- What is actually stopping delivery right now. Distinct from the structural
  -- cut: a starved terminal can be blocked by arcs that are nowhere near the
  -- network's overall bottleneck.
  self.deliveryCut = dcut

  local capacity, cut = self.g:maxflow(true)
  self.capacity = capacity
  self.cut = cut
  self.cutSet = { node = {}, edge = {} }
  for _, c in ipairs(cut) do self.cutSet[c.kind][c.id] = true end

  self.cutCapacity = 0
  for _, c in ipairs(cut) do self.cutCapacity = self.cutCapacity + (c.cap or 0) end

  -- The cut worth showing the player: what blocks delivery if demand is unmet,
  -- otherwise what the adversary is about to sever.
  self.focusCut = (flow < (self.demand or 0)) and self.deliveryCut or self.cut
  self.focusSet = { node = {}, edge = {} }
  for _, c in ipairs(self.focusCut or {}) do self.focusSet[c.kind][c.id] = true end

  self.peakFlow = math.max(self.peakFlow, flow)
  return flow
end

--------------------------------------------------------------------------------
-- Costs
--------------------------------------------------------------------------------

function Game:nodeCost(kind)
  local b = Game.balance
  local base = Graph.KINDS[kind].cost
  return math.ceil(base * (b.nodeCostGrowth ^ self.builtNodes))
end

function Game:linkCost(a, b_)
  local b = Game.balance
  local na, nb = self.g.nodes[a], self.g.nodes[b_]
  local d = math.sqrt((na.x - nb.x) ^ 2 + (na.y - nb.y) ^ 2)
  local c = b.linkCostBase + b.linkCostPerUnit * d
  -- Whitney's theorem: connectivity comes cheaper.
  if self:has("whitney") then c = c * 0.8 end
  return math.ceil(c)
end

function Game:capCost(edgeId)
  local b = Game.balance
  return math.ceil(b.capUpgradeBase + b.capUpgradePerCap * self.g.edges[edgeId].cap)
end

function Game:tpCost(nodeId)
  local b = Game.balance
  local n = self.g.nodes[nodeId]
  if n.throughput >= Graph.INF then return nil end
  return math.ceil(b.tpUpgradeBase + b.tpUpgradePerTp * n.throughput)
end

function Game:spend(amount)
  if self.energy < amount then return false end
  self.energy = self.energy - amount
  return true
end

--------------------------------------------------------------------------------
-- Building
--------------------------------------------------------------------------------

function Game:placementError(x, y)
  local b = Game.balance
  if x < 40 or y < 40 or x > b.fieldW - 40 or y > b.fieldH - 40 then
    return "outside the field"
  end
  for _, n in ipairs(self.g:aliveNodes()) do
    local d = math.sqrt((n.x - x) ^ 2 + (n.y - y) ^ 2)
    if d < b.minNodeSpacing then return "too close to another node" end
  end
  return nil
end

function Game:buildNode(x, y, kind)
  if self.phase ~= "build" then return nil, "not in build phase" end
  local err = self:placementError(x, y)
  if err then return nil, err end
  local cost = self:nodeCost(kind)
  if self.energy < cost then return nil, "not enough energy" end
  self:spend(cost)
  local n = self.g:addNode(x, y, kind)
  self:applyNodePerks(n)
  self.builtNodes = self.builtNodes + 1
  self:refresh()
  return n
end

function Game:buildLink(a, b_)
  if self.phase ~= "build" then return nil, "not in build phase" end
  local ok, why = self.g:canLink(a, b_)
  if not ok then return nil, why end
  local na, nb = self.g.nodes[a], self.g.nodes[b_]
  local d = math.sqrt((na.x - nb.x) ^ 2 + (na.y - nb.y) ^ 2)
  if d > Game.balance.maxLinkRange then return nil, "beyond link range" end
  local cost = self:linkCost(a, b_)
  if self.energy < cost then return nil, "not enough energy" end
  self:spend(cost)
  local e = self.g:addEdge(a, b_, 1)
  self:refresh()
  return e
end

function Game:upgradeLink(edgeId)
  if self.phase ~= "build" then return nil, "not in build phase" end
  local e = self.g.edges[edgeId]
  if not (e and e.alive) then return nil, "link is destroyed" end
  local cost = self:capCost(edgeId)
  if self.energy < cost then return nil, "not enough energy" end
  self:spend(cost)
  e.cap = e.cap + 1
  self:refresh()
  return e
end

function Game:upgradeNode(nodeId)
  if self.phase ~= "build" then return nil, "not in build phase" end
  local n = self.g.nodes[nodeId]
  if not (n and n.alive) then return nil, "node is destroyed" end
  local cost = self:tpCost(nodeId)
  if not cost then return nil, "throughput is already unlimited" end
  if self.energy < cost then return nil, "not enough energy" end
  self:spend(cost)
  n.throughput = n.throughput + 1
  self:refresh()
  return n
end

-- Demolition. Without it a severed sub-network squats on its terminal's ports
-- forever and the terminal can never be reconnected: the run is lost to
-- bookkeeping rather than to the adversary. Refunds a fraction so that
-- restructuring is a real option and not just a penalty.
function Game:demolishLink(edgeId)
  if self.phase ~= "build" then return nil, "not in build phase" end
  local e = self.g.edges[edgeId]
  if not (e and e.alive) then return nil, "already gone" end
  local refund = math.floor(self:linkCost(e.a, e.b) * 0.4)
  self.g:killEdge(edgeId)
  self.energy = self.energy + refund
  self:refresh()
  return refund
end

function Game:demolishNode(nodeId)
  if self.phase ~= "build" then return nil, "not in build phase" end
  local n = self.g.nodes[nodeId]
  if not (n and n.alive) then return nil, "already gone" end
  if n.kind == "source" or n.kind == "sink" then return nil, "cannot demolish that" end
  local refund = math.floor(self:nodeCost(n.kind) * 0.4)
  self.g:killNode(nodeId)
  self.energy = self.energy + refund
  self:refresh()
  return refund
end

-- Nodes that can no longer reach the source contribute nothing but still hold
-- ports. Surfaced in the UI so the player can see what to clear.
function Game:darkNodes()
  local l = self.g:components()
  local home = l[self.source.id]
  local dark = {}
  for _, n in ipairs(self.g:aliveNodes()) do
    if l[n.id] ~= home then dark[#dark + 1] = n.id end
  end
  return dark
end

--------------------------------------------------------------------------------
-- Terminals
--------------------------------------------------------------------------------

-- Terminals appear progressively farther out, so surviving means physically
-- growing the network rather than thickening one trunk.
function Game:spawnTerminal()
  local b = Game.balance
  local k = self.terminalsPlaced
  local radius = b.terminalRadius0 + k * b.terminalRadiusK
  local cx, cy = b.fieldW / 2, b.fieldH / 2

  for _ = 1, 60 do
    local ang = math.random() * math.pi * 2
    local r = radius * (0.85 + math.random() * 0.3)
    local x = math.max(80, math.min(b.fieldW - 80, cx + math.cos(ang) * r))
    local y = math.max(80, math.min(b.fieldH - 80, cy + math.sin(ang) * r * 0.72))
    if not self:placementError(x, y) then
      local t = self.g:addNode(x, y, "sink")
      t.bornWave = self.wave
      t.demand = Game.terminalDemand(1)
      self.terminalsPlaced = k + 1
      return t
    end
  end
  return nil
end

--------------------------------------------------------------------------------
-- Resolve: deliver flow, then let the adversary cut.
--------------------------------------------------------------------------------

function Game:resolve()
  if self.phase ~= "build" then return nil end
  local flow, _, served = self.g:maxflow(false)
  local _cap, cut = self.g:maxflow(true)
  self.flow, self.cut, self.served = flow, cut, served or {}

  local report = {
    wave = self.wave,
    demand = self.demand,
    flow = flow,
    survived = flow >= self.demand,
    served = served,
    perTerminal = self.perTerminal,
    cutBefore = cut,
    strikes = {},
    income = 0,
    newTerminal = false,
    shielded = false,
  }

  if not report.survived then
    self.phase = "dead"
    self.lastReport = report
    local starved = 0
    for _, t in ipairs(self.g:nodesOfKind("sink")) do
      if (served[t.id] or 0) < (t.demand or 0) then starved = starved + 1 end
    end
    report.starved = starved
    self:note("COLLAPSE: %d of %d delivered, %d terminal(s) starved", flow, self.demand, starved)
    return report
  end

  local b = Game.balance
  local income = b.baseIncome + b.incomePerFlow * flow
  -- Ford-Fulkerson: a steadier baseline.
  if self:has("ford_fulkerson") then income = income + 15 end
  self.energy = self.energy + income
  report.income = income
  self:note("Wave %d held: %d/%d delivered, +%d energy", self.wave, flow, self.demand, income)

  -- The adversary strikes the minimum cut: precisely the arcs that bound your
  -- throughput. Redundancy is the only defence.
  local n = Game.strikesFor(self.wave)
  if n > 0 and #cut > 0 then
    if self.strikeShield then
      self.strikeShield = false
      report.shielded = true
      self:note("Euler circuit absorbed the strike")
    else
      -- Re-derive the cut between strikes: severing one arc moves the bottleneck.
      for _ = 1, n do
        local _, live = self.g:maxflow(true)
        if #live == 0 then break end
        -- Escalation: early waves only sever links. Destroying a node takes its
        -- whole star with it, which on a small network is not a setback but an
        -- extinction. Edge connectivity is the first lesson, vertex the second.
        local pool = live
        if self.wave < b.nodeStrikeWave then
          pool = {}
          for _, c in ipairs(live) do if c.kind == "edge" then pool[#pool + 1] = c end end
          if #pool == 0 then break end
        end
        local target = pool[math.random(#pool)]
        local hit = self:strike(target)
        if hit then table.insert(report.strikes, hit) end
      end
    end
  end

  self.wave = self.wave + 1
  if self.wave % b.terminalEvery == 1 and self.wave > 1 then
    if self:spawnTerminal() then
      report.newTerminal = true
      self:note("New terminal at the frontier: it demands its own supply")
    end
  end
  self:updateDemands()

  self.phase = "report"
  self.lastReport = report
  self:refresh()
  return report
end

-- A strike does not shave capacity, it severs. Destroying one member of the
-- minimum cut is what makes a single fat trunk suicidal and many thin parallel
-- routes survivable: lose one arc of a k-arc cut and you keep (k-1)/k of your
-- throughput. This is the lesson the whole game is built to teach.
function Game:strike(target)
  if target.kind == "edge" then
    local e = self.g.edges[target.id]
    if not (e and e.alive) then return nil end
    local na, nb = self.g.nodes[e.a], self.g.nodes[e.b]
    local mx, my = (na.x + nb.x) / 2, (na.y + nb.y) / 2
    self.g:killEdge(e.id)
    self:note("Link severed (capacity %d lost)", e.cap)
    return { kind = "edge", id = e.id, destroyed = true, x = mx, y = my,
             ax = na.x, ay = na.y, bx = nb.x, by = nb.y }
  else
    local n = self.g.nodes[target.id]
    if not (n and n.alive) or n.throughput >= Graph.INF then return nil end
    local lost = self.g:degree(n.id)
    self.g:killNode(n.id)
    self:note("Node destroyed (%d links lost with it)", lost)
    return { kind = "node", id = n.id, destroyed = true, x = n.x, y = n.y }
  end
end

function Game:beginNextWave()
  if self.phase == "report" then self.phase = "build" end
end

-- Paced so the full theorem set takes roughly a dozen runs. The earlier rate
-- handed out every unlock inside three runs, which spent the whole meta layer
-- before the player had learned to read a cut.
function Game:insightEarned()
  return math.floor(self.wave * 0.5 + self.peakFlow * 0.25)
end

return Game
