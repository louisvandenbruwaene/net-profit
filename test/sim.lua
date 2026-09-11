-- sim.lua -- headless balance harness.  lua5.4 test/sim.lua [runs] [verbose]
package.path = "src/?.lua;../src/?.lua;test/?.lua;./?.lua;" .. package.path
local Game = require("game")
local Bot  = require("bot")

local botTurn = Bot.make(Game)

local function playRun(verbose)
  local run = Game.new({ unlocked = {} })
  while run.phase ~= "dead" and run.wave <= 60 do
    botTurn(run)
    local w, d, f, cw = run.wave, run.demand, run.flow, #run.cut
    local nT = #run.g:nodesOfKind("sink")
    local rep = run:resolve()
    if verbose then
      local st = run.g:stats()
      print(string.format(
        "  w%-3d term %d x%-2d = %-3d  flow %-3d %s E=%-5d |V|=%-3d |E|=%-3d cutw=%-2d hit=%d",
        w, nT, run.perTerminal or 0, d, f, rep.survived and "ok  " or "DEAD",
        run.energy, st.order, st.size, cw, #rep.strikes))
    end
    if run.phase == "report" then run:beginNextWave() end
  end
  return run
end

local runs = tonumber(arg[1]) or 40
math.randomseed(20260911)
if arg[2] then print("sample run:"); playRun(true); print("") end

local reached, sum, best, worst = {}, 0, 0, math.huge
for _ = 1, runs do
  local r = playRun(false)
  reached[#reached + 1] = r.wave
  sum = sum + r.wave
  best = math.max(best, r.wave); worst = math.min(worst, r.wave)
end
table.sort(reached)
print(string.format("greedy bot over %d runs", runs))
print(string.format("  mean %.1f   median %d   best %d   worst %d",
  sum / runs, reached[math.ceil(#reached / 2)], best, worst))
print(string.format("  per-terminal demand: w1=%d w5=%d w10=%d w15=%d w20=%d",
  Game.terminalDemand(1), Game.terminalDemand(5), Game.terminalDemand(10),
  Game.terminalDemand(15), Game.terminalDemand(20)))
