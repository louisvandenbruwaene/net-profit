-- Edit these values, then restart the game with make run. See EDITING.md.
--
-- Shops the company owns, on the streets between plots. Every day people walk
-- each street; each one passing an open shop may go in, until the shop is full
-- for the day. A customer pays the shop's price and uses a little of what the
-- shop is supplied with, so a shop stands on the company's own networks.
local Data = {}

-- `levels` is the most customers a day at each level, `levelCost` what each
-- expansion costs, `attract` the chance a passer-by goes in at the base price,
-- `needs` what one customer uses, `clients` the customers the company needs
-- before the shop is offered.
Data.SHOPS = {
  { key = "cafe",     name = "CAFE",     cost = 900,  upkeep = 6,  price = 4,  attract = 0.22,
    levels = { 25, 40, 60, 90 },   levelCost = { 0, 700, 1400, 2600 },  needs = { water = 0.2 },  clients = 6 },
  { key = "bakery",   name = "BAKERY",   cost = 1200, upkeep = 8,  price = 3,  attract = 0.30,
    levels = { 30, 50, 75, 110 },  levelCost = { 0, 800, 1600, 3000 },  needs = { water = 0.15, power = 0.15 }, clients = 10 },
  { key = "boutique", name = "BOUTIQUE", cost = 2400, upkeep = 12, price = 14, attract = 0.07,
    levels = { 10, 16, 24, 35 },   levelCost = { 0, 1200, 2400, 4200 }, needs = { power = 0.2 },  clients = 18 },
  { key = "cinema",   name = "CINEMA",   cost = 5200, upkeep = 25, price = 9,  attract = 0.10,
    levels = { 40, 70, 100, 150 }, levelCost = { 0, 2600, 5000, 9000 }, needs = { power = 0.4 },  clients = 28 },
}

-- Residents by customer type: who lives or works in a building and so walks
-- the streets round it.
Data.RESIDENTS = {
  house = 3, estate = 9, home = 3, subscriber = 2, workshop = 5, factory = 12, pub = 6, market = 8,
  hospital = 40, college = 60, stadium = 0, airport = 50,
}
Data.OUTINGS = 0.8     -- walks a day per resident, on each street within reach
Data.REACH = 320       -- how far from home a resident walks to a street
Data.STREET = 80       -- a shop must stand this close to a street
Data.SENSITIVITY = 0.6 -- each 100% over the base price takes this share off the chance to go in
Data.SPREAD = 0.15     -- a street's day-to-day wobble, either way
Data.WEEK = { 0.90, 0.90, 0.92, 0.95, 1.10, 1.35, 1.25 }
Data.WEATHER = { mild = 1.00, hot = 1.15, cold = 0.80, wet = 0.65 }
Data.MATCH = 260       -- extra walkers on the streets round a stadium, times its day's crowd
Data.BENCH = { cost = 150, reach = 90, boost = 0.5 }

return Data
