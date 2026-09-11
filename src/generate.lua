-- generate.lua -- procedural contracts that are guaranteed solvable.
--
-- Every map is handed to the reference solver before the player ever sees it.
-- If the solver cannot finish it, the map is discarded; the cost of the solution
-- it does find becomes par, and the budget is par plus slack. This is only
-- possible because the whole game runs on exact max-flow, and it means a
-- generated puzzle never turns out to be impossible or trivially over-funded.
local Solver = require("solver")

local G = {}

G.RUN_LENGTH = 12

-- The difficulty curve. Each axis is introduced separately so the player meets
-- one new idea at a time rather than five at once.
function G.plan(index)
  -- Capped at three. Surviving a threat of k needs k+1 disjoint routes per
  -- terminal, so terminals * (k+1) routes must fit in the source's ports, and
  -- beyond three the build turns into clicking rather than thinking.
  local terminals = (index <= 2 and 1) or (index <= 5 and 2) or 3

  local demand = 2 + math.floor(index / 2)

  local threatCount = (index <= 4 and 1) or (index <= 9 and 2) or 3
  -- Node threats arrive later and recur, because surviving them needs
  -- vertex-disjoint routes rather than merely edge-disjoint ones.
  local threatKind = (index >= 6 and index % 3 == 0) and "node" or "edge"

  local obstacles = (index <= 3) and 0 or math.min(6, math.floor((index - 2) / 1.5))

  -- Slack tightens: early contracts forgive, late ones demand near-par play.
  local slack = math.max(1.10, 1.40 - index * 0.025)

  return {
    terminals = terminals,
    demand = demand,
    threat = { kind = threatKind, count = threatCount },
    obstacles = obstacles,
    slack = slack,
  }
end

-- Tools arrive one at a time, and each one is a new verb rather than a bigger
-- number: hubs buy ports, conduits buy reach. A contract is generated knowing
-- only the tools the player will actually hold for it.
function G.tools(index)
  return { relay = true, hub = index >= 3, conduit = index >= 5 }
end

function G.toolUnlockedAt(index)
  if index == 3 then return "hub" end
  if index == 5 then return "conduit" end
  return nil
end

local function rand(rng, lo, hi) return lo + rng() * (hi - lo) end

local function farEnough(x, y, list, gap)
  for _, p in ipairs(list) do
    if (p.x - x) ^ 2 + (p.y - y) ^ 2 < gap * gap then return false end
  end
  return true
end

-- One candidate map. Solvability is checked by the caller.
local function candidate(index, plan, tools, rng)
  local w = 1250 + plan.terminals * 170
  local h = 950 + plan.terminals * 60
  local bounds = { x = 0, y = 0, w = w, h = h }
  local cx, cy = w / 2, h / 2

  local spec = {
    index = index,
    bounds = bounds,
    source = { x = cx, y = cy },
    terminals = {},
    obstacles = {},
    threat = plan.threat,
    tools = tools,
  }

  local placed = { { x = cx, y = cy } }
  local baseAngle = rng() * math.pi * 2
  for i = 1, plan.terminals do
    local ok = false
    for _ = 1, 40 do
      local ang = baseAngle + (i - 1) * (math.pi * 2 / plan.terminals) + rand(rng, -0.5, 0.5)
      local r = rand(rng, 270, 300 + plan.terminals * 55)
      local x = math.max(90, math.min(w - 90, cx + math.cos(ang) * r))
      local y = math.max(90, math.min(h - 90, cy + math.sin(ang) * r * 0.8))
      if farEnough(x, y, placed, 240) then
        spec.terminals[#spec.terminals + 1] = { x = x, y = y, demand = plan.demand }
        placed[#placed + 1] = { x = x, y = y }
        ok = true
        break
      end
    end
    if not ok then return nil end
  end

  -- Obstacles must never sit on a node, and must leave a gap around one, or the
  -- map becomes unsolvable in a way the player cannot see coming.
  for _ = 1, plan.obstacles do
    for _ = 1, 40 do
      local r = rand(rng, 62, 112)
      local x = rand(rng, r + 40, w - r - 40)
      local y = rand(rng, r + 40, h - r - 40)
      if farEnough(x, y, placed, r + 130) then
        spec.obstacles[#spec.obstacles + 1] = { x = x, y = y, r = r }
        break
      end
    end
  end

  return spec
end

-- Returns a solvable spec with `budget` and `par` filled in, or nil.
function G.contract(index, tools, rng)
  local plan = G.plan(index)
  for _ = 1, 30 do
    local spec = candidate(index, plan, tools, rng)
    if spec then
      local par = Solver.solve(spec)
      if par and par > 0 then
        spec.par = par
        spec.budget = math.ceil(par * plan.slack)
        return spec
      end
    end
  end
  return nil
end

-- A whole run. Deterministic in `seed`, so a daily or shared seed is free.
function G.campaign(seed, tools)
  local state = seed or os.time()
  -- Small deterministic LCG: os.random is global state we do not want to disturb.
  local function rng()
    state = (1103515245 * state + 12345) % 2147483648
    return state / 2147483648
  end

  local list = {}
  for i = 1, G.RUN_LENGTH do
    local spec = G.contract(i, tools or G.tools(i), rng)
    if not spec then return nil, i end
    list[#list + 1] = spec
  end
  return list
end

return G
