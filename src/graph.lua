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
  -- The company caps its own producing buildings lower, in City:buySource.
  source   = { name = "SOURCE",   ports = 16, throughput = INF, cost = 0,   color = {0.36, 0.85, 0.62} },
  sink = { name = "TERMINAL", ports = 6, throughput = INF, cost = 0, color = {0.98, 0.62, 0.35} },
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
  -- The key is "exchange" because old saves carry it; migrate() turns every
  -- one into a level-4 manifold.
  exchange = { name = "HUB",      ports = 10, throughput = 999, cost = 500,  color = {0.45, 0.86, 0.72} },
  -- A works takes things off the network and puts something else back on: a
  -- customer and a well in one building. What it makes and what it wants are
  -- written on the node by the city, so the solver never has to know a recipe.
  works    = { name = "WORKS",    ports = 6,  throughput = 999, cost = 2000, color = {0.98, 0.72, 0.45} },
  -- A distribution centre is where bulk meets local: the only thing inland that
  -- a railway, a highway or a ship can terminate at, and an ordinary structure
  -- in every other way, so mains and roads run out of it to the city.
  dc       = { name = "DEPOT YARD", ports = 10, throughput = 999, cost = 1500, color = {0.98, 0.84, 0.52} },
  -- A depot buffers a commodity overnight: surplus production goes in at the
  -- close, and the next day it feeds the network like a small second well.
  depot    = { name = "DEPOT",    ports = 3,  throughput = 999, cost = 190, color = {0.62, 0.56, 0.98} },
  -- The people network. A stop is where a district boards a road or a route, a
  -- filling station sells petrol to the drivers passing it, and a resort is
  -- somewhere worth travelling to.
  stop     = { name = "BUS STOP",     ports = 6,  throughput = 999, cost = 120,  color = {0.94, 0.84, 0.44} },
  station  = { name = "STATION",  ports = 3,  throughput = 999, cost = 260,  color = {0.98, 0.62, 0.34} },
  resort   = { name = "RESORT",   ports = 4,  throughput = 999, cost = 4800, color = {0.98, 0.58, 0.74} },
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
  internet = { name = "INTERNET", order = 6, mark = "signal", conduit = "FIBRE", form = "data", role = "utility",
            landed = false,
            color = {0.40, 0.92, 0.82}, fill = {0.16, 0.62, 0.56} },

  -- Feedstock: what the works eat.
  wheat = { name = "WHEAT", order = 10, mark = "box", conduit = "ROAD", form = "solid", role = "feed",
            color = {0.90, 0.78, 0.38}, fill = {0.72, 0.60, 0.22} },
  malt  = { name = "MALT",  order = 11, mark = "box", conduit = "ROAD", form = "solid", role = "feed",
            color = {0.82, 0.62, 0.34}, fill = {0.62, 0.44, 0.20} },
  timber= { name = "TIMBER",order = 12, mark = "box", conduit = "ROAD", form = "solid", role = "feed",
            color = {0.52, 0.72, 0.44}, fill = {0.32, 0.50, 0.28} },
  ore   = { name = "ORE",   order = 13, mark = "box", conduit = "ROAD", form = "solid", role = "feed",
            color = {0.72, 0.50, 0.42}, fill = {0.50, 0.32, 0.26} },
  salt  = { name = "SALT",  order = 13.5, mark = "salt", conduit = "ROAD", form = "solid", role = "feed",
            color = {0.92, 0.92, 0.96}, fill = {0.70, 0.72, 0.78} },
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
  -- Fuel is sold to people rather than to a customer on a main: it goes down a
  -- main to a filling station and out of it by the tankful.
  gasoline={ name = "GASOLINE",order = 19, mark = "drop",conduit = "MAIN", form = "liquid", role = "fuel",
            color = {0.98, 0.66, 0.34}, fill = {0.86, 0.46, 0.16} },
  rubber= { name = "RUBBER",order = 20, mark = "box", conduit = "ROAD", form = "solid", role = "feed",
            color = {0.56, 0.54, 0.50}, fill = {0.28, 0.27, 0.24} },

  -- Materials: what the company builds with.
  steel = { name = "STEEL", order = 30, mark = "box", conduit = "ROAD", form = "solid", role = "material",
            color = {0.64, 0.72, 0.82}, fill = {0.40, 0.48, 0.58} },
  planks= { name = "PLANKS",order = 31, mark = "box", conduit = "ROAD", form = "solid", role = "material",
            color = {0.80, 0.64, 0.42}, fill = {0.58, 0.42, 0.24} },
  glass = { name = "GLASS", order = 32, mark = "box", conduit = "ROAD", form = "solid", role = "material",
            color = {0.60, 0.88, 0.88}, fill = {0.34, 0.64, 0.66} },
  concrete={name = "CONCRETE",order=33,mark = "box", conduit = "ROAD", form = "solid", role = "material",
            color = {0.70, 0.70, 0.72}, fill = {0.46, 0.46, 0.50} },

  -- Vehicles: taken in at the yards like materials, and sold to the districts.
  cars  = { name = "CARS",  order = 35, mark = "box", conduit = "ROAD", form = "solid", role = "vehicle",
            landed = false,
            color = {0.90, 0.42, 0.48}, fill = {0.66, 0.22, 0.28} },
}

-- The four trades the company sells by the day and holds a licence for. The
-- sidebar's trade row is these, and nothing else: a player picking a main to lay
-- is choosing a business, not shopping through nineteen tables.
Graph.TRADES = { "water", "power", "beer", "oil", "internet" }
for key,spec in pairs(require("data.infrastructure").kinds) do Graph.KINDS[key]=spec end
Graph.KINDS.junction.name="T SPLIT"
Graph.KINDS.manifold.name="HUB"
Graph.COMMODITIES.panels={name="SOLAR PANELS",order=34,mark="box",conduit="ROAD",form="solid",role="material",
  color={0.46,0.65,0.92},fill={0.22,0.36,0.62}}

-- The grid each commodity is drawn with. Selecting any commodity keeps its
-- whole grid at full strength on the map and fades every other grid.
Graph.GRIDS = {
  water="water", power="power", beer="beer", internet="internet",
  oil="oil", diesel="oil", gasoline="oil",
  food="food", wheat="food", malt="food",
  ore="metals", coke="metals", steel="metals",
  rock="stone", sand="stone", cement="stone", concrete="stone",
  timber="wood", planks="wood",
  salt="goods", glass="goods", rubber="goods", panels="goods", cars="goods",
}
function Graph.gridOf(commodity) return Graph.GRIDS[commodity] or commodity end

-- Everything, in a stable order, for the places that really do mean everything.
Graph.COMMODITIES.saltwater={name="SALTWATER",order=0,mark="saltwater",conduit="MAIN",form="liquid",role="feed",landed=false,
 color={0.42,0.82,0.88},fill={0.22,0.55,0.68}}
Graph.COMMODITIES.gems={name="GEMS",order=29,mark="gem",conduit="ROAD",form="solid",role="feed",landed=false,color={0.9,0.45,0.9},fill={0.6,0.2,0.7}}
Graph.COMMODITIES.jewelry={name="JEWELRY",order=36,mark="gem",conduit="ROAD",form="solid",role="material",landed=false,color={1,0.8,0.3},fill={0.8,0.6,0.1}}
Graph.GRIDS.saltwater="water"; Graph.GRIDS.gems="goods"; Graph.GRIDS.jewelry="goods"
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

-- A min-heap of (key, id) pairs: the smallest key first, the lower id on a
-- tie. The shortest-path searches over roads and routes settle places in
-- exactly that order.
function Graph.heap()
  local keys, ids, size = {}, {}, 0
  local function before(i, j) return keys[i] < keys[j] or keys[i] == keys[j] and ids[i] < ids[j] end
  local function swap(i, j) keys[i], keys[j] = keys[j], keys[i]; ids[i], ids[j] = ids[j], ids[i] end
  local h = {}
  function h.push(key, id)
    size = size + 1; keys[size], ids[size] = key, id
    local i = size
    while i > 1 do
      local p = math.floor(i / 2)
      if not before(i, p) then break end
      swap(i, p); i = p
    end
  end
  function h.pop()
    if size == 0 then return nil end
    local key, id = keys[1], ids[1]
    keys[1], ids[1] = keys[size], ids[size]; keys[size], ids[size] = nil, nil; size = size - 1
    local i = 1
    while true do
      local l, r, m = 2 * i, 2 * i + 1, i
      if l <= size and before(l, m) then m = l end
      if r <= size and before(r, m) then m = r end
      if m == i then break end
      swap(i, m); i = m
    end
    return key, id
  end
  return h
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

-- Arcs are held as parallel arrays rather than one table each, and every
-- search walks them with numeric loops. The solver runs a dozen times a day
-- per trade; in this shape LuaJIT compiles it instead of falling back to the
-- interpreter trace after trace, which made it slower than no JIT at all.
local function netNew(n)
  return setmetatable({ n = n, m = 0, from = {}, to = {}, cap = {}, cap0 = {}, meta = {}, adj = {} }, Net)
end

function Net:arc(u, v, cap, meta)
  local adj = self.adj
  local au, av = adj[u], adj[v]
  if not au then au = {}; adj[u] = au end
  if not av then av = {}; adj[v] = av end
  local m = self.m + 1
  self.from[m], self.to[m], self.cap[m], self.cap0[m], self.meta[m] = u, v, cap, cap, meta or false
  au[#au + 1] = m
  m = m + 1
  self.from[m], self.to[m], self.cap[m], self.cap0[m], self.meta[m] = v, u, 0, 0, false
  av[#av + 1] = m
  self.m = m
end

-- Levels from s over arcs with room left; -1 is unreached.
function Net:bfs(s, t)
  local level, adj, cap, to = self.level, self.adj, self.cap, self.to
  for i = 1, self.n do level[i] = -1 end
  level[s] = 0
  local q, head, tail = self.queue, 1, 1
  q[1] = s
  while head <= tail do
    local u = q[head]; head = head + 1
    local list = adj[u]
    if list then
      local next = level[u] + 1
      for k = 1, #list do
        local ai = list[k]
        local v = to[ai]
        if cap[ai] > 0 and level[v] == -1 then
          level[v] = next
          tail = tail + 1; q[tail] = v
        end
      end
    end
  end
  return level[t] ~= -1
end

-- One augmenting path along the level graph, as deep as it will go.
local D_adj, D_to, D_cap, D_level, D_iter
local function dfs(u, t, pushed)
  if u == t or pushed == 0 then return pushed end
  local list = D_adj[u]
  if not list then return 0 end
  local n, want = #list, D_level[u] + 1
  local i = D_iter[u]
  while i <= n do
    local ai = list[i]
    local c = D_cap[ai]
    if c > 0 and D_level[D_to[ai]] == want then
      local got = dfs(D_to[ai], t, math.min(pushed, c))
      if got > 0 then
        D_cap[ai] = c - got
        local r = ai % 2 == 1 and ai + 1 or ai - 1
        D_cap[r] = D_cap[r] + got
        D_iter[u] = i
        return got
      end
    end
    i = i + 1
    D_iter[u] = i
  end
  return 0
end

function Net:maxflow(s, t)
  local total = 0
  self.level, self.queue, self.iter = self.level or {}, self.queue or {}, self.iter or {}
  while self:bfs(s, t) do
    local iter = self.iter
    for i = 1, self.n do iter[i] = 1 end
    D_adj, D_to, D_cap, D_level, D_iter = self.adj, self.to, self.cap, self.level, iter
    while true do
      local f = dfs(s, t, INF)
      if f == 0 then break end
      total = total + f
    end
  end
  D_adj, D_to, D_cap, D_level, D_iter = nil, nil, nil, nil, nil
  return total
end

-- Set of vertices reachable from s in the residual network. The min cut is the
-- set of saturated arcs crossing out of it.
function Net:reachable(s)
  local adj, cap, to = self.adj, self.cap, self.to
  local seen, q, head = { [s] = true }, { s }, 1
  while head <= #q do
    local u = q[head]; head = head + 1
    local list = adj[u]
    if list then
      for k = 1, #list do
        local ai = list[k]
        local v = to[ai]
        if cap[ai] > 0 and not seen[v] then
          seen[v] = true
          q[#q + 1] = v
        end
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
  local spillCount=0
  if commodity=='oil' then
    for _,e in ipairs(self.edges) do if e.alive and (e.spillWanted or 0)>0 then spillCount=spillCount+1 end end
  end
  n=n+spillCount
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
    local links = self.adj[node.id]
    if node.alive and links and #links > 0 then
      local vin, vout = 2 * node.id - 1, 2 * node.id
      net:arc(vin, vout, node.throughput, { kind = "node", id = node.id })
      if node.kind == "source" and (not commodity or node.commodity == commodity) then
        -- A well produces a finite amount per day.
        net:arc(SS, vin, node.effectiveOutput or node.output or INF)
        node._feedArc = net.m - 1
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
        node._feedArc = net.m - 1
      elseif node.kind == "works" and (node.makes == commodity or node.coproduct == commodity) and (node.ready or 0) > 0 then
        -- Everything this works managed to make out of what turned up.
        net:arc(SS, vin, node.coproduct==commodity and node.coproductReady or node.ready)
        node._feedArc = net.m - 1
      elseif node.kind == "depot" and (node.stored or 0) > 0
             and (not commodity or node.commodity == commodity) then
        -- Yesterday's surplus, available today. A depot only ever gives back
        -- what was put into it, so it is capacity in time rather than in space.
        net:arc(SS, vin, node.stored)
        node._feedArc = net.m - 1
      end
      if (node.kind == "client" or node.kind == "sink") and not node.prospect
         and not node.supplyClosed
         and (not commodity or (node.demands and node.demands[commodity]) or node.commodity == commodity) then
        -- The service valve controls only this customer's draw, not the main.
        net:arc(vout, TT, uncapped and INF or (node.demands and node.demands[commodity]) or (node.demand or INF))
        node._drainArc = net.m - 1
      elseif node.kind == "depot" and node.intakeRequest and node.commodity==commodity then
        -- Fill storage only after customers and production inputs have been
        -- satisfied. The second solve reuses their flow in the residual graph.
        net.depotDemands=net.depotDemands or {}
        net.depotDemands[#net.depotDemands+1]={node=node,vertex=vout,amount=node.intakeRequest}
      elseif node.kind == "dc" and commodity and (node.intake or {})[commodity] then
        -- A yard takes materials in and holds them for the builders.
        net:arc(vout, TT, uncapped and INF or node.intake[commodity])
        node._drainArc = net.m - 1
      elseif node.kind == "station" and commodity == "gasoline" then
        -- A filling station is a customer for petrol, sized to its tank.
        net:arc(vout, TT, uncapped and INF or (node.fuelWanted or 30))
        node._drainArc = net.m - 1
      elseif node.kind == "works" and commodity and (node.wants or {})[commodity] then
        -- A works is a customer for each of its inputs, and it asks for exactly
        -- what its rated output would eat.
        net:arc(vout, TT, uncapped and INF or node.wants[commodity])
        node._drainArc = net.m - 1
      end
    end
  end

  local spillIndex=#self.nodes
  for _, e in ipairs(self.edges) do
    e._spillArc=nil
    e._arcAB, e._arcBA = nil, nil
    -- A main carries one thing. A bulk line carries whatever it has wagons for,
    -- each wagon with its own capacity, which is why beer and water can share a
    -- train and never a pipe.
    local cap
    if e.wagons then
      cap = commodity and e.wagons[commodity] or nil
      if cap and commodity=='oil' then cap=math.max(0,cap-(e.shipSpill or 0)) end
    elseif not commodity or e.commodity == commodity then cap = e.effectiveCap or e.cap end
    if e.transportBlocked then cap=0 end
    if e.alive and cap and self.nodes[e.a].alive and self.nodes[e.b].alive then
      net:arc(2 * e.a, 2 * e.b - 1, cap, { kind = "edge", id = e.id })
      e._arcAB = net.m - 1
      net:arc(2 * e.b, 2 * e.a - 1, cap, { kind = "edge", id = e.id })
      e._arcBA = net.m - 1
      if commodity=='oil' and (e.spillWanted or 0)>0 then
        spillIndex=spillIndex+1
        local spillVertex=2*spillIndex
        net:arc(2*e.a,spillVertex,INF)
        net:arc(2*e.b,spillVertex,INF)
        net:arc(spillVertex,TT,e.spillWanted)
        e._spillArc=net.m-1
      end
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
  for _,request in ipairs(net.depotDemands or {}) do
    net:arc(request.vertex,TT,request.amount)
    request.node._drainArc=net.m-1
  end
  if net.depotDemands then flow=flow+net:maxflow(SS,TT) end
  local seen = net:reachable(SS)

  local served, produced = {}, {}
  for _, node in ipairs(self.nodes) do
    if node.alive and node._drainArc and (node.kind == "client" or node.kind == "sink"
       or node.kind == "depot" or node.kind == "works" or node.kind == "dc" or node.kind == "station") then
      served[node.id] = net.cap0[node._drainArc] - net.cap[node._drainArc]
    end
    if node.alive and node._feedArc then
      produced[node.id] = net.cap0[node._feedArc] - net.cap[node._feedArc]
    end
    node._feedArc = nil
  end

  -- Signed flow per edge (positive means a -> b) and load per node, for the
  -- renderer: this is what makes the network visibly move.
  local detail = { edge = {}, node = {}, spill = {} }
  for _, e in ipairs(self.edges) do
    if e._spillArc then
      detail.spill[e.id]=net.cap0[e._spillArc]-net.cap[e._spillArc]
      e._spillArc=nil
    end
    if e._arcAB and e._arcBA then
      local ab, ba = e._arcAB, e._arcBA
      detail.edge[e.id] = (net.cap0[ab] - net.cap[ab]) - (net.cap0[ba] - net.cap[ba])
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
  local meta, cap0, from, to = net.meta, net.cap0, net.from, net.to
  for i = 1, net.m, 2 do
    local mt = meta[i]
    if mt and cap0[i] > 0 and seen[from[i]] and not seen[to[i]] then
      local key = mt.kind .. mt.id
      if not mark[key] then
        mark[key] = true
        cut[#cut + 1] = { kind = mt.kind, id = mt.id, cap = cap0[i] }
      end
    end
  end
  return flow, cut, served, detail, produced
end

return Graph
