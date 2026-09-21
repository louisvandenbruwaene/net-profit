-- Rounds mode driven through the real input callbacks, for `make rounds-smoke`
-- and `make rounds-shots`. Runs only in isolated test modes: nothing here reads
-- or writes the player's run.
local Rounds = require("rounds")
local Bot = require("rounds_bot")

local W = {}
local steps, index, wait, mode, checks = {}, 1, 0, nil, 0
local app

local function check(v, msg)
  if not v then error("rounds " .. mode .. ": " .. msg, 0) end
  checks = checks + 1
end

local function screen(x, y) return app.camera():toScreen(x, y) end

local function click(x, y, button)
  love.mousepressed(x, y, button or 1)
  love.mousereleased(x, y, button or 1)
end

local function key(k) love.keypressed(k) end

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
local function untilTrue(cond, limit)
  steps[#steps + 1] = { cond = cond, limit = limit or 60 }
end

local function opening()
  local run = app.run()
  step(function()
    app.state.modal = nil
    key("1")
    check(app.state.tool == "well", "1 picks the well")
    local s = run.springs[1]
    click(screen(s.x, s.y))
    check(#run.buildings == 1 and run.buildings[1].kind == "well", "a click on a spring sinks a well")
  end)
  step(function()
    key("2")
    local z = run.zones[1]
    click(screen(z.x, z.y))
    check(#run.buildings == 2, "a junction lands in the first zone")
    key("escape")
    check(app.state.tool == nil, "Esc puts the tool down")
  end)
  step(function()
    key("6")
    check(app.state.size == 3, "6 picks the large main")
    local a, b = run.buildings[1], run.buildings[2]
    local ax, ay = screen(a.x, a.y)
    local bx, by = screen(b.x, b.y)
    love.mousepressed(ax, ay, 1)
    love.mousemoved(bx, by, bx - ax, by - ay)
    love.mousereleased(bx, by, 1)
    check(#run.pipes == 1, "dragging from the well to the junction lays a main")
  end)
  step(function()
    local b = run.buildings[2]
    click(screen(b.x, b.y))
    check(app.state.sel == b.id, "clicking a junction selects it")
    local before = run.money
    key("u")
    check(b.level == 2 and run.money < before, "U upgrades the selection")
    key("escape")
  end)
end

local function smokeScript()
  app.fresh(false, 3)
  opening()
  step(function()
    key("space")
    check(app.run().phase == "round", "Space starts the round")
  end)
  untilTrue(function() return app.state.modal == "result" end)
  step(function()
    local run = app.run()
    check(run.round == 2 and run.phase == "build", "the round ends back in a break")
    check(app.state.result and app.state.result.total > 0, "the round paid out")
    key("space")
    check(app.state.modal == nil, "Space closes the results")
  end)
  step(function()
    local run = app.run()
    local copy = Rounds.unpack(Rounds.deserialize(Rounds.serialize(run:pack())))
    check(copy and copy.round == run.round and copy.money == run.money
      and #copy.buildings == #run.buildings and #copy.pipes == #run.pipes, "a run survives a save round trip")
    -- Bought this break: sold back in full.
    local before = run.money
    local b = run:build("junction", run.zones[1].x + 120, run.zones[1].y + 40)
    if b then
      run:sell(b.id)
      check(run.money == before, "a building bought this break sells back at full price")
    end
  end)
  -- Deep into a run, drawn with everything on it.
  step(function()
    local run = app.run()
    for _ = 1, 14 do if not Bot.turn(run) then break end end
    check(run.round > 8, "the bot gets well into a run")
  end)
  step(function()
    app.state.speed = 3
    app.startRound()
  end, 30)
  untilTrue(function() return app.state.modal ~= nil end)
  step(function()
    check(app.state.modal == "result" or app.state.modal == "lost", "a late round finishes")
    app.state.modal = "help"
  end)
  step(function() app.state.modal = "newrun" end)
  step(function()
    app.fresh(true, 9)
    check(app.run().strict and app.run().lives == 1, "a strict run has one life")
  end)
  step(function()
    print(string.format("rounds smoke: %d checks passed", checks))
    love.event.quit(0)
  end)
end

local function shotScript()
  app.fresh(false, 3)
  step(function() app.state.modal = "help" end, 3)
  step(function() shot("rounds-01-help.png") end, 3)
  opening()
  step(function()
    app.state.modal = nil
    app.state.tool = "junction"
  end, 3)
  step(function() shot("rounds-02-opening.png") end, 3)
  step(function()
    app.state.tool = nil
    local run = app.run()
    for _ = 1, 13 do if not Bot.turn(run) then break end end
    for _, b in ipairs(run.buildings) do
      if b.kind == "junction" then app.state.sel = b.id; break end
    end
  end, 4)
  step(function() shot("rounds-03-midgame.png") end, 3)
  step(function()
    app.state.sel = nil
    app.state.speed = 1
    app.startRound()
  end, 3)
  untilTrue(function()
    local run = app.run()
    return run.phase ~= "round" or run.arrived >= math.floor(#run.houses * 0.7)
  end)
  step(function() shot("rounds-04-round.png") end, 3)
  untilTrue(function() return app.state.modal ~= nil end)
  step(function() shot("rounds-05-result.png") end, 3)
  step(function() app.state.modal = "lost" end, 3)
  step(function() shot("rounds-06-lost.png") end, 3)
  step(function() love.event.quit(0) end, 3)
end

function W.start(a, m)
  app, mode = a, m
  steps, index, wait = {}, 1, 3
  if m == "--smoke" then smokeScript() else shotScript() end
end

function W.update(_, dt)
  if wait > 0 then wait = wait - 1; return end
  local s = steps[index]
  if not s then return end
  if s.cond then
    s.limit = s.limit - dt
    if s.cond() then index = index + 1; wait = 1
    elseif s.limit <= 0 then error("rounds " .. mode .. ": timed out waiting at step " .. index, 0) end
    return
  end
  s.fn()
  index = index + 1
  wait = s.frames
end

return W
