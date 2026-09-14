-- Edit these values, then restart the game with make run. See EDITING.md.
local Data = {}

Data.MODES = {
  rail    = { name = "RAILWAY",  order = 1, tiein = 240, perM = 0.52, perWagon = 120,
              haulPerUnit = 0.10, haulPerM = 0.00035, wagonCap = 40, range = 4000,
              needs = "land", colour = {0.72, 0.74, 0.80},
              blurb = "High build cost. Low daily cost. Good for long routes." },
  highway = { name = "HIGHWAY",  order = 2, tiein = 140, perM = 0.30, perWagon = 50,
              haulPerUnit = 0.55, haulPerM = 0.0022, wagonCap = 18, range = 2000,
              needs = "land", diesel = true, colour = {0.92, 0.80, 0.42},
              blurb = "Low build cost. High daily cost." },
  sea     = { name = "SHIPPING", order = 3, tiein = 520, perM = 0.08, perWagon = 150,
              haulPerUnit = 0.08, haulPerM = 0.00012, wagonCap = 90, range = 1e9,
              needs = "coast", diesel = true, colour = {0.40, 0.68, 0.92},
              blurb = "Low daily cost. Requires water access." },
  air     = { name = "AIR FREIGHT", order = 4, tiein = 680, perM = 0.10, perWagon = 90,
              haulPerUnit = 3.20, haulPerM = 0.0040, wagonCap = 10, range = 1e9,
              needs = "air", colour = {0.86, 0.62, 0.98},
              blurb = "High daily cost. Requires airports. One plane type per route." },
}

Data.rail = {
  tiein = 240, perM = 0.52, bore = 4, borePerM = 0.011,
  upkeep = 1.4, upkeepPerM = 0.0038, range = 1400,
  haulPerUnit = 0.18, haulPerM = 0.0016,
}

Data.GOODS = {
  food   = { importCost = 3.0,  wholesale = 22, wholesalePerUnit = 1.1, sourceUpkeep = 12 },
  wheat  = { importCost = 0.9,  wholesale = 10, wholesalePerUnit = 0.35, sourceUpkeep = 7,
             sourceBase = 620,  sourceGrowth = 1.30, sourceOutput = 14, upgradeBase = 240,
             upgradeGrowth = 1.4, upgradeStep = 4 },
  timber = { importCost = 1.1,  wholesale = 12, wholesalePerUnit = 0.4, sourceUpkeep = 8,
             sourceBase = 700,  sourceGrowth = 1.30, sourceOutput = 12, upgradeBase = 260,
             upgradeGrowth = 1.4, upgradeStep = 3 },
  ore    = { importCost = 1.8,  wholesale = 16, wholesalePerUnit = 0.6, sourceUpkeep = 12,
             sourceBase = 1100, sourceGrowth = 1.34, sourceOutput = 10, upgradeBase = 420,
             upgradeGrowth = 1.45, upgradeStep = 3 },
  rock   = { importCost = nil,  wholesale = 8,  wholesalePerUnit = 0.25, sourceUpkeep = 9,
             sourceBase = 820,  sourceGrowth = 1.30, sourceOutput = 12, upgradeBase = 300,
             upgradeGrowth = 1.4, upgradeStep = 3 },
  sand   = { importCost = 0.6,  wholesale = 7,  wholesalePerUnit = 0.22, sourceUpkeep = 7,
             sourceBase = 600,  sourceGrowth = 1.28, sourceOutput = 12, upgradeBase = 220,
             upgradeGrowth = 1.4, upgradeStep = 3 },
  salt   = { importCost = 1.3 },
  coke   = { importCost = 2.4 },
  malt   = { importCost = 2.2 },
  cement = { importCost = 1.7 },
  diesel = { importCost = 4.0 },
  steel  = { importCost = 7.0 },
  planks = { importCost = 3.2 },
  glass  = { importCost = 5.5 },
  concrete = { importCost = 2.8 },
  gasoline = { importCost = 4.5, wholesale = 20, wholesalePerUnit = 1.0, sourceUpkeep = 10 },
  rubber = { importCost = 2.6 },
}

Data.MATERIALS = {
  exchange = { steel = 10 },
  works    = { steel = 40, concrete = 20 },
  nuclear  = { steel = 120, concrete = 200 },
  wind     = { steel = 60, concrete = 40 },
  -- Rail is steel by the kilometre. A highway is tarmac, and takes none at
  -- all, which is what stops the whole thing deadlocking: the first steel a
  -- company ever sees comes off a ship and goes inland by road, because there
  -- is no railway yet and no way to build one.
  rail     = { steel = 12 },      -- per kilometre of line
  highway  = {},
  resort   = { concrete = 40, glass = 20 },
}

Data.yardStock = 400

Data.yardIntakeRate = 25

Data.HAVENS = {
  port     = { name = "HARBOUR",      gate = "coast", import = 1.00, price = 2200,
               blurb = "deep water berths on the coast" },
  highway  = { name = "ROAD HEAD",    gate = "land",  import = 1.20, price = 1700,
               blurb = "a trunk road interchange" },
  airfield = { name = "AIR FREIGHT",  gate = "land",  import = 1.55, price = 3400,
               blurb = "an air freight apron" },
}

Data.havenReach = 150

Data.terminalUpkeep = 26

Data.depotCapacity = 18

Data.depotFillRate = 8

Data.hub = {
  radius = 700,          -- how far the last mile reaches
  connect = 12,          -- one off, per customer picked up
  perClient = 0.35,      -- per customer per day, whatever they take
  upkeep = 6,            -- the hub itself, per day
  floorStep = 1,         -- the rate floor moves in whole dollars
}

return Data
