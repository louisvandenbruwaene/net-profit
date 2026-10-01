-- imports.lua -- buying from abroad through a haven.
--
-- A haven already lands whatever the company's works and customers draw on,
-- every day, billed per unit. This is the other way in: an order. At a haven
-- the player picks a good and a quantity, pays the landed price up front (list
-- price times that haven's freight multiplier), and the cargo comes in on the
-- next day's tide: a freighter for a harbour, lorries for a road head, a plane
-- for an air apron. From there it is hauled on to the nearest yard (haulage.lua)
-- and is in stock the morning after; with no yard, the quay is the store.
--
-- An order is a row in `city.shipments` until it lands (`city.orders` is the
-- departments, a different thing); what landed on a day stays
-- in `city.landings` for that day, so the map can show the ship alongside.
local Graph = require("graph")

return function(City)
  City.IMPORT = require("data.freight").IMPORT

  -- What can be ordered: solid goods with a world price. Liquids come down a
  -- main and power is never imported.
  function City:importable()
    local out = {}
    for _, key in ipairs(Graph.ALL) do
      local spec, trade = Graph.COMMODITIES[key], City.trade[key]
      if spec and trade and trade.importCost and spec.landed ~= false and spec.form == "solid" then out[#out + 1] = key end
    end
    return out
  end

  function City:importPrice(key, haven)
    local trade = City.trade[key]
    if not trade or not trade.importCost then return nil end
    return trade.importCost * ((City.HAVENS[haven or "port"] or City.HAVENS.port).import or 1)
  end

  function City:shippedUnits(key)
    local total = 0
    for _, o in ipairs(self.shipments or {}) do if not key or o.key == key then total = total + o.units end end
    return total
  end

  -- Room left in the yards for a good, counting what is already on its way. A
  -- company with no yard keeps one yard's worth on the quay.
  function City:storeRoom(key)
    local yards = #self.g:nodesOfKind("dc")
    local cap = yards > 0 and yards * City.yardStock or City.IMPORT.quayStock
    return math.max(0, cap - self:materialStock(key) - self:shippedUnits(key) - (self.inlandUnits and self:inlandUnits(key) or 0))
  end

  function City:shipmentCost(havenId, key, units)
    local n = self.g.nodes[havenId]
    local price = n and self:importPrice(key, n.haven)
    return price and math.ceil(price * units) or nil
  end

  function City:shipmentError(havenId, key, units)
    local n = self.g.nodes[havenId]
    if not (n and n.alive and n.kind == "terminal") then return "order through a haven" end
    local ok = false
    for _, k in ipairs(self:importable()) do if k == key then ok = true end end
    if not ok then return "not for sale abroad" end
    if type(units) ~= "number" or units ~= units or units < 1 then return "order at least one" end
    if units > self:storeRoom(key) then return "no room in the yards" end
    if self:shipmentCost(havenId, key, units) > self.money then return "not enough cash" end
    return nil
  end

  -- The yard a haven's orders go on to unless an order says otherwise. Kept
  -- on the haven, so it holds across days and saves; nil is the nearest yard
  -- there is a way to.
  function City:importYardOf(haven)
    local y = haven and haven.importYard and self.g.nodes[haven.importYard]
    return y and y.alive and y.kind == "dc" and y or nil
  end

  function City:setImportYard(havenId, yardId)
    local haven = self.g.nodes[havenId]
    if not (haven and haven.alive and haven.kind == "terminal") then return nil, "choose a haven" end
    if yardId then
      local y = self.g.nodes[yardId]
      if not (y and y.alive and y.kind == "dc") then return nil, "choose a yard" end
    end
    haven.importYard = yardId
    return haven
  end

  -- `yardId`: the yard it is hauled on to; the haven's own choice when left
  -- out, and the nearest when the haven has none.
  function City:orderImport(havenId, key, units, yardId)
    units = math.floor(units or 0)
    local why = self:shipmentError(havenId, key, units)
    if why then return nil, why end
    local cost = self:shipmentCost(havenId, key, units)
    self:spend(cost)
    self.shipments = self.shipments or {}
    local yard = yardId and self.g.nodes[yardId] or self:importYardOf(self.g.nodes[havenId])
    local o = { haven = havenId, key = key, units = units, cost = cost, day = self.day, arrive = self.day + City.IMPORT.leadDays,
      yard = yard and yard.alive and yard.kind == "dc" and yard.id or nil }
    self.shipments[#self.shipments + 1] = o
    self:note("Ordered %d %s for $%d: lands tomorrow", units, string.lower(Graph.COMMODITIES[key].name), cost)
    return o
  end

  -- Orders due today land in the stock. A haven demolished in the meantime
  -- still lands its cargo: it was paid for and is already at sea.
  -- `today`: the morning they land (the close passes tomorrow's date). Returns
  -- what landed and what hauling it inland cost.
  function City:landShipments(today)
    today = today or self.day
    local landed, keep, haulage = {}, {}, 0
    self.landings = {}
    for _, o in ipairs(self.shipments or {}) do
      if o.arrive <= today then
        landed[o.key] = (landed[o.key] or 0) + o.units
        self.landings[#self.landings + 1] = { haven = o.haven, key = o.key, units = o.units, day = today }
        self:note("Landed %d %s", o.units, string.lower(Graph.COMMODITIES[o.key].name))
        -- On to the yards; with none, the quay is the store.
        local cv = self:haulInland(o.haven, o.key, o.units, today, o.yard)
        haulage = haulage + (cv and cv.cost or 0)
      else
        keep[#keep + 1] = o
      end
    end
    self.shipments = keep
    return landed, haulage
  end

  -- What one haven has on the way, and what it landed this morning, by good.
  function City:havenShipments(havenId)
    local coming, landed = {}, {}
    for _, o in ipairs(self.shipments or {}) do
      if o.haven == havenId then coming[o.key] = (coming[o.key] or 0) + o.units end
    end
    for _, o in ipairs(self.landings or {}) do
      if o.haven == havenId and o.day == self.day then landed[o.key] = (landed[o.key] or 0) + o.units end
    end
    return coming, landed
  end
end
