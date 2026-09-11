-- ui.lua -- sidebar, inspector and overlays for the contract loop.
-- Immediate mode: buttons register while drawing and are hit-tested on click.
local P     = require("palette")
local R     = require("render")
local Graph = require("graph")
local C     = require("contract")
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
      if h.enabled then A.play("click", 0.8); h.action() else A.play("denied", 0.6) end
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

local function heading(text, x, y)
  lg.setFont(R.fonts.tiny)
  lg.setColor(P.textFaint)
  lg.print(string.upper(text), x, y)
end

local function statRow(x, y, w, name, value, color)
  lg.setFont(R.fonts.small)
  lg.setColor(P.textDim)
  lg.print(name, x, y)
  lg.setFont(R.fonts.body)
  lg.setColor(color or P.text)
  lg.print(value, x + w - R.fonts.body:getWidth(value), y - 2)
end

local function bar(x, y, w, h, frac, color, bg)
  lg.setColor(bg or P.with(P.panelEdge, 0.8))
  lg.rectangle("fill", x, y, w, h, h / 2)
  local f = math.max(0, math.min(1, frac))
  if f > 0 then lg.setColor(color); lg.rectangle("fill", x, y, w * f, h, h / 2) end
end

function U.button(x, y, w, h, text, enabled, action, opts)
  opts = opts or {}
  local mx, my = love.mouse.getPosition()
  local hot = mx >= x and mx <= x + w and my >= y and my <= y + h
  local base = opts.color or P.accent

  if not enabled then lg.setColor(P.with(P.panelEdge, 0.55))
  elseif hot then lg.setColor(base[1], base[2], base[3], 0.92)
  else lg.setColor(base[1] * 0.42, base[2] * 0.42, base[3] * 0.42, 0.92) end
  lg.rectangle("fill", x, y, w, h, 5)
  lg.setColor(enabled and P.with(base, hot and 1 or 0.75) or P.with(P.textFaint, 0.5))
  lg.setLineWidth(1)
  lg.rectangle("line", x, y, w, h, 5)

  local font = opts.font or R.fonts.body
  lg.setFont(font)
  if not enabled then lg.setColor(P.with(P.textFaint, 0.75))
  elseif hot then lg.setColor(P.bg)
  else lg.setColor(P.text) end
  lg.print(text, x + (w - font:getWidth(text)) / 2, y + (h - font:getHeight()) / 2)

  U.hits[#U.hits + 1] = { x = x, y = y, w = w, h = h, enabled = enabled, action = action }
  return hot
end

local function fieldCentre(w)
  local W = lg.getWidth()
  local avail = W - U.SIDEBAR
  if avail < w + 24 then return math.max(8, (W - w) / 2) end
  return U.SIDEBAR + (avail - w) / 2
end

local function dim(a)
  lg.setColor(0, 0, 0, a or 0.72)
  lg.rectangle("fill", 0, 0, lg.getWidth(), lg.getHeight())
end

function U.threatText(threat)
  return string.format("%s %d %s",
    threat.kind == "node" and "destroys" or "severs",
    threat.count,
    threat.kind == "node" and (threat.count == 1 and "node" or "nodes")
                           or (threat.count == 1 and "link" or "links"))
end

--------------------------------------------------------------------------------
-- Sidebar
--------------------------------------------------------------------------------

function U.drawSidebar(ct, camp, state)
  local W, H = lg.getDimensions()
  local x, w = 12, U.SIDEBAR - 24
  lg.setColor(P.panel[1], P.panel[2], P.panel[3], 0.98)
  lg.rectangle("fill", 0, 0, U.SIDEBAR, H)
  lg.setColor(P.with(P.panelEdge, 0.9))
  lg.line(U.SIDEBAR, 0, U.SIDEBAR, H)

  local y = 14
  lg.setFont(R.fonts.mid)
  lg.setColor(P.accent)
  lg.print("AUGMENT", x, y)
  lg.setFont(R.fonts.small)
  lg.setColor(P.textFaint)
  local prog = "tutorial"
  if camp then
    local i, n = camp:progress()
    prog = string.format("contract %d / %d", i, n)
  end
  lg.print(prog, x + w - R.fonts.small:getWidth(prog), y + 6)
  y = y + 32

  -- The win condition leads: what survives the strike.
  local resilient = ct:resilience()
  local solved = resilient >= ct.demand
  panel(x, y, w, 92)
  heading("after the strike", x + 12, y + 9)
  lg.setFont(R.fonts.big)
  lg.setColor(solved and P.good or P.bad)
  lg.print(tostring(resilient), x + 12, y + 22)
  lg.setFont(R.fonts.body)
  lg.setColor(P.textDim)
  lg.print("/ " .. ct.demand .. " demanded",
    x + 12 + R.fonts.big:getWidth(tostring(resilient)) + 8, y + 38)
  bar(x + 12, y + 62, w - 24, 7, ct.demand > 0 and resilient / ct.demand or 1,
      solved and P.good or P.bad)
  lg.setFont(R.fonts.tiny)
  lg.setColor(P.textFaint)
  lg.print(string.format("delivering %d now, capacity %d", ct.flow, ct.capacity), x + 12, y + 74)
  y = y + 102

  -- Budget.
  local left = ct:remaining()
  panel(x, y, w, 76)
  heading("budget", x + 12, y + 9)
  lg.setFont(R.fonts.big)
  lg.setColor(left > 0 and P.energy or P.bad)
  lg.print(tostring(left), x + 12, y + 20)
  lg.setFont(R.fonts.tiny)
  lg.setColor(P.textFaint)
  lg.printf(string.format("%d of %d spent", ct.spent, ct.budget), x + 12, y + 26, w - 24, "right")
  bar(x + 12, y + 50, w - 24, 7, ct.budget > 0 and ct.spent / ct.budget or 0, P.energy)
  if ct.par then
    -- Par marker, so beating it is a visible target rather than a surprise.
    local px = x + 12 + (w - 24) * math.min(1, ct.par / ct.budget)
    lg.setColor(P.accent)
    lg.setLineWidth(2)
    lg.line(px, y + 47, px, y + 60)
    lg.setFont(R.fonts.tiny)
    lg.setColor(ct.spent <= ct.par and P.accent or P.textFaint)
    lg.print("par " .. ct.par, x + 12, y + 62)
  end
  y = y + 86

  -- The declared threat.
  panel(x, y, w, 60)
  heading("the adversary", x + 12, y + 9)
  lg.setFont(R.fonts.body)
  lg.setColor(ct.threat.kind == "node" and P.warn or P.bad)
  lg.print(U.threatText(ct.threat), x + 12, y + 24)
  lg.setFont(R.fonts.tiny)
  lg.setColor(P.textFaint)
  lg.print("marked in red on the field", x + 12, y + 44)
  y = y + 70

  -- Build palette: only what the player actually holds.
  heading("build", x, y); y = y + 14
  local kinds = { { "relay", "1" }, { "hub", "2" }, { "conduit", "3" } }
  for _, k in ipairs(kinds) do
    local kind, key = k[1], k[2]
    if ct.tools[kind] then
      local spec = Graph.KINDS[kind]
      local cost = ct:nodeCost(kind)
      local afford = left >= cost and not ct.committed
      local active = state.tool == kind
      local bh = 38
      local mx, my = love.mouse.getPosition()
      local hot = mx >= x and mx <= x + w and my >= y and my <= y + bh

      lg.setColor(active and P.with(spec.color, 0.24)
        or (hot and P.with(P.panelEdge, 0.75) or P.with(P.panel, 1)))
      lg.rectangle("fill", x, y, w, bh, 5)
      lg.setColor(active and P.with(spec.color, 0.95) or P.with(P.panelEdge, 0.9))
      lg.setLineWidth(active and 1.8 or 1)
      lg.rectangle("line", x, y, w, bh, 5)

      lg.setColor(P.with(spec.color, afford and 1 or 0.4))
      lg.circle("fill", x + 20, y + bh / 2, 7)
      lg.setFont(R.fonts.body)
      lg.setColor(afford and P.text or P.textFaint)
      lg.print(spec.name, x + 36, y + 5)
      lg.setFont(R.fonts.tiny)
      lg.setColor(P.textFaint)
      local note = (kind == "conduit") and string.format("%d ports  long reach", spec.ports)
                                        or string.format("%d ports", spec.ports)
      lg.print(note, x + 36, y + 22)
      lg.setFont(R.fonts.body)
      lg.setColor(afford and P.energy or P.bad)
      lg.print(tostring(cost), x + w - 14 - R.fonts.body:getWidth(tostring(cost)), y + 5)
      lg.setFont(R.fonts.tiny)
      lg.setColor(P.textFaint)
      lg.print(key, x + w - 14 - R.fonts.tiny:getWidth(key), y + 23)

      U.hits[#U.hits + 1] = { x = x, y = y, w = w, h = bh, enabled = not ct.committed,
                              action = function()
                                state.tool = (state.tool == kind) and nil or kind
                              end }
      y = y + bh + 5
    end
  end
  y = y + 6

  local st = ct.g:stats()
  panel(x, y, w, 78)
  heading("graph", x + 12, y + 9)
  local iy = y + 26
  statRow(x + 12, iy, w - 24, "order  |V|", tostring(st.order)); iy = iy + 19
  statRow(x + 12, iy, w - 24, "size  |E|", tostring(st.size)); iy = iy + 19
  statRow(x + 12, iy, w - 24, "cut vertices", tostring(#st.cutVertices),
          #st.cutVertices > 0 and P.warn or P.good)
end

--------------------------------------------------------------------------------
-- Objective line, inspector, bottom bar
--------------------------------------------------------------------------------

function U.objective(ct)
  if ct.committed then return nil end
  local resilient = ct:resilience()
  if ct.g:stats().size == 0 then
    return "Drag from the source to a terminal to lay your first link.", P.good
  end

  local lbl = ct.g:components()
  local home = lbl[ct.source.id]
  for _, t in ipairs(ct.terminals) do
    if lbl[t.id] ~= home then
      return "A terminal is not connected to the source yet.", P.bad
    end
  end

  if ct.flow < ct.demand then
    return string.format("Short by %d before any strike. Widen a link with U.",
      ct.demand - ct.flow), P.bad
  end
  if resilient < ct.demand then
    return string.format("The adversary %s and leaves you %d of %d. Add a route that avoids the red.",
      U.threatText(ct.threat), resilient, ct.demand), P.warn
  end
  if ct.par and ct.spent > ct.par then
    return string.format("Solved. Par is %d and you are at %d, if you want it tighter.",
      ct.par, ct.spent), P.accent
  end
  return "Solved, at or under par. Commit when ready.", P.good
end

function U.drawInspector(ct, state)
  local W, H = lg.getDimensions()
  local w, h = 250, 104
  local x, y = W - w - 16, H - U.BOTTOM - h - 16
  local g = ct.g

  if state.selNode then
    local n = g.nodes[state.selNode]
    if not (n and n.alive) then state.selNode = nil; return end
    local spec = Graph.KINDS[n.kind]
    panel(x, y, w, h)
    lg.setFont(R.fonts.body); lg.setColor(spec.color)
    lg.print(spec.name, x + 12, y + 10)
    local iy = y + 34
    statRow(x + 12, iy, w - 24, "degree / ports",
            string.format("%d / %d", g:degree(n.id), n.ports))
    local canDemo = not ct.committed and n.kind ~= "source" and n.kind ~= "sink"
    U.button(x + 12, y + h - 34, w - 24, 24, "demolish  (refunds in full)", canDemo,
      function()
        local refund = ct:demolishNode(n.id)
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
    lg.setFont(R.fonts.body); lg.setColor(P.linkLive)
    lg.print("LINK", x + 12, y + 10)
    local f = math.abs((ct.detail and ct.detail.edge[e.id]) or 0)
    local iy = y + 34
    statRow(x + 12, iy, w - 24, "capacity / carrying",
            string.format("%d / %d", e.cap, math.floor(f + 0.5)))
    local cc = ct:capCost()
    U.button(x + 12, y + h - 34, 112, 24, string.format("+1 cap  %d", cc),
      not ct.committed and ct:remaining() >= cc,
      function() if ct:upgradeLink(e.id) then A.play("upgrade") end end,
      { font = R.fonts.small, color = P.flow })
    U.button(x + w - 124, y + h - 34, 112, 24, "demolish", not ct.committed,
      function()
        local na, nb = g.nodes[e.a], g.nodes[e.b]
        local refund = ct:demolishLink(e.id)
        if refund then
          A.play("demolish")
          R.floatText((na.x + nb.x) / 2, (na.y + nb.y) / 2, "+" .. refund, P.energy)
        end
        state.selEdge = nil
      end, { font = R.fonts.small, color = P.bad })
  end
end

function U.drawBottom(ct, state)
  local W, H = lg.getDimensions()
  local x, y = U.SIDEBAR, H - U.BOTTOM
  lg.setColor(P.panel[1], P.panel[2], P.panel[3], 0.98)
  lg.rectangle("fill", x, y, W - x, U.BOTTOM)
  lg.setColor(P.with(P.panelEdge, 0.9))
  lg.line(x, y, W, y)

  local bw, bh = 172, 40
  local obj, objColor = U.objective(ct)
  lg.setFont(R.fonts.small)
  local hint = state.tool
    and string.format("click the site to place a %s   -   esc to cancel", Graph.KINDS[state.tool].name)
    or (obj or "drag node to node to link   -   drag empty space to pan   -   H for help")
  lg.setColor(state.tool and P.textFaint or (objColor or P.textFaint))
  local avail = (W - bw * 2 - 44) - (x + 18)
  while avail > 40 and R.fonts.small:getWidth(hint) > avail do
    hint = hint:sub(1, #hint - 4) .. "..."
  end
  lg.print(hint, x + 18, y + U.BOTTOM / 2 - 8)

  U.button(W - bw * 2 - 28, y + (U.BOTTOM - bh) / 2, bw, bh, "CLEAR SITE", not ct.committed,
    function() state.wantRetry = true end, { color = P.panelEdge, font = R.fonts.small })

  local solved = ct:resilience() >= ct.demand
  U.button(W - bw - 16, y + (U.BOTTOM - bh) / 2, bw, bh,
    solved and "COMMIT" or "COMMIT (fails)", not ct.committed,
    function() state.wantCommit = true end,
    { color = solved and P.good or P.bad })
end

--------------------------------------------------------------------------------
-- Overlays
--------------------------------------------------------------------------------

function U.drawResult(ct, camp, state)
  local res = ct.result
  if not res then return end
  local W, H = lg.getDimensions()
  local w, h = 470, 290
  local x, y = fieldCentre(w), (H - h) / 2
  dim(0.66)
  panel(x, y, w, h, 1)

  lg.setFont(R.fonts.big)
  lg.setColor(res.success and P.good or P.bad)
  lg.print(res.success and "CONTRACT HELD" or "NETWORK FAILED", x + 26, y + 22)

  lg.setFont(R.fonts.small)
  lg.setColor(P.textDim)
  lg.printf(string.format("The adversary %s. You delivered %d of %d.",
    U.threatText(ct.threat), res.delivered, res.demand), x + 26, y + 66, w - 52, "left")

  local iy = y + 108
  statRow(x + 26, iy, w - 52, "spent", string.format("%d of %d", res.spent, res.budget),
          P.energy); iy = iy + 24
  if res.par then
    statRow(x + 26, iy, w - 52, "par", tostring(res.par),
            res.beatPar and P.accent or P.textDim); iy = iy + 24
  end
  statRow(x + 26, iy, w - 52, "under budget", tostring(res.under), P.good)

  if res.beatPar and res.success then
    lg.setFont(R.fonts.body)
    lg.setColor(P.accent)
    lg.print("Under par.", x + 26, iy + 30)
  end

  if res.success then
    local i, n = 1, 1
    if camp then i, n = camp:progress() end
    local last = i >= n
    U.button(x + w - 190, y + h - 56, 164, 36, last and "FINISH RUN" or "NEXT CONTRACT", true,
      function() state.wantNext = true end, { color = P.good })
    U.button(x + 26, y + h - 56, 150, 36, "RE-LAY IT", true,
      function() state.wantRetry = true end, { color = P.panelEdge, font = R.fonts.small })
  else
    U.button(x + w - 190, y + h - 56, 164, 36, "TRY AGAIN", true,
      function() state.wantRetry = true end, { color = P.good })
  end
end

function U.drawComplete(camp, state)
  local W, H = lg.getDimensions()
  local w, h = 460, 250
  local x, y = fieldCentre(w), (H - h) / 2
  dim(0.85)
  panel(x, y, w, h, 1)
  lg.setFont(R.fonts.big)
  lg.setColor(P.good)
  lg.print("RUN COMPLETE", x + 26, y + 24)
  lg.setFont(R.fonts.small)
  lg.setColor(P.textDim)
  lg.printf("Every contract held.", x + 26, y + 68, w - 52, "left")
  local iy = y + 104
  statRow(x + 26, iy, w - 52, "contracts", tostring(#camp.specs)); iy = iy + 24
  statRow(x + 26, iy, w - 52, "total under budget", tostring(camp.totalUnder), P.accent)
  U.button(x + w - 176, y + h - 56, 150, 36, "NEW RUN", true,
    function() state.wantNewRun = true end, { color = P.good })
end

function U.drawHelp(state)
  local W, H = lg.getDimensions()
  dim(0.93)
  local w = 640
  local x, y = fieldCentre(w), 50
  lg.setFont(R.fonts.big); lg.setColor(P.accent)
  lg.print("HOW A CONTRACT WORKS", x, y)
  y = y + 50

  local lines = {
    { "THE RULE", P.text },
    { "Build a network that still meets every terminal's demand AFTER the adversary", P.textDim },
    { "takes its best cut. One fixed budget, no income. Demolition refunds in full,", P.textDim },
    { "so re-laying the whole site costs you nothing but thought.", P.textDim },
    { "", P.text },
    { "THE RED MARKS", P.cut },
    { "They show exactly what the adversary will take if you commit now. This is not", P.textDim },
    { "a guess: it is computed against your current network, every time you change it.", P.textDim },
    { "Make the red stop mattering and the contract is solved.", P.textDim },
    { "", P.text },
    { "WHY REDUNDANCY, NOT CAPACITY", P.text },
    { "Capacity is cheap and fragile: one thick link is a cut of width one. Routes are", P.textDim },
    { "expensive and robust. With r disjoint routes against a threat of k, you keep", P.textDim },
    { "r-k of them, so each needs demand/(r-k) capacity. Few fat routes or many thin", P.textDim },
    { "ones: there is a cheapest answer in between, and finding it is the puzzle.", P.textDim },
    { "", P.text },
    { "NODES ARE NOT LINKS", P.warn },
    { "When the threat destroys nodes, routes that share a relay die together. You need", P.textDim },
    { "routes that share no node, not merely no link.", P.textDim },
    { "", P.text },
    { "CONTROLS", P.text },
    { "1 2 3 pick a node and click to place it. Drag node to node to link.", P.textDim },
    { "U upgrades a link, X demolishes. Drag empty space to pan, wheel zooms.", P.textDim },
    { "S mutes. Enter commits.", P.textDim },
  }
  lg.setFont(R.fonts.small)
  for _, l in ipairs(lines) do
    lg.setColor(l[2]); lg.print(l[1], x, y)
    y = y + (l[1] == "" and 8 or 18)
  end
  U.button(x, y + 14, 180, 38, "BACK", true,
    function() state.screen = "contract" end, { color = P.good })
end

function U.drawTitle(state, meta)
  local W, H = lg.getDimensions()
  lg.setColor(P.bg[1], P.bg[2], P.bg[3], 0.86)
  lg.rectangle("fill", 0, 0, W, H)
  local cx, cy = W / 2, H / 2 - 70

  lg.setFont(R.fonts.huge); lg.setColor(P.accent)
  lg.print("AUGMENT", cx - R.fonts.huge:getWidth("AUGMENT") / 2, cy - 90)
  lg.setFont(R.fonts.body); lg.setColor(P.textDim)
  local s = "build a network that survives its own minimum cut"
  lg.print(s, cx - R.fonts.body:getWidth(s) / 2, cy - 28)

  if (meta.runs or 0) > 0 then
    lg.setFont(R.fonts.small); lg.setColor(P.textFaint)
    local r = string.format("%d runs   best contract %d   %d total under budget",
      meta.runs, meta.bestContract or 0, meta.bestUnder or 0)
    lg.print(r, cx - R.fonts.small:getWidth(r) / 2, cy + 4)
  end

  local fresh = not meta.tutorialDone
  if fresh then
    U.button(cx - 110, cy + 50, 220, 46, "TUTORIAL", true,
      function() state.startTutorial = true end, { color = P.accent, font = R.fonts.mid })
    U.button(cx - 110, cy + 106, 220, 34, "SKIP TO FREE PLAY", true,
      function() state.wantNewRun = true end, { color = P.good, font = R.fonts.small })
    lg.setFont(R.fonts.tiny); lg.setColor(P.textFaint)
    local n = "first time? the tutorial takes about two minutes"
    lg.print(n, cx - R.fonts.tiny:getWidth(n) / 2, cy + 148)
    U.button(cx - 55, cy + 168, 110, 30, "HOW", true,
      function() state.screen = "help" end, { color = P.flow, font = R.fonts.small })
  else
    U.button(cx - 110, cy + 50, 220, 46, "BEGIN RUN", true,
      function() state.wantNewRun = true end, { color = P.good, font = R.fonts.mid })
    U.button(cx - 110, cy + 106, 105, 34, "TUTORIAL", true,
      function() state.startTutorial = true end, { color = P.accent, font = R.fonts.small })
    U.button(cx + 5, cy + 106, 105, 34, "HOW", true,
      function() state.screen = "help" end, { color = P.flow, font = R.fonts.small })
  end
end

function U.drawTutorial(ct, state, T)
  local step = T.current()
  if not step then return end
  local W, H = lg.getDimensions()
  local avail = W - U.SIDEBAR
  local w = math.min(600, avail - 32)
  local x, y = U.SIDEBAR + (avail - w) / 2, 16
  local pad = 18
  local _, lines = R.fonts.body:getWrap(step.body, w - pad * 2)
  local h = pad + 24 + 8 + #lines * (R.fonts.body:getHeight() + 3) + 46

  lg.setColor(P.panel[1], P.panel[2], P.panel[3], 0.97)
  lg.rectangle("fill", x, y, w, h, 7)
  lg.setColor(P.with(P.accent, 0.85)); lg.setLineWidth(1.5)
  lg.rectangle("line", x, y, w, h, 7)

  lg.setFont(R.fonts.tiny); lg.setColor(P.textFaint)
  local counter = string.format("%d / %d", T.step, #T.steps)
  lg.print(counter, x + w - pad - R.fonts.tiny:getWidth(counter), y + pad + 4)
  lg.setFont(R.fonts.mid); lg.setColor(P.accent)
  lg.print(step.title, x + pad, y + pad - 2)
  lg.setFont(R.fonts.body); lg.setColor(P.text)
  lg.printf(step.body, x + pad, y + pad + 30, w - pad * 2, "left")

  local by = y + h - 38
  U.button(x + pad, by, 96, 26, "SKIP", true,
    function() T.stop(); state.tutorialSkipped = true end,
    { font = R.fonts.small, color = P.panelEdge })
  if step.kind == "explain" then
    U.button(x + w - pad - 132, by, 132, 26, "NEXT   (space)", true,
      function() T.advance() end, { font = R.fonts.small, color = P.accent })
  else
    lg.setFont(R.fonts.small)
    lg.setColor(P.good[1], P.good[2], P.good[3], 0.55 + 0.45 * math.sin(R.t * 4))
    local msg = "waiting for you..."
    lg.print(msg, x + w - pad - R.fonts.small:getWidth(msg), by + 6)
  end
end

return U
