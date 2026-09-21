-- Rounds mode driven through the company app's real input callbacks, for
-- `make rounds-smoke` and `make rounds-shots`. Test runs only: the app reads
-- and writes nothing of the player's while one is going.
local Save = require("company_save")
local Bot = require("rounds_bot")

local W = {}
local steps, index, wait, mode, checks = {}, 1, 0, nil, 0
local app

local function check(v, msg)
  if not v then error("rounds " .. mode .. ": " .. msg, 0) end
  checks = checks + 1
end

local function city() return app.city() end
local function screen(x, y) return app.camera():toScreen(x, y) end
local function click(x, y, button)
  love.mousepressed(x, y, button or 1)
  love.mousereleased(x, y, button or 1)
end
local function drag(a, b)
  local ax, ay = screen(a.x, a.y)
  local bx, by = screen(b.x, b.y)
  love.mousepressed(ax, ay, 1)
  love.mousemoved(bx, by, bx - ax, by - ay)
  love.mousereleased(bx, by, 1)
end

local function shot(name)
  local dir = os.getenv("ROUNDS_SHOTS")
  love.graphics.captureScreenshot(function(img)
    local data = img:encode("png"):getString()
    if dir then
      local f = assert(io.open(dir .. "/" .. name, "wb"))
      f:write(data); f:close()
    else
      love.filesystem.write(name, data)
    end
    print("shot " .. name)
  end)
end

local function step(fn, frames) steps[#steps + 1] = { fn = fn, frames = frames or 2 } end
-- Measured in seconds, not frames: an offscreen window with no vsync runs
-- thousands of frames a second.
local function untilTrue(cond, limit) steps[#steps + 1] = { cond = cond, limit = limit or 60 } end

local function focus(x, y, scale)
  local cam = app.camera()
  cam.x, cam.y = x, y
  cam.scale, cam.targetScale = scale, scale
end

-- The opening, by hand: a well on the spring, a hub in the zone, a main
-- dragged between them.
local function opening()
  step(function()
    app.state.modal = nil
    local c = city()
    check(c.rounds and c.rounds.round == 1, "the app opens a run with --rounds")
    local home = c.districts[6]
    focus(home.x + home.w / 2, home.y + home.h / 2, 0.8)
  end)
  step(function()
    local c = city()
    local home = c.districts[6]
    local dep, bd
    for _, d in ipairs(c.deposits) do
      if d.commodity == "water" and c:districtAt(d.x, d.y) == home then
        local e = (d.x - home.x - home.w / 2) ^ 2 + (d.y - home.y - home.h / 2) ^ 2
        if not bd or e < bd then dep, bd = d, e end
      end
    end
    app.state.tool, app.state.commodity = "source", "water"
    click(screen(dep.x, dep.y))
    check(#c.g:nodesOfKind("source") == 1, "a click on a spring sinks a well")
    app.state.tool = "exchange"
    click(screen(home.x + home.w / 2, home.y + home.h / 2))
    check(#app.city().g:nodesOfKind("exchange") == 1, "a hub goes in the middle of the zone")
    app.state.tool = nil
  end)
  step(function()
    local c = city()
    drag(c.g:nodesOfKind("source")[1], c.g:nodesOfKind("exchange")[1])
    local joined = false
    for _, e in ipairs(app.city().g.edges) do if e.alive and e.commodity == "water" then joined = true end end
    check(joined, "dragging from the well to the hub lays a main of a size the hub takes")
  end)
end

local function smokeScript()
  opening()
  step(function()
    local before = #city().g:aliveNodes()
    local home = city().districts[6]
    app.action("build", home.x + 140, home.y + 140, "junction", "water")
    check(#city().g:aliveNodes() == before + 1, "a junction goes in during the break")
    app.action("undo")
    check(#city().g:aliveNodes() == before, "undo takes it back")
  end)
  step(function()
    love.keypressed("return")
    check(city().rounds.phase == "round", "Enter starts the round")
    local c = city()
    local n = #c.g:aliveNodes()
    local home = c.districts[6]
    app.action("build", home.x + 150, home.y + 150, "junction", "water")
    check(#c.g:aliveNodes() == n, "nothing is built while houses arrive")
  end)
  untilTrue(function() return app.state.modal == "roundResult" or app.state.modal == "roundLost" end)
  step(function()
    local c = city()
    check(c.rounds.round == 2 and c.rounds.phase == "build", "the round ends back in a break")
    check(#c:roundHouses() == 0, "the houses leave with the round")
    love.keypressed("return")
    check(app.state.modal == nil, "Enter closes the results")
  end)
  step(function()
    local c = city()
    local copy = Save.unpack(Save.pack(c))
    check(copy and copy.rounds and copy.rounds.round == c.rounds.round and copy.money == c.money,
      "a run survives a save round trip")
    for _ = 1, 12 do if not Bot.turn(c) then break end end
    check(c.rounds.round > 6, "the bot gets well into a run")
    app.state.roundSpeed = 3
    app.action("startRound")
  end, 5)
  untilTrue(function() return app.state.modal ~= nil end)
  step(function()
    check(app.state.modal == "roundResult" or app.state.modal == "roundLost" or app.state.modal == "roundWon",
      "a late round finishes")
    app.state.modal = nil
    app.state.tab = "history"
  end)
  step(function() app.state.tab = "round" end)
  step(function()
    app.action("leaveRounds")
    check(not city().rounds, "Company goes back to the company")
    app.action("rounds")
    check(city().rounds, "Rounds comes back to a run")
    app.action("newRun", true)
    check(city().rounds.strict and city().rounds.lives == 1, "a strict run has one life")
  end)
  step(function()
    print(string.format("rounds smoke: %d checks passed", checks))
    love.event.quit(0)
  end)
end

local function shotScript()
  step(function() app.state.modal = "roundsHelp" end, 3)
  step(function() shot("rounds-01-help.png") end, 3)
  opening()
  step(function()
    app.state.tab = "round"
    local h = city().g:nodesOfKind("exchange")[1]
    app.state.node = h.id
  end, 3)
  step(function() shot("rounds-02-opening.png") end, 3)
  step(function()
    app.state.node = nil
    for _ = 1, 13 do if not Bot.turn(city()) then break end end
    app.state.tab = "round"
    app.action("fitWorld")
  end, 4)
  step(function() shot("rounds-03-midgame.png") end, 3)
  step(function()
    app.state.roundSpeed = 1
    app.action("startRound")
  end, 3)
  untilTrue(function()
    local rs = city().rounds
    return rs.phase ~= "round" or rs.arrived >= math.floor(#rs.queue * 0.7)
  end)
  step(function() shot("rounds-04-round.png") end, 3)
  untilTrue(function() return app.state.modal ~= nil end)
  step(function() shot("rounds-05-result.png") end, 3)
  step(function() app.state.modal = nil; app.state.tab = "history" end, 3)
  step(function() shot("rounds-06-history.png") end, 3)
  step(function() app.state.modal = "roundLost" end, 3)
  step(function() shot("rounds-07-lost.png") end, 3)
  step(function() love.event.quit(0) end, 3)
end

function W.start(a, m)
  app, mode = a, m
  steps, index, wait = {}, 1, 3
  if m == "--smoke" then smokeScript() else shotScript() end
end

function W.update(_, _, _, dt)
  if wait > 0 then wait = wait - 1; return end
  local s = steps[index]
  if not s then return end
  if s.cond then
    s.limit = s.limit - (dt or 0.016)
    if s.cond() then index = index + 1; wait = 1
    elseif s.limit <= 0 then error("rounds " .. mode .. ": timed out waiting at step " .. index, 0) end
    return
  end
  s.fn()
  index = index + 1
  wait = s.frames
end

return W
