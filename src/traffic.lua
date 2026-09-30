-- traffic.lua -- the town going about its day: cars and trucks on the streets
-- between plots, people on the pavements and between neighbours, boats on the
-- river and at sea, birds over the woods, airliners overhead, and a crew van
-- at every leak a crew is out to.
--
-- Pure decoration. Every position is a function of R.t and of hashes of things
-- that already exist, so nothing here is saved, nothing reads City:random(),
-- and the same frame always draws the same traffic.
local R = require("render")
local P = require("palette")

local Traffic = {}
local lg = love and love.graphics

local function hash(a, b, c)
  local v = math.sin(a * 12.9898 + b * 78.233 + (c or 0) * 37.719) * 43758.5453
  return v - math.floor(v)
end

-- Sized like the buildings (R.sym), so traffic stays readable next to them
-- when the camera pulls back, with a floor so nothing shrinks to grit.
local function px(base, scale, floor) return math.max(floor or 1, R.sym(base, scale)) end

local CAR_COLOURS = {
  { 0.86, 0.30, 0.28 }, { 0.92, 0.88, 0.80 }, { 0.30, 0.52, 0.86 }, { 0.20, 0.22, 0.26 },
  { 0.95, 0.76, 0.30 }, { 0.55, 0.60, 0.64 }, { 0.36, 0.66, 0.46 },
}
local COATS = {
  { 0.86, 0.36, 0.30 }, { 0.30, 0.50, 0.84 }, { 0.93, 0.80, 0.36 }, { 0.84, 0.86, 0.88 },
  { 0.46, 0.72, 0.52 }, { 0.62, 0.42, 0.78 },
}

--------------------------------------------------------------------------------
-- Streets. A land plot fills its cell, so the gap drawn between two plots is
-- the cell boundary, and that is the street. Each plot's own cars go round it
-- clockwise, inset from the boundary, so the plot next door's cars share the
-- street going the other way: two lanes with no lane table anywhere.
--------------------------------------------------------------------------------

local function perimeterPoint(d, s, inset)
  local w, h = d.w - inset * 2, d.h - inset * 2
  local x0, y0 = d.x + inset, d.y + inset
  s = s % (2 * (w + h))
  if s < w then return x0 + s, y0, 1, 0 end
  s = s - w
  if s < h then return x0 + w, y0 + s, 0, 1 end
  s = s - h
  if s < w then return x0 + w - s, y0 + h, -1, 0 end
  s = s - w
  return x0, y0 + h - s, 0, -1
end

-- Where a street runs through the river it needs a bridge. Found once per plot
-- by sampling its boundary, and kept for as long as the plot and river last.
local bridgesOf = setmetatable({}, { __mode = "k" })
local function bridges(city, d)
  local cached = bridgesOf[d]
  if cached and cached.river == city.river then return cached.spans end
  local spans, open = {}, nil
  local len = 2 * (d.w + d.h)
  for s = 0, len, 8 do
    local x, y = perimeterPoint(d, s, 0)
    local wet = y >= 0 and city:riverAt(x, y)
    if wet and not open then open = s end
    if not wet and open then spans[#spans + 1] = { open - 14, s + 14 }; open = nil end
  end
  if open then spans[#spans + 1] = { open - 14, len + 14 } end
  bridgesOf[d] = { river = city.river, spans = spans }
  return spans
end

local function drawBridges(city, cam, d)
  for _, span in ipairs(bridges(city, d)) do
    local ax, ay, dx, dy = perimeterPoint(d, span[1], 0)
    local bx, by = perimeterPoint(d, span[2], 0)
    local sax, say = cam:toScreen(ax, ay)
    local sbx, sby = cam:toScreen(bx, by)
    local deck = px(18, cam.scale, 3)
    lg.setColor(0, 0, 0, 0.35); lg.setLineWidth(deck + 4)
    lg.line(sax + 2, say + 3, sbx + 2, sby + 3)
    lg.setColor(0.30, 0.31, 0.33, 1); lg.setLineWidth(deck)
    lg.line(sax, say, sbx, sby)
    if deck > 6 then
      -- Parapets either side.
      local nx, ny = -dy * deck / 2, dx * deck / 2
      lg.setColor(0.62, 0.62, 0.60, 1); lg.setLineWidth(math.max(1, deck * 0.12))
      lg.line(sax + nx, say + ny, sbx + nx, sby + ny)
      lg.line(sax - nx, say - ny, sbx - nx, sby - ny)
    end
  end
end

-- A car, van, truck or bus seen from above, pointing along (dx, dy).
local function vehicle(kind, x, y, dx, dy, scale, colour)
  local len = kind == "truck" and 17 or kind == "bus" and 19 or kind == "van" and 11 or 9
  local wid = kind == "truck" and 5.4 or kind == "bus" and 5.6 or 4.6
  local L, W = px(len * 1.5, scale, 2.5), px(wid * 1.5, scale, 1.4)
  lg.push(); lg.translate(x, y); lg.rotate(math.atan2(dy, dx))
  lg.setColor(0, 0, 0, 0.28); lg.rectangle("fill", -L / 2 + 1, -W / 2 + 1.2, L, W, W * 0.3)
  if kind == "truck" then
    -- Trailer, then the cab ahead of it.
    lg.setColor(0.64, 0.62, 0.56); lg.rectangle("fill", -L / 2, -W / 2, L * 0.72, W, W * 0.12)
    lg.setColor(colour); lg.rectangle("fill", L * 0.26, -W / 2, L * 0.24, W, W * 0.25)
  elseif kind == "bus" then
    lg.setColor(0.95, 0.76, 0.30); lg.rectangle("fill", -L / 2, -W / 2, L, W, W * 0.2)
    if L > 10 then
      lg.setColor(0.18, 0.24, 0.30)
      for i = 0, 4 do lg.rectangle("fill", -L / 2 + L * (0.1 + i * 0.17), -W / 2, L * 0.1, W * 0.22) end
    end
  else
    lg.setColor(colour); lg.rectangle("fill", -L / 2, -W / 2, L, W, W * 0.35)
    if L > 7 then
      -- Windscreen and roof.
      lg.setColor(0.14, 0.20, 0.26, 0.9); lg.rectangle("fill", L * 0.08, -W * 0.36, L * 0.16, W * 0.72)
      lg.setColor(1, 1, 1, 0.16); lg.rectangle("fill", -L * 0.22, -W * 0.3, L * 0.3, W * 0.6)
    end
  end
  lg.pop()
end

local function person(x, y, scale, coat, t, phase)
  local r = px(4, scale, 1.5)
  local bob = math.sin(t * 9 + phase) * r * 0.25
  lg.setColor(0, 0, 0, 0.3); lg.circle("fill", x + r * 0.5, y + r * 0.7, r)
  lg.setColor(coat); lg.circle("fill", x, y + bob, r)
  if r >= 1.6 then lg.setColor(0.93, 0.80, 0.66); lg.circle("fill", x, y + bob - r * 0.2, r * 0.5) end
end

local function drawStreets(city, cam, visible, t)
  if cam.scale < 0.22 then return end
  for _, d in ipairs(city.districts or {}) do
    if not d.island and visible(d) and d.y >= 0 and cam:seesBox(d.x - 30, d.y - 30, d.x + d.w + 30, d.y + d.h + 30) then
      drawBridges(city, cam, d)
      local id = d.id or (d.col or 0) * 31 + (d.row or 0)
      local len = 2 * (d.w + d.h - 8 * 2)
      -- Owned ground is where the company's customers live: busy. Next door is
      -- quiet country.
      local count = math.floor(len / (d.owned and 230 or 700))
      local speed = 46 + 10 * hash(id, 1)
      for i = 1, count do
        local s = (i + 0.35 * hash(id, i, 2)) * len / count + t * speed
        local x, y, dx, dy = perimeterPoint(d, s, 5)
        if cam:sees(x, y, 20) then
          local roll = hash(id, i, 3)
          local kind = roll < 0.13 and "truck" or roll < 0.18 and "bus" or roll < 0.3 and "van" or "car"
          local sx, sy = cam:toScreen(x, y)
          vehicle(kind, sx, sy, dx, dy, cam.scale, CAR_COLOURS[math.floor(hash(id, i, 4) * #CAR_COLOURS) + 1])
        end
      end
      if cam.scale > 0.55 then
        -- Pavements: slow, both ways, keeping to the kerb of the plot.
        local walkers = math.floor(len / (d.owned and 160 or 600))
        for i = 1, walkers do
          local dir = hash(id, i, 5) < 0.5 and 1 or -1
          local s = i * len / walkers + dir * t * (7 + 4 * hash(id, i, 6))
          local x, y = perimeterPoint(d, s, 10.5)
          if cam:sees(x, y, 10) then
            local sx, sy = cam:toScreen(x, y)
            person(sx, sy, cam.scale, COATS[math.floor(hash(id, i, 7) * #COATS) + 1], t, i)
          end
        end
      end
    end
  end
end

--------------------------------------------------------------------------------
-- Neighbours. Each customer has a friend in the nearest house, and somebody is
-- always walking over for a cup of something. Neighbours are found through a
-- bucket grid and kept until the customer count changes.
--------------------------------------------------------------------------------

local neighbourCache = setmetatable({}, { __mode = "k" })
local BUCKET = 300
local function neighbours(city)
  local list = city:clientList()
  local cached = neighbourCache[city]
  if cached and cached.n == #list then return cached.pairs end
  local grid = {}
  for _, c in ipairs(list) do
    local k = math.floor(c.x / BUCKET) * 65536 + math.floor(c.y / BUCKET)
    grid[k] = grid[k] or {}; table.insert(grid[k], c)
  end
  local out = {}
  for _, c in ipairs(list) do
    local bx, by = math.floor(c.x / BUCKET), math.floor(c.y / BUCKET)
    local best, bestD
    for gx = bx - 1, bx + 1 do
      for gy = by - 1, by + 1 do
        for _, o in ipairs(grid[gx * 65536 + gy] or {}) do
          local dd = (o.x - c.x) ^ 2 + (o.y - c.y) ^ 2
          if o ~= c and dd > 30 * 30 and (not bestD or dd < bestD) then best, bestD = o, dd end
        end
      end
    end
    if best then out[#out + 1] = { c, best } end
  end
  neighbourCache[city] = { n = #list, pairs = out }
  return out
end

local function drawNeighbours(city, cam, t)
  if cam.scale < 0.55 then return end
  for _, pair in ipairs(neighbours(city)) do
    local a, b = pair[1], pair[2]
    if cam:seesBox(math.min(a.x, b.x), math.min(a.y, b.y), math.max(a.x, b.x), math.max(a.y, b.y), 20) then
      local dx, dy = b.x - a.x, b.y - a.y
      local len = math.sqrt(dx * dx + dy * dy)
      -- Out, a pause at the door, back, a pause at home. Starting a little
      -- clear of each building so nobody walks through a wall.
      local walk = len / 8
      local cycle = walk * 2 + 12
      local k = (t + hash(a.id, b.id) * cycle) % cycle
      local f
      if k < walk then f = k / walk
      elseif k < walk + 6 then f = 1
      elseif k < walk * 2 + 6 then f = 1 - (k - walk - 6) / walk
      else f = 0 end
      local clear = math.min(0.45, 22 / len)
      f = clear + f * (1 - clear * 2)
      -- A little meander so the path is not a ruler line.
      local side = math.sin(f * math.pi) * math.min(12, len * 0.08) * (hash(a.id, 9) < 0.5 and 1 or -1)
      local x, y = a.x + dx * f - dy / len * side, a.y + dy * f + dx / len * side
      local sx, sy = cam:toScreen(x, y)
      person(sx, sy, cam.scale, COATS[a.id % #COATS + 1], t, a.id)
    end
  end
end

--------------------------------------------------------------------------------
-- The river carries barges both ways, the sea carries ships along the coast.
--------------------------------------------------------------------------------

local riverLengths = setmetatable({}, { __mode = "k" })
local function lengths(p)
  local cum = riverLengths[p]
  if cum then return cum end
  cum = { 0 }
  for i = 2, p.n do cum[i] = cum[i - 1] + math.sqrt((p.x[i] - p.x[i - 1]) ^ 2 + (p.y[i] - p.y[i - 1]) ^ 2) end
  riverLengths[p] = cum
  return cum
end

local function along(p, cum, s)
  local lo, hi = 1, p.n
  while hi - lo > 1 do
    local mid = math.floor((lo + hi) / 2)
    if cum[mid] <= s then lo = mid else hi = mid end
  end
  local seg = math.max(1e-6, cum[hi] - cum[lo])
  local f = math.max(0, math.min(1, (s - cum[lo]) / seg))
  local x = p.x[lo] + (p.x[hi] - p.x[lo]) * f
  local y = p.y[lo] + (p.y[hi] - p.y[lo]) * f
  local hw = p.hw[lo] + (p.hw[hi] - p.hw[lo]) * f
  return x, y, (p.x[hi] - p.x[lo]) / seg, (p.y[hi] - p.y[lo]) / seg, hw
end

local function boat(kind, x, y, dx, dy, scale, t, phase)
  local L = px(kind == "ship" and 110 or kind == "sail" and 34 or 50, scale, 5)
  local W = L * (kind == "ship" and 0.2 or kind == "sail" and 0.36 or 0.3)
  lg.push(); lg.translate(x, y); lg.rotate(math.atan2(dy, dx))
  -- The wake: two lines opening out behind, shimmering.
  local shimmer = 0.5 + 0.5 * math.sin(t * 3 + phase)
  lg.setColor(0.85, 0.93, 1, 0.18 + 0.1 * shimmer); lg.setLineWidth(math.max(1, W * 0.14))
  lg.line(-L * 0.45, -W * 0.3, -L * 1.6, -W * 1.5)
  lg.line(-L * 0.45, W * 0.3, -L * 1.6, W * 1.5)
  lg.setColor(0, 0, 0, 0.3)
  lg.polygon("fill", -L / 2 + 2, -W / 2 + 2, L * 0.3 + 2, -W / 2 + 2, L / 2 + 2, 2, L * 0.3 + 2, W / 2 + 2, -L / 2 + 2, W / 2 + 2)
  if kind == "sail" then
    lg.setColor(0.93, 0.93, 0.90)
    lg.polygon("fill", -L / 2, -W / 2, L * 0.25, -W / 2, L / 2, 0, L * 0.25, W / 2, -L / 2, W / 2)
    lg.setColor(0.98, 0.98, 0.96); lg.polygon("fill", -L * 0.1, 0, L * 0.25, -W * 0.1, -L * 0.2, -W * 1.1)
  else
    lg.setColor(kind == "ship" and { 0.62, 0.20, 0.18 } or { 0.26, 0.30, 0.34 })
    lg.polygon("fill", -L / 2, -W / 2, L * 0.3, -W / 2, L / 2, 0, L * 0.3, W / 2, -L / 2, W / 2)
    if kind == "ship" then
      -- Containers in rows, the bridge aft.
      local cols = { { 0.30, 0.52, 0.86 }, { 0.95, 0.76, 0.30 }, { 0.36, 0.66, 0.46 }, { 0.86, 0.30, 0.28 } }
      for i = 0, 5 do
        lg.setColor(cols[(i + phase) % #cols + 1])
        lg.rectangle("fill", -L * 0.3 + i * L * 0.1, -W * 0.36, L * 0.085, W * 0.72)
      end
      lg.setColor(0.92, 0.92, 0.90); lg.rectangle("fill", -L * 0.44, -W * 0.34, L * 0.1, W * 0.68)
    else
      lg.setColor(0.86, 0.66, 0.36); lg.rectangle("fill", -L * 0.34, -W * 0.3, L * 0.5, W * 0.6)
      lg.setColor(0.92, 0.92, 0.90); lg.rectangle("fill", -L * 0.46, -W * 0.28, L * 0.1, W * 0.56)
    end
  end
  lg.pop()
end

local function drawWater(city, cam, t)
  if cam.scale < 0.14 then return end
  local p = city:riverPath()
  if p and p.n and p.n > 2 then
    local cum = lengths(p)
    local total = cum[p.n]
    local count = math.max(2, math.floor(total / 900))
    for i = 1, count do
      local up = i % 2 == 0
      local speed = up and 16 or 24
      local s = (i / count * total + (up and -1 or 1) * t * speed) % total
      local x, y, dx, dy, hw = along(p, cum, s)
      if hw > 30 and cam:sees(x, y, 60) then
        local off = hw * 0.38 * (up and 1 or -1)
        -- Upstream is toward higher sample index; the channel's normal is (-dy, dx).
        local bx, by = x - dy * off, y + dx * off
        if not up then dx, dy = -dx, -dy end
        local sx, sy = cam:toScreen(bx, by)
        boat(hash(i, 3) < 0.4 and "sail" or "barge", sx, sy, dx, dy, cam.scale, t, i)
      end
    end
  end
  -- Coastal shipping, well out from the beach.
  local b = city.bounds
  for i = 1, 4 do
    local dir = i % 2 == 0 and -1 or 1
    local lane = -260 - 420 * hash(i, 11)
    local span = b.w + 2400
    local x = b.x - 1200 + ((hash(i, 12) * span + dir * t * (i == 1 and 28 or 18)) % span)
    local y = lane + math.sin(t * 0.05 + i) * 30
    if cam:sees(x, y, 120) then
      local d = city:districtAt(x, y)
      if not (d and d.island) then
        local sx, sy = cam:toScreen(x, y)
        boat(i <= 2 and "ship" or "sail", sx, sy, dir, 0, cam.scale, t, i)
      end
    end
  end
end

--------------------------------------------------------------------------------
-- Crews. A company that pays for crews sees them: a van at each of the worst
-- leaks, beacon turning, somebody in hi-vis walking the main.
--------------------------------------------------------------------------------

local function drawCrews(city, cam, t)
  local crews = city.crews or 0
  if crews <= 0 then return end
  local leaks = {}
  for _, e in ipairs(city.g.edges) do
    if e.alive and e.leaking then leaks[#leaks + 1] = { e = e, cost = city:repairCost(e) } end
  end
  table.sort(leaks, function(a, b) return a.cost > b.cost end)
  for i = 1, math.min(crews, #leaks) do
    local e = leaks[i].e
    local na, nb = city.g.nodes[e.a], city.g.nodes[e.b]
    if na and nb then
      local mx, my = (na.x + nb.x) / 2, (na.y + nb.y) / 2
      if cam:sees(mx, my, 40) then
        local dx, dy = nb.x - na.x, nb.y - na.y
        local len = math.max(1, math.sqrt(dx * dx + dy * dy))
        local nx, ny = -dy / len, dx / len
        local vx, vy = cam:toScreen(mx + nx * 14, my + ny * 14)
        vehicle("van", vx, vy, dx, dy, cam.scale, { 0.98, 0.62, 0.22 })
        local beacon = (t * 2.5 + i) % 1 < 0.5
        lg.setColor(1, 0.75, 0.2, beacon and 0.95 or 0.25)
        lg.circle("fill", vx, vy, px(2, cam.scale, 1.5))
        if beacon then lg.setColor(1, 0.75, 0.2, 0.18); lg.circle("fill", vx, vy, px(9, cam.scale, 4)) end
        if cam.scale > 0.45 then
          local w = math.sin(t * 0.7 + i) * 10
          local wx, wy = cam:toScreen(mx + dx / len * w, my + dy / len * w)
          person(wx, wy, cam.scale, { 0.98, 0.62, 0.22 }, t, i)
        end
      end
    end
  end
end

--------------------------------------------------------------------------------
-- Overhead: birds wheeling over woods, airliners crossing the whole map.
--------------------------------------------------------------------------------

local function drawBirds(city, cam, t)
  if cam.scale < 0.3 then return end
  for _, o in ipairs(city.obstacles or {}) do
    if o.kind == "park" and not o.cleared and (o.r or 0) > 60 and cam:sees(o.x, o.y, o.r * cam.scale) then
      local flock = 3 + math.floor(hash(o.x, o.y, 1) * 4)
      local orbit = o.r * (0.35 + 0.3 * hash(o.x, o.y, 2))
      local spin = (hash(o.x, o.y, 3) < 0.5 and 1 or -1) * (0.12 + 0.06 * hash(o.x, o.y, 4))
      for i = 1, flock do
        local a = t * spin + i * 0.22 + hash(o.x, o.y, 5) * 6.28
        local rr = orbit + math.sin(t * 0.8 + i) * 8
        local sx, sy = cam:toScreen(o.x + math.cos(a) * rr, o.y + math.sin(a) * rr * 0.7)
        local span = px(5, cam.scale, 2)
        local flap = math.sin(t * 11 + i * 1.7) * span * 0.45
        lg.setColor(0.08, 0.10, 0.10, 0.85); lg.setLineWidth(math.max(1, span * 0.28))
        lg.line(sx - span, sy - flap, sx, sy, sx + span, sy - flap)
      end
    end
  end
end

local function plane(x, y, dx, dy, s)
  lg.push(); lg.translate(x, y); lg.rotate(math.atan2(dy, dx))
  lg.rectangle("fill", -s * 0.5, -s * 0.06, s, s * 0.12, s * 0.06)
  lg.polygon("fill", s * 0.08, 0, -s * 0.12, -s * 0.5, -s * 0.2, -s * 0.5, -s * 0.06, 0, -s * 0.2, s * 0.5, -s * 0.12, s * 0.5)
  lg.polygon("fill", -s * 0.38, 0, -s * 0.48, -s * 0.2, -s * 0.52, -s * 0.2, -s * 0.46, 0, -s * 0.52, s * 0.2, -s * 0.48, s * 0.2)
  lg.pop()
end

-- Flight paths cross the company's own ground, where the player is looking,
-- rather than the middle of the surveyed map.
local function home(city)
  local x, y, n = 0, 0, 0
  for _, d in ipairs(city.districts or {}) do
    if d.owned then x, y, n = x + d.x + d.w / 2, y + d.y + d.h / 2, n + 1 end
  end
  if n == 0 then local b = city.bounds; return b.x + b.w / 2, b.y + b.h / 2 end
  return x / n, y / n
end

local function drawPlanes(city, cam, t)
  local cx, cy = home(city)
  local reach = 6000
  local seed = (city.river and city.river.meander or 7) % 1000
  for i = 1, 4 do
    local ang = hash(seed, i, 21) * math.pi * 2
    local dx, dy = math.cos(ang), math.sin(ang)
    local ox = cx + (hash(seed, i, 22) - 0.5) * 1600
    local oy = cy + (hash(seed, i, 23) - 0.5) * 1000
    local speed = 240
    local flight = reach * 2 / speed
    local cycle = flight + 20 + 60 * hash(seed, i, 24)
    local k = (t + hash(seed, i, 25) * cycle) % cycle
    if k < flight then
      local s = -reach + k * speed
      local x, y = ox + dx * s, oy + dy * s
      local size = px(46, cam.scale, 10)
      if cam:sees(x, y, size * 6) then
        -- Contrail: two faint lines streaming back from the engines.
        local sx, sy = cam:toScreen(x, y)
        local trail = math.min(k * speed, 900) * cam.scale
        local nx, ny = -dy * size * 0.18, dx * size * 0.18
        lg.setLineWidth(math.max(1, size * 0.06))
        for q = 0, 5 do
          local a0, a1 = q / 6 * trail, (q + 1) / 6 * trail
          lg.setColor(1, 1, 1, 0.16 * (1 - q / 6))
          lg.line(sx + nx - dx * a0, sy + ny - dy * a0, sx + nx - dx * a1, sy + ny - dy * a1)
          lg.line(sx - nx - dx * a0, sy - ny - dy * a0, sx - nx - dx * a1, sy - ny - dy * a1)
        end
        -- Shadow far below and to the side: it is high up.
        lg.setColor(0, 0, 0, 0.22); plane(sx + size * 1.6, sy + size * 2.4, dx, dy, size)
        lg.setColor(0.93, 0.94, 0.95, 0.95); plane(sx, sy, dx, dy, size)
        lg.setColor(0.86, 0.30, 0.28, 0.9)
        lg.circle("fill", sx - dx * size * 0.48, sy - dy * size * 0.48, math.max(1, size * 0.05))
      end
    end
  end
end

-- Under the buildings: streets, water, neighbours, crews.
function Traffic.ground(city, cam, visible)
  local t = R.t or 0
  drawWater(city, cam, t)
  drawStreets(city, cam, visible, t)
  drawNeighbours(city, cam, t)
  drawCrews(city, cam, t)
end

-- Over everything on the ground: birds, then aircraft.
function Traffic.air(city, cam)
  local t = R.t or 0
  drawBirds(city, cam, t)
  drawPlanes(city, cam, t)
end

Traffic._hash, Traffic._perimeterPoint = hash, perimeterPoint
return Traffic
