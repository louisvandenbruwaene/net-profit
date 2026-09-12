-- graph.lua -- the mathematical core of AUGMENT.
-- Pure Lua, no love dependencies, so it can be unit tested headless with lua5.4.
--
-- The game graph is undirected: nodes have a throughput limit and a port limit
-- (max degree), edges have a capacity. To model node throughput inside a flow
-- network we use the standard node-splitting construction: every node v becomes
-- an arc v_in -> v_out carrying that node's throughput. A minimum cut can then
-- land on a node as naturally as on an edge, which is exactly what Menger's
-- theorem describes and exactly what the adversary exploits.

local Graph = {}
Graph.__index = Graph

local INF = 1e9
Graph.INF = INF

-- Node archetypes. The tension the player navigates is ports (how many
-- connections a node can host) against throughput (how much can pass through
-- it). No archetype is good at both.
Graph.KINDS = {
  -- Produced infrastructure.
  source   = { name = "SOURCE",   ports = 16, throughput = INF, cost = 0,   color = {0.36, 0.85, 0.62} },
  sink = { name = "TERMINAL", ports = 6, throughput = INF, cost = 0, color = {0.98, 0.62, 0.35} },
  relay = { name = "RELAY", ports = 3, throughput = 8, cost = 14, color = {0.55, 0.71, 0.98} },
  hub = { name = "HUB", ports = 6, throughput = 4, cost = 26, color = {0.78, 0.63, 0.98} },
  conduit = { name = "CONDUIT", ports = 2, throughput = 16, cost = 24, color = {0.42, 0.88, 0.92} },
  junction = { name = "JUNCTION", ports = 3,  throughput = 999, cost = 22,  color = {0.55, 0.71, 0.98} },
  manifold = { name = "MANIFOLD", ports = 6,  throughput = 999, cost = 46,  color = {0.78, 0.63, 0.98} },
  pump     = { name = "PUMP",     ports = 2,  throughput = 999, cost = 38,  color = {0.42, 0.88, 0.92} },
  tower    = { name = "TOWER",    ports = 4,  throughput = 999, cost = 92,  color = {0.98, 0.82, 0.38} },
  -- A gate is a node-split arc the player can tighten by hand: the one piece of
  -- infrastructure that makes flow scarcer on purpose, so a branch downstream
  -- can be starved to keep a better-paying branch whole.
  gate     = { name = "GATE",     ports = 2,  throughput = 6,   cost = 30,  color = {0.98, 0.70, 0.33} },
  -- A haven: the city's door to the outside world. It produces nothing itself
  -- and owns no ground worth speaking of, but everything the city does not make
  -- for itself arrives through it without limit, at a price charged on every
  -- unit that moves and a haulage bill for every metre it travels.
  terminal = { name = "HAVEN",    ports = 6,  throughput = 999, cost = 2200, color = {0.86, 0.74, 0.52} },
  -- The company's presence in a neighbourhood, rather than a pipe to one
  -- building. Everything inside its radius that pays enough is served from it
  -- without a main being drawn, which is what lets a company run a thousand
  -- customers without the player drawing a thousand pipes and without the
  -- solver carrying a thousand nodes.
  --
  -- The key is "exchange" and the name on screen is HUB, because the archived
  -- contract game above already owns "hub" in this table and a duplicate key in
  -- a Lua constructor silently wins. Do not rename either one.
  exchange = { name = "HUB",      ports = 8,  throughput = 999, cost = 1400, color = {0.45, 0.86, 0.72} },
  -- A works takes things off the network and puts something else back on: a
  -- customer and a well in one building. What it makes and what it wants are
  -- written on the node by the city, so the solver never has to know a recipe.
  works    = { name = "WORKS",    ports = 6,  throughput = 999, cost = 2000, color = {0.98, 0.72, 0.45} },
  -- A depot buffers a commodity overnight: surplus production goes in at the
  -- close, and the next day it feeds the network like a small second well.
  depot    = { name = "DEPOT",    ports = 3,  throughput = 999, cost = 190, color = {0.62, 0.56, 0.98} },
  -- Customers. Placed by the world, never by the player.
  client   = { name = "CLIENT",   ports = 3,  throughput = INF, cost = 0,   color = {0.98, 0.62, 0.35} },
}

-- What flows. Each commodity is a separate network sharing the same ground.
-- What flows, and how it reads on screen. `color` is the legible one, used for
-- outlines, pipes and text; `fill` is the body of the droplet, which is the
-- colour the commodity actually is. Oil is black, so it needs a steel rim to
-- survive a dark background; water and beer are legible as themselves.
-- `mark` is the glyph the trade is drawn with everywhere: liquids get a
-- droplet, electricity gets a bolt, because a thing that is not a liquid should
-- not be drawn as one. `conduit` is what a link carrying it is called.
-- Everything the city moves.
--
-- Three things decide what a commodity is. Its `form` decides how it travels:
-- a liquid goes down a main, electricity goes down a cable, and a solid goes by
-- road or by rail, because nobody pipes iron ore. Its `role` decides what it is
-- for: a utility is sold to customers by the day, a feedstock is eaten by a
-- works, and a material is spent on building things. And `order` is the order
-- it appears in, everywhere, because `pairs` is not stable and a sidebar that
-- shuffles itself is a sidebar nobody can learn.
Graph.COMMODITIES = {
  -- Utilities: the four the company started with, and the one the works make.
  water = { name = "WATER", order = 1, mark = "drop", conduit = "MAIN", form = "liquid", role = "utility",
            color = {0.38, 0.72, 0.98}, fill = {0.22, 0.52, 0.86} },
  power = { name = "POWER", order = 2, mark = "bolt", conduit = "CABLE", form = "energy", role = "utility",
            landed = false,
            color = {0.78, 0.56, 1.00}, fill = {0.58, 0.32, 0.92} },
  beer  = { name = "BEER",  order = 3, mark = "drop", conduit = "MAIN", form = "liquid", role = "utility",
            color = {0.95, 0.76, 0.26}, fill = {0.88, 0.66, 0.14} },
  oil   = { name = "OIL",   order = 4, mark = "drop", conduit = "MAIN", form = "liquid", role = "utility",
            color = {0.60, 0.62, 0.70}, fill = {0.045, 0.05, 0.07} },
  food  = { name = "FOOD",  order = 5, mark = "box",  conduit = "ROAD", form = "solid",  role = "utility",
            color = {0.96, 0.55, 0.42}, fill = {0.78, 0.36, 0.26} },

  -- Feedstock: what the works eat.
  wheat = { name = "WHEAT", order = 10, mark = "box", conduit = "ROAD", form = "solid", role = "feed",
            color = {0.90, 0.78, 0.38}, fill = {0.72, 0.60, 0.22} },
  malt  = { name = "MALT",  order = 11, mark = "box", conduit = "ROAD", form = "solid", role = "feed",
            color = {0.82, 0.62, 0.34}, fill = {0.62, 0.44, 0.20} },
  timber= { name = "TIMBER",order = 12, mark = "box", conduit = "ROAD", form = "solid", role = "feed",
            color = {0.52, 0.72, 0.44}, fill = {0.32, 0.50, 0.28} },
  ore   = { name = "ORE",   order = 13, mark = "box", conduit = "ROAD", form = "solid", role = "feed",
            color = {0.72, 0.50, 0.42}, fill = {0.50, 0.32, 0.26} },
  coke  = { name = "COKE",  order = 14, mark = "box", conduit = "ROAD", form = "solid", role = "feed",
            color = {0.46, 0.46, 0.52}, fill = {0.20, 0.20, 0.24} },
  rock  = { name = "ROCK",  order = 15, mark = "box", conduit = "ROAD", form = "solid", role = "feed",
            landed = false,
            color = {0.62, 0.60, 0.66}, fill = {0.40, 0.38, 0.44} },
  sand  = { name = "SAND",  order = 16, mark = "box", conduit = "ROAD", form = "solid", role = "feed",
            color = {0.90, 0.84, 0.62}, fill = {0.72, 0.66, 0.44} },
  cement= { name = "CEMENT",order = 17, mark = "box", conduit = "ROAD", form = "solid", role = "feed",
            color = {0.74, 0.74, 0.78}, fill = {0.52, 0.52, 0.56} },
  diesel= { name = "DIESEL",order = 18, mark = "drop",conduit = "MAIN", form = "liquid", role = "feed",
            color = {0.86, 0.64, 0.30}, fill = {0.60, 0.40, 0.16} },

  -- Materials: what the company builds with.
  steel = { name = "STEEL", order = 30, mark = "box", conduit = "ROAD", form = "solid", role = "material",
            color = {0.64, 0.72, 0.82}, fill = {0.40, 0.48, 0.58} },
  planks= { name = "PLANKS",order = 31, mark = "box", conduit = "ROAD", form = "solid", role = "material",
            color = {0.80, 0.64, 0.42}, fill = {0.58, 0.42, 0.24} },
  glass = { name = "GLASS", order = 32, mark = "box", conduit = "ROAD", form = "solid", role = "material",
            color = {0.60, 0.88, 0.88}, fill = {0.34, 0.64, 0.66} },
  concrete={name = "CONCRETE",order=33,mark = "box", conduit = "ROAD", form = "solid", role = "material",
            color = {0.70, 0.70, 0.72}, fill = {0.46, 0.46, 0.50} },
}

-- The four trades the company sells by the day and holds a licence for. The
-- sidebar's trade row is these, and nothing else: a player picking a main to lay
-- is choosing a business, not shopping through nineteen tables.
Graph.TRADES = { "water", "power", "beer", "oil" }

-- Everything, in a stable order, for the places that really do mean everything.
Graph.ALL = {}
for key in pairs(Graph.COMMODITIES) do Graph.ALL[#Graph.ALL + 1] = key end
table.sort(Graph.ALL, function(a, b)
  return Graph.COMMODITIES[a].order < Graph.COMMODITIES[b].order
end)

-- What a commodity travels in. A main, a cable and a road are three different
-- pieces of infrastructure with three different prices, and which one you are
-- laying is decided by what you are moving rather than by a menu.
function Graph.formOf(commodity)
  return (Graph.COMMODITIES[commodity] or Graph.COMMODITIES.water).form
end

function Graph.new()
  local self = setmetatable({}, Graph)
  self.nodes = {}      -- dense array of node records
  self.edges = {}      -- dense array of edge records
  self.adj = {}        -- node index -> array of edge indices
  return self
end

function Graph:addNode(x, y, kind)
  local spec = Graph.KINDS[kind]
  assert(spec, "unknown node kind: " .. tostring(kind))
  local n = {
    id = #self.nodes + 1,
    x = x, y = y,
    kind = kind,
    ports = spec.ports,
    throughput = spec.throughput,
    alive = true,
  }
  self.nodes[n.id] = n
  self.adj[n.id] = {}
  return n
end

function Graph:degree(id)
  local d = 0
  for _, ei in ipairs(self.adj[id] or {}) do
    if self.edges[ei].alive then d = d + 1 end
  end
  return d
end

function Graph:freePorts(id)
  local n = self.nodes[id]
  if not n or not n.alive then return 0 end
  return n.ports - self:degree(id)
end

function Graph:hasEdge(a, b)
  for _, ei in ipairs(self.adj[a] or {}) do
    local e = self.edges[ei]
    if e.alive and ((e.a == a and e.b == b) or (e.a == b and e.b == a)) then return ei end
  end
  return nil
end

-- Returns edge, or nil plus a human-readable reason. The reasons are surfaced
-- directly in the UI, so they are phrased for the player rather than the log.
function Graph:canLink(a, b)
  if a == b then return false, "a node cannot link to itself" end
  local na, nb = self.nodes[a], self.nodes[b]
  if not (na and nb and na.alive and nb.alive) then return false, "node is destroyed" end
  if self:hasEdge(a, b) then return false, "link already exists" end
  if self:freePorts(a) < 1 then return false, string.format("%s is out of ports", Graph.KINDS[na.kind].name) end
  if self:freePorts(b) < 1 then return false, string.format("%s is out of ports", Graph.KINDS[nb.kind].name) end
  return true
end

function Graph:addEdge(a, b, cap)
  local ok, why = self:canLink(a, b)
  if not ok then return nil, why end
  local e = { id = #self.edges + 1, a = a, b = b, cap = cap or 1, alive = true }
  self.edges[e.id] = e
  table.insert(self.adj[a], e.id)
  table.insert(self.adj[b], e.id)
  return e
end

function Graph:length(e)
  local na, nb = self.nodes[e.a], self.nodes[e.b]
  return math.sqrt((na.x - nb.x) ^ 2 + (na.y - nb.y) ^ 2)
end

function Graph:killEdge(id)
  local e = self.edges[id]
  if e and e.alive then e.alive = false; return true end
  return false
end

function Graph:killNode(id)
  local n = self.nodes[id]
  if not n or not n.alive then return false end
  n.alive = false
  for _, ei in ipairs(self.adj[id]) do self.edges[ei].alive = false end
  return true
end

function Graph:aliveNodes()
  local t = {}
  for _, n in ipairs(self.nodes) do if n.alive then t[#t + 1] = n end end
  return t
end

-- Every live edge on a node. Callers ask this when what matters is not how many
-- links a node has but what they carry: a haven's headroom, for instance, is
-- the capacity of the track leaving it.
function Graph:edgesAt(id)
  local t = {}
  for _, ei in ipairs(self.adj[id] or {}) do
    if self.edges[ei].alive then t[#t + 1] = self.edges[ei] end
  end
  return t
end

function Graph:nodesOfKind(kind)
  local t = {}
  for _, n in ipairs(self.nodes) do if n.alive and n.kind == kind then t[#t + 1] = n end end
  return t
end

--------------------------------------------------------------------------------
-- Dinic max flow over the node-split network.
--------------------------------------------------------------------------------

local Net = {}
Net.__index = Net

local function netNew(n)
  return setmetatable({ n = n, arcs = {}, adj = {} }, Net)
end

function Net:arc(u, v, cap, meta)
  self.adj[u] = self.adj[u] or {}
  self.adj[v] = self.adj[v] or {}
  self.arcs[#self.arcs + 1] = { from = u, to = v, cap = cap, cap0 = cap, meta = meta }
  table.insert(self.adj[u], #self.arcs)
  self.arcs[#self.arcs + 1] = { from = v, to = u, cap = 0, cap0 = 0 }
  table.insert(self.adj[v], #self.arcs)
end

local function rev(i) return (i % 2 == 1) and (i + 1) or (i - 1) end

function Net:bfs(s, t)
  self.level = {}
  local q, head = { s }, 1
  self.level[s] = 0
  while head <= #q do
    local u = q[head]; head = head + 1
    for _, ai in ipairs(self.adj[u] or {}) do
      local a = self.arcs[ai]
      if a.cap > 0 and self.level[a.to] == nil then
        self.level[a.to] = self.level[u] + 1
        q[#q + 1] = a.to
      end
    end
  end
  return self.level[t] ~= nil
end

function Net:dfs(u, t, pushed)
  if u == t or pushed == 0 then return pushed end
  while self.iter[u] <= #(self.adj[u] or {}) do
    local ai = self.adj[u][self.iter[u]]
    local a = self.arcs[ai]
    if a.cap > 0 and self.level[a.to] == (self.level[u] or -1) + 1 then
      local got = self:dfs(a.to, t, math.min(pushed, a.cap))
      if got > 0 then
        a.cap = a.cap - got
        self.arcs[rev(ai)].cap = self.arcs[rev(ai)].cap + got
        return got
      end
    end
    self.iter[u] = self.iter[u] + 1
  end
  return 0
end

function Net:maxflow(s, t)
  local total = 0
  while self:bfs(s, t) do
    self.iter = {}
    for i = 1, self.n do self.iter[i] = 1 end
    while true do
      local f = self:dfs(s, t, INF)
      if f == 0 then break end
      total = total + f
    end
  end
  return total
end

-- Set of vertices reachable from s in the residual network. The min cut is the
-- set of saturated arcs crossing out of it.
function Net:reachable(s)
  local seen, q, head = { [s] = true }, { s }, 1
  while head <= #q do
    local u = q[head]; head = head + 1
    for _, ai in ipairs(self.adj[u] or {}) do
      local a = self.arcs[ai]
      if a.cap > 0 and not seen[a.to] then
        seen[a.to] = true
        q[#q + 1] = a.to
      end
    end
  end
  return seen
end

-- Builds the flow network. Node i occupies vertices (2i-1) = in, (2i) = out.
-- A super source feeds every source node; every terminal drains to a super sink.
-- `uncapped` ignores per-terminal demand, giving the network's structural
-- throughput and its true bottleneck. Capped gives what is actually delivered.
-- `commodity` selects which network to solve: only pipes carrying it, wells
-- producing it and customers asking for it take part. Junctions are shared
-- ground, so a manifold can host water and beer without the two ever mixing.
function Graph:buildNetwork(uncapped, commodity)
  local n = #self.nodes
  local net = netNew(2 * n + 2)
  local SS, TT = 2 * n + 1, 2 * n + 2
  net.adj[SS] = {}; net.adj[TT] = {}

  for _, node in ipairs(self.nodes) do
    -- Cleared every build: a node that drained in the water network must not
    -- keep a stale arc index when the beer network is solved next.
    node._drainArc = nil
    node._feedArc = nil
    -- A node with nothing tied into it can neither carry, receive nor deliver.
    -- On a map where thousands of customers are covered by a hub rather than
    -- piped, leaving them out is the difference between a solve that fits in a
    -- frame and one that does not: they were costing four arcs each, four times
    -- over, to sit in the network doing nothing.
    if node.alive and #(self.adj[node.id] or {}) > 0 then
      local vin, vout = 2 * node.id - 1, 2 * node.id
      net:arc(vin, vout, node.throughput, { kind = "node", id = node.id })
      if node.kind == "source" and (not commodity or node.commodity == commodity) then
        -- A well produces a finite amount per day.
        net:arc(SS, vin, node.output or INF)
        node._feedArc = #net.arcs - 1
      elseif node.kind == "terminal" and commodity
             and (Graph.COMMODITIES[commodity] or {}).landed ~= false
             and (not node.commodity or node.commodity == commodity) then
        -- A haven is the outside world, and the outside world does not run out:
        -- it feeds every network except electricity, without a ceiling, and
        -- bills for every unit that actually lands. What stops it being free
        -- supply is the price per unit and the track it has to leave by.
        -- (A haven saved before havens carried every trade keeps its single
        -- commodity until it is migrated.)
        net:arc(SS, vin, node.output or INF)
        node._feedArc = #net.arcs - 1
      elseif node.kind == "works" and node.makes == commodity and (node.ready or 0) > 0 then
        -- Everything this works managed to make out of what turned up.
        net:arc(SS, vin, node.ready)
        node._feedArc = #net.arcs - 1
      elseif node.kind == "depot" and (node.stored or 0) > 0
             and (not commodity or node.commodity == commodity) then
        -- Yesterday's surplus, available today. A depot only ever gives back
        -- what was put into it, so it is capacity in time rather than in space.
        net:arc(SS, vin, node.stored)
        node._feedArc = #net.arcs - 1
      end
      if (node.kind == "client" or node.kind == "sink") and not node.prospect
         and not node.supplyClosed and not node.hub
         and (not commodity or node.commodity == commodity) then
        -- The service valve controls only this customer's draw, not the main.
        -- A customer on a hub is not here at all: their demand is carried by
        -- the hub, as one number.
        net:arc(vout, TT, uncapped and INF or (node.demand or INF))
        node._drainArc = #net.arcs - 1
      elseif node.kind == "exchange" and commodity and (node.demandBy or {})[commodity] then
        net:arc(vout, TT, uncapped and INF or node.demandBy[commodity])
        node._drainArc = #net.arcs - 1
      elseif node.kind == "works" and commodity and (node.wants or {})[commodity] then
        -- A works is a customer for each of its inputs, and it asks for exactly
        -- what its rated output would eat.
        net:arc(vout, TT, uncapped and INF or node.wants[commodity])
        node._drainArc = #net.arcs - 1
      end
    end
  end

  for _, e in ipairs(self.edges) do
    e._arcAB, e._arcBA = nil, nil
    if e.alive and self.nodes[e.a].alive and self.nodes[e.b].alive
       and (not commodity or e.commodity == commodity) then
      net:arc(2 * e.a, 2 * e.b - 1, e.cap, { kind = "edge", id = e.id })
      e._arcAB = #net.arcs - 1
      net:arc(2 * e.b, 2 * e.a - 1, e.cap, { kind = "edge", id = e.id })
      e._arcBA = #net.arcs - 1
    end
  end

  return net, SS, TT
end

-- Returns: flow value, list of cut members {kind="node"|"edge", id=...},
-- and a per-terminal delivery table. Cut members are deduplicated, because an
-- undirected edge contributes two arcs.
function Graph:maxflow(uncapped, commodity)
  local net, SS, TT = self:buildNetwork(uncapped, commodity)
  local flow = net:maxflow(SS, TT)
  local seen = net:reachable(SS)

  local served, produced = {}, {}
  for _, node in ipairs(self.nodes) do
    if node.alive and node._drainArc and (node.kind == "client" or node.kind == "sink"
       or node.kind == "exchange" or node.kind == "works") then
      local a = net.arcs[node._drainArc]
      served[node.id] = a.cap0 - a.cap
    end
    if node.alive and node._feedArc then
      local a = net.arcs[node._feedArc]
      produced[node.id] = a.cap0 - a.cap
    end
    node._feedArc = nil
  end

  -- Signed flow per edge (positive means a -> b) and load per node, for the
  -- renderer: this is what makes the network visibly move.
  local detail = { edge = {}, node = {} }
  for _, e in ipairs(self.edges) do
    if e._arcAB and e._arcBA then
      local ab = net.arcs[e._arcAB]
      local ba = net.arcs[e._arcBA]
      detail.edge[e.id] = (ab.cap0 - ab.cap) - (ba.cap0 - ba.cap)
    end
    e._arcAB, e._arcBA = nil, nil
  end
  for _, node in ipairs(self.nodes) do
    if node.alive then detail.node[node.id] = 0 end
  end
  -- Node load is the sum of flow arriving on incident edges, halved.
  for _, e in ipairs(self.edges) do
    local f = math.abs(detail.edge[e.id] or 0)
    if f > 0 then
      detail.node[e.a] = (detail.node[e.a] or 0) + f
      detail.node[e.b] = (detail.node[e.b] or 0) + f
    end
  end
  for id, v in pairs(detail.node) do detail.node[id] = v / 2 end

  local cut, mark = {}, {}
  for i, a in ipairs(net.arcs) do
    if i % 2 == 1 and a.meta and a.cap0 > 0 and seen[a.from] and not seen[a.to] then
      local key = a.meta.kind .. a.meta.id
      if not mark[key] then
        mark[key] = true
        cut[#cut + 1] = { kind = a.meta.kind, id = a.meta.id, cap = a.cap0 }
      end
    end
  end
  return flow, cut, served, detail, produced
end

--------------------------------------------------------------------------------
-- Resilience: what the adversary can take.
--------------------------------------------------------------------------------

-- The adversary removes k things, one at a time, each time taking whichever
-- single removal costs the most delivery. Greedy across steps but exact within
-- each step, which makes it both strong and explainable: "it takes the link that
-- hurts most, k times".
--
-- Delivery (demand-capped) is the objective, because that is the win condition.
-- Candidates are every live edge rather than the members of one minimum cut: a
-- graph can have several distinct minimum cuts, and picking from only one of
-- them would understate the threat and make the readout a lie.
--
-- Returns: delivery after the removals, and the list of what was removed.
function Graph:worstCase(k, kind)
  kind = kind or "edge"
  if not k or k <= 0 then return (self:maxflow(false)), {} end

  local removed = {}
  for _ = 1, k do
    local bestFlow, bestPick

    if kind == "edge" then
      for _, e in ipairs(self.edges) do
        if e.alive and self.nodes[e.a].alive and self.nodes[e.b].alive then
          e.alive = false
          local f = self:maxflow(false)
          e.alive = true
          if not bestFlow or f < bestFlow then bestFlow, bestPick = f, e end
        end
      end
      if not bestPick then break end
      bestPick.alive = false
      removed[#removed + 1] = { kind = "edge", id = bestPick.id }
    else
      for _, n in ipairs(self.nodes) do
        if n.alive and n.kind ~= "source" and n.kind ~= "sink" then
          n.alive = false
          local f = self:maxflow(false)
          n.alive = true
          if not bestFlow or f < bestFlow then bestFlow, bestPick = f, n end
        end
      end
      if not bestPick then break end
      bestPick.alive = false
      removed[#removed + 1] = { kind = "node", id = bestPick.id }
    end
  end

  local finalFlow = self:maxflow(false)

  -- Restore: this is a query, not a mutation.
  for _, r in ipairs(removed) do
    if r.kind == "edge" then self.edges[r.id].alive = true
    else self.nodes[r.id].alive = true end
  end

  return finalFlow, removed
end

--------------------------------------------------------------------------------
-- Structural diagnostics. These drive the stats panel, which is where the
-- player actually learns to read a graph.
--------------------------------------------------------------------------------

function Graph:neighbours(id)
  local t = {}
  for _, ei in ipairs(self.adj[id] or {}) do
    local e = self.edges[ei]
    if e.alive then
      local o = (e.a == id) and e.b or e.a
      if self.nodes[o].alive then t[#t + 1] = o end
    end
  end
  return t
end

-- Component labels for alive nodes, plus the component count.
function Graph:components()
  local label, count = {}, 0
  for _, node in ipairs(self:aliveNodes()) do
    if not label[node.id] then
      count = count + 1
      local q, head = { node.id }, 1
      label[node.id] = count
      while head <= #q do
        local u = q[head]; head = head + 1
        for _, v in ipairs(self:neighbours(u)) do
          if not label[v] then label[v] = count; q[#q + 1] = v end
        end
      end
    end
  end
  return label, count
end

function Graph:isConnected()
  local _, c = self:components()
  return c <= 1
end

-- BFS hop distance from a set of roots. Used for the latency readout.
function Graph:distancesFrom(roots)
  local dist, q, head = {}, {}, 1
  for _, r in ipairs(roots) do dist[r] = 0; q[#q + 1] = r end
  while head <= #q do
    local u = q[head]; head = head + 1
    for _, v in ipairs(self:neighbours(u)) do
      if dist[v] == nil then dist[v] = dist[u] + 1; q[#q + 1] = v end
    end
  end
  return dist
end

-- Tarjan articulation points: nodes whose loss disconnects the graph. Shown as
-- a warning, because they are the vertex cuts the adversary hunts for.
function Graph:articulationPoints()
  local disc, low, parent, ap = {}, {}, {}, {}
  local timer = 0

  local function visit(u)
    local stack = { { u, 1 } }
    timer = timer + 1
    disc[u], low[u] = timer, timer
    local children = {}
    children[u] = 0
    while #stack > 0 do
      local top = stack[#stack]
      local v, idx = top[1], top[2]
      local nbrs = self:neighbours(v)
      if idx <= #nbrs then
        top[2] = idx + 1
        local w = nbrs[idx]
        if disc[w] == nil then
          parent[w] = v
          children[v] = (children[v] or 0) + 1
          timer = timer + 1
          disc[w], low[w] = timer, timer
          children[w] = 0
          stack[#stack + 1] = { w, 1 }
        elseif w ~= parent[v] then
          low[v] = math.min(low[v], disc[w])
        end
      else
        table.remove(stack)
        local p = parent[v]
        if p then
          low[p] = math.min(low[p], low[v])
          if parent[p] == nil then
            if (children[p] or 0) > 1 then ap[p] = true end
          elseif low[v] >= disc[p] then
            ap[p] = true
          end
        end
      end
    end
  end

  for _, node in ipairs(self:aliveNodes()) do
    if disc[node.id] == nil then visit(node.id) end
  end

  local list = {}
  for id in pairs(ap) do list[#list + 1] = id end
  table.sort(list)
  return list
end

function Graph:stats()
  local alive = self:aliveNodes()
  local edges = 0
  for _, e in ipairs(self.edges) do
    if e.alive and self.nodes[e.a].alive and self.nodes[e.b].alive then edges = edges + 1 end
  end
  local minDeg, maxDeg, sumDeg = math.huge, 0, 0
  for _, n in ipairs(alive) do
    local d = self:degree(n.id)
    minDeg = math.min(minDeg, d)
    maxDeg = math.max(maxDeg, d)
    sumDeg = sumDeg + d
  end
  if #alive == 0 then minDeg = 0 end
  local _, comps = self:components()
  return {
    order = #alive,
    size = edges,
    minDegree = minDeg == math.huge and 0 or minDeg,
    maxDegree = maxDeg,
    avgDegree = #alive > 0 and (sumDeg / #alive) or 0,
    components = comps,
    cutVertices = self:articulationPoints(),
  }
end

return Graph
