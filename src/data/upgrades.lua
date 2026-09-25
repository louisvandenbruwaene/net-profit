-- Edit these values, then restart the game with make run. See EDITING.md.
--
-- A building is bought once and then grown. Every family below is one building
-- with four levels, and a new one always starts at level 1. What a level
-- gives is exactly what it lists:
--   ports       mains that can be tied in
--   throughput  most it can pass in a day (the flow solver's node arc)
--   reach       fraction added to how far a cable or pipe from it may run
--   radius      metres a distribution hub looks after
--   store       units a storage building holds, and `fill` how many a day go in
-- `cost` is a number, or a table by kind when the kinds differ in price.
-- `clients` is how many signed customers the company needs before it is
-- allowed the level, so the strong versions arrive with the company.
local Data = {}

-- Which family a building kind belongs to.
Data.FAMILY = {
  junction = "fitting", manifold = "fitting",
  pole = "tower", pylon = "tower", hvtower = "tower",
  pump = "pump",
  depot = "storage",
}

Data.NAMES = {
  fitting = { "T split", "Hub", "Large hub", "Distribution hub" },
  tower   = { "Basic", "Standard", "Reinforced", "Grid node" },
  pump    = { "Pump", "Booster pump", "Pumping station", "Main station" },
  storage = { "Tank", "Cistern", "Reservoir", "Water tower" },
}

-- One line under the name, so every level says what it is for.
Data.BLURBS = {
  fitting = {
    "Joins three mains. Upgrade it when you need more.",
    "Six connections, and more flow through it.",
    "Eight connections for a busy crossroads.",
    "Runs its neighbourhood: signs offers, connects them and widens full mains for every customer inside its range who pays your minimum price.",
  },
  storage = {
    "Keeps spare supply for a short day.",
    "Holds more, and takes more in each day.",
    "A day's worth of a small town.",
    "Holds a district's water and refills fast.",
  },
}

-- Level a building of this kind already is when a save from before levels
-- loads. Set so that nothing it could do is taken away: the stats a level
-- gives never lower what the building already has.
Data.LEGACY = { junction = 1, manifold = 2, pole = 2, pylon = 2, hvtower = 2,
                pump = 1, depot = 1 }
-- A manifold cannot be level 1, whatever its record says.
Data.MIN_LEVEL = { manifold = 2 }

-- Throughput of a tower scales with the voltage it carries.
Data.TOWER_SCALE = { pole = 1, pylon = 2, hvtower = 4 }

Data.LEVELS = {
  fitting = {
    { ports = 3,  throughput = 60 },
    { ports = 6,  throughput = 140, cost = 48,   clients = 0 },
    { ports = 8,  throughput = 300, cost = 150,  clients = 6 },
    { ports = 10, throughput = 999, cost = 1200, clients = 12, radius = 600 },
  },
  tower = {
    { ports = 3, throughput = 40,   reach = 0 },
    { ports = 4, throughput = 90,   reach = 0.10, cost = { pole = 90,  pylon = 230,  hvtower = 560 },  clients = 0 },
    { ports = 6, throughput = 200,  reach = 0.20, cost = { pole = 240, pylon = 620,  hvtower = 1500 }, clients = 8 },
    { ports = 8, throughput = 9999, reach = 0.35, cost = { pole = 560, pylon = 1400, hvtower = 3400 }, clients = 16 },
  },
  pump = {
    { ports = 2, throughput = 80,  reach = 0 },
    { ports = 2, throughput = 200, reach = 0.25, cost = 120, clients = 0 },
    { ports = 2, throughput = 500, reach = 0.50, cost = 340, clients = 8 },
    { ports = 2, throughput = 999, reach = 1.00, cost = 900, clients = 16 },
  },
  storage = {
    { ports = 3, throughput = 999, store = 100,  fill = 100 },
    { ports = 3, throughput = 999, store = 250,  fill = 200,  cost = 160,  clients = 0 },
    { ports = 4, throughput = 999, store = 600,  fill = 400,  cost = 480,  clients = 8 },
    { ports = 6, throughput = 999, store = 1500, fill = 900,  cost = 1300, clients = 16 },
  },
}

-- What a distribution hub does once a day, and what it costs to keep.
Data.DISTRIBUTION = {
  radius = 600,   -- metres it looks after
  floor = 5,      -- the minimum price a new one starts at, $ a unit
  floorStep = 1,  -- the minimum price moves in whole dollars
  perDay = 6,     -- most connections, and most widened mains, it does in a day
  upkeep = 10,    -- $ a day
}

-- Well depth is its own ladder of six, named so it reads as one building growing.
Data.WELL_NAMES = { "Hand well", "Well", "Deep well", "Borehole", "Deep borehole", "Aquifer station" }

return Data
