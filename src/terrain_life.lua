-- terrain_life.lua -- ground that changes with use.
--
-- A quarry takes rock out of the bedrock it stands on, and a range holds only
-- so much: what has been cut is kept on the range itself (`o.mined`), and the
-- quarry's daily output is capped by what is left, down to nothing. A range
-- in an older save starts full.
--
-- A wood cleared with Harvest is not gone for good: it is remembered in
-- `city.regrowth` and grows back on the same spot, with the same outline and
-- the same trees, once enough days have passed -- but only if nothing has been
-- built on it or run across it since. Ground kept in use stays clear.
local Shape = require("terrain_shape")

return function(City)
  City.TERRAIN_LIFE = {
    rockPerArea = 1 / 8,   -- units of rock per square metre of radius^2
    regrowDays = 40,       -- days from Harvest until a wood can stand again
  }
  local L = City.TERRAIN_LIFE

  function City:rockReserve(o)
    return math.floor(o.r * o.r * L.rockPerArea)
  end

  function City:rockLeft(o)
    return math.max(0, self:rockReserve(o) - (o.mined or 0))
  end

  -- The bedrock a quarry is cutting, if it is standing on any.
  function City:quarryRange(n)
    if not (n and n.kind == "source" and n.commodity == "rock") then return nil end
    local o = self:obstacleAt(n.x, n.y)
    if o and o.kind == "bedrock" and not o.river then return o end
    return nil
  end

  local refresh = City.refresh
  function City:refresh()
    -- Cap each quarry by what its range has left before the flow is solved.
    for _, n in ipairs(self.g:aliveNodes()) do
      local o = self:quarryRange(n)
      if o then
        local left = self:rockLeft(o)
        if left < (n.output or 0) then n.effectiveOutputLife = left else n.effectiveOutputLife = nil end
      else
        n.effectiveOutputLife = nil
      end
    end
    return refresh(self)
  end

  -- infrastructure.lua rebuilds effectiveOutput at the top of every refresh,
  -- so the depletion cap is applied as the last word through shockOutput,
  -- which that rebuild consults for every node.
  local shockOutput = City.shockOutput
  function City:shockOutput(n)
    local v = shockOutput and shockOutput(self, n) or nil
    if n.effectiveOutputLife then
      return math.min(v or n.output or 0, n.effectiveOutputLife)
    end
    return v
  end

  local clearTerrain = City.clearTerrain
  function City:clearTerrain(index)
    local o = self.obstacles[index]
    local keep = o and o.kind == "park" and { x = o.x, y = o.y, r = o.r, kind = o.kind, grove = o.grove, massive = o.massive }
    local ok, why = clearTerrain(self, index)
    if ok and keep then
      keep.cleared = self.day
      self.regrowth = self.regrowth or {}
      self.regrowth[#self.regrowth + 1] = keep
    end
    return ok, why
  end

  -- Is anything the company owns standing in or running across this ground?
  function City:groundInUse(o)
    for _, n in ipairs(self.g:aliveNodes()) do
      if Shape.contains(o, n.x, n.y) then return true end
    end
    for _, e in ipairs(self.g.edges) do
      local a, b = self.g.nodes[e.a], self.g.nodes[e.b]
      if e.alive and a and b and Shape.crosses(o, a.x, a.y, b.x, b.y) then return true end
    end
    for _, l in ipairs(self.links or {}) do
      local a, b = self.g.nodes[l.a], self.g.nodes[l.b]
      if l.alive and a and b and Shape.crosses(o, a.x, a.y, b.x, b.y) then return true end
    end
    return false
  end

  -- How far a regrowing wood has come, 0 to 1.
  function City:regrowthProgress(w)
    return math.max(0, math.min(1, (self.day - (w.cleared or self.day)) / L.regrowDays))
  end

  local endDay = City.endDay
  function City:endDay()
    -- What each quarry cut today, counted before the day turns over.
    self:refresh()
    local cut = {}
    for _, n in ipairs(self.g:aliveNodes()) do
      local o = self:quarryRange(n)
      if o then cut[#cut + 1] = { o = o, n = n, v = (self.produced or {})[n.id] or 0 } end
    end
    local report = endDay(self)
    if not report then return report end
    for _, c in ipairs(cut) do
      local before = self:rockLeft(c.o)
      c.o.mined = (c.o.mined or 0) + c.v
      if before > 0 and self:rockLeft(c.o) <= 0 then
        self:note("A quarry has worked its range out: no more rock there")
      end
    end
    local still = {}
    for _, w in ipairs(self.regrowth or {}) do
      if self:regrowthProgress(w) >= 1 and not self:groundInUse(w) then
        self.obstacles[#self.obstacles + 1] = { x = w.x, y = w.y, r = w.r, kind = w.kind, grove = w.grove, massive = w.massive }
        self:note("A harvested wood has grown back")
      else
        still[#still + 1] = w
      end
    end
    self.regrowth = #still > 0 and still or nil
    self:refresh()
    return report
  end
end
