-- bot.lua -- a reference player, shared by the sim and the tuner.
-- It plays the strategy the game is meant to teach: reach every terminal,
-- serve demand, then widen the cut so a strike costs a fraction rather than
-- everything. Tuning against a naive bot would tune the game for bad play.
local M = {}

function M.make(Game)
  local function dist(a, b) return math.sqrt((a.x - b.x) ^ 2 + (a.y - b.y) ^ 2) end

  local function connected(run, id)
    local l = run.g:components()
    return l[id] ~= nil and l[id] == l[run.source.id]
  end

  -- Nearest already-connected node with a spare port, to grow from the frontier
  -- rather than always from the source.
  local function anchorFor(run, target)
    local l = run.g:components()
    local home = l[run.source.id]
    local best, bestD
    for _, n in ipairs(run.g:aliveNodes()) do
      if l[n.id] == home and run.g:freePorts(n.id) > 0 then
        local d = dist(n, target)
        if not bestD or d < bestD then best, bestD = n, d end
      end
    end
    return best, bestD
  end

  -- Plan a whole route before spending anything. Two traps live here: the
  -- sideways bow that keeps routes disjoint also lengthens each hop, which can
  -- silently exceed link range; and a half-built route is pure waste, because
  -- orphaned relays cost energy and carry no flow.
  local function planRoute(run, anchor, sink, lane)
    local D = dist(anchor, sink)
    if D < 1 then return nil end
    local range = Game.balance.maxLinkRange
    local ux, uy = (sink.x - anchor.x) / D, (sink.y - anchor.y) / D
    local px, py = -uy, ux
    local sign = (lane % 2 == 0) and 1 or -1
    local amp = math.ceil(lane / 2) * 95 * sign

    for hops = math.max(1, math.ceil(D / (range * 0.78))), 14 do
      local pts, ok = { { x = anchor.x, y = anchor.y } }, true
      for i = 1, hops - 1 do
        local t = i / hops
        local bow = math.sin(math.pi * t) * amp
        local x = anchor.x + ux * D * t + px * bow
        local y = anchor.y + uy * D * t + py * bow
        -- Nudge along the bow direction until the spot is legal, also keeping
        -- clear of the points planned so far in this same route.
        local placed
        for nudge = 0, 6 do
          local nx = x + px * nudge * 22 * sign
          local ny = y + py * nudge * 22 * sign
          local clash = run:placementError(nx, ny) ~= nil
          if not clash then
            for _, q in ipairs(pts) do
              if dist({ x = nx, y = ny }, q) < Game.balance.minNodeSpacing then clash = true; break end
            end
          end
          if not clash then placed = { x = nx, y = ny }; break end
        end
        if not placed then ok = false; break end
        pts[#pts + 1] = placed
      end
      if ok then
        pts[#pts + 1] = { x = sink.x, y = sink.y }
        -- Every hop must be inside link range, bow included.
        local fits = true
        for i = 1, #pts - 1 do
          if dist(pts[i], pts[i + 1]) > range then fits = false; break end
        end
        if fits then return pts end
      end
    end
    return nil
  end

  local function routeCost(run, pts)
    local cost = 0
    local relays = #pts - 2
    for i = 0, relays - 1 do
      cost = cost + math.ceil(14 * (Game.balance.nodeCostGrowth ^ (run.builtNodes + i)))
    end
    for i = 1, #pts - 1 do
      local d = dist(pts[i], pts[i + 1])
      cost = cost + math.ceil(Game.balance.linkCostBase + Game.balance.linkCostPerUnit * d)
    end
    return cost
  end

  local function buildRoute(run, sink, lane, fromSource)
    local anchor
    if fromSource then
      anchor = run.g.nodes[run.source.id]
      if run.g:freePorts(anchor.id) < 1 then return false end
    else
      anchor = anchorFor(run, sink)
    end
    if not anchor or run.g:freePorts(sink.id) < 1 then return false end

    local pts = planRoute(run, anchor, sink, lane)
    if not pts then return false end
    -- Refuse to start what cannot be finished.
    if routeCost(run, pts) > run.energy then return false end

    local prev = anchor.id
    for i = 2, #pts - 1 do
      local n = run:buildNode(pts[i].x, pts[i].y, "relay")
      if not n then return false end
      if not run:buildLink(prev, n.id) then return false end
      prev = n.id
    end
    return run:buildLink(prev, sink.id) ~= nil
  end

  local function cheapestReinforcement(run)
    local best, bestCost, bestKind
    local cut = (run.flow < run.demand) and (run.deliveryCut or run.cut) or run.cut
    for _, c in ipairs(cut) do
      if c.kind == "edge" then
        local k = run:capCost(c.id)
        if not bestCost or k < bestCost then best, bestCost, bestKind = c.id, k, "edge" end
      else
        local k = run:tpCost(c.id)
        if k and (not bestCost or k < bestCost) then best, bestCost, bestKind = c.id, k, "node" end
      end
    end
    return best, bestCost, bestKind
  end

  local function raiseFlowTo(run, target, budgetFloor)
    for _ = 1, 500 do
      if run.flow >= target then return true end
      local id, cost, kind = cheapestReinforcement(run)
      if not id or cost > run.energy - (budgetFloor or 0) then return false end
      local ok = (kind == "edge") and run:upgradeLink(id) or run:upgradeNode(id)
      if not ok then return false end
    end
    return run.flow >= target
  end

  -- One full build phase.
  return function(run)
    local strikes = Game.strikesFor(run.wave)

    -- 0. Clear links into dead sub-networks, which otherwise hold ports hostage
    --    on exactly the terminals that need reconnecting.
    local l = run.g:components()
    local home = l[run.source.id]
    for _, sk in ipairs(run.g:nodesOfKind("sink")) do
      if l[sk.id] ~= home and run.g:freePorts(sk.id) < 1 then
        for _, ei in ipairs(run.g.adj[sk.id]) do
          if run.g.edges[ei].alive then run:demolishLink(ei); break end
        end
      end
    end

    -- 1. Every terminal must be reachable: each carries its own demand.
    for _ = 1, 16 do
      local orphan
      for _, s in ipairs(run.g:nodesOfKind("sink")) do
        if not connected(run, s.id) then orphan = s; break end
      end
      if not orphan then break end
      local built = false
      for lane = 1, 8 do
        if run.g:freePorts(orphan.id) < 1 then break end
        if buildRoute(run, orphan, lane, false) then built = true; break end
      end
      if not built then break end
    end

    -- 2. Serve this wave's demand first. Survival beats insurance.
    raiseFlowTo(run, run.demand, 0)

    -- 3. Insurance: widen the cut so one strike is a fraction, not a collapse.
    local want = strikes + 2
    for _ = 1, 12 do
      if #run.cut >= want then break end
      local target
      for _, s in ipairs(run.g:nodesOfKind("sink")) do
        if run.g:freePorts(s.id) > 0 then target = s; break end
      end
      if not target then break end
      -- From the source, not from the frontier: a route that branches off the
      -- existing path shares its bottleneck and adds no redundancy at all.
      local made = false
      for lane = 1, 8 do
        if buildRoute(run, target, lane, true) then made = true; break end
      end
      if not made then break end
    end

    -- 4. Headroom for what the strike will take, while keeping a reserve to
    --    rebuild with. Spending to zero means one severed link ends the run.
    raiseFlowTo(run, run.demand + strikes + 1, 45)
  end
end

return M
