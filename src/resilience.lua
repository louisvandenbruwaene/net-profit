-- Resilience: what one failure costs, and the contracts that price it.
--
-- Two halves. Shocks are things that happen to the company (a drought halves a
-- well, the ground shifts and cracks a district of mains). The N-1 check asks
-- the flow solver the question a shock makes real: if any single main or
-- structure went out tonight, how much of the daily revenue would go with it?
--
-- Nothing here draws from City:random(). That stream is shared with leaks and
-- offers, so a shock rolled from it would reshuffle every later arrival in an
-- existing save. Shocks come from a hash of the seed and the day instead.
local Graph = require("graph")
local D = require("data.resilience")

return function(City)
  City.SHOCKS, City.SECURE, City.RESILIENCE = D.SHOCKS, D.SECURE, D

  -- A number in [0,1) that depends only on the company and the two keys.
  function City:unit(a, b)
    return (self:cellSeed(a, b) - 1) / 2147483646
  end

  --------------------------------------------------------------------------
  -- Shocks
  --------------------------------------------------------------------------

  -- What a source gives while a shock is on, or nil when nothing touches it.
  function City:shockOutput(n)
    local v
    local s = self.shock
    if s and s.output and n.kind == "source" and n.commodity == s.commodity and n.output then
      v = math.max(1, math.floor(n.output * s.output))
    end
    -- A quarry on a nearly worked-out range gives only what is left of it
    -- (terrain_life.lua sets the cap before every solve).
    if n.effectiveOutputLife then return math.min(v or n.output or 0, n.effectiveOutputLife) end
    return v
  end

  local function applies(self, spec)
    if spec.ground then
      local mains = 0
      for _, e in ipairs(self.g.edges) do if e.alive and not e.bulk then mains = mains + 1 end end
      return mains >= 4
    end
    for _, n in ipairs(self.g:nodesOfKind("source")) do
      if n.commodity == spec.commodity then return true end
    end
    return false
  end

  -- Cracks every main whose middle lies within reach of a point chosen from
  -- the company's own mains, so the damage lands where there is something to
  -- damage and not in an empty field.
  local function crack(self, spec, report)
    local mains = {}
    for _, e in ipairs(self.g.edges) do
      if e.alive and not e.bulk then mains[#mains + 1] = e end
    end
    local centre = mains[1 + math.floor(self:unit(self.day, 3) * #mains)]
    local na, nb = self.g.nodes[centre.a], self.g.nodes[centre.b]
    local cx, cy = (na.x + nb.x) / 2, (na.y + nb.y) / 2
    local hit = 0
    for _, e in ipairs(mains) do
      local a, b = self.g.nodes[e.a], self.g.nodes[e.b]
      local mx, my = (a.x + b.x) / 2, (a.y + b.y) / 2
      if (mx - cx) ^ 2 + (my - cy) ^ 2 <= spec.radius ^ 2 and not e.leaking
         and self:unit(self.day * 7919 + e.id, 4) < spec.hit then
        e.leaking = true
        hit = hit + 1
      end
    end
    report.cracked = hit
    return hit
  end

  -- Called once a day from endDay: runs the active shock down, and maybe
  -- starts another.
  function City:advanceShock(report)
    if self.shock then
      self.shock.left = self.shock.left - 1
      if self.shock.left <= 0 then self.shock = nil end
    end
    if self.shock or self.day < D.SHOCK_FROM or #self:clientList() < D.SHOCK_CLIENTS then return end
    if self:unit(self.day, 1) >= D.SHOCK_CHANCE then return end
    local eligible = {}
    for _, spec in ipairs(D.SHOCKS) do
      if applies(self, spec) then eligible[#eligible + 1] = spec end
    end
    if #eligible == 0 then return end
    local spec = eligible[1 + math.floor(self:unit(self.day, 2) * #eligible)]
    report.shock = spec.head
    if spec.ground then
      local hit = crack(self, spec, report)
      self:note("%s: %d mains cracked", spec.head, hit)
    else
      self.shock = { key = spec.key, commodity = spec.commodity, output = spec.output,
                     left = spec.days, head = spec.head }
      self:note("%s", spec.head)
    end
  end

  --------------------------------------------------------------------------
  -- Secure contracts
  --------------------------------------------------------------------------
  -- An offer becomes secure in City:addClient.

  -- What a secure customer is refunded for a day they were not fully supplied:
  -- the missing units at their rate, on top of the income they never paid.
  function City:serviceCredit(c)
    if not c.secure or c.prospect or self:fullyServed(c) then return 0 end
    -- A household that wants water and power is short when either is.
    local short = 0
    if c.demands then
      for key, want in pairs(c.demands) do
        short = short + math.max(0, want - ((self.servedBy[c.id] or {})[key] or 0))
      end
    else
      short = math.max(0, (c.demand or 0) - (self.served[c.id] or 0))
    end
    return math.floor(short * c.rate * self:eventRate(c.commodity) * D.SECURE.credit + 0.5)
  end

  --------------------------------------------------------------------------
  -- The N-1 check
  --------------------------------------------------------------------------

  function City:describeElement(kind, id)
    if kind == "edge" then
      local e = self.g.edges[id]
      if not e then return "main " .. id end
      local conduit = Graph.COMMODITIES[e.commodity] and Graph.COMMODITIES[e.commodity].conduit or "main"
      return string.upper(e.commodity) .. " " .. conduit .. " " .. id
    end
    local n = self.g.nodes[id]
    if n and n.kind == "source" and n.commodity then return string.upper(n.commodity) .. " WELL " .. id end
    local name = n and Graph.KINDS[n.kind] and Graph.KINDS[n.kind].name or "structure"
    return string.upper(name) .. " " .. id
  end

  local last = setmetatable({}, { __mode = "k" })

  local function gradeFor(share)
    for _, g in ipairs(D.GRADES) do if share <= g[1] then return g[2] end end
    return "F"
  end

  -- Fails each loaded main and structure in turn, on a copy so nothing in the
  -- real company moves, and records what each one would cost. Busiest first,
  -- because a check runs a flow solve per element and the quiet ones cannot
  -- matter much.
  --
  -- It is a job that can be run a little at a time (`stepResilience` with a
  -- time budget), because on a large company one solve costs tens of
  -- milliseconds and a check is dozens of them. `assessResilience` runs it to
  -- the end for callers that can wait.
  function City:startResilience()
    local Save = require("company_save")
    local copy = assert(Save.unpack(Save.pack(self)))
    -- Judge the network itself: a drought in progress is not a flaw in it.
    copy.shock = nil
    copy:refresh()
    local job = { city = self, copy = copy, rev = self.revision, day = self.day,
                  base = copy:dailyRevenue(), served0 = {}, points = {}, exposure = {}, i = 0 }
    for _, c in ipairs(copy:clientList()) do job.served0[c.id] = copy.served[c.id] or 0 end

    local list = {}
    for _, e in ipairs(copy.g.edges) do
      local flow = e.alive and math.abs(copy.detail.edge[e.id] or 0) or 0
      if flow > 0 then list[#list + 1] = { kind = "edge", id = e.id, flow = flow } end
    end
    for _, n in ipairs(copy.g:aliveNodes()) do
      local flow = n.kind ~= "client" and ((copy.detail.node[n.id] or 0) + (copy.produced[n.id] or 0)) or 0
      if flow > 0 then list[#list + 1] = { kind = "node", id = n.id, flow = flow } end
    end
    table.sort(list, function(a, b)
      if a.flow ~= b.flow then return a.flow > b.flow end
      return a.kind == b.kind and a.id < b.id or a.kind < b.kind
    end)
    job.list, job.total, job.checked = list, #list, math.min(#list, D.CHECK_LIMIT)
    return job
  end

  local function probe(job, item)
    local copy = job.copy
    local obj = item.kind == "edge" and copy.g.edges[item.id] or copy.g.nodes[item.id]
    obj.alive = false
    copy:refresh()
    local loss = job.base - copy:dailyRevenue()
    local hurt = 0
    for _, c in ipairs(copy:clientList()) do
      local was = job.served0[c.id] or 0
      local now = copy.served[c.id] or 0
      if now < was then
        hurt = hurt + 1
        local frac = (was - now) / math.max(1, was)
        local cur = job.exposure[c.id]
        if not cur or frac > cur.frac then
          job.exposure[c.id] = { frac = frac, kind = item.kind, id = item.id }
        end
      end
    end
    obj.alive = true
    if loss > 0.5 then
      job.points[#job.points + 1] = { kind = item.kind, id = item.id, loss = loss,
                                      share = job.base > 0 and loss / job.base or 0, hurt = hurt }
    end
  end

  local function finish(job)
    local self, points = job.city, job.points
    table.sort(points, function(a, b)
      if a.loss ~= b.loss then return a.loss > b.loss end
      return a.id < b.id
    end)
    local worst = points[1]
    local share = worst and worst.share or 0
    for _, p in ipairs(points) do p.label = self:describeElement(p.kind, p.id) end
    last[self] = {
      rev = job.rev, day = job.day, base = job.base, checked = job.checked, total = job.total,
      grade = job.base > 0 and gradeFor(share) or nil, share = share, worst = worst,
      points = points, exposure = job.exposure,
    }
  end

  -- Runs the job for about `budget` seconds. Returns true once it has finished
  -- and stored its report, or false and how far along it is.
  function City:stepResilience(job, budget)
    local started = os.clock()
    while job.i < job.checked do
      job.i = job.i + 1
      probe(job, job.list[job.i])
      if os.clock() - started >= budget then break end
    end
    if job.i >= job.checked then finish(job); return true end
    return false, job.i / job.checked
  end

  function City:assessResilience()
    local job = self:startResilience()
    self:stepResilience(job, math.huge)
    return last[self]
  end

  -- The last check, and whether the company has changed since it ran.
  function City:resilienceReport()
    local r = last[self]
    if not r then return nil end
    return r, r.rev ~= self.revision
  end

  -- Would this customer keep being supplied through any one failure? nil when
  -- no check has been run.
  function City:exposureOf(id)
    local r = last[self]
    if not r then return nil end
    return r.exposure[id] or false
  end
end
