-- Edit these values, then restart the game with make run. See EDITING.md.
local Data = {}

-- Supply shocks. Unlike a market event they change what the ground gives, not
-- what a customer pays, and they land on every company the same way: through
-- the wells and mains it already has. A network with a spare route or a spare
-- well rides one out; one built as a single chain does not.
--
--   output  fraction of a source's output that survives, for `days` days
--   ground  a one-off: mains near a point crack, each with chance `hit`
Data.SHOCKS = {
  { key = "drought",    commodity = "water", output = 0.55, days = 4,
    head = "Drought: wells at half yield" },
  { key = "brownout",   commodity = "power", output = 0.60, days = 3,
    head = "Grid fault: generators at 60%" },
  { key = "subsidence", ground = true, radius = 330, hit = 0.55, days = 1,
    head = "Ground shift: mains crack" },
}

-- A small company must not be killed by bad luck, so nothing lands before this
-- many customers, and never more often than the chance below per day.
Data.SHOCK_CLIENTS = 6
Data.SHOCK_FROM = 8
Data.SHOCK_CHANCE = 0.10

-- Secure contracts: a customer who pays more and forgives less.
--   share     percent of new offers that come as secure ones
--   rate      multiple of the going rate they pay
--   credit    what a short day refunds, as a multiple of the missing revenue
--   patience  days of shortfall before they walk away
Data.SECURE = { clients = 8, share = 22, rate = 1.40, credit = 1.0, patience = 2 }

-- The worst single failure, as a share of daily revenue lost, and its grade.
Data.GRADES = {
  { 0.05, "A" }, { 0.15, "B" }, { 0.30, "C" }, { 0.50, "D" }, { 1.01, "F" },
}

-- How many structures and mains a resilience check will fail one at a time,
-- busiest first. Every one costs a flow solve.
Data.CHECK_LIMIT = 80

return Data
