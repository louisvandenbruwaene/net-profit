-- solver.lua -- a reference builder.
--
-- Used by the generator to prove a contract is solvable and to price its par,
-- and available in game as a hint. It plays the strategy the puzzle is about:
-- r vertex-disjoint routes per terminal, capacity split across them.
--
-- The arithmetic it is built on: with r disjoint routes of capacity c each and
-- a threat that removes k of them, delivery after the strike is (r-k)*c, so
-- c = ceil(D / (r-k)). Total capacity bought is r*ceil(D/(r-k)), which falls as
-- r grows while structural cost rises. There is a real optimum in between, and
-- finding it is the puzzle, so the solver simply tries every r and keeps the
-- cheapest that works.
local C = require("contract")

local S = {}

-- A scratch copy of a spec with an unlimited budget, for pricing a solution.
local function scratchSpec(spec)
  local t = {}
  for k, v in pairs(spec) do t[k] = v end
  t.budget = 1e9
  return t
end

local function dist(ax, ay, bx, by)
  return math.sqrt((ax - bx) ^ 2 + (ay - by) ^ 2)
end

-- Lay one bowed chain of relays from `fromId` to `toId`. Returns the edge ids
-- it created, or nil (having undone nothing: callers work on scratch copies).
local function layRoute(ct, fromId, toId, lane)
  local a, b = ct.g.nodes[fromId], ct.g.nodes[toId]
  local D = dist(a.x, a.y, b.x, b.y)
  if D < 1 then return nil end

  local ux, uy = (b.x - a.x) / D, (b.y - a.y) / D
  local px, py = -uy, ux
  local sign = (lane % 2 == 0) and 1 or -1
  local amp = math.ceil(lane / 2) * 88 * sign

  local range = C.maxLinkRange
  for hops = math.max(1, math.ceil(D / (range * 0.8))), 12 do
    local pts = { { x = a.x, y = a.y, id = fromId } }
    local ok = true
    for i = 1, hops - 1 do
      local t = i / hops
      local bow = math.sin(math.pi * t) * amp
      local bx = a.x + ux * D * t + px * bow
      local by = a.y + uy * D * t + py * bow
      local placed
      for nudge = 0, 7 do
        local nx = bx + px * nudge * 26 * sign
        local ny = by + py * nudge * 26 * sign
        if not ct:placementError(nx, ny) then placed = { x = nx, y = ny }; break end
      end
      if not placed then ok = false; break end
      pts[#pts + 1] = placed
    end
    if ok then
      pts[#pts + 1] = { x = b.x, y = b.y, id = toId }
      -- Every hop must be in range and clear of blocked ground.
      local fits = true
      for i = 1, #pts - 1 do
        local p, q = pts[i], pts[i + 1]
        if dist(p.x, p.y, q.x, q.y) > range or ct:crossesObstacle(p.x, p.y, q.x, q.y) then
          fits = false; break
        end
      end
      if fits then
        -- Commit it.
        local edges = {}
        local prev = fromId
        for i = 2, #pts - 1 do
          local n = ct:buildNode(pts[i].x, pts[i].y, "relay")
          if not n then return nil end
          local e = ct:buildLink(prev, n.id)
          if not e then return nil end
          edges[#edges + 1] = e.id
          prev = n.id
        end
        local e = ct:buildLink(prev, toId)
        if not e then return nil end
        edges[#edges + 1] = e.id
        return edges
      end
    end
  end
  return nil
end

-- Build a full solution into `ct` using r routes per terminal.
-- Returns true if every demand survives the threat.
local function attempt(ct, r)
  ct.bulk = true            -- evaluate once at the end, not on every piece
  local k = ct.threat.count
  local survivors = math.max(1, r - k)

  for _, term in ipairs(ct.terminals) do
    local need = math.ceil(term.demand / survivors)
    local built = 0
    for lane = 1, r + 4 do
      if built >= r then break end
      if ct.g:freePorts(term.id) < 1 or ct.g:freePorts(ct.source.id) < 1 then break end
      local edges = layRoute(ct, ct.source.id, term.id, lane)
      if edges then
        built = built + 1
        for _, eid in ipairs(edges) do
          for _ = 2, need do
            if not ct:upgradeLink(eid) then ct.bulk = false; return false end
          end
        end
      end
    end
    if built == 0 then ct.bulk = false; return false end
  end
  ct.bulk = false
  ct:refresh()
  return ct:isSolved()
end

-- Cheapest r that works. Returns cost and the winning r, or nil.
function S.solve(spec, maxR)
  local best, bestR
  local k = (spec.threat and spec.threat.count) or 1
  for r = k + 1, (maxR or k + 4) do
    local scratch = C.new(scratchSpec(spec))
    if attempt(scratch, r) then
      if not best or scratch.spent < best then best, bestR = scratch.spent, r end
    end
  end
  return best, bestR
end

-- Build a solution directly into the given contract. Finds the cheapest r on
-- scratch copies first, then lays that solution into the live site, so the
-- player's own contract ends up holding a real, committable network.
function S.autoBuild(ct)
  local cost, r = S.solve(ct.spec)
  if not r then return false end
  local okBuild = attempt(ct, r)
  return okBuild and ct:isSolved()
end

return S
