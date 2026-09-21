-- Rounds mode, on screen.
--
-- Build between rounds, then press Start and watch the houses come in one at a
-- time. Everything the player can do is on the left; the map is on the right.
-- The run lives in its own save file beside the companies and never touches
-- them.
love.filesystem.setRequirePath("src/?.lua;?.lua")

local Rounds = require("rounds")
local D = Rounds.D
local Camera = require("camera")
local P = require("palette")
local R = require("render")
local A = require("audio")
local Draw = require("company_render")
local lg = love.graphics

local App = {}
local run, cam
local testMode
local SIDE = 340
local RUN_FILE, RECORD_FILE = "rounds_run.lua", "rounds_records.lua"

local state = {
  tool = nil, size = 1, sel = nil, selPipe = nil,
  drag = nil, pan = nil, modal = nil, speed = 1,
  toast = nil, toastTime = 0, toastBad = false,
  flash = {}, pops = {},
}
local records = { best = 0, bestStrict = 0, wins = 0, strictWins = 0, runs = 0 }
local buttons = {}

local COL = {
  zone = { 0.62, 0.56, 0.98 },
  zoneNew = { 0.98, 0.82, 0.38 },
  river = { 0.20, 0.36, 0.56 },
  riverEdge = { 0.30, 0.48, 0.72 },
  rock = { 0.26, 0.24, 0.30 },
  rockEdge = { 0.36, 0.33, 0.42 },
  well = { 0.42, 0.82, 0.98 },
  junction = { 0.62, 0.56, 0.98 },
  tower = { 0.36, 0.85, 0.62 },
}

--------------------------------------------------------------------------------
-- Files
--------------------------------------------------------------------------------

local function readTable(name)
  if not love.filesystem.getInfo(name) then return nil end
  local text = love.filesystem.read(name)
  return Rounds.deserialize(text)
end

local function saveRun()
  if testMode or not run then return end
  love.filesystem.write(RUN_FILE, Rounds.serialize(run:pack()))
end

local function saveRecords()
  if testMode then return end
  love.filesystem.write(RECORD_FILE, Rounds.serialize(records))
end

local function noteRecord()
  if run.strict then
    records.bestStrict = math.max(records.bestStrict or 0, run.round)
  else
    records.best = math.max(records.best or 0, run.round)
  end
  saveRecords()
end

--------------------------------------------------------------------------------
-- Small helpers
--------------------------------------------------------------------------------

local function toast(msg, bad)
  state.toast, state.toastBad, state.toastTime = msg, bad and true or false, 3.5
  if bad then A.play("denied", 0.6) end
end

local function dist(ax, ay, bx, by) return math.sqrt((ax - bx) ^ 2 + (ay - by) ^ 2) end

local function money(n) return "$" .. tostring(math.floor(n + 0.5)) end

local function text(s, x, y, font, color, w, align)
  lg.setFont(R.fonts[font or "body"])
  lg.setColor(color or P.text)
  if w then lg.printf(tostring(s), math.floor(x), math.floor(y), w, align or "left")
  else lg.print(tostring(s), math.floor(x), math.floor(y)) end
end

local function width(s, font) return R.fonts[font or "body"]:getWidth(tostring(s)) end

local function button(id, label, x, y, w, h, fn, opts)
  opts = opts or {}
  local enabled = opts.enabled ~= false
  local mx, my = love.mouse.getPosition()
  local hover = enabled and mx >= x and mx < x + w and my >= y and my < y + h
  local color = opts.color or P.flow
  local pulse = opts.emphasis and enabled and (0.5 + 0.5 * math.sin(R.t * 3)) or 0
  lg.setColor(opts.active and P.with(color, 0.20)
    or opts.emphasis and enabled and P.with(color, 0.16 + 0.08 * pulse)
    or hover and P.hover or enabled and P.surface or P.panel)
  lg.rectangle("fill", x, y, w, h, 6)
  lg.setColor(opts.active and P.with(color, 0.85)
    or opts.emphasis and enabled and P.with(color, 0.75)
    or hover and P.textFaint or P.with(P.panelEdge, enabled and 0.9 or 0.4))
  lg.setLineWidth(1)
  lg.rectangle("line", x + 0.5, y + 0.5, w - 1, h - 1, 6)
  local fg = enabled and ((opts.active or opts.emphasis) and color or P.text) or P.textFaint
  local font = opts.font or "body"
  if opts.sub then
    text(label, x, y + h / 2 - 17, font, fg, w, "center")
    text(opts.sub, x, y + h / 2 + 2, "small", enabled and P.textDim or P.textFaint, w, "center")
  else
    lg.setFont(R.fonts[font])
    text(label, x, y + (h - R.fonts[font]:getHeight()) / 2, font, fg, w, "center")
  end
  buttons[#buttons + 1] = { id = id, x = x, y = y, w = w, h = h, fn = fn, enabled = enabled, tip = opts.tip }
  return hover
end

local function panel(x, y, w, h, edge)
  lg.setColor(P.with(P.panel, 0.96))
  lg.rectangle("fill", x, y, w, h, 8)
  lg.setColor(edge or P.panelEdge)
  lg.setLineWidth(1)
  lg.rectangle("line", x + 0.5, y + 0.5, w - 1, h - 1, 8)
end

--------------------------------------------------------------------------------
-- Camera
--------------------------------------------------------------------------------

local function layout()
  local w, h = R.dimensions()
  cam:setViewport(SIDE, 0, w - SIDE, h)
end

local function fit()
  layout()
  cam.x, cam.y = run.w / 2, run.h / 2
  cam.scale = math.min(cam.vw / (run.w + 120), cam.vh / (run.h + 120))
  cam.targetScale = cam.scale
end

local function toWorld(sx, sy) return cam:toWorld(sx, sy) end

--------------------------------------------------------------------------------
-- Starting, continuing, leaving
--------------------------------------------------------------------------------

local function fresh(strict, seed)
  run = Rounds.new({ strict = strict, seed = seed })
  records.runs = (records.runs or 0) + 1
  state.tool, state.sel, state.selPipe, state.modal = nil, nil, nil, nil
  state.lastHouses, state.result = nil, nil
  cam = Camera.new(run.w, run.h)
  cam:follow({ x = 0, y = 0, w = run.w, h = run.h })
  fit()
  saveRun(); saveRecords()
  if (records.runs or 0) <= 1 then state.modal = "help" end
end

local function leave()
  saveRun()
  if not testMode then love.filesystem.write("mode.txt", "company") end
  App.switchTo("company_app")
end

--------------------------------------------------------------------------------
-- Selection and building
--------------------------------------------------------------------------------

local function buildingAt(sx, sy)
  local best, bd
  for _, b in ipairs(run.buildings) do
    local x, y = cam:toScreen(b.x, b.y)
    local d = dist(sx, sy, x, y)
    local r = math.max(10, R.sym(b.kind == "junction" and 13 or 17, cam.scale)) + 4
    if d < r and (not bd or d < bd) then best, bd = b, d end
  end
  return best
end

local function segDist(px, py, ax, ay, bx, by)
  local dx, dy = bx - ax, by - ay
  local len2 = dx * dx + dy * dy
  local t = len2 > 0 and math.max(0, math.min(1, ((px - ax) * dx + (py - ay) * dy) / len2)) or 0
  return dist(px, py, ax + t * dx, ay + t * dy)
end

local function pipeAt(sx, sy)
  local best, bd = nil, 7
  for _, p in ipairs(run.pipes) do
    local a, b = run:byId(p.a), run:byId(p.b)
    local ax, ay = cam:toScreen(a.x, a.y)
    local bx, by = cam:toScreen(b.x, b.y)
    local d = segDist(sx, sy, ax, ay, bx, by)
    if d < bd then best, bd = p, d end
  end
  return best
end

local function houseAt(sx, sy)
  for _, h in ipairs(state.lastHouses or run.houses or {}) do
    if h.cover then
      local x, y = cam:toScreen(h.x, h.y)
      if dist(sx, sy, x, y) < math.max(9, R.sym(12, cam.scale)) then return h end
    end
  end
end

local function select(b)
  state.sel, state.selPipe = b and b.id or nil, nil
end

local function placeAt(wx, wy)
  local b, err = run:build(state.tool, wx, wy)
  if not b then toast(err, true); return end
  A.play("build", 0.7)
  R.ring(b.x, b.y, COL[b.kind])
  toast(D.BUILDINGS[b.kind].name .. " built for " .. money(b.paid))
  saveRun()
  -- A junction or tower stays in hand, since they come in groups. A well goes
  -- back, because there is only ever one spring under the cursor.
  if b.kind == "well" then state.tool = nil end
  select(b)
end

local function upgradeSelected()
  local b = state.sel and run:byId(state.sel)
  if b then
    local ok, err = run:upgrade(b.id)
    if not ok then toast(err, true); return end
    A.play("upgrade", 0.7)
    R.ring(b.x, b.y, P.good)
    toast(D.BUILDINGS[b.kind].name .. " is level " .. b.level)
    saveRun()
    return
  end
  local p = state.selPipe and run:pipeById(state.selPipe)
  if p then
    local ok, err = run:widen(p.id)
    if not ok then toast(err, true); return end
    A.play("upgrade", 0.7)
    toast("Main widened to " .. D.PIPES[p.size].name)
    saveRun()
  end
end

local function sellSelected()
  local b = state.sel and run:byId(state.sel)
  if b then
    local value, err = run:sell(b.id)
    if not value then toast(err, true); return end
    A.play("demolish", 0.7)
    R.burst(b.x, b.y, P.textDim, 10)
    toast("Sold for " .. money(value))
    state.sel = nil
    saveRun()
    return
  end
  local p = state.selPipe and run:pipeById(state.selPipe)
  if p then
    local value, err = run:sellPipe(p.id)
    if not value then toast(err, true); return end
    A.play("demolish", 0.7)
    toast("Main sold for " .. money(value))
    state.selPipe = nil
    saveRun()
  end
end

--------------------------------------------------------------------------------
-- Rounds
--------------------------------------------------------------------------------

local function startRound()
  if run.phase ~= "build" or state.modal then return end
  local plan = run:startRound()
  if not plan then return end
  state.tool, state.drag = nil, nil
  state.lastHouses, state.result = nil, nil
  state.pops = {}
  state.play = { t = 0, wait = 0,
    interval = math.max(0.07, math.min(0.42, 5.5 / math.max(1, #run.houses))) }
  A.play("resolve", 0.8)
  local n = 0
  for id in pairs(run.burst or {}) do
    local p = run:pipeById(id)
    if p then
      n = n + 1
      local a, b = run:byId(p.a), run:byId(p.b)
      R.burst((a.x + b.x) / 2, (a.y + b.y) / 2, P.bad, 22)
    end
  end
  if n > 0 then
    A.play("sever", 0.8)
    cam:shakeBy(0.35)
    toast(n == 1 and "A main has burst for this round" or (n .. " mains have burst for this round"), false)
  end
end

local function arriveOne()
  local h = run:arrive()
  if not h then return end
  state.pops[h] = 0
  if h.served then
    A.play("click", 0.35, 0.9 + math.min(0.6, run.arrived / 60))
    R.ring(h.x, h.y, P.flow)
  else
    A.play("sever", 0.7)
    R.burst(h.x, h.y, P.bad, 18)
    R.floatText(h.x, h.y - 26, "-" .. h.demand .. (h.demand == 1 and " life" or " lives"), P.bad)
    cam:shakeBy(0.12 + math.min(0.3, h.demand * 0.03))
    for id in pairs(h.cutPipes or {}) do state.flash[id] = 1.6 end
    toast(D.HOUSES[h.kind].name .. " went dry: " .. h.reason, false)
  end
  if run.phase == "lost" then
    A.play("collapse", 0.9)
    state.lastHouses = run.houses
    state.play = nil
    state.modal = "lost"
    noteRecord()
    saveRun()
  end
end

local function finish()
  state.lastHouses = run.houses
  state.lastSolve = run.lastSolve
  local result = run:finishRound()
  state.play = nil
  state.result = result
  if result.log.dry == 0 then A.play("held", 0.7) else A.play("step", 0.6) end
  state.modal = result.won and "won" or "result"
  if result.won then
    records.wins = (records.wins or 0) + 1
    if run.strict then records.strictWins = (records.strictWins or 0) + 1 end
    A.play("unlock", 0.8)
  end
  noteRecord()
  saveRun()
end

local function continue()
  if state.modal == "result" or state.modal == "won" then
    state.modal = nil
    state.lastHouses, state.lastSolve = nil, nil
  elseif state.modal == "help" then
    state.modal = nil
  end
end

--------------------------------------------------------------------------------
-- Drawing the map
--------------------------------------------------------------------------------

local function drawGround()
  local x0, y0 = cam:toScreen(0, 0)
  local x1, y1 = cam:toScreen(run.w, run.h)
  lg.setColor(P.land)
  lg.rectangle("fill", x0, y0, x1 - x0, y1 - y0, 6)
  -- A quiet grid every 200 m, so distances read without a ruler.
  lg.setColor(P.with(P.gridMajor, 0.55))
  lg.setLineWidth(1)
  for gx = 200, run.w - 1, 200 do
    local sx = cam:toScreen(gx, 0)
    lg.line(sx, y0, sx, y1)
  end
  for gy = 200, run.h - 1, 200 do
    local _, sy = cam:toScreen(0, gy)
    lg.line(x0, sy, x1, sy)
  end
end

local function drawRiver()
  local left, right = {}, {}
  local hw = run.river.w / 2
  for y = 0, run.h, 20 do
    local x = run:riverX(y)
    local lx, ly = cam:toScreen(x - hw, y)
    local rx, ry = cam:toScreen(x + hw, y)
    left[#left + 1], left[#left + 2] = lx, ly
    right[#right + 1], right[#right + 2] = rx, ry
  end
  lg.setColor(COL.river)
  for i = 1, #left - 2, 2 do
    lg.polygon("fill", left[i], left[i + 1], right[i], right[i + 1],
      right[i + 2], right[i + 3], left[i + 2], left[i + 3])
  end
  lg.setColor(COL.riverEdge)
  lg.setLineWidth(math.max(1, 2 * cam.scale))
  lg.line(left); lg.line(right)
end

local function drawRocks()
  for _, r in ipairs(run.rocks) do
    local x, y = cam:toScreen(r.x, r.y)
    lg.setColor(COL.rock)
    lg.circle("fill", x, y, r.r * cam.scale)
    lg.setColor(COL.rockEdge)
    lg.setLineWidth(math.max(1, 2 * cam.scale))
    lg.circle("line", x, y, r.r * cam.scale)
    -- Hatching says "hard ground" without a label.
    lg.setColor(P.with(COL.rockEdge, 0.6))
    local rr = r.r * cam.scale
    for k = -2, 2 do
      local o = k * rr * 0.35
      local half = math.sqrt(math.max(0, rr * rr - o * o)) * 0.8
      lg.line(x + o - half * 0.5, y - half * 0.85, x + o + half * 0.5, y + half * 0.85)
    end
  end
end

local function dashedCircle(x, y, r, segs, on)
  for i = 0, segs - 1 do
    local a0 = i / segs * math.pi * 2
    lg.arc("line", "open", x, y, r, a0, a0 + (math.pi * 2 / segs) * on)
  end
end

local function drawZones()
  local nextRound = run.round
  for _, z in ipairs(run.zones) do
    local x, y = cam:toScreen(z.x, z.y)
    local r = z.r * cam.scale
    local open = run:zoneOpen(z)
    local isNew = open and z.opens == nextRound
    local color = isNew and COL.zoneNew or COL.zone
    if open then
      lg.setColor(P.with(color, isNew and 0.10 + 0.04 * math.sin(R.t * 3) or 0.07))
      lg.circle("fill", x, y, r)
      lg.setColor(P.with(color, 0.55))
      lg.setLineWidth(math.max(1.2, 2.2 * cam.scale))
      lg.circle("line", x, y, r)
    else
      lg.setColor(P.with(P.textFaint, 0.35))
      lg.setLineWidth(math.max(1, 1.6 * cam.scale))
      dashedCircle(x, y, r, 28, 0.55)
    end
  end
end

-- Labels go on top of everything, so a main never runs through a zone's name.
local function drawZoneLabels()
  local nextRound = run.round
  for _, z in ipairs(run.zones) do
    local x, y = cam:toScreen(z.x, z.y)
    local r = z.r * cam.scale
    local open = run:zoneOpen(z)
    local isNew = open and z.opens == nextRound
    local color = isNew and COL.zoneNew or COL.zone
    -- The letter badge at the top of the ring, and the name beside it.
    local by = y - r
    local label = z.letter .. "  " .. z.name
    local f = cam.scale > 0.55 and "body" or "small"
    local lw = width(label, f) + 16
    lg.setColor(open and P.with(P.panel, 0.92) or P.with(P.panel, 0.7))
    lg.rectangle("fill", x - lw / 2, by - 11, lw, 22, 5)
    lg.setColor(open and P.with(color, 0.8) or P.with(P.textFaint, 0.5))
    lg.rectangle("line", x - lw / 2 + 0.5, by - 10.5, lw - 1, 21, 5)
    text(label, x - lw / 2, by - R.fonts[f]:getHeight() / 2, f, open and color or P.textFaint, lw, "center")
    if not open then
      text("opens round " .. z.opens, x - 80, y - 8, "small", P.with(P.textFaint, 0.8), 160, "center")
    elseif isNew then
      text("NEW THIS ROUND", x - 80, by + 16, "tiny", COL.zoneNew, 160, "center")
    end
  end
end

-- Every ring, as one soft wash, so what is covered reads at a glance. The
-- selected building's ring and the one under the cursor are drawn crisp.
local function drawRings()
  if run.phase ~= "build" and not state.sel then return end
  lg.setColor(P.with(P.flow, 0.045))
  for _, b in ipairs(run.buildings) do
    local x, y = cam:toScreen(b.x, b.y)
    lg.circle("fill", x, y, run:radius(b) * cam.scale)
  end
  local mx, my = love.mouse.getPosition()
  local hover = mx > SIDE and buildingAt(mx, my)
  for _, b in ipairs(run.buildings) do
    if b.id == state.sel or b == hover then
      local x, y = cam:toScreen(b.x, b.y)
      lg.setColor(P.with(COL[b.kind], b.id == state.sel and 0.8 or 0.45))
      lg.setLineWidth(1.5)
      dashedCircle(x, y, run:radius(b) * cam.scale, 48, 0.6)
    end
  end
end

local function drawSprings()
  for _, s in ipairs(run.springs) do
    if not run:springTaken(s) then
      local x, y = cam:toScreen(s.x, s.y)
      local r = math.max(5, R.sym(10, cam.scale))
      lg.setColor(P.with(COL.well, 0.12 + 0.05 * math.sin(R.t * 2 + s.index)))
      lg.circle("fill", x, y, r * 2.2)
      Draw.mark("water", x, y, r)
      -- How deep: the most levels a well here can take.
      for i = 1, 4 do
        lg.setColor(i <= s.depth and P.with(COL.well, 0.9) or P.with(P.textFaint, 0.3))
        lg.circle("fill", x - 9 + (i - 1) * 6, y + r * 1.6 + 4, 2)
      end
    end
  end
end

local function pipeColor(p, flow)
  local cap = D.PIPES[p.size].cap
  local u = math.abs(flow or 0) / cap
  if run.burst and run.burst[p.id] then return P.bad end
  if (state.flash[p.id] or 0) > 0 then
    local k = 0.5 + 0.5 * math.sin(R.t * 18)
    return { P.bad[1], P.bad[2] * k + P.link[2] * (1 - k), P.bad[3], 1 }
  end
  if not flow or flow == 0 then return P.link end
  if u > 0.92 then return P.warn end
  return P.linkLive
end

local function drawPipes()
  local solve = run.lastSolve or state.lastSolve
  local flows = solve and solve.pipeFlow or {}
  for _, p in ipairs(run.pipes) do
    local a, b = run:byId(p.a), run:byId(p.b)
    local ax, ay = cam:toScreen(a.x, a.y)
    local bx, by = cam:toScreen(b.x, b.y)
    local w = math.max(1.4, R.sym(1.5 + p.size * 1.6, cam.scale))
    local flow = flows[p.id]
    local burst = run.burst and run.burst[p.id]
    if p.id == state.selPipe then
      lg.setColor(P.with(P.text, 0.35))
      lg.setLineWidth(w + 6)
      lg.line(ax, ay, bx, by)
    end
    lg.setColor(P.bg)
    lg.setLineWidth(w + 2.5)
    lg.line(ax, ay, bx, by)
    lg.setColor(pipeColor(p, flow))
    lg.setLineWidth(w)
    if burst then
      -- Broken in the middle, with the gap showing.
      lg.line(ax, ay, ax + (bx - ax) * 0.44, ay + (by - ay) * 0.44)
      lg.line(ax + (bx - ax) * 0.56, ay + (by - ay) * 0.56, bx, by)
      local mx, my = (ax + bx) / 2, (ay + by) / 2
      lg.setLineWidth(2)
      lg.line(mx - 6, my - 6, mx + 6, my + 6); lg.line(mx - 6, my + 6, mx + 6, my - 6)
    else
      lg.line(ax, ay, bx, by)
    end
    -- Moving water: dots at a speed that grows with the flow, travelling the
    -- way it runs.
    if flow and math.abs(flow) > 0.01 and not burst then
      local len = dist(ax, ay, bx, by)
      local dir = flow > 0 and 1 or -1
      local spacing = 22
      local speed = 30 + 90 * math.min(1, math.abs(flow) / D.PIPES[p.size].cap)
      local off = (R.t * speed) % spacing
      lg.setColor(P.with(P.text, 0.8))
      for d = off, len, spacing do
        local t = d / len
        if dir < 0 then t = 1 - t end
        lg.circle("fill", ax + (bx - ax) * t, ay + (by - ay) * t, math.max(1.2, w * 0.32))
      end
    end
  end
end

local function pips(x, y, level, top, color)
  for i = 1, 4 do
    local px = x - 9 + (i - 1) * 6
    if i <= level then
      lg.setColor(color); lg.circle("fill", px, y, 2.2)
    elseif i <= top then
      lg.setColor(P.with(P.textFaint, 0.7)); lg.setLineWidth(1); lg.circle("line", px, y, 2)
    end
  end
end

local function drawBuilding(b, ghost)
  local x, y = cam:toScreen(b.x, b.y)
  local color = COL[b.kind]
  local a = ghost and 0.5 or 1
  local solve = run.lastSolve
  local hot = solve and solve.cutBuildings and solve.cutBuildings[b.id]
  if b.kind == "junction" then
    local r = math.max(6, R.sym(12, cam.scale))
    lg.setColor(P.with(P.surface, a)); lg.circle("fill", x, y, r)
    lg.setColor(P.with(hot and P.bad or color, a)); lg.setLineWidth(math.max(1.5, r * 0.22))
    lg.circle("line", x, y, r)
    -- One tick per port, so a full junction looks full.
    local ports = run:stat(b, "ports")
    local used = ghost and 0 or run:portsUsed(b)
    for i = 1, ports do
      local ang = (i - 1) / ports * math.pi * 2 - math.pi / 2
      lg.setColor(P.with(i <= used and color or P.textFaint, a))
      lg.circle("fill", x + math.cos(ang) * r * 0.5, y + math.sin(ang) * r * 0.5, math.max(1, r * 0.13))
    end
  elseif b.kind == "well" then
    local r = math.max(8, R.sym(16, cam.scale))
    lg.setColor(P.with(P.surface, a)); lg.circle("fill", x, y, r)
    lg.setColor(P.with(color, a)); lg.setLineWidth(math.max(1.5, r * 0.16))
    lg.circle("line", x, y, r)
    Draw.mark("water", x, y, r * 0.62, ghost)
  else
    -- A tank on legs.
    local r = math.max(8, R.sym(16, cam.scale))
    lg.setColor(P.with(P.surface, a))
    lg.rectangle("fill", x - r, y - r, r * 2, r * 1.2, r * 0.35)
    lg.setColor(P.with(color, a)); lg.setLineWidth(math.max(1.5, r * 0.14))
    lg.rectangle("line", x - r, y - r, r * 2, r * 1.2, r * 0.35)
    lg.line(x - r * 0.6, y + r * 0.2, x - r * 0.8, y + r)
    lg.line(x + r * 0.6, y + r * 0.2, x + r * 0.8, y + r)
    lg.line(x - r * 0.7, y + r * 0.6, x + r * 0.7, y + r * 0.6)
    Draw.mark("water", x, y - r * 0.4, r * 0.4, ghost)
  end
  if not ghost then
    local r = b.kind == "junction" and math.max(6, R.sym(12, cam.scale)) or math.max(8, R.sym(16, cam.scale))
    pips(x, y + r + 6, b.level, run:maxLevel(b), color)
    if b.id == state.sel then
      lg.setColor(P.text); lg.setLineWidth(1.5)
      lg.circle("line", x, y, r + 5 + math.sin(R.t * 4))
    end
  end
end

local HOUSE_GLYPH = { cottage = "house", house = "house", terrace = "workshop", estate = "estate", block = "estate" }
local HOUSE_SIZE = { cottage = 1.0, house = 1.3, terrace = 1.4, estate = 1.5, block = 2.2 }

local function drawHouses()
  local list = run.houses or state.lastHouses
  if not list then return end
  for _, h in ipairs(list) do
    if h.cover then
      local x, y = cam:toScreen(h.x, h.y)
      local age = state.pops[h] or 1
      local grow = math.min(1, age / 0.18)
      local s = math.max(0.6, R.sym(HOUSE_SIZE[h.kind], cam.scale)) * (0.4 + 0.6 * grow + 0.25 * math.sin(math.min(1, age / 0.3) * math.pi))
      -- The service drop, to the ring that fed it.
      if h.served and h.cover[1] then
        local b = run:byId(h.cover[1])
        if b then
          local bx, by = cam:toScreen(b.x, b.y)
          lg.setColor(P.with(P.linkLive, 0.35))
          lg.setLineWidth(1)
          lg.line(x, y, bx, by)
        end
      end
      lg.setColor(P.bg)
      lg.circle("fill", x, y, 12 * s)
      lg.setColor(h.served and P.flow or P.bad)
      Draw.clientGlyph(HOUSE_GLYPH[h.kind], x, y, s)
      if h.dry then
        lg.setColor(P.bad); lg.setLineWidth(2)
        lg.circle("line", x, y, 14 * s + 2)
      end
      if h.kind == "block" or cam.scale > 0.8 then
        text(h.demand, x - 20, y + 10 * s, "tiny", h.served and P.textDim or P.bad, 40, "center")
      end
    end
  end
end

local function drawDrag()
  if not state.drag then return end
  local a = run:byId(state.drag)
  if not a then return end
  local mx, my = love.mouse.getPosition()
  local ax, ay = cam:toScreen(a.x, a.y)
  local target = buildingAt(mx, my)
  local tx, ty = mx, my
  local err, cost
  if target and target ~= a then
    tx, ty = cam:toScreen(target.x, target.y)
    err = run:pipeError(a.id, target.id, state.size)
    if not err then cost = run:pipeCost(a, target, state.size) end
  end
  local ok = target and target ~= a and not err
  lg.setColor(ok and P.good or (target and target ~= a) and P.bad or P.ghost)
  lg.setLineWidth(math.max(1.5, R.sym(1.5 + state.size * 1.6, cam.scale)))
  lg.line(ax, ay, tx, ty)
  -- Reach, drawn around the start, so the player can see where the size stops.
  lg.setColor(P.with(P.ghost, 0.35)); lg.setLineWidth(1)
  dashedCircle(ax, ay, D.PIPES[state.size].reach * cam.scale, 64, 0.4)
  local wx, wy = toWorld(mx, my)
  local len = dist(a.x, a.y, target and target.x or wx, target and target.y or wy)
  local label = ok and (D.PIPES[state.size].name .. "  " .. money(cost))
    or err or (math.floor(len) .. " m of " .. D.PIPES[state.size].reach)
  local lw = width(label, "small") + 14
  lg.setColor(P.with(P.panel, 0.95)); lg.rectangle("fill", mx + 14, my - 30, lw, 22, 5)
  text(label, mx + 14, my - 26, "small", ok and P.good or err and P.bad or P.textDim, lw, "center")
end

local function drawGhost()
  if not state.tool or state.modal then return end
  local mx, my = love.mouse.getPosition()
  if mx < SIDE then return end
  local wx, wy = toWorld(mx, my)
  local err, px, py = run:placeError(state.tool, wx, wy)
  if state.tool == "well" and not err then wx, wy = px, py end
  local fake = { kind = state.tool, x = px or wx, y = py or wy, level = 1, id = -1 }
  local x, y = cam:toScreen(fake.x, fake.y)
  lg.setColor(P.with(err and P.bad or P.flow, 0.10))
  lg.circle("fill", x, y, D.BUILDINGS[state.tool].radius[1] * cam.scale)
  lg.setColor(P.with(err and P.bad or P.flow, 0.6)); lg.setLineWidth(1.5)
  dashedCircle(x, y, D.BUILDINGS[state.tool].radius[1] * cam.scale, 48, 0.6)
  drawBuilding(fake, true)
  local label = err or (D.BUILDINGS[state.tool].name .. "  " .. money(D.BUILDINGS[state.tool].cost[1]))
  local lw = width(label, "small") + 14
  lg.setColor(P.with(P.panel, 0.95)); lg.rectangle("fill", mx + 16, my + 12, lw, 22, 5)
  text(label, mx + 16, my + 16, "small", err and P.bad or P.text, lw, "center")
end

local function drawMap()
  local w, h = R.dimensions()
  lg.setScissor(SIDE, 0, w - SIDE, h)
  drawGround()
  drawRiver()
  drawRocks()
  drawZones()
  drawRings()
  drawSprings()
  drawPipes()
  for _, b in ipairs(run.buildings) do drawBuilding(b) end
  drawHouses()
  drawZoneLabels()
  drawDrag()
  drawGhost()
  R.drawEffects(cam)
  lg.setScissor()
end

--------------------------------------------------------------------------------
-- The sidebar
--------------------------------------------------------------------------------

local function plural(n, word)
  if n == 1 then return "1 " .. string.lower(word) end
  local w = string.lower(word)
  if w == "tower block" then return n .. " tower blocks" end
  return n .. " " .. w .. "s"
end

local function drawPreview(x, y, w)
  local inRound = run.phase == "round"
  local plan = run:plan(run.round)
  text(inRound and ("ROUND " .. run.round .. " RUNNING") or "NEXT ROUND", x, y, "small", P.textDim)
  y = y + 22
  if inRound then
    local total = #run.houses
    text(run.arrived .. " of " .. total .. " houses", x, y, "mid", P.text)
    y = y + 26
    lg.setColor(P.surface); lg.rectangle("fill", x, y, w, 6, 3)
    lg.setColor(P.flow); lg.rectangle("fill", x, y, w * run.arrived / math.max(1, total), 6, 3)
    y = y + 14
    local log = run.roundLog
    text(log.served .. " served", x, y, "body", P.good)
    text(log.dry .. " dry", x + w / 2, y, "body", log.dry > 0 and P.bad or P.textFaint)
    return y + 30
  end
  text(#plan.houses .. " houses", x, y, "mid", P.text)
  text(plan.demand .. " water wanted", x, y + 4, "body", P.textDim, w, "right")
  y = y + 30
  -- Supply against demand, as one bar: the first question every break.
  local supply = 0
  for _, b in ipairs(run.buildings) do
    local out = D.BUILDINGS[b.kind].output
    if out then
      local v = out[b.level]
      if b.kind == "well" and plan.shocks.drought then v = math.floor(v * D.SHOCKS.drought.factor) end
      supply = supply + v
    end
  end
  local short = supply < plan.demand
  text("Supply " .. supply .. " / " .. plan.demand, x, y, "small", short and P.bad or P.good)
  y = y + 18
  lg.setColor(P.surface); lg.rectangle("fill", x, y, w, 6, 3)
  if supply > 0 then
    lg.setColor(short and P.bad or P.good)
    lg.rectangle("fill", x, y, math.max(6, w * math.min(1, supply / math.max(1, plan.demand))), 6, 3)
  end
  y = y + 16
  for _, key in ipairs(D.SHOCK_ORDER) do
    if plan.shocks[key] then
      local s = D.SHOCKS[key]
      lg.setColor(P.with(P.warn, 0.14)); lg.rectangle("fill", x, y, w, 38, 5)
      lg.setColor(P.with(P.warn, 0.7)); lg.setLineWidth(1); lg.rectangle("line", x + 0.5, y + 0.5, w - 1, 37, 5)
      local blurb = s.blurb
      if key == "burst" then blurb = plan.bursts == 1 and "One main breaks when the round starts: give zones a second feed"
        or (plan.bursts .. " mains break when the round starts: give zones a second feed") end
      text(s.name, x + 8, y + 3, "small", P.warn)
      text(blurb, x + 8, y + 19, "tiny", P.textDim, w - 16)
      y = y + 44
    end
  end
  if plan.boss then
    lg.setColor(P.with(P.bad, 0.14)); lg.rectangle("fill", x, y, w, 38, 5)
    lg.setColor(P.with(P.bad, 0.7)); lg.setLineWidth(1); lg.rectangle("line", x + 0.5, y + 0.5, w - 1, 37, 5)
    text("TOWER BLOCK", x + 8, y + 3, "small", P.bad)
    text("Wants " .. math.ceil(D.HOUSES.block.demand * (plan.shocks.heatwave and D.SHOCKS.heatwave.factor or 1))
      .. " water on its own. Somewhere in the second half.", x + 8, y + 19, "tiny", P.textDim, w - 16)
    y = y + 44
  end
  -- Zone by zone: what is coming, and how much of the zone a ring reaches.
  for _, z in ipairs(run.zones) do
    local counts = plan.byZone[z.index]
    if counts then
      local parts, units = {}, 0
      for _, key in ipairs(D.HOUSE_ORDER) do
        local n = counts[key]
        if n then
          parts[#parts + 1] = plural(n, D.HOUSES[key].name)
          units = units + n * math.ceil(D.HOUSES[key].demand * (plan.shocks.heatwave and D.SHOCKS.heatwave.factor or 1))
        end
      end
      local cov = run:coverage(z)
      local isNew = z.opens == run.round
      local color = isNew and COL.zoneNew or COL.zone
      lg.setColor(P.with(color, 0.2)); lg.rectangle("fill", x, y + 1, 22, 22, 4)
      text(z.letter, x, y + 3, "body", color, 22, "center")
      text(z.name .. (isNew and "  NEW" or ""), x + 30, y, "small", isNew and COL.zoneNew or P.text)
      local covColor = cov >= 0.995 and P.good or cov >= 0.8 and P.warn or P.bad
      text(math.floor(cov * 100 + 0.5) .. "% covered", x, y, "small", covColor, w, "right")
      local line = table.concat(parts, ", ")
      text(units .. " water", x, y + 16, "tiny", P.textDim, w, "right")
      local _, wrapped = R.fonts.tiny:getWrap(line, w - 100)
      text(line, x + 30, y + 16, "tiny", P.textDim, w - 100)
      y = y + 24 + #wrapped * R.fonts.tiny:getHeight()
    end
  end
  return y
end

local function drawBuild(x, y, w)
  text("BUILD", x, y, "small", P.textDim)
  y = y + 20
  local bw = (w - 16) / 3
  for i, key in ipairs(D.ORDER) do
    local spec = D.BUILDINGS[key]
    local bx = x + (i - 1) * (bw + 8)
    button("tool-" .. key, spec.name == "WATER TOWER" and "TOWER" or spec.name, bx, y, bw, 50, function()
      state.tool = state.tool ~= key and key or nil
      state.sel, state.selPipe = nil, nil
    end, { active = state.tool == key, color = COL[key], sub = money(spec.cost[1]) .. "  [" .. spec.key .. "]",
           enabled = run.phase == "build" })
  end
  y = y + 58
  text("MAINS  (drag between two buildings)", x, y, "small", P.textDim)
  y = y + 20
  local pw = (w - 18) / 4
  for i, spec in ipairs(D.PIPES) do
    local bx = x + (i - 1) * (pw + 6)
    button("size-" .. i, spec.name, bx, y, pw, 46, function() state.size = i end,
      { active = state.size == i, color = P.linkLive, sub = spec.cap .. " / " .. spec.reach .. "m", font = "small" })
  end
  y = y + 52
  text("Carries " .. D.PIPES[state.size].cap .. " water, reaches " .. D.PIPES[state.size].reach
    .. " m, " .. money(D.PIPES[state.size].base) .. " + " .. money(D.PIPES[state.size].perM * 100) .. " per 100 m. Keys 4 to 7.",
    x, y, "tiny", P.textFaint, w)
  return y + 32
end

local function drawSidebar()
  local w, h = R.dimensions()
  lg.setColor(P.panel)
  lg.rectangle("fill", 0, 0, SIDE, h)
  lg.setColor(P.panelEdge)
  lg.line(SIDE, 0, SIDE, h)
  local x, cw = 18, SIDE - 36
  local y = 14
  text("ROUNDS" .. (run.strict and "  /  STRICT" or ""), x, y, "small", run.strict and P.bad or P.textFaint)
  text("Best " .. ((run.strict and records.bestStrict or records.best) or 0), x, y, "small", P.textFaint, cw, "right")
  y = y + 20
  local final = D.FINAL_ROUND
  text("Round " .. run.round, x, y, "big", P.text)
  text(run.round <= final and ("of " .. final) or "freeplay", x, y + 12, "body", P.textDim, cw, "right")
  y = y + 46
  -- Lives, cash, streak.
  local third = cw / 3
  text("LIVES", x, y, "tiny", P.textFaint)
  text("CASH", x + third, y, "tiny", P.textFaint)
  text("CLEAN ROUNDS", x + third * 2, y, "tiny", P.textFaint)
  y = y + 14
  local lifeColor = run.lives <= run.maxLives * 0.25 and P.bad or run.lives <= run.maxLives * 0.6 and P.warn or P.good
  text(run.lives, x, y, "mid", lifeColor)
  text(money(run.money), x + third, y, "mid", P.energy)
  text(run.streak, x + third * 2, y, "mid", run.streak > 0 and P.good or P.textDim)
  y = y + 26
  lg.setColor(P.surface); lg.rectangle("fill", x, y, cw, 5, 2)
  lg.setColor(lifeColor); lg.rectangle("fill", x, y, cw * run.lives / run.maxLives, 5, 2)
  y = y + 18
  lg.setColor(P.panelEdge); lg.line(x, y, x + cw, y)
  y = y + 12
  y = drawPreview(x, y, cw)
  y = y + 4
  lg.setColor(P.panelEdge); lg.line(x, y, x + cw, y)
  y = y + 12
  y = drawBuild(x, y, cw)

  -- The one big control, and the house-keeping row under it.
  local by = h - 108
  local label, fn, enabled = "START ROUND " .. run.round, startRound, run.phase == "build" and not state.modal
  if run.phase == "round" then
    label = state.speed > 1 and "FAST  x3" or "PLAYING  (Space: fast)"
    fn = function() state.speed = state.speed > 1 and 1 or 3 end
    enabled = true
  elseif run.phase == "lost" then
    label, fn = "NEW RUN", function() state.modal = "lost" end
  end
  button("start", label, x, by, cw, 52, fn,
    { enabled = enabled, emphasis = run.phase == "build", color = P.good, font = "mid",
      tip = "Space. During a round, Space toggles fast." })
  local sw = (cw - 18) / 4
  local ry = h - 46
  button("company", "Company", x, ry, sw, 32, leave, { font = "small", tip = "Back to your companies. The run is saved." })
  button("newrun", "New run", x + sw + 6, ry, sw, 32, function() state.modal = "newrun" end,
    { font = "small", enabled = run.phase ~= "round" })
  button("help", "Help", x + (sw + 6) * 2, ry, sw, 32, function() state.modal = "help" end, { font = "small" })
  button("mute", A.muted and "Muted" or "Sound", x + (sw + 6) * 3, ry, sw, 32, function()
    A.muted = not A.muted
  end, { font = "small" })
end

--------------------------------------------------------------------------------
-- Inspector, status line and modals
--------------------------------------------------------------------------------

local function statLine(label, now, nextValue, x, y, w)
  text(label, x, y, "small", P.textDim)
  local s = tostring(now)
  if nextValue and nextValue ~= now then s = s .. "  >  " .. nextValue end
  text(s, x, y, "small", nextValue and nextValue ~= now and P.good or P.text, w, "right")
end

local function drawInspector()
  local b = state.sel and run:byId(state.sel)
  local p = state.selPipe and run:pipeById(state.selPipe)
  if not (b or p) or state.modal then return end
  local W = R.dimensions()
  local w, x, y = 290, W - 290 - 16, 16
  if b then
    local spec = D.BUILDINGS[b.kind]
    local nextLevel = b.level < run:maxLevel(b) and b.level + 1 or nil
    local rows = {}
    if spec.output then rows[#rows + 1] = { "Water a round", run:stat(b, "output"), nextLevel and spec.output[nextLevel] } end
    if spec.throughput then rows[#rows + 1] = { "Passes through", run:stat(b, "throughput"), nextLevel and spec.throughput[nextLevel] } end
    rows[#rows + 1] = { "Mains", run:portsUsed(b) .. " of " .. run:stat(b, "ports"),
      nextLevel and (run:portsUsed(b) .. " of " .. spec.ports[nextLevel]) }
    rows[#rows + 1] = { "Ring", run:radius(b) .. " m", nextLevel and (spec.radius[nextLevel] .. " m") }
    local h = 96 + #rows * 20 + 50
    panel(x, y, w, h, P.with(COL[b.kind], 0.6))
    text(spec.name, x + 14, y + 12, "mid", COL[b.kind])
    text("Level " .. b.level .. " of " .. run:maxLevel(b), x + 14, y + 12, "small", P.textDim, w - 28, "right")
    text(spec.blurb, x + 14, y + 38, "tiny", P.textDim, w - 28)
    local ry = y + 70
    for _, r in ipairs(rows) do statLine(r[1], r[2], r[3], x + 14, ry, w - 28); ry = ry + 20 end
    if b.kind == "well" then
      text("Spring depth " .. run.springs[b.spring].depth .. ": the most levels it can take", x + 14, ry, "tiny", P.textFaint, w - 28)
    end
    ry = y + h - 50
    local cost = run:upgradeCost(b)
    local err = run:upgradeError(b)
    button("upgrade", cost and ("Upgrade  " .. money(cost)) or "Top level", x + 14, ry, (w - 36) * 0.58, 36,
      upgradeSelected, { enabled = not err, color = P.good, tip = err or "U" })
    button("sell", "Sell  " .. money(run:sellValue(b)), x + 14 + (w - 36) * 0.58 + 8, ry, (w - 36) * 0.42, 36,
      sellSelected, { enabled = run.phase == "build", color = P.bad, tip = "Delete. Its mains are sold with it." })
  else
    local spec = D.PIPES[p.size]
    local nextSpec = D.PIPES[p.size + 1]
    local a, bb = run:byId(p.a), run:byId(p.b)
    local h = 176
    panel(x, y, w, h, P.with(P.linkLive, 0.6))
    text(spec.name .. " MAIN", x + 14, y + 12, "mid", P.linkLive)
    text(math.floor(dist(a.x, a.y, bb.x, bb.y)) .. " m", x + 14, y + 16, "small", P.textDim, w - 28, "right")
    statLine("Carries", spec.cap, nextSpec and nextSpec.cap, x + 14, y + 46, w - 28)
    statLine("Reach", spec.reach .. " m", nextSpec and (nextSpec.reach .. " m"), x + 14, y + 66, w - 28)
    local flow = run.lastSolve and run.lastSolve.pipeFlow[p.id]
    statLine("Carrying now", flow and math.floor(math.abs(flow) + 0.5) or "-", nil, x + 14, y + 86, w - 28)
    if (p.crossings or 0) > 0 then
      text("Crosses the river " .. p.crossings .. (p.crossings == 1 and " time" or " times"), x + 14, y + 106, "tiny", P.textFaint, w - 28)
    end
    local cost = run:widenCost(p)
    local err = run:widenError(p)
    button("widen", cost and ("Widen  " .. money(cost)) or "Widest", x + 14, y + h - 50, (w - 36) * 0.58, 36,
      upgradeSelected, { enabled = not err, color = P.good, tip = err or "U" })
    button("sellpipe", "Sell  " .. money(run:refund(p)), x + 14 + (w - 36) * 0.58 + 8, y + h - 50, (w - 36) * 0.42, 36,
      sellSelected, { enabled = run.phase == "build", color = P.bad })
  end
end

local function drawStatus()
  local W, H = R.dimensions()
  local mx, my = love.mouse.getPosition()
  local msg, color = nil, P.textDim
  if state.toast then msg, color = state.toast, state.toastBad and P.bad or P.text end
  for _, b in ipairs(buttons) do
    if b.tip and mx >= b.x and mx < b.x + b.w and my >= b.y and my < b.y + b.h then msg, color = b.tip, P.textDim end
  end
  if not msg and mx > SIDE then
    local h = houseAt(mx, my)
    if h then
      msg = D.HOUSES[h.kind].name .. " in " .. run.zones[h.zone].name .. ", wants " .. h.demand
        .. (h.served and ": served" or (": dry, " .. (h.reason or "")))
      color = h.served and P.text or P.bad
    end
  end
  if not msg then
    if state.tool then msg = "Click the map to place. Right-click or Esc puts it down."
    elseif run.phase == "build" then msg = "Drag from a building to another to lay a main. Space starts the round. F shows the whole map." end
  end
  if not msg then return end
  local lw = math.min(W - SIDE - 40, width(msg, "small") + 24)
  local x = SIDE + (W - SIDE - lw) / 2
  lg.setColor(P.with(P.panel, 0.9)); lg.rectangle("fill", x, H - 40, lw, 26, 6)
  text(msg, x, H - 35, "small", color, lw, "center")
end

local function modalBox(w, h)
  local W, H = R.dimensions()
  lg.setColor(0, 0, 0, 0.45)
  lg.rectangle("fill", SIDE, 0, W - SIDE, H)
  local x, y = SIDE + (W - SIDE - w) / 2, (H - h) / 2
  panel(x, y, w, h, P.with(P.accent, 0.6))
  return x, y
end

local function drawModal()
  if not state.modal then return end
  if state.modal == "result" or state.modal == "won" then
    local res = state.result
    local w, h = 440, 204 + #res.items * 24 + (state.modal == "won" and 50 or 0)
    local x, y = modalBox(w, h)
    local clean = res.log.dry == 0
    text(state.modal == "won" and "Forty rounds. The city drinks." or ("Round " .. res.round .. (clean and " held" or " done")),
      x + 24, y + 20, "big", clean and P.good or P.warn)
    local sub = clean and ("Every one of " .. res.log.served .. " houses got its water.")
      or (res.log.dry .. (res.log.dry == 1 and " house" or " houses") .. " went dry: " .. res.log.lost .. " lives lost.")
    text(sub, x + 24, y + 60, "body", P.textDim, w - 48)
    local ry = y + 92
    for _, it in ipairs(res.items) do
      text(it.label, x + 24, ry, "body", P.text)
      text("+" .. money(it.amount), x + 24, ry, "body", P.energy, w - 48, "right")
      ry = ry + 24
    end
    lg.setColor(P.panelEdge); lg.line(x + 24, ry + 2, x + w - 24, ry + 2)
    text("Paid", x + 24, ry + 8, "body", P.textDim)
    text(money(res.total), x + 24, ry + 8, "mid", P.energy, w - 48, "right")
    if state.modal == "won" then
      text("You can keep going: the rounds do not stop, and nor does the city.", x + 24, ry + 40, "small", P.textDim, w - 48)
    end
    button("continue", state.modal == "won" and "Keep going" or "Build  (Space)", x + 24, y + h - 50, w - 48, 36, continue,
      { color = P.good, emphasis = true })
  elseif state.modal == "lost" then
    local w, h = 460, 290
    local x, y = modalBox(w, h)
    text("The taps ran dry", x + 24, y + 20, "big", P.bad)
    local served = 0
    for _, r in ipairs(run.history) do served = served + (r.houses or 0) - (r.dry or 0) end
    text("Round " .. run.round .. (run.strict and " on a strict run" or "") .. ". " .. served
      .. " houses kept in water along the way.", x + 24, y + 64, "body", P.textDim, w - 48)
    text("Best round  " .. (records.best or 0) .. "      Best strict  " .. (records.bestStrict or 0)
      .. "      Wins  " .. (records.wins or 0), x + 24, y + 116, "small", P.textFaint, w - 48)
    button("again", "New run", x + 24, y + h - 100, (w - 56) / 2, 38, function() fresh(false) end, { color = P.good, emphasis = true })
    button("again-strict", "New strict run", x + 32 + (w - 56) / 2, y + h - 100, (w - 56) / 2, 38, function() fresh(true) end, { color = P.bad })
    button("lost-company", "Back to company", x + 24, y + h - 52, w - 48, 36, leave)
  elseif state.modal == "newrun" then
    local w, h = 460, 250
    local x, y = modalBox(w, h)
    text("Start a new run?", x + 24, y + 20, "big", P.text)
    text("This run ends here and a new map is drawn. Standard gives " .. D.START.lives
      .. " lives, and a dry house costs as many lives as it wanted water. Strict ends on the first dry house.",
      x + 24, y + 64, "body", P.textDim, w - 48)
    button("new-std", "Standard", x + 24, y + h - 100, (w - 56) / 2, 38, function() fresh(false) end, { color = P.good, emphasis = true })
    button("new-strict", "Strict", x + 32 + (w - 56) / 2, y + h - 100, (w - 56) / 2, 38, function() fresh(true) end, { color = P.bad })
    button("new-cancel", "Keep playing", x + 24, y + h - 52, w - 48, 36, function() state.modal = nil end)
  elseif state.modal == "help" then
    local w, h = 540, 440
    local x, y = modalBox(w, h)
    text("Rounds", x + 24, y + 20, "big", P.text)
    local lines = {
      "Every round, houses appear one by one inside the open zones. Each wants water, and gets all of it or none.",
      "A house is served only inside the ring of a junction, well or tower. The preview shows how much of each zone your rings cover.",
      "Wells sit on springs. Mains carry water between buildings: drag from one to another. Their size caps what they carry and how far they reach.",
      "A dry house costs lives equal to the water it wanted. Run out of lives and the run ends.",
      "Between rounds you are paid for the round, for every unit delivered, for spare supply, and for clean rounds in a row. Anything bought this break sells back in full.",
      "Shocks are announced a round ahead. Every tenth round brings tower blocks.",
    }
    local ly = y + 64
    for _, l in ipairs(lines) do
      local _, wrapped = R.fonts.body:getWrap(l, w - 72)
      lg.setColor(P.accent); lg.circle("fill", x + 30, ly + 9, 3)
      text(l, x + 44, ly, "body", P.textDim, w - 72)
      ly = ly + #wrapped * R.fonts.body:getHeight() + 8
    end
    button("help-ok", "Got it", x + 24, y + h - 52, w - 48, 36, function() state.modal = nil end, { color = P.good, emphasis = true })
  end
end

--------------------------------------------------------------------------------
-- LOVE callbacks
--------------------------------------------------------------------------------

function App.load(args)
  for _, a in ipairs(args or {}) do
    if a == "--smoke" or a == "--shot" then testMode = a end
  end
  R.init(); A.init()
  if love.window and love.window.setIcon and love.image and love.filesystem.getInfo("assets/net-profit.png") then
    love.window.setIcon(love.image.newImageData("assets/net-profit.png"))
  end
  love.window.setTitle("Net Profit: Rounds")
  if testMode then A.setEnabled(false) end
  if not testMode then
    records = readTable(RECORD_FILE) or records
    love.filesystem.write("mode.txt", "rounds")
    local data = readTable(RUN_FILE)
    run = data and Rounds.unpack(data)
  end
  if run then
    cam = Camera.new(run.w, run.h)
    cam:follow({ x = 0, y = 0, w = run.w, h = run.h })
    fit()
    if run.phase == "lost" then state.modal = "lost" end
  else
    fresh(false, testMode and 3 or nil)
    if testMode then state.modal = nil end
  end
  App.state = state
  App.run = function() return run end
  App.camera = function() return cam end
  App.setRun = function(r) run = r; cam = Camera.new(run.w, run.h); cam:follow({ x = 0, y = 0, w = run.w, h = run.h }); fit() end
  App.startRound, App.finish, App.arriveOne, App.fresh = startRound, finish, arriveOne, fresh
  if testMode then require("rounds_walkthrough").start(App, testMode) end
end

function App.update(dt)
  R.update(dt)
  cam:update(dt)
  if state.toastTime > 0 then
    state.toastTime = state.toastTime - dt
    if state.toastTime <= 0 then state.toast = nil end
  end
  for id, t in pairs(state.flash) do
    state.flash[id] = t - dt
    if state.flash[id] <= 0 then state.flash[id] = nil end
  end
  for h, t in pairs(state.pops) do state.pops[h] = t + dt end
  if run.phase == "round" and state.play then
    local play = state.play
    if run:pendingHouses() > 0 then
      play.t = play.t + dt * state.speed
      while play.t >= play.interval and run:pendingHouses() > 0 and run.phase == "round" do
        play.t = play.t - play.interval
        arriveOne()
      end
    else
      play.wait = play.wait + dt * state.speed
      if play.wait > 0.9 then finish() end
    end
  end
  if testMode then require("rounds_walkthrough").update(App, dt) end
end

function App.draw()
  buttons = {}
  lg.clear(P.bg)
  drawMap()
  drawInspector()
  drawStatus()
  drawSidebar()
  drawModal()
end

local function clickButton(x, y)
  for i = #buttons, 1, -1 do
    local b = buttons[i]
    if x >= b.x and x < b.x + b.w and y >= b.y and y < b.y + b.h then
      if b.enabled then A.play("click", 0.4); b.fn() end
      return true
    end
  end
end

function App.mousepressed(x, y, button)
  if button == 1 and clickButton(x, y) then return end
  if state.modal then return end
  if x < SIDE then return end
  if button == 2 or button == 3 then
    state.pan = { x = x, y = y, moved = false, cancel = true }
    return
  end
  if button ~= 1 then return end
  if state.tool then
    local wx, wy = toWorld(x, y)
    placeAt(wx, wy)
    return
  end
  local b = buildingAt(x, y)
  if b then
    state.press = { x = x, y = y, id = b.id }
    if run.phase == "build" then state.drag = b.id end
    return
  end
  state.pan = { x = x, y = y, moved = false, click = true }
end

function App.mousemoved(x, y, dx, dy)
  if state.pan then
    if math.abs(x - state.pan.x) + math.abs(y - state.pan.y) > 4 then state.pan.moved = true end
    if state.pan.moved then cam:pan(dx, dy) end
  end
end

function App.mousereleased(x, y, button)
  if state.drag and button == 1 then
    local from = state.drag
    state.drag = nil
    local target = buildingAt(x, y)
    if target and target.id ~= from then
      local p, err = run:layPipe(from, target.id, state.size)
      if p then
        A.play("build", 0.6)
        toast(D.PIPES[p.size].name .. " main laid for " .. money(p.paid))
        state.sel, state.selPipe = nil, p.id
        saveRun()
      else
        toast(err, true)
      end
      state.press = nil
      return
    end
  end
  if state.press and button == 1 then
    local b = run:byId(state.press.id)
    state.press = nil
    if b then
      if state.sel == b.id then select(nil) else select(b) end
    end
    return
  end
  if state.pan and (button == 1 or button == 2 or button == 3) then
    local pan = state.pan
    state.pan = nil
    if not pan.moved then
      if pan.cancel then
        state.tool, state.sel, state.selPipe = nil, nil, nil
      elseif pan.click then
        local p = pipeAt(x, y)
        if p then
          state.sel, state.selPipe = nil, (state.selPipe ~= p.id) and p.id or nil
        else
          state.sel, state.selPipe = nil, nil
        end
      end
    end
  end
end

function App.wheelmoved(_, dy)
  local mx, my = love.mouse.getPosition()
  if mx < SIDE then return end
  cam:zoomAt(mx, my, dy)
end

function App.keypressed(key)
  if key == "escape" then
    if state.modal == "help" or state.modal == "newrun" then state.modal = nil
    elseif state.modal == "result" or state.modal == "won" then continue()
    else state.tool, state.sel, state.selPipe, state.drag = nil, nil, nil, nil end
    return
  end
  if key == "space" or key == "return" then
    if state.modal == "result" or state.modal == "won" or state.modal == "help" then continue()
    elseif run.phase == "round" then state.speed = state.speed > 1 and 1 or 3
    elseif run.phase == "build" and not state.modal then startRound() end
    return
  end
  if state.modal then return end
  if key == "f" then fit(); return end
  if key == "m" then A.muted = not A.muted; return end
  if key == "u" then upgradeSelected(); return end
  if key == "delete" or key == "backspace" then sellSelected(); return end
  for _, k in ipairs(D.ORDER) do
    if key == D.BUILDINGS[k].key and run.phase == "build" then
      state.tool = state.tool ~= k and k or nil
      state.sel, state.selPipe = nil, nil
      return
    end
  end
  local size = tonumber(key)
  if size and size >= 4 and size <= 7 then state.size = size - 3 end
end

function App.resize() R.retune(); layout() end

function App.quit() saveRun() end

return App
