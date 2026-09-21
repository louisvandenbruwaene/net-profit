-- Rounds mode: every number the mode is balanced on. Edit, then restart the
-- game. Building prices are the company game's own (data/economy.lua,
-- data/pipes.lua, data/upgrades.lua); only what a round pays and demands lives
-- here. See src/rounds.lua for what each one does.
local D = {}

D.START = { money = 2600, lives = 100, strictLives = 1 }
D.FINAL_ROUND = 40

-- Districts open as zones in this order, the first in round one. Houses only
-- ever land in an open zone. Ids are the authored districts of the company map
-- (4 by 3, Millbrook in the middle at 6), walked outward from the start.
D.ZONE_ORDER = { 6, 7, 2, 5, 10, 3, 11, 1, 8, 9, 12, 4 }
D.ZONE_OPENS = { 1, 4, 8, 12, 16, 20, 24, 28, 32, 35, 38, 40 }

-- Houses. The kinds are the company's own customers; `demand` overrides theirs
-- so a round reads the same every time, and a dry house costs that many lives.
D.HOUSES = {
  { key = "cottage", client = "house",  name = "COTTAGE",     demand = 2, from = 1 },
  { key = "house",   client = "house",  name = "HOUSE",       demand = 3, from = 3 },
  { key = "terrace", client = "house",  name = "TERRACE",     demand = 4, from = 9 },
  { key = "estate",  client = "estate", name = "ESTATE",      demand = 6, from = 15 },
  -- The boss: a block every tenth round, big enough to need a main of its own.
  { key = "block",   client = "estate", name = "TOWER BLOCK", demand = 24, boss = true },
}
D.BOSS_EVERY = 10
-- A house keeps clear of the district's edge by this much.
D.EDGE = 50
-- The share of houses that land anywhere in their zone. The rest gather
-- towards the middle.
D.SPREAD = 0.5

-- Money, paid at the end of a round. A round is worth a few company days: the
-- houses only stay for one.
D.PAY = {
  base = 320, perRound = 40,     -- the round's own cheque
  perUnit = 16,                  -- per unit of water delivered
  sparePerUnit = 4,              -- per unit of supply left over
  spareCap = { base = 80, perRound = 12 },
  streak = 40, streakMax = 5,    -- per clean round in a row
  upkeep = 1.0,                  -- rounds of company upkeep charged per round
}

-- Shocks, announced a round ahead. None before `from`.
D.SHOCKS = {
  drought  = { name = "DROUGHT",     from = 6,  chance = 0.16, output = 0.6,
               blurb = "Wells give 60% of their yield this round" },
  heatwave = { name = "HEATWAVE",    from = 9,  chance = 0.14, factor = 1.5,
               blurb = "Every house wants half as much again" },
  burst    = { name = "BURST MAINS", from = 7,  chance = 0.20,
               blurb = "Mains break when the round starts and stay broken until repaired" },
}
D.SHOCK_ORDER = { "drought", "heatwave", "burst" }

-- What the company game gates on customer count, Rounds gates on the most
-- houses served in one round. Automation hubs are the tool Rounds is played
-- with, so they are open from the start.
D.ALWAYS_OPEN = { hub = true }

return D
