-- Levels: one building, grown in place.
--
-- Junctions, towers, automation hubs and pumps each start weak and are made
-- stronger by paying for the next level, rather than being replaced by a
-- different building. Level lives on the node (`n.level`) and so does every
-- stat a level gives (`ports`, `throughput`, `radius`), so the flow solver and
-- the port checks read them exactly as they always did and a save needs no
-- new machinery. See src/data/upgrades.lua for the numbers.
local Graph = require("graph")
local D = require("data.upgrades")

return function(City)
  City.LEVELS = D

  local function family(n) return n and D.FAMILY[n.kind] end

  function City:levelFamily(n) return family(n) end

  -- A building's level: what it records, never below what its kind implies.
  function City:levelOf(n)
    if not family(n) then return nil end
    return math.max(n.level or D.LEGACY[n.kind] or 1, D.MIN_LEVEL[n.kind] or 1)
  end

  function City:levelCount(n) return family(n) and #D.LEVELS[family(n)] or 0 end

  function City:levelName(n, level)
    local f = family(n)
    return f and D.NAMES[f][level or self:levelOf(n)] or nil
  end

  -- The stats of a level for this particular building. Towers scale their
  -- throughput with the voltage they carry.
  function City:levelSpec(n, level)
    local f = family(n)
    local base = f and D.LEVELS[f][level]
    if not base then return nil end
    local spec = { level = level, name = D.NAMES[f][level], ports = base.ports,
      throughput = base.throughput, reach = base.reach, radius = base.radius,
      clients = base.clients or 0 }
    if f == "tower" and base.throughput < 9999 then
      spec.throughput = base.throughput * (D.TOWER_SCALE[n.kind] or 1)
    end
    spec.cost = type(base.cost) == "table" and base.cost[n.kind] or base.cost
    return spec
  end

  -- Puts a building at a level. A new building is set to the level's numbers
  -- exactly; an existing one only ever gains, so an old save never loses a
  -- connection or a bit of capacity it was already using.
  local function apply(self, n, level, exact)
    local spec = self:levelSpec(n, level)
    n.level = level
    if exact then
      n.ports, n.throughput = spec.ports, spec.throughput
    else
      n.ports = math.max(n.ports or 0, spec.ports)
      n.throughput = math.max(n.throughput or 0, spec.throughput)
    end
    if spec.radius then n.radius = exact and spec.radius or math.max(n.radius or 0, spec.radius) end
    return spec
  end

  function City:levelError(id)
    local n = self.g.nodes[id]
    if not (n and n.alive and family(n)) then return "nothing here can be upgraded" end
    local level = self:levelOf(n)
    if level >= self:levelCount(n) then return "already at the highest level" end
    local spec = self:levelSpec(n, level + 1)
    if self:progress() < spec.clients then
      return "needs " .. spec.clients .. " signed customers"
    end
    if spec.cost > self.money then return "not enough cash" end
    return nil
  end

  -- What the next level would give, for the panel and the advisor.
  function City:levelNext(id)
    local n = self.g.nodes[id]
    if not (n and n.alive and family(n)) then return nil end
    local level = self:levelOf(n)
    if level >= self:levelCount(n) then return nil end
    return self:levelSpec(n, level + 1)
  end

  function City:upgradeLevel(id)
    local err = self:levelError(id)
    if err then return nil, err end
    local n = self.g.nodes[id]
    local spec = self:levelSpec(n, self:levelOf(n) + 1)
    self:spend(spec.cost)
    n.paid = (n.paid or 0) + spec.cost
    -- A junction becomes a hub the moment it needs more than three ports; the
    -- mains already tied in stay exactly where they are.
    if n.kind == "junction" and spec.ports > Graph.KINDS.junction.ports then n.kind = "manifold" end
    apply(self, n, spec.level, false)
    self:note("%s %d upgraded to level %d, %s, for $%d", Graph.KINDS[n.kind].name, id,
      spec.level, spec.name, spec.cost)
    self:refresh()
    return n
  end

  -- How far a cable or pipe out of this building may run, beyond its base.
  function City:reachBonus(n)
    local f = family(n)
    if f ~= "tower" and f ~= "pump" then return 0 end
    -- A building that predates levels reaches exactly as far as it always did
    -- until it is first upgraded.
    if not n.level then return 0 end
    local spec = self:levelSpec(n, self:levelOf(n))
    return spec and spec.reach or 0
  end

  -- New buildings start at level 1 (a manifold, which is a hub by definition,
  -- at the level that gives it its six ports).
  local plainBuild = City.build
  function City:build(...)
    local n, err = plainBuild(self, ...)
    if n and family(n) then
      local level = D.MIN_LEVEL[n.kind] or 1
      apply(self, n, level, true)
    end
    return n, err
  end

  -- Swapping a building for another kind keeps its level only inside its own
  -- family: a level 3 junction does not become a level 3 pump for free.
  local plainConvert = City.convertNode
  function City:convertNode(id, kind, ...)
    local before = self.g.nodes[id]
    local wasFamily, wasLevel = family(before), before and self:levelOf(before)
    local n, err = plainConvert(self, id, kind, ...)
    if n and family(n) then
      local level = wasFamily == family(n) and wasLevel or 1
      level = math.max(level, D.MIN_LEVEL[n.kind] or 1)
      if n.kind == "junction" then level = 1 end
      apply(self, n, level, level == 1)
    end
    return n, err
  end

  -- Longer reach for the better buildings on either end.
  local plainRange = City.rangeBetween
  function City:rangeBetween(a, b, rail, commodity, size)
    local range = plainRange(self, a, b, rail, commodity, size)
    if rail then return range end
    local na, nb = self.g.nodes[a], self.g.nodes[b]
    if not (na and nb) then return range end
    return range * (1 + math.max(self:reachBonus(na), self:reachBonus(nb)))
  end
end
