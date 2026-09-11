-- contract.lua -- one self-contained network puzzle.
--
-- A contract hands you a map, a fixed budget and a declared threat, and asks for
-- a network that still meets every demand AFTER the adversary takes its best k
-- removals. There is no income and no wave loop: the whole decision is how to
-- spend one budget on one geometry.
--
-- Demolition refunds in full, on purpose. The interesting act is re-laying the
-- network three times before committing, and charging for that would punish
-- exactly the behaviour the puzzle is built around.
local Graph = require("graph")

local C = {}
C.__index = C

C.costs = {
  relay   = 10,
  hub     = 18,
  conduit = 16,
  linkBase = 4,
  linkPerUnit = 1 / 40,   -- one point per 40 world units
  capacity = 5,           -- flat: capacity is cheap, and cheap is fragile
}

C.maxLinkRange = 300
C.conduitRange = 520     -- a conduit reaches across gaps a relay cannot
C.minNodeSpacing = 46

--------------------------------------------------------------------------------

function C.new(spec)
  local self = setmetatable({}, C)
  self.spec      = spec
  self.index     = spec.index or 1
  self.budget    = spec.budget
  self.par       = spec.par
  self.threat    = spec.threat or { kind = "edge", count = 1 }
  self.obstacles = spec.obstacles or {}
  self.tools     = spec.tools or { relay = true }
  self.bounds    = spec.bounds
  self.spent     = 0
  self.committed = false
  self.log       = {}

  self.g = Graph.new()
  self.source = self.g:addNode(spec.source.x, spec.source.y, "source")
  self.terminals = {}
  for _, t in ipairs(spec.terminals) do
    local n = self.g:addNode(t.x, t.y, "sink")
    n.demand = t.demand
    self.terminals[#self.terminals + 1] = n
  end

  self.demand = 0
  for _, t in ipairs(self.terminals) do self.demand = self.demand + t.demand end

  self:refresh()
  return self
end

function C:remaining() return self.budget - self.spent end

function C:note(fmt, ...)
  table.insert(self.log, 1, string.format(fmt, ...))
  for i = #self.log, 12, -1 do self.log[i] = nil end
end

--------------------------------------------------------------------------------
-- Costs
--------------------------------------------------------------------------------

function C:nodeCost(kind) return C.costs[kind] or 10 end

function C:linkCost(a, b)
  local na, nb = self.g.nodes[a], self.g.nodes[b]
  local d = math.sqrt((na.x - nb.x) ^ 2 + (na.y - nb.y) ^ 2)
  return math.ceil(C.costs.linkBase + d * C.costs.linkPerUnit)
end

function C:capCost() return C.costs.capacity end

--------------------------------------------------------------------------------
-- Geometry
--------------------------------------------------------------------------------

local function segCircle(ax, ay, bx, by, cx, cy, r)
  local dx, dy = bx - ax, by - ay
  local l2 = dx * dx + dy * dy
  local t = 0
  if l2 > 1e-9 then
    t = ((cx - ax) * dx + (cy - ay) * dy) / l2
    t = math.max(0, math.min(1, t))
  end
  local px, py = ax + dx * t, ay + dy * t
  return (px - cx) ^ 2 + (py - cy) ^ 2 <= r * r
end

function C:inObstacle(x, y)
  for _, o in ipairs(self.obstacles) do
    if (x - o.x) ^ 2 + (y - o.y) ^ 2 <= o.r * o.r then return true end
  end
  return false
end

function C:crossesObstacle(ax, ay, bx, by)
  for _, o in ipairs(self.obstacles) do
    if segCircle(ax, ay, bx, by, o.x, o.y, o.r) then return true end
  end
  return false
end

function C:placementError(x, y)
  local b = self.bounds
  if x < b.x or y < b.y or x > b.x + b.w or y > b.y + b.h then
    return "outside the site"
  end
  if self:inObstacle(x, y) then return "blocked ground" end
  for _, n in ipairs(self.g:aliveNodes()) do
    if (n.x - x) ^ 2 + (n.y - y) ^ 2 < C.minNodeSpacing ^ 2 then
      return "too close to another node"
    end
  end
  return nil
end

-- Reach is per link: a conduit at either end extends it.
function C:rangeBetween(a, b)
  local ka, kb = self.g.nodes[a].kind, self.g.nodes[b].kind
  if ka == "conduit" or kb == "conduit" then return C.conduitRange end
  return C.maxLinkRange
end

function C:linkError(a, b)
  local ok, why = self.g:canLink(a, b)
  if not ok then return why end
  local na, nb = self.g.nodes[a], self.g.nodes[b]
  local d = math.sqrt((na.x - nb.x) ^ 2 + (na.y - nb.y) ^ 2)
  if d > self:rangeBetween(a, b) then return "beyond link range" end
  if self:crossesObstacle(na.x, na.y, nb.x, nb.y) then return "blocked ground" end
  return nil
end

--------------------------------------------------------------------------------
-- Building
--------------------------------------------------------------------------------

function C:buildNode(x, y, kind)
  if self.committed then return nil, "contract already committed" end
  if not self.tools[kind] then return nil, "not unlocked" end
  local err = self:placementError(x, y)
  if err then return nil, err end
  local cost = self:nodeCost(kind)
  if cost > self:remaining() then return nil, "over budget" end
  local n = self.g:addNode(x, y, kind)
  -- Throughput is deliberately not a constraint here: a contract is about ports,
  -- reach and topology, and a hidden per-node ceiling would only obscure that.
  n.throughput = 999
  self.spent = self.spent + cost
  self:refresh()
  return n
end

function C:buildLink(a, b)
  if self.committed then return nil, "contract already committed" end
  local err = self:linkError(a, b)
  if err then return nil, err end
  local cost = self:linkCost(a, b)
  if cost > self:remaining() then return nil, "over budget" end
  local e = self.g:addEdge(a, b, 1)
  self.spent = self.spent + cost
  self:refresh()
  return e
end

function C:upgradeLink(id)
  if self.committed then return nil, "contract already committed" end
  local e = self.g.edges[id]
  if not (e and e.alive) then return nil, "no such link" end
  local cost = self:capCost()
  if cost > self:remaining() then return nil, "over budget" end
  e.cap = e.cap + 1
  self.spent = self.spent + cost
  self:refresh()
  return e
end

-- Full refunds: restructuring must be free, or the puzzle punishes thinking.
function C:demolishLink(id)
  if self.committed then return nil, "contract already committed" end
  local e = self.g.edges[id]
  if not (e and e.alive) then return nil, "no such link" end
  local refund = self:linkCost(e.a, e.b) + (e.cap - 1) * self:capCost()
  self.g:killEdge(id)
  self.spent = self.spent - refund
  self:refresh()
  return refund
end

function C:demolishNode(id)
  if self.committed then return nil, "contract already committed" end
  local n = self.g.nodes[id]
  if not (n and n.alive) then return nil, "no such node" end
  if n.kind == "source" or n.kind == "sink" then return nil, "cannot demolish that" end
  local refund = self:nodeCost(n.kind)
  for _, ei in ipairs(self.g.adj[id]) do
    local e = self.g.edges[ei]
    if e.alive then
      refund = refund + self:linkCost(e.a, e.b) + (e.cap - 1) * self:capCost()
    end
  end
  self.g:killNode(id)
  self.spent = self.spent - refund
  self:refresh()
  return refund
end

--------------------------------------------------------------------------------
-- Live evaluation. This is the heart of the puzzle: the player can always see
-- exactly what the adversary would take, so committing is a decision rather
-- than a gamble.
--------------------------------------------------------------------------------

-- `bulk` suppresses evaluation while the solver lays hundreds of pieces; it is
-- cleared by the next resilience query. Without it, pricing one contract costs
-- tens of thousands of max-flow computations.
-- Nodes that cannot reach the source carry nothing. Drawn as shells so a
-- stranded branch is visible rather than looking merely unused.
function C:darkNodes()
  local l = self.g:components()
  local home = l[self.source.id]
  local dark = {}
  for _, n in ipairs(self.g:aliveNodes()) do
    if l[n.id] ~= home then dark[#dark + 1] = n.id end
  end
  return dark
end

function C:refresh()
  if self.bulk then self.resDirty = true; return end

  local flow, dcut, served, detail = self.g:maxflow(false)
  self.flow, self.served = flow, served or {}
  self.detail = detail or { edge = {}, node = {} }
  self.deliveryCut = dcut

  local capacity, cut = self.g:maxflow(true)
  self.capacity, self.cut = capacity, cut
  self.cutSet = { node = {}, edge = {} }
  for _, c in ipairs(cut) do self.cutSet[c.kind][c.id] = true end

  -- The worst case is the expensive query: computed on demand, cached until the
  -- next edit, because it costs k * |E| max-flow solves.
  self.resDirty = true
  return flow
end

-- Delivery after the adversary's best removals.
function C:resilience()
  if self.bulk then
    self.bulk = false
    self:refresh()
  end
  if self.resDirty or not self.doomed then
    local after, removed = self.g:worstCase(self.threat.count, self.threat.kind)
    self.resilient = after
    self.doomed = removed
    self.doomedSet = { node = {}, edge = {} }
    for _, r in ipairs(removed) do self.doomedSet[r.kind][r.id] = true end
    self.focusSet = self.doomedSet
    self.resDirty = false
  end
  return self.resilient, self.doomed
end

function C:isSolved() return self:resilience() >= self.demand end

-- Commit: the adversary takes what the readout has been showing all along.
function C:commit()
  if self.committed then return nil end
  local after, removed = self.g:worstCase(self.threat.count, self.threat.kind)
  self.committed = true
  for _, r in ipairs(removed) do
    if r.kind == "edge" then self.g:killEdge(r.id) else self.g:killNode(r.id) end
  end
  local flow = self.g:maxflow(false)
  local result = {
    success = flow >= self.demand,
    delivered = flow,
    demand = self.demand,
    removed = removed,
    spent = self.spent,
    budget = self.budget,
    par = self.par,
    under = self.budget - self.spent,
    beatPar = self.par and self.spent <= self.par,
  }
  self.result = result
  self:refresh()
  return result
end

function C:reset()
  return C.new(self.spec)
end

return C
