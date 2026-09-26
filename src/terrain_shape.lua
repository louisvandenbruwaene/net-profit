-- terrain_shape.lua -- the outline of a wood or a range, shared by the rules and
-- the renderer so what is drawn is exactly what charges to be crossed.
--
-- A piece of terrain is saved as a centre and a radius. Its outline is a lobed
-- blob inside that circle, worked out from a hash of the centre, so old saves
-- need nothing new and the same ground always has the same shape. The outline
-- never passes the saved radius: it only ever gives ground back.
local Shape = {}

local function hash(a, b, c)
  local v = math.sin(a * 12.9898 + b * 78.233 + (c or 0) * 37.719) * 43758.5453
  return v - math.floor(v)
end
Shape.hash = hash

local atan2 = math.atan2 or math.atan

local phases = setmetatable({}, { __mode = "k" })
local function phase(o)
  local p = phases[o]
  if not p then
    p = {}
    for i = 1, 5 do p[i] = hash(o.x, o.y, 100 + i) * math.pi * 2 end
    phases[o] = p
  end
  return p
end

-- The outline as a fraction of the saved radius, between 0.52 and 1.
function Shape.fraction(o, t)
  local p = phase(o)
  local g = 0.45 * math.sin(2 * t + p[1]) + 0.32 * math.sin(3 * t + p[2])
          + 0.15 * math.sin(5 * t + p[3]) + 0.08 * math.sin(9 * t + p[4])
  return 0.76 + 0.24 * g
end

-- How far the outline reaches from the centre in the direction of (x, y).
function Shape.reach(o, x, y)
  return o.r * Shape.fraction(o, atan2(y - o.y, x - o.x))
end

-- Is the point inside, and how deep: 0 at the centre, 1 on the outline.
function Shape.depth(o, x, y)
  local dx, dy = x - o.x, y - o.y
  local d2 = dx * dx + dy * dy
  if d2 > o.r * o.r then return nil end
  local reach = o.r * Shape.fraction(o, atan2(dy, dx))
  local d = math.sqrt(d2)
  if d > reach then return nil end
  return d / reach
end

function Shape.contains(o, x, y)
  return Shape.depth(o, x, y) ~= nil
end

local SIDES = 72
local outlines = setmetatable({}, { __mode = "k" })

-- The outline as a closed polygon, in world coordinates.
function Shape.outline(o)
  local pts = outlines[o]
  if not pts then
    pts = {}
    for i = 0, SIDES - 1 do
      local t = i / SIDES * math.pi * 2
      local f = o.r * Shape.fraction(o, t)
      pts[#pts + 1] = { o.x + math.cos(t) * f, o.y + math.sin(t) * f }
    end
    outlines[o] = pts
  end
  return pts
end

local function segSeg(ax, ay, bx, by, cx, cy, dx, dy)
  local rx, ry, sx, sy = bx - ax, by - ay, dx - cx, dy - cy
  local den = rx * sy - ry * sx
  if den == 0 then return false end
  local t = ((cx - ax) * sy - (cy - ay) * sx) / den
  local u = ((cx - ax) * ry - (cy - ay) * rx) / den
  return t >= 0 and t <= 1 and u >= 0 and u <= 1
end

-- Does a straight run from a to b touch this ground?
function Shape.crosses(o, ax, ay, bx, by)
  -- Cheap rejection against the saved circle first.
  local dx, dy = bx - ax, by - ay
  local l2 = dx * dx + dy * dy
  local t = 0
  if l2 > 1e-9 then t = math.max(0, math.min(1, ((o.x - ax) * dx + (o.y - ay) * dy) / l2)) end
  local px, py = ax + dx * t, ay + dy * t
  if (px - o.x) ^ 2 + (py - o.y) ^ 2 > o.r * o.r then return false end
  if Shape.contains(o, ax, ay) or Shape.contains(o, bx, by) then return true end
  local pts = Shape.outline(o)
  for i = 1, #pts do
    local p, q = pts[i], pts[i % #pts + 1]
    if segSeg(ax, ay, bx, by, p[1], p[2], q[1], q[2]) then return true end
  end
  return false
end

return Shape
