-- usage.lua -- contracts and what customers actually use.
--
-- `demand` is the contract: the most a customer may draw in a day, and what
-- they pay for. `use` is today's draw, set on the node before every solve and
-- never above the contract. It comes from a hash of the company, the customer
-- and the day, never from City:random(), so the same day always has the same
-- weather and the same draws, and tomorrow can be forecast.
local D = require("data.usage")

return function(City)
  City.USAGE = D

  -- 1..7, Monday first. Day 1 of every company is a Monday.
  function City.weekday(day) return ((day - 1) % 7) + 1 end
  function City.weekdayName(day) return D.WEEKDAYS[City.weekday(day)] end

  local weatherCache = setmetatable({}, { __mode = "k" })
  function City:weatherOn(day)
    local cache = weatherCache[self]
    if not cache then cache = {}; weatherCache[self] = cache end
    if cache[day] then return cache[day] end
    cache[day] = self:rollWeather(day)
    return cache[day]
  end

  function City:rollWeather(day)
    local roll, acc = self:unit(day, 4411), 0
    for _, w in ipairs(D.WEATHER) do
      acc = acc + w.p
      if roll < acc then return w end
    end
    return D.WEATHER[1]
  end

  -- The share of the contract a customer of this type expects to use on this
  -- day for this trade, before their own mood.
  function City:usageFactor(c, key, day)
    local kind = c.clientType or "house"
    local week = kind == "stadium" and D.WEEK.stadium or D.BUSINESS[kind] and D.WEEK.business or D.WEEK.home
    local w = self:weatherOn(day)
    return (D.MEAN[kind] or D.DEFAULT_MEAN) * week[City.weekday(day)] * (w[key] or 1)
  end

  -- What one customer draws of one trade on one day: the contract times the
  -- factor, nudged by their mood, rounded by a hash, at least 1, at most the
  -- contract.
  function City:useOf(c, key, want, day)
    if not want or want <= 0 then return 0 end
    local salt = key == c.commodity and 0 or 50
    -- `usagePeak` is set only on a forecast copy: everybody at the top of
    -- their range at once, the worst the day's weather and weekday can bring.
    local mood = self.usagePeak and 1 + D.SPREAD or 1 + D.SPREAD * (2 * self:unit(c.id * 131 + salt, day) - 1)
    local exact = want * self:usageFactor(c, key, day) * mood
    local whole = self.usagePeak and math.ceil(exact) or math.floor(exact)
    if not self.usagePeak and self:unit(c.id * 131 + salt + 7, day) < exact - whole then whole = whole + 1 end
    return math.max(1, math.min(want, whole))
  end

  -- Before a solve: every signed customer's draw for the day. Worked out once
  -- a day per customer and kept on the node, since refresh runs after every
  -- click. The test suites that are about flow, not demand, set FLAT_USAGE and
  -- have every customer draw the whole contract.
  function City:applyUsage()
    local day = self.day
    local flat = City.FLAT_USAGE
    local nodes = self.g.nodes
    for i = 1, #nodes do
      local c = nodes[i]
      if c.alive and c.kind == "client" and not c.prospect then
        if flat then
          c.use, c.useDay = c.demand, nil
          if c.demands then
            c.uses = {}
            for key, want in pairs(c.demands) do c.uses[key] = want end
          else
            c.uses = nil
          end
        else
          -- The contract as one number, so a change to any trade on it redraws.
          local sig = c.demand or 0
          local extra = c.demands
          if extra then
            for key, want in pairs(extra) do
              if key ~= c.commodity then sig = sig + want * 1000 end
            end
          end
          if c.useDay ~= day or c.useFor ~= sig then
            c.useDay, c.useFor = day, sig
            self:setUse(c, day)
          end
        end
      end
    end
  end

  function City:setUse(c, day)
    c.use = self:useOf(c, c.commodity, c.demand, day)
    if c.demands then
      c.uses = {}
      for key, want in pairs(c.demands) do
        c.uses[key] = key == c.commodity and c.use or self:useOf(c, key, want, day)
      end
    else
      c.uses = nil
    end
  end

  -- What a customer wants today of a trade (their own by default).
  function City:want(c, key)
    key = key or c.commodity
    if key == c.commodity then return c.use or c.demand or 0 end
    return (c.uses or {})[key] or (c.demands or {})[key] or 0
  end

  -- Tomorrow's likely draw on one trade, as the lowest and highest the day
  -- could bring given the weather and weekday, against the contracts.
  function City:forecast(key, day)
    day = day or self.day + 1
    local lo, hi, contract = 0, 0, 0
    for _, c in ipairs(self:clientList()) do
      local want = key == c.commodity and c.demand or (c.demands or {})[key]
      if want and want > 0 then
        local f = self:usageFactor(c, key, day)
        lo = lo + math.max(1, math.min(want, math.floor(want * f * (1 - D.SPREAD))))
        hi = hi + math.max(1, math.min(want, math.ceil(want * f * (1 + D.SPREAD))))
        contract = contract + want
      end
    end
    return lo, hi, contract
  end
end
