-- tune.lua -- parameter sweep scored by how far the reference bot survives.
-- Target: a median in the high teens. Far enough that a run has an arc,
-- short enough that failure stays real.
package.path = "src/?.lua;../src/?.lua;test/?.lua;./?.lua;" .. package.path
local Bot = require("bot")

local function score(cfg, runs)
  package.loaded["graph"] = nil
  package.loaded["game"] = nil
  local Game = require("game")
  for k, v in pairs(cfg.balance or {}) do Game.balance[k] = v end
  if cfg.demandSlope then Game.balance.demandSlope = cfg.demandSlope end
  local bot = Bot.make(Game)
  math.randomseed(7)
  local waves, sum = {}, 0
  for _ = 1, runs do
    local run = Game.new({ unlocked = {} })
    while run.phase ~= "dead" and run.wave <= 70 do
      bot(run); run:resolve()
      if run.phase == "report" then run:beginNextWave() end
    end
    waves[#waves + 1] = run.wave; sum = sum + run.wave
  end
  table.sort(waves)
  return sum / runs, waves[math.ceil(#waves / 2)], waves[1], waves[#waves]
end

local grid = {}
for _, base in ipairs({ 40, 60 }) do
  for _, per in ipairs({ 8, 12, 16 }) do
    for _, tev in ipairs({ 5, 6 }) do
      for _, slope in ipairs({ 0.35, 0.45 }) do
        grid[#grid + 1] = {
          label = string.format("base=%-2d perFlow=%-2d termEvery=%d slope=%.2f",
                                base, per, tev, slope),
          demandSlope = slope,
          balance = { baseIncome = base, incomePerFlow = per, terminalEvery = tev },
        }
      end
    end
  end
end

local results = {}
for _, cfg in ipairs(grid) do
  local mean, med, lo, hi = score(cfg, 14)
  results[#results + 1] = { label = cfg.label, mean = mean, med = med, lo = lo, hi = hi }
end
table.sort(results, function(a, b) return a.mean > b.mean end)

print(string.format("%-56s %6s %5s %5s %5s", "config", "mean", "med", "min", "max"))
for i = 1, math.min(#results, 18) do
  local r = results[i]
  print(string.format("%-56s %6.1f %5d %5d %5d", r.label, r.mean, r.med, r.lo, r.hi))
end
