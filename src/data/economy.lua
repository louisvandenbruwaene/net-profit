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
  -- A licence is priced against what the trade costs to enter, not against
  -- the paper it is written on. Electricity was $340 in front of a $850
  -- generator and a transformer pole, which made it read as a cheap trinket
  -- and left companies holding a licence they could not yet use.
  powerLicence = 900, beerLicence = 600, oilLicence = 1500, foodLicence = 900,
  internetLicence = 2400,
  ads = 90,
}

-- Supply is priced so that a company grows one organ rather than scattering
-- many. `upgradeGrowth` now sits below `sourceGrowth` in every trade, which is
-- the inversion that makes deepening the cheaper unit of supply at the margin.
-- The two ladders interleave rather than one dominating outright, so the
-- settled answer is one deep source and two or three shallow ones, the way an
-- animal runs one heart and a pair of kidneys and not thirty of anything.
Data.trade = {
  water = {
    tiein = 14, trench = 0.11, bore = 7, borePerM = 0.028,
    repairBase = 14, repairPerLost = 6, repairPerM = 0.030,
    upkeep = 0.30, upkeepPerM = 0.0016,
    sourceBase = 260, sourceGrowth = 1.85, sourceOutput = 20,
    upgradeBase = 120, upgradeGrowth = 1.26, upgradeStep = 10,
    -- An intake is a treatment works, not a hole in a field: it costs three
    -- times a well to commission and its own ladder is steeper again, so the
    -- second one is a late luxury and the third is never the answer.
    intakeMult = 3.2, intakeGrowth = 2.6,
    -- A well costs its upkeep a day and a pumping cost for every unit it
    -- lifts. Nothing pays the well: customers are the only income.
    wholesale = 0, wholesalePerUnit = 0, sourceUpkeep = 4, extractPerUnit = 0.30,
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
    upkeep = 0.45, upkeepPerM = 0.0023,
    sourceBase = 3600, sourceGrowth = 1.35, sourceOutput = 45,
    upgradeBase = 1400, upgradeGrowth = 1.42, upgradeStep = 12,
    wholesale = 0, wholesalePerUnit = 0, sourceUpkeep = 52,
    fuelPerUnit = 0.55,
    importCost = nil,
  },
  beer = {
    tiein = 26, trench = 0.21, bore = 13, borePerM = 0.050,
    repairBase = 30, repairPerLost = 13, repairPerM = 0.060,
    upkeep = 0.60, upkeepPerM = 0.0030,
    sourceBase = 420, sourceGrowth = 1.55, sourceOutput = 10,
    upgradeBase = 210, upgradeGrowth = 1.22, upgradeStep = 4,
    wholesale = 0, wholesalePerUnit = 0, sourceUpkeep = 11, extractPerUnit = 1.0,
    importCost = 5.5,
  },
  oil = {
    tiein = 44, trench = 0.34, bore = 21, borePerM = 0.085,
    repairBase = 52, repairPerLost = 21, repairPerM = 0.105,
    upkeep = 1.00, upkeepPerM = 0.0050,
    sourceBase = 900, sourceGrowth = 1.55, sourceOutput = 10,
    upgradeBase = 430, upgradeGrowth = 1.22, upgradeStep = 4,
    wholesale = 0, wholesalePerUnit = 0, sourceUpkeep = 14, extractPerUnit = 1.6,
    importCost = 9.0,
  },
}

Data.rules = {
  linkRange = 300,
  pumpRange = 520,
  minSpacing = 46,
  leakBase = 0.07,          -- per pipe per day, before quality and grade
  adDays = 5,
  adBoost = 0.25,
  -- The chance of a request on a day that is not already promised one, before
  -- reputation adds its share. Odd days always bring one while the company is
  -- small, so the player is never left two closes in a row with nothing to do.
  arriveBase = 0.40,
  investDays = 7,
  investMean = 0.10,
  -- The spread of a settlement widens by investSdPerDay every day the company
  -- trades, and then stops where a total loss is investSdRuin deviations out.
  -- It has to stop somewhere: a payout cannot go below zero, so a spread wide
  -- enough to reach -100% quietly pays the player for the tail that gets
  -- clipped off. Four deviations puts that tail at about one settlement in
  -- thirty thousand, which is worth nothing to anybody.
  --
  -- What is left is a real gamble that an analyst makes worth taking. At the
  -- opening 10% mean the cap is 0.275, so a settlement loses money 36% of the
  -- time; one analyst carries the mean to 20% against a 0.30 spread and loses
  -- 25% of the time. An analyst costs $1,000 and $25/day -- $175 a cycle --
  -- and pays 10 points of mean, so it earns its wage on $1,750 invested and
  -- its hiring fee on the cycle after that.
  investSdPerDay = 0.01,
  investSdRuin = 4,
  repLoss = 12,
  repDecline = 1,
  repIgnored = 2,
  -- Earned at every close where every signed customer was fully supplied.
  repGain = 2,
  -- Requests a day at 100% reputation. The limit climbs in even steps from one
  -- at 50% reputation, so the drip becomes a stream rather than a flood.
  requestMax = 4,
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
