-- The anatomy of a built network: luajit test/anatomy.lua
--
-- Not a pass/fail suite. It is a measurement, like bench_flow.lua, and it
-- answers one question the price model cannot answer on its own: does a
-- company that follows these prices actually end up with a branching tree, or
-- with a mesh that merely has wide pipes in it?
--
-- The method is Horton-Strahler ordering, which is how river networks and
-- vascular trees are measured. Every main that ends at a building is order 1.
-- Where two mains of the same order meet, the main below them is one order
-- higher. Then three ratios describe the whole tree:
--
--   R_B, the bifurcation ratio: how many order-w mains per order-(w+1) main.
--        Rivers run 3 to 5, vascular trees nearer 2 to 3.
--   R_L, the length ratio: how much longer an order-(w+1) main is. In a
--        space-filling tree West, Brown and Enquist give R_L = R_B^(1/3),
--        because a vessel that supplies n times the tissue has to reach
--        n^(1/3) times as far across it.
--   R_C, the capacity ratio: how much more a main one order down carries. With
--        flow conserved at every join this is R_B, and Murray's law is the
--        statement that the pipe sizes follow it.
--
-- Together they give the self-similar dimension D = log(R_B)/log(R_L), the
-- number that says whether the same shape repeats at every scale. R_L at or
-- below 1 means it does not: the tree has a hierarchy of capacities laid over
-- a geometry with a single length scale, which is what this game builds today
-- and why the number is printed rather than asserted.
package.path = "src/?.lua;" .. package.path
local City = require("city")
local A = require("autoplay")
A.budget = math.huge
require("data.resilience").SHOCK_CHANCE = 0

local SEEDS = { 3, 7, 11, 19, 23, 24, 29, 37, 41 }
local DAYS = tonumber(os.getenv("DAYS") or "60")

local function play(seed)
  local c = City.new({ seed = seed })
  for _ = 1, 20000 do
    if c.day > DAYS then break end
    local stop; c, _, stop = A.step(c)
    if stop then break end
  end
  return c
end

-- Strahler order for every main, walking out from the sources.
local function orders(c, commodity)
  local adj, mains = {}, {}
  for _, e in ipairs(c.g.edges) do
    if e.alive and e.commodity == commodity and not e.bulk then
      mains[#mains + 1] = e
      adj[e.a] = adj[e.a] or {}; adj[e.b] = adj[e.b] or {}
      table.insert(adj[e.a], e); table.insert(adj[e.b], e)
    end
  end
  if #mains < 6 then return nil end
  local roots = {}
  for _, n in ipairs(c.g:nodesOfKind("source")) do
    if n.alive and n.commodity == commodity and adj[n.id] then roots[#roots + 1] = n.id end
  end
  if #roots == 0 then return nil end
  -- Point every main away from the sources, so the tree has a direction.
  local seen, queue, below = {}, {}, {}
  for _, r in ipairs(roots) do seen[r] = true; queue[#queue + 1] = r end
  local head = 1
  while head <= #queue do
    local id = queue[head]; head = head + 1
    below[id] = below[id] or {}
    for _, e in ipairs(adj[id] or {}) do
      local other = (e.a == id) and e.b or e.a
      if not seen[other] then
        seen[other] = true; queue[#queue + 1] = other
        table.insert(below[id], { edge = e, to = other })
      end
    end
  end
  local ord = {}
  local function walk(id)
    local kids = below[id] or {}
    if #kids == 0 then return 0 end
    local best, count = 0, 0
    for _, k in ipairs(kids) do
      local o = math.max(1, walk(k.to))
      ord[k.edge] = o
      if o > best then best, count = o, 1 elseif o == best then count = count + 1 end
    end
    return count > 1 and best + 1 or best
  end
  for _, r in ipairs(roots) do walk(r) end
  return ord, mains
end

local function measure(c)
  local ord, mains = orders(c, "water")
  if not ord then return nil end
  local band, top = {}, 0
  for _, e in ipairs(mains) do
    local o = ord[e] or 1
    band[o] = band[o] or { n = 0, len = 0, cap = 0 }
    band[o].n = band[o].n + 1
    band[o].len = band[o].len + c:pipeLength(e)
    band[o].cap = band[o].cap + (e.capMax or e.cap or 0)
    top = math.max(top, o)
  end
  local rb, rl, rc = {}, {}, {}
  for o = 1, top - 1 do
    local lo, hi = band[o], band[o + 1]
    if lo and hi and hi.n > 0 then
      rb[#rb + 1] = lo.n / hi.n
      rl[#rl + 1] = (hi.len / hi.n) / (lo.len / lo.n)
      rc[#rc + 1] = (hi.cap / hi.n) / (lo.cap / lo.n)
    end
  end
  local function mean(t) local s = 0; for _, v in ipairs(t) do s = s + v end; return #t > 0 and s / #t or 0 end
  return { band = band, top = top, mains = #mains,
    RB = mean(rb), RL = mean(rl), RC = mean(rc) }
end

print(string.format("Network anatomy after %d days, %d seeded companies\n", DAYS, #SEEDS))
local tb, tl, tc, tn, tk = 0, 0, 0, 0, 0
for _, seed in ipairs(SEEDS) do
  local c = play(seed)
  local m = measure(c)
  if not m then
    print(string.format("seed %-3d  no network to measure", seed))
  else
    print(string.format("seed %-3d  %3d clients  %3d mains  orders 1..%d",
      seed, #c:clientList(), m.mains, m.top))
    for o = 1, m.top do
      local b = m.band[o]
      if b then
        print(string.format("           order %d  %4d mains  %6.0f m mean  %6.1f mean capacity",
          o, b.n, b.len / b.n, b.cap / b.n))
      end
    end
    print(string.format("           R_B %.2f   R_L %.2f   R_C %.2f   %s",
      m.RB, m.RL, m.RC,
      m.RL > 1 and string.format("D = %.2f", math.log(m.RB) / math.log(m.RL))
        or "D undefined: mains do not lengthen with order"))
    tb = tb + m.RB; tl = tl + m.RL; tc = tc + m.RC; tn = tn + m.mains; tk = tk + 1
  end
end
if tk > 0 then
  local RB, RL, RC = tb / tk, tl / tk, tc / tk
  print(string.format("\nMEAN over %d companies: %.0f mains   R_B %.2f   R_L %.2f   R_C %.2f",
    tk, tn / tk, RB, RL, RC))
  print(string.format("  capacity follows the branching (Murray): R_C %.2f against R_B %.2f, %.0f%% of it",
    RC, RB, RC / RB * 100))
  print(string.format("  space filling would want R_L = R_B^(1/3) = %.2f, and it is %.2f",
    RB ^ (1 / 3), RL))
  if RL <= 1.02 then
    print("  so the tree is hierarchical in capacity and flat in space: every main")
    print("  is about as long as every other, whatever it carries.")
  end
end
