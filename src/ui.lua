-- ui.lua -- sidebar, inspector and overlays.
-- Immediate mode: buttons are registered while drawing and hit-tested on click.
local P     = require("palette")
local R     = require("render")
local Graph = require("graph")
local Game  = require("game")
local Meta  = require("meta")
local A     = require("audio")

local U = {}
local lg = love.graphics

U.SIDEBAR = 306
U.BOTTOM  = 66
U.hits = {}

function U.begin() U.hits = {} end

function U.click(mx, my)
  for i = #U.hits, 1, -1 do
    local h = U.hits[i]
    if mx >= h.x and mx <= h.x + h.w and my >= h.y and my <= h.y + h.h then
      if h.enabled then
        A.play("click", 0.8)
        h.action()
      else
        A.play("denied", 0.6)
      end
      return true
    end
  end
  return false
end

function U.hovering(mx, my)
  for _, h in ipairs(U.hits) do
    if mx >= h.x and mx <= h.x + h.w and my >= h.y and my <= h.y + h.h then return true end
  end
  return false
end

--------------------------------------------------------------------------------
-- Primitives
--------------------------------------------------------------------------------

local function panel(x, y, w, h, alpha)
  lg.setColor(P.panel[1], P.panel[2], P.panel[3], alpha or 0.96)
  lg.rectangle("fill", x, y, w, h, 6)
  lg.setColor(P.with(P.panelEdge, 0.9))
  lg.setLineWidth(1)
  lg.rectangle("line", x, y, w, h, 6)
end

local function label(text, x, y, color, font)
  lg.setFont(font or R.fonts.small)
  lg.setColor(color or P.textDim)
  lg.print(text, x, y)
end

local function heading(text, x, y)
  lg.setFont(R.fonts.tiny)
  lg.setColor(P.textFaint)
  lg.print(string.upper(text), x, y)
end

-- Right-aligned value with an optional unit, the workhorse of the stat rows.
local function statRow(x, y, w, name, value, color)
  lg.setFont(R.fonts.small)
  lg.setColor(P.textDim)
  lg.print(name, x, y)
  lg.setFont(R.fonts.body)
  lg.setColor(color or P.text)
  local vw = R.fonts.body:getWidth(value)
  lg.print(value, x + w - vw, y - 2)
end

local function bar(x, y, w, h, frac, color, bg)
  lg.setColor(bg or P.with(P.panelEdge, 0.8))
  lg.rectangle("fill", x, y, w, h, h / 2)
  local f = math.max(0, math.min(1, frac))
  if f > 0 then
    lg.setColor(color)
    lg.rectangle("fill", x, y, w * f, h, h / 2)
  end
end

function U.button(x, y, w, h, text, enabled, action, opts)
  opts = opts or {}
  local mx, my = love.mouse.getPosition()
  local hot = mx >= x and mx <= x + w and my >= y and my <= y + h
  local base = opts.color or P.accent

  if not enabled then
    lg.setColor(P.with(P.panelEdge, 0.55))
  elseif hot then
    lg.setColor(base[1], base[2], base[3], 0.92)
  else
    lg.setColor(base[1] * 0.42, base[2] * 0.42, base[3] * 0.42, 0.92)
  end
  lg.rectangle("fill", x, y, w, h, 5)
  lg.setColor(enabled and P.with(base, hot and 1 or 0.75) or P.with(P.textFaint, 0.5))
  lg.setLineWidth(1)
  lg.rectangle("line", x, y, w, h, 5)

  lg.setFont(opts.font or R.fonts.body)
  local tw = (opts.font or R.fonts.body):getWidth(text)
  local th = (opts.font or R.fonts.body):getHeight()
  if not enabled then lg.setColor(P.with(P.textFaint, 0.75))
  elseif hot then lg.setColor(P.bg)
  else lg.setColor(P.text) end
  lg.print(text, x + (w - tw) / 2, y + (h - th) / 2)

  U.hits[#U.hits + 1] = { x = x, y = y, w = w, h = h, enabled = enabled, action = action }
  return hot
end

--------------------------------------------------------------------------------
-- Sidebar
--------------------------------------------------------------------------------

function U.drawSidebar(run, state)
  local W, H = lg.getDimensions()
  local x, w = 12, U.SIDEBAR - 24
  lg.setColor(P.panel[1], P.panel[2], P.panel[3], 0.98)
  lg.rectangle("fill", 0, 0, U.SIDEBAR, H)
  lg.setColor(P.with(P.panelEdge, 0.9))
  lg.line(U.SIDEBAR, 0, U.SIDEBAR, H)

  local y = 16
  lg.setFont(R.fonts.mid)
  lg.setColor(P.accent)
  lg.print("AUGMENT", x, y)
  lg.setFont(R.fonts.small)
  lg.setColor(P.textFaint)
  lg.print(string.format("wave %d", run.wave), x + w - 52, y + 5)
  y = y + 34

  -- Delivery is the survival condition, so it leads.
  local met = run.flow >= run.demand
  panel(x, y, w, 96)
  heading("delivery", x + 12, y + 9)
  lg.setFont(R.fonts.big)
  lg.setColor(met and P.good or P.bad)
  lg.print(string.format("%d", run.flow), x + 12, y + 22)
  lg.setFont(R.fonts.body)
  lg.setColor(P.textDim)
  lg.print(string.format("/ %d required", run.demand), x + 12 + R.fonts.big:getWidth(tostring(run.flow)) + 8, y + 38)
  bar(x + 12, y + 64, w - 24, 7, run.demand > 0 and run.flow / run.demand or 1,
      met and P.good or P.bad)
  lg.setFont(R.fonts.tiny)
  lg.setColor(P.textFaint)
  lg.print(string.format("network capacity %d", run.capacity or 0), x + 12, y + 76)
  y = y + 106

  -- Energy.
  panel(x, y, w, 56)
  heading("energy", x + 12, y + 9)
  lg.setFont(R.fonts.big)
  lg.setColor(P.energy)
  lg.print(string.format("%d", run.energy), x + 12, y + 20)
  lg.setFont(R.fonts.tiny)
  lg.setColor(P.textFaint)
  local inc = Game.balance.baseIncome + Game.balance.incomePerFlow * run.flow
    + (run:has("ford_fulkerson") and 15 or 0)
  lg.printf(string.format("+%d if this wave holds", inc), x + 12, y + 34, w - 24, "right")
  y = y + 66

  -- The threat. Naming what is about to happen is the whole teaching moment.
  local strikes = Game.strikesFor(run.wave)
  local cw = #(run.cut or {})
  panel(x, y, w, 74)
  heading("adversary", x + 12, y + 9)
  lg.setFont(R.fonts.small)
  if strikes == 0 then
    lg.setColor(P.textDim)
    lg.printf("Dormant. It wakes on wave " .. Game.balance.firstStrikeWave .. ".", x + 12, y + 26, w - 24, "left")
  elseif cw == 0 then
    lg.setColor(P.bad)
    lg.printf("No route reaches a terminal. There is no cut left to sever.",
      x + 12, y + 24, w - 24, "left")
    lg.setFont(R.fonts.tiny)
    lg.setColor(P.bad)
    lg.printf("Reconnect the network before resolving.", x + 12, y + 54, w - 24, "left")
  else
    lg.setColor(cw > strikes and P.warn or P.bad)
    lg.printf(string.format("Severs %d of the %d link%s in your minimum cut.",
      strikes, cw, cw == 1 and "" or "s"), x + 12, y + 24, w - 24, "left")
    lg.setFont(R.fonts.tiny)
    lg.setColor(cw > strikes and P.textFaint or P.bad)
    lg.printf(cw > strikes and "The cut is wider than the strike. You survive it."
                            or "The cut is too narrow. This will break you.",
      x + 12, y + 54, w - 24, "left")
  end
  y = y + 84

  -- Build palette.
  heading("build", x, y); y = y + 14
  local kinds = { { "relay", "1" }, { "hub", "2" }, { "conduit", "3" } }
  for _, k in ipairs(kinds) do
    local kind, key = k[1], k[2]
    local spec = Graph.KINDS[kind]
    local cost = run:nodeCost(kind)
    local afford = run.energy >= cost and run.phase == "build"
    local active = state.tool == kind
    local bh = 40
    local mx, my = love.mouse.getPosition()
    local hot = mx >= x and mx <= x + w and my >= y and my <= y + bh

    lg.setColor(active and P.with(spec.color, 0.24) or (hot and P.with(P.panelEdge, 0.75) or P.with(P.panel, 1)))
    lg.rectangle("fill", x, y, w, bh, 5)
    lg.setColor(active and P.with(spec.color, 0.95) or P.with(P.panelEdge, 0.9))
    lg.setLineWidth(active and 1.8 or 1)
    lg.rectangle("line", x, y, w, bh, 5)

    lg.setColor(P.with(spec.color, afford and 1 or 0.4))
    lg.circle("fill", x + 22, y + bh / 2, 8)
    lg.setFont(R.fonts.body)
    lg.setColor(afford and P.text or P.textFaint)
    lg.print(spec.name, x + 40, y + 6)
    lg.setFont(R.fonts.tiny)
    lg.setColor(P.textFaint)
    lg.print(string.format("%d ports  %s throughput", spec.ports,
      spec.throughput >= Graph.INF and "inf" or tostring(spec.throughput)), x + 40, y + 23)
    lg.setFont(R.fonts.body)
    lg.setColor(afford and P.energy or P.bad)
    local ct = tostring(cost)
    lg.print(ct, x + w - 14 - R.fonts.body:getWidth(ct), y + 6)
    lg.setFont(R.fonts.tiny)
    lg.setColor(P.textFaint)
    lg.print(key, x + w - 14 - R.fonts.tiny:getWidth(key), y + 24)

    U.hits[#U.hits + 1] = { x = x, y = y, w = w, h = bh, enabled = run.phase == "build",
                            action = function() state.tool = (state.tool == kind) and nil or kind end }
    y = y + bh + 6
  end
  y = y + 6

  -- Structural readout: the vocabulary, live.
  local st = run.g:stats()
  panel(x, y, w, 116)
  heading("graph", x + 12, y + 9)
  local iy = y + 26
  statRow(x + 12, iy, w - 24, "order  |V|", tostring(st.order)); iy = iy + 19
  statRow(x + 12, iy, w - 24, "size  |E|", tostring(st.size)); iy = iy + 19
  statRow(x + 12, iy, w - 24, "min / max degree",
          string.format("%d / %d", st.minDegree, st.maxDegree)); iy = iy + 19
  statRow(x + 12, iy, w - 24, "components", tostring(st.components),
          st.components > 1 and P.warn or P.text); iy = iy + 19
  statRow(x + 12, iy, w - 24, "cut vertices", tostring(#st.cutVertices),
          #st.cutVertices > 0 and P.warn or P.good)
  y = y + 126

  -- Log.
  heading("log", x, y); y = y + 14
  lg.setFont(R.fonts.tiny)
  for i = 1, math.min(#run.log, math.floor((H - y - 16) / 15)) do
    lg.setColor(P.textFaint[1], P.textFaint[2], P.textFaint[3], 1 - (i - 1) * 0.12)
    lg.printf(run.log[i], x, y, w, "left")
    y = y + 15
  end
end

--------------------------------------------------------------------------------
-- Inspector and bottom bar
--------------------------------------------------------------------------------

function U.drawInspector(run, state)
  local W, H = lg.getDimensions()
  local w, h = 268, 128
  local x, y = W - w - 16, H - U.BOTTOM - h - 16
  local g = run.g

  if state.selNode then
    local n = g.nodes[state.selNode]
    if not (n and n.alive) then state.selNode = nil; return end
    local spec = Graph.KINDS[n.kind]
    panel(x, y, w, h)
    lg.setFont(R.fonts.body)
    lg.setColor(spec.color)
    lg.print(spec.name, x + 12, y + 10)
    lg.setFont(R.fonts.tiny)
    lg.setColor(P.textFaint)
    lg.print(string.format("#%d", n.id), x + w - 34, y + 13)

    local iy = y + 34
    statRow(x + 12, iy, w - 24, "degree / ports",
            string.format("%d / %d", g:degree(n.id), n.ports)); iy = iy + 20
    statRow(x + 12, iy, w - 24, "throughput",
            n.throughput >= Graph.INF and "unlimited" or tostring(n.throughput)); iy = iy + 20

    local tp = run:tpCost(n.id)
    local can = run.phase == "build" and tp and run.energy >= tp
    if tp then
      U.button(x + 12, y + h - 34, 118, 24,
        string.format("+1 tp  %d", tp), can,
        function() if run:upgradeNode(n.id) then A.play("upgrade") end end,
        { font = R.fonts.small, color = P.flow })
    end
    local canDemo = run.phase == "build" and n.kind ~= "source" and n.kind ~= "sink"
    U.button(x + w - 130, y + h - 34, 118, 24, "demolish", canDemo,
      function()
        local refund = run:demolishNode(n.id)
        if refund then
          A.play("demolish")
          R.burst(n.x, n.y, P.textFaint, 10)
          R.floatText(n.x, n.y, "+" .. refund, P.energy)
        end
        state.selNode = nil
      end, { font = R.fonts.small, color = P.bad })

  elseif state.selEdge then
    local e = g.edges[state.selEdge]
    if not (e and e.alive) then state.selEdge = nil; return end
    panel(x, y, w, h)
    lg.setFont(R.fonts.body)
    lg.setColor(P.linkLive)
    lg.print("LINK", x + 12, y + 10)

    local f = math.abs((run.detail and run.detail.edge[e.id]) or 0)
    local iy = y + 34
    statRow(x + 12, iy, w - 24, "capacity", tostring(e.cap)); iy = iy + 20
    statRow(x + 12, iy, w - 24, "carrying", string.format("%d", math.floor(f + 0.5)),
            f >= e.cap and P.warn or P.text); iy = iy + 20

    local cc = run:capCost(e.id)
    U.button(x + 12, y + h - 34, 118, 24, string.format("+1 cap  %d", cc),
      run.phase == "build" and run.energy >= cc,
      function() if run:upgradeLink(e.id) then A.play("upgrade") end end,
      { font = R.fonts.small, color = P.flow })
    U.button(x + w - 130, y + h - 34, 118, 24, "demolish", run.phase == "build",
      function()
        local na, nb = g.nodes[e.a], g.nodes[e.b]
        local refund = run:demolishLink(e.id)
        if refund then
          A.play("demolish")
          R.burst((na.x + nb.x) / 2, (na.y + nb.y) / 2, P.textFaint, 10)
          R.floatText((na.x + nb.x) / 2, (na.y + nb.y) / 2, "+" .. refund, P.energy)
        end
        state.selEdge = nil
      end, { font = R.fonts.small, color = P.bad })
  end
end

-- A single next step, derived from the live graph rather than a scripted
-- tutorial. It names the concept that currently matters, which is how the
-- vocabulary gets taught: when it is the thing standing in your way.
function U.objective(run)
  if run.phase ~= "build" then return nil end
  local st = run.g:stats()

  local unreached = 0
  local lbl = run.g:components()
  local home = lbl[run.source.id]
  for _, t in ipairs(run.g:nodesOfKind("sink")) do
    if lbl[t.id] ~= home then unreached = unreached + 1 end
  end

  if st.size == 0 then
    return "Drag from the SOURCE to the terminal to lay your first link.", P.good
  end
  if unreached > 0 then
    return string.format("%d terminal%s cut off. Every terminal must be reached.",
      unreached, unreached == 1 and "" or "s"), P.bad
  end
  if run.flow < run.demand then
    return string.format("Short by %d. Select a link on the red cut and press U.",
      run.demand - run.flow), P.bad
  end

  local strikes = Game.strikesFor(run.wave)
  local cw = #(run.cut or {})
  if strikes > 0 and cw <= strikes then
    return string.format("Cut is %d wide, %d will be severed. Build another route.",
      cw, strikes), P.warn
  end
  if #st.cutVertices > 0 then
    return string.format("%d cut vertex: losing one splits the network.",
      #st.cutVertices), P.warn
  end
  return nil
end

function U.drawBottom(run, state)
  local W, H = lg.getDimensions()
  local x, y = U.SIDEBAR, H - U.BOTTOM
  lg.setColor(P.panel[1], P.panel[2], P.panel[3], 0.98)
  lg.rectangle("fill", x, y, W - x, U.BOTTOM)
  lg.setColor(P.with(P.panelEdge, 0.9))
  lg.line(x, y, W, y)

  local bw, bh = 186, 40
  lg.setFont(R.fonts.small)
  lg.setColor(P.textFaint)
  local obj, objColor = U.objective(run)
  local hint = state.tool
    and string.format("click the field to place a %s   -   esc to cancel", Graph.KINDS[state.tool].name)
    or (obj or "drag node to node to link   -   click to inspect   -   right-drag pans   -   wheel zooms   -   H for help")
  if obj and not state.tool then lg.setColor(objColor) end
  -- Clipped to the space the resolve button leaves, so the two never collide.
  local avail = (W - bw - 32) - (x + 18)
  while avail > 40 and R.fonts.small:getWidth(hint) > avail do
    hint = hint:sub(1, #hint - 4) .. "..."
  end
  lg.print(hint, x + 18, y + U.BOTTOM / 2 - 8)

  local met = run.flow >= run.demand
  U.button(W - bw - 16, y + (U.BOTTOM - bh) / 2, bw, bh,
    met and "RESOLVE WAVE" or "RESOLVE (will fail)",
    run.phase == "build",
    function() state.pendingResolve = true end,
    { color = met and P.good or P.bad, font = R.fonts.body })
end

--------------------------------------------------------------------------------
-- Overlays
--------------------------------------------------------------------------------

-- Centre a panel over the field area. Centring on the whole window puts these
-- on top of the sidebar once the window is narrow, which a tiling WM makes the
-- common case rather than the exception.
local function fieldCentre(w)
  local W = lg.getWidth()
  local avail = W - U.SIDEBAR
  if avail < w + 24 then return math.max(8, (W - w) / 2) end
  --------------------------------------------------------------------------------
-- Tutorial
--------------------------------------------------------------------------------

-- Drawn at the top of the field so it never covers the sidebar numbers the
-- instructions keep referring to.
function U.drawTutorial(run, state, T)
  local step = T.current()
  if not step then return end

  local W, H = lg.getDimensions()
  local avail = W - U.SIDEBAR
  local w = math.min(600, avail - 32)
  local x = U.SIDEBAR + (avail - w) / 2
  local y = 16

  local pad = 18
  local bodyFont = R.fonts.body
  local _, lines = bodyFont:getWrap(step.body, w - pad * 2)
  local bodyH = #lines * (bodyFont:getHeight() + 3)
  local h = pad + 24 + 8 + bodyH + 46

  lg.setColor(P.panel[1], P.panel[2], P.panel[3], 0.97)
  lg.rectangle("fill", x, y, w, h, 7)
  lg.setColor(P.with(P.accent, 0.85))
  lg.setLineWidth(1.5)
  lg.rectangle("line", x, y, w, h, 7)

  lg.setFont(R.fonts.tiny)
  lg.setColor(P.textFaint)
  local counter = string.format("%d / %d", T.step, #T.steps)
  lg.print(counter, x + w - pad - R.fonts.tiny:getWidth(counter), y + pad + 4)

  lg.setFont(R.fonts.mid)
  lg.setColor(P.accent)
  lg.print(step.title, x + pad, y + pad - 2)

  lg.setFont(bodyFont)
  lg.setColor(P.text)
  lg.printf(step.body, x + pad, y + pad + 30, w - pad * 2, "left")

  local by = y + h - 38
  U.button(x + pad, by, 96, 26, "SKIP", true,
    function() T.stop(); state.tutorialSkipped = true end,
    { font = R.fonts.small, color = P.panelEdge })

  if step.kind == "explain" then
    U.button(x + w - pad - 132, by, 132, 26, "NEXT   (space)", true,
      function() T.advance() end, { font = R.fonts.small, color = P.accent })
  else
    -- Action steps wait on the graph, so say what is being waited for.
    lg.setFont(R.fonts.small)
    local pulse = 0.55 + 0.45 * math.sin(R.t * 4)
    lg.setColor(P.good[1], P.good[2], P.good[3], pulse)
    local msg = "waiting for you..."
    lg.print(msg, x + w - pad - R.fonts.small:getWidth(msg), by + 6)
  end
end

return U.SIDEBAR + (avail - w) / 2
end

local function dim(a)
  local W, H = lg.getDimensions()
  lg.setColor(0, 0, 0, a or 0.72)
  lg.rectangle("fill", 0, 0, W, H)
end

function U.drawReport(run, state)
  local rep = run.lastReport
  if not rep then return end
  local W, H = lg.getDimensions()
  local w, h = 470, 320
  local x, y = fieldCentre(w), (H - h) / 2
  dim(0.62)
  panel(x, y, w, h, 1)

  lg.setFont(R.fonts.big)
  lg.setColor(P.good)
  lg.print(string.format("WAVE %d HELD", rep.wave), x + 26, y + 22)

  lg.setFont(R.fonts.small)
  local iy = y + 74
  statRow(x + 26, iy, w - 52, "delivered", string.format("%d / %d", rep.flow, rep.demand), P.good); iy = iy + 24
  statRow(x + 26, iy, w - 52, "energy gained", "+" .. rep.income, P.energy); iy = iy + 24

  iy = iy + 10
  lg.setFont(R.fonts.small)
  lg.setColor(P.textFaint)
  lg.print("ADVERSARY", x + 26, iy); iy = iy + 20
  lg.setFont(R.fonts.small)
  if rep.shielded then
    lg.setColor(P.accent)
    lg.print("Euler circuit absorbed the strike.", x + 26, iy); iy = iy + 20
  elseif #rep.strikes == 0 then
    lg.setColor(P.textDim)
    lg.print("No strike this wave.", x + 26, iy); iy = iy + 20
  else
    for _, s in ipairs(rep.strikes) do
      lg.setColor(P.bad)
      lg.print(s.kind == "edge" and "Link severed at the minimum cut."
                                or "Node destroyed at the minimum cut.", x + 26, iy)
      iy = iy + 19
    end
  end

  if rep.newTerminal then
    iy = iy + 8
    lg.setColor(P.warn)
    lg.print("A new terminal appeared. It demands its own supply.", x + 26, iy)
  end

  U.button(x + w - 176, y + h - 56, 150, 36, "CONTINUE", true,
    function() run:beginNextWave(); state.showReport = false end, { color = P.good })
end

function U.drawDeath(run, state, meta)
  local W, H = lg.getDimensions()
  local w, h = 470, 300
  local x, y = fieldCentre(w), (H - h) / 2
  dim(0.80)
  panel(x, y, w, h, 1)

  lg.setFont(R.fonts.big)
  lg.setColor(P.bad)
  lg.print("NETWORK COLLAPSED", x + 26, y + 24)

  lg.setFont(R.fonts.small)
  lg.setColor(P.textDim)
  local rep = run.lastReport or {}
  lg.printf(string.format("Wave %d demanded %d. The network delivered %d.",
    run.wave, rep.demand or run.demand, rep.flow or run.flow), x + 26, y + 66, w - 52, "left")
  if (rep.starved or 0) > 0 then
    lg.setColor(P.bad)
    lg.printf(string.format("%d terminal%s went unsupplied.",
      rep.starved, rep.starved == 1 and "" or "s"), x + 26, y + 88, w - 52, "left")
  end

  local iy = y + 124
  statRow(x + 26, iy, w - 52, "waves survived", tostring(run.wave - 1)); iy = iy + 24
  statRow(x + 26, iy, w - 52, "peak delivery", tostring(run.peakFlow)); iy = iy + 24
  statRow(x + 26, iy, w - 52, "insight earned", "+" .. run:insightEarned(), P.accent)

  U.button(x + 26, y + h - 56, 190, 36, "THEOREMS", true,
    function() state.screen = "meta" end, { color = P.accent })
  U.button(x + w - 176, y + h - 56, 150, 36, "NEW RUN", true,
    function() state.restart = true end, { color = P.good })
end

function U.drawMeta(state, meta)
  local W, H = lg.getDimensions()
  dim(0.90)
  local w = 620
  local x, y = (W - w) / 2, 60

  lg.setFont(R.fonts.big)
  lg.setColor(P.accent)
  lg.print("THEOREMS", x, y)
  lg.setFont(R.fonts.body)
  lg.setColor(P.accent)
  local it = string.format("%d insight", meta.insight or 0)
  lg.print(it, x + w - R.fonts.body:getWidth(it), y + 12)
  y = y + 48

  lg.setFont(R.fonts.small)
  lg.setColor(P.textFaint)
  lg.printf("Insight is earned by surviving. What you unlock here persists across every future run.",
    x, y, w, "left")
  y = y + 34

  for _, t in ipairs(Meta.THEOREMS) do
    local owned = meta.unlocked[t.key]
    local afford = (meta.insight or 0) >= t.cost
    local hh = 66
    panel(x, y, w, hh)
    lg.setFont(R.fonts.body)
    lg.setColor(owned and P.good or P.text)
    lg.print(t.name, x + 16, y + 10)
    lg.setFont(R.fonts.small)
    lg.setColor(owned and P.textDim or P.text)
    lg.print(t.line, x + 16, y + 29)
    lg.setFont(R.fonts.tiny)
    lg.setColor(P.textFaint)
    lg.printf(t.note, x + 16, y + 47, w - 150, "left")

    if owned then
      lg.setFont(R.fonts.small)
      lg.setColor(P.good)
      lg.print("KNOWN", x + w - 78, y + 24)
    else
      U.button(x + w - 108, y + 20, 92, 28, string.format("%d", t.cost), afford,
        function()
          if Meta.unlock(meta, t.key) then
            state.metaFlash = t.name
            A.play("unlock")
          end
        end, { font = R.fonts.small, color = P.accent })
    end
    y = y + hh + 8
  end

  U.button(x, y + 8, 180, 38, "BACK", true,
    function() state.screen = "run" end, { color = P.good })
end

function U.drawHelp(state)
  local W, H = lg.getDimensions()
  dim(0.92)
  local w = 640
  local x, y = (W - w) / 2, 56

  lg.setFont(R.fonts.big)
  lg.setColor(P.accent)
  lg.print("READING THE NETWORK", x, y)
  y = y + 52

  local lines = {
    { "THE RULE", P.text },
    { "Every terminal demands its own supply each wave. Deliver all of it or the run ends.", P.textDim },
    { "", P.text },
    { "WHAT THE FIELD SHOWS", P.text },
    { "Link thickness is capacity: how much it could carry.", P.textDim },
    { "Moving dots are flow: how much it does carry.", P.textDim },
    { "The ring around a node is its ports: one tick per link it can hold.", P.textDim },
    { "A node's inner fill is how close it is to its throughput limit.", P.textDim },
    { "", P.text },
    { "THE RED PULSE", P.cut },
    { "That is your minimum cut: the cheapest set of links that, if removed,", P.textDim },
    { "would disconnect supply from demand. Its total capacity is exactly your", P.textDim },
    { "maximum flow. That is the max-flow min-cut theorem, and it is the whole game.", P.textDim },
    { "", P.text },
    { "THE ADVERSARY", P.bad },
    { "Each wave it severs links from that cut. A single thick trunk is one cut of", P.textDim },
    { "width one: lose it and you lose everything. Several thin disjoint routes", P.textDim },
    { "form a wide cut: lose one of five and you keep four fifths.", P.textDim },
    { "Redundancy is not caution here. It is the only thing that survives.", P.text },
    { "", P.text },
    { "CONTROLS", P.text },
    { "1 2 3 pick a node type, click the field to place it.", P.textDim },
    { "Drag from node to node to lay a link. Click anything to inspect it.", P.textDim },
    { "Right-drag pans, the wheel zooms, space resolves the wave.", P.textDim },
  }
  lg.setFont(R.fonts.small)
  for _, l in ipairs(lines) do
    lg.setColor(l[2])
    lg.print(l[1], x, y)
    y = y + (l[1] == "" and 8 or 18)
  end

  U.button(x, y + 14, 180, 38, "BACK", true,
    function() state.screen = "run" end, { color = P.good })
end

function U.drawTitle(state, meta)
  local W, H = lg.getDimensions()
  -- The field is already drawn behind: veil it rather than hide it, so the
  -- title sits on a living network.
  lg.setColor(P.bg[1], P.bg[2], P.bg[3], 0.86)
  lg.rectangle("fill", 0, 0, W, H)

  local cx, cy = W / 2, H / 2 - 80
  lg.setFont(R.fonts.huge)
  lg.setColor(P.accent)
  local t = "AUGMENT"
  lg.print(t, cx - R.fonts.huge:getWidth(t) / 2, cy - 90)

  lg.setFont(R.fonts.body)
  lg.setColor(P.textDim)
  local s = "grow a network that survives its own minimum cut"
  lg.print(s, cx - R.fonts.body:getWidth(s) / 2, cy - 28)

  if (meta.runs or 0) > 0 then
    lg.setFont(R.fonts.small)
    lg.setColor(P.textFaint)
    local r = string.format("%d runs   best wave %d   peak delivery %d   %d insight",
      meta.runs, meta.bestWave, meta.bestFlow, meta.insight or 0)
    lg.print(r, cx - R.fonts.small:getWidth(r) / 2, cy + 4)
  end

  -- A first-time player is pointed at the tutorial, not at a blank field.
  local fresh = not meta.tutorialDone
  if fresh then
    U.button(cx - 110, cy + 50, 220, 46, "TUTORIAL", true,
      function() state.startTutorial = true end, { color = P.accent, font = R.fonts.mid })
    U.button(cx - 110, cy + 106, 220, 34, "SKIP TO FREE PLAY", true,
      function() state.restart = true end, { color = P.good, font = R.fonts.small })
    lg.setFont(R.fonts.tiny)
    lg.setColor(P.textFaint)
    local n = "first time? the tutorial takes about two minutes"
    lg.print(n, cx - R.fonts.tiny:getWidth(n) / 2, cy + 148)
    U.button(cx - 110, cy + 170, 105, 30, "THEOREMS", true,
      function() state.screen = "meta" end, { color = P.accent, font = R.fonts.small })
    U.button(cx + 5, cy + 170, 105, 30, "HOW", true,
      function() state.screen = "help" end, { color = P.flow, font = R.fonts.small })
  else
    U.button(cx - 110, cy + 50, 220, 46, "BEGIN RUN", true,
      function() state.restart = true end, { color = P.good, font = R.fonts.mid })
    U.button(cx - 110, cy + 106, 68, 34, "TUTORIAL", true,
      function() state.startTutorial = true end, { color = P.accent, font = R.fonts.small })
    U.button(cx - 37, cy + 106, 74, 34, "THEOREMS", true,
      function() state.screen = "meta" end, { color = P.accent, font = R.fonts.small })
    U.button(cx + 42, cy + 106, 68, 34, "HOW", true,
      function() state.screen = "help" end, { color = P.flow, font = R.fonts.small })
  end
end

--------------------------------------------------------------------------------
-- Tutorial
--------------------------------------------------------------------------------

-- Drawn at the top of the field so it never covers the sidebar numbers the
-- instructions keep referring to.
function U.drawTutorial(run, state, T)
  local step = T.current()
  if not step then return end

  local W, H = lg.getDimensions()
  local avail = W - U.SIDEBAR
  local w = math.min(600, avail - 32)
  local x = U.SIDEBAR + (avail - w) / 2
  local y = 16

  local pad = 18
  local bodyFont = R.fonts.body
  local _, lines = bodyFont:getWrap(step.body, w - pad * 2)
  local bodyH = #lines * (bodyFont:getHeight() + 3)
  local h = pad + 24 + 8 + bodyH + 46

  lg.setColor(P.panel[1], P.panel[2], P.panel[3], 0.97)
  lg.rectangle("fill", x, y, w, h, 7)
  lg.setColor(P.with(P.accent, 0.85))
  lg.setLineWidth(1.5)
  lg.rectangle("line", x, y, w, h, 7)

  lg.setFont(R.fonts.tiny)
  lg.setColor(P.textFaint)
  local counter = string.format("%d / %d", T.step, #T.steps)
  lg.print(counter, x + w - pad - R.fonts.tiny:getWidth(counter), y + pad + 4)

  lg.setFont(R.fonts.mid)
  lg.setColor(P.accent)
  lg.print(step.title, x + pad, y + pad - 2)

  lg.setFont(bodyFont)
  lg.setColor(P.text)
  lg.printf(step.body, x + pad, y + pad + 30, w - pad * 2, "left")

  local by = y + h - 38
  U.button(x + pad, by, 96, 26, "SKIP", true,
    function() T.stop(); state.tutorialSkipped = true end,
    { font = R.fonts.small, color = P.panelEdge })

  if step.kind == "explain" then
    U.button(x + w - pad - 132, by, 132, 26, "NEXT   (space)", true,
      function() T.advance() end, { font = R.fonts.small, color = P.accent })
  else
    -- Action steps wait on the graph, so say what is being waited for.
    lg.setFont(R.fonts.small)
    local pulse = 0.55 + 0.45 * math.sin(R.t * 4)
    lg.setColor(P.good[1], P.good[2], P.good[3], pulse)
    local msg = "waiting for you..."
    lg.print(msg, x + w - pad - R.fonts.small:getWidth(msg), by + 6)
  end
end

return U
