-- Edit these values, then restart the game with make run. See EDITING.md.
local Data = {}

Data.PEOPLE = {
  -- Signed customers before a district counts as somewhere people live, and
  -- how many people each one is worth once it is supplied.
  settleAt = 3,
  perCustomer = 70,
  -- The most a district can hold, by ring: the old city is dense, the frontier
  -- is not. A city generated with people already in it can grow past this.
  ceiling = { 1400, 950, 650, 450 },
  growth = 0.12,
  decline = 0.04,

  tripAt = 40,
  tripsPerCapita = 0.03,
  workReach = 3,
  leisureShare = 0.35,
  -- What a trip is worth to the person taking it: the most they will pay in
  -- tolls, fares and petrol before they stay at home.
  work = { base = 2, perKm = 2.2 },
  leisure = { base = 5, perKm = 3.5 },

  carShare = 0.25,
  carShareMax = 0.85,
  peoplePerCar = 3,
  carWear = 0.01,
  carPrice = 70,

  fuelPerKm = 0.5,
  pumpPrice = 3,
  priceSensitivity = 0.15,
  stationTank = 30,
  stationUpkeep = 5,

  roadRange = 2000,
  roadCapacity = 400,
  roadTiein = 90,
  roadPerM = 0.20,
  roadUpkeep = 2,
  roadUpkeepPerM = 0.002,
  tollDefault = 1,
  tollMax = 12,

  resortPull = 3000,
  resortSpend = 6,
  resortLevels = 4,
  resortBase = 3000,
  resortGrowth = 1.6,
  resortUpkeep = 40,

  maxVehicles = 8,
}

Data.ROUTES = {
  bus   = { name = "BUS ROUTE", seats = 40,  vehicle = 240,  running = 16,  fare = 3,  max = 12, needs = "road",
            colour = { 0.96, 0.78, 0.30 },
            blurb = "Seats on a road you already have: cheap, short, and it takes the people who do not drive." },
  ferry = { name = "FERRY",     seats = 120, vehicle = 1400, running = 55,  fare = 6,  max = 20, needs = "water",
            colour = { 0.42, 0.72, 0.96 },
            blurb = "Calls at the coast, the river and the islands, once there is a harbour." },
  air   = { name = "AIRLINE",   seats = 60,  vehicle = 3200, running = 150, fare = 22, max = 60, needs = "air",
            colour = { 0.86, 0.62, 0.98 },
            blurb = "Between two air freight aprons, at a fare only a long trip will pay." },
}

return Data
