-- What a unit costs, and what it sells for.
--
-- A well used to be paid a "wholesale" fee for every unit a customer drew,
-- which made the price of water impossible to read: the source earned money,
-- so what did a unit actually cost? Now a source only costs. It has an upkeep
-- a day whether it pumps or not, and a pumping cost for every unit it lifts
-- (fuel, for a reactor; the landed price, for anything imported). Every
-- customer pays a rate a unit. The difference is the margin, and the game
-- shows it wherever a price is shown.
--
--   marginal cost  what one more unit costs at the source
--   unit cost      everything this trade cost today (sources, pumping, mains)
--                  over every unit it delivered: the true cost of a unit
--   price          what customers of this trade pay on average
--   margin         price minus unit cost

return function(City)
  local function trade(t) return City.trade[t] or City.trade.water end

  -- What one more unit costs at the cheapest place it can come from.
  function City:marginalCost(t)
    local best
    for _, n in ipairs(self.g:nodesOfKind("source")) do
      if n.alive and n.commodity == t then
        local c = n.plant and (n.fuel or trade(t).fuelPerUnit or 0) or (trade(t).extractPerUnit or 0)
        if not best or c < best then best = c end
      end
    end
    if best then return best end
    for _, n in ipairs(self.g:nodesOfKind("terminal")) do
      if n.alive and trade(t).importCost then
        local c = trade(t).importCost * ((City.HAVENS[n.haven] or {}).import or 1)
        if not best or c < best then best = c end
      end
    end
    return best or trade(t).extractPerUnit or 0
  end

  -- The pumping bill: every unit a source lifted today, at its per-unit cost.
  -- Reactors bill their fuel separately (fuelBill), so they are not here.
  function City:pumpingBill()
    local total = 0
    for _, n in ipairs(self.g:nodesOfKind("source")) do
      if n.alive and not n.plant then
        local rate = trade(n.commodity).extractPerUnit or 0
        total = total + ((self.produced or {})[n.id] or 0) * rate
      end
    end
    return total
  end

  local function delivered(self, c, t)
    local by = (self.servedBy or {})[c.id]
    if by and by[t] then return by[t] end
    if c.commodity == t then return (self.served or {})[c.id] or 0 end
    return 0
  end

  -- Everything one trade cost today and everything it earned. `extra` adds a
  -- customer that is not signed yet, at full demand, so an offer can say what
  -- a unit would cost with it on the books.
  local function tradeCosts(self, t, extra)
    local spec = trade(t)
    local fixed, variable, units, revenue, rates, signed = 0, 0, 0, 0, 0, 0
    for _, n in ipairs(self.g:nodesOfKind("source")) do
      if n.alive and n.commodity == t then
        fixed = fixed + self:sourceUpkeep(n)
        local made = (self.produced or {})[n.id] or 0
        variable = variable + made * (n.plant and (n.fuel or spec.fuelPerUnit or 0) or (spec.extractPerUnit or 0))
      end
    end
    for _, n in ipairs(self.g:nodesOfKind("terminal")) do
      local landed = ((self.producedBy or {})[n.id] or {})[t] or 0
      variable = variable + landed * (spec.importCost or 0) * ((City.HAVENS[n.haven] or {}).import or 1)
    end
    for _, e in ipairs(self.g.edges) do
      if e.alive and not e.rail and e.commodity == t then fixed = fixed + self:pipeUpkeep(e) end
    end
    for _, c in ipairs(self:clientList()) do
      local got = delivered(self, c, t)
      if got > 0 then
        units = units + got
        -- A household's second utility is billed at its own rate, as in clientIncome.
        local rate = t ~= c.commodity and (c.utilityRates or {})[t] or c.rate or 0
        revenue = revenue + got * rate * self:eventRate(t)
      end
      if c.commodity == t then rates, signed = rates + (c.rate or 0), signed + 1 end
    end
    if extra then
      local want = (extra.demands and extra.demands[t]) or extra.demand or 0
      units = units + want
      variable = variable + want * self:marginalCost(t)
    end
    local out = { fixed = fixed, variable = variable, units = units, revenue = revenue,
                  marginal = self:marginalCost(t) }
    out.total = fixed + variable
    out.perUnit = units > 0 and out.total / units or nil
    out.price = units > 0 and revenue / units or (signed > 0 and rates / signed or nil)
    out.margin = out.perUnit and out.price and out.price - out.perUnit or nil
    return out
  end

  -- The clients list asks this for every row of every frame, and the answer
  -- only changes when the network does, so it is kept until the next solve.
  -- Held beside the company rather than on it, so it never reaches a save.
  local cache = setmetatable({}, { __mode = "k" })
  function City:tradeCosts(t, extra)
    local c = cache[self]
    if not c or c.rev ~= self.revision then c = { rev = self.revision }; cache[self] = c end
    local key = extra and (t .. ":" .. extra.id .. ":" .. tostring(extra.demand)) or t
    if not c[key] then c[key] = tradeCosts(self, t, extra) end
    return c[key]
  end

  -- One customer's margin: their rate against what a unit of their trade
  -- costs the company. An offer is priced as if it were already signed.
  function City:clientMargin(c)
    local t = c.commodity
    local costs = self:tradeCosts(t, c.prospect and c or nil)
    local cost = costs.perUnit or costs.marginal
    local rate = (c.rate or 0) * self:eventRate(t)
    return rate - cost, cost, rate, costs.perUnit == nil
  end

  -- A change in money, always with its sign in front: "+$30", "-$10".
  function City.signed(v)
    local n = math.floor(v + 0.5)
    return (n < 0 and "-$" or "+$") .. math.abs(n)
  end

  -- Money as it reads everywhere: whole dollars when it is big, cents when a
  -- unit of water is worth less than one.
  function City.money2(v)
    if v == nil then return "-" end
    local a = math.abs(v)
    if a == math.floor(a) or a >= 100 then return string.format("%s$%d", v < 0 and "-" or "", math.floor(a + 0.5)) end
    if a >= 10 then return string.format("%s$%.1f", v < 0 and "-" or "", a) end
    return string.format("%s$%.2f", v < 0 and "-" or "", a)
  end
end
