-- projects.lua -- big one-off projects, and referrals from reliable customers.
--
-- A project is a customer the company builds for itself: a hospital, a
-- college, a stadium, an airport. It wants more than any house main carries,
-- so it needs a real main to it, and once it is fully supplied it draws new
-- offers round itself. A referral is the small version of the same idea: a
-- customer supplied without a break for a month sends a neighbour, who pays
-- over the going rate.
local Data = require("data.projects")

return function(City)
  City.PROJECTS = Data.PROJECTS
  City.PROJECT_BY = {}
  for _, spec in ipairs(Data.PROJECTS) do
    City.PROJECT_BY[spec.key] = spec
    -- Projects are customer types, so names, income and art all work, but
    -- pickClientType lists its types by name and never offers one of these.
    City.CLIENTS[spec.key] = City.CLIENTS[spec.key] or {
      name = spec.name, commodity = spec.commodity, demand = { spec.demand, spec.demand },
      rate = spec.rate, patience = spec.patience, weight = 0, project = true,
    }
  end
  City.PROJECT_MAIN = Data.PROJECT_MAIN
  City.REFERRAL = Data.REFERRAL

  -- The project's standing building, or nil if it was never built or has gone.
  function City:projectNode(key)
    local rec = (self.projects or {})[key]
    local n = rec and self.g.nodes[rec.id]
    if n and n.alive and n.kind == "client" and n.clientType == key then return n end
    return nil
  end

  -- Why this project cannot be offered at all yet (nil when it can).
  function City:projectLocked(key)
    local spec = City.PROJECT_BY[key]
    if not spec then return "no such project" end
    if self:projectNode(key) then return "already built" end
    if not self.licences[spec.commodity] then return "needs the " .. spec.commodity .. " licence" end
    if #self:clientList() < spec.clients then return spec.clients .. " customers first" end
    return nil
  end

  function City:projectError(key, x, y)
    local why = self:projectLocked(key)
    if why then return why end
    why = self:placementError(x, y, "client")
    if why then return why end
    if City.PROJECT_BY[key].price > self.money then return "not enough cash" end
    return nil
  end

  -- What a project earns a day once it is fully supplied, before the main to it.
  function City.projectIncome(key)
    local spec = City.PROJECT_BY[key]
    return spec.demand * spec.rate
  end

  function City:buildProject(key, x, y)
    local why = self:projectError(key, x, y)
    if why then return nil, why end
    local spec = City.PROJECT_BY[key]
    self:spend(spec.price)
    local n = self.g:addNode(x, y, "client")
    n.clientType, n.commodity, n.demand = key, spec.commodity, spec.demand
    n.rate, n.rateBase = spec.rate, spec.rate
    n.patience, n.grace = spec.patience, spec.patience
    n.prospect = false
    n.baseDemand = spec.demand
    self.projects = self.projects or {}
    self.projects[key] = { id = n.id, day = self.day, attract = spec.attract }
    self:note("%s built for $%d", spec.name, spec.price)
    self:refresh()
    return n
  end

  -- At the close: each project that is fully supplied draws one offer a day
  -- round itself until its draw is spent.
  function City:projectArrivals(report)
    for _, spec in ipairs(City.PROJECTS) do
      local rec = (self.projects or {})[spec.key]
      local n = self:projectNode(spec.key)
      if n and (rec.attract or 0) > 0 and self:fullyServed(n) then
        local c = self:addClient(nil, true, nil, n)
        if c then
          rec.attract = rec.attract - 1
          c.expires = self.day + City.REFERRAL.expires
          local request = { name = City.CLIENTS[c.clientType].name, x = c.x, y = c.y, id = c.id, drawnBy = n.id }
          report.arrivals[#report.arrivals + 1] = request
          report.arrived = report.arrived or request
        end
      end
    end
  end

  -- At the close: a customer supplied for a month without a break sends a
  -- neighbour. The neighbour asks for the same trade where it can, and offers
  -- the going rate plus the referral premium, never less than the draw gave.
  function City:referralsFrom(c, report)
    if c.prospect or City.PROJECT_BY[c.clientType] then return nil end
    if (c.streak or 0) == 0 or c.streak % City.REFERRAL.every ~= 0 then return nil end
    if self:unit(c.id, 900 + c.streak) >= City.REFERRAL.chance then return nil end
    local n = self:addClient(nil, true, nil, c)
    if not n then return nil end
    local base = n.rateBase or City.CLIENTS[n.clientType].rate
    n.rate = math.max(n.rate, math.ceil(base * (1 + City.REFERRAL.premium)))
    n.referredBy = c.id
    n.expires = self.day + City.REFERRAL.expires
    report.referred = report.referred or {}
    report.referred[#report.referred + 1] = { x = c.x, y = c.y, id = n.id, from = c.id }
    return n
  end
end
