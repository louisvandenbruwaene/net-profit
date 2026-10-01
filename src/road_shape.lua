-- road_shape.lua -- where every road actually lies, worked out once per change.
--
-- A road is laid between two places, but it is not drawn as a straight bar
-- from one to the other. Roads joined end to end through a bend are one
-- street that curves round it; where three or more meet there is a junction
-- whose kerbs sweep from one arm into the next; a highway runs straight
-- through an interchange while the road it serves crosses over it on a
-- bridge and slip roads bend off to meet it; and where two roads cross with
-- no junction between them, one goes over the other.
--
-- Everything here is plain Lua and depends only on the city, so the map, the
-- traffic on it, the people on its pavements and the mouse all ask the same
-- question and get the same answer:
--   chains   streets as smoothed polylines, each point with its own half
--            width, kind and link, so a highway narrowing into a road tapers
--   pads     at-grade junctions: the kerb outline, and each arm's stop line
--   ramps    an interchange's slip roads, as curves
--   rounds   the roundabout a road ends in where it stops at a highway
--   flyovers a crossing with no junction: which street goes over, and where
--   signs    give-way, speed limit and exit signs, never on a building
--   pieces   link id -> the polylines that are that link, for hit tests
local City = require("city")

local RoadShape = {}
local cache = setmetatable({}, { __mode = "k" })

-- What a road looks like: a bridge is drawn as the road it carries.
function RoadShape.visual(l)
  if l.deck then return l.deck end
  local kind = l.roadType or "road"
  return kind == "bridge" and "road" or kind
end
function RoadShape.half(kind) return (City.ROAD_WIDTH[kind] or 16) / 2 end
-- The pavement a normal road has, the verge a track or a highway has.
function RoadShape.pave(kind)
  if kind == "road" then return City.PAVEMENT end
  if kind == "highway" then return 2.5 end
  return 1.5
end
local RANK = { offroad = 1, road = 2, highway = 3 }
-- A roundabout's carriageway radius, and its middle island's.
local ROUND, ISLAND = 15, 6.5
RoadShape.ROUND, RoadShape.ISLAND = ROUND, ISLAND

local sqrt, atan2, abs, min, max, floor = math.sqrt, math.atan2, math.abs, math.min, math.max, math.floor
local function norm(x, y)
  local l = sqrt(x * x + y * y)
  if l < 1e-9 then return 0, 0, 0 end
  return x / l, y / l, l
end

-- How far a building's road stops short of its middle: at its front step.
local function bodyOf(n)
  if City.ROAD_JUNCTIONS[n.kind] then return 0 end
  local body = City.footprint(n.kind)
  if n.kind == "client" and City.PROJECT_BY and City.PROJECT_BY[n.clientType or ""] then body = body * 1.5 end
  return body * 0.55
end

--------------------------------------------------------------------------------
-- Polylines
--------------------------------------------------------------------------------

-- Points are tables {x, y, h (half width), k (kind), l (link)}.
local function lengthOf(pts)
  local s = 0
  for i = 2, #pts do s = s + sqrt((pts[i].x - pts[i - 1].x) ^ 2 + (pts[i].y - pts[i - 1].y) ^ 2) end
  return s
end

-- Drop `d` metres off the start of a polyline, keeping the cut point.
local function trimStart(pts, d)
  if d <= 0 then return pts end
  local out = {}
  local i = 2
  while i <= #pts do
    local a, b = pts[i - 1], pts[i]
    local seg = sqrt((b.x - a.x) ^ 2 + (b.y - a.y) ^ 2)
    if seg >= d then
      local f = seg > 0 and d / seg or 0
      out[1] = { x = a.x + (b.x - a.x) * f, y = a.y + (b.y - a.y) * f, h = a.h + (b.h - a.h) * f, k = b.k, l = b.l }
      for j = i, #pts do out[#out + 1] = pts[j] end
      return out
    end
    d = d - seg
    i = i + 1
  end
  -- Shorter than the cut: keep a stub at the far end.
  local last = pts[#pts]
  return { { x = last.x, y = last.y, h = last.h, k = last.k, l = last.l }, last }
end

local function reversed(pts)
  local out = {}
  for i = #pts, 1, -1 do out[#out + 1] = pts[i] end
  return out
end

local function trimEnd(pts, d) return reversed(trimStart(reversed(pts), d)) end

-- A point `s` metres along, with its heading and half width.
function RoadShape.at(pts, s)
  for i = 2, #pts do
    local a, b = pts[i - 1], pts[i]
    local dx, dy = b.x - a.x, b.y - a.y
    local seg = sqrt(dx * dx + dy * dy)
    if s <= seg or i == #pts then
      local f = seg > 0 and max(0, min(1, s / seg)) or 0
      return a.x + dx * f, a.y + dy * f, dx / max(seg, 1e-6), dy / max(seg, 1e-6), a.h + (b.h - a.h) * f, b.k
    end
    s = s - seg
  end
  local p = pts[1]
  return p.x, p.y, 1, 0, p.h, p.k
end

-- The stretch of a polyline between two distances along it.
function RoadShape.slice(pts, s0, s1)
  local out = {}
  local x, y, _, _, h, k = RoadShape.at(pts, s0)
  out[1] = { x = x, y = y, h = h, k = k }
  local s = 0
  for i = 2, #pts do
    local seg = sqrt((pts[i].x - pts[i - 1].x) ^ 2 + (pts[i].y - pts[i - 1].y) ^ 2)
    s = s + seg
    if s > s0 and s < s1 then out[#out + 1] = pts[i] end
  end
  x, y, _, _, h, k = RoadShape.at(pts, s1)
  out[#out + 1] = { x = x, y = y, h = h, k = k }
  return out
end

-- Round every corner of a polyline. A vertex is replaced by a curve that
-- leaves the straight a tangent length before it and rejoins one after; the
-- half width eases from the one road to the other over the same curve, so a
-- highway that turns into a normal road tapers rather than stepping.
local function smooth(raw)
  if #raw <= 2 then return raw end
  local out = { raw[1] }
  for i = 2, #raw - 1 do
    local p, v, q = raw[i - 1], raw[i], raw[i + 1]
    local ux, uy, l1 = norm(v.x - p.x, v.y - p.y)
    local wx, wy, l2 = norm(q.x - v.x, q.y - v.y)
    local cosT = max(-1, min(1, ux * wx + uy * wy))
    local turn = math.acos(cosT)
    local hin, hout = v.hin or p.h, v.hout or q.h
    local hmax = max(hin, hout)
    -- A gentle bend for a wide road, never more than the straights allow.
    local radius = max(hmax * 4, 45)
    local t = turn > 0.02 and radius * math.tan(turn / 2) or 0
    if hin ~= hout then t = max(t, 30) end
    t = min(t, l1 * 0.48, l2 * 0.48)
    if t < 1 then
      out[#out + 1] = v
    else
      local sx, sy = v.x - ux * t, v.y - uy * t
      local ex, ey = v.x + wx * t, v.y + wy * t
      local steps = max(3, math.ceil(turn / 0.12))
      for j = 0, steps do
        local f = j / steps
        local a, b, c = (1 - f) ^ 2, 2 * (1 - f) * f, f * f
        local e = f * f * (3 - 2 * f)
        out[#out + 1] = { x = a * sx + b * v.x + c * ex, y = a * sy + b * v.y + c * ey,
          h = hin + (hout - hin) * e, k = f < 0.5 and v.k or q.k, l = f < 0.5 and v.l or q.l }
      end
    end
  end
  out[#out + 1] = raw[#raw]
  return out
end

-- Where two segments cross, as fractions along each, or nil.
local function crossing(ax, ay, bx, by, cx, cy, dx, dy)
  local rx, ry, sx, sy = bx - ax, by - ay, dx - cx, dy - cy
  local den = rx * sy - ry * sx
  if abs(den) < 1e-9 then return nil end
  local t = ((cx - ax) * sy - (cy - ay) * sx) / den
  local u = ((cx - ax) * ry - (cy - ay) * rx) / den
  if t > 0 and t < 1 and u > 0 and u < 1 then return t, u end
  return nil
end
RoadShape.crossing = crossing

--------------------------------------------------------------------------------
-- The network
--------------------------------------------------------------------------------

local function build(city)
  local shape = { chains = {}, pads = {}, ramps = {}, rounds = {}, flyovers = {}, signs = {}, pieces = {}, ends = {} }
  local nodes = city.g.nodes
  local roads, at = {}, {}
  for _, l in ipairs(city.links or {}) do
    local na, nb = nodes[l.a], nodes[l.b]
    if l.alive and l.mode == "road" and na and nb and na.alive and nb.alive and l.a ~= l.b then
      local kind = RoadShape.visual(l)
      local r = { l = l, kind = kind, h = RoadShape.half(kind) }
      roads[#roads + 1] = r
      at[l.a] = at[l.a] or {}; table.insert(at[l.a], r)
      at[l.b] = at[l.b] or {}; table.insert(at[l.b], r)
    end
  end
  shape.at = at
  local function other(r, id) return r.l.a == id and r.l.b or r.l.a end
  local function dirFrom(id, r)
    local n, m = nodes[id], nodes[other(r, id)]
    local x, y = norm(m.x - n.x, m.y - n.y)
    return x, y
  end

  -- What each node is to the roads at it.
  --   bend   a road node with two roads: the street curves through it
  --   pass   an interchange the highway runs straight through, and with two
  --          other roads, the road over it as well
  --   pad    any other meeting of three or more
  --   end    a dead end, or a building the road stops at
  local role, pairs_ = {}, {}
  for id, list in pairs(at) do
    local n = nodes[id]
    local junction = City.ROAD_JUNCTIONS[n.kind]
    if not junction or #list == 1 then
      role[id] = "end"
    elseif #list == 2 then
      role[id] = "bend"
      pairs_[id] = { [list[1]] = list[2], [list[2]] = list[1] }
    else
      local high, low = {}, {}
      for _, r in ipairs(list) do if r.kind == "highway" then high[#high + 1] = r else low[#low + 1] = r end end
      local straight = false
      if #high == 2 and #low >= 1 then
        local ax, ay = dirFrom(id, high[1]); local bx, by = dirFrom(id, high[2])
        straight = ax * bx + ay * by < -0.5
      end
      if straight then
        role[id] = "pass"
        local p = { [high[1]] = high[2], [high[2]] = high[1] }
        if #low == 2 then
          local ax, ay = dirFrom(id, low[1]); local bx, by = dirFrom(id, low[2])
          if ax * bx + ay * by < 0 then p[low[1]] = low[2]; p[low[2]] = low[1] end
        end
        pairs_[id] = p
      else
        role[id] = "pad"
      end
    end
  end
  shape.role = role

  -- How far back from a junction each arm stops, so arms that meet at a
  -- narrow angle still leave room for the kerb between them.
  local setback, rampBack, rounds = {}, {}, {}
  for id, list in pairs(at) do
    if role[id] == "pad" then
      local widest = 0
      for _, r in ipairs(list) do widest = max(widest, r.h + RoadShape.pave(r.kind)) end
      local d = widest * 1.25 + 6
      local dirs = {}
      for _, r in ipairs(list) do local x, y = dirFrom(id, r); dirs[#dirs + 1] = atan2(y, x) end
      table.sort(dirs)
      for i = 1, #dirs do
        local gap = (dirs[i % #dirs + 1] - dirs[i]) % (2 * math.pi)
        if gap > 0.05 then d = max(d, widest / math.tan(min(gap, math.pi * 0.9) / 2) + 4) end
      end
      setback[id] = d
    elseif role[id] == "pass" then
      -- A road meeting the highway at a slant has further to go to clear it.
      local hw, hx, hy, slant = 0, 0, 0, 1
      for _, r in ipairs(list) do if r.kind == "highway" then hw = max(hw, r.h); hx, hy = dirFrom(id, r) end end
      local d = hw + RoadShape.pave("highway") + 14
      for _, r in ipairs(list) do
        if r.kind ~= "highway" then
          local lx, ly = dirFrom(id, r)
          local sin = abs(lx * hy - ly * hx)
          slant = min(slant, max(0.35, sin))
          -- Far enough out that the slip roads have room to curve.
          local want = (hw + RoadShape.pave("highway") + 34) / max(0.35, sin)
          -- A short road cannot give the slip roads more room than it has.
          local m = nodes[other(r, id)]
          local length = sqrt((m.x - nodes[id].x) ^ 2 + (m.y - nodes[id].y) ^ 2)
          local least = (hw + RoadShape.pave("highway") + 12) / max(0.35, sin)
          d = max(d, max(least, min(want, length * 0.55)))
        end
      end
      -- The slip roads leave the road this far out; a road that stops here
      -- runs on a lane's width past them, so its end and the two slip roads
      -- close up into one T with no gap between.
      -- On a slant the road end's near corner reaches further than its
      -- middle, by the road's half width times the cosine.
      local clear = (hw + RoadShape.pave("highway") + 11 + 8 * sqrt(1 - slant * slant)) / slant
      setback[id] = max(clear, d - 13)
      rampBack[id] = max(d, setback[id] + 13)
      -- A road that stops at the highway ends in a roundabout set out from
      -- it, and the two slip roads leave the roundabout. Whatever the angle
      -- the road comes in at and however short it is, the slip roads get a
      -- long straight run at the highway instead of a hairpin off its kerb.
      for _, r in ipairs(list) do
        local through = pairs_[id] and pairs_[id][r]
        if r.kind ~= "highway" and through then
          -- A road over the highway gets a roundabout on each side of the
          -- bridge, on the road itself, as far out as the slip roads need
          -- and the road allows.
          local lx, ly = dirFrom(id, r)
          local sin = abs(lx * hy - ly * hx)
          local base = hw + RoadShape.pave("highway")
          local far = nodes[other(r, id)]
          local length = sqrt((far.x - nodes[id].x) ^ 2 + (far.y - nodes[id].y) ^ 2)
          local least = (base + 10 + ROUND) / max(0.2, sin)
          local d = min((base + 30 + ROUND) / max(0.2, sin), length - ROUND - 12 - bodyOf(far))
          if sin > 0.3 and d >= least then
            rounds[id] = rounds[id] or {}
            rounds[id][r] = { x = nodes[id].x + lx * d, y = nodes[id].y + ly * d, r = ROUND, through = true }
          end
        elseif r.kind ~= "highway" then
          local lx, ly = dirFrom(id, r)
          local mx, my = -hy, hx
          if mx * lx + my * ly < 0 then mx, my = -mx, -my end
          local base = hw + RoadShape.pave("highway")
          local far = nodes[other(r, id)]
          local fx, fy = far.x - nodes[id].x, far.y - nodes[id].y
          local fPerp, fAlong = fx * mx + fy * my, fx * hx + fy * hy
          local perp = max(base + 12 + ROUND, min(base + 34 + ROUND, fPerp - 6))
          local along = fAlong * min(1, perp / max(1, fPerp)) * 0.35
          rounds[id] = rounds[id] or {}
          rounds[id][r] = { x = nodes[id].x + mx * perp + hx * along, y = nodes[id].y + my * perp + hy * along, r = ROUND }
        end
      end
    end
  end

  -- Walk the streets. A chain runs from wherever a street starts, through
  -- every bend and every interchange it passes straight through, to wherever
  -- it stops.
  local function nextAt(id, r) return pairs_[id] and pairs_[id][r] end
  local seen = {}
  for _, r0 in ipairs(roads) do
    if not seen[r0] then
      local start, from, guard = r0, r0.l.a, 0
      while guard < 500 do
        local prev = nextAt(from, start)
        if not prev or prev == r0 then break end
        start = prev
        from = other(prev, from)
        guard = guard + 1
      end
      -- From `from`, along `start`, forward.
      local raw, links, cur, here = {}, {}, start, from
      local n0 = nodes[here]
      raw[1] = { x = n0.x, y = n0.y, h = start.h, k = start.kind, l = start.l }
      local passes = {}
      guard = 0
      while cur and not seen[cur] and guard < 500 do
        seen[cur] = true
        links[#links + 1] = cur
        here = other(cur, here)
        local n = nodes[here]
        local nxt = nextAt(here, cur)
        if nxt and seen[nxt] then nxt = nil end
        raw[#raw + 1] = { x = n.x, y = n.y, h = nxt and (cur.h + nxt.h) / 2 or cur.h, k = cur.kind, l = cur.l, node = here }
        if nxt and role[here] == "pass" then passes[#passes + 1] = { node = here, index = #raw } end
        cur = nxt
        guard = guard + 1
      end
      -- Width per vertex: each straight keeps its own road's width up to the
      -- bend, and the bend eases between them.
      for i = 2, #raw do
        raw[i].h, raw[i].hin, raw[i].hout = links[i - 1].h, links[i - 1].h, (links[i] or links[i - 1]).h
        raw[i].k, raw[i].l = links[i - 1].kind, links[i - 1].l
      end
      local first, last = raw[1].node or from, raw[#raw].node
      -- A road ending at a roundabout runs to its middle, under the ring.
      local roundA = rounds[first] and rounds[first][links[1]]
      local roundB = rounds[last] and rounds[last][links[#links]]
      if roundA and roundA.through then roundA = nil end
      if roundB and roundB.through then roundB = nil end
      if roundA then raw[1].x, raw[1].y = roundA.x, roundA.y end
      if roundB then raw[#raw].x, raw[#raw].y = roundB.x, roundB.y end
      local pts = smooth(raw)
      local trimA = (roundA and ROUND - 2) or setback[first] or (role[first] == "end" and bodyOf(nodes[first])) or 0
      local trimB = (roundB and ROUND - 2) or setback[last] or (role[last] == "end" and bodyOf(nodes[last])) or 0
      local total = lengthOf(pts)
      if trimA + trimB > total - 2 then
        local k = max(0, total - 2) / max(1e-6, trimA + trimB)
        trimA, trimB = trimA * k, trimB * k
      end
      pts = trimEnd(trimStart(pts, trimA), trimB)
      local ch = { pts = pts, links = links, a = first, b = last, kind = links[1].kind, h = links[1].h,
        id = links[1].l.id, len = lengthOf(pts) }
      local x0, y0, x1, y1 = math.huge, math.huge, -math.huge, -math.huge
      for _, p in ipairs(pts) do
        x0, x1 = min(x0, p.x - p.h - 8), max(x1, p.x + p.h + 8)
        y0, y1 = min(y0, p.y - p.h - 8), max(y1, p.y + p.h + 8)
      end
      ch.box = { x0, y0, x1, y1 }
      shape.chains[#shape.chains + 1] = ch
      -- Each arm's end, as the junction sees it: where it stops, which way it
      -- points away from the junction, and how wide it is there.
      local function arm(node, p, q, rd)
        local dx, dy = norm(q.x - p.x, q.y - p.y)
        shape.ends[node] = shape.ends[node] or {}
        table.insert(shape.ends[node], { x = p.x, y = p.y, dx = dx, dy = dy, h = p.h, kind = rd.kind, chain = ch, l = rd.l })
      end
      if #pts >= 2 then
        arm(first, pts[1], pts[2], links[1])
        arm(last, pts[#pts], pts[#pts - 1], links[#links])
      end
    end
  end

  -- The pieces of each link, for the mouse and for the traffic on it.
  for _, ch in ipairs(shape.chains) do
    local cur, list
    for i, p in ipairs(ch.pts) do
      local l = p.l or ch.links[1].l
      if l ~= cur then
        if list and i > 1 then list[#list + 1] = p end
        list = {}
        shape.pieces[l.id] = shape.pieces[l.id] or {}
        table.insert(shape.pieces[l.id], list)
        if i > 1 then list[1] = ch.pts[i - 1] end
        cur = l
      end
      list[#list + 1] = p
    end
  end

  -- Junction pads: each arm's two kerbs, and between neighbouring arms a
  -- kerb that sweeps from the one into the other. The control point of the
  -- sweep is where the two kerb lines would meet, so square crossroads get
  -- square-ish corners and a fork gets a long gentle one.
  for id, list in pairs(shape.ends) do
    if role[id] == "pad" and #list >= 2 then
      local n = nodes[id]
      table.sort(list, function(p, q) return atan2(p.dy, p.dx) < atan2(q.dy, q.dx) end)
      local function outline(extra)
        local poly = {}
        for i, e in ipairs(list) do
          local f = list[i % #list + 1]
          local w = e.h + (extra and RoadShape.pave(e.kind) or 0)
          local wf = f.h + (extra and RoadShape.pave(f.kind) or 0)
          local nx, ny = -e.dy, e.dx
          local fx, fy = -f.dy, f.dx
          local p1x, p1y = e.x - nx * w, e.y - ny * w
          local p2x, p2y = e.x + nx * w, e.y + ny * w
          local q1x, q1y = f.x - fx * wf, f.y - fy * wf
          poly[#poly + 1] = p1x; poly[#poly + 1] = p1y
          poly[#poly + 1] = p2x; poly[#poly + 1] = p2y
          -- The kerb lines run back toward the junction along each arm.
          local cx, cy
          local den = (-e.dx) * (-f.dy) - (-e.dy) * (-f.dx)
          if abs(den) > 1e-3 then
            local t = ((q1x - p2x) * (-f.dy) - (q1y - p2y) * (-f.dx)) / den
            if t > 0 and t < 400 then cx, cy = p2x - e.dx * t, p2y - e.dy * t end
          end
          cx, cy = cx or n.x, cy or n.y
          for j = 1, 7 do
            local s = j / 8
            local a, b, c = (1 - s) ^ 2, 2 * (1 - s) * s, s * s
            poly[#poly + 1] = a * p2x + b * cx + c * q1x; poly[#poly + 1] = a * p2y + b * cy + c * q1y
          end
        end
        return poly
      end
      shape.pads[#shape.pads + 1] = { id = id, x = n.x, y = n.y, arms = list, road = outline(false), kerb = outline(true), r = setback[id] or 20 }
    end
  end

  -- Interchanges: the road crossing over, and a slip road in every quarter
  -- between the highway and a road that meets it. A slip road leaves the
  -- highway's outer edge heading in, and bends round to meet the road square
  -- on, beside the bridge.
  for id, list in pairs(at) do
    if role[id] == "pass" then
      local n = nodes[id]
      local arms = {}
      for _, r in ipairs(list) do
        local dx, dy = dirFrom(id, r)
        arms[#arms + 1] = { r = r, dx = dx, dy = dy, a = atan2(dy, dx) }
      end
      table.sort(arms, function(p, q) return p.a < q.a end)
      local back = rampBack[id]
      local RH = 4.5
      for i, e in ipairs(arms) do
        local f = arms[i % #arms + 1]
        local high, low
        if e.r.kind == "highway" and f.r.kind ~= "highway" then high, low = e, f
        elseif f.r.kind == "highway" and e.r.kind ~= "highway" then high, low = f, e end
        local round = high and rounds[id] and rounds[id][low.r]
        if round then
          -- Off the roundabout: out of the ring heading for the highway and
          -- along it, then a long gentle curve down beside it and the merge.
          local mx, my = -high.dy, high.dx
          if mx * low.dx + my * low.dy < 0 then mx, my = -mx, -my end
          local function frame(u, v) return n.x + high.dx * u + mx * v, n.y + high.dy * u + my * v end
          local ux, uy = norm(high.dx * 0.8 - mx * 0.6, high.dy * 0.8 - my * 0.6)
          local ax, ay = round.x + ux * (ROUND - 1), round.y + uy * (ROUND - 1)
          local ua = (ax - n.x) * high.dx + (ay - n.y) * high.dy
          local va = (ax - n.x) * mx + (ay - n.y) * my
          local vm = high.r.h + RH
          local um = ua + max(70, (va - vm) * 2.4)
          local bx, by = frame(um, vm)
          local k = sqrt((bx - ax) ^ 2 + (by - ay) ^ 2) * 0.45
          local c1x, c1y = ax + ux * k, ay + uy * k
          local c2x, c2y = bx - high.dx * k, by - high.dy * k
          local pts = {}
          for j = 0, 20 do
            local t = j / 20
            local a, b, c, dd = (1 - t) ^ 3, 3 * (1 - t) ^ 2 * t, 3 * (1 - t) * t * t, t ^ 3
            local flare = j <= 2 and (1 + (2 - j) / 2 * 0.6) or 1
            pts[#pts + 1] = { x = a * ax + b * c1x + c * c2x + dd * bx, y = a * ay + b * c1y + c * c2y + dd * by, h = RH * flare, k = "ramp" }
          end
          local taper = 80
          for j = 1, 10 do
            local t = j / 10
            local w = RH * (1 - t)
            local x, y = frame(um + taper * t, high.r.h + w)
            pts[#pts + 1] = { x = x, y = y, h = max(0.05, w), k = "ramp" }
          end
          shape.ramps[#shape.ramps + 1] = { pts = pts, node = id }
          local off = high.r.h + 2 * RH + RoadShape.pave("highway") + 3
          local sx, sy = frame(um + taper + 50, off)
          shape.signs[#shape.signs + 1] = { kind = "exit", x = sx, y = sy, dx = -high.dx, dy = -high.dy }
        elseif high then
          -- m: across the highway toward the road; n: across the road toward
          -- the highway arm this slip road serves.
          local mx, my = -high.dy, high.dx
          if mx * low.dx + my * low.dy < 0 then mx, my = -mx, -my end
          local nx, ny = -low.dy, low.dx
          if nx * high.dx + ny * high.dy < 0 then nx, ny = -nx, -ny end
          -- Where it leaves the road: at the road's kerb, a lane's width short
          -- of where a dead-end road stops, so the road's end and the slip
          -- roads either side of it read as one T.
          local d = back - RH
          local ax, ay = n.x + low.dx * d + nx * (low.r.h - 1), n.y + low.dy * d + ny * (low.r.h - 1)
          -- Where it comes alongside the highway, its inner kerb on the
          -- highway's edge.
          local function frame(u, v) return n.x + high.dx * u + mx * v, n.y + high.dy * u + my * v end
          local ua = (ax - n.x) * high.dx + (ay - n.y) * high.dy
          local va = (ax - n.x) * mx + (ay - n.y) * my
          local vm = high.r.h + RH
          local um = ua + max(60, (va - vm) * 1.8)
          local bx, by = frame(um, vm)
          local k = sqrt((bx - ax) ^ 2 + (by - ay) ^ 2) * 0.5
          -- Out of the road square to it, leaning toward the highway, so a
          -- slanting road's slip road does not climb away before turning.
          local gx, gy = norm(bx - ax, by - ay)
          local tx, ty = norm(nx * 0.7 + gx, ny * 0.7 + gy)
          local c1x, c1y = ax + tx * k, ay + ty * k
          local c2x, c2y = bx - high.dx * k, by - high.dy * k
          local pts = {}
          for j = 0, 20 do
            local t = j / 20
            local a, b, c, dd = (1 - t) ^ 3, 3 * (1 - t) ^ 2 * t, 3 * (1 - t) * t * t, t ^ 3
            -- A bell mouth where it leaves the road.
            local flare = j <= 3 and (1 + (3 - j) / 3 * 0.9) or 1
            pts[#pts + 1] = { x = a * ax + b * c1x + c * c2x + dd * bx, y = a * ay + b * c1y + c * c2y + dd * by, h = RH * flare, k = "ramp" }
          end
          -- Then the merge: the lane runs on beside the highway and narrows
          -- into it, its inner kerb always on the highway's edge.
          local taper = 80
          for j = 1, 10 do
            local t = j / 10
            local w = RH * (1 - t)
            local x, y = frame(um + taper * t, high.r.h + w)
            pts[#pts + 1] = { x = x, y = y, h = max(0.05, w), k = "ramp" }
          end
          shape.ramps[#shape.ramps + 1] = { pts = pts, node = id }
          -- An exit sign on the verge before the slip road.
          local off = high.r.h + 2 * RH + RoadShape.pave("highway") + 3
          local sx, sy = frame(um + taper + 50, off)
          shape.signs[#shape.signs + 1] = { kind = "exit", x = sx, y = sy, dx = -high.dx, dy = -high.dy }
          -- And give way where it meets the road.
          shape.signs[#shape.signs + 1] = { kind = "giveway", x = ax - low.dx * (RH + 3) + nx * 4, y = ay - low.dy * (RH + 3) + ny * 4, dx = nx, dy = ny }
        end
      end
    end
  end

  for id, byRoad in pairs(rounds) do
    for _, rd in pairs(byRoad) do shape.rounds[#shape.rounds + 1] = { x = rd.x, y = rd.y, r = rd.r, node = id } end
  end

  -- Where two streets cross with no junction, one goes over. A highway stays
  -- on the ground and the other road bridges it; otherwise the newer road
  -- goes over the older one.
  local function over(a, b)
    local ra, rb = RANK[a.kind] or 2, RANK[b.kind] or 2
    if (a.kind == "highway") ~= (b.kind == "highway") then return a.kind ~= "highway" end
    if ra ~= rb then return ra > rb end
    return a.id > b.id
  end
  for i = 1, #shape.chains do
    local A = shape.chains[i]
    for j = i + 1, #shape.chains do
      local B = shape.chains[j]
      local ba, bb = A.box, B.box
      if ba[1] < bb[3] and bb[1] < ba[3] and ba[2] < bb[4] and bb[2] < ba[4] then
        local sa = 0
        for p = 2, #A.pts do
          local a1, a2 = A.pts[p - 1], A.pts[p]
          local segA = sqrt((a2.x - a1.x) ^ 2 + (a2.y - a1.y) ^ 2)
          local sb = 0
          for q = 2, #B.pts do
            local b1, b2 = B.pts[q - 1], B.pts[q]
            local segB = sqrt((b2.x - b1.x) ^ 2 + (b2.y - b1.y) ^ 2)
            local t, u = crossing(a1.x, a1.y, a2.x, a2.y, b1.x, b1.y, b2.x, b2.y)
            if t then
              local up, down, s, hDown = A, B, sa + segA * t, b1.h + (b2.h - b1.h) * u
              if not over(A, B) then up, down, s, hDown = B, A, sb + segB * u, a1.h + (a2.h - a1.h) * t end
              local reach = hDown + RoadShape.pave(down.kind) + 10
              shape.flyovers[#shape.flyovers + 1] = { chain = up, under = down,
                s0 = max(0, s - reach), s1 = min(up.len, s + reach),
                x = a1.x + (a2.x - a1.x) * t, y = a1.y + (a2.y - a1.y) * t }
            end
            sb = sb + segB
          end
          sa = sa + segA
        end
      end
    end
  end

  -- Signs: give way at each arm of a junction, a speed limit now and then
  -- along a normal road, a motorway sign where a highway starts. None stands
  -- on a building, a carriageway or water.
  for _, pad in ipairs(shape.pads) do
    for _, e in ipairs(pad.arms) do
      if e.kind ~= "highway" then
        local off = e.h + RoadShape.pave(e.kind) + 2.5
        shape.signs[#shape.signs + 1] = { kind = "giveway", x = e.x + e.dx * 4 - e.dy * off, y = e.y + e.dy * 4 + e.dx * off,
          dx = -e.dx, dy = -e.dy }
      end
    end
  end
  for _, ch in ipairs(shape.chains) do
    if ch.kind == "road" and ch.len > 160 then
      local count = floor(ch.len / 360) + 1
      for i = 1, count do
        local s = ch.len * i / (count + 1)
        local x, y, ux, uy, h = RoadShape.at(ch.pts, s)
        local side = i % 2 == 0 and 1 or -1
        local off = h + RoadShape.pave("road") + 2
        shape.signs[#shape.signs + 1] = { kind = "speed", x = x - uy * off * side, y = y + ux * off * side, dx = ux * side, dy = uy * side }
      end
    elseif ch.kind == "highway" and ch.len > 120 then
      for _, which in ipairs({ 1, -1 }) do
        local s = which == 1 and 40 or ch.len - 40
        local x, y, ux, uy, h = RoadShape.at(ch.pts, s)
        local off = (h + RoadShape.pave("highway") + 3) * which
        shape.signs[#shape.signs + 1] = { kind = "motorway", x = x - uy * off, y = y + ux * off, dx = ux * which, dy = uy * which }
      end
    end
  end
  local kept = {}
  for _, sg in ipairs(shape.signs) do
    local ok = not city:isWater(sg.x, sg.y)
    if ok then
      for _, n in ipairs(city.g:aliveNodes()) do
        if not City.ROAD_JUNCTIONS[n.kind] then
          local body = City.footprint(n.kind)
          if (n.x - sg.x) ^ 2 + (n.y - sg.y) ^ 2 < (body + 3) ^ 2 then ok = false; break end
        end
      end
    end
    if ok then
      for _, ch in ipairs(shape.chains) do
        local b = ch.box
        if sg.x > b[1] and sg.x < b[3] and sg.y > b[2] and sg.y < b[4] then
          for p = 2, #ch.pts do
            local a, c = ch.pts[p - 1], ch.pts[p]
            local dx, dy = c.x - a.x, c.y - a.y
            local t = max(0, min(1, ((sg.x - a.x) * dx + (sg.y - a.y) * dy) / max(1e-9, dx * dx + dy * dy)))
            if (a.x + dx * t - sg.x) ^ 2 + (a.y + dy * t - sg.y) ^ 2 < (a.h + 1) ^ 2 then ok = false; break end
          end
        end
        if not ok then break end
      end
    end
    if ok then kept[#kept + 1] = sg end
  end
  shape.signs = kept
  return shape
end

function RoadShape.get(city)
  local key = (city.revision or 0) .. ":" .. #(city.links or {}) .. ":" .. #city.g.nodes
  local c = cache[city]
  if c and c.key == key and c.river == city.river then return c.shape end
  local shape = build(city)
  cache[city] = { key = key, river = city.river, shape = shape }
  return shape
end

function RoadShape.forget(city) cache[city] = nil end

-- How far a point is from a link's road, in metres, and the road's half width
-- there; nil if the link has no road drawn.
function RoadShape.distanceTo(city, l, x, y)
  local pieces = RoadShape.get(city).pieces[l.id]
  if not pieces then return nil end
  local best, half
  for _, pts in ipairs(pieces) do
    for i = 2, #pts do
      local a, b = pts[i - 1], pts[i]
      local dx, dy = b.x - a.x, b.y - a.y
      local t = max(0, min(1, ((x - a.x) * dx + (y - a.y) * dy) / max(1e-9, dx * dx + dy * dy)))
      local d = sqrt((a.x + dx * t - x) ^ 2 + (a.y + dy * t - y) ^ 2)
      if not best or d < best then best, half = d, a.h + (b.h - a.h) * t end
    end
  end
  return best, half
end

return RoadShape
