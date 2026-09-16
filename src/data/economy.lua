-- Edit these values, then restart the game with make run. See EDITING.md.
local Data = {}

Data.price = {
  junction = 22, manifold = 46, pump = 38, tower = 92, gate = 30, depot = 190,
  -- A hub is not a bigger junction: it is a whole neighbourhood's last mile,
  -- bought outright and never drawn. It is priced like the business it
  -- replaces, not like the pipe fitting it resembles.
  exchange = 1400, dc = 1500,
  terminal = 2200,
  stop = 120, station = 260, resort = 4800,
  powerLicence = 340, beerLicence = 600, oilLicence = 1500, foodLicence = 900,
  internetLicence = 2400,
  qualityBase = 140,
  ads = 90,
}

Data.trade = {
  water = {
    tiein = 14, trench = 0.11, bore = 7, borePerM = 0.028,
    repairBase = 14, repairPerLost = 6, repairPerM = 0.030,
    liningRate = 0.40, armourRate = 0.72,
    upkeep = 0.30, upkeepPerM = 0.0016,
    sourceBase = 260, sourceGrowth = 1.55, sourceOutput = 20,
    upgradeBase = 140, upgradeGrowth = 1.8, upgradeStep = 10,
    wholesale = 12, wholesalePerUnit = 0.55, sourceUpkeep = 6,
    importCost = 1.2,
  },
  -- Electricity sits between water and beer: cables are dearer than a water
  -- trench and cheaper than a sanitary beer main, and a workshop pays more than
  -- a household and less than a pub. It is the first trade worth expanding into.
  -- Electricity is the one trade nobody can land at a haven: it has to be
  -- generated inside the city. A reactor is priced the way a reactor is -- an
  -- enormous cheque, a standing crew whether it runs or not, and fuel so cheap
  -- per unit that the marginal cost of the next megawatt is nearly nothing.
  power = {
    tiein = 20, trench = 0.16, bore = 10, borePerM = 0.038,
    repairBase = 22, repairPerLost = 9, repairPerM = 0.044,
    liningRate = 0.40, armourRate = 0.72,
    upkeep = 0.45, upkeepPerM = 0.0023,
    sourceBase = 3600, sourceGrowth = 1.35, sourceOutput = 45,
    upgradeBase = 1400, upgradeGrowth = 1.42, upgradeStep = 12,
    wholesale = 18, wholesalePerUnit = 0.90, sourceUpkeep = 52,
    fuelPerUnit = 0.55,
    importCost = nil,
  },
  beer = {
    tiein = 26, trench = 0.21, bore = 13, borePerM = 0.050,
    repairBase = 30, repairPerLost = 13, repairPerM = 0.060,
    liningRate = 0.40, armourRate = 0.72,
    upkeep = 0.60, upkeepPerM = 0.0030,
    sourceBase = 420, sourceGrowth = 1.38, sourceOutput = 10,
    upgradeBase = 300, upgradeGrowth = 1.50, upgradeStep = 3,
    wholesale = 26, wholesalePerUnit = 1.30, sourceUpkeep = 11,
    importCost = 5.5,
  },
  oil = {
    tiein = 44, trench = 0.34, bore = 21, borePerM = 0.085,
    repairBase = 52, repairPerLost = 21, repairPerM = 0.105,
    liningRate = 0.40, armourRate = 0.72,
    upkeep = 1.00, upkeepPerM = 0.0050,
    sourceBase = 900, sourceGrowth = 1.38, sourceOutput = 10,
    upgradeBase = 620, upgradeGrowth = 1.50, upgradeStep = 3,
    wholesale = 44, wholesalePerUnit = 2.20, sourceUpkeep = 17,
    importCost = 9.0,
  },
}

Data.rules = {
  linkRange = 300,
  pumpRange = 520,
  minSpacing = 46,
  leakBase = 0.07,          -- per pipe per day, before quality and grade
  qualityStep = 0.13,       -- each quality level removes this fraction
  adDays = 5,
  adBoost = 0.25,
  arriveBase = 0.14,
  -- How much of the per metre bore charge survives the square root. Tuned so a
  -- capacity three stub costs about what it always did and a capacity thirty
  -- trunk costs a third of what it used to.
  boreScale = 2.7,
  investDays = 7,
  investMean = 0.10,
  investSd = 0.05,
  sourceIncome = 12,        -- wholesale, per well per day
  repLoss = 8,
  repDecline = 1,
  repIgnored = 2,
  -- A well answers to a trunk main now, so the opening is a well, a junction,
  -- the trunk into it, a stub on to the first house, and still a little room:
  -- four purchases where there used to be two, not two purchases stretched.
  startMoney = 750,
}

Data.loanRate = 0.10          -- per week, on the outstanding balance

Data.loanRatio = 0.50         -- of collateral

Data.salvage = 0.3

Data.crewWage = 14

Data.crewHire = 340

Data.crewMax = 4

return Data
