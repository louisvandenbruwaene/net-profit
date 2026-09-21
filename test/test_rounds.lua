package.path = 'src/?.lua;' .. package.path
local City = require('city')
local Save = require('company_save')
local Bot = require('rounds_bot')
local D = City.ROUNDS
local checks = 0
local function check(v, m) assert(v, m); checks = checks + 1 end

local function home(c) return c.districts[D.ZONE_ORDER[1]] end
local function spring(c, d)
  for _, dep in ipairs(c.deposits) do
    if dep.commodity == 'water' and c:districtAt(dep.x, dep.y) == d then return dep end
  end
end
-- A well, a hub in the middle of the first zone, and a main between them.
local function opening(c)
  local d = home(c)
  local dep = spring(c, d)
  local w = assert(c:buySource('water', dep.x, dep.y))
  local h = assert(c:build(d.x + d.w / 2, d.y + d.h / 2, 'exchange'))
  assert(c:layPipe(w.id, h.id, 'water', 'large'))
  return w, h
end

-- A run is a company city with rounds on it.
do
  local c = City.newRounds({ seed = 5 })
  check(c.rounds and c.rounds.round == 1 and c.rounds.lives == D.START.lives, 'a run starts at round one')
  check(#c:clientList() == 0, 'the company opening house is gone')
  check(c.money == D.START.money, 'a run starts with its own money')
  check(#c:zones() == 1 and home(c).owned, 'the first zone is open and held')
  check(c:unlocked('hub'), 'hubs are open from the start')
  check(not c:pendingLesson(), 'no company lessons in a run')
  local strict = City.newRounds({ seed = 5, strict = true })
  check(strict.rounds.lives == 1, 'strict has one life')
end

-- Each round has more houses than the last, and is fixed in advance.
do
  for r = 2, 60 do check(City.houseCount(r) > City.houseCount(r - 1), 'rounds grow') end
  local a, b = City.newRounds({ seed = 9 }), City.newRounds({ seed = 9 })
  opening(b)
  local pa, pb = a:roundPlan(12), b:roundPlan(12)
  check(#pa.houses == #pb.houses, 'building does not change a round')
  for i, h in ipairs(pa.houses) do
    check(h.kind == pb.houses[i].kind and h.fx == pb.houses[i].fx and h.zone == pb.houses[i].zone,
      'houses land where the plan said')
    check(a.districts[h.zone].zoneOpens <= 12, 'houses land only in open zones')
  end
  check(a:roundPlan(10).boss and not a:roundPlan(11).boss, 'every tenth round brings tower blocks')
end

-- A round: served inside a hub on a watered network, dry outside one.
do
  local c = City.newRounds({ seed = 5 })
  opening(c)
  local plan = c:startRound()
  check(plan and c.rounds.phase == 'round', 'a round starts')
  local marked = #c.g.nodes
  while c:pendingHouses() > 0 do c:roundArrive() end
  local served, dry = 0, 0
  for _, n in ipairs(c:roundHouses()) do
    if n.roundServed then
      served = served + 1
      check(c:fullyServed(n), 'an accepted house is fully served')
    else
      dry = dry + 1
      check(n.dryReason, 'a dry house says why')
    end
  end
  check(served + dry == #plan.houses, 'every planned house arrived')
  local result = c:finishRound()
  check(result and result.total > 0, 'a round pays')
  check(#c.g.nodes == marked, 'the houses leave with the round and take no room')
  check(c.rounds.round == 2 and c.rounds.phase == 'build', 'the next break begins')
end

-- A house no hub reaches goes dry and costs its demand in lives.
do
  local c = City.newRounds({ seed = 5 })
  local w, h = opening(c)
  c.g:killNode(h.id); c:refresh()
  local lives = c.rounds.lives
  c:startRound()
  local n = c:roundArrive()
  check(n.dry and n.dryReason == 'no hub reaches it', 'no hub, no water')
  check(c.rounds.lives == lives - n.demand, 'a dry house costs its demand in lives')
  check(w, 'built')
end

-- A hub with no main to water cannot serve.
do
  local c = City.newRounds({ seed = 5 })
  local d = home(c)
  c:build(d.x + d.w / 2, d.y + d.h / 2, 'exchange')
  c:startRound()
  local n = c:roundArrive()
  check(n.dry and n.dryReason == 'its hub is not joined to any water', 'a hub needs water behind it')
end

-- First come, first served: a later house cannot take an earlier one's water.
do
  local c = City.newRounds({ seed = 5 })
  local w = opening(c)
  c:startRound()
  local accepted = {}
  while c:pendingHouses() > 0 do
    local n = c:roundArrive()
    if n.roundServed then accepted[#accepted + 1] = n end
    for _, a in ipairs(accepted) do check(c:fullyServed(a), 'accepted houses stay served') end
  end
  check(w, 'built')
end

-- Nothing about a round changes the gates of the company game.
do
  local company = City.new({ seed = 5 })
  check(company:progress() == #company:clientList(), 'a company counts its customers')
  check(not company.rounds and not company:unlocked('hub'), 'a company still earns its hubs with customers')
end

-- Shocks.
do
  local c = City.newRounds({ seed = 5 })
  opening(c)
  local found
  for r = 7, 60 do
    local plan = c:roundPlan(r)
    if plan.shocks.heatwave then
      found = true
      for _, h in ipairs(plan.houses) do
        check(h.demand == math.ceil(City.ROUND_HOUSE[h.kind].demand * D.SHOCKS.heatwave.factor), 'a heatwave raises demand')
      end
      break
    end
  end
  check(found, 'heatwaves happen')
  -- A burst main stays broken after the round, until it is repaired.
  local e
  for _, edge in ipairs(c.g.edges) do if edge.alive then e = edge end end
  e.leaking, e.cap = true, 0
  c:startRound(); c:finishRound()
  check(e.leaking and e.cap == 0, 'a burst main outlasts the round')
  check(c:repairPipe(e.id) and not e.leaking and e.cap > 0, 'and is fixed by a repair')
end

-- Saves carry the run.
do
  local c = City.newRounds({ seed = 21 })
  Bot.turn(c); Bot.turn(c); Bot.turn(c)
  local copy = Save.unpack(Save.pack(c))
  check(copy and copy.rounds, 'a run saves as a run')
  check(copy.rounds.round == c.rounds.round and copy.money == c.money and copy.rounds.lives == c.rounds.lives,
    'its numbers come back')
  check(#copy.g:aliveNodes() == #c.g:aliveNodes(), 'its network comes back')
  check(copy.districts[D.ZONE_ORDER[2]].zoneOpens == D.ZONE_OPENS[2], 'its zones come back')
end

-- Doing nothing loses; playing sensibly gets a long way.
do
  local idle = City.newRounds({ seed = 4 })
  for _ = 1, 40 do if not idle:playRound() then break end end
  check(idle.rounds.phase == 'lost' and idle.rounds.round < 15, 'an empty map loses early')
  local strict = City.newRounds({ seed = 4, strict = true })
  strict:startRound(); strict:roundArrive()
  check(strict.rounds.phase == 'lost', 'strict ends on the first dry house')
  local far = 0
  for seed = 1, 4 do
    local c = City.newRounds({ seed = seed })
    while c.rounds.phase ~= 'lost' and c.rounds.round <= D.FINAL_ROUND do
      if not Bot.turn(c) then break end
    end
    far = far + (c.rounds.round >= 20 and 1 or 0)
  end
  check(far >= 3, 'a careful player reaches round 20 on most maps')
end

print(string.format('rounds: %d checks passed', checks))
