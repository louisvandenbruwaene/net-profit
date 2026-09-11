-- Headless unit tests: lua5.4 test/test_graph.lua
-- Every expected value here is hand-computed, not recorded from the implementation.
package.path = "src/?.lua;../src/?.lua;" .. package.path
local Graph = require("graph")

local pass, fail = 0, 0
local function check(name, got, want)
  if got == want then
    pass = pass + 1
  else
    fail = fail + 1
    print(string.format("  FAIL  %s\n        got %s, want %s", name, tostring(got), tostring(want)))
  end
end

-- Free a node from balance constraints so tests stay stable across tuning.
local function unbound(g, id, tp, ports)
  g.nodes[id].throughput = tp or 1000
  g.nodes[id].ports = ports or 20
  return id
end

--------------------------------------------------------------------------------
print("edge bottleneck")
do
  local g = Graph.new()
  local s = g:addNode(0, 0, "source").id
  local r = unbound(g, g:addNode(1, 0, "relay").id)
  local t = g:addNode(2, 0, "sink").id
  g:addEdge(s, r, 3)
  g:addEdge(r, t, 2)
  local f, cut = g:maxflow()
  check("flow = min(3,2)", f, 2)
  check("cut size", #cut, 1)
  check("cut is an edge", cut[1] and cut[1].kind, "edge")
  check("cut capacity", cut[1] and cut[1].cap, 2)
end

--------------------------------------------------------------------------------
print("node throughput bottleneck")
do
  local g = Graph.new()
  local s = g:addNode(0, 0, "source").id
  local r = g:addNode(1, 0, "relay").id
  local t = g:addNode(2, 0, "sink").id
  g.nodes[r].throughput = 4
  g:addEdge(s, r, 10)
  g:addEdge(r, t, 10)
  local f, cut = g:maxflow()
  check("flow capped by node", f, 4)
  check("cut is the node", cut[1] and cut[1].kind, "node")
  check("cut node id", cut[1] and cut[1].id, r)
end

--------------------------------------------------------------------------------
print("parallel paths add up")
do
  local g = Graph.new()
  local s = unbound(g, g:addNode(0, 0, "source").id)
  local t = unbound(g, g:addNode(3, 0, "sink").id)
  local a = unbound(g, g:addNode(1, 1, "relay").id)
  local b = unbound(g, g:addNode(1, -1, "relay").id)
  g:addEdge(s, a, 3); g:addEdge(a, t, 3)
  g:addEdge(s, b, 3); g:addEdge(b, t, 3)
  local f, cut = g:maxflow()
  check("two disjoint paths", f, 6)
  check("cut needs both", #cut, 2)
end

--------------------------------------------------------------------------------
print("diamond with cross link")
do
  -- S-A 3, S-B 2, A-T 2, B-T 3, A-B 1. Min cut {S}|rest = 5; also {S,A,B}|{T} = 5.
  local g = Graph.new()
  local s = unbound(g, g:addNode(0, 0, "source").id)
  local a = unbound(g, g:addNode(1, 1, "relay").id)
  local b = unbound(g, g:addNode(1, -1, "relay").id)
  local t = unbound(g, g:addNode(2, 0, "sink").id)
  g:addEdge(s, a, 3); g:addEdge(s, b, 2)
  g:addEdge(a, t, 2); g:addEdge(b, t, 3)
  g:addEdge(a, b, 1)
  local f = g:maxflow()
  check("hand-computed max flow", f, 5)
end

--------------------------------------------------------------------------------
print("undirected edges carry either direction")
do
  -- Built 'backwards': every edge added as (later, earlier). Flow must not care.
  local g = Graph.new()
  local s = unbound(g, g:addNode(0, 0, "source").id)
  local r = unbound(g, g:addNode(1, 0, "relay").id)
  local t = unbound(g, g:addNode(2, 0, "sink").id)
  g:addEdge(r, s, 5)
  g:addEdge(t, r, 5)
  check("orientation independent", (g:maxflow()), 5)
end

--------------------------------------------------------------------------------
print("multiple terminals share one budget")
do
  local g = Graph.new()
  local s = unbound(g, g:addNode(0, 0, "source").id)
  local r = unbound(g, g:addNode(1, 0, "relay").id)
  local t1 = unbound(g, g:addNode(2, 1, "sink").id)
  local t2 = unbound(g, g:addNode(2, -1, "sink").id)
  g:addEdge(s, r, 4)
  g:addEdge(r, t1, 3)
  g:addEdge(r, t2, 3)
  check("shared trunk limits total", (g:maxflow()), 4)
end

--------------------------------------------------------------------------------
print("disconnected graph carries nothing")
do
  local g = Graph.new()
  local s = unbound(g, g:addNode(0, 0, "source").id)
  local t = unbound(g, g:addNode(5, 0, "sink").id)
  local f, cut = g:maxflow()
  check("no path, no flow", f, 0)
  check("empty cut", #cut, 0)
  check("two components", select(2, g:components()), 2)
  check("not connected", g:isConnected(), false)
end

--------------------------------------------------------------------------------
print("destroying a node severs its links")
do
  local g = Graph.new()
  local s = unbound(g, g:addNode(0, 0, "source").id)
  local r = unbound(g, g:addNode(1, 0, "relay").id)
  local t = unbound(g, g:addNode(2, 0, "sink").id)
  g:addEdge(s, r, 5); g:addEdge(r, t, 5)
  check("flows before", (g:maxflow()), 5)
  g:killNode(r)
  check("flows after", (g:maxflow()), 0)
  check("degree of source drops", g:degree(s), 0)
  check("order drops", g:stats().order, 2)
end

--------------------------------------------------------------------------------
print("ports constrain degree")
do
  local g = Graph.new()
  local c = g:addNode(0, 0, "conduit").id   -- 2 ports
  local a = unbound(g, g:addNode(1, 0, "relay").id)
  local b = unbound(g, g:addNode(0, 1, "relay").id)
  local d = unbound(g, g:addNode(-1, 0, "relay").id)
  check("link 1", g:addEdge(c, a, 1) ~= nil, true)
  check("link 2", g:addEdge(c, b, 1) ~= nil, true)
  check("link 3 refused", g:addEdge(c, d, 1), nil)
  check("degree stops at ports", g:degree(c), 2)
  check("no self loops", g:addEdge(a, a, 1), nil)
  check("no duplicate links", g:addEdge(c, a, 1), nil)
end

--------------------------------------------------------------------------------
print("articulation points")
do
  -- Path S-A-B-T: A and B are both cut vertices.
  local g = Graph.new()
  local s = unbound(g, g:addNode(0, 0, "source").id)
  local a = unbound(g, g:addNode(1, 0, "relay").id)
  local b = unbound(g, g:addNode(2, 0, "relay").id)
  local t = unbound(g, g:addNode(3, 0, "sink").id)
  g:addEdge(s, a, 1); g:addEdge(a, b, 1); g:addEdge(b, t, 1)
  local ap = g:articulationPoints()
  check("path has 2 cut vertices", #ap, 2)
  check("first is A", ap[1], a)
  check("second is B", ap[2], b)

  -- Closing the cycle removes every cut vertex: the graph is 2-connected.
  g:addEdge(t, s, 1)
  check("cycle has none", #g:articulationPoints(), 0)
end

--------------------------------------------------------------------------------
print("hop distances")
do
  local g = Graph.new()
  local s = unbound(g, g:addNode(0, 0, "source").id)
  local a = unbound(g, g:addNode(1, 0, "relay").id)
  local b = unbound(g, g:addNode(2, 0, "relay").id)
  g:addEdge(s, a, 1); g:addEdge(a, b, 1)
  local d = g:distancesFrom({ s })
  check("d(s)", d[s], 0)
  check("d(a)", d[a], 1)
  check("d(b)", d[b], 2)
end

--------------------------------------------------------------------------------
print(string.format("\n%d passed, %d failed", pass, fail))
os.exit(fail == 0 and 0 or 1)
