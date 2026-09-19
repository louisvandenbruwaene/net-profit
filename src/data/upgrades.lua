-- Edit these values, then restart the game with make run. See EDITING.md.
--
-- A building is bought once and then grown. Every family below is one building
-- with four levels, and a new one always starts at level 1. What a level
-- gives is exactly what it lists:
--   ports       mains that can be tied in
--   throughput  most it can pass in a day (the flow solver's node arc)
--   reach       fraction added to how far a cable or pipe from it may run
--   radius      metres a hub serves customers over
-- `cost` is a number, or a table by kind when the kinds differ in price.
-- `clients` is how many signed customers the company needs before it is
-- allowed the level, so the strong versions arrive with the company.
local Data = {}

-- Which family a building kind belongs to.
Data.FAMILY = {
  junction = "fitting", manifold = "fitting",
  pole = "tower", pylon = "tower", hvtower = "tower",
  exchange = "hub",
  pump = "pump",
}

Data.NAMES = {
  fitting = { "T split", "Hub", "Large hub", "Interchange hub" },
  tower   = { "Basic", "Standard", "Reinforced", "Grid node" },
  hub     = { "Depot office", "District hub", "Regional hub", "Metro hub" },
  pump    = { "Pump", "Booster pump", "Pumping station", "Main station" },
}

-- Level a building of this kind already is when a save from before levels
-- loads. Set so that nothing it could do is taken away: the stats a level
-- gives never lower what the building already has.
Data.LEGACY = { junction = 1, manifold = 2, pole = 2, pylon = 2, hvtower = 2,
                exchange = 3, pump = 1 }
-- A manifold cannot be level 1, whatever its record says.
Data.MIN_LEVEL = { manifold = 2 }

-- Throughput of a tower scales with the voltage it carries.
Data.TOWER_SCALE = { pole = 1, pylon = 2, hvtower = 4 }

Data.LEVELS = {
  fitting = {
    { ports = 3,  throughput = 60 },
    { ports = 6,  throughput = 140, cost = 48,  clients = 0 },
    { ports = 8,  throughput = 300, cost = 150, clients = 6 },
    { ports = 10, throughput = 999, cost = 420, clients = 14 },
  },
  tower = {
    { ports = 3, throughput = 40,   reach = 0 },
    { ports = 4, throughput = 90,   reach = 0.10, cost = { pole = 90,  pylon = 230,  hvtower = 560 },  clients = 0 },
    { ports = 6, throughput = 200,  reach = 0.20, cost = { pole = 240, pylon = 620,  hvtower = 1500 }, clients = 8 },
    { ports = 8, throughput = 9999, reach = 0.35, cost = { pole = 560, pylon = 1400, hvtower = 3400 }, clients = 16 },
  },
  hub = {
    { ports = 4,  throughput = 150, radius = 450 },
    { ports = 6,  throughput = 300, radius = 580, cost = 1500, clients = 8 },
    { ports = 10, throughput = 999, radius = 700, cost = 3300, clients = 14 },
    { ports = 14, throughput = 999, radius = 900, cost = 6800, clients = 24 },
  },
  pump = {
    { ports = 2, throughput = 80,  reach = 0 },
    { ports = 2, throughput = 200, reach = 0.25, cost = 120, clients = 0 },
    { ports = 2, throughput = 500, reach = 0.50, cost = 340, clients = 8 },
    { ports = 2, throughput = 999, reach = 1.00, cost = 900, clients = 16 },
  },
}

return Data
