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
-- tankard, a chimney.
--------------------------------------------------------------------------------

function Draw.clientGlyph(kind, x, y, s)
  s = s or 1
  local r, g, b, a = trim()
  lg.push()
  lg.translate(x, y)
  lg.setColor(r, g, b, a)

  if kind == "factory" then
    -- A works: a shed with a stack. Two rectangles in one colour merge into
    -- one silhouette, which is the whole drawing.
    lg.rectangle("fill", -3.2 * s, -13 * s, 3.2 * s, 11.5 * s)
    lg.rectangle("fill", -4.2 * s, -13.6 * s, 5.2 * s, 1.8 * s, 0.4 * s)
    lg.rectangle("fill", -10 * s, -2 * s, 20 * s, 10 * s, 0.8 * s)
  elseif kind == "pub" then
    -- A tankard. The handle is a single arc, not a ring with a hole in it.
    lg.polygon("fill", -7 * s, -8 * s, 4.4 * s, -8 * s, 3 * s, 8 * s, -5.6 * s, 8 * s)
    stroke(20 * s, 0.13)
    lg.arc("line", "open", 4 * s, -1 * s, 4.4 * s, -math.pi * 0.46, math.pi * 0.46)
  elseif kind == "workshop" then
    -- The saw-tooth roof every light-industrial shed in the world has.
    lg.polygon("fill", -9 * s, 8 * s, -9 * s, -7 * s, -3 * s, -1 * s,
                       -3 * s, -7 * s, 3 * s, -1 * s, 3 * s, -7 * s,
                        9 * s, -1 * s, 9 * s, 8 * s)
  elseif kind == "estate" then
    -- Two flat-roofed blocks: housing stacked rather than spread, and nothing
    -- like the house or the saw-tooth shed in outline.
    lg.rectangle("fill", -9.5 * s, -9.5 * s, 9 * s, 17.5 * s, 0.6 * s)
    lg.rectangle("fill", 1 * s, -3.5 * s, 8.5 * s, 11.5 * s, 0.6 * s)
  else
    -- A house: a pitched roof on four walls, and nothing else.
    lg.polygon("fill", -9 * s, 8 * s, -9 * s, -1 * s, 0, -9.5 * s,
                        9 * s, -1 * s, 9 * s, 8 * s)
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
    -- A casing with the impeller in it, pointing the way it pushes.
    lg.circle("line", 0, 0, 7 * s)
    lg.polygon("fill", -3 * s, -4 * s, 4.6 * s, 0, -3 * s, 4 * s)
    lg.line(-10 * s, 0, -7 * s, 0)
    lg.line(7 * s, 0, 10 * s, 0)
  elseif kind == "tower" then
    -- A tank up on splayed legs: a water tower, from any distance.
    lg.rectangle("fill", -7 * s, -10 * s, 14 * s, 7.5 * s, 1 * s)
    lg.line(-4.6 * s, -2.5 * s, -7.4 * s, 9 * s)
    lg.line(4.6 * s, -2.5 * s, 7.4 * s, 9 * s)
  elseif kind == "gate" then
    -- A valve: two seats closing on the line, and the wheel you close them
    -- with. The wheel is what says a human sets this one by hand.
    lg.line(-10 * s, 0, -4.4 * s, 0)
    lg.line(4.4 * s, 0, 10 * s, 0)
    lg.polygon("fill", -4.4 * s, -6 * s, -4.4 * s, 6 * s, 0, 0)
    lg.polygon("fill", 4.4 * s, -6 * s, 4.4 * s, 6 * s, 0, 0)
    lg.line(0, -4 * s, 0, -8.5 * s)
    lg.line(-4 * s, -9 * s, 4 * s, -9 * s)
  elseif kind == "depot" then
    -- Crates: what a depot is full of.
    lg.rectangle("fill", -9 * s, -0.5 * s, 8.4 * s, 8.4 * s, 0.6 * s)
    lg.rectangle("fill", 0.6 * s, -0.5 * s, 8.4 * s, 8.4 * s, 0.6 * s)
    lg.rectangle("fill", -4.2 * s, -9.4 * s, 8.4 * s, 8.4 * s, 0.6 * s)
  elseif kind == "terminal" then
    -- A crane on a quay: the generic haven, whichever door it happens to be.
    lg.rectangle("fill", -10 * s, 7 * s, 20 * s, 2.4 * s, 0.8 * s)
    lg.rectangle("fill", -4.6 * s, -9 * s, 2.6 * s, 16 * s, 0.6 * s)
    lg.rectangle("fill", -4.6 * s, -9 * s, 13.6 * s, 2.4 * s, 0.6 * s)
    lg.line(7.8 * s, -6.6 * s, 7.8 * s, 0)
    lg.rectangle("fill", 5.4 * s, 0, 4.8 * s, 4 * s, 0.6 * s)
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

local function drawDistricts(city, cam, state)
  lg.setLineWidth(1)
  for _, d in ipairs(city.districts or {}) do
    local x, y = cam:toScreen(d.x, d.y)
    local w, h = d.w * cam.scale, d.h * cam.scale
    -- Unbadged background buildings are deliberately quieter than customers.
    lg.setColor(d.owned and {0.075,0.12,0.13,0.8} or {0.09,0.11,0.14,0.5})
    lg.rectangle("fill",x+4,y+4,w-8,h-8,8)
    if x+w>cam.vx and x<cam.vx+cam.vw and y+h>130 and y<cam.vy+cam.vh then
      for col=1,5 do
        for row=1,3 do
          local px,py=x+col*w/6,y+row*h/4
          lg.setColor(P.with(P.textDim,d.owned and 0.09 or 0.04)); lg.setLineWidth(math.max(1,3*cam.scale))
          lg.line(px-w/14,py+h/22,px+w/14,py+h/22)
          for lot=1,5 do
            local lx,ly=px+(lot-3)*24*cam.scale,py+((lot+d.id)%2)*12*cam.scale
            local bw,bh=(14+(lot%2)*5)*cam.scale,(18+(d.id%3)*4)*cam.scale
            lg.setColor(0.02,0.04,0.055,0.3); lg.rectangle("fill",lx+3*cam.scale,ly+3*cam.scale,bw,bh,2)
            lg.setColor(0.25,0.30+(d.id%2)*0.04,0.32,d.owned and 0.3 or 0.12)
            lg.rectangle("fill",lx,ly,bw,bh,2)
            lg.setColor(0.41,0.46,0.45,d.owned and 0.18 or 0.08)
            lg.line(lx,ly,lx+bw,ly,lx+bw,ly+bh)
          end
        end
      end
    end
    lg.setColor(P.with(P.textDim,d.owned and 0.12 or 0.06)); lg.setLineWidth(math.max(2,7*cam.scale))
    lg.line(x+12,y+h/2,x+w-12,y+h/2)
    lg.line(x+w/2,y+12,x+w/2,y+h-12)
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
      if cam.scale > 0.22 then
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
    -- Three districts can host a haven. Say so on the ground, so the choice of
    -- which district to buy is made looking at the map.
    local spec = City.DISTRICTS[d.id]
    if spec and spec.haven and cam.scale > 0.26 then
      local hv = City.HAVENS[spec.haven]
      local hx,hy=x+w/2,y+h-48
      lg.setColor(P.with(P.energy,d.owned and 0.7 or 0.4)); lg.setLineWidth(2)
      if spec.haven=="port" then
        lg.line(hx-18,hy+10,hx-18,hy-15,hx+22,hy-15,hx+22,hy)
        lg.line(hx-27,hy+12,hx+30,hy+12)
      elseif spec.haven=="airfield" then
        lg.line(hx,hy-16,hx,hy+15); lg.line(hx-20,hy,hx+20,hy)
        lg.line(hx-9,hy+12,hx+9,hy+12)
      else
        lg.line(hx-24,hy+12,hx-24,hy-9,hx+24,hy-9,hx+24,hy+12)
        lg.line(hx-7,hy-5,hx-7,hy+12); lg.line(hx+7,hy-5,hx+7,hy+12)
      end
      label(hv.name, x + w / 2, y + h - 22,
        d.owned and P.energy or P.with(P.energy, 0.55), R.fonts.tiny)
    end
  end
end

-- What the ground is, drawn as the thing it is: trees for parkland, water for
-- the river, boulders for bedrock. Few shapes and large ones, so the ground
-- reads at a glance from across the city, and all of them inside the circle
-- the game will not let you build in.
local function scenery(o, x, y, r)
  local spec = City.OBSTACLES[o.kind] or {}
  local c = spec.color or { 0.3, 0.3, 0.3 }
  if o.kind == "park" then
    local h = r * 0.38
    for _, p in ipairs({ {0, -0.36}, {-0.44, 0.02}, {0.44, 0.02},
                         {-0.20, 0.42}, {0.24, 0.40} }) do
      local tx, ty = x + p[1] * r, y + p[2] * r
      lg.setColor(c[1] * 0.55, c[2] * 0.55, c[3] * 0.5, 0.9)
      lg.rectangle("fill", tx - math.max(0.5, h * 0.09), ty + h * 0.10,
        math.max(1, h * 0.18), h * 0.34)
      lg.setColor(c[1] * 0.8, c[2] * 1.05, c[3] * 0.85, 0.95)
      lg.polygon("fill", tx, ty - h * 0.92,
        tx - h * 0.5, ty + h * 0.16, tx + h * 0.5, ty + h * 0.16)
    end
  elseif o.kind == "river" then
    lg.setColor(c[1], c[2], c[3], 0.5)
    lg.setLineWidth(math.max(1.2, r * 0.06))
    for i = -1, 1 do
      local yy = y + i * r * 0.4
      local half = math.sqrt(math.max(0, r * r - (yy - y) ^ 2)) * 0.78
      local pts = {}
      for j = 0, 12 do
        local t = j / 12
        pts[#pts + 1] = x - half + 2 * half * t
        pts[#pts + 1] = yy + math.sin(t * math.pi * 2 + i) * r * 0.09
      end
      lg.line(pts)
    end
  else
    for _, p in ipairs({ {-0.28, -0.12, 0.5}, {0.3, 0.1, 0.4}, {-0.08, 0.44, 0.32} }) do
      local bx, by, bs = x + p[1] * r, y + p[2] * r, r * p[3]
      lg.setColor(c[1] * 1.5, c[2] * 1.5, c[3] * 1.5, 0.8)
      lg.polygon("fill", bx - bs * 0.6, by + bs * 0.4,
                         bx - bs * 0.08, by - bs * 0.5, bx + bs * 0.6, by + bs * 0.4)
    end
  end
end

local function drawSeams(city, cam)
  for _, s in ipairs(city.deposits or {}) do
    if not s.taken then
      local x, y = cam:toScreen(s.x, s.y)
      local d = city:districtAt(s.x, s.y)
      if d and d.owned then
        local r = City.seamRange * cam.scale
        lg.setColor(P.with(P.energy, 0.10)); lg.circle("fill", x, y, r)
        lg.setColor(P.with(P.energy, 0.40)); lg.setLineWidth(1)
        lg.circle("line", x, y, r)
        Draw.mark(s.commodity, x, y - 2, math.max(2.5, R.sym(9, cam.scale)))
        if cam.scale > 0.45 then
          label("SEAM  x" .. string.format("%.1f", s.yield), x, y + r + 4, P.energy, R.fonts.tiny)
        end
      end
    end
  end
end

function Draw.world(city, cam, state)
  local _,height = R.dimensions()
  lg.setScissor(cam.vx, 80, cam.vw, height-138)
  R.drawGrid(cam, city.bounds.w, city.bounds.h)
  drawDistricts(city, cam, state)

  for _, o in ipairs(city.obstacles) do
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
  drawSeams(city, cam)

  local selected = city.g.nodes[state.node or 0]
  if selected and selected.alive and selected.kind == "tower" then
    local x,y = cam:toScreen(selected.x,selected.y)
    lg.setColor(P.with(P.energy,0.10)); lg.circle("fill",x,y,220*cam.scale)
    lg.setColor(P.with(P.energy,0.45)); lg.circle("line",x,y,220*cam.scale)
  end

  local route=state.bottlenecks and E.route(city,state.node) or {}
  for _, e in ipairs(city.g.edges) do
    if e.alive and (not state.filter or e.commodity==state.filter) then
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
        local dx,dy = bx-ax,by-ay
        local len = math.max(1,math.sqrt(dx*dx+dy*dy))
        local nx,ny = -dy/len*(width*0.45+1.5), dx/len*(width*0.45+1.5)
        lg.setColor(P.with(P.textFaint,0.75)); lg.setLineWidth(math.max(1,1.6*cam.scale))
        local step = math.max(9,16*cam.scale)
        for d = 0,len,step do
          local t = d/len
          local sx,sy = ax+dx*t, ay+dy*t
          lg.line(sx-nx*1.6,sy-ny*1.6,sx+nx*1.6,sy+ny*1.6)
        end
        lg.setColor(P.with(c,0.85)); lg.setLineWidth(math.max(1.2,2*cam.scale))
        lg.line(ax+nx,ay+ny,bx+nx,by+ny)
        lg.line(ax-nx,ay-ny,bx-nx,by-ny)
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
    if not state.filter or not n.commodity or n.commodity==state.filter then
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
      Draw.mark(n.commodity, x, y - r * 0.04, r * 0.58)
      local level = n.level or 1
      -- How hard the well is actually being worked, not just how deep it is.
      -- A well reading 22/22 is the reason a customer downstream is short, and
      -- that has to be visible without opening anything.
      local drawn = (city.produced or {})[n.id] or 0
      local maxed = drawn >= (n.output or 0) and (n.output or 0) > 0
      if named then
        label(string.upper(n.commodity) .. "  " .. drawn .. "/" .. (n.output or 0),
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
          label((City.HAVENS[n.haven or "port"] or {}).name or "TERMINAL", x, y+r+6, color)
        end
        if cam.scale > 0.6 then
          local landed = (city.produced or {})[n.id] or 0
          label("lands "..landed.."/"..(n.output or 0), x, y-r-21,
            landed >= (n.output or 0) and P.warn or P.textDim, R.fonts.tiny)
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
    local err = city:placementError(wx,wy)
    local cost, seam
    if state.tool=="source" then cost, seam = city:sourceCost(state.commodity,wx,wy)
    else cost = city:nodeCost(state.tool) end
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
