-- AUGMENT -- grow a network that survives its own minimum cut.
love.filesystem.setRequirePath("src/?.lua;test/?.lua;?.lua")

local P      = require("palette")
local Graph  = require("graph")
local Game   = require("game")
local Meta   = require("meta")
local Camera = require("camera")
local R      = require("render")
local U      = require("ui")
local A      = require("audio")
local T      = require("tutorial")

local state = {
  screen = "title",     -- title | run | meta | help
  tool = nil,           -- node kind armed for placement
  selNode = nil, selEdge = nil,
  dragFrom = nil,
  panning = false,
  maybePan = nil,
  showReport = false,
  pendingResolve = false,
  restart = false,
  recorded = false,
}

local meta, run, cam
local doResolve  -- defined below, referenced by the scripted test walkthroughs

-- Screenshot mode (`love . --shot`): plays a few waves with the reference bot so
-- the captured frame shows a real mid-game network, then writes PNGs and exits.
local shot = { active = false, frames = 0, stage = 1 }

-- Smoke test (`love . --smoke`): drives the real mouse and key callbacks so the
-- input layer is exercised, not just the rules. The sim never touches this code.
local smoke = { active = false, frames = 0, fails = 0 }

-- Soak (`love . --soak`): plays whole runs to collapse with rendering live, so
-- every screen gets drawn, including the wave report and the death overlay that
-- a screenshot pass never reaches. Any error in a draw path crashes the run.
local soak = { active = false, runs = 0, maxRuns = 3, frames = 0, waves = 0,
               deadFrames = 0, reportFrames = 0, draws = 0 }
local audiotest = false

-- Tutorial test (`love . --tut`): walks all twelve steps through the same
-- callbacks a player uses. If a step's completion predicate can never be met,
-- or an instruction is not affordable, this is where it shows up.
local tut = { active = false, frames = 0, fails = 0 }
local shottut, shottutFrames = false, 0

local function expect(cond, what)
  if cond then
    print("  ok    " .. what)
  else
    smoke.fails = smoke.fails + 1
    print("  FAIL  " .. what)
  end
end

local function layout()
  local W, H = love.graphics.getDimensions()
  cam:setViewport(U.SIDEBAR, 0, W - U.SIDEBAR, H - U.BOTTOM)
end

local function newRun(opts)
  opts = opts or {}
  run = Game.new(meta, opts)
  cam = Camera.new(Game.balance.fieldW, Game.balance.fieldH)
  cam.targetScale, cam.scale = 0.85, 0.85
  cam:centerOn(run.source.x, run.source.y)
  layout()
  state.tool, state.selNode, state.selEdge = nil, nil, nil
  state.showReport, state.recorded, state.restart = false, false, false
  state.backdrop = false
  state.startTutorial = false
  if opts.tutorial then T.start() else T.active = false end
  state.screen = "run"
end

function love.load(args)
  love.graphics.setBackgroundColor(P.bg)
  love.graphics.setLineStyle("smooth")
  math.randomseed(os.time())
  R.init()
  A.init()
  meta = Meta.load()
  A.muted = false

  for _, a in ipairs(args or {}) do
    if a == "--shot" then shot.active = true end
    if a == "--smoke" then smoke.active = true end
    if a == "--soak" then soak.active = true end
    if a == "--audio" then audiotest = true end
    if a == "--tut" then tut.active = true end
    if a == "--shottut" then shottut = true end
  end

  if shot.active or smoke.active or soak.active or tut.active or audiotest or shottut then
    -- Never write the player's save from a test mode, and turn any runtime
    -- error into a non-zero exit instead of an interactive error screen.
    Meta.save = function() end
    A.setEnabled(false)
    meta = { insight = 0, unlocked = {}, runs = 0, bestWave = 0, bestFlow = 0 }
    local function die(msg)
      io.stderr:write("RUNTIME ERROR: " .. tostring(msg) .. "\n")
      io.stderr:write(debug.traceback("", 2) .. "\n")
      love.event.quit(1)
      return function() end
    end
    love.errorhandler = die
    love.errhand = die
  end

  if shot.active then
    math.randomseed(4)
    meta = { insight = 12, unlocked = {}, runs = 3, bestWave = 11, bestFlow = 14 }
    run = Game.new(meta)
    state.screen = "run"
  else
    -- A run plays itself out behind the title screen so the field is never empty.
    -- It is scenery: mark it so a collapse there never counts as a played run.
    state.backdrop = true
    run = Game.new(meta)
    local ok, Bot = pcall(require, "bot")
    if ok then
      local turn = Bot.make(Game)
      for _ = 1, 6 do
        if run.phase == "dead" then break end
        turn(run); run:resolve()
        if run.phase == "report" then run:beginNextWave() end
      end
    end
  end

  cam = Camera.new(Game.balance.fieldW, Game.balance.fieldH)
  cam:centerOn(run.source.x, run.source.y)
  if shot.active then cam.scale, cam.targetScale = 0.8, 0.8 end
  layout()
end

function love.resize() layout() end

local function runTutorial()
  print("tutorial: walking every step")
  local fails = 0
  local function expectStep(n, what)
    if T.step == n and T.active then
      print(string.format("  ok    step %-2d %s", n, what))
    else
      fails = fails + 1
      print(string.format("  FAIL  expected step %d (%s), at step %s active=%s",
        n, what, tostring(T.step), tostring(T.active)))
    end
  end
  local function tick() T.update(run) end
  local function press() T.advance() end

  newRun({ tutorial = true })
  local src = run.g.nodes[run.source.id]
  local term = run.g:nodesOfKind("sink")[1]

  expectStep(1, "source intro")
  press(); expectStep(2, "terminal intro")
  press(); expectStep(3, "lay first link")

  -- Drag source onto terminal.
  local ax, ay = cam:toScreen(src.x, src.y)
  local bx, by = cam:toScreen(term.x, term.y)
  love.mousepressed(ax, ay, 1)
  love.mousereleased(bx, by, 1)
  tick(); expectStep(4, "capacity vs flow")

  press(); expectStep(5, "widen the link")

  -- Upgrade until delivery meets demand, exactly as instructed.
  local eid = run.g:hasEdge(src.id, term.id)
  if not eid then fails = fails + 1; print("  FAIL  no link was created") end
  state.selEdge = eid
  local guard = 0
  while run.flow < run.demand and guard < 20 do
    love.keypressed("u"); guard = guard + 1
  end
  tick(); expectStep(6, "resolve the wave")

  love.keypressed("space")
  state.pendingResolve = false
  doResolve()
  tick(); expectStep(7, "the minimum cut")

  -- A report overlay is up; dismiss it the way a player does.
  if state.showReport then
    run:beginNextWave(); state.showReport = false
  end

  press(); expectStep(8, "the adversary")
  press(); expectStep(9, "place a relay")

  -- Place a relay off the straight line.
  love.keypressed("1")
  local rx, ry = cam:toScreen(src.x + 107, src.y - 120)
  love.mousepressed(rx, ry, 1)
  tick(); expectStep(10, "route around")

  local relay = run.g.nodes[#run.g.nodes]
  if relay.kind ~= "relay" then fails = fails + 1; print("  FAIL  relay was not placed") end
  local px, py = cam:toScreen(relay.x, relay.y)
  love.mousepressed(ax, ay, 1); love.mousereleased(px, py, 1)
  love.mousepressed(px, py, 1); love.mousereleased(bx, by, 1)
  tick(); expectStep(11, "cut is two wide")

  if #run.cut < 2 then
    fails = fails + 1
    print(string.format("  FAIL  cut width is %d, expected 2 or more", #run.cut))
  else
    print(string.format("  ok    cut width reached %d via a disjoint route", #run.cut))
  end

  press(); expectStep(12, "controls recap")
  press()
  if T.active or not T.finished then
    fails = fails + 1; print("  FAIL  tutorial did not finish")
  else
    print("  ok    tutorial completed and closed")
  end
  if meta.tutorialDone == nil then meta.tutorialDone = false end

  tut.fails = fails
end

-- Walks a full build interaction through the public callbacks.
local function runSmoke()
  print("smoke test: input layer")
  newRun()
  local src = run.g.nodes[run.source.id]
  local term = run.g:nodesOfKind("sink")[1]
  expect(src ~= nil and term ~= nil, "run starts with a source and a terminal")

  -- Arm the relay tool and place one partway to the terminal.
  love.keypressed("1")
  expect(state.tool == "relay", "key 1 arms the relay tool")
  local mx0 = src.x + (term.x - src.x) * 0.5
  local my0 = src.y + (term.y - src.y) * 0.5
  local sx, sy = cam:toScreen(mx0, my0)
  local before = #run.g:aliveNodes()
  love.mousepressed(sx, sy, 1)
  expect(#run.g:aliveNodes() == before + 1, "clicking the field places a node")
  local relay = run.g.nodes[#run.g.nodes]

  -- Drag source -> relay, then relay -> terminal.
  local ax, ay = cam:toScreen(src.x, src.y)
  local bx, by = cam:toScreen(relay.x, relay.y)
  love.mousepressed(ax, ay, 1)
  expect(state.dragFrom == src.id, "pressing a node starts a link drag")
  love.mousereleased(bx, by, 1)
  expect(run.g:hasEdge(src.id, relay.id) ~= nil, "releasing on a node lays a link")

  local cx2, cy2 = cam:toScreen(term.x, term.y)
  love.mousepressed(bx, by, 1)
  love.mousereleased(cx2, cy2, 1)
  expect(run.g:hasEdge(relay.id, term.id) ~= nil, "second link reaches the terminal")
  expect(run.flow > 0, "flow is delivered once a path exists")

  -- Upgrade the selected link.
  local eid = run.g:hasEdge(src.id, relay.id)
  state.selEdge, state.selNode = eid, nil
  local cap0 = run.g.edges[eid].cap
  love.keypressed("u")
  expect(run.g.edges[eid].cap == cap0 + 1, "u upgrades the selected link")

  -- Raise delivery to demand, then resolve the wave.
  for _ = 1, 60 do
    if run.flow >= run.demand then break end
    local c = (run.deliveryCut and run.deliveryCut[1]) or (run.cut and run.cut[1])
    if not c then break end
    if c.kind == "edge" then run:upgradeLink(c.id) else run:upgradeNode(c.id) end
  end
  expect(run.flow >= run.demand, "demand can be met from the starting energy")

  local w0 = run.wave
  love.keypressed("space")
  state.pendingResolve = false
  local rep = run:resolve() or run.lastReport
  expect(run.wave == w0 + 1 or run.phase == "dead", "resolving advances the wave")
  expect(run.phase ~= "dead", "wave 1 is survivable")

  -- Panning and zooming must actually move the camera. Asserting only that the
  -- callbacks do not throw is how a dead control slips through a green suite.
  local camx, camy = cam.x, cam.y
  love.mousepressed(sx, sy, 2)
  love.mousemoved(sx + 30, sy + 20, 30, 20)
  love.mousereleased(sx, sy, 2)
  expect(cam.x ~= camx or cam.y ~= camy, "right-drag pans the camera")

  camx, camy = cam.x, cam.y
  love.mousepressed(sx, sy, 3)
  love.mousemoved(sx - 25, sy - 15, -25, -15)
  love.mousereleased(sx, sy, 3)
  expect(cam.x ~= camx or cam.y ~= camy, "middle-drag pans the camera")

  -- Left-drag on empty space is what most people reach for first.
  camx, camy = cam.x, cam.y
  local emptyx, emptyy = cam:toScreen(src.x + 300, src.y + 300)
  expect(emptyx > U.SIDEBAR and emptyy < love.graphics.getHeight() - U.BOTTOM,
    "test point lies inside the field")
  love.mousepressed(emptyx, emptyy, 1)
  love.mousemoved(emptyx + 40, emptyy + 30, 40, 30)
  love.mousereleased(emptyx + 40, emptyy + 30, 1)
  expect(cam.x ~= camx or cam.y ~= camy, "left-drag on empty space pans the camera")

  -- And a press with no movement must still clear the selection, not pan.
  state.selNode = src.id
  love.mousepressed(emptyx, emptyy, 1)
  love.mousereleased(emptyx, emptyy, 1)
  expect(state.selNode == nil, "a click without movement still deselects")

  local fx, fy = cam:toScreen(src.x, src.y)
  love.mouse.setPosition(fx, fy)
  local gx, gy = love.mouse.getPosition()
  local sc = cam.targetScale
  if math.abs(gx - fx) < 2 and math.abs(gy - fy) < 2 then
    love.wheelmoved(0, 1)
    expect(cam.targetScale ~= sc, "wheel zooms")
  else
    -- Unfocused window: the cursor cannot be warped, so exercise the camera itself.
    cam:zoomAt(fx, fy, 1)
    expect(cam.targetScale ~= sc, "wheel zooms (camera driven directly, cursor warp unavailable)")
  end
  cam.targetScale, cam.scale = 0.85, 0.85

  -- A player leaves the report before building again; so must the test.
  run:beginNextWave()
  state.showReport = false
  expect(run.phase == "build", "continuing the report returns to the build phase")

  -- Demolition frees the port again.
  local deg0 = run.g:degree(relay.id)
  state.selEdge = run.g:hasEdge(src.id, relay.id)
  love.keypressed("x")
  expect(run.g:degree(relay.id) == deg0 - 1, "x demolishes the selected link")

  -- Overlays.
  love.keypressed("h"); expect(state.screen == "help", "h opens help")
  love.keypressed("h"); expect(state.screen == "run", "h closes help")
  love.keypressed("m"); expect(state.screen == "meta", "m opens theorems")
  love.keypressed("escape"); expect(state.screen == "run", "escape leaves theorems")
end

--------------------------------------------------------------------------------
-- Picking
--------------------------------------------------------------------------------

local function inField(mx, my)
  return mx > U.SIDEBAR and my < love.graphics.getHeight() - U.BOTTOM
end

local function pickNode(mx, my)
  local best, bestD
  for _, n in ipairs(run.g.nodes) do
    if n.alive then
      local sx, sy = cam:toScreen(n.x, n.y)
      local d = math.sqrt((sx - mx) ^ 2 + (sy - my) ^ 2)
      local r = ((n.kind == "source" and 22) or (n.kind == "sink" and 19) or 15) * cam.scale + 7
      if d <= r and (not bestD or d < bestD) then best, bestD = n.id, d end
    end
  end
  return best
end

local function pointToSegment(px, py, ax, ay, bx, by)
  local dx, dy = bx - ax, by - ay
  local l2 = dx * dx + dy * dy
  if l2 < 1e-6 then return math.sqrt((px - ax) ^ 2 + (py - ay) ^ 2) end
  local t = math.max(0, math.min(1, ((px - ax) * dx + (py - ay) * dy) / l2))
  local qx, qy = ax + t * dx, ay + t * dy
  return math.sqrt((px - qx) ^ 2 + (py - qy) ^ 2)
end

local function pickEdge(mx, my)
  local best, bestD
  for _, e in ipairs(run.g.edges) do
    if e.alive then
      local na, nb = run.g.nodes[e.a], run.g.nodes[e.b]
      if na.alive and nb.alive then
        local ax, ay = cam:toScreen(na.x, na.y)
        local bx, by = cam:toScreen(nb.x, nb.y)
        local d = pointToSegment(mx, my, ax, ay, bx, by)
        local tol = math.max(7, (1.1 + math.min(e.cap, 24) * 0.52) * cam.scale * 0.5 + 5)
        if d <= tol and (not bestD or d < bestD) then best, bestD = e.id, d end
      end
    end
  end
  return best
end

--------------------------------------------------------------------------------
-- Resolving a wave
--------------------------------------------------------------------------------

doResolve = function()
  local rep = run:resolve()
  if not rep then return end

  A.play("resolve", 0.9)
  for i, s in ipairs(rep.strikes) do
    if s.x and s.y then
      R.burst(s.x, s.y, P.cut, s.kind == "node" and 30 or 18)
      R.ring(s.x, s.y, P.cut)
      R.floatText(s.x, s.y, s.kind == "node" and "NODE DESTROYED" or "SEVERED", P.cut)
      A.play(s.kind == "node" and "destroy" or "sever", 1.0, 0.94 + i * 0.05)
    end
  end
  cam:shakeBy(rep.survived and (0.30 + 0.22 * #rep.strikes) or 1.1)

  if rep.survived then
    A.play("held", 0.85)
    state.showReport = true
    if rep.newTerminal then
      A.play("terminal", 0.8)
      for _, t in ipairs(run.g:nodesOfKind("sink")) do
        if t.bornWave == run.wave then R.ring(t.x, t.y, P.warn) end
      end
    end
  else
    A.play("collapse", 1.0, 1.0)
  end
  state.selNode, state.selEdge = nil, nil
end

--------------------------------------------------------------------------------
-- Update
--------------------------------------------------------------------------------

function love.update(dt)
  R.update(dt)
  cam:update(dt)

  if state.screen == "title" then cam:pan(-12 * dt, -4 * dt) end

  if run.phase == "dead" and not state.recorded and not state.backdrop then
    state.recorded = true
    Meta.record(meta, run)
  end


  if shot.active then
    shot.frames = shot.frames + 1
    if shot.frames == 14 then
      love.graphics.captureScreenshot("00-wave1.png")
    elseif shot.frames == 16 then
      -- Develop the network so the next frame shows a real mid-game position.
      local turn = require("bot").make(Game)
      for _ = 1, 7 do
        if run.phase == "dead" then break end
        turn(run); run:resolve()
        if run.phase == "report" then run:beginNextWave() end
      end
      run.energy = run.energy + 200
      state.showReport = false
      cam:centerOn(run.source.x, run.source.y)
    elseif shot.frames == 24 then
      love.graphics.captureScreenshot("01-run.png")
    elseif shot.frames == 26 then
      doResolve()
    elseif shot.frames == 34 then
      love.graphics.captureScreenshot("05-report.png")
    elseif shot.frames == 36 then
      -- Force a collapse so the death overlay can be inspected.
      run:beginNextWave()
      state.showReport = false
      local sinks = run.g:nodesOfKind("sink")
      for _, t in ipairs(sinks) do t.demand = 999 end
      run.demand = 999 * #sinks
      run:refresh()
      doResolve()
    elseif shot.frames == 44 then
      love.graphics.captureScreenshot("06-death.png")
    elseif shot.frames == 48 then
      state.screen = "help"
    elseif shot.frames == 56 then
      love.graphics.captureScreenshot("02-help.png")
    elseif shot.frames == 60 then
      state.screen = "meta"
    elseif shot.frames == 68 then
      love.graphics.captureScreenshot("03-theorems.png")
    elseif shot.frames == 72 then
      state.screen = "title"
    elseif shot.frames == 80 then
      love.graphics.captureScreenshot("04-title.png")
    elseif shot.frames > 92 then
      love.event.quit()
    end
    return
  end

  if shottut then
    shottutFrames = shottutFrames + 1
    if shottutFrames == 4 then
      newRun({ tutorial = true })
    elseif shottutFrames == 12 then
      love.graphics.captureScreenshot("07-tutorial-1.png")
    elseif shottutFrames == 16 then
      T.advance(); T.advance()   -- to the first action step
    elseif shottutFrames == 24 then
      love.graphics.captureScreenshot("08-tutorial-3.png")
    elseif shottutFrames > 34 then
      love.event.quit()
    end
    return
  end

  if tut.active then
    tut.frames = tut.frames + 1
    if tut.frames == 3 then runTutorial() end
    if tut.frames > 8 then
      print(tut.fails == 0 and "tutorial: all steps completable"
                            or string.format("tutorial: %d FAILURES", tut.fails))
      love.event.quit(tut.fails == 0 and 0 or 1)
    end
    return
  end

  if audiotest then
    print(string.format("%-10s %8s %8s %7s", "sound", "peak", "rms", "dur"))
    local bad = 0
    for _, r in ipairs(A.report()) do
      local flag = ""
      if r.rms < 0.004 then flag = "  <- SILENT"; bad = bad + 1 end
      if r.peak > 0.999 then flag = flag .. "  <- CLIPPED"; bad = bad + 1 end
      print(string.format("%-10s %8.3f %8.4f %6.2fs%s", r.name, r.peak, r.rms, r.dur, flag))
    end
    print(bad == 0 and "\naudio: all sounds have content, none clipped"
                   or string.format("\naudio: %d PROBLEMS", bad))
    love.event.quit(bad == 0 and 0 or 1)
    return
  end

  if soak.active then
    soak.frames = soak.frames + 1
    -- Start from a real run, not the title backdrop, so the soak exercises the
    -- path a player actually takes (including the save on collapse).
    if soak.frames == 1 then newRun() end

    -- Keep the inspector pointed at something, cycling node and link variants
    -- (including source and terminals, whose panels differ).
    if soak.frames % 11 == 0 then
      local ns = run.g:aliveNodes()
      if #ns > 0 then state.selNode, state.selEdge = ns[math.random(#ns)].id, nil end
    elseif soak.frames % 11 == 5 then
      local live = {}
      for _, e in ipairs(run.g.edges) do if e.alive then live[#live + 1] = e.id end end
      if #live > 0 then state.selEdge, state.selNode = live[math.random(#live)], nil end
    end

    if run.phase == "dead" then
      soak.deadFrames = soak.deadFrames + 1
      if soak.deadFrames == 3 then state.screen = "meta"
      elseif soak.deadFrames == 7 then state.screen = "help"
      elseif soak.deadFrames == 11 then state.screen = "title"
      elseif soak.deadFrames >= 15 then
        soak.runs = soak.runs + 1
        soak.deadFrames = 0
        print(string.format("  run %d collapsed on wave %d (peak delivery %d)",
          soak.runs, run.wave, run.peakFlow))
        if soak.runs >= soak.maxRuns then
          print(string.format("soak: %d runs, %d waves, %d frames drawn, no errors",
            soak.runs, soak.waves, soak.draws))
          love.event.quit(0)
        else
          state.screen = "run"
          newRun()
        end
      end
    elseif state.showReport then
      soak.reportFrames = soak.reportFrames + 1
      if soak.reportFrames >= 3 then
        soak.reportFrames = 0
        run:beginNextWave()
        state.showReport = false
      end
    elseif run.phase == "build" then
      soak.bot = soak.bot or require("bot").make(Game)
      soak.bot(run)
      soak.waves = soak.waves + 1
      doResolve()
    end
    return
  end

  if smoke.active then
    smoke.frames = smoke.frames + 1
    if smoke.frames == 3 then runSmoke() end
    if smoke.frames > 8 then
      print(smoke.fails == 0 and "smoke: all input paths ok" or
            string.format("smoke: %d FAILURES", smoke.fails))
      love.event.quit(smoke.fails == 0 and 0 or 1)
    end
    return
  end

  if state.startTutorial then
    state.startTutorial = false
    newRun({ tutorial = true })
  end

  if state.restart then newRun() end

  -- Action steps complete when the player's own graph satisfies them.
  if T.active then
    if T.update(run) then A.play("step", 0.8) end
    if not T.active and not meta.tutorialDone then
      meta.tutorialDone = true
      Meta.save(meta)
    end
  end

  if state.pendingResolve then
    state.pendingResolve = false
    doResolve()
  end

  -- Edge pan when dragging a link near the viewport border.
  if state.dragFrom then
    local mx, my = love.mouse.getPosition()
    local m = 48
    local dx, dy = 0, 0
    if mx > U.SIDEBAR and mx < U.SIDEBAR + m then dx = 1 end
    if mx > love.graphics.getWidth() - m then dx = -1 end
    if my < m then dy = 1 end
    if my > love.graphics.getHeight() - U.BOTTOM - m then dy = -1 end
    if dx ~= 0 or dy ~= 0 then cam:pan(dx * 420 * dt, dy * 420 * dt) end
  end
end

--------------------------------------------------------------------------------
-- Draw
--------------------------------------------------------------------------------

function love.draw()
  local W, H = love.graphics.getDimensions()
  soak.draws = soak.draws + 1
  U.begin()

  if state.screen == "title" then
    R.drawGrid(cam, Game.balance.fieldW, Game.balance.fieldH)
    R.drawLinks(cam, run, nil, nil)
    R.drawNodes(cam, run, nil, nil)
    U.drawTitle(state, meta)
    return
  end

  -- Field, clipped to its viewport.
  love.graphics.setScissor(U.SIDEBAR, 0, W - U.SIDEBAR, H - U.BOTTOM)
  R.drawGrid(cam, Game.balance.fieldW, Game.balance.fieldH)

  local mx, my = love.mouse.getPosition()
  local overField = inField(mx, my) and not U.hovering(mx, my)
  local hoverNode = overField and pickNode(mx, my) or nil
  local hoverEdge = (overField and not hoverNode) and pickEdge(mx, my) or nil

  R.drawLinks(cam, run, hoverEdge, state.selEdge)
  R.drawNodes(cam, run, hoverNode, state.selNode)

  if state.dragFrom then
    R.drawLinkDrag(cam, run, state.dragFrom, mx, my, hoverNode ~= state.dragFrom and hoverNode or nil)
  elseif state.tool and overField and run.phase == "build" then
    R.drawPlaceGhost(cam, run, state.tool, mx, my)
  end

  if T.active and state.screen == "run" and not state.showReport and run.phase ~= "dead" then
    local fx, fy = T.focusPoint(run)
    if fx then R.drawFocusRing(cam, fx, fy) end
  end

  R.drawEffects(cam)
  love.graphics.setScissor()

  U.drawSidebar(run, state)
  U.drawBottom(run, state)
  U.drawInspector(run, state)
  if T.active and state.screen == "run" and not state.showReport and run.phase ~= "dead" then
    U.drawTutorial(run, state, T)
  end

  if state.screen == "meta" then
    U.drawMeta(state, meta)
  elseif state.screen == "help" then
    U.drawHelp(state)
  elseif run.phase == "dead" then
    U.drawDeath(run, state, meta)
  elseif state.showReport then
    U.drawReport(run, state)
  end
end

--------------------------------------------------------------------------------
-- Input
--------------------------------------------------------------------------------

local modal = function()
  return state.screen == "meta" or state.screen == "help"
      or state.showReport or run.phase == "dead"
end

function love.mousepressed(mx, my, button)
  if button == 2 or button == 3 then state.panning = true; return end
  if button ~= 1 then return end

  if U.click(mx, my) then return end
  if modal() or state.screen == "title" then return end
  if not inField(mx, my) then return end

  local n = pickNode(mx, my)
  if n then
    -- A press on a node begins a link drag; a release on the same node selects it.
    state.dragFrom = (run.phase == "build") and n or nil
    state.selNode, state.selEdge = n, nil
    return
  end

  if state.tool and run.phase == "build" then
    local wx, wy = cam:toWorld(mx, my)
    local node, err = run:buildNode(wx, wy, state.tool)
    if node then
      R.ring(wx, wy, Graph.KINDS[state.tool].color)
      A.play("place")
      if not love.keyboard.isDown("lshift", "rshift") then state.tool = nil end
    elseif err then
      R.floatText(wx, wy, err, P.bad)
      A.play("denied", 0.7)
    end
    return
  end

  local e = pickEdge(mx, my)
  if e then
    state.selEdge, state.selNode = e, nil
    return
  end

  -- Empty space: this may be a pan or may be a click that clears the selection.
  -- Which one it is gets decided by whether the mouse moves.
  state.maybePan = { moved = 0 }
end

function love.mousereleased(mx, my, button)
  if button == 2 or button == 3 then state.panning = false; return end
  if button ~= 1 then return end

  if state.maybePan then
    -- Never moved, so it was a click after all.
    if not state.panning then state.selNode, state.selEdge = nil, nil end
    state.maybePan, state.panning = nil, false
    return
  end

  if state.dragFrom then
    local target = pickNode(mx, my)
    if target and target ~= state.dragFrom then
      local e, err = run:buildLink(state.dragFrom, target)
      local a, b = run.g.nodes[state.dragFrom], run.g.nodes[target]
      if e then
        R.burst((a.x + b.x) / 2, (a.y + b.y) / 2, P.linkLive, 10)
        A.play("link")
      elseif err then
        R.floatText((a.x + b.x) / 2, (a.y + b.y) / 2, err, P.bad)
        A.play("denied", 0.7)
      end
    end
    state.dragFrom = nil
  end
end

function love.mousemoved(mx, my, dx, dy)
  if state.panning then cam:pan(dx, dy); return end
  if state.maybePan then
    state.maybePan.moved = state.maybePan.moved + math.abs(dx) + math.abs(dy)
    if state.maybePan.moved > 4 then
      state.panning = true
      cam:pan(dx, dy)
    end
  end
end

function love.wheelmoved(_, dy)
  local mx, my = love.mouse.getPosition()
  if inField(mx, my) and dy ~= 0 then cam:zoomAt(mx, my, dy) end
end

function love.keypressed(key)
  if key == "escape" then
    if T.active and state.screen == "run" and not state.tool then
      T.stop()
      state.tutorialSkipped = true
      return
    end
    if state.screen == "meta" or state.screen == "help" then
      state.screen = "run"
    elseif state.tool then
      state.tool = nil
    elseif state.selNode or state.selEdge then
      state.selNode, state.selEdge = nil, nil
    elseif state.screen == "run" then
      state.screen = "title"
    end
    return
  end

  if key == "h" then
    state.screen = (state.screen == "help") and "run" or "help"
    return
  end
  if key == "m" then
    state.screen = (state.screen == "meta") and "run" or "meta"
    return
  end

  if state.screen == "title" then
    if key == "return" or key == "space" then state.restart = true end
    return
  end

  if T.active and T.isExplain() and (key == "space" or key == "return")
     and not state.showReport and run.phase ~= "dead" and state.screen == "run" then
    T.advance()
    A.play("step", 0.8)
    return
  end

  if state.showReport and (key == "space" or key == "return") then
    run:beginNextWave()
    state.showReport = false
    return
  end
  if run.phase == "dead" and (key == "space" or key == "return") then
    state.restart = true
    return
  end

  if key == "1" then state.tool = (state.tool == "relay") and nil or "relay" end
  if key == "2" then state.tool = (state.tool == "hub") and nil or "hub" end
  if key == "3" then state.tool = (state.tool == "conduit") and nil or "conduit" end

  if (key == "space" or key == "return") and run.phase == "build" then
    state.pendingResolve = true
  end

  -- Quick actions on the current selection. A refused action says why, in the
  -- field: the inspector buttons grey out, but a keystroke has nowhere else to
  -- report failure.
  local function edgeMid(id)
    local e = run.g.edges[id]
    if not e then return nil end
    local na, nb = run.g.nodes[e.a], run.g.nodes[e.b]
    return (na.x + nb.x) / 2, (na.y + nb.y) / 2
  end

  if key == "u" then
    if state.selEdge then
      local x, y = edgeMid(state.selEdge)
      local ok, err = run:upgradeLink(state.selEdge)
      if ok then A.play("upgrade") end
      if not ok and err and x then R.floatText(x, y, err, P.bad); A.play("denied", 0.7) end
    elseif state.selNode then
      local n = run.g.nodes[state.selNode]
      local ok, err = run:upgradeNode(state.selNode)
      if ok then A.play("upgrade") end
      if not ok and err and n then R.floatText(n.x, n.y, err, P.bad); A.play("denied", 0.7) end
    end
  end

  if key == "x" or key == "delete" then
    if state.selEdge then
      local x, y = edgeMid(state.selEdge)
      local refund, err = run:demolishLink(state.selEdge)
      if refund then
        R.burst(x, y, P.textFaint, 10)
        R.floatText(x, y, "+" .. refund, P.energy)
        A.play("demolish")
        state.selEdge = nil
      elseif err and x then
        R.floatText(x, y, err, P.bad)
        A.play("denied", 0.7)
      end
    elseif state.selNode then
      local n = run.g.nodes[state.selNode]
      local refund, err = run:demolishNode(state.selNode)
      if refund then
        R.burst(n.x, n.y, P.textFaint, 10)
        R.floatText(n.x, n.y, "+" .. refund, P.energy)
        A.play("demolish")
        state.selNode = nil
      elseif err and n then
        R.floatText(n.x, n.y, err, P.bad)
        A.play("denied", 0.7)
      end
    end
  end
  if key == "s" then
    local m = A.toggleMute()
    R.floatText(run.source.x, run.source.y, m and "SOUND OFF" or "SOUND ON", P.textDim)
  end
  if key == "c" then cam:centerOn(run.source.x, run.source.y) end
  if key == "t" then
    local sinks = run.g:nodesOfKind("sink")
    if #sinks > 0 then
      state.tIdx = ((state.tIdx or 0) % #sinks) + 1
      local t = sinks[state.tIdx]
      cam:centerOn(t.x, t.y)
    end
  end
end
