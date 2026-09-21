-- rounds_bot.lua -- a plain, careful player for Rounds mode.
--
-- It exists to answer one question the numbers in data/rounds.lua cannot
-- answer on their own: can forty rounds be won by someone who plays sensibly
-- and never looks ahead further than the preview? The tests run it, and the
-- screenshot harness uses it to reach a mid-game map. It plays through the
-- same public calls the screen does and knows nothing the player does not.
local Rounds = require("rounds")
local D = Rounds.D

local Bot = {}

local function dist(a, b) return math.sqrt((a.x - b.x) ^ 2 + (a.y - b.y) ^ 2) end

-- Everything reachable from a building over mains.
local function component(run, start)
  local seen, queue = { [start.id] = true }, { start.id }
  while #queue > 0 do
    local id = table.remove(queue)
    for _, p in ipairs(run.pipes) do
      local other = (p.a == id and p.b) or (p.b == id and p.a)
      if other and not seen[other] then seen[other] = true; queue[#queue + 1] = other end
    end
  end
  return seen
end

local function hasSource(run, seen)
  for _, b in ipairs(run.buildings) do
    if seen[b.id] and b.kind ~= "junction" then return true end
  end
end

-- Try a spot, then a few spots around it, because rocks and the river move
-- the right place a little more often than not.
local function place(run, kind, x, y)
  for ring = 0, 4 do
    for k = 0, (ring == 0 and 0 or 7) do
      local a = k / 8 * math.pi * 2
      local b = run:build(kind, x + math.cos(a) * ring * 30, y + math.sin(a) * ring * 30)
      if b then return b end
    end
  end
end

-- A main from a to b, putting junctions in between where one main cannot reach.
local function chain(run, a, b, size, depth)
  depth = depth or 0
  if depth > 8 then return nil end
  if run:pipeBetween(a.id, b.id) then return true end
  local reach = D.PIPES[size].reach
  local d = dist(a, b)
  if d <= reach then
    local p = run:layPipe(a.id, b.id, size)
    if p then return p end
    -- Out of ports or blocked: step through a junction beside the target.
  end
  local step = math.min(reach * 0.9, d * 0.5)
  local mid = place(run, "junction", a.x + (b.x - a.x) * step / d, a.y + (b.y - a.y) * step / d)
  if not mid then return nil end
  if not run:layPipe(a.id, mid.id, size) then run:sell(mid.id); return nil end
  return chain(run, mid, b, size, depth + 1)
end

local function hubOf(run, z)
  local best, bd
  for _, b in ipairs(run.buildings) do
    if b.kind == "junction" and b.zone == z.index then
      local d = dist(b, z)
      if not bd or d < bd then best, bd = b, d end
    end
  end
  return best
end

local function zoneDemand(plan, z)
  local total = 0
  for kind, n in pairs(plan.byZone[z.index] or {}) do
    total = total + n * math.ceil(D.HOUSES[kind].demand * (plan.shocks.heatwave and D.SHOCKS.heatwave.factor or 1))
  end
  return total
end

local function sizeFor(flow)
  for i, spec in ipairs(D.PIPES) do if spec.cap >= flow then return i end end
  return #D.PIPES
end

-- Water enough for the round with a quarter to spare: deepen what exists
-- before drilling somewhere new, because a level is cheaper than a well.
local function ensureSupply(run, want)
  local guard = 0
  while run:supply() < want and guard < 20 do
    guard = guard + 1
    local best
    for _, b in ipairs(run.buildings) do
      if b.kind == "well" and not run:upgradeError(b) then
        if not best or b.level < best.level then best = b end
      end
    end
    if best then
      run:upgrade(best.id)
    else
      -- A new well on the nearest free spring to the network, joined to the
      -- nearest thing already built.
      local choice, cd, anchor
      for _, s in ipairs(run.springs) do
        if not run:springTaken(s) then
          for _, b in ipairs(run.buildings) do
            local d = dist(s, b)
            if not cd or d < cd then choice, cd, anchor = s, d, b end
          end
        end
      end
      if not choice or run.money < D.BUILDINGS.well.cost[1] + 80 then return end
      local w = run:build("well", choice.x, choice.y)
      if not w then return end
      if not chain(run, w, anchor, 3) then run:sell(w.id); return end
    end
  end
end

function Bot.build(run)
  if run.phase ~= "build" then return end
  local plan = run:plan()
  local total = plan.demand
  local drought = plan.shocks.drought and D.SHOCKS.drought.factor or 1

  -- Every open zone gets a hub at its heart, fed from the nearest water.
  for _, z in ipairs(run:openZones()) do
    local hub = hubOf(run, z)
    if not hub then
      hub = place(run, "junction", z.x, z.y)
      if hub then hub.zone = z.index end
    end
    if hub then
      local seen = component(run, hub)
      if not hasSource(run, seen) then
        local target, td
        for _, b in ipairs(run.buildings) do
          if not seen[b.id] and (b.kind ~= "junction" or hasSource(run, component(run, b))) then
            local d = dist(b, hub)
            if not td or d < td then target, td = b, d end
          end
        end
        if not target or td > 900 then
          local spring, sd
          for _, s in ipairs(run.springs) do
            if not run:springTaken(s) and (not sd or dist(s, hub) < sd) then spring, sd = s, dist(s, hub) end
          end
          if spring then target = run:build("well", spring.x, spring.y) end
        end
        if target then chain(run, target, hub, 3) end
      end
    end
  end

  -- Supply before coverage: a covered house with no water is still dry.
  ensureSupply(run, math.ceil(total * 1.25 / drought) + 4)

  -- Every hub carries its zone's round, and so does every main feeding it.
  for _, z in ipairs(run:openZones()) do
    local hub = hubOf(run, z)
    if hub then
      local want = zoneDemand(plan, z) * 1.3 + 3
      while run:stat(hub, "throughput") < want and not run:upgradeError(hub) do run:upgrade(hub.id) end
      for _, p in ipairs(run.pipes) do
        if p.a == hub.id or p.b == hub.id then
          while D.PIPES[p.size].cap < want / 1.4 and not run:widenError(p) do run:widen(p.id) end
        end
      end
      -- Rings until the zone is nearly all reachable: widen the hub's ring
      -- first, then add satellites around it.
      local guard = 0
      while run:coverage(z) < 0.999 and guard < 14 do
        guard = guard + 1
        if hub.level < 3 and not run:upgradeError(hub) then
          run:upgrade(hub.id)
        else
          local placedOne
          for k = 0, 5 do
            local a = k / 6 * math.pi * 2 + 0.3
            local x, y = z.x + math.cos(a) * z.r * 0.68, z.y + math.sin(a) * z.r * 0.68
            if #run:coveredBy(x, y) == 0 or run:coverage(z) < 0.999 then
              local near = false
              for _, b in ipairs(run.buildings) do if dist(b, { x = x, y = y }) < 90 then near = true end end
              if not near then
                local s = place(run, "junction", x, y)
                if s then
                  if run:layPipe(hub.id, s.id, sizeFor(want / 3)) then placedOne = true; break end
                  run:sell(s.id)
                end
              end
            end
          end
          if not placedOne then break end
        end
      end
    end
  end

  -- A burst is announced, so every hub that hangs off a single main gets a
  -- second one to some other watered building. Checked by taking each main out
  -- in turn and asking whether the hub still reaches water.
  if plan.shocks.burst then
    for _, z in ipairs(run:openZones()) do
      local hub = hubOf(run, z)
      for _ = 1, 2 do
        local weak = false
        for _, p in ipairs(run.pipes) do
          run.burst = { [p.id] = true }
          if not run:watered({ hub and hub.id }) then weak = true end
          run.burst = nil
          if weak then break end
        end
        if not (hub and weak) then break end
        local best, bd
        for _, b in ipairs(run.buildings) do
          if b ~= hub and not run:pipeBetween(b.id, hub.id) and run:watered({ b.id }) then
            local d = dist(b, hub)
            if d > 60 and (not bd or d < bd) then best, bd = b, d end
          end
        end
        if not best then break end
        local size = 1
        for _, p in ipairs(run.pipes) do
          if p.a == hub.id or p.b == hub.id then size = math.max(size, p.size) end
        end
        if not chain(run, best, hub, size) then break end
      end
    end
  end

  -- The preview's demand, put on each hub at once, run through the solver.
  -- Whatever the minimum cut lands on is what gets money next, until the
  -- network carries it all or the money runs out.
  local fakes = {}
  for _, z in ipairs(run:openZones()) do
    local hub = hubOf(run, z)
    if hub then
      fakes[#fakes + 1] = { x = hub.x, y = hub.y, served = true, cover = { hub.id },
        demand = math.ceil(zoneDemand(plan, z) * 1.2) + 2 }
    end
  end
  for _ = 1, 40 do
    local want = 0
    for _, f in ipairs(fakes) do want = want + f.demand end
    run.houses, run.shocks = fakes, plan.shocks
    local result = run:solve()
    run.houses, run.shocks = nil, nil
    if result.flow >= want - 1e-6 then break end
    local acted = false
    for id in pairs(result.cutPipes) do
      local p = run:pipeById(id)
      if p and not run:widenError(p) then run:widen(id); acted = true end
    end
    for id in pairs(result.cutBuildings) do
      local b = run:byId(id)
      if b and not run:upgradeError(b) then run:upgrade(id); acted = true end
    end
    if not acted then
      -- No main and no junction is the limit, so the water this hub can
      -- reach is spent: deepen a well on its own network, or drill a new
      -- spring and join it on.
      for _, f in ipairs(fakes) do
        if (result.houseServed[f] or 0) < f.demand and not acted then
          local hub = run:byId(f.cover[1])
          local seen = component(run, hub)
          local best
          for _, b in ipairs(run.buildings) do
            if seen[b.id] and b.kind == "well" and not run:upgradeError(b) then
              if not best or b.level < best.level then best = b end
            end
          end
          if best then
            acted = run:upgrade(best.id) and true
          else
            local spring, sd
            for _, sp in ipairs(run.springs) do
              if not run:springTaken(sp) and (not sd or dist(sp, hub) < sd) then spring, sd = sp, dist(sp, hub) end
            end
            local w = spring and run:build("well", spring.x, spring.y)
            if w then
              if chain(run, w, hub, 3) then acted = true else run:sell(w.id) end
            end
          end
        end
      end
    end
    if not acted then break end
  end

  -- What the last round showed was full, widened or raised now.
  for id in pairs(run.lastCut or {}) do
    local p = run:pipeById(id)
    if p and not run:widenError(p) then run:widen(p.id) end
  end
  for id in pairs(run.lastCutBuildings or {}) do
    local b = run:byId(id)
    if b and not run:upgradeError(b) then run:upgrade(b.id) end
  end
  for id, f in pairs(run.lastFlow or {}) do
    local p = run:pipeById(id)
    if p and math.abs(f) > D.PIPES[p.size].cap * 0.8 and not run:widenError(p) then run:widen(p.id) end
  end
end

-- One round with a build before it, remembering what the round strained.
function Bot.turn(run)
  Bot.build(run)
  local ok = run:startRound()
  if not ok then return nil end
  local cut, cutB = {}, {}
  while run.phase == "round" and run:pendingHouses() > 0 do
    local h = run:arrive()
    if h and h.dry then
      for id in pairs(h.cutPipes or {}) do cut[id] = true end
      for id in pairs(h.cutBuildings or {}) do cutB[id] = true end
    end
  end
  local flow = run.lastSolve and run.lastSolve.pipeFlow or {}
  if run.phase == "lost" then return nil end
  local result = run:finishRound()
  run.lastCut, run.lastCutBuildings, run.lastFlow = cut, cutB, flow
  return result
end

return Bot
