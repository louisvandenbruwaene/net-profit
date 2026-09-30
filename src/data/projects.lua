-- Edit these values, then restart the game with make run. See EDITING.md.
--
-- Big projects: one of each per company, built where the player puts it on
-- owned ground. Each is a customer the company pays to create: a large, steady
-- demand that no house main can carry, and once it is fully supplied it draws
-- `attract` new offers round itself, one a close. Paybacks are slow on purpose.
local Data = {}

Data.PROJECTS = {
  { key = "hospital", name = "HOSPITAL", commodity = "water", demand = 18, rate = 11, patience = 5,
    price = 8000,  clients = 15, attract = 4 },
  { key = "college",  name = "COLLEGE",  commodity = "power", demand = 20, rate = 12, patience = 5,
    price = 11000, clients = 25, attract = 5 },
  { key = "stadium",  name = "STADIUM",  commodity = "beer",  demand = 16, rate = 20, patience = 5,
    price = 14000, clients = 35, attract = 4 },
  { key = "airport",  name = "AIRPORT",  commodity = "oil",   demand = 14, rate = 34, patience = 5,
    price = 22000, clients = 50, attract = 4 },
}

-- A project takes a main up to this size, where a house takes only small.
Data.PROJECT_MAIN = "large"

-- Referrals: a customer kept fully supplied for `every` closes in a row may
-- (`chance`) put a neighbour in touch, at most one a close, and the neighbour
-- offers `premium` over the going rate.
Data.REFERRAL = { every = 40, chance = 0.3, premium = 0.15, expires = 8 }

return Data
