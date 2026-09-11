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
  -- Customers. Placed by the world, never by the player.
  client   = { name = "CLIENT",   ports = 3,  throughput = INF, cost = 0,   color = {0.98, 0.62, 0.35} },
}

-- What flows. Each commodity is a separate network sharing the same ground.
Graph.COMMODITIES = {
  water = { name = "WATER", color = {0.38, 0.72, 0.98} },
  beer  = { name = "BEER",  color = {0.95, 0.72, 0.28} },
  oil   = { name = "OIL",   color = {0.72, 0.55, 0.95} },
}

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
    if node.alive then
      local vin, vout = 2 * node.id - 1, 2 * node.id
      local endpoint = commodity and node.kind == "client"
      net:arc(vin, vout, endpoint and 0 or node.throughput, { kind = "node", id = node.id })
      if node.kind == "source" and (not commodity or node.commodity == commodity) then
        -- A well produces a finite amount per day.
        net:arc(SS, vin, node.output or INF)
      end
      if (node.kind == "client" or node.kind == "sink") and not node.prospect
         and (not commodity or node.commodity == commodity) then
        net:arc(endpoint and vin or vout, TT, uncapped and INF or (node.demand or INF))
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

  local served = {}
  for _, node in ipairs(self.nodes) do
    if node.alive and (node.kind == "client" or node.kind == "sink") and node._drainArc then
      local a = net.arcs[node._drainArc]
      served[node.id] = a.cap0 - a.cap
    end
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
  return flow, cut, served, detail
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
