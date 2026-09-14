-- Edit these values, then restart the game with make run. See EDITING.md.
local Data = {}

Data.FORMS = {
  liquid = {
    tiein = 26, trench = 0.21, bore = 13, borePerM = 0.050,
    repairBase = 30, repairPerLost = 13, repairPerM = 0.060,
    liningRate = 0.40, armourRate = 0.72,
    upkeep = 0.60, upkeepPerM = 0.0030,
  },
  energy = {
    tiein = 20, trench = 0.16, bore = 10, borePerM = 0.038,
    repairBase = 22, repairPerLost = 9, repairPerM = 0.044,
    liningRate = 0.40, armourRate = 0.72,
    upkeep = 0.45, upkeepPerM = 0.0023,
  },
  -- Fibre is cable carrying a signal rather than a current: cheaper to dig in
  -- than a power line, and it fouls just the same.
  data = {
    tiein = 18, trench = 0.13, bore = 9, borePerM = 0.034,
    repairBase = 18, repairPerLost = 7, repairPerM = 0.036,
    liningRate = 0.40, armourRate = 0.72,
    upkeep = 0.40, upkeepPerM = 0.0020,
  },
  -- Solids go by road, which is cheap to lay and dear to run, and short: a
  -- lorry route across three districts is a railway waiting to be built.
  solid = {
    tiein = 34, trench = 0.30, bore = 16, borePerM = 0.058,
    repairBase = 0, repairPerLost = 0, repairPerM = 0,
    upkeep = 0.95, upkeepPerM = 0.0042, noLeak = true, range = 300,
  },
}

Data.PIPE_SIZES = {
  { key = "small",  name = "SMALL",  cap = 7,  tiein = 1.0, trench = 1.0 },
  { key = "medium", name = "MEDIUM", cap = 15, tiein = 1.6, trench = 1.7 },
  { key = "large",  name = "LARGE",  cap = 25, tiein = 2.6, trench = 2.9 },
  -- A trunk for a company that already runs hubs and havens. Four large mains'
  -- worth of flow for well under four large mains' worth of digging.
  { key = "massive", name = "MASSIVE", cap = 100, tiein = 6.5, trench = 7.5, unlock = "massive" },
}

Data.SIZE_LIMIT = {
  client = { max = "small" },
  sink   = { max = "small" },
  source = { min = "large" },
  works  = { min = "large" },
}

Data.GRADES = {
  { name = "Bare",     risk = 1.00, repair = 1.00, decay = 1, cost = 1.00, price = 0 },
  { name = "Lined",    risk = 0.45, repair = 0.70, decay = 1, cost = 1.35, price = 900 },
  { name = "Armoured", risk = 0.12, repair = 0.45, decay = 2, cost = 1.95, price = 3200 },
  -- Sealed pipe is the end of the maintenance game. It is priced as such: the
  -- licence to lay it costs more than most of the network, and every metre of
  -- it costs three times bare pipe.
  { name = "Sealed",   risk = 0.02, repair = 0.30, decay = 3, cost = 3.20, price = 11000 },
}

Data.TIEIN = {
  source = 1.6, client = 1.0, junction = 0.7, manifold = 0.7,
  pump = 1.1, tower = 1.0, gate = 0.8, depot = 1.2,
}

return Data
