-- The distribution hub: the top of the fitting ladder.
--
-- A T split becomes a hub, a hub becomes a large hub, and a large hub becomes a
-- distribution hub. That last level is the one that runs a neighbourhood by
-- itself. Once a day, for every customer inside its radius who pays at least
-- the minimum price the player set on it, it does the three things a person
-- would otherwise click through by hand:
--
--   1. signs the offer,
--   2. lays a real connection to them (T splits and mains, paid for at the
--      ordinary price, exactly as if the player had drawn them), and
--   3. digs out the main that is starving them and lays the next size up.
--
-- Nothing here is free and nothing is invisible: every pipe it lays is on the
-- map and on the books. The minimum price is the whole of the decision, which
-- is why it is the only control the hub has.
local NB = require("network_builder")
local Graph = require("graph")
local D = require("data.upgrades")

return function(City)
  City.DISTRIBUTION = D.DISTRIBUTION

  local function dist(a, b) return math.sqrt((a.x - b.x) ^ 2 + (a.y - b.y) ^ 2) end

  function City:isDistribution(n)
    return n and n.alive and self:levelFamily(n) == "fitting"
      and self:levelOf(n) >= #D.LEVELS.fitting
  end

  function City:distributionHubs()
    local t = {}
    for _, n in ipairs(self.g:aliveNodes()) do
      if self:isDistribution(n) then t[#t + 1] = n end
    end
    return t
  end

  function City:hubRadius(h) return h.radius or D.DISTRIBUTION.radius end

  function City:hubFloor(h) return h.floor or D.DISTRIBUTION.floor end

  function City:setHubFloor(id, value)
    local n = self.g.nodes[id]
    if not self:isDistribution(n) then return nil, "Select a distribution hub first" end
    n.floor = math.max(0, math.floor(value))
    return n
  end

  -- The trades a hub can hand out: whatever arrives at it over a live main.
  function City:hubTrades(h)
    local t = {}
    for _, e in ipairs(self.g:edgesAt(h.id)) do
      if e.alive and not e.rail and Graph.COMMODITIES[e.commodity]
         and Graph.COMMODITIES[e.commodity].role == "utility" then
        t[e.commodity] = true
      end
    end
    return t
  end

  -- Every customer and offer this hub looks after today, nearest first so the
  -- chains it lays grow outward from the hub rather than criss-crossing it.
  function City:hubClients(h, prospects)
    local r2, t = self:hubRadius(h) ^ 2, {}
    for _, c in ipairs(self.g:aliveNodes()) do
      if c.kind == "client" and (prospects == nil or (c.prospect and true or false) == prospects)
         and (c.x - h.x) ^ 2 + (c.y - h.y) ^ 2 <= r2 then
        t[#t + 1] = c
      end
    end
    table.sort(t, function(a, b)
      local da, db = dist(a, h), dist(b, h)
      if da ~= db then return da < db end
      return a.id < b.id
    end)
    return t
  end

  local function wants(c)
    return c.demands or { [c.commodity] = c.demand or 0 }
  end

  local function hasMain(self, c, key)
    for _, e in ipairs(self.g:edgesAt(c.id)) do
      if e.alive and e.commodity == key then return true end
    end
    return false
  end

  -- A connection from the hub itself when it has a port free and the trade in
  -- hand, otherwise from the nearest fitting on the network that can carry it.
  local function connect(self, h, c, key, want)
    if NB.freePort(self, h) and dist(h, c) <= self:hubRadius(h) then
      local seen = NB.component(self, h.id, key)
      if NB.headroom(self, seen, key) >= want and NB.chain(self, h, c, key) then return true end
    end
    return NB.connectPipe(self, c, want, key)
  end

  -- One hub's day. It lays at most `perDay` connections and widens at most
  -- `perDay` mains, each paid for out of cash on hand.
  function City:runHub(h, out)
    local floor, trades = self:hubFloor(h), self:hubTrades(h)
    if not next(trades) then return end
    local cap = D.DISTRIBUTION.perDay

    -- 1. Sign. A secure contract promises refunds, so it stays the player's call.
    for _, c in ipairs(self:hubClients(h, true)) do
      if trades[c.commodity] and (c.rate or 0) >= floor and not c.secure
         and self.licences[c.commodity] then
        c.prospect = false
        out.signed = out.signed + 1
      end
    end

    -- 2. Connect.
    local laid = 0
    for _, c in ipairs(self:hubClients(h, false)) do
      if laid >= cap then break end
      if (c.rate or 0) >= floor and not c.supplyClosed and self.day >= (c.hubRetryDay or 0) then
        for key, want in pairs(wants(c)) do
          if trades[key] and want > 0 and not hasMain(self, c, key) then
            local before = self.money
            if connect(self, h, c, key, want) then
              laid, out.wired = laid + 1, out.wired + 1
              out.spent = out.spent + math.max(0, before - self.money)
            else
              c.hubRetryDay = self.day + 3
            end
          end
        end
      end
    end

    -- 3. Widen whatever is starving a paying customer.
    local widened = 0
    for _, c in ipairs(self:hubClients(h, false)) do
      if widened >= cap then break end
      if (c.rate or 0) >= floor and trades[c.commodity] then
        local why, eid = self:constraintFor(c.id)
        local e = eid and self.g.edges[eid]
        if why == "main" and e and (e.capMax or e.cap) < City.autoWidenCap() then
          local bigger = self:biggerSize(e)
          local quote = bigger and self:replaceQuote(eid, bigger, e.grade)
          if quote and quote.net <= self.money and not self:replaceError(eid, bigger, e.grade)
             and self:replacePipe(eid, bigger, e.grade) then
            widened, out.widened = widened + 1, out.widened + 1
            out.spent = out.spent + quote.net
          end
        elseif why == "repair" and e then
          local cost = self:repairCost(e)
          if cost <= self.money and self:repairPipe(eid) then
            widened, out.repaired = widened + 1, out.repaired + 1
            out.spent = out.spent + cost
          end
        end
      end
    end
  end

  -- Every distribution hub, once, in node order so two hubs sharing a street
  -- decide who wires it the same way every time.
  function City:runDistribution(report)
    local out = { signed = 0, wired = 0, widened = 0, repaired = 0, spent = 0 }
    local hubs = self:distributionHubs()
    for _, h in ipairs(hubs) do self:runHub(h, out) end
    if #hubs > 0 then self:refresh() end
    if report then report.distribution = out end
    if out.signed + out.wired + out.widened + out.repaired > 0 then
      local parts = {}
      if out.signed > 0 then parts[#parts + 1] = out.signed .. " signed" end
      if out.wired > 0 then parts[#parts + 1] = out.wired .. " connected" end
      if out.widened > 0 then parts[#parts + 1] = out.widened .. " mains widened" end
      if out.repaired > 0 then parts[#parts + 1] = out.repaired .. " repaired" end
      self:note("Distribution hubs: %s for $%d", table.concat(parts, ", "), out.spent)
    end
    return out
  end

  function City:distributionBill()
    return #self:distributionHubs() * D.DISTRIBUTION.upkeep
  end
end
