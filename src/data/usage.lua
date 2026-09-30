-- Edit these values, then restart the game with make run. See EDITING.md.
--
-- A customer's contract is the most they may draw in a day, and what they pay
-- for. What they actually use each day is less: a share of the contract that
-- depends on who they are, the day of the week, the weather, and their own
-- mood. So a network sized for the average can sell more than it could ever
-- carry at once, and pays for it on a hot Saturday.
local Data = {}

-- Average share of the contract used on an ordinary day, by customer type.
Data.MEAN = {
  house = 0.62, estate = 0.66, home = 0.58, subscriber = 0.60,
  workshop = 0.72, factory = 0.80, pub = 0.64, market = 0.66,
  hospital = 0.80, college = 0.70, stadium = 0.55, airport = 0.78,
}
Data.DEFAULT_MEAN = 0.65

-- How far one customer strays from that on a given day, either way.
Data.SPREAD = 0.22

-- Day of the week, Monday first. Households use more at the weekend, trade
-- less; a stadium is busy on match days.
Data.WEEKDAYS = { "Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun" }
Data.WEEK = {
  home     = { 0.96, 0.96, 0.96, 0.98, 1.02, 1.14, 1.20 },
  business = { 1.06, 1.06, 1.06, 1.06, 1.04, 0.78, 0.66 },
  stadium  = { 0.70, 0.70, 0.90, 0.70, 0.95, 1.60, 1.40 },
}
Data.BUSINESS = { workshop = true, factory = true, market = true, college = true, airport = true }

-- The weather, drawn once per day from the company's seed, so it can be
-- forecast. `p` is how often it comes up; the rest is what it does to each trade.
Data.WEATHER = {
  { key = "mild", p = 0.45, water = 1.00, power = 1.00, beer = 1.00 },
  { key = "hot",  p = 0.20, water = 1.30, power = 1.08, beer = 1.25 },
  { key = "cold", p = 0.20, water = 0.90, power = 1.28, beer = 0.90 },
  { key = "wet",  p = 0.15, water = 0.82, power = 1.06, beer = 0.95 },
}

-- How many days ahead the weather is known.
Data.FORECAST_DAYS = 3

return Data
