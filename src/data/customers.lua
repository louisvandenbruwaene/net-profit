-- Edit these values, then restart the game with make run. See EDITING.md.
local Data = {}

Data.CLIENTS = {
  house   = { name = "HOUSE",   commodity = "water", demand = {2, 4}, rate = 4,  patience = 3, weight = 10 },
  estate  = { name = "ESTATE",  commodity = "water", demand = {5, 7}, rate = 6,  patience = 2, weight = 3 },
  workshop= { name = "WORKSHOP",commodity = "power", demand = {3, 5}, rate = 10, patience = 2, weight = 7 },
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

return Data
