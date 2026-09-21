-- Rounds mode: every number the mode is balanced on. Edit, then restart the
-- game. See src/rounds.lua for what each one does.
local D = {}

D.MAP = { w = 2600, h = 1600 }

D.START = { money = 700, lives = 40, strictLives = 1 }
D.FINAL_ROUND = 40

-- What the player can build. Each building has four levels, bought in place.
-- `output` is water a day, `radius` is how far a service drop reaches from it,
-- `throughput` is what may pass through it, `ports` counts mains only.
D.BUILDINGS = {
  well = {
    name = "WELL", key = "1", onSpring = true,
    cost = { 150, 170, 300, 520 },
    output = { 12, 24, 40, 64 },
    ports = { 3, 4, 5, 6 },
    radius = { 70, 80, 90, 100 },
    blurb = "Sinks onto a spring. The only cheap water there is.",
  },
  junction = {
    name = "JUNCTION", key = "2",
    cost = { 60, 70, 130, 240 },
    throughput = { 14, 28, 50, 90 },
    ports = { 3, 4, 6, 8 },
    radius = { 125, 160, 200, 250 },
    blurb = "Serves every house inside its ring, and splits mains.",
  },
  tower = {
    name = "WATER TOWER", key = "3",
    cost = { 420, 300, 480, 760 },
    output = { 10, 20, 34, 52 },
    ports = { 2, 3, 3, 4 },
    radius = { 150, 170, 190, 210 },
    blurb = "Water anywhere, no spring needed, at four times the price.",
  },
}
D.ORDER = { "well", "junction", "tower" }

-- Mains. Capacity against price, with a reach past which a junction is needed.
D.PIPES = {
  { key = "small",   name = "SMALL",   cap = 6,  base = 18, perM = 0.10, reach = 330 },
  { key = "medium",  name = "MEDIUM",  cap = 15, base = 30, perM = 0.19, reach = 420 },
  { key = "large",   name = "LARGE",   cap = 30, base = 52, perM = 0.32, reach = 520 },
  { key = "massive", name = "MASSIVE", cap = 60, base = 95, perM = 0.55, reach = 620 },
}
-- Crossing the river is a bored crossing, priced per crossing and per size step.
D.RIVER_CROSSING = 110

-- Selling returns this share of everything a building or main has cost.
D.SELL_BACK = 0.7

-- Houses. `demand` is water a day, and a dry house costs that many lives.
D.HOUSES = {
  cottage = { name = "COTTAGE", demand = 1, from = 1 },
  house   = { name = "HOUSE",   demand = 2, from = 4 },
  terrace = { name = "TERRACE", demand = 3, from = 11 },
  estate  = { name = "ESTATE",  demand = 5, from = 18 },
  -- The boss: one block every tenth round, big enough to need its own main.
  block   = { name = "TOWER BLOCK", demand = 14 },
}
D.HOUSE_ORDER = { "cottage", "house", "terrace", "estate", "block" }
D.BOSS_EVERY = 10

-- Money. Paid at the end of a round, never during one.
D.PAY = {
  base = 120, perRound = 8,      -- the round's own cheque
  perUnit = 7,                   -- for every unit delivered
  sparePerUnit = 2,              -- for supply left over at the end
  spareCap = { base = 60, perRound = 6 },
  streak = 20, streakMax = 5,    -- per dry-free round in a row
}

-- Shocks, announced a round ahead. None before `from`.
D.SHOCKS = {
  drought  = { name = "DROUGHT",   from = 6,  chance = 0.16, factor = 0.7,
               blurb = "Wells give 70% of their output" },
  heatwave = { name = "HEATWAVE",  from = 9,  chance = 0.14, factor = 1.5,
               blurb = "Every house wants half as much again" },
  burst    = { name = "BURST MAINS", from = 8, chance = 0.18,
               blurb = "Mains break at the start of the round" },
}
D.SHOCK_ORDER = { "drought", "heatwave", "burst" }

-- Zones, in the order they open. Houses only ever spawn inside an open zone.
D.ZONES = {
  { name = "MILLBROOK",  opens = 1 },
  { name = "OLD TOWN",   opens = 3 },
  { name = "HILLCREST",  opens = 7 },
  { name = "THE FLATS",  opens = 12 },
  { name = "CANALSIDE",  opens = 17 },
  { name = "NORTHGATE",  opens = 23 },
  { name = "DEEPCUT",    opens = 30 },
}

D.SPRINGS = 8
D.ROCKS = 9

return D
