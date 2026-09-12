local P = require("palette")
local Graph = require("graph")
local City = require("city")
local R = require("render")
local E = require("experience")
local Draw = {}
local lg = love.graphics

local function label(text, x, y, color, font)
  font = font or R.fonts.small
  lg.setFont(font)
  local w = font:getWidth(text)
  lg.setColor(P.with(P.bg, 0.94))
  lg.rectangle("fill", x - w / 2 - 4, y - 1, w + 8, font:getHeight() + 2, 3)
  lg.setColor(color or P.text)
  lg.print(text, x - w / 2, y)
end

--------------------------------------------------------------------------------
-- Symbols
--
-- One flat shape per thing, in one colour, drawn from fractions of a single
-- size argument so the same function serves the five-pixel map dot and the
-- twenty-pixel sidebar glyph. No shading, no highlights, no windows: a symbol
-- on a map has to survive being eleven pixels wide, and every interior detail
-- is one more thing to turn into mud when it gets there. A house is a house
-- shape, a forest is trees, a depot is crates.
--------------------------------------------------------------------------------

-- Line weight for an icon of the given span, never thinner than a hairline.
local function stroke(size, k)
  lg.setLineWidth(math.max(0.9, size * (k or 0.11)))
end

-- The colour a caller set before calling a glyph. Every glyph is drawn in it,
-- so the trade colour is chosen once at the call site.
local function trim()
  local r, g, b, a = lg.getColor()
  return r, g, b, a or 1
end

-- One droplet, three colours: blue water, amber beer, black oil. Every place a
-- commodity appears -- wells, pipes legend, customer badges, sidebar buttons --
-- uses this same shape, so the trade is readable before any text is.
local function dropletPoints(x, y, r)
  local pts = { x, y - r }
  local cy, rr = y + 0.24 * r, 0.74 * r
  for i = 0, 18 do
    local a = math.rad(-32) + (i / 18) * math.rad(244)
    pts[#pts + 1] = x + math.cos(a) * rr
    pts[#pts + 1] = cy + math.sin(a) * rr
  end
  return pts
end

-- Electricity is not a liquid and is not drawn as one. The bolt is the only
-- glyph in the set that is not a droplet, which is exactly how it should read.
local function boltPoints(x, y, r)
  return {
    x + 0.16*r, y - r,      x - 0.58*r, y + 0.10*r,
    x - 0.06*r, y + 0.10*r, x - 0.20*r, y + r,
    x + 0.58*r, y - 0.14*r, x + 0.06*r, y - 0.14*r,
  }
end

-- Exported so the sidebar draws the identical glyph the map does.
function Draw.mark(commodity, x, y, r, dim)
  local spec = Graph.COMMODITIES[commodity] or Graph.COMMODITIES.water
  local a = dim and 0.45 or 1
  local pts = (spec.mark == "bolt") and boltPoints(x, y, r) or dropletPoints(x, y, r)
  lg.setColor(P.with(spec.fill, a))
  lg.polygon("fill", pts)
  -- Oil is very nearly black, so its outline is not decoration: it is the only
  -- thing keeping the drop from reading as a hole in the screen.
  lg.setColor(P.with(spec.color, a))
  stroke(r * 2, 0.09)
  lg.polygon("line", pts)
end

-- Kept as an alias: most of the game's trades really are droplets.
Draw.droplet = Draw.mark

--------------------------------------------------------------------------------
-- Customers
--
-- Five silhouettes that differ at the outline, because the outline is all
-- there is at map size: a pitched roof, a stepped block, a saw-tooth shed, a
-- tankard, a pair of stacks.
--------------------------------------------------------------------------------

function Draw.clientGlyph(kind, x, y, s)
  s = s or 1
  local r, g, b, a = trim()
  lg.push()
  lg.translate(x, y)
  lg.setColor(r, g, b, a)

  if kind == "factory" then
    -- A works: a block with two capped stacks. One thin stack read as a
    -- flagpole; two of them, side by side and shorter, read as a plant.
    lg.rectangle("fill", -10 * s, -3.4 * s, 20 * s, 11.4 * s, 0.8 * s)
    lg.rectangle("fill", -8.6 * s, -10.4 * s, 4.2 * s, 7.6 * s)
    lg.rectangle("fill", -9.4 * s, -11.6 * s, 5.8 * s, 1.5 * s, 0.4 * s)
  elseif kind == "pub" then
    -- A tankard: straight sides, and a handle whose ends run back under the
    -- body. An arc that stops short of the mug floats off it at map size.
    lg.rectangle("fill", -8 * s, -8.4 * s, 10.6 * s, 16.8 * s, 1 * s)
    stroke(20 * s, 0.12)
    lg.arc("line", "open", 3.4 * s, 0, 3.8 * s, -math.pi * 0.72, math.pi * 0.72)
  elseif kind == "workshop" then
    -- The saw-tooth roof every light-industrial shed in the world has: the
    -- shed, and one triangle per tooth, all of them convex.
    lg.rectangle("fill", -9.4 * s, -1.4 * s, 18.8 * s, 9.4 * s, 0.4 * s)
    for i = 0, 2 do
      local bx = (-9.4 + i * 6.3) * s
      lg.polygon("fill", bx, -1 * s, bx, -7.6 * s, bx + 6.3 * s, -1 * s)
    end
  elseif kind == "estate" then
    -- Two flat-roofed blocks with windows punched out of them. Bare rectangles
    -- read as a bar chart, and a parapet lip turned them into jars; windows are
    -- the only detail that says "people live here", and they are cut in the
    -- background colour so they simply close up as the camera pulls back.
    lg.rectangle("fill", -9.4 * s, -8.2 * s, 8.8 * s, 16.2 * s, 0.6 * s)
    lg.rectangle("fill", 1 * s, -2.4 * s, 8.4 * s, 10.4 * s, 0.6 * s)
    -- Under about fifteen pixels across, a window is smaller than a pixel: it
    -- stops being a window and becomes grit on the silhouette, so below that
    -- the blocks are drawn solid.
    if s >= 1 then
      lg.setColor(P.bg)
      for col = 0, 1 do
        for rowi = 0, 2 do
          lg.rectangle("fill", (-7.9 + col * 4.2) * s, (-6.4 + rowi * 5) * s,
            2.4 * s, 2.8 * s, 0.3 * s)
        end
        for rowi = 0, 1 do
          lg.rectangle("fill", (2.5 + col * 4) * s, (-0.8 + rowi * 4.6) * s,
            2.2 * s, 2.6 * s, 0.3 * s)
        end
      end
      lg.setColor(r, g, b, a)
    end
  else
    -- A house: a roof sitting on its walls, not hanging past them. The old
    -- eaves stuck out far enough that the roof read as a separate triangle
    -- parked on a box; keep the overhang to a hair and the silhouette is one
    -- pentagon. Still two convex pieces, because a concave outline filled in
    -- one go comes out of LOVE's triangulator with a corner sliced off.
    lg.rectangle("fill", -7 * s, -2.6 * s, 14 * s, 10.6 * s, 0.4 * s)
    lg.polygon("fill", -7.7 * s, -2.2 * s, 0, -10.4 * s, 7.7 * s, -2.2 * s)
  end
  lg.pop()
end

--------------------------------------------------------------------------------
-- Structures
--
-- The player's own equipment, each one a picture of what the thing is: ports on
-- a junction, an impeller in a pump, a tank on legs, a valve, crates, a crane.
--------------------------------------------------------------------------------

function Draw.structureGlyph(kind, x, y, s)
  s = s or 1
  local r, g, b, a = trim()
  local span = 20 * s
  lg.push()
  lg.translate(x, y)
  lg.setColor(r, g, b, a)
  stroke(span, 0.1)

  if kind == "pump" then
    -- A pump on a line: the round casing, the motor bolted on top.
    lg.rectangle("fill", -10 * s, -1.6 * s, 20 * s, 3.2 * s, 0.8 * s)
    lg.circle("fill", 0, 0, 6.4 * s)
    lg.setColor(P.bg)
    lg.circle("fill", 0, 0, 3.4 * s)
    lg.setColor(r, g, b, a)
    lg.rectangle("fill", -3.4 * s, -10.5 * s, 6.8 * s, 4.6 * s, 0.6 * s)
  elseif kind == "tower" then
    -- A tank up a column on a footing: a water tower.
    lg.rectangle("fill", -8 * s, -11 * s, 16 * s, 7 * s, 1.6 * s)
    lg.rectangle("fill", -2.2 * s, -4.6 * s, 4.4 * s, 11.6 * s)
    lg.rectangle("fill", -7 * s, 7 * s, 14 * s, 2.2 * s, 0.8 * s)
  elseif kind == "gate" then
    -- A valve on a line, with the handwheel you set it by.
    lg.rectangle("fill", -10 * s, -1.6 * s, 20 * s, 3.2 * s, 0.8 * s)
    lg.rectangle("fill", -4.6 * s, -4.4 * s, 9.2 * s, 8.8 * s, 1 * s)
    lg.rectangle("fill", -1.2 * s, -9.6 * s, 2.4 * s, 5.4 * s)
    stroke(span, 0.085)
    lg.circle("line", 0, -10.4 * s, 3.6 * s)
  elseif kind == "depot" then
    -- Crates: what a depot is full of.
    lg.rectangle("fill", -9 * s, -0.5 * s, 8.4 * s, 8.4 * s, 0.6 * s)
    lg.rectangle("fill", 0.6 * s, -0.5 * s, 8.4 * s, 8.4 * s, 0.6 * s)
    lg.rectangle("fill", -4.2 * s, -9.4 * s, 8.4 * s, 8.4 * s, 0.6 * s)
  elseif kind == "terminal" then
    -- A gantry over a load: what stands at every door into the city, whether
    -- the freight arrives by sea, by air or by road.
    lg.rectangle("fill", -10 * s, -9.5 * s, 20 * s, 2.6 * s, 0.6 * s)
    lg.rectangle("fill", -9.4 * s, -6.9 * s, 2.6 * s, 15.4 * s)
    lg.rectangle("fill", 6.8 * s, -6.9 * s, 2.6 * s, 15.4 * s)
    lg.rectangle("fill", -3.6 * s, 1.6 * s, 7.2 * s, 6.9 * s, 0.6 * s)
  elseif kind == "dc" then
    -- A depot yard: a shed with a loading bay and two crates on the apron. The
    -- bay is what says freight rather than storage.
    lg.rectangle("fill", -10 * s, -7 * s, 20 * s, 11 * s, 0.8 * s)
    lg.setColor(P.bg)
    lg.rectangle("fill", -5.6 * s, -2.6 * s, 11.2 * s, 6.6 * s, 0.5 * s)
    lg.setColor(r, g, b, a)
    lg.rectangle("fill", -9 * s, 5 * s, 7 * s, 4 * s, 0.5 * s)
    lg.rectangle("fill", 1.4 * s, 5 * s, 7 * s, 4 * s, 0.5 * s)
  elseif kind == "works" then
    -- A works: a shed with a saw-tooth roof and a stack, which is what a
    -- factory looks like to everybody. It is deliberately close to the customer
    -- factory glyph, because they are the same kind of building -- one the
    -- company owns and one it sells to.
    lg.rectangle("fill", -9.6 * s, -1.6 * s, 19.2 * s, 9.6 * s, 0.6 * s)
    for i = 0, 2 do
      local bx = (-9.6 + i * 6.4) * s
      lg.polygon("fill", bx, -1.2 * s, bx, -7.4 * s, bx + 6.4 * s, -1.2 * s)
    end
    lg.rectangle("fill", 5.4 * s, -11.4 * s, 3 * s, 10 * s)
    lg.rectangle("fill", 4.6 * s, -12.4 * s, 4.6 * s, 1.4 * s, 0.35 * s)
  elseif kind == "exchange" then
    -- A hub: a depot building with four spurs running off it to the streets.
    -- Nothing else in the set has arms ending in dots, which is what says "this
    -- one reaches things you did not draw a pipe to".
    stroke(span, 0.085)
    for i = 0, 3 do
      local t = math.pi / 4 + i * math.pi / 2
      local ax, ay = math.cos(t) * 10 * s, math.sin(t) * 10 * s
      lg.line(0, 0, ax, ay)
      lg.circle("fill", ax, ay, 2.1 * s)
    end
    lg.rectangle("fill", -6.4 * s, -5 * s, 12.8 * s, 10 * s, 1.4 * s)
    lg.setColor(P.bg)
    lg.rectangle("fill", -3.4 * s, -2.4 * s, 6.8 * s, 4.8 * s, 0.8 * s)
    lg.setColor(r, g, b, a)
  elseif kind == "manifold" then
    -- Six ports on one hub, drawn as six ports on one hub.
    for i = 0, 5 do
      local t = i * math.pi / 3
      lg.line(0, 0, math.cos(t) * 9.4 * s, math.sin(t) * 9.4 * s)
    end
    lg.circle("fill", 0, 0, 3.6 * s)
  else
    -- A junction: three ports, and the cheapest way to turn a corner.
    for i = 0, 2 do
      local t = -math.pi / 2 + i * math.pi * 2 / 3
      lg.line(0, 0, math.cos(t) * 9 * s, math.sin(t) * 9 * s)
    end
    lg.circle("fill", 0, 0, 3.2 * s)
  end
  lg.pop()
end

-- A nuclear plant. Everybody on earth reads a cooling tower as power, which is
-- why it is drawn instead of the bolt the trade is marked with everywhere else:
-- the bolt says electricity, and this says the place electricity is made. Two
-- convex halves meeting at the waist, for the same reason the house is two
-- pieces: one concave outline comes back from the triangulator with a corner
-- sliced off.
function Draw.reactor(x, y, r)
  lg.polygon("fill", x - 0.62 * r, y + 0.74 * r, x - 0.30 * r, y - 0.02 * r,
                     x + 0.30 * r, y - 0.02 * r, x + 0.62 * r, y + 0.74 * r)
  lg.polygon("fill", x - 0.30 * r, y - 0.02 * r, x - 0.46 * r, y - 0.70 * r,
                     x + 0.46 * r, y - 0.70 * r, x + 0.30 * r, y - 0.02 * r)
end

-- A wind turbine: mast, hub, three blades. Drawn instead of the cooling tower
-- on a wind park, because the two things are not the same building and the
-- whole point of the island is that it is the one that burns nothing.
function Draw.turbine(x, y, r)
  lg.setLineWidth(math.max(1, r * 0.12))
  lg.line(x, y + 0.9 * r, x, y - 0.25 * r)
  for i = 0, 2 do
    local a = -math.pi / 2 + i * math.pi * 2 / 3
    lg.line(x, y - 0.25 * r, x + math.cos(a) * 0.85 * r, y - 0.25 * r + math.sin(a) * 0.85 * r)
  end
  lg.circle("fill", x, y - 0.25 * r, math.max(1, r * 0.14))
end

-- Every node on the map is a disc: a dark body tinted by its trade, and a rim
-- in the trade colour. Flat, so the symbol on top of it is what the eye finds.
function Draw.disc(x, y, r, color, tint)
  lg.setColor(P.bg)
  lg.circle("fill", x, y, r)
  lg.setColor(P.with(color, tint or 0.20))
  lg.circle("fill", x, y, r)
  lg.setColor(color)
  lg.setLineWidth(math.max(1, r * 0.10))
  lg.circle("line", x, y, r)
end

function Draw.edgePoints(cam, city, e)
  local a, b = city.g.nodes[e.a], city.g.nodes[e.b]
  local ax, ay = cam:toScreen(a.x, a.y)
  local bx, by = cam:toScreen(b.x, b.y)
  local length = math.max(1, math.sqrt((bx-ax)^2 + (by-ay)^2))
  local offset = 0
  for _, other in ipairs(city.g.edges) do
    if other.alive and other.id ~= e.id and
      ((other.a == e.a and other.b == e.b) or (other.b == e.a and other.a == e.b)) then
      offset = ({water=-9, power=-3, beer=3, oil=9})[e.commodity] or 0
      break
    end
  end
  local sign = e.a < e.b and 1 or -1
  local ox, oy = -(by-ay)/length*offset*sign, (bx-ax)/length*offset*sign
  return ax+ox, ay+oy, bx+ox, by+oy
end

--------------------------------------------------------------------------------

-- The plots themselves, and nothing else. A district is a piece of ground,
-- drawn as one: it used to carry rows of decorative houses and a street cross,
-- which is scenery the player cannot touch competing for attention with the
-- icons they can.
--
-- Ground goes down in two passes with the terrain sandwiched between them, so
-- that a tree never lands on top of a price and unowned land dims whatever is
-- standing on it.
-- Only what is on screen is drawn, for every pass over the map. A company on an
-- endless map holds ground and customers it cannot see, and a frame spent
-- drawing them is a frame spent on nothing.
local function drawDistrictGround(city, cam)
  for _, d in ipairs(city.districts or {}) do
    if cam:seesBox(d.x, d.y, d.x + d.w, d.y + d.h) then
      local x, y = cam:toScreen(d.x, d.y)
      local w, h = d.w * cam.scale, d.h * cam.scale
      if d.island then
        -- Rock in the water, with a shoreline. Rounded hard, because nothing
        -- out there was laid out by a surveyor.
        lg.setColor(d.owned and {0.13,0.13,0.11,0.95} or {0.10,0.11,0.11,0.9})
        lg.rectangle("fill",x,y,w,h,math.min(w,h)*0.34)
        lg.setColor(0.52,0.48,0.38,d.owned and 0.55 or 0.3)
        lg.setLineWidth(2)
        lg.rectangle("line",x,y,w,h,math.min(w,h)*0.34)
      else
        lg.setColor(d.owned and {0.075,0.12,0.13,0.8} or {0.09,0.11,0.14,0.5})
        lg.rectangle("fill",x+4,y+4,w-8,h-8,8)
      end
    end
  end
end

local function drawDistrictChrome(city, cam, state)
  lg.setLineWidth(1)
  for _, d in ipairs(city.districts or {}) do
    if cam:seesBox(d.x, d.y, d.x + d.w, d.y + d.h) then
    local x, y = cam:toScreen(d.x, d.y)
    local w, h = d.w * cam.scale, d.h * cam.scale
    if d.owned then
      lg.setColor(P.with(P.panelEdge, 0.55))
      lg.rectangle("line", x, y, w, h)
    else
      -- Ground you do not own is visibly not yours, but still legible enough
      -- to plan towards.
      lg.setColor(P.with(P.bg, 0.62))
      lg.rectangle("fill", x, y, w, h)
      local hot = state.district == d.id
      local buyable = not city:districtError(d.id)
      lg.setColor(P.with(hot and P.energy or buyable and P.good or P.textFaint, hot and 0.9 or 0.45))
      lg.setLineWidth(hot and 2 or 1)
      lg.rectangle("line", x + 2, y + 2, w - 4, h - 4)
      if cam.scale > 0.19 then
        local cx, cy = x + w / 2, y + h / 2
        label(string.upper(d.name), cx, cy - 20, buyable and P.text or P.textDim, R.fonts.body)
        label("$" .. city:districtCost(d), cx, cy + 4,
          buyable and P.energy or P.textFaint, R.fonts.small)
        if not buyable and city:districtAdjacent(d) then
          label("needs more cash", cx, cy + 26, P.textFaint, R.fonts.tiny)
        elseif not city:districtAdjacent(d) then
          label("not adjacent", cx, cy + 26, P.textFaint, R.fonts.tiny)
        end
      end
    end
    if cam.scale > 0.34 and d.owned then
      label(string.upper(d.name), x + w / 2, y + 6, P.textFaint, R.fonts.tiny)
    end
    end
  end
end

-- What the ground is, drawn as one icon standing in the middle of it: a tree
-- for parkland, water for the river, a boulder for bedrock. One icon each,
-- because a scatter of five little ones is texture rather than a symbol, and
-- texture is what makes a map hard to read.
local function scenery(o, x, y, r)
  local spec = City.OBSTACLES[o.kind] or {}
  local c = spec.color or { 0.3, 0.3, 0.3 }
  local s = r * 0.58
  if o.kind == "park" then
    -- A tree: brown trunk, green crown.
    lg.setColor(0.34, 0.24, 0.15, 0.95)
    lg.rectangle("fill", x - s * 0.10, y + s * 0.06, s * 0.20, s * 0.58, s * 0.05)
    lg.setColor(0.24, 0.58, 0.33, 0.95)
    lg.circle("fill", x, y - s * 0.26, s * 0.5)
  elseif o.kind == "river" then
    -- Water: the two-wave mark, and nothing else.
    lg.setColor(c[1], c[2], c[3], 0.75)
    lg.setLineWidth(math.max(1.4, s * 0.16))
    for i = 0, 1 do
      local yy = y + (i - 0.5) * s * 0.62
      local pts = {}
      for j = 0, 16 do
        local t = j / 16
        pts[#pts + 1] = x - s + 2 * s * t
        pts[#pts + 1] = yy + math.sin(t * math.pi * 2) * s * 0.2
      end
      lg.line(pts)
    end
  else
    -- A boulder: angular and taller than it is wide at the peak, so it reads
    -- as rock rather than as a hill.
    lg.setColor(c[1] * 1.7, c[2] * 1.7, c[3] * 1.7, 0.85)
    lg.polygon("fill", x - s * 0.82, y + s * 0.56, x - s * 0.5, y - s * 0.34,
                       x - s * 0.06, y - s * 0.9, x + s * 0.46, y - s * 0.42,
                       x + s * 0.82, y + s * 0.56)
  end
end

--------------------------------------------------------------------------------
-- The outside world
--
-- Three things run along the edge of the map and stop at it: an estuary down
-- the west side, a trunk road across the north, an air freight apron along the
-- south. They are not ground: nothing can be built on them and the company will
-- never own them. They are drawn outside the boundary for exactly that reason,
-- so the one place a haven may stand -- the strip of city just inside the line
-- -- is somewhere you can see rather than somewhere you have to be told about.
--------------------------------------------------------------------------------

-- The sea is drawn from the coast up to whatever the camera can see, because it
-- has no far shore. A harbour has to stand on the strip of city just below the
-- line, so the line is drawn as something you can aim at.
local function drawSea(city, cam, state)
  local left, top = cam:toWorld(cam.vx, cam.vy)
  local right = cam:toWorld(cam.vx + cam.vw, cam.vy)
  if top > 0 then return end
  local x0, y0 = cam:toScreen(left - 200, top - 200)
  local x1, y1 = cam:toScreen(right + 200, 0)
  lg.setColor(0.07, 0.14, 0.22, 1)
  lg.rectangle("fill", x0, y0, x1 - x0, y1 - y0)
  -- Swell, drawn as long lines running with the coast rather than across it.
  lg.setColor(0.30, 0.48, 0.72, 0.26)
  lg.setLineWidth(math.max(1, 1.6 * cam.scale))
  local rows = 7
  for i = 1, rows do
    local wy = -((i / rows) ^ 1.5) * (0 - (top - 200))
    local pts = {}
    for j = 0, 28 do
      local t = j / 28
      local wx = left - 200 + (right - left + 400) * t
      local sx, sy = cam:toScreen(wx, wy + math.sin(t * math.pi * 5 + i * 1.7) * 26)
      pts[#pts + 1] = sx; pts[#pts + 1] = sy
    end
    lg.line(pts)
  end
  -- The coastline itself.
  local cx0, cy = cam:toScreen(left - 200, 0)
  local cx1 = cam:toScreen(right + 200, 0)
  lg.setColor(P.with({ 0.40, 0.64, 0.88 }, 0.6)); lg.setLineWidth(2)
  lg.line(cx0, cy, cx1, cy)

  -- Where a harbour may stand, shown only while the tool is in hand.
  if state and state.tool == "terminal" and (state.havenKind or "port") == "port" then
    local sx, sy = cam:toScreen(left - 200, 0)
    local ex, ey = cam:toScreen(right + 200, City.havenReach)
    lg.setColor(P.with(P.good, 0.12)); lg.rectangle("fill", sx, sy, ex - sx, ey - sy)
    lg.setColor(P.with(P.good, 0.5)); lg.setLineWidth(1)
    lg.rectangle("line", sx, sy, ex - sx, ey - sy)
  end
  if cam.scale > 0.16 then
    local _, ly = cam:toScreen(0, -150)
    label("THE SEA", cam.vx + cam.vw / 2, math.max(cam.vy + 16, ly),
      P.with({ 0.55, 0.75, 0.95 }, 0.8), R.fonts.tiny)
  end
end

local function drawSeams(city, cam)
  for _, s in ipairs(city.deposits or {}) do
    if not s.taken and cam:sees(s.x, s.y, City.seamRange * cam.scale + 40) then
      local x, y = cam:toScreen(s.x, s.y)
      local d = city:districtAt(s.x, s.y)
      -- Surveyors report on ground the company has not bought yet, which is the
      -- whole reason to have them: you can see what a district holds before you
      -- write the cheque.
      if d and (d.owned or (city.orders or {}).surveyors) then
        -- A deposit is the only place its trade can be taken out of the
        -- ground, so it is drawn in that trade's own colour and says which
        -- trade it is. The ring is the ground a works has to stand on.
        local spec = Graph.COMMODITIES[s.commodity] or Graph.COMMODITIES.water
        local r = City.seamRange * cam.scale
        local dim = not d.owned and 0.5 or 1
        lg.setColor(P.with(spec.color, 0.09 * dim)); lg.circle("fill", x, y, r)
        lg.setColor(P.with(spec.color, 0.45 * dim)); lg.setLineWidth(1)
        lg.circle("line", x, y, r)
        Draw.mark(s.commodity, x, y - 2, math.max(2.5, R.sym(9, cam.scale)))
        if cam.scale > 0.45 then
          label(string.upper(s.commodity) .. "  x" .. string.format("%.1f", s.yield),
            x, y + r + 4, spec.color, R.fonts.tiny)
        end
      end
    end
  end
end

function Draw.world(city, cam, state)
  local _,height = R.dimensions()
  lg.setScissor(cam.vx, 80, cam.vw, height-138)
  R.drawGrid(cam, city.bounds.w, city.bounds.h)
  drawSea(city, cam, state)
  drawDistrictGround(city, cam)

  for _, o in ipairs(city.obstacles) do
    if cam:sees(o.x, o.y, o.r * cam.scale + 60) then
    local spec = City.OBSTACLES[o.kind]
    local x, y = cam:toScreen(o.x, o.y)
    local r = o.r * cam.scale
    local freed = city.permits and city.permits[o.kind]
    lg.setColor(P.with(spec.color, freed and 0.10 or 0.16))
    lg.circle("fill", x, y, r)
    lg.setColor(P.with(spec.color, freed and 0.35 or 0.6))
    lg.setLineWidth(1)
    lg.circle("line", x, y, r)
    scenery(o,x,y,r)
    if cam.scale > 0.48 then
      local cross = city:groundCross(o.kind)
      local tag = spec.name .. (cross and (cross > 1 and string.format("  x%.1f", cross) or "  OPEN") or "  CLOSED")
      label(tag, x, y+r+3, freed and P.good or P.textDim, R.fonts.tiny)
    end
    end
  end
  drawDistrictChrome(city, cam, state)
  drawSeams(city, cam)

  -- What each hub covers. Drawn faintly all the time, because the radius is the
  -- thing the player is actually placing, and drawn with its spokes when the
  -- hub is picked up, because that is when you want to see who is on it.
  for _, h in ipairs(city.g:nodesOfKind("exchange")) do
    if cam:sees(h.x, h.y, City.hub.radius * cam.scale + 40) then
    local hx, hy = cam:toScreen(h.x, h.y)
    local r = City.hub.radius * cam.scale
    local live = state.node == h.id or state.hoverNode == h.id or state.tool == "exchange"
    local colour = Graph.KINDS.exchange.color
    lg.setColor(P.with(colour, live and 0.10 or 0.05)); lg.circle("fill", hx, hy, r)
    lg.setColor(P.with(colour, live and 0.55 or 0.22)); lg.setLineWidth(1)
    lg.circle("line", hx, hy, r)
    if live then
      for _, id in ipairs(h.covered or {}) do
        local c = city.g.nodes[id]
        if c and c.alive then
          local cx, cy = cam:toScreen(c.x, c.y)
          lg.setColor(P.with(colour, 0.35)); lg.setLineWidth(1)
          lg.line(hx, hy, cx, cy)
        end
      end
    end
    end
  end

  local selected = city.g.nodes[state.node or 0]
  if selected and selected.alive and selected.kind == "tower" then
    local x,y = cam:toScreen(selected.x,selected.y)
    lg.setColor(P.with(P.energy,0.10)); lg.circle("fill",x,y,220*cam.scale)
    lg.setColor(P.with(P.energy,0.45)); lg.circle("line",x,y,220*cam.scale)
  end

  local route=state.bottlenecks and E.route(city,state.node) or {}
  for _, e in ipairs(city.g.edges) do
    local ea, eb = city.g.nodes[e.a], city.g.nodes[e.b]
    if e.alive and (not state.filter or e.commodity==state.filter)
       and cam:seesBox(math.min(ea.x,eb.x), math.min(ea.y,eb.y),
                       math.max(ea.x,eb.x), math.max(ea.y,eb.y)) then
      local ax, ay, bx, by = Draw.edgePoints(cam,city,e)
      local spec = Graph.COMMODITIES[e.commodity] or Graph.COMMODITIES.water
      local c = spec.color
      local width = math.min(10,2+e.capMax*0.6)*cam.scale+1
      if state.bottlenecks and (route[e.id] or e.leaking or math.abs(city.detail.edge[e.id] or 0)>=e.cap) then
        lg.setColor(P.with((e.leaking or math.abs(city.detail.edge[e.id] or 0)>=e.cap) and P.warn or P.flow,0.3))
        lg.setLineWidth(width+10); lg.line(ax,ay,bx,by)
      end
      if state.edge == e.id or state.hoverEdge == e.id then
        lg.setColor(P.with(P.text,0.7)); lg.setLineWidth(width+5); lg.line(ax,ay,bx,by)
      end
      -- Track reads as track: two steel rails on sleepers, tinted by what it
      -- happens to be hauling.
      if e.rail then
        -- A bulk line is drawn as the mode it is, with one stripe per wagon in
        -- the colour of what that wagon carries. A glance says both what this
        -- line is and what is on it.
        local mode = City.MODES[e.bulk or "rail"]
        local dx,dy = bx-ax,by-ay
        local len = math.max(1,math.sqrt(dx*dx+dy*dy))
        local nx,ny = -dy/len, dx/len
        local wide = math.max(2, 3.4*cam.scale)
        lg.setColor(P.with(mode.colour,0.9)); lg.setLineWidth(wide)
        lg.line(ax,ay,bx,by)
        if e.bulk == "rail" or not e.bulk then
          lg.setColor(P.with(P.textFaint,0.6)); lg.setLineWidth(math.max(1,1.4*cam.scale))
          local step = math.max(9,16*cam.scale)
          for d = 0,len,step do
            local t = d/len
            lg.line(ax+dx*t-nx*wide, ay+dy*t-ny*wide, ax+dx*t+nx*wide, ay+dy*t+ny*wide)
          end
        elseif e.bulk == "sea" then
          lg.setColor(P.with(mode.colour,0.35)); lg.setLineWidth(wide*2.4)
          lg.line(ax,ay,bx,by)
        end
        local loaded = {}
        for _,name in ipairs(Graph.TRADES) do
          if (e.wagons or {})[name] then loaded[#loaded+1] = name end
        end
        for _,name in ipairs(Graph.ALL) do
          if (e.wagons or {})[name] and not (Graph.COMMODITIES[name].role == "utility") then
            loaded[#loaded+1] = name
          end
        end
        if #loaded == 0 and e.commodity then loaded[1] = e.commodity end
        for i,name in ipairs(loaded) do
          local off = (i - (#loaded+1)/2) * math.max(1.6, 2.6*cam.scale)
          lg.setColor(P.with(Graph.COMMODITIES[name].color,0.95))
          lg.setLineWidth(math.max(1,1.8*cam.scale))
          lg.line(ax+nx*off, ay+ny*off, bx+nx*off, by+ny*off)
        end
      end
      -- Oil mains are drawn as their contents: a black bore in a steel casing.
      if e.rail then
        -- already drawn above
      elseif e.commodity == "oil" then
        lg.setColor(P.with(c, e.cap == 0 and 0.22 or 0.45))
        lg.setLineWidth(width + 2); lg.line(ax,ay,bx,by)
      end
      if not e.rail then
        lg.setColor(P.with(e.leaking and P.bad or (e.commodity == "oil" and spec.fill or c),
          e.cap == 0 and 0.35 or (e.commodity == "oil" and 0.95 or 0.65)))
        lg.setLineWidth(width); lg.line(ax,ay,bx,by)
      end
      -- A lined main wears a casing stripe; armour wears two.
      local grade = e.grade or 1
      if grade > 1 and not e.rail and cam.scale > 0.42 then
        lg.setColor(P.with(P.good, grade > 2 and 0.85 or 0.5))
        lg.setLineWidth(1)
        local dx, dy = bx-ax, by-ay
        local len = math.max(1, math.sqrt(dx*dx+dy*dy))
        local nx, ny = -dy/len*(width/2+2), dx/len*(width/2+2)
        lg.line(ax+nx,ay+ny,bx+nx,by+ny)
        if grade > 2 then lg.line(ax-nx,ay-ny,bx-nx,by-ny) end
      end
      local flow = city.detail.edge[e.id] or 0
      if flow ~= 0 then
        local count = math.min(12,math.ceil(math.abs(flow)))
        for i=1,count do
          local t = (R.t*0.22+i/count)%1
          if flow < 0 then t = 1-t end
          lg.setColor(c)
          lg.circle("fill", ax+(bx-ax)*t, ay+(by-ay)*t, math.max(1, R.sym(2.8, cam.scale)))
        end
      end
      if e.leaking then
        local x,y = (ax+bx)/2,(ay+by)/2
        lg.setColor(P.with(P.bad,0.6+0.3*math.sin(R.t*5)))
        lg.setLineWidth(2); lg.circle("line",x,y,10+2*math.sin(R.t*4))
      end
      if cam.scale > 0.8 or e.leaking or state.edge == e.id then
        label(string.format("%d/%d",math.abs(flow),e.cap),(ax+bx)/2,(ay+by)/2-22,e.leaking and P.bad or P.textDim,R.fonts.tiny)
      end
    end
  end

  for _, n in ipairs(city.g:aliveNodes()) do
    if (not state.filter or not n.commodity or n.commodity==state.filter)
       and cam:sees(n.x, n.y, 90) then
    local x,y = cam:toScreen(n.x,n.y)
    -- Sized through R.sym, so pulling the camera back always makes a node
    -- smaller. The symbol inside is drawn at every zoom: one flat shape reads
    -- at eleven pixels, and swapping it for something else on the way out
    -- would only mean two things to learn instead of one.
    local r = math.max(3, R.sym(n.kind == "source" and 23 or 17, cam.scale))
    -- Two thresholds, in pixels of disc radius. A label wider than the thing
    -- it names is worse than no label, and a pip under a pixel is grit.
    local named, fine = r >= 7.5, r >= 10
    local spec = n.commodity and Graph.COMMODITIES[n.commodity]
      or (n.makes and Graph.COMMODITIES[n.makes])
    local color = spec and spec.color or Graph.KINDS[n.kind].color
    local served = city.served[n.id] or 0
    if n.prospect then color = P.textDim end
    local supplied = not n.prospect and served >= (n.demand or 0)
    if state.node == n.id or state.hoverNode == n.id then
      lg.setColor(P.text); lg.setLineWidth(math.max(1, r * 0.09))
      lg.circle("line", x, y, r + math.max(4, r * 0.5))
    end
    if n.kind == "client" and not n.prospect and served < n.demand then
      lg.setColor(P.with(n.grace == 1 and P.bad or P.warn,0.65))
      lg.setLineWidth(math.max(1.3, r * 0.13))
      lg.arc("line","open",x,y,r + math.max(3, r * 0.3),
        -math.pi/2,-math.pi/2+math.pi*2*(n.grace/n.patience))
    end
    if n.kind == "client" and supplied then
      lg.setColor(P.with(P.good,0.10)); lg.circle("fill",x,y,r * 1.42)
    end
    Draw.disc(x, y, r, color, n.prospect and 0.14 or 0.20)

    if n.kind == "client" then
      lg.setColor(color)
      Draw.clientGlyph(n.clientType, x, y + r * 0.06, r / 15)
      if named then
        local title = n.prospect and "OFFER" or n.supplyClosed and "SHUT"
          or string.format("%d/%d",served,n.demand)
        label(title,x,y+r+6,n.prospect and P.energy or (served>=n.demand and P.good or P.warn))
      end
      if cam.scale > 0.72 then
        local premium = city:ratePremium(n)
        local tag = E.clientName(city,n) .. "  $" .. n.rate
        label(tag, x, y-r-21,
          premium > 0.10 and P.good or premium < -0.10 and P.bad or P.textDim, R.fonts.tiny)
      end
    elseif n.kind == "source" then
      if n.plant == "wind" then
        lg.setColor(color)
        Draw.turbine(x, y, r * 0.9)
      elseif n.plant == "nuclear" then
        lg.setColor(color)
        Draw.reactor(x, y - r * 0.04, r * 0.86)
      else
        Draw.mark(n.commodity, x, y - r * 0.04, r * 0.58)
      end
      local level = n.level or 1
      -- How hard the well is actually being worked, not just how deep it is.
      -- A well reading 22/22 is the reason a customer downstream is short, and
      -- that has to be visible without opening anything.
      local drawn = (city.produced or {})[n.id] or 0
      local maxed = drawn >= (n.output or 0) and (n.output or 0) > 0
      if named then
        label((n.plant and string.upper((City.PLANTS[n.plant] or {}).name or "PLANT")
          or string.upper(n.commodity))
          .. "  " .. drawn .. "/" .. (n.output or 0),
          x, y+r+8, maxed and P.warn or color)
      end
      -- A capacity bar across the bottom of the well, so the ratio reads at a
      -- glance from any zoom the labels survive.
      if cam.scale > 0.5 and (n.output or 0) > 0 then
        local bw = r * 1.5
        local frac = math.min(1, drawn / n.output)
        lg.setColor(P.with(P.textFaint, 0.7))
        lg.rectangle("fill", x - bw/2, y + r + 24, bw, 3, 1.5)
        lg.setColor(maxed and P.warn or color)
        lg.rectangle("fill", x - bw/2, y + r + 24, bw * frac, 3, 1.5)
      end
      if fine then
        -- Level pips: how far the well has been deepened.
        local pips, gap = City.sourceMaxLevel, math.max(3.6, r * 0.25)
        local pr = math.max(1, r * 0.085)
        for i = 1, pips do
          lg.setColor(i <= level and color or P.with(P.textFaint, 0.6))
          lg.setLineWidth(math.max(0.9, pr * 0.5))
          lg.circle(i <= level and "fill" or "line",
            x - (pips - 1) * gap / 2 + (i - 1) * gap, y - r - pr * 3, pr)
        end
      end
      if n.seam then label("SEAM", x, y-r-24, P.energy, R.fonts.tiny) end
    else
      lg.setColor(color)
      Draw.structureGlyph(n.kind, x, y, r / 15)
      if n.kind == "gate" then
        if named then
          label(tostring(n.throughput or 0), x, y+r+6,
            (n.throughput or 0) == 0 and P.bad or P.warn)
        end
      elseif n.kind == "terminal" then
        if named then
          label((City.HAVENS[n.haven or "port"] or {}).name or "HAVEN", x, y+r+6, color)
        end
        if cam.scale > 0.6 then
          local landed = (city.produced or {})[n.id] or 0
          local _, bill = city:importBill()
          label(landed > 0 and (landed .. " landed  -$" .. math.floor((bill[n.id] or 0) + 0.5))
            or "no freight moving", x, y-r-21, landed > 0 and P.textDim or P.warn, R.fonts.tiny)
        end
      elseif n.kind == "works" then
        local recipe = City.RECIPES[n.recipe or ""]
        if named and recipe then
          label((n.ready or 0) .. "/" .. recipe.rate .. " " .. recipe.makes, x, y+r+6,
            (n.ready or 0) >= recipe.rate and P.good or (n.ready or 0) > 0 and P.warn or P.bad)
        end
        if cam.scale > 0.6 and recipe then
          label(recipe.name, x, y-r-21, P.textDim, R.fonts.tiny)
        end
      elseif n.kind == "depot" then
        if named then
          label((n.stored or 0) .. "/" .. (n.capacityStore or City.depotCapacity), x, y+r+6,
            (n.stored or 0) > 0 and P.good or P.textDim)
        end
      end
      -- Port ring: one pip per port, filled as the ports are taken up.
      if fine then
        local pr = math.max(1, R.sym(1.9, cam.scale))
        for i=1,n.ports do
          local a = i/n.ports*math.pi*2
          lg.setColor(i<=city.g:degree(n.id) and color or P.textFaint)
          lg.circle("fill",x+math.cos(a)*(r+pr*1.6),y+math.sin(a)*(r+pr*1.6),pr)
        end
      end
    end
    end
  end

  if city.day==1 and not city.guideDismissed and city.unserved>0 then
    local x,y=cam:toScreen(city.firstSource.x,city.firstSource.y)
    lg.setColor(P.with(P.good,0.45)); lg.setLineWidth(2)
    lg.circle("line",x,y,34+5*math.sin(R.t*3))
  end
  R.drawEffects(cam)
  local mx,my = love.mouse.getPosition()
  if state.drag then
    local from = city.g.nodes[state.drag]
    local x,y = cam:toScreen(from.x,from.y)
    local target = state.hoverNode
    local err = target and city:pipeError(from.id,target,state.commodity,state.rail)
    lg.setColor(P.with(state.rail and P.accent or P.textDim,0.25)); lg.setLineWidth(1)
    lg.circle("line",x,y,city:rangeBetween(from.id,from.id,state.rail)*cam.scale)
    lg.setColor(err and P.bad or P.good); lg.setLineWidth(2); lg.line(x,y,mx,my)
    if target and target~=from.id then
      if err then
        label(err,(x+mx)/2,(y+my)/2-24,P.bad)
      else
        -- The quote, itemised, right where the pipe is being drawn.
        local q = city:pipeQuote(from.id,target,state.commodity,state.capacity,state.rail)
        local p=E.pipePreview(city,from.id,target,state.commodity,state.capacity,state.rail)
        if not p.error then
          local unsigned=city.g.nodes[target].prospect
          local note=unsigned and "Unsigned offer: sign before earning income."
            or p.displaced>0 and (p.displaced.." other customers would receive less.")
          local qw,qh=math.min(350,cam.vw-32),note and 136 or 114
          local qx=math.max(cam.vx+16,math.min(cam.vx+cam.vw-qw-16,mx+20))
          local qy=math.max(202,math.min(height-74-qh,my-qh-22))
          lg.setColor(P.panel); lg.rectangle("fill",qx,qy,qw,qh,7)
          lg.setColor(p.cash<0 and P.bad or P.flow); lg.setLineWidth(1)
          lg.rectangle("line",qx,qy,qw,qh,7)
          lg.setFont(R.fonts.mid); lg.setColor(P.energy)
          lg.print("Build for $"..q.total,qx+14,qy+10)
          lg.setFont(R.fonts.small); lg.setColor(P.textDim)
          lg.print(string.format("%dm  /  %s $%d  /  %s $%d  /  bore $%d",math.floor(q.metres),
            state.rail and "yards" or "tie-in",q.tiein,state.rail and "track" or "trench",q.trench,q.bore),qx+14,qy+38)
          local detail=string.format("Net change $%+d/day",p.net)
          if p.demand then detail=p.delivery.."/"..p.demand.." supplied  /  "..detail end
          lg.setFont(R.fonts.body); lg.setColor(P.good); lg.print(detail,qx+14,qy+61)
          lg.setColor(p.cash<0 and P.bad or P.text)
          lg.print(p.cash<0 and ("Need $"..(-p.cash).." more cash") or ("Cash after building: $"..p.cash),qx+14,qy+84)
          if note then lg.setFont(R.fonts.small); lg.setColor(P.warn); lg.print(note,qx+14,qy+111) end
        end
      end
    end
  elseif state.tool and mx>cam.vx and my>130 and my<height-58 then
    local wx,wy = cam:toWorld(mx,my)
    local err, cost, seam
    if state.tool=="source" then
      err = city:sourceError(state.commodity,wx,wy,state.plant)
      cost, seam = city:sourceCost(state.commodity,wx,wy,state.plant)
      if not err and state.commodity=="power" then
        err = city:materialError(city:materialsFor("source",state.plant))
      end
    else
      err = city:placementError(wx,wy)
      cost = city:nodeCost(state.tool)
      if state.tool=="terminal" then
        local kind = state.havenKind or "port"
        cost = city:havenCost(kind)
        if not err then err = select(2, city:havenSite(wx,wy,kind)) end
      elseif state.tool=="works" then
        cost = (City.RECIPES[state.recipe or ""] or {}).cost or cost
      end
      -- The bill of materials, before the click rather than after it.
      if not err then
        local bill = state.tool=="works" and city:materialsFor("works")
          or city:materialsFor(state.tool)
        err = city:materialError(bill)
      end
    end
    local color = (err or cost>city.money) and P.bad or P.good
    lg.setColor(P.with(color,0.3)); lg.setLineWidth(1)
    local range = state.tool=="pump" and 520 or state.tool=="tower" and 220 or 300
    lg.circle("line",mx,my,range*cam.scale)
    lg.setColor(color); lg.circle("line",mx,my,18*cam.scale)
    label(err or ("$"..cost),mx,my+30,color)
    if seam and not err then label("SEAM: x"..string.format("%.1f",seam.yield).." output",mx,my+48,P.energy,R.fonts.tiny) end
  end
  lg.setScissor()
end

return Draw
