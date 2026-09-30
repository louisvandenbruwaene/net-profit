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
local City = require("city")

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
  { 0.62, 0.30, 0.28 }, { 0.26, 0.36, 0.52 }, { 0.72, 0.62, 0.40 }, { 0.70, 0.70, 0.68 },
  { 0.34, 0.46, 0.36 }, { 0.44, 0.34, 0.48 }, { 0.22, 0.24, 0.28 }, { 0.58, 0.46, 0.34 },
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

-- A person seen from above: legs stepping under a coat, shoulders across the
-- way they walk, a head of hair. Muted colours, so a crowd reads as people
-- and not confetti. Far out they are a single soft dot.
local HAIR = { { 0.20, 0.14, 0.10 }, { 0.42, 0.28, 0.16 }, { 0.78, 0.64, 0.38 }, { 0.10, 0.10, 0.11 }, { 0.62, 0.62, 0.60 } }
local function person(x, y, dx, dy, scale, coat, t, phase, still)
  local r = px(4.2, scale, 1.1)
  if r < 1.8 then
    lg.setColor(coat[1], coat[2], coat[3], 0.9); lg.circle("fill", x, y, 1.2)
    return
  end
  lg.push(); lg.translate(x, y); lg.rotate(math.atan2(dy, dx))
  lg.setColor(0, 0, 0, 0.22); lg.ellipse("fill", r * 0.35, r * 0.55, r * 0.9, r * 1.05)
  local stride = still and 0 or math.sin(t * 7 + phase) * r * 0.55
  -- Legs: two dark strokes, one ahead and one behind.
  lg.setColor(0.18, 0.19, 0.22)
  lg.ellipse("fill", stride, -r * 0.32, r * 0.42, r * 0.22)
  lg.ellipse("fill", -stride, r * 0.32, r * 0.42, r * 0.22)
  -- Shoulders and coat, arms swinging opposite the legs.
  lg.setColor(coat[1] * 0.8, coat[2] * 0.8, coat[3] * 0.8)
  lg.ellipse("fill", -stride * 0.5, -r * 0.78, r * 0.3, r * 0.2)
  lg.ellipse("fill", stride * 0.5, r * 0.78, r * 0.3, r * 0.2)
  lg.setColor(coat); lg.ellipse("fill", 0, 0, r * 0.5, r * 0.8)
  lg.setColor(0, 0, 0, 0.35); lg.setLineWidth(math.max(0.6, r * 0.12)); lg.ellipse("line", 0, 0, r * 0.5, r * 0.8)
  local hair = HAIR[phase % #HAIR + 1]
  lg.setColor(hair); lg.circle("fill", r * 0.05, 0, r * 0.42)
  lg.setColor(0.90, 0.76, 0.62); lg.circle("fill", r * 0.22, 0, r * 0.18)
  lg.pop()
end

--------------------------------------------------------------------------------
-- Where people may walk. The pavement runs along each plot just inside its
-- edge, and is cut wherever something stands on it: the river, a wood, rough
-- ground, a building. Walkers keep to one clear stretch and turn at its ends.
-- A building's front path, door to kerb, is walked only if it is clear too.
-- Both are worked out once per change to the company and kept.
--------------------------------------------------------------------------------

local PAVE = 8.5
local walkCache = setmetatable({}, { __mode = "k" })

local function walkData(city)
  local rev = city.revision or 0
  local w = walkCache[city]
  if w and w.rev == rev and w.nodes == #city.g.nodes then return w end
  w = { rev = rev, nodes = #city.g.nodes, runs = {}, doors = {} }
  -- Buildings in a coarse grid, so a sample asks only its neighbours.
  local grid = {}
  for _, n in ipairs(city.g.nodes) do
    if n.alive and n.kind ~= "corner" then
      local k = math.floor(n.x / 60) * 65536 + math.floor(n.y / 60)
      grid[k] = grid[k] or {}; table.insert(grid[k], n)
    end
  end
  w.grid = grid
  walkCache[city] = w
  return w
end

-- Is this spot open ground a person could stand on? `except` is the building
-- whose own door the path leaves from.
local function standable(city, w, x, y, except)
  if y < 0 then return false end
  if city:obstacleAt(x, y) then return false end
  local gx, gy = math.floor(x / 60), math.floor(y / 60)
  for ix = gx - 1, gx + 1 do
    for iy = gy - 1, gy + 1 do
      for _, n in ipairs(w.grid[ix * 65536 + iy] or {}) do
        if n ~= except then
          local body = n.kind == "client" and (City.PROJECT_BY and City.PROJECT_BY[n.clientType or ""] and 34 or 22) or 16
          if (n.x - x) ^ 2 + (n.y - y) ^ 2 < body * body then return false end
        end
      end
    end
  end
  return true
end

-- The clear stretches of one plot's pavement, as {a, b} along its perimeter.
local function pavementRuns(city, d)
  local w = walkData(city)
  local key = d.id or ((d.col or 0) * 131 + (d.row or 0))
  if w.runs[key] then return w.runs[key] end
  local runs, open = {}, nil
  local len = 2 * (d.w + d.h - PAVE * 4)
  for s = 0, len, 6 do
    local x, y = perimeterPoint(d, s, PAVE)
    local ok = standable(city, w, x, y)
    if ok and not open then open = s end
    if not ok and open then
      if s - open >= 40 then runs[#runs + 1] = { open, s - 6 } end
      open = nil
    end
  end
  if open and len - open >= 40 then runs[#runs + 1] = { open, len } end
  w.runs[key] = runs
  return runs
end

-- A building's way out: its door, the kerb straight across from it on its
-- own plot's nearest edge, and the pavement run that kerb lands on. Nil if
-- anything stands between.
local function frontPath(city, n)
  local w = walkData(city)
  local cached = w.doors[n.id]
  if cached ~= nil then return cached or nil end
  local d = city:districtAt(n.x, n.y)
  local result = false
  if d and not d.island then
    local sides = {
      { dist = n.y - d.y, kx = n.x, ky = d.y + PAVE },
      { dist = d.y + d.h - n.y, kx = n.x, ky = d.y + d.h - PAVE },
      { dist = n.x - d.x, kx = d.x + PAVE, ky = n.y },
      { dist = d.x + d.w - n.x, kx = d.x + d.w - PAVE, ky = n.y },
    }
    table.sort(sides, function(a, b) return a.dist < b.dist end)
    local side = sides[1]
    if side.dist < 260 then
      local dx, dy = side.kx - n.x, side.ky - n.y
      local len = math.sqrt(dx * dx + dy * dy)
      local clear = true
      for k = 18, len, 6 do
        local x, y = n.x + dx * k / len, n.y + dy * k / len
        if not standable(city, w, x, y, n) then clear = false; break end
      end
      if clear and standable(city, w, side.kx, side.ky, n) then
        result = { dx = n.x, dy = n.y, kx = side.kx, ky = side.ky, len = len }
      end
    end
  end
  w.doors[n.id] = result
  return result or nil
end

local function tri(v) v = v % 2; return v < 1 and v or 2 - v end

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
        -- Pavement walkers, each pacing one clear stretch end to end.
        for r, run in ipairs(pavementRuns(city, d)) do
          local span = run[2] - run[1]
          local walkers = math.max(1, math.floor(span / (d.owned and 150 or 500)))
          for i = 1, walkers do
            local speed = 6 + 4 * hash(id, r * 37 + i, 6)
            local v = (t * speed + hash(id, r * 37 + i, 5) * 2 * span) / span
            local f = tri(v)
            local s = run[1] + f * span
            local x, y, dx, dy = perimeterPoint(d, s, PAVE)
            if cam:sees(x, y, 10) then
              local back = (v % 2) >= 1
              local sx, sy = cam:toScreen(x, y)
              person(sx, sy, back and -dx or dx, back and -dy or dy, cam.scale,
                COATS[math.floor(hash(id, r * 37 + i, 7) * #COATS) + 1], t, r * 7 + i)
            end
          end
        end
      end
    end
  end
end

--------------------------------------------------------------------------------
-- Residents. Now and then somebody leaves a building by its front path, walks
-- to the kerb, and comes back. Only where that path is clear.
--------------------------------------------------------------------------------

-- Walk a front path: out, a pause at the kerb, back, a long spell indoors.
local function frontWalker(cam, path, t, seed, coat, phase, cycle)
  local walk = path.len / 7
  cycle = cycle or walk * 2 + 30
  local k = (t + seed * cycle) % cycle
  local f, out
  if k < walk then f, out = k / walk, true
  elseif k < walk + 4 then f = 1
  elseif k < walk * 2 + 4 then f, out = 1 - (k - walk - 4) / walk, false
  else return end
  local ddx, ddy = path.kx - path.dx, path.ky - path.dy
  local x, y = path.dx + ddx * f, path.dy + ddy * f
  if not cam:sees(x, y, 10) then return end
  local sx, sy = cam:toScreen(x, y)
  if out == nil then person(sx, sy, ddx, ddy, cam.scale, coat, t, phase, true)
  else person(sx, sy, out and ddx or -ddx, out and ddy or -ddy, cam.scale, coat, t, phase) end
end

local function drawResidents(city, cam, t)
  if cam.scale < 0.55 then return end
  for _, c in ipairs(city:clientList()) do
    if not c.shop and cam:sees(c.x, c.y, 120 * cam.scale) then
      local path = frontPath(city, c)
      if path then
        frontWalker(cam, path, t, hash(c.id, 3), COATS[c.id % #COATS + 1], c.id)
      end
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
          person(wx, wy, dx / len * math.cos(t * 0.7 + i), dy / len * math.cos(t * 0.7 + i) + 1e-3, cam.scale, { 0.98, 0.62, 0.22 }, t, i)
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

--------------------------------------------------------------------------------
-- Shoppers. Round each shop, the street carries as many walkers as really
-- passed it today, and the ones who went in walk from the kerb to the door.
--------------------------------------------------------------------------------

local function drawShoppers(city, cam, t)
  if cam.scale < 0.45 or not city.shops then return end
  for _, n in ipairs(city:shops()) do
    if cam:sees(n.x, n.y, 260 * cam.scale) then
      local path = frontPath(city, n)
      local served = city:shopServed(n) or 0
      if path then
        -- Customers go in by the front path and come out again, each on
        -- their own clock; the busier the day, the more of them.
        local inside = math.min(10, math.ceil(served / 5))
        for i = 1, inside do
          frontWalker(cam, path, t, hash(n.id, i, 42), COATS[math.floor(hash(n.id, i, 44) * #COATS) + 1],
            n.id + i, path.len / 7 * 2 + 6 + 6 * hash(n.id, i, 41))
        end
        -- The street in front carries the crowd that passed today, on the
        -- clear stretch the kerb lands on.
        local d = city:districtAt(n.x, n.y)
        if d then
          for _, run in ipairs(pavementRuns(city, d)) do
            local span = run[2] - run[1]
            local extra = math.min(16, math.ceil((n.passing or 0) / 10))
            for i = 1, extra do
              local speed = 7 + 4 * hash(n.id, i, 32)
              local v = (t * speed + hash(n.id, i, 31) * 2 * span) / span
              local s = run[1] + tri(v) * span
              local x, y, dx, dy = perimeterPoint(d, s, PAVE)
              if (x - path.kx) ^ 2 + (y - path.ky) ^ 2 < 280 * 280 and cam:sees(x, y, 10) then
                local back = (v % 2) >= 1
                local sx, sy = cam:toScreen(x, y)
                person(sx, sy, back and -dx or dx, back and -dy or dy, cam.scale,
                  COATS[math.floor(hash(n.id, i, 34) * #COATS) + 1], t, n.id + i)
              end
            end
          end
        end
      end
    end
  end
end

-- Under the buildings: streets, water, neighbours, shoppers, crews.
function Traffic.ground(city, cam, visible)
  local t = R.t or 0
  drawWater(city, cam, t)
  drawStreets(city, cam, visible, t)
  drawResidents(city, cam, t)
  drawShoppers(city, cam, t)
  drawCrews(city, cam, t)
end

-- Over everything on the ground: birds, then aircraft.
function Traffic.air(city, cam)
  local t = R.t or 0
  drawBirds(city, cam, t)
  drawPlanes(city, cam, t)
end

Traffic._hash, Traffic._perimeterPoint, Traffic._frontPath = hash, perimeterPoint, frontPath
return Traffic
