-- rounds_bot.lua -- a plain, careful player for Rounds mode.
--
-- It answers the one question the numbers in data/rounds.lua cannot answer on
-- their own: can forty rounds be won by someone who plays sensibly and looks
-- no further ahead than the preview? The tests run it and the screenshot
-- harness uses it to reach a mid-game map. It plays through the same City
-- calls the buttons do and knows nothing the player does not.
local City = require("city")
local N = require("network_builder")
local D = City.ROUNDS

local Bot = {}

local function dist(a, b) return math.sqrt((a.x - b.x) ^ 2 + (a.y - b.y) ^ 2) end

local function hubOf(c, d)
  local best, bd
  for _, h in ipairs(c.g:nodesOfKind("exchange")) do
    if c:districtAt(h.x, h.y) == d then
      local e = dist(h, { x = d.x + d.w / 2, y = d.y + d.h / 2 })
      if not bd or e < bd then best, bd = h, e end
    end
  end
  return best
end

local function watered(c, id)
  for other in pairs(N.component(c, id, "water")) do
    local n = c.g.nodes[other]
    if n.kind == "source" then return true end
  end
  return false
end

-- The untaken spring nearest to a point, on ground the company holds.
local function spring(c, near)
  local best, bd
  for _, dep in ipairs(c.deposits) do
    local d = c:districtAt(dep.x, dep.y)
    if dep.commodity == "water" and not dep.taken and d and d.owned and not c:sourceError("water", dep.x, dep.y) then
      local e = dist(dep, near)
      if not bd or e < bd then best, bd = dep, e end
    end
  end
  return best
end

-- A run of mains from one building to another, with T splits between where
-- one main cannot reach. Large, because a hub takes nothing smaller.
local function join(c, from, to)
  if c:pipeBetween(from.id, to.id, "water") then return true end
  if c:layPipe(from.id, to.id, "water", "large") then return true end
  return N.chain(c, from, to, "water", "large", "large")
end

local function newWell(c, near)
  local dep = spring(c, near)
  if not dep then return nil end
  return c:buySource("water", dep.x, dep.y)
end

local function wells(c)
  local t = {}
  for _, n in ipairs(c.g:nodesOfKind("source")) do if n.commodity == "water" then t[#t + 1] = n end end
  return t
end

-- Water for the round with a quarter to spare: deepen before drilling.
local function supply(c, want)
  for _ = 1, 20 do
    if c:roundSupply() >= want then return end
    local best, bc
    for _, w in ipairs(wells(c)) do
      local cost = c:sourceUpgradeCost(w)
      if cost and cost <= c.money and (not bc or cost < bc) then best, bc = w, cost end
    end
    local dep = spring(c, wells(c)[1] or c.districts[6])
    local drill = dep and c:sourceCost("water", dep.x, dep.y)
    if best and (not drill or bc <= drill) then
      if not c:upgradeSource(best.id) then return end
    elseif dep and drill <= c.money then
      local w = c:buySource("water", dep.x, dep.y)
      if not w then return end
      local anchor, ad
      for _, n in ipairs(c.g:aliveNodes()) do
        if n.id ~= w.id and (n.kind == "exchange" or n.kind == "junction" or n.kind == "manifold" or n.kind == "source") then
          if not ad or dist(n, w) < ad then anchor, ad = n, dist(n, w) end
        end
      end
      if anchor then join(c, w, anchor) end
    else
      return
    end
  end
end

-- Fake houses standing on every hub, each wanting what the preview says its
-- zone will want, solved the way a round is. Whatever holds a hub back gets
-- the money next. The fakes are cut off the graph afterwards, the same way
-- the houses of a real round are.
local function stress(c, plan)
  for _ = 1, 40 do
    local mark = #c.g.nodes
    local hubs = {}
    for _, d in ipairs(c:zones()) do
      local h = hubOf(c, d)
      local want = (plan.byZone[d.id] or {}).demand
      if h and want then
        local n = c.g:addNode(h.x + 1, h.y + 1, "client")
        n.clientType, n.commodity, n.demand, n.rate = "house", "water", math.ceil(want * 1.2) + 2, 6
        n.prospect = false
        hubs[#hubs + 1] = h
      end
    end
    c:refresh()
    local verdicts = {}
    for _, h in ipairs(hubs) do
      local v, e = c:hubConstraint(h)
      if v then verdicts[#verdicts + 1] = { v = v, e = e, h = h } end
    end
    for id = #c.g.nodes, mark + 1, -1 do c.g.nodes[id] = nil; c.g.adj[id] = nil end
    c:refresh()
    if #verdicts == 0 then return end
    local acted = false
    for _, it in ipairs(verdicts) do
      if it.v == "main" and it.e and c.g.edges[it.e.id].alive then
        local size = c:biggerSize(c.g.edges[it.e.id])
        if size and c:replacePipe(it.e.id, size) then acted = true end
      elseif it.v == "repair" and it.e then
        if c:repairPipe(it.e.id) then acted = true end
      elseif it.v == "hub" then
        if c:upgradeLevel(it.h.id) then acted = true end
      elseif it.v == "output" then
        -- Water on this hub's own network: deepen a well on it, or drill a
        -- new spring and join it straight to the hub.
        local seen = N.component(c, it.h.id, "water")
        local best, bc
        for id in pairs(seen) do
          local w = c.g.nodes[id]
          if w.kind == "source" and w.commodity == "water" then
            local cost = c:sourceUpgradeCost(w)
            if cost and cost <= c.money and (not bc or cost < bc) then best, bc = w, cost end
          end
        end
        if best and c:upgradeSource(best.id) then
          acted = true
        else
          local w = newWell(c, it.h)
          if w and join(c, w, it.h) then acted = true end
        end
      elseif it.v == "unconnected" then
        local w = newWell(c, it.h)
        if w and join(c, w, it.h) then acted = true end
      end
    end
    if not acted then return end
  end
end

function Bot.build(c)
  local rs = c.rounds
  if rs.phase ~= "build" then return end
  c:repairAll()
  local plan = c:roundPlan()
  local drought = plan.shocks.drought and D.SHOCKS.drought.output or 1

  for _, d in ipairs(c:zones()) do
    local h = hubOf(c, d)
    if not h then
      h = N.place(c, "exchange", d.x + d.w / 2, d.y + d.h / 2, nil, nil, 200)
    end
    if h and not watered(c, h.id) then
      local anchor, ad
      for _, n in ipairs(c.g:aliveNodes()) do
        if n.id ~= h.id and (n.kind == "exchange" or n.kind == "source") and watered(c, n.id) then
          if not ad or dist(n, h) < ad then anchor, ad = n, dist(n, h) end
        end
      end
      if not (anchor and ad < 1500 and join(c, anchor, h)) then
        local w = newWell(c, h)
        if w then join(c, w, h) end
      end
    end
  end

  supply(c, math.ceil(plan.demand * 1.25 / drought) + 4)
  stress(c, plan)

  -- Reach: level a hub until its zone is covered, while money allows and
  -- after keeping back what the next zone will cost to open.
  local nextZone = c:nextZone()
  local reserve = (nextZone and nextZone.zoneOpens - rs.round <= 3) and 2200 or 0
  for _, d in ipairs(c:zones()) do
    local h = hubOf(c, d)
    while h and c:zoneCoverage(d) < 0.999 and not c:levelError(h.id)
          and c.money - (c:levelNext(h.id) or {}).cost >= reserve do
      if not c:upgradeLevel(h.id) then break end
    end
  end

  -- A burst is announced, so every hub hanging off one main gets a second.
  if plan.shocks.burst then
    for _, d in ipairs(c:zones()) do
      local h = hubOf(c, d)
      if h then
        local feeds = 0
        for _, e in ipairs(c.g:edgesAt(h.id)) do if e.commodity == "water" then feeds = feeds + 1 end end
        if feeds < 2 then
          local other, od
          for _, n in ipairs(c.g:aliveNodes()) do
            if n.id ~= h.id and (n.kind == "exchange" or n.kind == "source") and not c:pipeBetween(n.id, h.id, "water")
               and watered(c, n.id) and (not od or dist(n, h) < od) then other, od = n, dist(n, h) end
          end
          if other then join(c, other, h) end
        end
      end
    end
  end
end

function Bot.turn(c)
  Bot.build(c)
  local plan = c:startRound()
  if not plan then return nil end
  while c.rounds.phase == "round" and c:pendingHouses() > 0 do c:roundArrive() end
  if c.rounds.phase == "lost" then return nil end
  return c:finishRound()
end

return Bot
