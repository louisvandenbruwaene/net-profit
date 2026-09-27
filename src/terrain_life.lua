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
    gemChance = 0.05,      -- chance that demolishing a range turns up gems
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


  -- What harvesting a wood or blasting a range yields, and what it costs. A
  -- range a quarry has cut into gives no more than it has left.
  function City:clearYield(o)
    local units=math.floor(o.r*o.r/100)
    if o.kind=='bedrock' then units=math.min(units,self:rockLeft(o)) end
    return units
  end
  function City:clearCost(o) return math.ceil(self:clearYield(o)*(o.kind=='park' and 4 or 35)) end
  function City:clearTerrain(index)
    local o=self.obstacles[index]
    if not o or (o.kind~='park' and o.kind~='bedrock') then return nil,'select woodland or mountain' end
    if not self.permits[o.kind] then return nil,'requires the terrain permit' end
    -- Every affected region must belong to the company before a range is cleared.
    for col=math.floor((o.x-o.r)/City.MAP.w)+1,math.floor((o.x+o.r)/City.MAP.w)+1 do
      for row=math.floor((o.y-o.r)/City.MAP.h)+1,math.floor((o.y+o.r)/City.MAP.h)+1 do
        local d=self:cellAt(col,row); if not d or not d.owned then return nil,'buy all regions covered by this terrain first' end
      end
    end
    local units,cost=self:clearYield(o),self:clearCost(o)
    if self.money<cost then return nil,'clearing costs $'..cost end
    self:spend(cost); local key=o.kind=='park' and 'timber' or 'rock'; self.stock[key]=(self.stock[key] or 0)+units
    if o.kind=='bedrock' and self:random()<L.gemChance then self.stock.gems=(self.stock.gems or 0)+math.max(1,math.floor(units/100)) end
    table.remove(self.obstacles,index)
    -- A harvested wood is remembered, and grows back where nothing is built.
    if o.kind=='park' then
      self.regrowth=self.regrowth or {}
      self.regrowth[#self.regrowth+1]={x=o.x,y=o.y,r=o.r,kind=o.kind,grove=o.grove,massive=o.massive,cleared=self.day}
    end
    self:refresh(); return true
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

end
