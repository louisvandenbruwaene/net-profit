-- road_draw.lua -- the roads, drawn as road_shape.lua says they lie.
--
-- Layer by layer, every street before the next layer, so that roads meeting
-- merge into one surface instead of being stacked:
--   decks      a bridge's deck, piers and shadow where a road crosses water
--   slip roads an interchange's ramps, under the roads they join
--   verges     pavements beside a normal road, a hard shoulder by a highway
--   surface    the carriageway, junction pads included
--   markings   centre lines, a highway's four lanes and central reserve,
--              stop lines and zebra crossings at junctions, a track's ruts
--   flyovers   where one road crosses another with no junction, the upper
--              one again, on its own deck, with a shadow on the road below
--   signs      give way, speed limits, motorway and exit boards
local RS = require("road_shape")
local City = require("city")
local R = require("render")

local Roads = {}
local lg = love and love.graphics
local max, min, sqrt, floor = math.max, math.min, math.sqrt, math.floor

local SURFACE = { road = { 0.25, 0.26, 0.28 }, highway = { 0.21, 0.22, 0.24 }, offroad = { 0.45, 0.36, 0.25 }, ramp = { 0.23, 0.24, 0.26 } }
local VERGE = { road = { 0.52, 0.52, 0.50 }, highway = { 0.40, 0.41, 0.36 }, offroad = { 0.36, 0.30, 0.21 }, ramp = { 0.40, 0.41, 0.36 } }
local DECK = { 0.46, 0.46, 0.47 }

-- One coloured triangle strip, reused frame to frame.
local mesh, cap
local function strip(verts)
  if #verts < 4 then return end
  if not mesh or #verts > cap then
    cap = max(#verts, 2 * (cap or 512))
    mesh = lg.newMesh({ { "VertexPosition", "float", 2 }, { "VertexColor", "float", 4 } }, cap, "strip", "stream")
  end
  mesh:setVertices(verts)
  mesh:setDrawRange(1, #verts)
  lg.setColor(1, 1, 1, 1)
  lg.draw(mesh)
end

-- The unit normal at each point: the average of the segments either side.
local function normals(pts)
  local nx, ny = {}, {}
  for i = 1, #pts do
    local a, b = pts[max(1, i - 1)], pts[min(#pts, i + 1)]
    local dx, dy = b.x - a.x, b.y - a.y
    local l = sqrt(dx * dx + dy * dy)
    if l < 1e-9 then nx[i], ny[i] = nx[i - 1] or 0, ny[i - 1] or 1
    else nx[i], ny[i] = -dy / l, dx / l end
  end
  return nx, ny
end

-- Metres across a road, as pixels: never thinner than a hairline far out.
local function scaleFor(cam, h) return max(cam.scale, 1.6 / max(1, h)) end

-- A band between two offsets from the centre line, coloured per point.
local function band(cam, pts, nx, ny, inner, outer, colour, alpha, dx, dy)
  local verts = {}
  dx, dy = dx or 0, dy or 0
  for i, p in ipairs(pts) do
    local k = scaleFor(cam, p.h)
    local sx, sy = cam:toScreen(p.x, p.y)
    local c = colour(p, i)
    local a = (alpha or 1) * (c[4] or 1)
    local o1, o2 = inner(p) * k, outer(p) * k
    verts[#verts + 1] = { sx + nx[i] * o1 + dx, sy + ny[i] * o1 + dy, c[1], c[2], c[3], a }
    verts[#verts + 1] = { sx + nx[i] * o2 + dx, sy + ny[i] * o2 + dy, c[1], c[2], c[3], a }
  end
  strip(verts)
end

local function kindOf(p) return p.k or "road" end
local function surfaceOf(p) return SURFACE[kindOf(p)] or SURFACE.road end
local function vergeOf(p) return VERGE[kindOf(p)] or VERGE.road end
local function outerOf(p) return p.h + RS.pave(kindOf(p)) end

-- A line along the road at `frac` of its half width (+ metres `add`), solid
-- or dashed, only along the stretches of the kind asked for. Dashes are
-- counted in metres from the chain's start, so they do not crawl as the
-- camera moves.
-- Markings fade out as the camera pulls back: a line can get no thinner
-- than a pixel, so far out they would only stripe the road white.
local markFade = 1
local function line(cam, pts, nx, ny, kind, frac, add, width, colour, on, off, s0)
  if markFade <= 0 then return end
  lg.setColor(colour[1], colour[2], colour[3], (colour[4] or 1) * markFade)
  lg.setLineWidth(max(1, width * cam.scale))
  local s = s0 or 0
  for i = 2, #pts do
    local a, b = pts[i - 1], pts[i]
    local seg = sqrt((b.x - a.x) ^ 2 + (b.y - a.y) ^ 2)
    if kindOf(b) == kind and seg > 0 then
      local ka, kb = scaleFor(cam, a.h), scaleFor(cam, b.h)
      local ax, ay = cam:toScreen(a.x, a.y)
      local bx, by = cam:toScreen(b.x, b.y)
      local oa, ob = (a.h * frac + add) * ka, (b.h * frac + add) * kb
      ax, ay = ax + nx[i - 1] * oa, ay + ny[i - 1] * oa
      bx, by = bx + nx[i] * ob, by + ny[i] * ob
      if not on then
        lg.line(ax, ay, bx, by)
      else
        local period = on + off
        local d = 0
        while d < seg do
          local phase = (s + d) % period
          if phase < on then
            local e = min(seg, d + on - phase)
            lg.line(ax + (bx - ax) * d / seg, ay + (by - ay) * d / seg, ax + (bx - ax) * e / seg, ay + (by - ay) * e / seg)
            d = e
          else
            d = d + period - phase
          end
        end
      end
    end
    s = s + seg
  end
end

local function markings(cam, pts, nx, ny, s0)
  if cam.scale < 0.18 then return end
  -- A normal road: one broken white line down the middle.
  line(cam, pts, nx, ny, "road", 0, 0, 0.7, { 0.92, 0.92, 0.88, 0.75 }, 5, 7, s0)
  -- A highway: a central reserve with its barrier, two lanes each way with a
  -- broken line between them, and a solid edge line by the shoulder.
  line(cam, pts, nx, ny, "highway", 0, 0, 2.4, { 0.40, 0.42, 0.38, 1 }, nil, nil, s0)
  line(cam, pts, nx, ny, "highway", 0, 0, 0.5, { 0.75, 0.76, 0.74, 0.9 }, nil, nil, s0)
  for _, side in ipairs({ -1, 1 }) do
    line(cam, pts, nx, ny, "highway", 0, side * 1.6, 0.45, { 0.95, 0.85, 0.40, 0.85 }, nil, nil, s0)
    line(cam, pts, nx, ny, "highway", side * 0.55, side * 0.7, 0.6, { 0.92, 0.92, 0.88, 0.75 }, 6, 9, s0)
    line(cam, pts, nx, ny, "highway", side * 1, -side * 0.9, 0.5, { 0.92, 0.92, 0.88, 0.8 }, nil, nil, s0)
  end
  -- A track: two wheel ruts.
  if cam.scale > 0.35 then
    for _, side in ipairs({ -1, 1 }) do
      line(cam, pts, nx, ny, "offroad", side * 0.45, 0, 1.4, { 0.36, 0.28, 0.19, 1 }, nil, nil, s0)
    end
  end
end

-- Distances along a chain at each point, and the stretches over water.
local function along(ch)
  if ch.cum then return ch.cum end
  local cum, s = { 0 }, 0
  for i = 2, #ch.pts do
    s = s + sqrt((ch.pts[i].x - ch.pts[i - 1].x) ^ 2 + (ch.pts[i].y - ch.pts[i - 1].y) ^ 2)
    cum[i] = s
  end
  ch.cum = cum
  return cum
end
local function wetRuns(city, ch)
  if ch.wet then return ch.wet end
  local runs, open = {}, nil
  local step = 6
  for s = 0, ch.len, step do
    local x, y = RS.at(ch.pts, s)
    local w = city:isWater(x, y)
    if w and not open then open = s end
    if not w and open then runs[#runs + 1] = { max(0, open - 10), min(ch.len, s + 10) }; open = nil end
  end
  if open then runs[#runs + 1] = { max(0, open - 10), ch.len } end
  ch.wet = runs
  return runs
end

-- A deck under a stretch of road: shadow on what is below, the deck, piers.
-- The deck's ends rest on the ground, so its shadow stops short of them;
-- run to the end, the offset shadow would lie on the road beyond as a dark
-- seam across it.
local function polyLength(pts)
  local s = 0
  for i = 2, #pts do s = s + sqrt((pts[i].x - pts[i - 1].x) ^ 2 + (pts[i].y - pts[i - 1].y) ^ 2) end
  return s
end
local function deck(cam, pts, raise)
  local nx, ny = normals(pts)
  local grey = function() return DECK end
  local shadow = function() return { 0, 0, 0, 0.35 } end
  local w = function(p) return outerOf(p) + 2.5 end
  local len = polyLength(pts)
  local inset = min(10, len * 0.2)
  local sub = RS.slice(pts, inset, len - inset)
  local sx, sy = normals(sub)
  band(cam, sub, sx, sy, function(p) return -w(p) end, w, shadow, 1, 3 * raise, 6 * raise)
  band(cam, pts, nx, ny, function(p) return -w(p) end, w, grey)
  return nx, ny
end
local function parapets(cam, pts, nx, ny)
  for _, side in ipairs({ -1, 1 }) do
    lg.setColor(0.74, 0.74, 0.72); lg.setLineWidth(max(1, 1.4 * cam.scale))
    local line_ = {}
    for i, p in ipairs(pts) do
      local k = scaleFor(cam, p.h)
      local sx, sy = cam:toScreen(p.x, p.y)
      local o = side * (outerOf(p) + 1.8) * k
      line_[#line_ + 1] = sx + nx[i] * o; line_[#line_ + 1] = sy + ny[i] * o
    end
    if #line_ >= 4 then lg.line(line_) end
  end
end

local function seen(cam, b) return cam:seesBox(b[1], b[2], b[3], b[4], 40) end

-- A junction pad in screen space, cut into triangles once.
local function padTriangles(poly)
  local ok, tris = pcall(love.math.triangulate, poly)
  if ok and #tris > 0 then return tris end
  -- A kerb outline that folds over itself: a fan from its middle instead.
  local cx, cy, n = 0, 0, #poly / 2
  for i = 1, #poly, 2 do cx, cy = cx + poly[i], cy + poly[i + 1] end
  cx, cy = cx / n, cy / n
  tris = {}
  for i = 1, #poly, 2 do
    local j = i + 2 > #poly and 1 or i + 2
    tris[#tris + 1] = { cx, cy, poly[i], poly[i + 1], poly[j], poly[j + 1] }
  end
  return tris
end
local function drawPad(cam, pad, which, colour)
  pad.tris = pad.tris or {}
  if not pad.tris[which] then pad.tris[which] = padTriangles(pad[which]) end
  lg.setColor(colour)
  for _, t in ipairs(pad.tris[which]) do
    local ax, ay = cam:toScreen(t[1], t[2])
    local bx, by = cam:toScreen(t[3], t[4])
    local cx, cy = cam:toScreen(t[5], t[6])
    lg.polygon("fill", ax, ay, bx, by, cx, cy)
  end
end

-- The widest arm sets what a junction is paved with.
local function padKind(pad)
  local best, kind = -1, "road"
  for _, e in ipairs(pad.arms) do if e.h > best then best, kind = e.h, e.kind end end
  return kind
end

local function padMarkings(cam, pad)
  if cam.scale < 0.3 then return end
  local fade = markFade
  for _, e in ipairs(pad.arms) do
    if e.kind == "road" or e.kind == "highway" then
      local nx, ny = -e.dy, e.dx
      -- Traffic keeps right, so the lane coming in is on the -normal side.
      local x0, y0 = e.x + e.dx * 1.5, e.y + e.dy * 1.5
      local ax, ay = cam:toScreen(x0, y0)
      local bx, by = cam:toScreen(x0 - nx * e.h * 0.95, y0 - ny * e.h * 0.95)
      lg.setColor(0.94, 0.94, 0.90, 0.85 * fade); lg.setLineWidth(max(1, 1.1 * cam.scale)); lg.line(ax, ay, bx, by)
      if e.kind == "road" and cam.scale > 0.5 then
        -- A zebra crossing just back from the stop line.
        lg.setColor(0.94, 0.94, 0.90, 0.7 * fade)
        lg.setLineWidth(max(1, 1.6 * cam.scale))
        for k = -e.h + 1.5, e.h - 1.5, 2.6 do
          local px, py = e.x + e.dx * 4 + nx * k, e.y + e.dy * 4 + ny * k
          local qx, qy = e.x + e.dx * 8.5 + nx * k, e.y + e.dy * 8.5 + ny * k
          local sx, sy = cam:toScreen(px, py)
          local tx, ty = cam:toScreen(qx, qy)
          lg.line(sx, sy, tx, ty)
        end
      end
    end
  end
end

-- Road signs, a few metres tall, on a post with a shadow.
local function sign(cam, sg)
  local sx, sy = cam:toScreen(sg.x, sg.y)
  local u = max(0.6, R.sym(1.1, cam.scale))
  lg.setColor(0, 0, 0, 0.3); lg.setLineWidth(max(1, 0.5 * u)); lg.line(sx, sy, sx + 2.5 * u, sy + 1.5 * u)
  lg.setColor(0.55, 0.56, 0.58); lg.line(sx, sy, sx, sy - 3.4 * u)
  local cy = sy - 4.6 * u
  if sg.kind == "giveway" then
    lg.setColor(0.86, 0.18, 0.16); lg.polygon("fill", sx - 2 * u, cy - 1.4 * u, sx + 2 * u, cy - 1.4 * u, sx, cy + 2 * u)
    lg.setColor(0.96, 0.96, 0.94); lg.polygon("fill", sx - 1.1 * u, cy - 0.85 * u, sx + 1.1 * u, cy - 0.85 * u, sx, cy + 1.05 * u)
  elseif sg.kind == "speed" then
    lg.setColor(0.86, 0.18, 0.16); lg.circle("fill", sx, cy, 1.7 * u)
    lg.setColor(0.96, 0.96, 0.94); lg.circle("fill", sx, cy, 1.15 * u)
    lg.setColor(0.12, 0.12, 0.12); lg.rectangle("fill", sx - 0.55 * u, cy - 0.5 * u, 0.35 * u, 1 * u); lg.rectangle("fill", sx + 0.15 * u, cy - 0.5 * u, 0.35 * u, 1 * u)
  elseif sg.kind == "motorway" then
    lg.setColor(0.16, 0.34, 0.70); lg.rectangle("fill", sx - 2 * u, cy - 1.8 * u, 4 * u, 3.4 * u, 0.4 * u)
    lg.setColor(0.96, 0.96, 0.94); lg.setLineWidth(max(1, 0.35 * u))
    lg.line(sx - 0.9 * u, cy + 1.2 * u, sx - 0.3 * u, cy - 1.2 * u); lg.line(sx + 0.9 * u, cy + 1.2 * u, sx + 0.3 * u, cy - 1.2 * u)
  else
    -- An exit board on two legs: green, with an arrow peeling off.
    lg.setColor(0.55, 0.56, 0.58); lg.setLineWidth(max(1, 0.5 * u)); lg.line(sx - 2.6 * u, sy, sx - 2.6 * u, cy)
    lg.setColor(0.10, 0.45, 0.28); lg.rectangle("fill", sx - 3.6 * u, cy - 1.8 * u, 7.2 * u, 3.4 * u, 0.4 * u)
    lg.setColor(0.96, 0.96, 0.94); lg.setLineWidth(max(1, 0.4 * u))
    lg.line(sx - 2 * u, cy + 1 * u, sx - 2 * u, cy - 0.6 * u); lg.line(sx - 2 * u, cy - 0.6 * u, sx - 0.6 * u, cy - 1.2 * u)
    lg.rectangle("fill", sx + 0.2 * u, cy - 0.9 * u, 2.6 * u, 0.4 * u); lg.rectangle("fill", sx + 0.2 * u, cy + 0.1 * u, 2 * u, 0.4 * u)
  end
end

-- A road that stops at a bend node with nothing beyond it ends in a rounded
-- turning head rather than a cut edge.
local function deadEnds(city, shape, ch)
  local out = {}
  for _, which in ipairs({ "a", "b" }) do
    local id = ch[which]
    local n = city.g.nodes[id]
    if n and City.ROAD_JUNCTIONS[n.kind] and shape.role[id] == "end" and #ch.pts >= 2 then
      local p = which == "a" and ch.pts[1] or ch.pts[#ch.pts]
      local q = which == "a" and ch.pts[2] or ch.pts[#ch.pts - 1]
      out[#out + 1] = { p = p, q = q }
    end
  end
  return out
end
-- A highway is never rounded off like a cul-de-sac: it stops square at a
-- crash barrier, red and white, across both carriageways and the shoulders.
local function cap(cam, e, r, colour)
  local p = e.p
  if kindOf(p) == "highway" then return end
  local sx, sy = cam:toScreen(p.x, p.y)
  lg.setColor(colour)
  lg.circle("fill", sx, sy, r * scaleFor(cam, p.h))
end

local function barrier(cam, e)
  local p, q = e.p, e.q
  if kindOf(p) ~= "highway" then return end
  local dx, dy = p.x - q.x, p.y - q.y
  local l = sqrt(dx * dx + dy * dy)
  if l < 1e-6 then return end
  dx, dy = dx / l, dy / l
  local w = outerOf(p)
  local bx, by = p.x - dx * 1.5, p.y - dy * 1.5
  local n, s = 8, cam.scale
  lg.setLineWidth(max(1.5, 1.6 * s))
  for i = 0, n - 1 do
    local a, b = -w + 2 * w * i / n, -w + 2 * w * (i + 1) / n
    local x0, y0 = cam:toScreen(bx - dy * a, by + dx * a)
    local x1, y1 = cam:toScreen(bx - dy * b, by + dx * b)
    if i % 2 == 0 then lg.setColor(0.86, 0.22, 0.20) else lg.setColor(0.95, 0.95, 0.92) end
    lg.line(x0, y0, x1, y1)
  end
end

local function disc(cam, x, y, r, colour)
  local sx, sy = cam:toScreen(x, y)
  lg.setColor(colour)
  lg.circle("fill", sx, sy, max(1, r * cam.scale), 40)
end
-- The middle of a roundabout: a kerbed grass island. At each way in, the
-- give-way line across the lanes coming in, a double row of short dashes on
-- the ring's edge, and a give-way triangle painted on the lane before it.
local function giveWay(cam, rd, e)
  local s = cam.scale
  local cx, cy = -e.dy, e.dx
  local function at(out, across) return cam:toScreen(rd.x + e.dx * out + cx * across, rd.y + e.dy * out + cy * across) end
  lg.setColor(0.94, 0.94, 0.90, 0.85 * markFade)
  local dash, gap = 1.1, 0.8
  local w = math.max(1, 0.55 * s)
  for _, out in ipairs({ rd.r + 0.7, rd.r + 2.0 }) do
    local u = e.a + 0.3
    while u < e.b - 0.3 do
      local u1 = math.min(e.b - 0.3, u + dash)
      local x0, y0 = at(out, u); local x1, y1 = at(out, u1)
      lg.setLineWidth(w); lg.line(x0, y0, x1, y1)
      u = u1 + gap
    end
  end
  if s > 0.9 then
    -- The triangle points at the ring, in the middle of the way in.
    local mid, out = (e.a + e.b) / 2, rd.r + 6
    local half = math.min(1.8, (e.b - e.a) * 0.3)
    local ax, ay = at(out - 1.6, mid)
    local bx, by = at(out + 2.8, mid - half)
    local qx, qy = at(out + 2.8, mid + half)
    lg.setLineWidth(math.max(0.8, 0.45 * s))
    lg.polygon("line", ax, ay, bx, by, qx, qy)
  end
end
local function island(cam, rd)
  local sx, sy = cam:toScreen(rd.x, rd.y)
  local s = cam.scale
  local ri = RS.ISLAND * s
  if markFade > 0 then
    for _, e in ipairs(rd.entries or {}) do giveWay(cam, rd, e) end
  end
  lg.setColor(VERGE.road); lg.circle("fill", sx, sy, ri + 1.2 * s, 32)
  lg.setColor(0.26, 0.40, 0.24); lg.circle("fill", sx, sy, ri, 32)
  lg.setColor(0.32, 0.50, 0.28); lg.circle("fill", sx - ri * 0.2, sy - ri * 0.2, ri * 0.45, 16)
end

function Roads.draw(city, cam)
  local shape = RS.get(city)
  markFade = math.max(0, math.min(1, (cam.scale - 0.2) / 0.45))
  local visible = {}
  for _, ch in ipairs(shape.chains) do
    if #ch.pts >= 2 and seen(cam, ch.box) then
      visible[#visible + 1] = ch
    end
  end
  local pads = {}
  for _, pad in ipairs(shape.pads) do
    if cam:sees(pad.x, pad.y, (pad.r + 40) * cam.scale) then pads[#pads + 1] = pad end
  end
  local function nrm(ch)
    if not ch.nx then ch.nx, ch.ny = normals(ch.pts) end
    return ch.nx, ch.ny
  end
  -- Decks over water first: they stand in the river, under the road.
  for _, ch in ipairs(visible) do
    for _, run in ipairs(wetRuns(city, ch)) do
      local sub = RS.slice(ch.pts, run[1], run[2])
      local nx, ny = deck(cam, sub, 1)
      -- Piers down into the water.
      lg.setColor(0, 0, 0, 0.4)
      local step = 45
      for s = run[1] + step / 2, run[2] - step / 4, step do
        local x, y, ux, uy, h = RS.at(ch.pts, s)
        local w = h + RS.pave("road") + 2
        for _, side in ipairs({ -1, 1 }) do
          local px, py = cam:toScreen(x - uy * w * side, y + ux * w * side)
          local r = max(1.5, 2 * cam.scale)
          lg.rectangle("fill", px - r + 3, py - r + 5, r * 2, r * 2)
        end
      end
    end
  end
  -- Verges and pavements, then the carriageway, every street at once.
  -- Slip roads' verges go down with the rest; their surface goes over the
  -- highway's shoulder, so the lane joins the carriageway with no seam.
  local ramps, overs = {}, {}
  for _, ramp in ipairs(shape.ramps) do
    local p = ramp.pts[1]
    if cam:sees(p.x, p.y, 400 * cam.scale + 60) then
      if not ramp.ny then ramp.nx, ramp.ny = normals(ramp.pts) end
      if ramp.over then overs[#overs + 1] = ramp else ramps[#ramps + 1] = ramp end
    end
  end
  for _, ramp in ipairs(ramps) do
    band(cam, ramp.pts, ramp.nx, ramp.ny, function(q) return -q.h - 2 end, function(q) return q.h + 2 end, function() return VERGE.ramp end)
  end
  local rounds = {}
  for _, rd in ipairs(shape.rounds) do
    if cam:sees(rd.x, rd.y, (rd.r + 20) * cam.scale) then rounds[#rounds + 1] = rd end
  end
  for _, pad in ipairs(pads) do drawPad(cam, pad, "kerb", VERGE[padKind(pad)] or VERGE.road) end
  for _, rd in ipairs(rounds) do disc(cam, rd.x, rd.y, rd.r + RS.pave("road"), VERGE.road) end
  for _, ch in ipairs(visible) do
    local nx, ny = nrm(ch)
    band(cam, ch.pts, nx, ny, function(p) return -outerOf(p) end, outerOf, vergeOf)
    for _, e in ipairs(deadEnds(city, shape, ch)) do cap(cam, e, outerOf(e.p), vergeOf(e.p)) end
  end
  for _, pad in ipairs(pads) do drawPad(cam, pad, "road", SURFACE[padKind(pad)] or SURFACE.road) end
  for _, ch in ipairs(visible) do
    local nx, ny = nrm(ch)
    band(cam, ch.pts, nx, ny, function(p) return -p.h end, function(p) return p.h end, surfaceOf)
    for _, e in ipairs(deadEnds(city, shape, ch)) do cap(cam, e, e.p.h, surfaceOf(e.p)) end
    -- A kerb line where a pavement meets the road.
    if cam.scale > 0.45 then
      for _, side in ipairs({ -1, 1 }) do line(cam, ch.pts, nx, ny, "road", side, 0, 0.5, { 0.66, 0.66, 0.64, 0.8 }) end
    end
  end
  for _, ramp in ipairs(ramps) do
    band(cam, ramp.pts, ramp.nx, ramp.ny, function(q) return -q.h end, function(q) return q.h end, function() return SURFACE.ramp end)
  end
  for _, ch in ipairs(visible) do
    local nx, ny = nrm(ch)
    markings(cam, ch.pts, nx, ny, 0)
    for _, e in ipairs(deadEnds(city, shape, ch)) do barrier(cam, e) end
  end
  if cam.scale > 0.3 then
    for _, ramp in ipairs(ramps) do
      -- Solid edge lines, the inner one broken where the lane merges.
      line(cam, ramp.pts, ramp.nx, ramp.ny, "ramp", 1, -0.7, 0.45, { 0.92, 0.92, 0.88, 0.75 })
      line(cam, ramp.pts, ramp.nx, ramp.ny, "ramp", -1, 0.7, 0.45, { 0.92, 0.92, 0.88, 0.75 }, 4, 4)
    end
  end
  -- A roundabout's ring over the mouths of the slip roads and over the
  -- markings of a road that runs through it.
  for _, rd in ipairs(rounds) do disc(cam, rd.x, rd.y, rd.r, SURFACE.road); island(cam, rd) end
  for _, pad in ipairs(pads) do padMarkings(cam, pad) end
  for _, ch in ipairs(visible) do
    for _, run in ipairs(wetRuns(city, ch)) do
      local sub = RS.slice(ch.pts, run[1], run[2])
      local nx, ny = normals(sub)
      parapets(cam, sub, nx, ny)
    end
  end
  -- One road over another.
  for _, f in ipairs(shape.flyovers) do
    if cam:sees(f.x, f.y, 120 * cam.scale + 40) then
      local sub = RS.slice(f.chain.pts, f.s0, f.s1)
      local nx, ny = deck(cam, sub, 1.4)
      band(cam, sub, nx, ny, function(p) return -outerOf(p) end, outerOf, vergeOf)
      band(cam, sub, nx, ny, function(p) return -p.h end, function(p) return p.h end, surfaceOf)
      markings(cam, sub, nx, ny, f.s0)
      parapets(cam, sub, nx, ny)
    end
  end
  -- A motorway junction's flyover, over the main line: two lanes, one each
  -- way, on a deck with its shadow on the carriageways below.
  for _, ramp in ipairs(overs) do
    local pts = ramp.pts
    local nx, ny = deck(cam, pts, 1.4)
    band(cam, pts, nx, ny, function(q) return -q.h end, function(q) return q.h end, function() return SURFACE.ramp end)
    if cam.scale > 0.3 then
      line(cam, pts, nx, ny, "ramp", 1, -0.7, 0.45, { 0.92, 0.92, 0.88, 0.75 })
      line(cam, pts, nx, ny, "ramp", -1, 0.7, 0.45, { 0.92, 0.92, 0.88, 0.75 })
      line(cam, pts, nx, ny, "ramp", 0, 0, 0.45, { 0.92, 0.80, 0.30, 0.8 })
    end
    parapets(cam, pts, nx, ny)
  end
  if cam.scale > 0.5 then
    for _, sg in ipairs(shape.signs) do
      if cam:sees(sg.x, sg.y, 20) then sign(cam, sg) end
    end
  end
end

-- The road a dragged-out plan would lay, as a translucent band, and where it
-- would put its ends and junctions.
function Roads.ghost(city, cam, plan, ok)
  local kind = plan.variant == "highway" and "highway" or plan.variant == "offroad" and "offroad" or "road"
  local h = RS.half(kind)
  local k = scaleFor(cam, h)
  local ax, ay = cam:toScreen(plan.ax, plan.ay)
  local bx, by = cam:toScreen(plan.bx, plan.by)
  local col = ok and { 0.95, 0.88, 0.55 } or { 0.92, 0.36, 0.30 }
  lg.setColor(col[1], col[2], col[3], 0.28); lg.setLineWidth((h + RS.pave(kind)) * 2 * k); lg.line(ax, ay, bx, by)
  lg.setColor(col[1], col[2], col[3], 0.55); lg.setLineWidth(h * 2 * k); lg.line(ax, ay, bx, by)
  lg.setColor(col[1], col[2], col[3], 0.9); lg.setLineWidth(1.5)
  for _, s in ipairs(plan.stops or {}) do
    local sx, sy = cam:toScreen(s.ref.x, s.ref.y)
    lg.circle("line", sx, sy, max(4, h * k * 0.8))
  end
  -- The price, or why not, beside the far end.
  local text = plan.err or ("$" .. plan.cost)
  local font = R.fonts.small
  lg.setFont(font)
  local tw, th = font:getWidth(text), font:getHeight()
  local tx, ty = bx + 14, by - th - 10
  -- Kept on screen, flipping to the left of the pointer near the right edge.
  if tx + tw + 8 > cam.vx + cam.vw then tx = bx - 14 - tw end
  ty = math.max(cam.vy + 6, ty)
  lg.setColor(0.08, 0.09, 0.10, 0.85); lg.rectangle("fill", tx - 6, ty - 3, tw + 12, th + 6, 4)
  lg.setColor(col[1], col[2], col[3], 1); lg.print(text, tx, ty)
end

-- A selected or hovered road: both kerbs traced in a bright line, with a
-- soft wash over the carriageway, along its own curves.
function Roads.highlight(city, cam, l, colour, strong)
  local pieces = RS.get(city).pieces[l.id]
  if not pieces then return end
  for _, pts in ipairs(pieces) do
    if #pts >= 2 then
      local nx, ny = normals(pts)
      band(cam, pts, nx, ny, function(p) return -outerOf(p) end, outerOf, function() return { colour[1], colour[2], colour[3], strong and 0.22 or 0.14 } end)
      for _, side in ipairs({ -1, 1 }) do
        local poly = {}
        for i, p in ipairs(pts) do
          local sx, sy = cam:toScreen(p.x, p.y)
          local o = side * (outerOf(p) + 1) * scaleFor(cam, p.h)
          poly[#poly + 1] = sx + nx[i] * o; poly[#poly + 1] = sy + ny[i] * o
        end
        lg.setColor(colour[1], colour[2], colour[3], strong and 0.95 or 0.6)
        lg.setLineWidth(strong and 2.5 or 1.5)
        lg.line(poly)
      end
    end
  end
end

return Roads
