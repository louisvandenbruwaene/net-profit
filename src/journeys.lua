-- journeys.lua -- the day's drives, each car on the way it actually went.
--
-- people.lua books every drive as the roads it took, in order, from where it
-- set out (`city.transit.journeys`). Here each one becomes a single path a
-- car follows on the map, in its lane, keeping right:
--   along a street       in the right-hand lane, round its bends
--   through a junction   up to the stop line, then a turn across the pad
--                        onto the next street
--   at an interchange    off the highway by the slip road, round the
--                        roundabout and away, or up the road, round, and
--                        down the slip road into the highway's slow lane
--   past a roundabout    a road through one goes round it, not over it
-- Each car sets out at its own moment of a looping day, drives there, waits a
-- while, and drives home; so the roads are never full at once and never
-- empty. Rules of the road, worked out every frame among the cars on screen:
-- give way at a junction to anyone already in it, give way entering a
-- roundabout to anyone coming round, merge onto the highway behind its
-- traffic, and never drive into the car ahead.
local RoadShape = require("road_shape")
local City = require("city")

local Journeys = {}

-- How long a day is on the map, in seconds of real time.
Journeys.DAY = 150
local DAY = Journeys.DAY
-- Most drives drawn in a day, however many people travel.
local MOST = 220
local SPEED = { car = 42, van = 38, truck = 30, bus = 28 }
-- How fast each kind of way is driven, against a normal road.
local PACE = { road = 1, offroad = 0.6, highway = 1.7, ramp = 0.9, ring = 0.55, turn = 0.5 }
local STEP = 8

local sqrt, atan2, min, max, floor, abs = math.sqrt, math.atan2, math.min, math.max, math.floor, math.abs
local TAU = 2 * math.pi

local function hash(a, b, c)
  local v = math.sin(a * 12.9898 + b * 78.233 + (c or 0) * 37.719) * 43758.5453
  return v - floor(v)
end
local function norm(x, y)
  local l = sqrt(x * x + y * y)
  if l < 1e-9 then return 0, 0, 0 end
  return x / l, y / l, l
end
local function dist(ax, ay, bx, by) return sqrt((ax - bx) ^ 2 + (ay - by) ^ 2) end

--------------------------------------------------------------------------------
-- Roundabouts: cars keep right, so they go round anticlockwise on the map
-- (the angle falling, with y down), in the middle of the ring.
--------------------------------------------------------------------------------

local RING = (RoadShape.ISLAND + 1.2 + RoadShape.ROUND) / 2
Journeys.RING = RING

-- The way from a point outside a ring, round it, to another point outside:
-- straight in, round, straight out, as a function of the distance gone.
function Journeys.ringWay(cx, cy, ax, ay, bx, by)
  local ta, tb = atan2(ay - cy, ax - cx), atan2(by - cy, bx - cx)
  local delta = (ta - tb) % TAU
  if delta < 0.3 then delta = delta + TAU end
  local px, py = cx + math.cos(ta) * RING, cy + math.sin(ta) * RING
  local qx, qy = cx + math.cos(tb) * RING, cy + math.sin(tb) * RING
  local l1 = dist(px, py, ax, ay)
  local l2 = RING * delta
  local l3 = dist(bx, by, qx, qy)
  local total = l1 + l2 + l3
  local function pos(d)
    if d <= l1 then local f = l1 > 0 and d / l1 or 1; return ax + (px - ax) * f, ay + (py - ay) * f end
    d = d - l1
    if d <= l2 then local th = ta - d / RING; return cx + math.cos(th) * RING, cy + math.sin(th) * RING end
    local f = l3 > 0 and min(1, (d - l2) / l3) or 1
    return qx + (bx - qx) * f, qy + (by - qy) * f
  end
  return pos, total, ta, l1, l2
end
local ringWay = Journeys.ringWay

--------------------------------------------------------------------------------
-- Building a drive's path
--------------------------------------------------------------------------------

-- A link's road as drawn, as centre-line points from the end at `from`.
local function piece(shape, city, lid, from)
  local list = shape.pieces[lid]
  if not list or #list == 0 then return nil end
  local pts = {}
  for _, p in ipairs(list) do
    for i, q in ipairs(p) do
      local last = pts[#pts]
      if not (last and i == 1 and dist(last.x, last.y, q.x, q.y) < 0.5) then
        pts[#pts + 1] = { x = q.x, y = q.y, h = q.h, k = q.k }
      end
    end
  end
  local n = city.g.nodes[from]
  if not n then return nil end
  if dist(pts[#pts].x, pts[#pts].y, n.x, n.y) < dist(pts[1].x, pts[1].y, n.x, n.y) then
    local r = {}
    for i = #pts, 1, -1 do r[#r + 1] = pts[i] end
    pts = r
  end
  return pts
end

-- Points no further apart than STEP, so a lane can be laid beside them.
local function resample(pts)
  local out = { pts[1] }
  for i = 2, #pts do
    local a, b = pts[i - 1], pts[i]
    local d = dist(a.x, a.y, b.x, b.y)
    local n = max(1, math.ceil(d / STEP))
    for j = 1, n do
      local f = j / n
      out[#out + 1] = { x = a.x + (b.x - a.x) * f, y = a.y + (b.y - a.y) * f, h = a.h + (b.h - a.h) * f, k = b.k or a.k }
    end
  end
  return out
end

-- The lane a car keeps on a centre line: `laneOf(p, i)` metres to the right.
local function laneSide(pts, laneOf)
  local out = {}
  for i, p in ipairs(pts) do
    local a, b = pts[max(1, i - 1)], pts[min(#pts, i + 1)]
    local ux, uy = norm(b.x - a.x, b.y - a.y)
    local w = laneOf(p, i)
    out[i] = { x = p.x - uy * w, y = p.y + ux * w, kind = p.k or "road" }
  end
  return out
end

-- Cut a path where it first comes within `r` of a point; the part before.
local function cutBefore(path, cx, cy, r)
  for i = 2, #path do
    local a, b = path[i - 1], path[i]
    if dist(b.x, b.y, cx, cy) < r and dist(a.x, a.y, cx, cy) >= r then
      -- Where along a..b it crosses the circle.
      local lo, hi = 0, 1
      for _ = 1, 20 do
        local m = (lo + hi) / 2
        if dist(a.x + (b.x - a.x) * m, a.y + (b.y - a.y) * m, cx, cy) >= r then lo = m else hi = m end
      end
      local out = {}
      for j = 1, i - 1 do out[j] = path[j] end
      -- A ring already worked out past here is gone with the rest.
      if out[#out].mark and out[#out].mark.ring then out[#out] = { x = out[#out].x, y = out[#out].y, kind = out[#out].kind } end
      out[#out + 1] = { x = a.x + (b.x - a.x) * lo, y = a.y + (b.y - a.y) * lo, kind = a.kind }
      return out, i
    end
  end
  return nil
end
-- The part of a path after it last leaves `r` of a point.
local function cutAfter(path, cx, cy, r)
  for i = #path - 1, 1, -1 do
    local a, b = path[i], path[i + 1]
    if dist(a.x, a.y, cx, cy) < r and dist(b.x, b.y, cx, cy) >= r then
      local lo, hi = 0, 1
      for _ = 1, 20 do
        local m = (lo + hi) / 2
        if dist(a.x + (b.x - a.x) * m, a.y + (b.y - a.y) * m, cx, cy) < r then lo = m else hi = m end
      end
      local out = { { x = a.x + (b.x - a.x) * hi, y = a.y + (b.y - a.y) * hi, kind = b.kind } }
      for j = i + 1, #path do out[#out + 1] = path[j] end
      return out
    end
  end
  -- Never inside: all of it.
  if dist(path[1].x, path[1].y, cx, cy) >= r then return path end
  return nil
end

-- Round a roundabout from the end of `path` to `to`'s first point.
local function roundTo(path, rd, to)
  local a, b = path[#path], to[1]
  local pos, total, ta, l1, l2 = ringWay(rd.x, rd.y, a.x, a.y, b.x, b.y)
  a.mark = { ring = { rd = rd, total = total, l1 = l1, l2 = l2, te = ta } }
  local n = max(6, math.ceil(total / 2))
  for j = 1, n - 1 do
    local x, y = pos(total * j / n)
    path[#path + 1] = { x = x, y = y, kind = "ring" }
  end
  for _, p in ipairs(to) do path[#path + 1] = p end
end

-- A road through roundabouts goes round each one rather than over the island.
local function aroundRings(path, rounds)
  for _, rd in ipairs(rounds) do
    if rd.through then
      local near = false
      for _, p in ipairs(path) do
        if p.kind ~= "ring" and dist(p.x, p.y, rd.x, rd.y) < 6 then near = true; break end
      end
      if near then
        local before = cutBefore(path, rd.x, rd.y, rd.r + 4)
        local after = cutAfter(path, rd.x, rd.y, rd.r + 4)
        if before and after then
          roundTo(before, rd, after)
          path = before
        end
      end
    end
  end
  return path
end

local function append(path, more)
  for i, p in ipairs(more) do
    local last = path[#path]
    if not (i == 1 and last and dist(last.x, last.y, p.x, p.y) < 0.3) then path[#path + 1] = p end
  end
end

-- The lane a vehicle keeps on a highway: trucks and buses on the slow outer
-- lane, cars on either. Within `ease` metres of a slip road at either end,
-- it moves over to the outer lane.
local function highwayLane(pts, fast, nearStart, nearEnd)
  local total, run = 0, { 0 }
  for i = 2, #pts do total = total + dist(pts[i - 1].x, pts[i - 1].y, pts[i].x, pts[i].y); run[i] = total end
  return function(p, i)
    local h = p.h or 16
    local want = fast and 0.34 or 0.77
    local f = 1
    if nearStart then f = min(f, run[i] / 90) end
    if nearEnd then f = min(f, (total - run[i]) / 90) end
    f = max(0, min(1, f))
    f = f * f * (3 - 2 * f)
    return h * (0.77 + (want - 0.77) * f)
  end
end

local function laneFor(k, fast)
  if k == "highway" then return function(p) return (p.h or 16) * (fast and 0.34 or 0.77) end end
  return function(p) return (p.h or 8) * 0.48 end
end

-- The drive along `links` from node `from`, as one path of lane points with
-- marks where it must give way; nil where a link has no road drawn.
local function build(city, shape, links, from, fast, info)
  local nodes = city.g.nodes
  local path = {}
  local at = from
  local prevKind, prevLink
  for k, lid in ipairs(links) do
    local l = city.links[lid]
    if not l then return nil end
    local nextNode = l.a == at and l.b or l.a
    local c = piece(shape, city, lid, at)
    if not c then return nil end
    local kind = RoadShape.visual(l)
    local role = shape.role[at]
    local turned = false
    if k > 1 and role == "pass" and (kind == "highway") ~= (prevKind == "highway") then
      local m = nodes[at]
      if kind == "highway" then
        -- Up the slip road: the one that joins the highway going our way.
        local fx, fy = norm(nodes[nextNode].x - m.x, nodes[nextNode].y - m.y)
        local ramp
        for _, r in ipairs(shape.ramps) do
          if r.node == at and not r.off and r.round and r.hx * fx + r.hy * fy > 0 then ramp = r end
        end
        if ramp then
          local rd = ramp.round
          -- The ring the road comes to first: this one, or the near one of
          -- a pair over the highway.
          local first = rd.across or rd
          -- On the far side of the bridge: over it first.
          if first.link ~= prevLink then
            local over = piece(shape, city, first.link.id, at)
            if over then
              append(path, laneSide(resample(over), laneFor("road")))
            end
          end
          local before = cutBefore(path, first.x, first.y, first.r + 4)
          if before and rd.across then
            -- Round the near ring, over the road across, to the far one.
            local b = cutAfter(laneSide(resample(first.bridge), laneFor("road")), first.x, first.y, first.r + 4)
            b = b and cutBefore(b, rd.x, rd.y, rd.r + 4)
            if b then roundTo(before, first, b) else before = nil end
          end
          if before then
            path = before
            local up = {}
            for i, q in ipairs(ramp.pts) do
              up[#up + 1] = { x = q.x, y = q.y, kind = "ramp" }
              if i == 21 then up[#up].mark = { merge = { ramp = ramp } } end
            end
            roundTo(path, rd, up)
            -- Into the highway's slow lane where the slip road ends, then
            -- across to its own lane.
            local hw = resample(c)
            local e = ramp.pts[#ramp.pts]
            local bi, bd = 1, math.huge
            for i, q in ipairs(hw) do
              local d = dist(q.x, q.y, e.x, e.y)
              if d < bd then bi, bd = i, d end
            end
            local rest = {}
            for i = bi, #hw do rest[#rest + 1] = hw[i] end
            if #rest >= 2 then append(path, laneSide(rest, highwayLane(rest, fast, true, false))) end
            turned = true
          end
        end
      else
        -- Off by the slip road on our side, round, and away down the road.
        local m = nodes[at]
        local prev = city.links[links[k - 1]]
        local back = prev.a == at and prev.b or prev.a
        local fx, fy = norm(nodes[back].x - m.x, nodes[back].y - m.y)
        local ramp
        for _, r in ipairs(shape.ramps) do
          if r.node == at and r.off and r.round and r.hx * fx + r.hy * fy > 0 then ramp = r end
        end
        if ramp then
          local rd = ramp.round
          local e = ramp.pts[#ramp.pts]
          -- Leave the highway where the slip road meets it.
          local bi, bd
          for i = #path, max(1, #path - 120), -1 do
            local d = dist(path[i].x, path[i].y, e.x, e.y)
            if not bd or d < bd then bi, bd = i, d end
          end
          if bi and bd < 30 then
            local kept = {}
            for i = 1, bi do kept[i] = path[i] end
            path = kept
            for i = #ramp.pts, 1, -1 do path[#path + 1] = { x = ramp.pts[i].x, y = ramp.pts[i].y, kind = "ramp" } end
            -- The ring the road leaves from: this one, or the near one of a
            -- pair over the highway.
            local last = rd.across or rd
            -- Away: down this road, or over the bridge to the far side first.
            local away = {}
            if last.link.id ~= lid then
              local toNode = piece(shape, city, last.link.id, last.link.a == at and last.link.b or last.link.a)
              if toNode then append(away, laneSide(resample(toNode), laneFor("road"))) end
            end
            append(away, laneSide(resample(c), laneFor(kind)))
            local out = cutAfter(away, last.x, last.y, last.r + 4)
            local across = true
            if rd.across then
              -- Round the far ring and back over the road across.
              local rev = {}
              for i = #last.bridge, 1, -1 do rev[#rev + 1] = last.bridge[i] end
              local b = cutAfter(laneSide(resample(rev), laneFor("road")), rd.x, rd.y, rd.r + 4)
              b = b and cutBefore(b, last.x, last.y, last.r + 4)
              if b then roundTo(path, rd, b) else across = false end
            end
            if across and out and #out >= 2 then
              out = aroundRings(out, shape.rounds)
              roundTo(path, last, out)
              turned = true
            end
          end
        end
      end
    end
    if not turned then
      local laneOf = kind == "highway" and highwayLane(resample(c), fast,
        false, false) or laneFor(kind, fast)
      -- A highway leg that leaves by a slip road at its far end eases over
      -- to the slow lane before it.
      if kind == "highway" and links[k + 1] then
        local nl = city.links[links[k + 1]]
        if nl and RoadShape.visual(nl) ~= "highway" and shape.role[nextNode] == "pass" then
          local rs = resample(c)
          laneOf = highwayLane(rs, fast, false, true)
        end
      end
      local lane = laneSide(resample(c), laneOf)
      lane = aroundRings(lane, shape.rounds)
      if k > 1 and role == "pad" and #path > 0 then
        -- A junction: stop at the line, then across the pad to the next road.
        local pad
        for _, p in ipairs(shape.pads) do if p.id == at then pad = p; break end end
        path[#path].mark = { gate = { x = nodes[at].x, y = nodes[at].y, r = pad and pad.r or 20 } }
        local a, b = path[#path], lane[1]
        local a0 = path[max(1, #path - 1)]
        local ux, uy = norm(a.x - a0.x, a.y - a0.y)
        local b1 = lane[min(#lane, 2)]
        local vx, vy = norm(b1.x - b.x, b1.y - b.y)
        local kk = dist(a.x, a.y, b.x, b.y) * 0.45
        for j = 1, 7 do
          local f = j / 8
          local p0, p1, p2, p3 = (1 - f) ^ 3, 3 * (1 - f) ^ 2 * f, 3 * (1 - f) * f * f, f ^ 3
          path[#path + 1] = {
            x = p0 * a.x + p1 * (a.x + ux * kk) + p2 * (b.x - vx * kk) + p3 * b.x,
            y = p0 * a.y + p1 * (a.y + uy * kk) + p2 * (b.y - vy * kk) + p3 * b.y, kind = "turn" }
        end
      end
      append(path, lane)
    end
    prevKind, prevLink, at = kind, l, nextNode
  end
  if #path < 2 then return nil end
  -- Lengths, times and the marks along the way.
  local r = { x = {}, y = {}, s = { 0 }, t = { 0 }, rings = {}, gates = {}, merges = {}, kind = {} }
  local speed = SPEED[info.vehicle] or SPEED.car
  for i, p in ipairs(path) do
    r.x[i], r.y[i], r.kind[i] = p.x, p.y, p.kind or "road"
    if i > 1 then
      local d = dist(path[i - 1].x, path[i - 1].y, p.x, p.y)
      r.s[i] = r.s[i - 1] + d
      r.t[i] = r.t[i - 1] + d / (speed * (PACE[path[i - 1].kind or "road"] or 1))
    end
    local mk = p.mark
    if mk and mk.ring then
      local g = mk.ring
      r.rings[#r.rings + 1] = { rd = g.rd, s0 = r.s[i], len = g.total, total = g.total, l1 = g.l1, l2 = g.l2, te = g.te }
    elseif mk and mk.gate then
      r.gates[#r.gates + 1] = { s = r.s[i], x = mk.gate.x, y = mk.gate.y, r = mk.gate.r }
    elseif mk and mk.merge then
      local ramp = mk.merge.ramp
      r.merges[#r.merges + 1] = { s = r.s[i], ramp = ramp }
    end
  end
  r.len, r.time = r.s[#r.s], r.t[#r.t]
  return r
end

-- Where a car is `s` metres along, and the way it faces.
local function sampleS(r, s)
  local lo, hi = 1, #r.s
  while hi - lo > 1 do
    local mid = floor((lo + hi) / 2)
    if r.s[mid] <= s then lo = mid else hi = mid end
  end
  local seg = r.s[hi] - r.s[lo]
  local f = seg > 0 and max(0, min(1, (s - r.s[lo]) / seg)) or 0
  local dx, dy = r.x[hi] - r.x[lo], r.y[hi] - r.y[lo]
  local ux, uy = norm(dx, dy)
  return r.x[lo] + dx * f, r.y[lo] + dy * f, ux, uy, r.kind[lo]
end
-- How far along a car is `e` seconds out, and how long it takes to get `s` in.
local function sAtTime(r, e)
  local lo, hi = 1, #r.t
  while hi - lo > 1 do
    local mid = floor((lo + hi) / 2)
    if r.t[mid] <= e then lo = mid else hi = mid end
  end
  local span = r.t[hi] - r.t[lo]
  local f = span > 0 and max(0, min(1, (e - r.t[lo]) / span)) or 0
  return r.s[lo] + (r.s[hi] - r.s[lo]) * f
end
local function timeAtS(r, s)
  local lo, hi = 1, #r.s
  while hi - lo > 1 do
    local mid = floor((lo + hi) / 2)
    if r.s[mid] <= s then lo = mid else hi = mid end
  end
  local seg = r.s[hi] - r.s[lo]
  local f = seg > 0 and max(0, min(1, (s - r.s[lo]) / seg)) or 0
  return r.t[lo] + (r.t[hi] - r.t[lo]) * f
end

--------------------------------------------------------------------------------
-- The day's drives
--------------------------------------------------------------------------------

local cache = setmetatable({}, { __mode = "k" })

local CAR_KIND = function(seed) return hash(seed, 7, 9) < 0.15 and "van" or "car" end

-- Every drive of the day: its path, when it sets out, and its vehicle.
function Journeys.plan(city)
  local transit = city.transit
  local shape = RoadShape.get(city)
  local c = cache[city]
  if c and c.transit == transit and c.shape == shape then return c.drives end
  local drives = {}
  -- Which roundabout each slip road leaves from.
  for _, rd in ipairs(shape.rounds or {}) do
    for _, ramp in ipairs(rd.ramps or {}) do ramp.round = rd end
  end
  local list = (transit and transit.journeys) or {}
  local total = 0
  for _, j in ipairs(list) do total = total + j.count end
  local share = min(1, MOST / max(1, total))
  local paths = {}
  local function pathFor(links, from, fast, vehicle)
    local key = (fast and "f" or "s") .. vehicle .. ":" .. from .. ":" .. table.concat(links, ",")
    if paths[key] == nil then paths[key] = build(city, shape, links, from, fast, { vehicle = vehicle }) or false end
    return paths[key] or nil
  end
  local function reversed(links) local r = {} for i = #links, 1, -1 do r[#r + 1] = links[i] end return r end
  local function lastNode(links, from)
    local at = from
    for _, lid in ipairs(links) do local l = city.links[lid]; if not l then return nil end; at = l.a == at and l.b or l.a end
    return at
  end
  for ji, j in ipairs(list) do
    local n = j.count * share
    local whole = floor(n) + ((hash(ji, 3, 5) < n - floor(n)) and 1 or 0)
    if j.vehicle == "bus" then whole = max(1, j.count) end
    local home = lastNode(j.links, j.from)
    for i = 1, min(whole, 12) do
      local seed = ji * 37 + i
      local kind = j.vehicle == "car" and CAR_KIND(seed) or j.vehicle
      local fast = kind ~= "truck" and kind ~= "bus" and hash(seed, 6) < 0.5
      local out = pathFor(j.links, j.from, fast, j.vehicle)
      local back = home and pathFor(reversed(j.links), home, fast, j.vehicle)
      if out then
        -- A bus works its line all day; anyone else sets out once, at a
        -- moment of their own, stays a while, and drives home.
        local leave = j.vehicle == "bus" and (i - 1) / whole * DAY or hash(seed, 1) * DAY
        local stay = j.vehicle == "bus" and 4 or 8 + 30 * hash(seed, 2)
        local colour = floor(hash(seed, 4) * 7) + 1
        local pace = 0.9 + 0.2 * hash(seed, 8)
        drives[#drives + 1] = { key = seed * 2, r = out, leave = leave, kind = kind, colour = colour, pace = pace }
        if back then
          drives[#drives + 1] = { key = seed * 2 + 1, r = back, leave = (leave + out.time / pace + stay) % DAY, kind = kind, colour = colour, pace = pace }
        end
      end
    end
  end
  cache[city] = { transit = transit, shape = shape, drives = drives }
  return drives
end

--------------------------------------------------------------------------------
-- The rules of the road
--------------------------------------------------------------------------------

-- Each car keeps how long it has been held up, so one that waits stands
-- still and then drives on from where it stood.
local held, frame, lastT = {}, 0, nil

local function holdTo(v, s)
  if v.s > s then
    local e = timeAtS(v.r, s)
    v.w.d = v.w.d + (v.e - e)
    v.e, v.s = e, s
  end
end
local function standStill(v, dt)
  local e = max(0, v.e - dt)
  v.w.d = v.w.d + (v.e - e)
  v.e, v.s = e, sAtTime(v.r, e)
end

-- At a junction: wait at the line while anyone else is on the pad, one car
-- across at a time.
local function junctions(cars)
  local claimed = {}
  for _, v in ipairs(cars) do
    local passed = v.w.passed
    for gi, g in ipairs(v.r.gates) do
      local u = v.s - g.s
      local key = "g" .. gi
      if not passed[key] then
        if u > 1.5 then
          -- Already over the line before anyone looked.
          passed[key] = true
        elseif u > -12 then
          local zone = g.x * 7919 + g.y
          local busy = claimed[zone]
          if not busy then
            -- Anyone over the line here and not yet clear of the junction.
            for _, o in ipairs(cars) do
              if o ~= v and dist(o.x, o.y, g.x, g.y) < g.r + 8 then
                for ogi, og in ipairs(o.r.gates) do
                  if og.x == g.x and og.y == g.y and o.w.passed["g" .. ogi] and o.s - og.s < 2 * g.r + 20 then busy = true; break end
                end
              end
              if busy then break end
            end
          end
          if busy then
            holdTo(v, g.s - 1)
            v.waiting = true
          elseif u >= -2 then
            passed[key] = true
            claimed[zone] = true
          end
        end
      end
    end
  end
end

-- At a roundabout: wait short of the line while anyone close is coming round
-- or still clearing the way in; once round, keep a distance from the car ahead.
local UPSTREAM, CLEARING, GAP = 1.3, 0.55, 0.75
local function roundabouts(cars, dt)
  local at = {}
  for _, v in ipairs(cars) do
    for ri, rg in ipairs(v.r.rings) do
      local u = v.s - rg.s0
      if u > -16 and u <= rg.len + 0.5 then
        local list = at[rg.rd] or {}
        at[rg.rd] = list
        list[#list + 1] = { v = v, rg = rg, key = "r" .. ri, u = u, th = atan2(v.y - rg.rd.y, v.x - rg.rd.x) }
      end
    end
  end
  for _, list in pairs(at) do
    local function circling(o) return o.u >= 0 and o.u < o.rg.l1 + o.rg.l2 and o.v.w.passed[o.key] end
    for _, c in ipairs(list) do
      local passed = c.v.w.passed
      if c.u > 1.5 and not passed[c.key] and c.v.w.ringWait ~= c.key then passed[c.key] = true end
      local back = max(0, 8.5 - c.rg.l1)
      if not passed[c.key] and c.u > -back - 3 then
        local blocked = false
        for _, o in ipairs(list) do
          if o ~= c and circling(o) then
            local a = (o.th - c.rg.te) % TAU
            if a < UPSTREAM or a > TAU - CLEARING then blocked = true; break end
          end
        end
        if blocked then
          c.v.w.ringWait = c.key
          c.v.waiting = true
          holdTo(c.v, c.rg.s0 - back)
        else
          c.v.w.ringWait = nil
          if c.u >= -back then passed[c.key] = true end
        end
      end
    end
    local function going(o) return o.u >= 0 and o.v.w.passed[o.key] and o.u >= o.rg.l1 end
    for _, c in ipairs(list) do
      if going(c) then
        for _, o in ipairs(list) do
          if o ~= c and going(o) then
            local a = (c.th - o.th) % TAU
            if a > 0 and a < GAP then standStill(c.v, dt * c.v.pace); break end
          end
        end
      end
    end
  end
end

-- Onto the highway: where the slip road runs alongside, wait while the slow
-- lane is taken beside it or coming up behind.
local function merges(cars)
  for _, v in ipairs(cars) do
    for mi, m in ipairs(v.r.merges) do
      local u = v.s - m.s
      if u > -12 and u <= 1 and not v.w.passed["m" .. mi] then
        local ramp = m.ramp
        local p = ramp.pts[21]
        local dx, dy = ramp.hx, ramp.hy
        local blocked = false
        for _, o in ipairs(cars) do
          if o ~= v and o.x and o.on == "highway" then
            local ox, oy = o.x - p.x, o.y - p.y
            local along = ox * dx + oy * dy
            local side = abs(ox * -dy + oy * dx)
            if along > -40 and along < 12 and abs(side - (ramp.lane + 4.5)) < 4 then blocked = true; break end
          end
        end
        if blocked then holdTo(v, m.s); v.waiting = true
        elseif u >= -1 then v.w.passed["m" .. mi] = true end
      end
    end
  end
end

-- Never into the car ahead: one close behind another going its way, in its
-- lane, stands still this moment.
local function follow(cars, dt)
  local grid, CELL = {}, 16
  for _, v in ipairs(cars) do
    local k = floor(v.x / CELL) * 65536 + floor(v.y / CELL)
    grid[k] = grid[k] or {}
    table.insert(grid[k], v)
  end
  for _, v in ipairs(cars) do
    local cx, cy = floor(v.x / CELL), floor(v.y / CELL)
    local stop = false
    for ix = cx - 1, cx + 1 do
      for iy = cy - 1, cy + 1 do
        for _, o in ipairs(grid[ix * 65536 + iy] or {}) do
          if o ~= v and v.ux * o.ux + v.uy * o.uy > 0.5 then
            local dx, dy = o.x - v.x, o.y - v.y
            local ahead = dx * v.ux + dy * v.uy
            local side = abs(dx * -v.uy + dy * v.ux)
            -- Level with each other: the later one on the road holds back.
            if abs(ahead) < 0.5 then ahead = (v.key > o.key) and 0.5 or -1 end
            if ahead > 0 and ahead < (v.long + o.long) / 2 + 2 and side < 2.2 then stop = true end
          end
        end
      end
    end
    if stop then standStill(v, dt * v.pace) end
  end
end

local LONG = { car = 13.5, van = 16.5, truck = 25.5, bus = 28.5 }

-- The cars on the road now, within `box` (x0, y0, x1, y1), each placed and
-- facing its way: { x, y, ux, uy, kind, colour }.
function Journeys.now(city, t, box)
  local drives = Journeys.plan(city)
  frame = frame + 1
  local dt = lastT and max(0, min(0.25, t - lastT)) or 0
  lastT = t
  local cars = {}
  local x0, y0, x1, y1 = box[1] - 200, box[2] - 200, box[3] + 200, box[4] + 200
  for _, d in ipairs(drives) do
    local w = held[d.key]
    if not w then w = { d = 0, passed = {} }; held[d.key] = w end
    w.seen = frame
    -- A new day: whatever held it up yesterday is forgotten.
    local day = floor((t - d.leave) / DAY)
    if w.day ~= day then w.day, w.d, w.passed, w.ringWait = day, 0, {}, nil end
    local e = ((t - d.leave) % DAY) * d.pace - w.d
    if e >= 0 and e < d.r.time then
      local s = sAtTime(d.r, e)
      local x, y = sampleS(d.r, s)
      if x > x0 and x < x1 and y > y0 and y < y1 then
        local v = { r = d.r, w = w, e = e, s = s, kind = d.kind, colour = d.colour, long = LONG[d.kind] or 13.5, key = d.key, pace = d.pace }
        cars[#cars + 1] = v
      end
    end
  end
  local function place()
    for _, v in ipairs(cars) do v.x, v.y, v.ux, v.uy, v.on = sampleS(v.r, v.s) end
  end
  place()
  junctions(cars)
  roundabouts(cars, dt)
  merges(cars)
  place()
  follow(cars, dt)
  place()
  -- One that cannot pull out yet is still parked where it set out from.
  local out = {}
  for _, v in ipairs(cars) do if v.s > 0.5 then out[#out + 1] = v end end
  cars = out
  if frame % 600 == 0 then
    for k, w in pairs(held) do if frame - w.seen > 600 then held[k] = nil end end
  end
  return cars
end

-- For tests: the path a drive along `links` from `from` would take.
Journeys.build = function(city, links, from, fast, vehicle)
  local shape = RoadShape.get(city)
  for _, rd in ipairs(shape.rounds or {}) do
    for _, ramp in ipairs(rd.ramps or {}) do ramp.round = rd end
  end
  return build(city, shape, links, from, fast, { vehicle = vehicle or "car" })
end

return Journeys
