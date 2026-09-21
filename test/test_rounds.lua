package.path = 'src/?.lua;' .. package.path
local Rounds = require('rounds')
local Bot = require('rounds_bot')
local D = Rounds.D
local checks = 0
local function check(v, m) assert(v, m); checks = checks + 1 end

-- The map is the seed's, whoever asks.
do
  local a, b = Rounds.new({ seed = 11 }), Rounds.new({ seed = 11 })
  check(#a.zones == #D.ZONES and #a.springs >= 5, 'a map has every zone and enough springs')
  for i, z in ipairs(a.zones) do
    check(z.x == b.zones[i].x and z.y == b.zones[i].y, 'zones come from the seed alone')
    check(not a:onRiver(z.x, z.y, z.r * 0.5), 'no zone sits in the river')
  end
  local west = 0
  for _, s in ipairs(a.springs) do
    check(not a:rockAt(s.x, s.y) and not a:onRiver(s.x, s.y), 'springs are on open ground')
    if s.x < a:riverX(s.y) then west = west + 1 end
  end
  check(west >= 2, 'the first zone has water on its own bank')
end

-- Each round has more houses than the last, and a round is fixed in advance.
do
  for r = 2, 60 do check(Rounds.houseCount(r) > Rounds.houseCount(r - 1), 'rounds grow') end
  local run = Rounds.new({ seed = 5 })
  local p1 = run:plan(12)
  run.planCache = nil
  run:build('junction', run.zones[1].x, run.zones[1].y)
  local p2 = run:plan(12)
  check(#p1.houses == #p2.houses, 'building does not change the round')
  for i, h in ipairs(p1.houses) do
    check(h.x == p2.houses[i].x and h.kind == p2.houses[i].kind, 'houses land where the plan said')
    check(run.zones[h.zone].opens <= 12, 'houses only land in open zones')
  end
  check(run:plan(10).boss and not run:plan(11).boss, 'every tenth round is a boss round')
end

-- Build rules.
do
  local run = Rounds.new({ seed = 7 })
  local z = run.zones[1]
  check(run:build('well', z.x, z.y) == nil, 'a well needs a spring')
  local s = run.springs[1]
  local w = run:build('well', s.x + 10, s.y - 5)
  check(w and w.x == s.x and w.y == s.y, 'a well snaps onto its spring')
  local _, err = run:build('well', s.x, s.y)
  check(err, 'one well per spring')
  local j = run:build('junction', z.x, z.y)
  check(j, 'a junction goes anywhere open')
  local cash = run.money
  local p = run:layPipe(w.id, j.id, 4)
  if not p then p = run:layPipe(w.id, j.id, 3) end
  check(p and run.money < cash, 'a main costs money')
  check(run:layPipe(w.id, j.id, 1) == nil, 'two buildings are joined once')
  -- Refunds: full in the same break, a share after a round.
  check(run:refund(p) == p.paid, 'a main bought this break refunds in full')
  run.round = run.round + 1
  check(run:refund(p) == math.floor(p.paid * D.SELL_BACK), 'after a round it sells at the usual share')
  for _ = 1, 4 do run.money = 1e6; run:upgrade(w.id) end
  check(w.level == run:maxLevel(w) and w.level <= run.springs[w.spring].depth, 'a shallow spring caps its well')
end

-- The round: coverage, capacity and arrival order.
do
  local run = Rounds.new({ seed = 7 })
  run.money = 1e6
  local s, z = run.springs[1], run.zones[1]
  local w = run:build('well', s.x, s.y)
  local j = run:build('junction', z.x, z.y)
  check(run:layPipe(w.id, j.id, 1) or run:layPipe(w.id, j.id, 2) or run:layPipe(w.id, j.id, 3), 'joined')
  run.phase = 'round'
  run.roundLog = { dry = 0, lost = 0, delivered = 0, served = 0 }
  local function house(x, y, demand)
    run.houses[#run.houses + 1] = { kind = 'house', zone = 1, x = x, y = y, demand = demand }
  end
  run.houses, run.arrived = {}, 0
  house(z.x + 5, z.y, 4)          -- in the ring
  house(z.x + 1000, z.y + 1000, 1) -- nowhere near a ring
  house(z.x - 5, z.y, 20)         -- more than the well gives
  local lives = run.lives
  local h1 = run:arrive(); check(h1.served, 'a house in a ring on a watered network is served')
  local h2 = run:arrive(); check(h2.dry and h2.reason == 'no ring reaches it', 'outside every ring is dry')
  local h3 = run:arrive(); check(h3.dry, 'a house wanting more than is left goes dry')
  check(run.lives == lives - 21, 'a dry house costs its demand in lives')
  check(run.roundLog.delivered == 4, 'only served water counts')
end

-- A house in two rings is not a free main between them.
do
  local run = Rounds.new({ seed = 7 })
  run.money = 1e6
  local s, z = run.springs[1], run.zones[1]
  local w = run:build('well', s.x, s.y)
  local a = run:build('junction', z.x - 60, z.y)
  local b = run:build('junction', z.x + 60, z.y)
  check(run:layPipe(w.id, a.id, 3) or run:layPipe(w.id, a.id, 4), 'fed')
  run.phase = 'round'
  run.roundLog = { dry = 0, lost = 0, delivered = 0, served = 0 }
  run.houses, run.arrived = {
    { kind = 'cottage', zone = 1, x = z.x, y = z.y, demand = 1 },
    { kind = 'house', zone = 1, x = b.x + 20, y = b.y + 100, demand = 2 },
  }, 0
  check(run:arrive().served, 'the bridge house drinks')
  local far = run:arrive()
  check(far.dry, 'but carries nothing on to a junction with no main of its own')
end

-- Shocks do what they say.
do
  local run = Rounds.new({ seed = 7 })
  local s = run.springs[1]
  local w = run:build('well', s.x, s.y)
  check(run:supply() == D.BUILDINGS.well.output[1], 'supply is what the wells give')
  run.shocks = { drought = true }
  check(run:supply() == math.floor(D.BUILDINGS.well.output[1] * D.SHOCKS.drought.factor), 'drought cuts wells')
  run.shocks = nil
  local found
  for r = 8, 60 do
    local plan = run:plan(r); run.planCache = nil
    if plan.shocks.heatwave then
      found = true
      for _, h in ipairs(plan.houses) do
        check(h.demand == math.ceil(D.HOUSES[h.kind].demand * D.SHOCKS.heatwave.factor), 'a heatwave raises demand')
      end
      break
    end
  end
  check(found, 'heatwaves happen')
  check(w, 'built')
end

-- Saves carry the run and nothing the seed can rebuild.
do
  local run = Rounds.new({ seed = 21 })
  Bot.turn(run); Bot.turn(run); Bot.turn(run)
  local text = Rounds.serialize(run:pack())
  local copy = Rounds.unpack(Rounds.deserialize(text))
  check(copy.round == run.round and copy.money == run.money and copy.lives == run.lives, 'numbers round trip')
  check(#copy.buildings == #run.buildings and #copy.pipes == #run.pipes, 'the network round trips')
  check(copy.zones[3].x == run.zones[3].x, 'the map comes back from the seed')
  check(Rounds.deserialize('os.exit(1)') == nil, 'a save cannot run code')
  check(Rounds.unpack({ version = 99 }) == nil, 'an unknown save is refused')
end

-- Doing nothing loses; playing sensibly gets a long way.
do
  local idle = Rounds.new({ seed = 4 })
  for _ = 1, 40 do if not idle:playRound() then break end end
  check(idle.phase == 'lost' and idle.round < 12, 'an empty map loses early')
  local strict = Rounds.new({ seed = 4, strict = true })
  strict:startRound(); strict:arrive()
  check(strict.phase == 'lost', 'strict ends on the first dry house')
  local far, wins = 0, 0
  for seed = 1, 6 do
    local run = Rounds.new({ seed = seed })
    while run.phase ~= 'lost' and run.round <= D.FINAL_ROUND do
      if not Bot.turn(run) then break end
    end
    far = far + (run.round >= 25 and 1 or 0)
    wins = wins + (run.won and 1 or 0)
  end
  check(far >= 4, 'a careful player reaches round 25 on most maps')
  check(wins >= 1, 'forty rounds can be won')
end

print(string.format('rounds: %d checks passed', checks))
