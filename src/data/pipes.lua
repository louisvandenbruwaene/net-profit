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

-- Sizes follow Murray's law, the small-vessel half of West/Brown/Enquist.
-- Minimising pumping power plus the cost of maintaining the fluid gives
-- Q ~ r^3, so cross-section, and with it the dig, the pipe and the fittings,
-- goes as Q^(2/3). That exponent is the whole economic case for branching:
-- doubling the flow costs 1.59 times the main, so one trunk that splits always
-- beats two mains laid side by side. `large` was already sitting on the curve
-- (2.90 against 2.924), so the ladder is anchored there. The price level
-- barely moves. Only the shape does.
--
-- `reach` is the other half of the physics. Pressure gradient goes as Q/r^4,
-- so at each size's design flow it falls as Q^(-1/3): a trunk carries further
-- between pumps than a stub does. That is what pays for the long run out to a
-- distant heart instead of sinking a well next to every customer.
-- Fittings are on the same curve as the dig, and for the same reason: a
-- flange is a piece of pipe wall, and there is Q^(2/3) of wall to pay for.
-- What makes a split cost something, and so stops a tree branching for ever,
-- is the price of the junction or manifold standing at it, not a surcharge
-- hidden in the fittings.
Data.PIPE_SIZES = {
  { key = "small",  name = "SMALL",  cap = 10,  tiein = 0.89, trench = 1.00, reach = 1.00 },
  { key = "medium", name = "MEDIUM", cap = 30,  tiein = 1.85, trench = 2.08, reach = 1.44 },
  { key = "large",  name = "LARGE",  cap = 50,  tiein = 2.60, trench = 2.92, reach = 1.71 },
  { key = "massive", name = "MASSIVE", cap = 100, tiein = 4.13, trench = 4.64, reach = 2.15, unlock = "massive" },
  -- The rung the measurement asked for. A quarter of the widest mains in a
  -- mature company were running full, and the flow arriving at them was 3.6
  -- times what the mains below carried where the pipe ladder only stepped up
  -- 1.9 times. Two hundred is what a works on a broad channel makes in a day,
  -- so this is the main that carries a heart's whole output in one trench.
  { key = "trunk", name = "TRUNK", cap = 200, tiein = 6.55, trench = 7.36, reach = 2.71, unlock = "trunk" },
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
