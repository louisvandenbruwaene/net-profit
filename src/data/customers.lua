-- Edit these values, then restart the game with make run. See EDITING.md.
local Data = {}

Data.CLIENTS = {
  house   = { name = "HOUSE",   commodity = "water", demand = {2, 4}, rate = 6,  patience = 3, weight = 10 },
  estate  = { name = "ESTATE",  commodity = "water", demand = {5, 7}, rate = 8,  patience = 2, weight = 3 },
  workshop= { name = "WORKSHOP",commodity = "power", demand = {3, 5}, rate = 10, patience = 2, weight = 7 },
  -- A household on the electricity grid. It takes low voltage, so it hangs off
  -- a low voltage pole rather than a standard tower.
  home    = { name = "HOME",    commodity = "power", demand = {1, 3}, rate = 6,  patience = 3,
              weight = 5, follows = "house" },
  pub     = { name = "PUB",     commodity = "beer",  demand = {2, 4}, rate = 16, patience = 2, weight = 6 },
  factory = { name = "FACTORY", commodity = "oil",   demand = {4, 6}, rate = 26, patience = 1, weight = 5 },
  -- A market is the shop end of the food chain: wheat becomes food becomes a
  -- queue of people who will pay for it.
  market  = { name = "MARKET",  commodity = "food",  demand = {3, 6}, rate = 9,  patience = 2, weight = 6 },
  -- A household that wants a line as well as a tap. A district that leans to
  -- houses leans to subscribers at half the rate.
  subscriber = { name = "SUBSCRIBER", commodity = "internet", demand = {1, 3}, rate = 14, patience = 2,
                 weight = 5, follows = "house" },
}

-- A household signs for one utility. Some of them, later, also want the other
-- one, and that is an offer they make rather than a condition of the first
-- contract: `share` is the fraction of households that ever ask, decided once
-- per building from the company's seed, and `daily` is how likely one of those
-- asks on any given day once the licence is held.
--
-- It was every household, every day, which made "a house" mean "a water main
-- and a cable" and made the second utility a chore rather than a decision.
Data.DUAL = { share = 0.35, daily = 0.22 }

return Data
