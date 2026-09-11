-- Archived contract game, available with --contracts.
--
-- A run is twelve contracts. Each one is a site, a fixed budget and a declared
-- threat, and the whole decision is how to spend that budget on that geometry.
love.filesystem.setRequirePath("src/?.lua;?.lua")

local P        = require("palette")
local Graph    = require("graph")
local Contract = require("contract")
local Campaign = require("campaign")
local Solver   = require("solver")
local Meta     = require("meta")
local Camera   = require("camera")
local R        = require("render")
local U        = require("ui")
local A        = require("audio")
local T        = require("tutorial")

local state = {
  screen = "title",      -- title | contract | result | complete | help
  tool = nil,
  selNode = nil, selEdge = nil,
  dragFrom = nil,
  panning = false, maybePan = nil,
  wantCommit = false, wantRetry = false, wantNext = false,
  wantNewRun = false, startTutorial = false,
  recorded = false,
}

local meta, camp, ct, cam
local handleIntents  -- defined below, used by the scripted walkthroughs

-- Test modes.
local shot   = { active = false, frames = 0 }
local smoke  = { active = false, frames = 0, fails = 0 }
local soak   = { active = false, frames = 0, contracts = 0, draws = 0, fails = 0 }
local tut    = { active = false, frames = 0, fails = 0 }
local audiotest = false

-- A campaign-shaped stub so the tutorial contract can use the same UI.
local tutorialCamp = { progress = function() return 1, 1 end, totalUnder = 0, specs = { true } }

--------------------------------------------------------------------------------

local function layout()
  local W, H = love.graphics.getDimensions()
  cam:setViewport(U.SIDEBAR, 0, W - U.SIDEBAR, H - U.BOTTOM)
end

-- Frame the whole site: a contract is meant to be readable at a glance, and
-- hunting for an off-screen terminal is not part of the puzzle.
-- Frame what matters, not the whole plot. Fitting the full site bounds leaves
-- the source and terminals as a small cluster in the middle of empty ground;
-- fitting the content plus room to build around it fills the screen.
local function fitCamera()
  if not (ct and ct.spec and ct.spec.bounds) then return end
  local b = ct.spec.bounds
  layout()

  local x0, y0 = ct.source.x, ct.source.y
  local x1, y1 = x0, y0
  local function include(x, y, r)
    r = r or 0
    x0 = math.min(x0, x - r); x1 = math.max(x1, x + r)
    y0 = math.min(y0, y - r); y1 = math.max(y1, y + r)
  end
  for _, t in ipairs(ct.terminals) do include(t.x, t.y) end
  for _, o in ipairs(ct.obstacles) do include(o.x, o.y, o.r) end

  local margin = 200          -- room to route around the outside
  x0, y0 = math.max(b.x, x0 - margin), math.max(b.y, y0 - margin)
  x1, y1 = math.min(b.x + b.w, x1 + margin), math.min(b.y + b.h, y1 + margin)

  local s = math.min((cam.vw - 50) / math.max(1, x1 - x0),
                     (cam.vh - 50) / math.max(1, y1 - y0))
  s = math.max(0.3, math.min(1.5, s))
  cam.scale, cam.targetScale = s, s
  cam:centerOn((x0 + x1) / 2, (y0 + y1) / 2)
  cam.fieldW, cam.fieldH = b.w, b.h
end

local function clearSelection()
  state.tool, state.selNode, state.selEdge, state.dragFrom = nil, nil, nil, nil
end

local function startCampaign(seed)
  camp = Campaign.new(seed)
  if not camp:ok() then return false end
  ct = camp:current()
  state.screen = "contract"
  state.recorded = false
  T.active = false
  clearSelection()
  fitCamera()
  return true
end

local function startTutorial()
  camp = nil
  ct = Contract.new(T.SPEC)
  T.start()
  state.screen = "contract"
  clearSelection()
  fitCamera()
end

function love.load(args)
  love.graphics.setBackgroundColor(P.bg)
  love.graphics.setLineStyle("smooth")
  math.randomseed(os.time())
  R.init()
  A.init()
  meta = Meta.load()

  for _, a in ipairs(args or {}) do
    if a == "--shot"  then shot.active = true end
    if a == "--smoke" then smoke.active = true end
    if a == "--soak"  then soak.active = true end
    if a == "--tut"   then tut.active = true end
    if a == "--audio" then audiotest = true end
  end

  if shot.active or smoke.active or soak.active or tut.active or audiotest then
    -- Test modes never touch the player's save, never make noise, and turn any
    -- runtime error into a non-zero exit instead of an interactive screen.
    Meta.save = function() end
    meta = { insight = 0, unlocked = {}, runs = 0, bestContract = 0, bestUnder = 0 }
    A.setEnabled(false)
    local function die(msg)
      io.stderr:write("RUNTIME ERROR: " .. tostring(msg) .. "\n")
      io.stderr:write(debug.traceback("", 2) .. "\n")
      love.event.quit(1)
      return function() end
    end
    love.errorhandler, love.errhand = die, die
  end

  cam = Camera.new(1400, 1000)
  -- A live contract sits behind the title screen so the field is never blank.
  if not startCampaign(nil) then
    ct = Contract.new(T.SPEC)
  end
  if not (smoke.active or soak.active or tut.active or shot.active) then
    state.screen = "title"
  end
  fitCamera()
end

function love.resize() layout() end

--------------------------------------------------------------------------------
-- Picking
--------------------------------------------------------------------------------

local function inField(mx, my)
  return mx > U.SIDEBAR and my < love.graphics.getHeight() - U.BOTTOM
end

local function pickNode(mx, my)
  local best, bestD
  for _, n in ipairs(ct.g.nodes) do
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
  for _, e in ipairs(ct.g.edges) do
    if e.alive then
      local na, nb = ct.g.nodes[e.a], ct.g.nodes[e.b]
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
-- Commit
--------------------------------------------------------------------------------

local function doCommit()
  if ct.committed then return end
  local result = ct:commit()
  if not result then return end

  A.play("resolve", 0.9)
  for i, r in ipairs(result.removed) do
    local x, y
    if r.kind == "edge" then
      local e = ct.g.edges[r.id]
      local na, nb = ct.g.nodes[e.a], ct.g.nodes[e.b]
      x, y = (na.x + nb.x) / 2, (na.y + nb.y) / 2
    else
      local n = ct.g.nodes[r.id]
      x, y = n.x, n.y
    end
    R.burst(x, y, P.cut, r.kind == "node" and 30 or 18)
    R.ring(x, y, P.cut)
    A.play(r.kind == "node" and "destroy" or "sever", 1.0, 0.94 + i * 0.05)
  end
  cam:shakeBy(result.success and 0.45 or 1.0)
  A.play(result.success and "held" or "collapse", 0.9)

  if camp then camp:record(result) end
  clearSelection()
  state.screen = "result"
end

local function nextContract()
  if not camp then
    -- The tutorial's single contract: back to the title once it is done.
    state.screen = "title"
    return
  end
  if camp:advance() then
    ct = camp:current()
    clearSelection()
    fitCamera()
    state.screen = "contract"
    local tool = camp:newToolThisContract()
    if tool then
      state.newTool = tool
      A.play("unlock", 0.9)
    end
  else
    if not state.recorded then
      state.recorded = true
      Meta.record(meta, camp)
    end
    state.screen = "complete"
  end
end

local function retryContract()
  if camp then ct = camp:retry() else ct = Contract.new(T.SPEC) end
  clearSelection()
  state.screen = "contract"
end

--------------------------------------------------------------------------------
-- Scripted walkthroughs, driven through the real callbacks.
--------------------------------------------------------------------------------

local function expect(box, cond, what)
  if cond then
    print("  ok    " .. what)
  else
    box.fails = box.fails + 1
    print("  FAIL  " .. what)
  end
end

local function runSmoke()
  print("smoke: input paths on a contract")
  local e = function(c, w) expect(smoke, c, w) end
  startCampaign(4242)
  e(ct ~= nil and camp ~= nil, "a campaign generates and opens a contract")
  e(ct.budget > 0 and ct.spent == 0, "budget set, nothing spent")
  e(not ct:isSolved(), "an empty site is not solved")

  local src = ct.g.nodes[ct.source.id]

  -- Place a relay next to the source, then link to it.
  love.keypressed("1")
  e(state.tool == "relay", "key 1 arms the relay")
  local wx, wy = src.x + 130, src.y + 30
  local sx, sy = cam:toScreen(wx, wy)
  local before = #ct.g:aliveNodes()
  love.mousepressed(sx, sy, 1)
  e(#ct.g:aliveNodes() == before + 1, "clicking the site places a node")
  e(ct.spent > 0, "placing spends budget")
  local relay = ct.g.nodes[#ct.g.nodes]

  local ax, ay = cam:toScreen(src.x, src.y)
  love.mousepressed(ax, ay, 1)
  e(state.dragFrom == src.id, "pressing a node starts a link drag")
  love.mousereleased(sx, sy, 1)
  e(ct.g:hasEdge(src.id, relay.id) ~= nil, "releasing on a node lays a link")

  -- Upgrade and demolish, with a full refund.
  local eid = ct.g:hasEdge(src.id, relay.id)
  state.selEdge = eid
  local cap0, spent0 = ct.g.edges[eid].cap, ct.spent
  love.keypressed("u")
  e(ct.g.edges[eid].cap == cap0 + 1, "u upgrades link capacity")
  e(ct.spent == spent0 + ct:capCost(), "the upgrade is charged")
  love.keypressed("x")
  e(ct.g:hasEdge(src.id, relay.id) == nil, "x demolishes the link")
  e(ct.spent < spent0, "demolition refunds")

  -- Camera.
  local cx0, cy0 = cam.x, cam.y
  love.mousepressed(ax, ay, 2); love.mousemoved(ax + 30, ay + 20, 30, 20)
  love.mousereleased(ax, ay, 2)
  e(cam.x ~= cx0 or cam.y ~= cy0, "right-drag pans")

  cx0, cy0 = cam.x, cam.y
  local ex, ey = cam:toScreen(ct.spec.bounds.x + 40, ct.spec.bounds.y + ct.spec.bounds.h - 40)
  if ex > U.SIDEBAR and ey < love.graphics.getHeight() - U.BOTTOM then
    love.mousepressed(ex, ey, 1)
    love.mousemoved(ex + 40, ey + 30, 40, 30)
    love.mousereleased(ex + 40, ey + 30, 1)
    e(cam.x ~= cx0 or cam.y ~= cy0, "left-drag on empty space pans")
  end

  -- Solve it properly and commit.
  local built = Solver.autoBuild(ct)
  e(built, "the site can be solved within budget")
  e(ct:resilience() >= ct.demand, "the solution survives the declared threat")
  e(ct.spent <= ct.budget, "and stays inside the budget")

  love.keypressed("return")
  handleIntents()
  e(ct.committed, "enter commits the contract")
  e(ct.result ~= nil and ct.result.success, "the contract holds")
  e(state.screen == "result", "the result screen opens")
  e(#ct.result.removed == ct.threat.count, "the adversary took exactly what it declared")

  state.wantNext = true; handleIntents()
  e(select(1, camp:progress()) == 2, "advancing moves to the next contract")
  e(ct.spent == 0, "the next contract starts from an empty site")
end

local function runTutorialTest()
  print("tutorial: walking every step")
  local e = function(c, w) expect(tut, c, w) end
  local function at(n, what)
    e(T.active and T.step == n, string.format("step %d: %s", n, what))
  end

  startTutorial()
  at(1, "a contract, not a wave")
  T.advance(); at(2, "the adversary is declared")
  T.advance(); at(3, "lay a link")

  local src = ct.g.nodes[ct.source.id]
  local term = ct.terminals[1]
  local ax, ay = cam:toScreen(src.x, src.y)
  local bx, by = cam:toScreen(term.x, term.y)
  love.mousepressed(ax, ay, 1)
  love.mousereleased(bx, by, 1)
  e(ct.g:hasEdge(src.id, term.id) ~= nil, "source links straight to the terminal")
  T.update(ct); at(4, "widen it")

  local eid = ct.g:hasEdge(src.id, term.id)
  state.selEdge = eid
  local guard = 0
  while ct.flow < ct.demand and guard < 20 do love.keypressed("u"); guard = guard + 1 end
  T.update(ct); at(5, "you deliver 2 and survive 0")
  e(ct:resilience() == 0, "one route survives nothing")

  T.advance(); at(6, "build a second route")
  love.keypressed("1")
  local rx, ry = cam:toScreen(src.x + 135, src.y + 160)
  love.mousepressed(rx, ry, 1)
  local relay = ct.g.nodes[#ct.g.nodes]
  e(relay.kind == "relay", "a relay is placed off the line")
  local px, py = cam:toScreen(relay.x, relay.y)
  love.mousepressed(ax, ay, 1); love.mousereleased(px, py, 1)
  love.mousepressed(px, py, 1); love.mousereleased(bx, by, 1)
  local e1 = ct.g:hasEdge(src.id, relay.id)
  local e2 = ct.g:hasEdge(relay.id, term.id)
  e(e1 ~= nil and e2 ~= nil, "the second route is linked")
  state.selEdge = e1; love.keypressed("u")
  state.selEdge = e2; love.keypressed("u")
  T.update(ct)
  e(ct:resilience() >= ct.demand, "two disjoint routes survive the strike")
  at(7, "now it holds")

  T.advance(); at(8, "commit")
  love.keypressed("return"); handleIntents()
  e(ct.committed, "the contract is committed")
  e(ct.result.success, "and it held")
  T.update(ct); at(9, "budget and par")
  T.advance()
  e(not T.active and T.finished, "the tutorial closes")
end

--------------------------------------------------------------------------------
-- Update
--------------------------------------------------------------------------------

handleIntents = function()
  if state.wantNewRun then
    state.wantNewRun = false
    startCampaign(nil)
  end
  if state.startTutorial then
    state.startTutorial = false
    startTutorial()
  end
  if state.wantCommit then
    state.wantCommit = false
    doCommit()
  end
  if state.wantRetry then
    state.wantRetry = false
    retryContract()
  end
  if state.wantNext then
    state.wantNext = false
    nextContract()
  end
end

function love.update(dt)
  R.update(dt)
  cam:update(dt)
  if state.screen == "title" then cam:pan(-10 * dt, -3 * dt) end

  if T.active and ct then
    if T.update(ct) then A.play("step", 0.8) end
    if not T.active and not meta.tutorialDone then
      meta.tutorialDone = true
      Meta.save(meta)
    end
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
    if soak.frames == 2 then startCampaign(4242) end
    if soak.frames > 3 then
      if state.screen == "contract" then
        if not Solver.autoBuild(ct) then
          soak.fails = soak.fails + 1
          print(string.format("  FAIL  contract %d could not be built", select(1, camp:progress())))
          love.event.quit(1)
          return
        end
        doCommit()
      elseif state.screen == "result" then
        if not ct.result.success then
          soak.fails = soak.fails + 1
          print(string.format("  FAIL  contract %d did not hold", select(1, camp:progress())))
          love.event.quit(1)
          return
        end
        soak.contracts = soak.contracts + 1
        nextContract()
      elseif state.screen == "complete" then
        print(string.format("soak: %d contracts held, %d frames drawn, no errors",
          soak.contracts, soak.draws))
        love.event.quit(0)
        return
      end
    end
    return
  end

  if smoke.active then
    smoke.frames = smoke.frames + 1
    if smoke.frames == 3 then runSmoke() end
    if smoke.frames > 8 then
      print(smoke.fails == 0 and "smoke: all input paths ok"
                              or string.format("smoke: %d FAILURES", smoke.fails))
      love.event.quit(smoke.fails == 0 and 0 or 1)
    end
    return
  end

  if tut.active then
    tut.frames = tut.frames + 1
    if tut.frames == 3 then runTutorialTest() end
    if tut.frames > 8 then
      print(tut.fails == 0 and "tutorial: all steps completable"
                             or string.format("tutorial: %d FAILURES", tut.fails))
      love.event.quit(tut.fails == 0 and 0 or 1)
    end
    return
  end

  if shot.active then
    shot.frames = shot.frames + 1
    if shot.frames == 4 then
      startCampaign(4242); state.screen = "contract"
    elseif shot.frames == 8 then
      love.graphics.captureScreenshot("01-contract-empty.png")
    elseif shot.frames == 10 then
      Solver.autoBuild(ct)
    elseif shot.frames == 18 then
      love.graphics.captureScreenshot("02-contract-solved.png")
    elseif shot.frames == 20 then
      for _ = 1, 5 do camp:advance() end
      ct = camp:current(); fitCamera(); Solver.autoBuild(ct)
    elseif shot.frames == 30 then
      love.graphics.captureScreenshot("03-late-contract.png")
    elseif shot.frames == 32 then
      doCommit()
    elseif shot.frames == 42 then
      love.graphics.captureScreenshot("04-result.png")
    elseif shot.frames == 46 then
      startTutorial()
    elseif shot.frames == 54 then
      love.graphics.captureScreenshot("05-tutorial.png")
    elseif shot.frames == 58 then
      state.screen = "help"
    elseif shot.frames == 66 then
      love.graphics.captureScreenshot("06-help.png")
    elseif shot.frames > 76 then
      love.event.quit()
    end
    return
  end

  handleIntents()

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
    R.drawGrid(cam, cam.fieldW, cam.fieldH)
    R.drawObstacles(cam, ct.obstacles)
    R.drawLinks(cam, ct, nil, nil)
    R.drawNodes(cam, ct, nil, nil)
    U.drawTitle(state, meta)
    return
  end

  love.graphics.setScissor(U.SIDEBAR, 0, W - U.SIDEBAR, H - U.BOTTOM)
  R.drawGrid(cam, cam.fieldW, cam.fieldH)
  R.drawObstacles(cam, ct.obstacles)

  local mx, my = love.mouse.getPosition()
  local overField = inField(mx, my) and not U.hovering(mx, my)
  local hoverNode = overField and pickNode(mx, my) or nil
  local hoverEdge = (overField and not hoverNode) and pickEdge(mx, my) or nil

  ct:resilience()   -- keeps the doomed set current for the renderer
  R.drawLinks(cam, ct, hoverEdge, state.selEdge)
  R.drawNodes(cam, ct, hoverNode, state.selNode)

  if state.dragFrom then
    R.drawLinkDrag(cam, ct, state.dragFrom, mx, my,
      hoverNode ~= state.dragFrom and hoverNode or nil)
  elseif state.tool and overField and not ct.committed then
    R.drawPlaceGhost(cam, ct, state.tool, mx, my)
  end

  if T.active and state.screen == "contract" then
    local fx, fy = T.focusPoint(ct)
    if fx then R.drawFocusRing(cam, fx, fy) end
  end

  R.drawEffects(cam)
  love.graphics.setScissor()

  U.drawSidebar(ct, camp or (T.active and tutorialCamp or nil), state)
  U.drawBottom(ct, state)
  U.drawInspector(ct, state)

  if state.screen == "help" then
    U.drawHelp(state)
  elseif state.screen == "result" then
    U.drawResult(ct, camp or tutorialCamp, state)
  elseif state.screen == "complete" then
    U.drawComplete(camp, state)
  elseif T.active then
    U.drawTutorial(ct, state, T)
  end
end

--------------------------------------------------------------------------------
-- Input
--------------------------------------------------------------------------------

local function modal()
  return state.screen == "help" or state.screen == "result"
      or state.screen == "complete" or state.screen == "title"
end

function love.mousepressed(mx, my, button)
  if button == 2 or button == 3 then state.panning = true; return end
  if button ~= 1 then return end
  if U.click(mx, my) then return end
  if modal() then return end
  if not inField(mx, my) then return end
  if ct.committed then return end

  local n = pickNode(mx, my)
  if n then
    state.dragFrom = n
    state.selNode, state.selEdge = n, nil
    return
  end

  if state.tool then
    local wx, wy = cam:toWorld(mx, my)
    local node, err = ct:buildNode(wx, wy, state.tool)
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
  if e then state.selEdge, state.selNode = e, nil; return end
  state.maybePan = { moved = 0 }
end

function love.mousereleased(mx, my, button)
  if button == 2 or button == 3 then state.panning = false; return end
  if button ~= 1 then return end

  if state.maybePan then
    if not state.panning then state.selNode, state.selEdge = nil, nil end
    state.maybePan, state.panning = nil, false
    return
  end

  if state.dragFrom then
    local target = pickNode(mx, my)
    if target and target ~= state.dragFrom then
      local a, b = ct.g.nodes[state.dragFrom], ct.g.nodes[target]
      local e, err = ct:buildLink(state.dragFrom, target)
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
    if state.screen == "help" then state.screen = "contract"
    elseif T.active then T.stop()
    elseif state.tool then state.tool = nil
    elseif state.selNode or state.selEdge then state.selNode, state.selEdge = nil, nil
    elseif state.screen == "contract" then state.screen = "title" end
    return
  end

  if key == "h" then
    state.screen = (state.screen == "help") and "contract" or "help"
    return
  end
  if key == "s" then
    local m = A.toggleMute()
    R.floatText(ct.source.x, ct.source.y, m and "SOUND OFF" or "SOUND ON", P.textDim)
    return
  end

  if state.screen == "title" then
    if key == "return" or key == "space" then state.wantNewRun = true end
    return
  end

  -- An explain step consumes space so committing and advancing never collide.
  if T.active and T.isExplain() and (key == "space" or key == "return")
     and state.screen == "contract" then
    T.advance(); A.play("step", 0.8)
    return
  end

  if state.screen == "result" then
    if key == "return" or key == "space" then
      state.wantNext = ct.result and ct.result.success or false
      state.wantRetry = not (ct.result and ct.result.success)
    end
    return
  end
  if state.screen == "complete" then
    if key == "return" or key == "space" then state.wantNewRun = true end
    return
  end

  if key == "1" and ct.tools.relay then state.tool = (state.tool == "relay") and nil or "relay" end
  if key == "2" and ct.tools.hub then state.tool = (state.tool == "hub") and nil or "hub" end
  if key == "3" and ct.tools.conduit then state.tool = (state.tool == "conduit") and nil or "conduit" end

  if key == "return" and state.screen == "contract" then state.wantCommit = true end
  if key == "r" then state.wantRetry = true end
  if key == "f" then fitCamera() end

  local function edgeMid(id)
    local e = ct.g.edges[id]
    if not e then return nil end
    local na, nb = ct.g.nodes[e.a], ct.g.nodes[e.b]
    return (na.x + nb.x) / 2, (na.y + nb.y) / 2
  end

  if key == "u" and state.selEdge then
    local x, y = edgeMid(state.selEdge)
    local okUp, err = ct:upgradeLink(state.selEdge)
    if okUp then A.play("upgrade")
    elseif err and x then R.floatText(x, y, err, P.bad); A.play("denied", 0.7) end
  end

  if (key == "x" or key == "delete") then
    if state.selEdge then
      local x, y = edgeMid(state.selEdge)
      local refund, err = ct:demolishLink(state.selEdge)
      if refund then
        A.play("demolish"); R.floatText(x, y, "+" .. refund, P.energy)
        state.selEdge = nil
      elseif err and x then R.floatText(x, y, err, P.bad); A.play("denied", 0.7) end
    elseif state.selNode then
      local n = ct.g.nodes[state.selNode]
      local refund, err = ct:demolishNode(state.selNode)
      if refund then
        A.play("demolish"); R.floatText(n.x, n.y, "+" .. refund, P.energy)
        state.selNode = nil
      elseif err and n then R.floatText(n.x, n.y, err, P.bad); A.play("denied", 0.7) end
    end
  end
end
