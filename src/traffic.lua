-- traffic.lua -- everything that moves on the map, and only for a reason.
--
-- Nothing here is scenery. Every vehicle is one the company's own day put
-- there, and every person lives in a building on the map:
--   * cars, vans, trucks and buses drive the roads the player laid, as many
--     as the day's trips used that road (`city.transit.byLink`), each in its
--     own lane;
--   * freight lines carry their day's flow: trucks on a trucking line, a
--     train on rail, a ship on a sea lane, a freighter on an air lane;
--   * a harbour sees a ship come in only on a day it lands cargo, a road
--     head sees lorries (company_render), an air apron a freighter;
--   * ferries and airliners run only on routes that carried passengers, and
--     an airport project brings flights only while it is supplied;
--   * people walk out of the houses, shops and works they live and work in,
--     onto the pavement of a road beside them if there is one, or round
--     their own garden if not. Never on a carriageway, never through water
--     or a building. More of them as the district's population grows.
--
-- Positions are functions of R.t and of hashes of things that exist, so
-- nothing is saved, nothing reads City:random(), and a frame is repeatable.
local R = require("render")
local City = require("city")
local Graph = require("graph")
local Shape = require("terrain_shape")
local ShopData = require("data.shops")

local Traffic = {}
local lg = love and love.graphics

local function hash(a, b, c)
  local v = math.sin(a * 12.9898 + b * 78.233 + (c or 0) * 37.719) * 43758.5453
  return v - math.floor(v)
end

-- Sized like the buildings (R.sym), so traffic stays readable next to them
-- when the camera pulls back, with a floor so nothing shrinks to grit.
local function px(base, scale, floor) return math.max(floor or 1, R.sym(base, scale)) end

local function ease(f) return f * f * (3 - 2 * f) end

local CAR_COLOURS = {
  { 0.86, 0.30, 0.28 }, { 0.92, 0.88, 0.80 }, { 0.30, 0.52, 0.86 }, { 0.20, 0.22, 0.26 },
  { 0.95, 0.76, 0.30 }, { 0.55, 0.60, 0.64 }, { 0.36, 0.66, 0.46 },
}
local COATS = {
  { 0.62, 0.30, 0.28 }, { 0.26, 0.36, 0.52 }, { 0.72, 0.62, 0.40 }, { 0.70, 0.70, 0.68 },
  { 0.34, 0.46, 0.36 }, { 0.44, 0.34, 0.48 }, { 0.22, 0.24, 0.28 }, { 0.58, 0.46, 0.34 },
}

local function cargoColour(key)
  local spec = Graph.COMMODITIES[key or ""]
  return spec and spec.color or { 0.55, 0.60, 0.64 }
end

--------------------------------------------------------------------------------
-- Drawing: road vehicles, people, boats, aircraft
--------------------------------------------------------------------------------

-- A car, van, truck, semi or bus seen from above, pointing along (dx, dy).
-- `load` colours a truck's or semi's trailer with what it carries.
local function vehicle(kind, x, y, dx, dy, scale, colour, load)
  local len = kind == "semi" and 24 or kind == "truck" and 17 or kind == "bus" and 19 or kind == "van" and 11 or 9
  local wid = (kind == "truck" or kind == "semi") and 5.4 or kind == "bus" and 5.6 or 4.6
  local L, W = px(len * 1.5, scale, 2.5), px(wid * 1.5, scale, 1.4)
  lg.push(); lg.translate(x, y); lg.rotate(math.atan2(dy, dx))
  lg.setColor(0, 0, 0, 0.28); lg.rectangle("fill", -L / 2 + 1, -W / 2 + 1.2, L, W, W * 0.3)
  if kind == "truck" or kind == "semi" then
    -- Trailer, then the cab ahead of it; a semi's trailer is longer, with a gap.
    local trailer = kind == "semi" and 0.74 or 0.72
    lg.setColor(0.64, 0.62, 0.56); lg.rectangle("fill", -L / 2, -W / 2, L * trailer, W, W * 0.12)
    if load then
      lg.setColor(load); lg.rectangle("fill", -L / 2 + L * 0.04, -W * 0.36, L * (trailer - 0.08), W * 0.72, W * 0.08)
    end
    lg.setColor(colour); lg.rectangle("fill", L * 0.28, -W / 2, L * 0.22, W, W * 0.25)
    lg.setColor(0.14, 0.20, 0.26, 0.9); lg.rectangle("fill", L * 0.42, -W * 0.38, L * 0.05, W * 0.76)
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
  -- Until a figure is big enough to read, a person is a dot in their coat.
  if r < 3.2 then
    lg.setColor(coat[1], coat[2], coat[3], 0.95); lg.circle("fill", x, y, math.max(1.2, r * 0.5), 6)
    return
  end
  lg.push(); lg.translate(x, y); lg.rotate(math.atan2(dy, dx))
  lg.setColor(0, 0, 0, 0.22); lg.ellipse("fill", r * 0.35, r * 0.55, r * 0.9, r * 1.05)
  local stride = still and 0 or math.sin(t * 7 + phase) * r * 0.55
  lg.setColor(0.18, 0.19, 0.22)
  lg.ellipse("fill", stride, -r * 0.32, r * 0.42, r * 0.22)
  lg.ellipse("fill", -stride, r * 0.32, r * 0.42, r * 0.22)
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

-- A hull from above: square stern, parallel sides, a fine bow.
local function hull(L, W, ox, oy)
  ox, oy = ox or 0, oy or 0
  return { ox - L / 2, oy - W * 0.42, ox - L * 0.47, oy - W / 2, ox + L * 0.18, oy - W / 2,
           ox + L * 0.36, oy - W * 0.36, ox + L / 2, oy, ox + L * 0.36, oy + W * 0.36,
           ox + L * 0.18, oy + W / 2, ox - L * 0.47, oy + W / 2, ox - L / 2, oy + W * 0.42 }
end

-- Wake and bow wave, in the boat's own frame, for a boat under way.
local function wake(L, W, t, phase, speed)
  if speed <= 0 then return end
  local a = math.min(1, speed)
  local shimmer = 0.5 + 0.5 * math.sin(t * 3 + phase)
  -- A churned trail straight astern, fading out.
  for i = 1, 6 do
    local f = i / 6
    lg.setColor(0.88, 0.94, 1, (0.20 - 0.03 * i) * a)
    lg.ellipse("fill", -L / 2 - f * L * 1.2, 0, L * 0.16, W * (0.22 + 0.25 * f))
  end
  -- The Kelvin wedge: two lines opening out from the stern quarters.
  lg.setColor(0.88, 0.94, 1, (0.16 + 0.08 * shimmer) * a); lg.setLineWidth(math.max(1, W * 0.10))
  lg.line(-L * 0.35, -W * 0.5, -L * 1.9, -W * 1.9)
  lg.line(-L * 0.35, W * 0.5, -L * 1.9, W * 1.9)
  -- Bow wave curling off both sides.
  lg.setColor(1, 1, 1, 0.35 * a); lg.setLineWidth(math.max(1, W * 0.12))
  lg.line(L * 0.5, 0, L * 0.30, -W * 0.62, L * 0.10, -W * 0.72)
  lg.line(L * 0.5, 0, L * 0.30, W * 0.62, L * 0.10, W * 0.72)
end

-- Boats: a container ship, a passenger ferry, a sailing yacht. Lengths are
-- world metres; `speed` 0 is moored (no wake), 1 is full ahead.
local BOAT = { ship = { 120, 20 }, ferry = { 54, 15 }, sail = { 16, 5.5 }, barge = { 64, 12 } }
local function boat(kind, x, y, dx, dy, scale, t, phase, speed, cargo)
  local spec = BOAT[kind]
  local L = math.max(kind == "sail" and 5 or 9, spec[1] * scale)
  local W = L * spec[2] / spec[1]
  lg.push(); lg.translate(x, y); lg.rotate(math.atan2(dy, dx))
  if L > 14 then wake(L, W, t, phase, speed) end
  -- Shadow on the water, then the hull.
  lg.setColor(0, 0, 0, 0.30); lg.polygon("fill", hull(L, W, 1.5, 2.5))
  if kind == "ship" then
    lg.setColor(0.52, 0.16, 0.14); lg.polygon("fill", hull(L, W))
    lg.setColor(0.30, 0.32, 0.34); lg.polygon("fill", hull(L * 0.94, W * 0.82, -L * 0.01))
    -- Containers in bays of two rows, coloured by what was landed, then the
    -- accommodation block aft with its funnel.
    local bays = L > 30 and 8 or 4
    local bw = L * 0.62 / bays
    for i = 0, bays - 1 do
      for row = 0, 1 do
        local c = cargo and #cargo > 0 and cargoColour(cargo[(i + row) % #cargo + 1]) or { 0.55, 0.58, 0.60 }
        local shade = 0.82 + 0.18 * hash(phase, i, row)
        lg.setColor(c[1] * shade, c[2] * shade, c[3] * shade)
        lg.rectangle("fill", -L * 0.26 + i * bw, -W * 0.36 + row * W * 0.37, bw * 0.9, W * 0.34)
      end
    end
    lg.setColor(0.94, 0.94, 0.92); lg.rectangle("fill", -L * 0.43, -W * 0.38, L * 0.13, W * 0.76, W * 0.08)
    lg.setColor(0.16, 0.18, 0.22); lg.rectangle("fill", -L * 0.41, -W * 0.30, L * 0.02, W * 0.6)
    lg.setColor(0.20, 0.20, 0.22); lg.circle("fill", -L * 0.465, 0, W * 0.14)
  elseif kind == "barge" then
    -- A river barge: a long open hold full of the load, a wheelhouse aft.
    lg.setColor(0.22, 0.24, 0.27); lg.polygon("fill", hull(L, W))
    local c = cargo and cargo[1] and cargoColour(cargo[1]) or { 0.40, 0.36, 0.30 }
    lg.setColor(c); lg.rectangle("fill", -L * 0.30, -W * 0.34, L * 0.62, W * 0.68, W * 0.1)
    lg.setColor(0.92, 0.92, 0.90); lg.rectangle("fill", -L * 0.46, -W * 0.30, L * 0.12, W * 0.6)
  elseif kind == "ferry" then
    lg.setColor(0.94, 0.94, 0.92); lg.polygon("fill", hull(L, W))
    lg.setColor(0.24, 0.42, 0.66); lg.polygon("fill", hull(L * 0.78, W * 0.7, -L * 0.04))
    lg.setColor(0.96, 0.96, 0.94); lg.rectangle("fill", -L * 0.30, -W * 0.25, L * 0.48, W * 0.5, W * 0.1)
    if L > 18 then
      lg.setColor(0.16, 0.22, 0.30)
      for i = 0, 5 do lg.rectangle("fill", -L * 0.27 + i * L * 0.075, -W * 0.20, L * 0.04, W * 0.4) end
    end
  else
    lg.setColor(0.96, 0.96, 0.94); lg.polygon("fill", hull(L, W))
    lg.setColor(0.62, 0.48, 0.32); lg.polygon("fill", hull(L * 0.7, W * 0.6, -L * 0.08))
    -- The sail, sheeted out to leeward of a steady westerly.
    local leeward = math.sin(math.atan2(dy, dx)) >= 0 and -1 or 1
    lg.setColor(1, 1, 1, 0.95)
    lg.polygon("fill", L * 0.18, 0, -L * 0.42, leeward * W * 0.9, -L * 0.30, leeward * W * 0.25)
    lg.setColor(0.25, 0.25, 0.25); lg.circle("fill", L * 0.18, 0, math.max(0.8, W * 0.12))
  end
  lg.pop()
end

-- An aircraft from above, nose along (dx, dy), `s` its span on screen.
local function plane(x, y, dx, dy, s, livery)
  lg.push(); lg.translate(x, y); lg.rotate(math.atan2(dy, dx))
  lg.ellipse("fill", 0, 0, s * 0.5, s * 0.065)
  lg.polygon("fill", s * 0.10, -s * 0.05, -s * 0.12, -s * 0.5, -s * 0.21, -s * 0.5, -s * 0.07, -s * 0.05,
    -s * 0.07, s * 0.05, -s * 0.21, s * 0.5, -s * 0.12, s * 0.5, s * 0.10, s * 0.05)
  lg.polygon("fill", -s * 0.36, 0, -s * 0.46, -s * 0.19, -s * 0.51, -s * 0.19, -s * 0.47, 0,
    -s * 0.51, s * 0.19, -s * 0.46, s * 0.19)
  if livery then
    local r, g, b, a = lg.getColor()
    lg.setColor(livery[1], livery[2], livery[3], a)
    lg.rectangle("fill", -s * 0.42, -s * 0.02, s * 0.8, s * 0.04)
    lg.setColor(r, g, b, a)
  end
  lg.pop()
end

-- An aircraft at `alt` (0 on the ground, 1 at cruise): a shadow that falls
-- away from it as it climbs, then the plane, a little bigger up high.
local function flying(cam, x, y, dx, dy, alt, livery, size)
  local s = px(size or 40, cam.scale, 8) * (1 + 0.25 * alt)
  local sx, sy = cam:toScreen(x, y)
  lg.setColor(0, 0, 0, 0.22 - 0.06 * alt); plane(sx + s * 1.4 * alt + 1, sy + s * 2.2 * alt + 1, dx, dy, s / (1 + 0.25 * alt))
  lg.setColor(0.94, 0.95, 0.96, 0.97); plane(sx, sy, dx, dy, s, livery)
end

--------------------------------------------------------------------------------
-- Where things can go. Built once per change to the company and kept: the
-- roads as segments with their widths, the buildings in a coarse grid, and
-- for each building the way out of its door.
--------------------------------------------------------------------------------

local CELL = 120
local geoCache = setmetatable({}, { __mode = "k" })

local function bodyOf(n)
  if n.kind == "client" then return City.PROJECT_BY and City.PROJECT_BY[n.clientType or ""] and 34 or 22 end
  if n.kind == "corner" then return 0 end
  return 16
end

local function geo(city)
  local rev, links = city.revision or 0, #(city.links or {})
  local g = geoCache[city]
  if g and g.rev == rev and g.links == links and g.nodes == #city.g.nodes then return g end
  g = { rev = rev, links = links, nodes = #city.g.nodes, roads = {}, roadGrid = {}, grid = {}, routes = {}, runs = {} }
  for _, l in ipairs(city.links or {}) do
    local na, nb = city.g.nodes[l.a], city.g.nodes[l.b]
    if l.alive and l.mode == "road" and na and nb and na.alive and nb.alive then
      local dx, dy = nb.x - na.x, nb.y - na.y
      local len = math.sqrt(dx * dx + dy * dy)
      if len > 1 then
        local kind = l.roadType or "road"
        local r = { l = l, kind = kind, ax = na.x, ay = na.y, bx = nb.x, by = nb.y, len = len,
          ux = dx / len, uy = dy / len, half = City.ROAD_WIDTH[kind] / 2,
          pave = (kind == "road" or kind == "bridge") and City.PAVEMENT or kind == "offroad" and 4 or 0 }
        g.roads[#g.roads + 1] = r
        for cx = math.floor((math.min(na.x, nb.x) - 30) / CELL), math.floor((math.max(na.x, nb.x) + 30) / CELL) do
          for cy = math.floor((math.min(na.y, nb.y) - 30) / CELL), math.floor((math.max(na.y, nb.y) + 30) / CELL) do
            local k = cx * 65536 + cy
            g.roadGrid[k] = g.roadGrid[k] or {}
            table.insert(g.roadGrid[k], r)
          end
        end
      end
    end
  end
  for _, n in ipairs(city.g.nodes) do
    if n.alive and bodyOf(n) > 0 then
      local k = math.floor(n.x / 60) * 65536 + math.floor(n.y / 60)
      g.grid[k] = g.grid[k] or {}; table.insert(g.grid[k], n)
    end
  end
  geoCache[city] = g
  return g
end

-- Distance from a point to a road's centre line, and how far along it.
local function along(r, x, y)
  local s = (x - r.ax) * r.ux + (y - r.ay) * r.uy
  local c = math.max(0, math.min(r.len, s))
  local qx, qy = r.ax + r.ux * c - x, r.ay + r.uy * c - y
  return math.sqrt(qx * qx + qy * qy), s
end

local function onCarriageway(g, x, y)
  for _, r in ipairs(g.roadGrid[math.floor(x / CELL) * 65536 + math.floor(y / CELL)] or {}) do
    if along(r, x, y) < r.half + 0.5 then return true end
  end
  return false
end

-- Open ground a person could stand on: not water, not rough ground, not a
-- carriageway, not inside a building (`except` is the one whose door it is).
local function standable(city, g, x, y, except, deck)
  -- `deck`: on a bridge's pavement, the water below is no obstacle.
  if (not deck and city:isWater(x, y)) or (not deck and city:obstacleAt(x, y)) then return false end
  if onCarriageway(g, x, y) then return false end
  local gx, gy = math.floor(x / 60), math.floor(y / 60)
  for ix = gx - 1, gx + 1 do
    for iy = gy - 1, gy + 1 do
      for _, n in ipairs(g.grid[ix * 65536 + iy] or {}) do
        if n ~= except then
          local body = bodyOf(n)
          if (n.x - x) ^ 2 + (n.y - y) ^ 2 < body * body then return false end
        end
      end
    end
  end
  return true
end

local function clear(city, g, ax, ay, bx, by, except, from)
  local dx, dy = bx - ax, by - ay
  local len = math.sqrt(dx * dx + dy * dy)
  for k = from or 0, len, 5 do
    if not standable(city, g, ax + dx * k / len, ay + dy * k / len, except) then return false end
  end
  return standable(city, g, bx, by, except)
end

-- A point on one side of a road's pavement: `side` +1 or -1.
local function pavePoint(r, s, side)
  local off = side * (r.half + r.pave / 2)
  return r.ax + r.ux * s - r.uy * off, r.ay + r.uy * s + r.ux * off
end

-- The clear stretches of one side of a road's pavement, as {a, b} along it.
-- Cut wherever something stands on it, including another road's carriageway:
-- people do not walk across junctions.
local function paveRuns(city, g, r, side)
  local key = r.l.id * 2 + (side > 0 and 1 or 0)
  if g.runs[key] then return g.runs[key] end
  local runs, open = {}, nil
  for s = 0, r.len, 5 do
    local x, y = pavePoint(r, s, side)
    local ok = standable(city, g, x, y, nil, r.kind == "bridge")
    if ok and not open then open = s end
    if not ok and open then
      if s - open >= 25 then runs[#runs + 1] = { open, s - 5 } end
      open = nil
    end
  end
  if open and r.len - open >= 25 then runs[#runs + 1] = { open, r.len } end
  g.runs[key] = runs
  return runs
end

-- A building's way out. With a road (with a pavement or verge) near, it is
-- the walk from the door straight to the pavement on this side of it, and
-- the clear stretch of pavement that lands on. Without one, a stroll out
-- into its own ground and back. False if nothing is clear at all.
-- Working a way out is a few dozen ground samples. After a change every
-- building wants one again, so only so many are worked out a frame: the rest
-- step out a moment later rather than the frame stalling.
local ROUTES_PER_FRAME = 24
local routeBudget = ROUTES_PER_FRAME
local function routeOf(city, n)
  local g = geo(city)
  local cached = g.routes[n.id]
  if cached ~= nil then return cached or nil end
  if routeBudget <= 0 then return nil end
  routeBudget = routeBudget - 1
  local body = bodyOf(n)
  local best
  for cx = math.floor(n.x / CELL) - 2, math.floor(n.x / CELL) + 2 do
    for cy = math.floor(n.y / CELL) - 2, math.floor(n.y / CELL) + 2 do
      for _, r in ipairs(g.roadGrid[cx * 65536 + cy] or {}) do
        if r.pave > 0 then
          local d, s = along(r, n.x, n.y)
          if s > 8 and s < r.len - 8 and d < 240 and (not best or d < best.d) then best = { r = r, d = d, s = s } end
        end
      end
    end
  end
  local result = false
  if best then
    local r = best.r
    local side = ((n.x - r.ax) * -r.uy + (n.y - r.ay) * r.ux) >= 0 and 1 or -1
    local kx, ky = pavePoint(r, best.s, side)
    local reach = math.sqrt((kx - n.x) ^ 2 + (ky - n.y) ^ 2)
    if reach > body * 0.8 + 4 and clear(city, g, n.x, n.y, kx, ky, n, body) then
      for _, run in ipairs(paveRuns(city, g, r, side)) do
        if best.s >= run[1] - 3 and best.s <= run[2] + 3 then
          local dx, dy = kx - n.x, ky - n.y
          local len = math.sqrt(dx * dx + dy * dy)
          result = { road = r, side = side, s = best.s, run = run, kx = kx, ky = ky,
            ox = n.x + dx / len * body * 0.8, oy = n.y + dy / len * body * 0.8, len = len - body * 0.8 }
          break
        end
      end
    end
  end
  if not result then
    for i = 0, 7 do
      local a = (hash(n.id, 1) + i / 8) * math.pi * 2
      local reach = body + 22 + 26 * hash(n.id, i, 2)
      local ox, oy = n.x + math.cos(a) * body * 0.8, n.y + math.sin(a) * body * 0.8
      local ex, ey = n.x + math.cos(a) * reach, n.y + math.sin(a) * reach
      if clear(city, g, ox, oy, ex, ey, n, 4) then
        result = { ox = ox, oy = oy, kx = ex, ky = ey, len = reach - body * 0.8 }
        break
      end
    end
  end
  g.routes[n.id] = result
  return result or nil
end

--------------------------------------------------------------------------------
-- People
--------------------------------------------------------------------------------

-- One outing: out of the door, along the pavement and back, or out into the
-- garden and back; then a long spell indoors.
local function outing(cam, rt, t, seed, coat, phase, opts)
  local v = 6 + 3 * hash(seed, 1)
  local out = rt.len / v
  local stretch, s0 = 0, rt.s
  if rt.road and not (opts and opts.noStroll) then
    local target = rt.run[1] + (rt.run[2] - rt.run[1]) * hash(seed, 2)
    stretch = target - rt.s
  end
  local walk = math.abs(stretch) / v
  local pause = (opts and opts.pause) or (2 + 6 * hash(seed, 3))
  local indoors = (opts and opts.indoors) or (6 + 26 * hash(seed, 4))
  local cycle = 2 * (out + walk) + pause + indoors
  local k = (t + hash(seed, 5) * cycle) % cycle
  local x, y, dx, dy, still
  local px0, py0, px1, py1 = rt.ox, rt.oy, rt.kx, rt.ky
  local function door(f, outward)
    x, y = px0 + (px1 - px0) * f, py0 + (py1 - py0) * f
    dx, dy = (px1 - px0) * (outward and 1 or -1), (py1 - py0) * (outward and 1 or -1)
  end
  local function pave(f, outward)
    local r = rt.road
    x, y = pavePoint(r, s0 + stretch * f, rt.side)
    local sign = (stretch >= 0 and 1 or -1) * (outward and 1 or -1)
    dx, dy = r.ux * sign, r.uy * sign
  end
  if k < out then door(k / out, true)
  elseif k < out + walk then pave((k - out) / walk, true)
  elseif k < out + walk + pause then
    if rt.road then pave(1, true) else door(1, true) end
    still = true
  elseif k < out + 2 * walk + pause then pave(1 - (k - out - walk - pause) / walk, false)
  elseif k < 2 * (out + walk) + pause then door(1 - (k - out - 2 * walk - pause) / out, false)
  else return end
  if not cam:sees(x, y, 10) then return end
  local sx, sy = cam:toScreen(x, y)
  person(sx, sy, dx, dy, cam.scale, coat, t, phase, still)
end

-- How many of a building's people are out at once: its residents, scaled by
-- how far its district has grown and by the weather.
local function outNow(city, n, d, weather)
  local res = ShopData.RESIDENTS[n.clientType or ""] or (n.kind == "client" and 3 or 2)
  if res <= 0 then res = 4 end
  local grow = 1 + math.min(2, ((d and d.population) or 0) / 450)
  local share = n.prospect and 0.25 or 0.4
  return math.max(1, math.min(10, math.floor(res * share * grow * weather + 0.5)))
end

local function drawPeople(city, cam, t)
  if cam.scale < 0.45 then return end
  -- Pulled back, fewer of each building's people are drawn: the crowd
  -- thins to what can be seen, and the frame stays in budget.
  local share = math.min(1, (cam.scale - 0.3) / 0.7)
  local w = city.weatherOn and city:weatherOn(city.day or 1)
  local weather = (w and ShopData.WEATHER[w.key]) or 1
  for _, n in ipairs(city.g.nodes) do
    if n.alive and (n.kind == "client" or n.kind == "works" or n.kind == "resort" or n.kind == "station")
       and cam:sees(n.x, n.y, 300 * cam.scale) then
      local rt = routeOf(city, n)
      if rt then
        local d = city:districtAt(n.x, n.y)
        local count = City.isShop and City.isShop(n) and 1 or math.max(1, math.floor(outNow(city, n, d, weather) * share + 0.5))
        for i = 1, count do
          outing(cam, rt, t, hash(n.id, i, 40), COATS[math.floor(hash(n.id, i, 41) * #COATS) + 1], n.id + i)
        end
      end
    end
  end
end

-- Shoppers: the ones who went in walk from the pavement to the door and back,
-- and the pavement outside carries a share of everyone who passed today.
local function drawShoppers(city, cam, t)
  if cam.scale < 0.45 or not city.shops then return end
  for _, n in ipairs(city:shops()) do
    if cam:sees(n.x, n.y, 260 * cam.scale) then
      local rt = routeOf(city, n)
      if rt and rt.road then
        local served = city:shopServed(n) or 0
        for i = 1, math.min(10, math.ceil(served / 5)) do
          outing(cam, rt, t, hash(n.id, i, 42), COATS[math.floor(hash(n.id, i, 44) * #COATS) + 1], n.id + i,
            { noStroll = true, pause = 4 + 4 * hash(n.id, i, 45), indoors = 4 + 6 * hash(n.id, i, 46) })
        end
        local span = rt.run[2] - rt.run[1]
        for i = 1, math.min(16, math.ceil((n.passing or 0) / 10)) do
          local v = (t * (6 + 4 * hash(n.id, i, 32)) + hash(n.id, i, 31) * 2 * span) / span
          local f = v % 2; f = f < 1 and f or 2 - f
          local x, y = pavePoint(rt.road, rt.run[1] + f * span, rt.side)
          if cam:sees(x, y, 10) then
            local back = (v % 2) >= 1
            local sx, sy = cam:toScreen(x, y)
            person(sx, sy, back and -rt.road.ux or rt.road.ux, back and -rt.road.uy or rt.road.uy, cam.scale,
              COATS[math.floor(hash(n.id, i, 34) * #COATS) + 1], t, n.id + i)
          end
        end
      end
    end
  end
end

--------------------------------------------------------------------------------
-- Roads: the day's trips, in lane
--------------------------------------------------------------------------------

local SPEED = { car = 42, van = 38, truck = 30, bus = 28 }
local ROAD_PACE = { offroad = 0.6, road = 1, highway = 1.7, bridge = 1 }

-- Roads joined end to end through plain corners are one street to the traffic
-- on it: a car goes round the bend instead of vanishing into it. A chain runs
-- from a building or a junction to the next, through any corners between.
local function chains(city, g)
  if g.chains then return g.chains end
  local at = {}
  for _, r in ipairs(g.roads) do
    for _, id in ipairs({ r.l.a, r.l.b }) do at[id] = at[id] or {}; table.insert(at[id], r) end
  end
  local function bend(id)
    local n = city.g.nodes[id]
    return n and n.kind == "corner" and #at[id] == 2
  end
  local seen, out = {}, {}
  for _, r in ipairs(g.roads) do
    if not seen[r] then
      -- Walk back to where this street starts, then forward to where it ends.
      local start, from = r, r.l.a
      local guard = 0
      while bend(from) and guard < 200 do
        local other = at[from][1] == start and at[from][2] or at[from][1]
        if seen[other] or other == r then break end
        from = other.l.a == from and other.l.b or other.l.a
        start = other
        guard = guard + 1
      end
      local node = city.g.nodes[from]
      local pts, links, cur, here = { node.x, node.y }, {}, start, from
      guard = 0
      while cur and not seen[cur] and guard < 400 do
        seen[cur] = true
        links[#links + 1] = cur
        here = cur.l.a == here and cur.l.b or cur.l.a
        local n = city.g.nodes[here]
        pts[#pts + 1] = n.x; pts[#pts + 1] = n.y
        local nxt
        if bend(here) then nxt = at[here][1] == cur and at[here][2] or at[here][1] end
        cur = nxt
        guard = guard + 1
      end
      local len = 0
      for i = 3, #pts, 2 do len = len + math.sqrt((pts[i] - pts[i - 2]) ^ 2 + (pts[i + 1] - pts[i - 1]) ^ 2) end
      local x0, y0, x1, y1 = math.huge, math.huge, -math.huge, -math.huge
      for i = 1, #pts, 2 do
        x0, x1 = math.min(x0, pts[i]), math.max(x1, pts[i])
        y0, y1 = math.min(y0, pts[i + 1]), math.max(y1, pts[i + 1])
      end
      out[#out + 1] = { pts = pts, len = len, links = links, kind = start.kind, half = start.half,
        id = start.l.id, box = { x0, y0, x1, y1 } }
    end
  end
  g.chains = out
  return out
end

-- A point `s` metres along a street, and its heading there.
local function along_(pts, s)
  for i = 3, #pts, 2 do
    local dx, dy = pts[i] - pts[i - 2], pts[i + 1] - pts[i - 1]
    local seg = math.sqrt(dx * dx + dy * dy)
    if s <= seg or i == #pts - 1 then
      local f = seg > 0 and math.max(0, math.min(1, s / seg)) or 0
      return pts[i - 2] + dx * f, pts[i - 1] + dy * f, dx / math.max(seg, 1e-6), dy / math.max(seg, 1e-6)
    end
    s = s - seg
  end
  return pts[1], pts[2], 1, 0
end

local function drawRoads(city, cam, t)
  if cam.scale < 0.2 then return end
  local g = geo(city)
  local byLink = (city.transit or {}).byLink or {}
  for _, ch in ipairs(chains(city, g)) do
    local b = ch.box
    if cam:seesBox(b[1], b[2], b[3], b[4], 20) then
      -- A street carries as many as its busiest stretch did today.
      local car, truck, bus = 0, 0, 0
      for _, r in ipairs(ch.links) do
        local rec = byLink[r.l.id] or {}
        car, truck, bus = math.max(car, rec.car or 0), math.max(truck, rec.truck or 0), math.max(bus, rec.bus or 0)
      end
      local fleet = {
        { "car", math.min(10 + #ch.links, math.ceil(car / 3)) },
        { "truck", ch.kind == "offroad" and 0 or math.min(4, math.ceil(truck / 2)) },
        { "bus", ch.kind == "offroad" and 0 or math.min(3, bus) },
      }
      local i = 0
      for _, f in ipairs(fleet) do
        for j = 1, f[2] do
          i = i + 1
          local kind = f[1]
          if kind == "car" and hash(ch.id, i, 9) < 0.15 then kind = "van" end
          local dir = i % 2 == 0 and -1 or 1
          local speed = SPEED[kind] * ROAD_PACE[ch.kind] * (0.9 + 0.2 * hash(ch.id, i, 3))
          local s = (hash(ch.id, i, 1) * ch.len + t * speed) % (ch.len + 40) - 20
          if s > 6 and s < ch.len - 6 then
            if dir < 0 then s = ch.len - s end
            local x, y, ux, uy = along_(ch.pts, s)
            ux, uy = ux * dir, uy * dir
            -- Keep right: a highway's slow lane is the outer one.
            local lane = ch.half * (ch.kind == "highway" and (kind == "car" and 0.3 or 0.72) or 0.48)
            x, y = x - uy * lane, y + ux * lane
            if cam:sees(x, y, 20) then
              local sx, sy = cam:toScreen(x, y)
              vehicle(kind, sx, sy, ux, uy, cam.scale, CAR_COLOURS[math.floor(hash(ch.id, i, 4) * #CAR_COLOURS) + 1])
            end
          end
        end
      end
    end
  end
end

--------------------------------------------------------------------------------
-- Freight: the day's loads on the lines that carry them
--------------------------------------------------------------------------------

-- Where a boat calls at a place: a harbour or a coastal stop on land is
-- reached at the head of its jetty, out at sea; anything already on the
-- water (an island, the river) is reached where it stands.
local function quay(city, n)
  if n.y >= 0 and n.y <= City.havenReach + 60 and not city:riverAt(n.x, n.y) then
    return n.x + 24, City.JETTY_HEAD - 40
  end
  return n.x, n.y
end

-- What a freight line carries today: the units, the way they go (+1 a to b),
-- and the trades in the load.
local function freightOn(city, e)
  local units, best, dir, cargo = 0, 0, 1, {}
  for key, flows in pairs(city.edgeFlowBy or {}) do
    local f = flows[e.id] or 0
    if f ~= 0 then
      units = units + math.abs(f)
      cargo[#cargo + 1] = key
      if math.abs(f) > best then best, dir = math.abs(f), f > 0 and 1 or -1 end
    end
  end
  table.sort(cargo)
  return units, dir, cargo
end

local function lineEnds(city, e, dir)
  local na, nb = city.g.nodes[e.a], city.g.nodes[e.b]
  if not (na and nb) then return end
  if dir < 0 then na, nb = nb, na end
  if e.bulk == "sea" then
    local ax, ay = quay(city, na)
    local bx, by = quay(city, nb)
    na, nb = { x = ax, y = ay }, { x = bx, y = by }
  end
  local dx, dy = nb.x - na.x, nb.y - na.y
  local len = math.max(1, math.sqrt(dx * dx + dy * dy))
  return na.x, na.y, dx / len, dy / len, len
end

-- A train: a locomotive and its wagons, coupled along the line.
local function train(cam, ax, ay, ux, uy, s, wagons, cargo, laden)
  local step = 26
  for i = 0, wagons do
    local d = s - i * step
    local x, y = ax + ux * d, ay + uy * d
    if cam:sees(x, y, 30) then
      local sx, sy = cam:toScreen(x, y)
      local L, W = px(24 * 1.4, cam.scale, 3), px(7 * 1.4, cam.scale, 1.6)
      lg.push(); lg.translate(sx, sy); lg.rotate(math.atan2(uy, ux))
      lg.setColor(0, 0, 0, 0.3); lg.rectangle("fill", -L / 2 + 1, -W / 2 + 1.5, L, W)
      if i == 0 then
        lg.setColor(0.78, 0.22, 0.18); lg.rectangle("fill", -L / 2, -W / 2, L, W, W * 0.3)
        lg.setColor(0.20, 0.22, 0.26); lg.rectangle("fill", L * 0.25, -W * 0.35, L * 0.15, W * 0.7)
      else
        lg.setColor(0.36, 0.36, 0.38); lg.rectangle("fill", -L / 2, -W / 2, L, W, W * 0.1)
        if laden then
          local c = cargoColour(cargo[(i - 1) % math.max(1, #cargo) + 1])
          lg.setColor(c); lg.rectangle("fill", -L * 0.42, -W * 0.34, L * 0.84, W * 0.68)
        end
      end
      lg.pop()
    end
  end
end

local function drawFreight(city, cam, t)
  if cam.scale < 0.14 then return end
  for _, e in ipairs(city.g.edges) do
    if e.alive and e.rail and e.bulk ~= "air" then
      local units, dir, cargo = freightOn(city, e)
      if units > 0 then
        local mode = e.bulk or "rail"
        local spec = City.MODES[mode] or City.MODES.rail
        local loads = math.max(1, math.ceil(units / spec.wagonCap))
        for back = 0, 1 do
          local ax, ay, ux, uy, len = lineEnds(city, e, back == 0 and dir or -dir)
          if ax and cam:seesBox(math.min(ax, ax + ux * len), math.min(ay, ay + uy * len),
              math.max(ax, ax + ux * len), math.max(ay, ay + uy * len), 120) then
            local laden = back == 0
            if mode == "highway" then
              -- Lorries out full and back empty, in their lanes.
              local n = math.min(6, loads)
              for i = 1, n do
                local s = (hash(e.id, i, back) * len + t * 32) % (len + 40) - 20
                if s > 10 and s < len - 10 then
                  local x, y = ax + ux * s - uy * 4, ay + uy * s + ux * 4
                  if cam:sees(x, y, 20) then
                    local sx, sy = cam:toScreen(x, y)
                    vehicle("truck", sx, sy, ux, uy, cam.scale, laden and cargoColour(cargo[(i - 1) % #cargo + 1]) or { 0.55, 0.58, 0.60 })
                  end
                end
              end
            elseif mode == "sea" then
              local n = math.min(3, loads)
              for i = 1, n do
                local s = (hash(e.id, i, back) * len + t * 18) % (len + 300) - 150
                if s > 40 and s < len - 40 then
                  local x, y = ax + ux * s - uy * 20, ay + uy * s + ux * 20
                  if cam:sees(x, y, 160) then
                    local sx, sy = cam:toScreen(x, y)
                    boat("ship", sx, sy, ux, uy, cam.scale, t, e.id + i, 1, laden and cargo or nil)
                  end
                end
              end
            else
              -- One train each way, as long as the day's load needs.
              local wagons = math.min(10, loads)
              local cycle = (len + wagons * 26) / 36 + 20
              local k = (t + hash(e.id, back, 7) * cycle) % cycle
              local s = k * 36
              if s < len + wagons * 26 then train(cam, ax - uy * 3, ay + ux * 3, ux, uy, math.min(s, len), wagons, cargo, laden) end
            end
          end
        end
      end
    end
  end
end

--------------------------------------------------------------------------------
-- Havens: a ship in for a harbour's day of cargo
--------------------------------------------------------------------------------

-- What a haven brought in today: the day's draw on it and this morning's
-- ordered cargo. Units, and the goods as a sorted list.
local function landedToday(city, n)
  local units, seen, cargo = (city.produced or {})[n.id] or 0, {}, {}
  for key, v in pairs((city.producedBy or {})[n.id] or {}) do if v > 0 then seen[key] = true end end
  local coming, landed = {}, {}
  if city.havenShipments then coming, landed = city:havenShipments(n.id) end
  for key, v in pairs(landed) do units = units + v; seen[key] = true end
  for key in pairs(seen) do cargo[#cargo + 1] = key end
  table.sort(cargo)
  return units, cargo, coming
end
local function landedCargo(city, n) return select(2, landedToday(city, n)) end
Traffic.landedToday = landedToday

-- A ship's call at the harbour: in from open sea, alongside the jetty head,
-- swung round by the tugs, and out again.
local sighted = setmetatable({}, { __mode = "k" })
local function drawHarbours(city, cam, t)
  for _, n in ipairs(city.g.nodes) do
    if n.alive and n.kind == "terminal" and (n.haven or "port") == "port" and n.y < City.havenReach + 60 then
      local landed, cargo = landedToday(city, n)
      -- Ordered cargo still at sea: the freighter is on its way in, and rides
      -- at anchor off the harbour until the morning it lands.
      local i = 0
      for _, o in ipairs(city.shipments or {}) do
        if o.haven == n.id and i < 3 then
          i = i + 1
          -- Each order's ship sets out from the horizon the moment it is
          -- placed, sails in, and rides at anchor until the morning it lands.
          sighted[o] = sighted[o] or t
          local f = math.min(1, (t - sighted[o]) / 70)
          local x, y = n.x - 150 - (i - 1) * 80, -2800 + 1800 * ease(f) - (i - 1) * 170
          if cam:sees(x, y, 200) then
            local sx, sy = cam:toScreen(x, y + (f >= 1 and math.sin(t + i) * 1.5 or 0))
            boat("ship", sx, sy, 0, 1, cam.scale, t, n.id + 7 * i, f >= 1 and 0 or 0.7, { o.key })
          end
        end
      end
      if landed > 0 and cam:seesBox(n.x - 300, -2000, n.x + 300, n.y, 100) then
        local ships = math.min(3, math.ceil(landed / City.MODES.sea.wagonCap))
        local berthX, berthY = n.x + 24, City.JETTY_HEAD + 72
        local IN, MOOR, TURN, OUT = 30, 26, 8, 30
        local cycle = IN + MOOR + TURN + OUT
        for i = 1, ships do
          local k = (t + (i - 1) * cycle / ships + hash(n.id, 3) * cycle) % cycle
          local x, y, dx, dy, speed
          if k < IN then
            local f = ease(k / IN)
            x, y, dx, dy, speed = berthX, berthY - 1700 * (1 - f), 0, 1, 1 - f * 0.8
          elseif k < IN + MOOR then
            x, y, dx, dy, speed = berthX, berthY + math.sin(t * 1.3 + i) * 1.2, 0, 1, 0
          elseif k < IN + MOOR + TURN then
            local a = math.pi / 2 + math.pi * ease((k - IN - MOOR) / TURN)
            x, y, dx, dy, speed = berthX + 30 * math.sin(a - math.pi / 2), berthY, math.cos(a), math.sin(a), 0.2
          else
            local f = (k - IN - MOOR - TURN) / OUT
            x, y, dx, dy, speed = berthX, berthY - 1700 * f * f, 0, -1, 0.3 + 0.7 * f
          end
          if cam:sees(x, y, 200) then
            local sx, sy = cam:toScreen(x, y)
            boat("ship", sx, sy, dx, dy, cam.scale, t, n.id + i, speed, k < IN + MOOR and cargo or nil)
          end
        end
      end
    end
  end
end

-- Ferries on routes that carried passengers today, shuttling end to end.
local function drawFerries(city, cam, t)
  local byLink = (city.transit or {}).byLink or {}
  for _, l in ipairs(city.links or {}) do
    local rec = byLink[l.id]
    if l.alive and l.mode == "ferry" and rec and (rec.trips or 0) > 0 then
      local na, nb = city.g.nodes[l.a], city.g.nodes[l.b]
      if na and nb then
        local ax, ay = quay(city, na)
        local bx, by = quay(city, nb)
        na, nb = { x = ax, y = ay }, { x = bx, y = by }
        local dx, dy = nb.x - na.x, nb.y - na.y
        local len = math.max(1, math.sqrt(dx * dx + dy * dy))
        local run, dock = len / 22, 10
        local cycle = 2 * (run + dock)
        for i = 1, math.max(1, l.vehicles or 1) do
          local k = (t + (i - 1) * cycle / (l.vehicles or 1)) % cycle
          local f, dir, speed
          if k < run then f, dir, speed = ease(k / run), 1, 1
          elseif k < run + dock then f, dir, speed = 1, 1, 0
          elseif k < 2 * run + dock then f, dir, speed = 1 - ease((k - run - dock) / run), -1, 1
          else f, dir, speed = 0, -1, 0 end
          local x, y = na.x + dx * f, na.y + dy * f
          if cam:sees(x, y, 80) then
            local sx, sy = cam:toScreen(x, y)
            boat("ferry", sx, sy, dx / len * dir, dy / len * dir, cam.scale, t, l.id + i, speed)
          end
        end
      end
    end
  end
end

-- Yachts off a resort on the coast: its guests out on the water.
local function drawYachts(city, cam, t)
  for _, n in ipairs(city.g.nodes) do
    if n.alive and n.kind == "resort" and n.y < 500 then
      for i = 1, 2 + (n.level or 1) do
        local cx, cy = n.x + (hash(n.id, i, 1) - 0.5) * 500, -220 - 260 * hash(n.id, i, 2)
        local rx, ry = 160 + 120 * hash(n.id, i, 3), 50 + 40 * hash(n.id, i, 4)
        local a = t * (0.025 + 0.02 * hash(n.id, i, 5)) * (i % 2 == 0 and 1 or -1) + hash(n.id, i, 6) * 6.28
        local x, y = cx + math.cos(a) * rx, cy + math.sin(a) * ry
        if cam:sees(x, y, 40) then
          local sgn = i % 2 == 0 and 1 or -1
          local sx, sy = cam:toScreen(x, y)
          boat("sail", sx, sy, -math.sin(a) * rx * sgn, math.cos(a) * ry * sgn, cam.scale, t, i, 0.6)
        end
      end
    end
  end
end

--------------------------------------------------------------------------------
-- Crews at the worst leaks, when the company pays for crews.
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
-- Overhead: birds over the woods, and aircraft only where there is a reason.
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

-- A flight between two points along a gentle arc: climb, cruise, descend.
local function flight(cam, ax, ay, bx, by, f, livery, size)
  local dx, dy = bx - ax, by - ay
  local cx, cy = (ax + bx) / 2 - dy * 0.18, (ay + by) / 2 + dx * 0.18
  local x = (1 - f) ^ 2 * ax + 2 * (1 - f) * f * cx + f * f * bx
  local y = (1 - f) ^ 2 * ay + 2 * (1 - f) * f * cy + f * f * by
  local tx = 2 * (1 - f) * (cx - ax) + 2 * f * (bx - cx)
  local ty = 2 * (1 - f) * (cy - ay) + 2 * f * (by - cy)
  local alt = math.min(1, math.min(f, 1 - f) * 6)
  if cam:sees(x, y, 200) then flying(cam, x, y, tx, ty, alt, livery, size) end
end

-- Landing and taking off along a runway: (rx, ry) its touchdown point, (ux,
-- uy) the way it lands. The approach comes in from far out; the departure
-- leaves the other way.
local function runway(cam, t, rx, ry, ux, uy, seed, livery)
  local APPROACH, ROLL, GROUND, CLIMB = 22, 7, 18, 20
  local cycle = APPROACH + ROLL + GROUND + CLIMB
  local k = (t + seed * cycle) % cycle
  local x, y, alt
  if k < APPROACH then
    local f = k / APPROACH
    local d = 2200 * (1 - f)
    x, y, alt = rx - ux * d, ry - uy * d, (1 - f) * 0.9
  elseif k < APPROACH + ROLL then
    local f = (k - APPROACH) / ROLL
    local d = 140 * (1 - (1 - f) ^ 2)
    x, y, alt = rx + ux * d, ry + uy * d, 0
  elseif k < APPROACH + ROLL + GROUND then
    return
  else
    local f = (k - APPROACH - ROLL - GROUND) / CLIMB
    local d = -120 + 2400 * f * f
    x, y, alt = rx + ux * d, ry + uy * d, math.min(1, math.max(0, (d + 40) / 900))
  end
  if cam:sees(x, y, 200) then flying(cam, x, y, ux, uy, alt, livery) end
end

local function drawAir(city, cam, t)
  local byLink = (city.transit or {}).byLink or {}
  for _, n in ipairs(city.g.nodes) do
    if n.alive then
      -- An air freight apron, on a day it lands cargo: the freighter in and out.
      if n.kind == "terminal" and n.haven == "airfield" and landedToday(city, n) > 0 then
        local a = (math.floor(Shape.hash(n.x, n.y, 90) * 4) - 1.5) * 0.35
        local ux, uy = math.cos(a), math.sin(a)
        local rx, ry = n.x - uy * 27 - ux * 110, n.y + ux * 27 - uy * 110
        local cargo = landedCargo(city, n)
        runway(cam, t, rx, ry, ux, uy, hash(n.id, 1), cargo[1] and cargoColour(cargo[1]))
      end
      -- An airport the company supplies: its flights come and go.
      if n.kind == "client" and n.clientType == "airport" and not n.prospect and city:fullyServed(n) then
        local a = Shape.hash(n.x, n.y, 91) * math.pi * 2
        local ux, uy = math.cos(a), math.sin(a)
        for i = 1, 2 do
          runway(cam, t, n.x - ux * 60, n.y - uy * 60, ux, uy, hash(n.id, i, 2), { 0.30, 0.52, 0.86 })
        end
      end
    end
  end
  -- Airliners on passenger routes that flew today, out and back.
  for _, l in ipairs(city.links or {}) do
    local rec = byLink[l.id]
    if l.alive and l.mode == "air" and rec and (rec.trips or 0) > 0 then
      local na, nb = city.g.nodes[l.a], city.g.nodes[l.b]
      if na and nb then
        local len = math.sqrt((nb.x - na.x) ^ 2 + (nb.y - na.y) ^ 2)
        local leg = len / 160 + 10
        for i = 1, math.max(1, l.vehicles or 1) do
          local k = (t + (i - 1) * leg * 2 / (l.vehicles or 1) + hash(l.id, i) * 10) % (leg * 2)
          if k < leg then flight(cam, na.x, na.y, nb.x, nb.y, k / leg, { 0.86, 0.30, 0.28 })
          else flight(cam, nb.x, nb.y, na.x, na.y, (k - leg) / leg, { 0.86, 0.30, 0.28 }) end
        end
      end
    end
  end
  -- Air freight lanes carrying cargo today.
  for _, e in ipairs(city.g.edges) do
    if e.alive and e.rail and e.bulk == "air" then
      local units, dir, cargo = freightOn(city, e)
      if units > 0 then
        local na, nb = city.g.nodes[e.a], city.g.nodes[e.b]
        if dir < 0 then na, nb = nb, na end
        local len = math.sqrt((nb.x - na.x) ^ 2 + (nb.y - na.y) ^ 2)
        local leg = len / 160 + 10
        local k = (t + hash(e.id, 1) * leg * 2) % (leg * 2)
        local livery = cargo[1] and cargoColour(cargo[1])
        if k < leg then flight(cam, na.x, na.y, nb.x, nb.y, k / leg, livery)
        else flight(cam, nb.x, nb.y, na.x, na.y, (k - leg) / leg, nil) end
      end
    end
  end
end

--------------------------------------------------------------------------------
-- Convoys: loads on their way inland from a haven, and materials going out
-- to a building site (haulage.lua). Each sets off the moment it is first seen
-- and runs its route once; an inland load then waits at the yard gate, a site
-- delivery stands by the site, until the day closes.
--------------------------------------------------------------------------------

local convoySeen = setmetatable({}, { __mode = "k" })

-- A point `s` metres along a polyline, and the way it faces there.
local function onPath(pts, s)
  for i = 3, #pts, 2 do
    local dx, dy = pts[i] - pts[i - 2], pts[i + 1] - pts[i - 1]
    local seg = math.sqrt(dx * dx + dy * dy)
    if s <= seg or i == #pts - 1 then
      local f = seg > 0 and math.max(0, math.min(1, s / seg)) or 0
      return pts[i - 2] + dx * f, pts[i - 1] + dy * f, dx / math.max(seg, 1e-6), dy / math.max(seg, 1e-6)
    end
    s = s - seg
  end
  return pts[1], pts[2], 1, 0
end

local function drawConvoys(city, cam, t, air)
  local fresh = 0
  for _, cv in ipairs(city.convoys or {}) do
    local spec = City.HAUL and City.HAUL[cv.mode]
    if spec and (cv.mode == "plane") == air and cv.pts and #cv.pts >= 4 then
      -- Loads that set off together leave one after another, not on top.
      if not convoySeen[cv] then convoySeen[cv] = t + fresh * 10; fresh = fresh + 1 end
      local run = (t - convoySeen[cv]) * spec.speed
      local count = math.min(cv.mode == "train" and 1 or 6, math.max(1, math.ceil(cv.units / spec.cap)))
      -- Until a site's materials arrive it is a building site: a fence and
      -- a tower crane turning over it.
      if not air and not cv.stock and run < cv.len + (count - 1) * 34 then
        local ex, ey = cv.pts[#cv.pts - 1], cv.pts[#cv.pts]
        if cam:sees(ex, ey, 80) then
          local sx, sy = cam:toScreen(ex, ey)
          local k = math.max(0.4, cam.scale)
          lg.setColor(0.95, 0.70, 0.20, 0.85); lg.setLineWidth(math.max(1, 1.5 * k))
          for a = 0, 11 do
            if a % 2 == 0 then lg.arc("line", "open", sx, sy, 34 * k, a * math.pi / 6, (a + 1) * math.pi / 6) end
          end
          local jib = (t * 0.25 + (cv.id or 0)) % (math.pi * 2)
          lg.setColor(0, 0, 0, 0.3); lg.setLineWidth(math.max(1, 2 * k))
          lg.line(sx + 4 * k, sy + 6 * k, sx + 4 * k + math.cos(jib) * 40 * k, sy + 6 * k + math.sin(jib) * 40 * k)
          lg.setColor(0.98, 0.78, 0.22); lg.setLineWidth(math.max(1, 2.4 * k))
          lg.line(sx - math.cos(jib) * 12 * k, sy - math.sin(jib) * 12 * k, sx + math.cos(jib) * 40 * k, sy + math.sin(jib) * 40 * k)
          lg.rectangle("fill", sx - 3 * k, sy - 3 * k, 6 * k, 6 * k)
          lg.setColor(0.30, 0.30, 0.32); lg.rectangle("fill", sx - math.cos(jib) * 12 * k - 3 * k, sy - math.sin(jib) * 12 * k - 3 * k, 6 * k, 6 * k)
        end
      end
      local load = cargoColour(cv.key)
      local gap = cv.mode == "barge" and 90 or 34
      for i = 1, count do
        local s = math.min(cv.len - 8 - (i - 1) * gap, run - (i - 1) * gap)
        if s >= 0 then
          local x, y, dx, dy = onPath(cv.pts, s)
          if cv.mode == "plane" then
            local f = math.min(1, s / math.max(1, cv.len))
            if f < 1 then flight(cam, cv.pts[1], cv.pts[2], cv.pts[#cv.pts - 1], cv.pts[#cv.pts], f, load) end
          elseif cam:sees(x, y, 60) then
            local sx, sy = cam:toScreen(x, y)
            local moving = run - (i - 1) * gap < cv.len - 8 - (i - 1) * gap
            if cv.mode == "barge" or cv.mode == "ship" then
              boat(cv.mode, sx, sy, dx, dy, cam.scale, t, i, moving and 0.7 or 0, { cv.key })
            elseif cv.mode == "train" then
              train(cam, x, y, dx, dy, 0, math.min(10, math.ceil(cv.units / spec.cap)), { cv.key }, true)
            else
              -- Keep right on a road; overland, just the track it makes.
              local lane = cv.mode == "semi" and 4 or 0
              sx, sy = cam:toScreen(x - dy * lane, y + dx * lane)
              vehicle(cv.mode == "semi" and "semi" or "truck", sx, sy, dx, dy, cam.scale,
                { 0.86, 0.50, 0.22 }, load)
            end
          end
        end
      end
    end
  end
end

-- Under the buildings: what is on the ground and on the water.
function Traffic.ground(city, cam, visible)
  local t = R.t or 0
  routeBudget = ROUTES_PER_FRAME
  drawHarbours(city, cam, t)
  drawFerries(city, cam, t)
  drawYachts(city, cam, t)
  drawFreight(city, cam, t)
  drawConvoys(city, cam, t, false)
  drawRoads(city, cam, t)
  drawPeople(city, cam, t)
  drawShoppers(city, cam, t)
  drawCrews(city, cam, t)
end

-- Over everything on the ground: birds, then aircraft.
function Traffic.air(city, cam)
  local t = R.t or 0
  drawBirds(city, cam, t)
  drawAir(city, cam, t)
  drawConvoys(city, cam, t, true)
end

Traffic._hash, Traffic._route, Traffic._standable, Traffic._geo, Traffic._chains = hash, routeOf, standable, geo, chains
return Traffic
