-- render.lua -- drawing the field. The visual language is deliberate:
--   link thickness  = capacity          (what it could carry)
--   moving dots     = flow              (what it does carry)
--   red pulse       = the minimum cut   (what is about to be taken)
--   node ring       = ports used        (degree against its limit)
-- If the player can read those four things, they can read a flow network.
local P = require("palette")
local Graph = require("graph")
local Contract = require("contract")

local R = {}
R.fx = {}
R.t = 0

local lg = love.graphics

function R.dimensions()
  if R.viewportOverride then return R.viewportOverride[1], R.viewportOverride[2] end
  return lg.getDimensions()
end

function R.init()
  R.fonts = {
    tiny  = lg.newFont(11),
    small = lg.newFont(12),
    body  = lg.newFont(14),
    mid   = lg.newFont(18),
    big   = lg.newFont(30),
    huge  = lg.newFont(54),
  }
end

--------------------------------------------------------------------------------
-- Zoom
--------------------------------------------------------------------------------

-- How large a symbol is drawn at a given camera scale.
--
-- A symbol must never grow as the camera pulls back, and clamping its size with
-- math.max(floor, k * scale) does precisely that: past the floor the world keeps
-- shrinking underneath a symbol that has stopped, so a city seen from far out
-- fills with blobs larger than the streets they stand on. The cure is to
-- compress the curve rather than clamp it. scale^0.55 is strictly increasing --
-- zooming out always makes a symbol smaller -- but it falls away slowly enough
-- that a node is still five pixels across at the furthest zoom instead of two.
local SYM = 0.55
function R.sym(base, scale)
  return base * scale ^ SYM
end

--------------------------------------------------------------------------------
-- Effects
--------------------------------------------------------------------------------

function R.burst(x, y, color, n)
  for _ = 1, (n or 14) do
    local a = math.random() * math.pi * 2
    local s = 40 + math.random() * 170
    R.fx[#R.fx + 1] = {
      kind = "spark", x = x, y = y,
      vx = math.cos(a) * s, vy = math.sin(a) * s,
      life = 0.5 + math.random() * 0.5, age = 0, color = color,
    }
  end
end

function R.floatText(x, y, text, color)
  R.fx[#R.fx + 1] = { kind = "text", x = x, y = y, text = text,
                      color = color, life = 1.3, age = 0 }
end

function R.ring(x, y, color)
  R.fx[#R.fx + 1] = { kind = "ring", x = x, y = y, color = color, life = 0.6, age = 0 }
end

function R.update(dt)
  R.t = R.t + dt
  for i = #R.fx, 1, -1 do
    local f = R.fx[i]
    f.age = f.age + dt
    if f.kind == "spark" then
      f.x = f.x + f.vx * dt
      f.y = f.y + f.vy * dt
      f.vx = f.vx * (1 - dt * 2.4)
      f.vy = f.vy * (1 - dt * 2.4)
    elseif f.kind == "text" then
      f.y = f.y - dt * 26
    end
    if f.age >= f.life then table.remove(R.fx, i) end
  end
end

function R.drawEffects(cam)
  for _, f in ipairs(R.fx) do
    local k = 1 - f.age / f.life
    local sx, sy = cam:toScreen(f.x, f.y)
    if f.kind == "spark" then
      lg.setColor(f.color[1], f.color[2], f.color[3], k)
      lg.circle("fill", sx, sy, 2.2 * k * cam.scale + 0.6)
    elseif f.kind == "ring" then
      lg.setColor(f.color[1], f.color[2], f.color[3], k * 0.8)
      lg.setLineWidth(2.5 * k + 0.5)
      lg.circle("line", sx, sy, (1 - k) * 60 * cam.scale + 6)
    elseif f.kind == "text" then
      lg.setFont(R.fonts.body)
      lg.setColor(f.color[1], f.color[2], f.color[3], math.min(1, k * 1.6))
      lg.printf(f.text, sx - 70, sy - 8, 140, "center")
    end
  end
end

--------------------------------------------------------------------------------
-- Field
--------------------------------------------------------------------------------

function R.drawGrid(cam, fieldW, fieldH)
  -- The city is large enough to be viewed from a long way out; a fixed grid
  -- step turns into a solid wash at that distance, so it coarsens with zoom.
  local step = cam.scale < 0.30 and 600 or cam.scale < 0.55 and 240 or 120
  local x0, y0 = cam:toWorld(cam.vx, cam.vy)
  local x1, y1 = cam:toWorld(cam.vx + cam.vw, cam.vy + cam.vh)
  lg.setLineWidth(1)
  for gx = math.floor(x0 / step) * step, x1, step do
    local major = (gx % (step * 5) == 0)
    lg.setColor(major and P.gridMajor or P.grid)
    local ax, ay = cam:toScreen(gx, y0)
    local bx, by = cam:toScreen(gx, y1)
    lg.line(ax, ay, bx, by)
  end
  for gy = math.floor(y0 / step) * step, y1, step do
    local major = (gy % (step * 5) == 0)
    lg.setColor(major and P.gridMajor or P.grid)
    local ax, ay = cam:toScreen(x0, gy)
    local bx, by = cam:toScreen(x1, gy)
    lg.line(ax, ay, bx, by)
  end

  -- Field boundary: you cannot build past it.
  lg.setColor(P.with(P.panelEdge, 0.9))
  lg.setLineWidth(2)
  local ax, ay = cam:toScreen(0, 0)
  local bx, by = cam:toScreen(fieldW, fieldH)
  lg.rectangle("line", ax, ay, bx - ax, by - ay)
end

-- Blocked ground. Nothing may be built on it and no link may cross it, so it
-- reads as solid rather than decorative.
function R.drawObstacles(cam, obstacles)
  for _, o in ipairs(obstacles or {}) do
    local sx, sy = cam:toScreen(o.x, o.y)
    local r = o.r * cam.scale
    lg.setColor(0.12, 0.10, 0.14, 0.95)
    lg.circle("fill", sx, sy, r)
    lg.setColor(P.bad[1] * 0.5, P.bad[2] * 0.35, P.bad[3] * 0.4, 0.5)
    lg.setLineWidth(1.5)
    lg.circle("line", sx, sy, r)
    -- Hatching, so it never reads as empty space you simply have not used.
    lg.setColor(P.bad[1] * 0.45, P.bad[2] * 0.3, P.bad[3] * 0.35, 0.22)
    lg.setLineWidth(1)
    local step = math.max(7, 13 * cam.scale)
    for d = -r, r, step do
      local h = math.sqrt(math.max(0, r * r - d * d))
      lg.line(sx + d, sy - h, sx + d, sy + h)
    end
  end
end

--------------------------------------------------------------------------------
-- Links
--------------------------------------------------------------------------------

local function edgeWidth(cap, scale)
  return math.max(1.4, (1.1 + math.min(cap, 24) * 0.52) * scale)
end

function R.drawLinks(cam, run, hoverEdge, selectedEdge)
  local g = run.g
  local pulse = 0.55 + 0.45 * math.sin(R.t * 4.2)
  local dark = {}
  for _, id in ipairs(run:darkNodes()) do dark[id] = true end

  for _, e in ipairs(g.edges) do
    if e.alive then
      local na, nb = g.nodes[e.a], g.nodes[e.b]
      if na.alive and nb.alive then
        local ax, ay = cam:toScreen(na.x, na.y)
        local bx, by = cam:toScreen(nb.x, nb.y)
        local inCut = run.focusSet and run.focusSet.edge[e.id]
        local isDark = dark[e.a] or dark[e.b]
        local w = edgeWidth(e.cap, cam.scale)

        -- A wide, dim underlay reads as installed capacity.
        lg.setLineWidth(w)
        if isDark then
          lg.setColor(P.with(P.textFaint, 0.35))
        elseif inCut then
          lg.setColor(P.cut[1], P.cut[2], P.cut[3], 0.35 + 0.45 * pulse)
        else
          lg.setColor(P.with(P.link, 0.95))
        end
        lg.line(ax, ay, bx, by)

        if e.id == selectedEdge then
          lg.setColor(P.with(P.accent, 0.95))
          lg.setLineWidth(w + 4)
          lg.line(ax, ay, bx, by)
          lg.setLineWidth(w)
          lg.setColor(P.with(P.link, 0.95))
          lg.line(ax, ay, bx, by)
        elseif e.id == hoverEdge then
          lg.setColor(P.with(P.text, 0.30))
          lg.setLineWidth(w + 3)
          lg.line(ax, ay, bx, by)
        end

        -- Flow as travelling dots, one per unit, so "3 of 5" is countable.
        local f = math.abs((run.detail and run.detail.edge[e.id]) or 0)
        if f > 0.01 and not isDark then
          local sign = ((run.detail.edge[e.id] or 0) >= 0) and 1 or -1
          local dx, dy = bx - ax, by - ay
          local len = math.sqrt(dx * dx + dy * dy)
          if len > 1 then
            local n = math.min(math.ceil(f), 14)
            local speed = 0.34
            for i = 1, n do
              local phase = ((R.t * speed) + i / n) % 1
              if sign < 0 then phase = 1 - phase end
              local px = ax + dx * phase
              local py = ay + dy * phase
              lg.setColor(P.flow[1], P.flow[2], P.flow[3], 0.92)
              lg.circle("fill", px, py, math.max(1, R.sym(2.5, cam.scale)))
            end
          end
        end

        -- Capacity labels are noise on every link at once: show them where they
        -- inform, and everywhere only once zoomed in.
        local showLabel = cam.scale > 0.95 or inCut
          or e.id == hoverEdge or e.id == selectedEdge
        if showLabel then
          local mx, my = (ax + bx) / 2, (ay + by) / 2
          lg.setFont(R.fonts.tiny)
          local label = string.format("%d", e.cap)
          if f > 0.01 then label = string.format("%d/%d", math.floor(f + 0.5), e.cap) end
          local tw = R.fonts.tiny:getWidth(label)
          lg.setColor(P.with(P.bg, 0.82))
          lg.rectangle("fill", mx - tw / 2 - 3, my - 7, tw + 6, 14, 3)
          lg.setColor(inCut and P.cut or P.textDim)
          lg.print(label, mx - tw / 2, my - 6)
        end

        -- Mark the cut itself.
        if inCut then
          local mx, my = (ax + bx) / 2, (ay + by) / 2
          local dx, dy = bx - ax, by - ay
          local len = math.max(1, math.sqrt(dx * dx + dy * dy))
          local px, py = -dy / len, dx / len
          local s = 13 * cam.scale + 5
          lg.setColor(P.cut[1], P.cut[2], P.cut[3], 0.55 + 0.45 * pulse)
          lg.setLineWidth(2)
          lg.line(mx + px * s, my + py * s, mx - px * s, my - py * s)
        end
      end
    end
  end
end

--------------------------------------------------------------------------------
-- Nodes
--------------------------------------------------------------------------------

local function nodeRadius(kind, scale)
  local base = (kind == "source" and 22) or (kind == "sink" and 19) or 15
  return base * scale
end

function R.drawNodes(cam, run, hoverNode, selectedNode)
  local g = run.g
  local pulse = 0.55 + 0.45 * math.sin(R.t * 4.2)
  local dark = {}
  for _, id in ipairs(run:darkNodes()) do dark[id] = true end

  for _, n in ipairs(g.nodes) do
    if n.alive then
      local spec = Graph.KINDS[n.kind]
      local sx, sy = cam:toScreen(n.x, n.y)
      local r = nodeRadius(n.kind, cam.scale)
      local inCut = run.focusSet and run.focusSet.node[n.id]
      local isDark = dark[n.id]

      if n.kind == "source" then
        local glow = 0.20 + 0.10 * math.sin(R.t * 2.1)
        lg.setColor(spec.color[1], spec.color[2], spec.color[3], glow)
        lg.circle("fill", sx, sy, r * 2.3)
      end

      if inCut then
        lg.setColor(P.cut[1], P.cut[2], P.cut[3], 0.20 + 0.28 * pulse)
        lg.circle("fill", sx, sy, r * 2.0)
      end

      if n.id == selectedNode then
        lg.setColor(P.with(P.accent, 0.9))
        lg.setLineWidth(2)
        lg.circle("line", sx, sy, r + 7)
      elseif n.id == hoverNode then
        lg.setColor(P.with(P.text, 0.45))
        lg.setLineWidth(1.5)
        lg.circle("line", sx, sy, r + 6)
      end

      -- Port ring: one tick per port, filled when the port is in use.
      local used = g:degree(n.id)
      local ports = n.ports
      if cam.scale > 0.45 then
        for i = 1, ports do
          local a = -math.pi / 2 + (i - 1) * (math.pi * 2 / ports)
          local rr = r + 5
          local px, py = sx + math.cos(a) * rr, sy + math.sin(a) * rr
          if i <= used then
            lg.setColor(P.with(spec.color, 0.95))
            lg.circle("fill", px, py, math.max(1, R.sym(2.1, cam.scale)))
          else
            lg.setColor(P.with(P.textFaint, 0.75))
            lg.circle("line", px, py, math.max(1, R.sym(2.0, cam.scale)))
          end
        end
      end

      -- Body, dimmed to a shell when the node is cut off from the source.
      local c = spec.color
      if isDark then
        lg.setColor(c[1] * 0.32, c[2] * 0.32, c[3] * 0.32, 0.9)
      else
        lg.setColor(c[1] * 0.30, c[2] * 0.30, c[3] * 0.30, 0.98)
      end
      lg.circle("fill", sx, sy, r)

      -- Fill proportion shows how loaded the node is against its throughput.
      local load = (run.detail and run.detail.node[n.id]) or 0
      if n.throughput < Graph.INF and n.throughput > 0 and load > 0 then
        local frac = math.min(1, load / n.throughput)
        lg.setColor(c[1], c[2], c[3], 0.85)
        lg.circle("fill", sx, sy, r * math.sqrt(frac))
      end

      lg.setLineWidth(inCut and 2.6 or 1.8)
      lg.setColor(inCut and P.cut or (isDark and P.textFaint or c))
      lg.circle("line", sx, sy, r)

      -- Terminals carry their own demand, so show delivery against it.
      if n.kind == "sink" and cam.scale > 0.4 then
        local served = (run.served and run.served[n.id]) or 0
        local demand = n.demand or 0
        local met = served >= demand
        lg.setFont(R.fonts.small)
        local label = string.format("%d/%d", served, demand)
        local tw = R.fonts.small:getWidth(label)
        lg.setColor(P.with(P.bg, 0.85))
        lg.rectangle("fill", sx - tw / 2 - 4, sy + r + 4, tw + 8, 16, 3)
        lg.setColor(met and P.good or P.bad)
        lg.print(label, sx - tw / 2, sy + r + 5)
      elseif n.kind == "source" and cam.scale > 0.4 then
        lg.setFont(R.fonts.small)
        lg.setColor(P.with(spec.color, 0.95))
        local label = "SOURCE"
        lg.print(label, sx - R.fonts.small:getWidth(label) / 2, sy + r + 6)
      elseif cam.scale > 0.72 and n.throughput < Graph.INF then
        lg.setFont(R.fonts.tiny)
        lg.setColor(P.with(P.textFaint, 0.95))
        local label = string.format("%d", n.throughput)
        lg.print(label, sx - R.fonts.tiny:getWidth(label) / 2, sy - 5)
      end
    end
  end
end

--------------------------------------------------------------------------------
-- Build previews
--------------------------------------------------------------------------------

function R.drawLinkDrag(cam, run, fromId, mx, my, targetId)
  local g = run.g
  local from = g.nodes[fromId]
  if not from then return end
  local ax, ay = cam:toScreen(from.x, from.y)

  -- Range circle: everything reachable in one link.
  lg.setColor(P.with(P.ghost, 0.22))
  lg.setLineWidth(1.5)
  lg.circle("line", ax, ay, run:rangeBetween(fromId, fromId) * cam.scale)

  local bx, by = mx, my
  local ok, why = true, nil
  if targetId then
    local t = g.nodes[targetId]
    bx, by = cam:toScreen(t.x, t.y)
    why = run:linkError(fromId, targetId)
    ok = (why == nil)
  else
    local wx, wy = cam:toWorld(mx, my)
    local d = math.sqrt((from.x - wx) ^ 2 + (from.y - wy) ^ 2)
    ok = d <= run:rangeBetween(fromId, fromId)
  end

  lg.setLineWidth(3)
  lg.setColor(ok and P.with(P.good, 0.85) or P.with(P.bad, 0.85))
  lg.line(ax, ay, bx, by)

  if targetId and not ok and why then
    lg.setFont(R.fonts.small)
    lg.setColor(P.bad)
    lg.printf(why, bx - 90, by - 34, 180, "center")
  elseif targetId and ok then
    local cost = run:linkCost(fromId, targetId)
    lg.setFont(R.fonts.small)
    lg.setColor(run:remaining() >= cost and P.energy or P.bad)
    lg.printf(string.format("%d energy", cost), (ax + bx) / 2 - 70, (ay + by) / 2 - 26, 140, "center")
  end
end

function R.drawPlaceGhost(cam, run, kind, mx, my)
  local wx, wy = cam:toWorld(mx, my)
  local err = run:placementError(wx, wy)
  local cost = run:nodeCost(kind)
  local afford = run:remaining() >= cost
  local spec = Graph.KINDS[kind]
  local r = nodeRadius(kind, cam.scale)
  local good = (not err) and afford

  lg.setColor(good and P.with(spec.color, 0.55) or P.with(P.bad, 0.45))
  lg.circle("line", mx, my, r)
  lg.setColor(good and P.with(spec.color, 0.16) or P.with(P.bad, 0.14))
  lg.circle("fill", mx, my, r)

  -- Show how far this node could reach, so placement is a spatial decision.
  lg.setColor(P.with(P.ghost, 0.13))
  lg.setLineWidth(1)
  local reach = (kind == "conduit") and Contract.conduitRange or Contract.maxLinkRange
  lg.circle("line", mx, my, reach * cam.scale)

  lg.setFont(R.fonts.small)
  local msg = err or (afford and string.format("%s  -  %d energy", spec.name, cost)
                             or string.format("need %d energy", cost))
  lg.setColor(good and P.textDim or P.bad)
  lg.printf(msg, mx - 100, my + r + 8, 200, "center")
end

-- A pulsing ring the tutorial puts around whatever it is currently talking
-- about, so an instruction never leaves the player hunting for the subject.
function R.drawFocusRing(cam, wx, wy)
  local sx, sy = cam:toScreen(wx, wy)
  local pulse = (R.t * 1.5) % 1
  for i = 0, 1 do
    local k = (pulse + i * 0.5) % 1
    lg.setColor(P.accent[1], P.accent[2], P.accent[3], (1 - k) * 0.65)
    lg.setLineWidth(2.5)
    lg.circle("line", sx, sy, 22 + k * 46)
  end
  lg.setColor(P.accent[1], P.accent[2], P.accent[3], 0.30 + 0.20 * math.sin(R.t * 4))
  lg.setLineWidth(2)
  lg.circle("line", sx, sy, 20)
end

return R
