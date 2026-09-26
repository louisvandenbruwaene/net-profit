local P = require("palette")
local Graph = require("graph")
local City = require("city")
local R = require("render")
local E = require("experience")
local Scenery = require("scenery")
local Shape = require("terrain_shape")
local Draw = {}
local lg = love.graphics

local labels,occupied,segments={},{},{}
local labelPriority=0

-- Grids other than the selected one are drawn faded, so the grid being built
-- stands out. While fading, every colour set is scaled, and the colour a glyph
-- reads back is unscaled so it is not faded twice. Set to 0 by Draw.world when
-- the player has switched on solo view, hiding other grids outright.
local UNFOCUSED_ALPHA=0.4
local fade=1
local setColor,getColor=lg.setColor,lg.getColor
local function fadedSetColor(r,g,b,a)
  if type(r)=="table" then r,g,b,a=r[1],r[2],r[3],r[4] end
  setColor(r,g,b,(a or 1)*fade)
end
local function fadedGetColor()
  local r,g,b,a=getColor()
  return r,g,b,(a or 1)/fade
end
local function fading(on)
  fade=on and UNFOCUSED_ALPHA or 1
  lg.setColor=on and fadedSetColor or setColor
  lg.getColor=on and fadedGetColor or getColor
end

local function label(value,x,y,color,font)
  labels[#labels+1]={text=tostring(value),x=x,y=y,color=color or P.text,font=font or R.fonts.small,priority=labelPriority,order=#labels+1,fade=fade}
end
local function crossesBox(line,x,y,w,h)
  local t0,t1=0,1
  local dx,dy=line.bx-line.ax,line.by-line.ay
  local pad=line.pad or 4
  x,y,w,h=x-pad,y-pad,w+pad*2,h+pad*2
  for _,v in ipairs({{-dx,line.ax-x},{dx,x+w-line.ax},{-dy,line.ay-y},{dy,y+h-line.ay}}) do
    local p,q=v[1],v[2]
    if p==0 then if q<0 then return false end
    elseif p<0 then t0=math.max(t0,q/p)
    else t1=math.min(t1,q/p) end
    if t0>t1 then return false end
  end
  return true
end
local function drawLabels(cam)
  table.sort(labels,function(a,b) return a.priority>b.priority or (a.priority==b.priority and a.order<b.order) end)
  for _,item in ipairs(labels) do
    local f=item.font
    local w,h=require("symbol_font").width(item.text,f)+8,f:getHeight()+4
    local x,y=item.x-w/2,item.y-2
    local clear=x>=cam.vx+4 and x+w<=cam.vx+cam.vw-4 and y>=cam.vy and y+h<=cam.vy+cam.vh
    for _,r in ipairs(occupied) do
      if x<r.x+r.w and x+w>r.x and y<r.y+r.h and y+h>r.y then clear=false; break end
    end
    if clear then
      for _,line in ipairs(segments) do
        if crossesBox(line,x,y,w,h) then clear=false; break end
      end
    end
    if clear then
      occupied[#occupied+1]={x=x,y=y,w=w,h=h}
      local c=item.color
      lg.setColor(P.with(P.bg,0.94*item.fade)); lg.rectangle("fill",x,y,w,h,3)
      lg.setFont(f); lg.setColor(c[1],c[2],c[3],(c[4] or 1)*item.fade); lg.print(item.text,x+4,y+2)
    end
  end
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
  if commodity=="steel" then
    lg.setColor(P.with(spec.color,a))
    lg.rectangle("fill",x-r,y-r,r*2,r*.4); lg.rectangle("fill",x-r*.22,y-r,r*.44,r*2); lg.rectangle("fill",x-r,y+r*.6,r*2,r*.4); return
  elseif commodity=="panels" or commodity=="glass" then
    lg.setColor(P.with(spec.fill,a)); lg.rectangle("fill",x-r,y-r*.75,r*2,r*1.5)
    lg.setColor(P.with(spec.color,a)); stroke(r*2,.08); lg.rectangle("line",x-r,y-r*.75,r*2,r*1.5)
    if commodity=="panels" then lg.line(x-r,y,x+r,y); lg.line(x-r/3,y-r*.75,x-r/3,y+r*.75); lg.line(x+r/3,y-r*.75,x+r/3,y+r*.75)
    else lg.line(x-r*.6,y+r*.4,x+r*.3,y-r*.4) end; return
  elseif commodity=="timber" or commodity=="planks" then
    lg.setColor(P.with(spec.color,a)); stroke(r*2,.12)
    for j=-1,1 do lg.line(x-r,y+j*r*.65,x+r,y+j*r*.65) end
    if commodity=="timber" then lg.circle("line",x+r*.7,y,r*.35) end; return
  elseif commodity=="rock" or commodity=="ore" or commodity=="coke" then
    lg.setColor(P.with(spec.fill,a)); lg.polygon("fill",x-r,y+r*.7,x-r*.7,y-r*.4,x+r*.2,y-r,x+r,y+r*.7)
    lg.setColor(P.with(spec.color,a)); stroke(r*2,.1); lg.polygon("line",x-r,y+r*.7,x-r*.7,y-r*.4,x+r*.2,y-r,x+r,y+r*.7); return
  elseif spec.mark=="gem" then
    lg.setColor(P.with(spec.color,a)); stroke(r*2,.1)
    lg.polygon("line",x-r,y-r*.4,x-r*.5,y-r,x+r*.5,y-r,x+r,y-r*.4,x,y+r)
    lg.line(x-r,y-r*.4,x+r,y-r*.4); lg.line(x-r*.5,y-r,x,y+r,x+r*.5,y-r); return
  end
  if spec.mark=="salt" then
    lg.setColor(P.with(spec.color,a)); stroke(r*2,.1); lg.circle("line",x,y,r*.8); lg.line(x-r,y,x+r,y); return
  elseif spec.mark=="box" or spec.mark=="gem" then
    lg.setColor(P.with(spec.fill,a)); lg.polygon("fill",x-r,y-r*.4,x,y-r,x+r,y-r*.4,x+r,y+r*.5,x,y+r,x-r,y+r*.5)
    lg.setColor(P.with(spec.color,a)); stroke(r*2,.09)
    lg.polygon("line",x-r,y-r*.4,x,y-r,x+r,y-r*.4,x+r,y+r*.5,x,y+r,x-r,y+r*.5)
    lg.line(x-r,y-r*.4,x,y,x+r,y-r*.4); lg.line(x,y,x,y+r)
    if commodity=="steel" then lg.line(x-r*.7,y+r*.2,x+r*.7,y+r*.2) end
    return
  end
  if spec.mark == "signal" then
    -- A signal does not pour: a dot and the two waves leaving it.
    lg.setColor(P.with(spec.fill, a))
    lg.circle("fill", x, y + 0.55 * r, 0.28 * r)
    lg.setColor(P.with(spec.color, a))
    stroke(r * 2, 0.11)
    lg.arc("line", "open", x, y + 0.55 * r, 0.72 * r, -math.pi * 0.78, -math.pi * 0.22)
    lg.arc("line", "open", x, y + 0.55 * r, 1.22 * r, -math.pi * 0.74, -math.pi * 0.26)
    return
  end
  local pts = (spec.mark == "bolt") and boltPoints(x, y, r) or dropletPoints(x, y, r)
  lg.setColor(P.with(spec.fill, a))
  lg.polygon("fill", pts)
  -- Oil is very nearly black, so its outline is not decoration: it is the only
  -- thing keeping the drop from reading as a hole in the screen.
  lg.setColor(P.with(spec.color, a))
  stroke(r * 2, 0.09)
  lg.polygon("line", pts)
  if spec.mark=="saltwater" then lg.line(x-r*.8,y+r*.25,x+r*.8,y+r*.25) end
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
  elseif kind == "subscriber" then
    -- A screen on a stand: the one customer who wants a signal, not a supply.
    lg.rectangle("fill", -9.4 * s, -8.4 * s, 18.8 * s, 12.4 * s, 1 * s)
    lg.rectangle("fill", -1.6 * s, 4 * s, 3.2 * s, 3.4 * s)
    lg.rectangle("fill", -6 * s, 7.2 * s, 12 * s, 1.8 * s, 0.6 * s)
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

  if kind=="filtration" then
    lg.rectangle("line",-7*s,-10*s,14*s,20*s,3*s)
    for i=-1,1 do lg.line(-5*s,i*5*s,5*s,i*5*s) end
  elseif kind=="binder" then
    for i=-1,1 do lg.line(-10*s,i*5*s,10*s,i*5*s) end
    lg.rectangle("line",-4*s,-10*s,8*s,20*s,2*s)
  elseif kind=="transformer" then
    lg.rectangle("line",-10*s,-8*s,20*s,16*s,2*s)
    for i=-1,1 do lg.circle("line",-3*s,i*4*s,3*s); lg.circle("line",3*s,i*4*s,3*s) end
  elseif kind=="pylon" then
    lg.line(-8*s,10*s,0,-10*s,8*s,10*s)
    lg.line(-10*s,-4*s,10*s,-4*s); lg.line(-6*s,4*s,6*s,4*s)
  elseif kind=="hvtower" then
    -- A lattice mast: two cross-arms and a braced waist.
    lg.line(-7*s,10*s,-2*s,-10*s,2*s,-10*s,7*s,10*s)
    lg.line(-10*s,-6*s,10*s,-6*s); lg.line(-8*s,0,8*s,0)
    lg.line(-5*s,5*s,4*s,-1*s); lg.line(-4*s,-1*s,5*s,5*s)
  elseif kind=="pole" then
    lg.line(0,10*s,0,-10*s); lg.line(-7*s,-6*s,7*s,-6*s)
  elseif kind=="lab" then
    lg.line(-4*s,-10*s,4*s,-10*s)
    lg.polygon("line",-3*s,-10*s,-3*s,-2*s,-9*s,9*s,9*s,9*s,3*s,-2*s,3*s,-10*s)
    lg.line(-6*s,4*s,6*s,4*s)
  elseif kind == "pump" then
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
  elseif kind == "corner" then
    -- The road arrives from the left and leaves downward: a bend, drawn as one.
    lg.setLineWidth(3*s); lg.line(-12*s,-6*s,0,-6*s); lg.line(0,-6*s,0,12*s)
  elseif kind == "intersection" or kind == "roundabout" or kind == "interchange" then
    lg.setLineWidth(3*s); lg.line(-12*s,0,12*s,0); lg.line(0,-12*s,0,12*s)
    if kind~="intersection" then lg.circle("line",0,0,(kind=="interchange" and 9 or 6)*s) end
  elseif kind == "stop" then
    -- A stop: a post with its sign plate, and a shelter roof beside it.
    lg.rectangle("fill", -7.8 * s, -10 * s, 2.4 * s, 19 * s)
    lg.rectangle("fill", -9.8 * s, -10.8 * s, 7.6 * s, 5.8 * s, 0.8 * s)
    lg.rectangle("fill", -0.6 * s, -2.8 * s, 10.6 * s, 2.2 * s, 0.4 * s)
    lg.rectangle("fill", 7.6 * s, -1 * s, 2 * s, 10 * s)
  elseif kind == "station" then
    -- A petrol pump and its hose.
    lg.rectangle("fill", -8 * s, -9 * s, 10 * s, 18 * s, 1.2 * s)
    lg.setColor(P.bg)
    lg.rectangle("fill", -5.8 * s, -6.6 * s, 5.6 * s, 4.4 * s, 0.4 * s)
    lg.setColor(r, g, b, a)
    stroke(span, 0.09)
    lg.line(2 * s, -4 * s, 7 * s, -4 * s, 7 * s, 5 * s)
    lg.circle("fill", 7 * s, 6.4 * s, 1.8 * s)
  elseif kind == "resort" then
    -- A beach umbrella, which says holiday at any size.
    lg.polygon("fill", -10 * s, -2 * s, 0, -10.6 * s, 10 * s, -2 * s)
    lg.rectangle("fill", -1.1 * s, -2.4 * s, 2.2 * s, 11.6 * s)
    lg.rectangle("fill", -7 * s, 8 * s, 14 * s, 1.8 * s, 0.6 * s)
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

-- A terminal's live freight, shuttling in and out: a truck for a road head, a
-- plane for an air freight apron, a hull for a harbour. Drawn in the colour
-- the caller already set, facing whichever way it is currently travelling.
function Draw.freightVehicle(haven, x, y, dir, s)
  local r, g, b, a = trim()
  lg.push()
  lg.translate(x, y)
  lg.scale(dir, 1)
  if haven == "airfield" then
    lg.polygon("fill", -3.4 * s, 0, 3.2 * s, -1.3 * s, 3.2 * s, 1.3 * s)
    lg.rectangle("fill", -3.4 * s, -0.4 * s, 4.6 * s, 0.8 * s)
  elseif haven == "port" then
    lg.polygon("fill", -3.4 * s, 1.6 * s, 3.4 * s, 1.6 * s, 2.1 * s, -0.8 * s, -2.1 * s, -0.8 * s)
    lg.rectangle("fill", -0.7 * s, -2.2 * s, 1.4 * s, 1.6 * s)
  else
    lg.rectangle("fill", -3.2 * s, -1.6 * s, 6.4 * s, 3.2 * s, 0.5 * s)
    lg.setColor(P.bg)
    lg.rectangle("fill", 1.6 * s, -1.15 * s, 1.4 * s, 2.3 * s)
  end
  lg.pop()
  lg.setColor(r, g, b, a)
end

-- A customer seen close up: the building itself, standing on the ground, in
-- the same footprint as its disc (so the same click lands on it). Walls and
-- roofs are the building's own colours; the trade shows in one accent -- the
-- door, the sign, the awning -- and in a small badge on the roof, so the
-- reading the disc gave is never lost. Far out the disc comes back.
local WALL, ROOF_L, ROOF_D = { 0.74, 0.70, 0.62 }, { 0.58, 0.33, 0.27 }, { 0.40, 0.23, 0.20 }
local SLATE_L, SLATE_D = { 0.46, 0.49, 0.53 }, { 0.30, 0.32, 0.36 }
function Draw.clientBuilding(kind, x, y, r, accent, commodity, ghost)
  local a = ghost and 0.55 or 1
  local function c(t, k) k = k or 1; lg.setColor(t[1] * k, t[2] * k, t[3] * k, a) end
  local u = r / 10
  lg.setColor(0, 0, 0, 0.28 * a); lg.ellipse("fill", x + 2 * u, y + 9 * u, 13 * u, 4.5 * u)
  local function gable(bx, by, w, h, roofL, roofD)
    -- Front wall, then a pitched roof seen from above and in front: the
    -- sunlit slope and the shaded one meet at the ridge.
    c(WALL, 0.85); lg.rectangle("fill", bx - w / 2, by - h * 0.15, w, h * 0.55)
    c(roofL); lg.polygon("fill", bx - w / 2 - u * 0.6, by - h * 0.1, bx - w / 2 + w * 0.12, by - h * 0.75, bx, by - h * 0.75, bx, by - h * 0.1)
    c(roofD); lg.polygon("fill", bx, by - h * 0.1, bx, by - h * 0.75, bx + w / 2 - w * 0.12, by - h * 0.75, bx + w / 2 + u * 0.6, by - h * 0.1)
  end
  if kind == "estate" then
    for i, b in ipairs({ { -5, 2, 9, 15 }, { 5, 4, 9, 11 } }) do
      local bx, by, w, h = x + b[1] * u, y + b[2] * u, b[3] * u, b[4] * u
      c(WALL, i == 1 and 0.95 or 0.85); lg.rectangle("fill", bx - w / 2, by - h / 2, w, h)
      c(SLATE_D); lg.rectangle("fill", bx - w / 2, by - h / 2, w, 2 * u)
      lg.setColor(0.16, 0.20, 0.26, a)
      for row = 0, math.floor(h / (3.4 * u)) - 2 do
        for col = 0, 1 do
          lg.rectangle("fill", bx - w / 2 + (1.6 + col * 3.8) * u, by - h / 2 + (3.4 + row * 3.4) * u, 2 * u, 1.8 * u)
        end
      end
    end
    lg.setColor(accent[1], accent[2], accent[3], a); lg.rectangle("fill", x - 6 * u, y + 8 * u, 2.6 * u, 1.8 * u)
  elseif kind == "workshop" or kind == "factory" then
    local w, h = (kind == "factory" and 24 or 20) * u, 12 * u
    c(WALL, 0.7); lg.rectangle("fill", x - w / 2, y - h / 2 + 2 * u, w, h)
    local teeth = kind == "factory" and 4 or 3
    for i = 0, teeth - 1 do
      local tx = x - w / 2 + i * w / teeth
      c(SLATE_L); lg.polygon("fill", tx, y - 1 * u, tx, y - 6 * u, tx + w / teeth, y - 1 * u)
      c(SLATE_D); lg.rectangle("fill", tx, y - 1 * u, w / teeth, 1.2 * u)
    end
    if kind == "factory" then
      for i = 0, 1 do
        local cx = x - w / 2 + (3 + i * 5) * u
        c(SLATE_D, 0.9); lg.rectangle("fill", cx, y - 13 * u, 3 * u, 8 * u)
        -- Smoke drifting off each stack.
        for p = 0, 2 do
          local ph = (R.t * 0.4 + p / 3 + i * 0.5) % 1
          lg.setColor(0.70, 0.70, 0.72, 0.35 * (1 - ph) * a)
          lg.circle("fill", cx + 1.5 * u + ph * 6 * u, y - 14 * u - ph * 8 * u, (1.5 + ph * 2.5) * u)
        end
      end
    end
    lg.setColor(accent[1], accent[2], accent[3], a); lg.rectangle("fill", x - 2 * u, y + 3 * u, 4 * u, 5 * u)
  elseif kind == "market" then
    c(WALL, 0.8); lg.rectangle("fill", x - 9 * u, y - 2 * u, 18 * u, 9 * u)
    -- A striped awning in the trade colour.
    for i = 0, 5 do
      if i % 2 == 0 then lg.setColor(accent[1], accent[2], accent[3], a) else lg.setColor(0.92, 0.90, 0.84, a) end
      lg.polygon("fill", x - 10 * u + i * 20 / 6 * u, y - 7 * u, x - 10 * u + (i + 1) * 20 / 6 * u, y - 7 * u,
        x - 10 * u + (i + 1) * 20 / 6 * u, y - 1 * u, x - 10 * u + i * 20 / 6 * u, y - 1 * u)
    end
  else
    gable(x, y + 2 * u, 18 * u, 16 * u, ROOF_L, ROOF_D)
    lg.setColor(accent[1], accent[2], accent[3], a); lg.rectangle("fill", x - 1.4 * u, y + 2.4 * u, 2.8 * u, 4 * u)
    if kind == "pub" then
      -- A hanging sign on a bracket.
      c(SLATE_D); lg.rectangle("fill", x + 9 * u, y - 3 * u, 4 * u, 0.8 * u)
      lg.setColor(accent[1], accent[2], accent[3], a); lg.rectangle("fill", x + 11 * u, y - 2.4 * u, 3.4 * u, 4 * u, 0.6 * u)
    elseif kind == "subscriber" then
      -- A dish on the roof.
      lg.setColor(0.85, 0.86, 0.88, a); lg.arc("fill", "closed", x + 4 * u, y - 7 * u, 3 * u, math.pi * 0.1, math.pi * 1.1)
    elseif kind == "home" then
      c(SLATE_D); lg.rectangle("fill", x + 3 * u, y - 10 * u, 2.4 * u, 4 * u)
    end
  end
  -- The trade, on a small badge at the corner, as the disc would have shown it.
  if commodity and r >= 16 then
    local bx, by, br = x + 10 * u, y - 9 * u, 3.6 * u
    lg.setColor(P.bg[1], P.bg[2], P.bg[3], 0.9 * a); lg.circle("fill", bx, by, br)
    lg.setColor(accent[1], accent[2], accent[3], a); lg.setLineWidth(1); lg.circle("line", bx, by, br)
    Draw.mark(commodity, bx, by, br * 0.62, ghost)
  end
end

-- A well seen close up. Water and brine come up through a stone well-head
-- with a windlass over it; oil through a pumpjack whose beam nods on its own
-- clock. Drawn in the disc's footprint, with the trade badge on the corner.
function Draw.sourceBuilding(commodity, x, y, r, accent, seed)
  local u = r / 12
  lg.setColor(0, 0, 0, 0.28); lg.ellipse("fill", x + 2 * u, y + 9 * u, 13 * u, 4.5 * u)
  if commodity == "oil" then
    -- Base, A-frame, a walking beam rocking about its top, horse head and
    -- the counterweight crank at the back.
    lg.setColor(0.30, 0.31, 0.34); lg.rectangle("fill", x - 11 * u, y + 5 * u, 22 * u, 3 * u)
    local tilt = math.sin(R.t * 1.6 + (seed or 0)) * 0.28
    local px, py = x, y - 6 * u
    lg.setColor(0.42, 0.44, 0.48); lg.setLineWidth(math.max(1, 1.6 * u))
    lg.line(x - 4 * u, y + 5 * u, px, py); lg.line(x + 4 * u, y + 5 * u, px, py)
    local cx, cy = math.cos(tilt), math.sin(tilt)
    local hx, hy = px - cx * 10 * u, py - cy * 10 * u
    local tx, ty = px + cx * 8 * u, py + cy * 8 * u
    lg.setColor(accent[1] * 0.7, accent[2] * 0.7, accent[3] * 0.7); lg.setLineWidth(math.max(1.5, 2.4 * u)); lg.line(hx, hy, tx, ty)
    lg.setColor(0.85, 0.62, 0.20); lg.polygon("fill", hx - 2 * u, hy - 2 * u, hx + 1 * u, hy - 3 * u, hx + 1 * u, hy + 3 * u, hx - 2 * u, hy + 2 * u)
    lg.setColor(0.25, 0.26, 0.29); lg.circle("fill", tx + 1 * u, ty + 3 * u, 3 * u)
    lg.setColor(0.42, 0.44, 0.48); lg.setLineWidth(1); lg.line(hx - 1 * u, hy + 2 * u, hx - 1 * u, y + 5 * u)
  else
    -- Stone ring, the water in it, two posts and a windlass across.
    lg.setColor(0.52, 0.50, 0.47); lg.circle("fill", x, y + 2 * u, 8 * u)
    lg.setColor(0.36, 0.35, 0.33); lg.setLineWidth(math.max(1, u)); lg.circle("line", x, y + 2 * u, 8 * u)
    lg.setColor(accent[1] * 0.8, accent[2] * 0.8, accent[3] * 0.8); lg.circle("fill", x, y + 2 * u, 5 * u)
    lg.setColor(1, 1, 1, 0.25 + 0.15 * math.sin(R.t * 2 + (seed or 0))); lg.ellipse("fill", x - 1.5 * u, y + 0.5 * u, 2 * u, 1 * u)
    lg.setColor(0.36, 0.26, 0.17)
    lg.rectangle("fill", x - 9 * u, y - 8 * u, 2 * u, 12 * u); lg.rectangle("fill", x + 7 * u, y - 8 * u, 2 * u, 12 * u)
    lg.rectangle("fill", x - 9 * u, y - 8 * u, 18 * u, 2 * u)
    lg.setColor(0.58, 0.33, 0.27); lg.polygon("fill", x - 11 * u, y - 7 * u, x, y - 13 * u, x + 11 * u, y - 7 * u)
  end
  if r >= 16 then
    local bx, by, br = x + 10 * u, y - 10 * u, 3.6 * u
    lg.setColor(P.bg[1], P.bg[2], P.bg[3], 0.9); lg.circle("fill", bx, by, br)
    lg.setColor(accent); lg.setLineWidth(1); lg.circle("line", bx, by, br)
    Draw.mark(commodity, bx, by, br * 0.62)
  end
end

-- A works close up: a brick hall with a slate roof, a stack with smoke when
-- it is making something, and a stripe and badge in the colour of what it
-- makes.
function Draw.worksBuilding(makes, x, y, r, accent, busy, seed)
  local u = r / 12
  lg.setColor(0, 0, 0, 0.28); lg.ellipse("fill", x + 2 * u, y + 9 * u, 14 * u, 4.5 * u)
  lg.setColor(0.52, 0.32, 0.26); lg.rectangle("fill", x - 11 * u, y - 3 * u, 22 * u, 11 * u)
  lg.setColor(0.40, 0.24, 0.20)
  for row = 0, 2 do lg.line(x - 11 * u, y + (-0.5 + row * 3.5) * u, x + 11 * u, y + (-0.5 + row * 3.5) * u) end
  lg.setColor(0.46, 0.49, 0.53); lg.polygon("fill", x - 12 * u, y - 3 * u, x - 8 * u, y - 10 * u, x + 8 * u, y - 10 * u, x + 12 * u, y - 3 * u)
  lg.setColor(0.32, 0.34, 0.38); lg.polygon("fill", x, y - 10 * u, x + 8 * u, y - 10 * u, x + 12 * u, y - 3 * u, x, y - 3 * u)
  lg.setColor(accent); lg.rectangle("fill", x - 11 * u, y + 1 * u, 22 * u, 1.6 * u)
  lg.setColor(0.18, 0.20, 0.24); lg.rectangle("fill", x - 2.5 * u, y + 3 * u, 5 * u, 5 * u)
  local sx = x - 7 * u
  lg.setColor(0.36, 0.26, 0.22); lg.rectangle("fill", sx, y - 16 * u, 3 * u, 8 * u)
  if busy then
    for p = 0, 2 do
      local ph = (R.t * 0.4 + p / 3 + (seed or 0)) % 1
      lg.setColor(0.72, 0.72, 0.74, 0.35 * (1 - ph))
      lg.circle("fill", sx + 1.5 * u + ph * 6 * u, y - 17 * u - ph * 8 * u, (1.5 + ph * 2.5) * u)
    end
  end
  if r >= 16 and makes then
    local bx, by, br = x + 11 * u, y - 11 * u, 3.6 * u
    lg.setColor(P.bg[1], P.bg[2], P.bg[3], 0.9); lg.circle("fill", bx, by, br)
    lg.setColor(accent); lg.setLineWidth(1); lg.circle("line", bx, by, br)
    Draw.mark(makes, bx, by, br * 0.62)
  end
end

-- Network structures close up. A tower is a steel pylon, taller the higher
-- its level; a depot a storage tank showing how full it is, on legs as a
-- water tower at the top of its ladder; a pump a small pump house with its
-- impeller turning while water moves.
function Draw.structureBuilding(kind, x, y, r, accent, level, fill, busy, seed)
  local u = r / 12
  level = level or 1
  if kind ~= "tower" then lg.setColor(0, 0, 0, 0.28); lg.ellipse("fill", x + 2 * u, y + 9 * u, 11 * u, 4 * u) end
  if kind == "tower" then
    -- The cables attach where the node is, so the top arm sits there and the
    -- lattice stands below it.
    local h = (14 + level * 2.5) * u
    local top, base = y - 2 * u, y - 2 * u + h
    lg.setColor(0, 0, 0, 0.28); lg.ellipse("fill", x + 2 * u, base + 1 * u, 9 * u, 3 * u)
    lg.setColor(0.62, 0.64, 0.68); lg.setLineWidth(math.max(1, 1.1 * u))
    lg.line(x - 7 * u, base, x - 1.5 * u, top); lg.line(x + 7 * u, base, x + 1.5 * u, top)
    -- Cross bracing up the legs.
    local steps = 3 + level
    for i = 0, steps - 1 do
      local t0, t1 = i / steps, (i + 1) / steps
      local l0, l1 = x - 7 * u + 5.5 * u * t0, x - 7 * u + 5.5 * u * t1
      local r0, r1 = x + 7 * u - 5.5 * u * t0, x + 7 * u - 5.5 * u * t1
      local y0, y1 = base + (top - base) * t0, base + (top - base) * t1
      lg.line(l0, y0, r1, y1); lg.line(r0, y0, l1, y1)
    end
    -- Cross-arms with insulators in the trade colour.
    for arm = 0, math.min(2, level - 1) do
      local ay, aw = top + (2 + arm * 4) * u, (8 - arm) * u
      lg.setColor(0.62, 0.64, 0.68); lg.line(x - aw, ay, x + aw, ay)
      lg.setColor(accent); lg.circle("fill", x - aw, ay + 1 * u, 1 * u); lg.circle("fill", x + aw, ay + 1 * u, 1 * u)
    end
  elseif kind == "depot" then
    local legs = level >= 4
    local cy = legs and y - 6 * u or y
    if legs then
      lg.setColor(0.40, 0.42, 0.46); lg.setLineWidth(math.max(1, 1.2 * u))
      lg.line(x - 6 * u, cy + 4 * u, x - 8 * u, y + 8 * u); lg.line(x + 6 * u, cy + 4 * u, x + 8 * u, y + 8 * u)
      lg.line(x - 7 * u, y + 3 * u, x + 7 * u, y + 3 * u)
    end
    local w = (legs and 16 or 14 + level * 1.5) * u
    local hgt = (legs and 9 or 10) * u
    lg.setColor(0.60, 0.62, 0.64); lg.rectangle("fill", x - w / 2, cy - hgt / 2, w, hgt)
    lg.setColor(0.46, 0.48, 0.50); lg.rectangle("fill", x, cy - hgt / 2, w / 2, hgt)
    lg.setColor(0.72, 0.74, 0.76); lg.ellipse("fill", x, cy - hgt / 2, w / 2, 2.6 * u)
    lg.setColor(0.50, 0.52, 0.54); lg.ellipse("line", x, cy - hgt / 2, w / 2, 2.6 * u)
    -- A gauge down the side: how full it is, in the trade colour.
    lg.setColor(0.16, 0.18, 0.22); lg.rectangle("fill", x - w / 2 + 2 * u, cy - hgt / 2 + 2 * u, 2.2 * u, hgt - 3 * u)
    local f = math.max(0, math.min(1, fill or 0))
    lg.setColor(accent); lg.rectangle("fill", x - w / 2 + 2 * u, cy + hgt / 2 - 1 * u - (hgt - 3 * u) * f, 2.2 * u, (hgt - 3 * u) * f)
  elseif kind == "stop" then
    -- A bus shelter: a glass box under a flat roof, and the sign on its pole.
    lg.setColor(0.35, 0.60, 0.75, 0.55); lg.rectangle("fill", x - 8 * u, y - 3 * u, 16 * u, 8 * u)
    lg.setColor(0.30, 0.32, 0.36); lg.rectangle("fill", x - 9 * u, y - 5 * u, 18 * u, 2.4 * u)
    lg.setColor(0.36, 0.38, 0.42); lg.setLineWidth(math.max(1, u)); lg.line(x + 11 * u, y + 7 * u, x + 11 * u, y - 7 * u)
    lg.setColor(accent); lg.circle("fill", x + 11 * u, y - 8 * u, 2.4 * u)
  elseif kind == "station" then
    -- A fuel station: canopy on columns over two pumps, and the shop behind.
    lg.setColor(0.62, 0.60, 0.56); lg.rectangle("fill", x - 11 * u, y - 9 * u, 9 * u, 7 * u)
    lg.setColor(0.36, 0.38, 0.42); lg.rectangle("fill", x - 1 * u, y - 1 * u, 1.4 * u, 8 * u); lg.rectangle("fill", x + 9 * u, y - 1 * u, 1.4 * u, 8 * u)
    for i = 0, 1 do lg.setColor(accent); lg.rectangle("fill", x + (1.5 + i * 4) * u, y + 1 * u, 2.4 * u, 4 * u) end
    lg.setColor(0.88, 0.88, 0.86); lg.rectangle("fill", x - 2 * u, y - 5 * u, 14 * u, 4 * u)
    lg.setColor(accent); lg.rectangle("fill", x - 2 * u, y - 2 * u, 14 * u, 1 * u)
  elseif kind == "resort" then
    -- A hotel: a tall block with balconies, and a pool catching the light.
    local floors = 2 + math.min(4, level)
    lg.setColor(0.86, 0.82, 0.74); lg.rectangle("fill", x - 7 * u, y + 6 * u - floors * 3 * u, 11 * u, floors * 3 * u)
    lg.setColor(0.28, 0.40, 0.52)
    for f = 0, floors - 1 do lg.rectangle("fill", x - 6 * u, y + 6.8 * u - (f + 1) * 3 * u, 9 * u, 1.2 * u) end
    lg.setColor(0.25, 0.60, 0.80); lg.rectangle("fill", x + 5 * u, y + 1 * u, 7 * u, 5 * u, 1 * u)
    lg.setColor(1, 1, 1, 0.3 + 0.2 * math.sin(R.t * 2 + (seed or 0))); lg.rectangle("fill", x + 6 * u, y + 2 * u, 3 * u, 1 * u)
    lg.setColor(accent); lg.rectangle("fill", x - 7 * u, y + 6 * u - floors * 3 * u - 1.5 * u, 11 * u, 1.5 * u)
  elseif kind == "dc" then
    -- A depot yard: a shed, and containers stacked on the hard standing.
    lg.setColor(0.34, 0.35, 0.37); lg.rectangle("fill", x - 13 * u, y - 7 * u, 26 * u, 15 * u, 1.5 * u)
    lg.setColor(0.52, 0.54, 0.58); lg.rectangle("fill", x - 12 * u, y - 6 * u, 10 * u, 7 * u)
    local cols = { { 0.30, 0.55, 0.75 }, { 0.85, 0.62, 0.25 }, { 0.40, 0.65, 0.40 }, { 0.70, 0.35, 0.35 } }
    for i = 0, 5 do
      lg.setColor(cols[(i + math.floor((seed or 0) * 10)) % #cols + 1])
      lg.rectangle("fill", x + (0 + (i % 3) * 4) * u, y + (-5 + math.floor(i / 3) * 5) * u, 3.4 * u, 4 * u)
    end
    lg.setColor(accent); lg.rectangle("fill", x - 12 * u, y + 3 * u, 10 * u, 1.2 * u)
  else
    -- Pump house: a concrete block, the main passing through its flanges,
    -- and the impeller showing through a round port.
    lg.setColor(0.56, 0.58, 0.60); lg.rectangle("fill", x - 8 * u, y - 6 * u, 16 * u, 12 * u, 1.5 * u)
    lg.setColor(0.44, 0.46, 0.48); lg.rectangle("fill", x - 8 * u, y - 6 * u, 16 * u, 3 * u, 1.5 * u)
    lg.setColor(accent); lg.rectangle("fill", x - 11 * u, y + 1 * u, 3 * u, 3 * u); lg.rectangle("fill", x + 8 * u, y + 1 * u, 3 * u, 3 * u)
    lg.setColor(0.18, 0.20, 0.24); lg.circle("fill", x, y + 1.5 * u, 3.6 * u)
    local spin = busy and R.t * 5 + (seed or 0) or (seed or 0)
    lg.setColor(accent); lg.setLineWidth(math.max(1, 0.9 * u))
    for i = 0, 2 do
      local a = spin + i * math.pi * 2 / 3
      lg.line(x, y + 1.5 * u, x + math.cos(a) * 3 * u, y + 1.5 * u + math.sin(a) * 3 * u)
    end
  end
end

-- Every node on the map is a disc: a dark body tinted by its trade, and a rim
-- in the trade colour. Flat, so the symbol on top of it is what the eye finds.
function Draw.disc(x, y, r, color, tint)
  lg.setColor(0,0,0,0.22)
  lg.circle("fill", x, y+2, r+2)
  lg.setColor(P.bg)
  lg.circle("fill", x, y, r)
  lg.setColor(P.with(color, tint or 0.20))
  lg.circle("fill", x, y, r)
  -- A bevel: light catching the upper left of the rim, shade on the lower
  -- right, so a building stands on the ground instead of being printed on it.
  if r >= 6 then
    lg.setLineWidth(math.max(1, r * 0.12))
    lg.setColor(1, 1, 1, 0.14)
    lg.arc("line", "open", x, y, r * 0.8, math.pi * 1.05, math.pi * 1.55)
    lg.setColor(0, 0, 0, 0.22)
    lg.arc("line", "open", x, y, r * 0.8, math.pi * 0.05, math.pi * 0.55)
  end
  lg.setColor(color)
  lg.setLineWidth(math.max(1, r * 0.10))
  lg.circle("line", x, y, r)
end

local laneCache={}
function Draw.edgePoints(cam, city, e)
  if laneCache.city~=city or laneCache.revision~=city.revision or laneCache.count~=#city.g.edges then
    local groups,offsets={},{}
    for _,edge in ipairs(city.g.edges) do
      if edge.alive then
        local key=math.min(edge.a,edge.b)..":"..math.max(edge.a,edge.b)
        groups[key]=groups[key] or {}; table.insert(groups[key],edge.id)
      end
    end
    for _,ids in pairs(groups) do
      for i,id in ipairs(ids) do offsets[id]=(i-(#ids+1)/2)*8 end
    end
    laneCache={city=city,revision=city.revision,count=#city.g.edges,offsets=offsets}
  end
  local a,b=city.g.nodes[e.a],city.g.nodes[e.b]
  local ax,ay=cam:toScreen(a.x,a.y)
  local bx,by=cam:toScreen(b.x,b.y)
  local length=math.max(1,math.sqrt((bx-ax)^2+(by-ay)^2))
  local offset=laneCache.offsets[e.id] or 0
  local sign=e.a<e.b and 1 or -1
  local ox,oy=-(by-ay)/length*offset*sign,(bx-ax)/length*offset*sign
  return ax+ox,ay+oy,bx+ox,by+oy
end

-- Physical road geometry. Bus services use the road segments below.
function Draw.linkPoints(cam, city, l)
  local a, b = city.g.nodes[l.a], city.g.nodes[l.b]
  local ax, ay = cam:toScreen(a.x, a.y)
  local bx, by = cam:toScreen(b.x, b.y)
  local length = math.max(1, math.sqrt((bx - ax) ^ 2 + (by - ay) ^ 2))
  local offset = ({ ferry = -8 })[l.mode] or 0
  local sign = l.a < l.b and 1 or -1
  local ox, oy = -(by - ay) / length * offset * sign, (bx - ax) / length * offset * sign
  return ax + ox, ay + oy, bx + ox, by + oy
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
    if city:districtVisible(d) and cam:seesBox(d.x, d.y, d.x + d.w, d.y + d.h) then
      local x, y = cam:toScreen(d.x, d.y)
      local w, h = d.w * cam.scale, d.h * cam.scale
      if d.island then
        -- A speck of rock in the water, not a surveyed lot: a smooth oval,
        -- never a straight edge.
        -- Drawn as an island looks from the air: surf breaking round a ragged
        -- shore, a beach, and green ground inside it. The shore wanders but
        -- never passes the oval the island is surveyed as.
        local cx,cy=x+w/2,y+h/2
        local a,b=(d.id or 1)*1.7,(d.id or 1)*2.3
        local function shore(k,swell)
          local pts={}
          for i=0,47 do
            local t=i/48*math.pi*2
            local f=(0.9+0.055*math.sin(3*t+a)+0.04*math.sin(5*t+b)+0.015*math.sin(9*t+a*b))*k+(swell or 0)
            pts[#pts+1]=cx+math.cos(t)*w/2*f; pts[#pts+1]=cy+math.sin(t)*h/2*f
          end
          return pts
        end
        local surf=0.5+0.5*math.sin(R.t*0.9+(d.id or 1))
        lg.setColor(0.20,0.40,0.55,0.35+0.15*surf); lg.polygon("fill",shore(1.12,0.01*surf))
        lg.setColor(0.58,0.53,0.40,d.owned and 0.95 or 0.75); lg.polygon("fill",shore(1))
        lg.setColor(d.owned and {0.16,0.25,0.18,1} or {0.12,0.18,0.15,1}); lg.polygon("fill",shore(0.86))
      else
        -- A plot is a field with a verge round it: rounded, mottled grass
        -- pinned to the world, and a lit top edge so it sits on the map rather
        -- than being printed on it. Ground not yet bought is the same field,
        -- greyer and hatched as undeveloped.
        local m=math.max(2,10*cam.scale)
        local px,py,pw,ph=x+m,y+m,w-m*2,h-m*2
        local round=math.max(3,18*cam.scale)
        lg.setColor(0,0,0,0.22); lg.rectangle("fill",px,py+2,pw,ph,round)
        lg.setColor(d.owned and {P.land[1],P.land[2],P.land[3],0.96} or {0.092,0.128,0.126,0.94})
        lg.rectangle("fill",px,py,pw,ph,round)
        Scenery.grass(d.x+10,d.y+10,d.w-20,d.h-20,px,py,cam.scale,d.owned and 1 or 0.8)
        if not d.owned and cam.scale>0.22 then
          -- Lines where (x - px) + (y - py) is constant, clipped to the plot.
          lg.setColor(1,1,1,0.022); lg.setLineWidth(1)
          local step=26
          for c=step-((px+py)%step),pw+ph,step do
            local x0,y0=px+math.max(0,c-ph),py+math.min(ph,c)
            local x1,y1=px+math.min(pw,c),py+math.max(0,c-pw)
            lg.line(x0,y0,x1,y1)
          end
        end
        lg.setLineWidth(1)
        lg.setColor(1,1,1,d.owned and 0.06 or 0.03)
        lg.line(px+round,py+0.5,px+pw-round,py+0.5)
        lg.setColor(0,0,0,0.25)
        lg.line(px+round,py+ph-0.5,px+pw-round,py+ph-0.5)
      end
    end
  end
end

local function drawDistrictChrome(city, cam, state)
  lg.setLineWidth(1)
  for _, d in ipairs(city.districts or {}) do
    if city:districtVisible(d) and cam:seesBox(d.x, d.y, d.x + d.w, d.y + d.h) then
    local x, y = cam:toScreen(d.x, d.y)
    local w, h = d.w * cam.scale, d.h * cam.scale
    local cx, cy = x + w / 2, y + h / 2
    if d.owned then
      lg.setColor(P.with(P.panelEdge, 0.55))
      if d.island then lg.ellipse("line", cx, cy, w / 2, h / 2)
      else lg.rectangle("line", x, y, w, h) end
    else
      -- Ground you do not own is visibly not yours, but still legible enough
      -- to plan towards.
      lg.setColor(P.with(P.bg, 0.14))
      if d.island then lg.ellipse("fill", cx, cy, w / 2, h / 2)
      else lg.rectangle("fill", x, y, w, h) end
      local hot = state.district == d.id
      local buyable = not city:districtError(d.id)
      -- The land view draws its own, stronger status borders.
      if state.tab ~= "map" then
        lg.setColor(P.with(hot and P.energy or buyable and P.good or P.textFaint, hot and 0.9 or 0.25))
        lg.setLineWidth(hot and 2 or 1)
        local m = math.max(2, 10 * cam.scale)
        if d.island then lg.ellipse("line", cx, cy, w / 2 - 2, h / 2 - 2)
        else lg.rectangle("line", x + m, y + m, w - m * 2, h - m * 2, math.max(3, 18 * cam.scale)) end
      end
      -- Prices only when land is the question: the land view, the overview
      -- from far out, or the plot just clicked. Close in, a city of price
      -- tags is noise over the network being built.
      local pricing = state.tab ~= "map" and (hot or cam.scale <= 0.34)
      if cam.scale > 0.19 and pricing then
        label(d.name, cx, cy - 20, buyable and P.text or P.textDim, R.fonts.body)
        if (d.population or 0) > 0 then
          label("POP " .. d.population, cx, cy - 44, P.textDim, R.fonts.tiny)
        end
        label("$" .. city:districtCost(d)..(city:landDiscount(d)>0 and ("  -"..math.floor(city:landDiscount(d)*100).."%") or ""), cx, cy + 4,
          buyable and P.energy or P.textFaint, R.fonts.small)
        if hot and not buyable and city:districtAdjacent(d) then
          label("needs more cash", cx, cy + 26, P.textFaint, R.fonts.tiny)
        elseif hot and not city:districtAdjacent(d) then
          label("separate holding", cx, cy + 26, P.textFaint, R.fonts.tiny)
        end
      end
    end
    if cam.scale > 0.34 and d.owned then
      label(string.upper(d.name), cx, (d.island and cy - h / 2 + 16) or y + 6, P.textFaint, R.fonts.tiny)
      if (d.population or 0) > 0 then
        label("POP " .. d.population, cx, (d.island and cy - h / 2 + 34) or y + 24, P.textDim, R.fonts.tiny)
      end
    end
    end
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
-- Runs fn clipped to a band of screen rows, inside whatever clip is already set,
-- so water on one side of the coastline can never be painted over the other.
local function withinRows(top, bottom, fn)
  local sx, sy, sw, sh = lg.getScissor()
  top = math.max(0, top)
  local width=R.dimensions()
  lg.intersectScissor(0, top, width, math.max(0, bottom - top))
  fn()
  if sx then lg.setScissor(sx, sy, sw, sh) else lg.setScissor() end
end

local function drawSea(city, cam, state)
  local left, top = cam:toWorld(cam.vx, cam.vy)
  local right = cam:toWorld(cam.vx + cam.vw, cam.vy)
  if top > 0 then return end
  local _, coast = cam:toScreen(0, 0)
  withinRows(0, coast, function()
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
        local sx, sy = cam:toScreen(wx, wy + math.sin(t * math.pi * 5 + i * 1.7 + R.t * 0.35) * 26)
        pts[#pts + 1] = sx; pts[#pts + 1] = sy
      end
      local smooth={}
      for k=1,#pts-2,2 do
        local a=math.max(1,k-2); local b=math.min(#pts-1,k+4)
        for step=0,7 do
          local t=step/8
          for axis=0,1 do
            local p0,p1,p2,p3=pts[a+axis],pts[k+axis],pts[k+2+axis],pts[b+axis]
            smooth[#smooth+1]=.5*((2*p1)+(-p0+p2)*t+(2*p0-5*p1+4*p2-p3)*t*t+(-p0+3*p1-3*p2+p3)*t*t*t)
          end
        end
      end
      smooth[#smooth+1]=pts[#pts-1]; smooth[#smooth+1]=pts[#pts]
      lg.line(smooth)
    end
  end)
  -- Glints on the open water: short flecks of light on a coarse world grid,
  -- each twinkling on its own clock, thinning out toward the shallows.
  withinRows(0, coast, function()
    local cell = 170
    local gx0, gx1 = math.floor((left - 200) / cell), math.floor((right + 200) / cell)
    local gy0 = math.floor((top - 200) / cell)
    if (gx1 - gx0) * (0 - gy0) < 900 then
      lg.setLineWidth(math.max(1, 1.5 * cam.scale))
      for gx = gx0, gx1 do
        for gy = gy0, -2 do
          local hx = Shape.hash(gx, gy, 1)
          local wx, wy = (gx + hx) * cell, (gy + Shape.hash(gx, gy, 2)) * cell
          local tw = math.sin(R.t * (0.6 + hx) + Shape.hash(gx, gy, 3) * 6.28)
          if tw > 0.45 then
            local sx, sy = cam:toScreen(wx, wy)
            local len = (3 + 5 * hx) * math.max(0.5, cam.scale)
            lg.setColor(0.80, 0.90, 1, (tw - 0.45) * math.min(1, cam.scale / 0.45))
            lg.line(sx - len, sy, sx + len, sy)
          end
        end
      end
    end
  end)

  -- The shore: shallows lightening toward land, a beach whose edge wanders,
  -- wet sand at the waterline and surf running up it. All of it is on the sea
  -- side of the line, so nothing drawn here is ground anyone could build on.
  -- The estuary has no shore across it.
  local p = city:riverPath()
  local gapA, gapB = math.huge, -math.huge
  if p and p.n > 0 then gapA, gapB = p.x[1] - p.hw[1], p.x[1] + p.hw[1] end
  -- The beach narrows to nothing as it reaches the river mouth, so the sand
  -- turns the corner into the banks instead of stopping at a wall.
  local function edge(wx)
    local e = -20 - 7 * math.sin(wx / 90) - 4 * math.sin(wx / 37 + 1)
    local near = math.min(math.abs(wx - gapA), math.abs(wx - gapB))
    local taper = math.min(1, near / 90)
    return e * (0.15 + 0.85 * taper * taper * (3 - 2 * taper))
  end
  local step = math.max(12, 18 / math.max(0.2, cam.scale))
  local x0w = math.floor((left - 200) / step) * step
  withinRows(0, coast, function()
    for i = 1, 14 do
      local _, ty = cam:toScreen(0, -i * 14)
      lg.setColor(0.16, 0.34, 0.46, 0.032)
      lg.rectangle("fill", cam.vx, ty, cam.vw, math.max(0, coast - ty))
    end
  end)
  local function runs(fn)
    local wx = x0w
    while wx < right + 200 do
      local nx = wx + step
      if nx <= gapA or wx >= gapB then fn(wx, nx) end
      wx = nx
    end
  end
  runs(function(a, b)
    local ax, ay = cam:toScreen(a, edge(a))
    local bx, by = cam:toScreen(b, edge(b))
    local _, base = cam:toScreen(0, 0)
    lg.setColor(0.52, 0.48, 0.36, 0.92)
    lg.polygon("fill", ax, ay, bx, by, bx, base, ax, base)
    lg.setColor(0.36, 0.34, 0.28, 0.9)
    local _, wy1 = cam:toScreen(0, edge(a) + 5)
    local _, wy2 = cam:toScreen(0, edge(b) + 5)
    lg.polygon("fill", ax, ay, bx, by, bx, wy2, ax, wy1)
  end)
  -- Surf: a foam line that runs up the sand and slides back, and a fainter
  -- one further out.
  lg.setLineWidth(math.max(1, 2 * cam.scale))
  for k = 0, 1 do
    runs(function(a, b)
      local function surf(wx)
        local surge = (0.5 + 0.5 * math.sin(R.t * 0.8 + wx / 260 + k * 2.1)) * (k == 0 and 8 or 12)
        return edge(wx) - (k == 0 and 2 or 22) - surge * (k == 0 and 1 or -0.3)
      end
      local ax, ay = cam:toScreen(a, surf(a))
      local bx, by = cam:toScreen(b, surf(b))
      lg.setColor(0.85, 0.92, 0.96, k == 0 and 0.55 or 0.18)
      lg.line(ax, ay, bx, by)
    end)
  end

  -- Where a harbour may stand, shown only while the tool is in hand.
  if state and state.tool == "terminal" and (state.havenKind or "port") == "port" then
    local sx, sy = cam:toScreen(left - 200, 0)
    local ex, ey = cam:toScreen(right + 200, City.havenReach)
    lg.setColor(P.with(P.good, 0.12)); lg.rectangle("fill", sx, sy, ex - sx, ey - sy)
    lg.setColor(P.with(P.good, 0.5)); lg.setLineWidth(1)
    lg.rectangle("line", sx, sy, ex - sx, ey - sy)
  end
  if cam.scale > 0.16 and coast>cam.vy+40 then
    local _, ly = cam:toScreen(0, -150)
    label("THE SEA", cam.vx + cam.vw / 2, math.max(cam.vy + 16, ly),
      P.with({ 0.55, 0.75, 0.95 }, 0.8), R.fonts.tiny)
  end
end

-- Only the reach the camera can see is drawn, and none of it north of the
-- coastline: the estuary opens into the sea rather than being painted over it.
--
-- A river is drawn the way it looks from above, in layers, every layer for
-- every channel before the next so that a tributary pours into the main
-- stream instead of being fenced off from it:
--   the banks      a strip of trodden, damper ground along both sides
--   the shallows   the full width of the water
--   the deep       the channel's thalweg, which swings to the outside of every
--                  bend, because that is where the current cuts
--   point bars     pale sand on the inside of a bend, where the current drops it
--   the current    ripples drifting downstream to the sea
local RIVER = {
  bank    = { 0.19, 0.23, 0.18, 1 },
  shallow = { 0.12, 0.26, 0.36, 1 },
  deep    = { 0.07, 0.17, 0.28, 1 },
  sand    = { 0.64, 0.57, 0.41 },
  edge    = { 0.42, 0.60, 0.72 },
}

-- How hard the channel bends at each sample, and to which side: +1 when the
-- inside of the bend is on the +normal bank, -1 when it is on the other.
local function bends(p)
  if p.bend then return p.bend, p.inner end
  local bend, inner = {}, {}
  local function heading(i) return math.atan2(p.ny[i], -p.nx[i]) end
  for i = 1, p.n do
    local a, b = heading(math.max(1, i - 2)), heading(math.min(p.n, i + 2))
    local d = b - a
    if d > math.pi then d = d - 2 * math.pi elseif d < -math.pi then d = d + 2 * math.pi end
    local curvature = d / (City.riverStep * (math.min(p.n, i + 2) - math.max(1, i - 2)))
    bend[i] = math.min(1, math.abs(curvature) * p.hw[i] * 5)
    inner[i] = curvature > 0 and -1 or 1
  end
  p.bend, p.inner = bend, inner
  return bend, inner
end

-- A point across the channel: `across` is -1 on one bank, +1 on the other.
local function across(cam, p, i, off)
  return cam:toScreen(p.x[i] + p.nx[i] * off, p.y[i] + p.ny[i] * off)
end

-- A ribbon between two offsets from the centreline, as quads, because the
-- channel as a whole is nowhere near convex.
-- One triangle strip, so neighbouring pieces share their edges and no
-- hairline of the layer beneath shows through between them.
local ribbonMesh, ribbonCap
local function ribbon(cam, p, first, last, inner, outer)
  local verts = {}
  for i = first, last do
    local ax, ay = across(cam, p, i, inner(i))
    local bx, by = across(cam, p, i, outer(i))
    verts[#verts + 1] = { ax, ay }
    verts[#verts + 1] = { bx, by }
  end
  if #verts < 4 then return end
  if not ribbonMesh or #verts > ribbonCap then
    ribbonCap = math.max(#verts, 2 * (ribbonCap or 1024))
    ribbonMesh = lg.newMesh({ { "VertexPosition", "float", 2 } }, ribbonCap, "strip", "stream")
  end
  ribbonMesh:setVertices(verts)
  ribbonMesh:setDrawRange(1, #verts)
  lg.draw(ribbonMesh)
end

local function riverPoint(p, s)
  local f = s / City.riverStep + 1
  local i = math.max(1, math.min(p.n - 1, math.floor(f)))
  local t = math.max(0, math.min(1, f - i))
  local function lerp(a) return a[i] + (a[i + 1] - a[i]) * t end
  return lerp(p.x), lerp(p.y), lerp(p.hw), lerp(p.nx), lerp(p.ny)
end

local function drawRiver(city, cam)
  local p = city:riverPath()
  if not p then return end
  local _, top = cam:toWorld(cam.vx, cam.vy)
  local _, bottom = cam:toWorld(cam.vx, cam.vy + cam.vh)
  if bottom < 0 then return end
  local paths = { p }
  for _, branch in ipairs(p.branches or {}) do paths[#paths + 1] = branch end
  local spans = {}
  for k, q in ipairs(paths) do
    local first, last = city:riverSpan(top - q.maxHalf, bottom + q.maxHalf, q)
    if first and last - first >= 1 then spans[k] = { first, last } end
  end
  local _, coast = cam:toScreen(0, 0)
  local _, viewHeight = R.dimensions()
  local fine = cam.scale > 0.22
  withinRows(coast, viewHeight, function()
    -- The banks.
    lg.setColor(RIVER.bank)
    for k, q in ipairs(paths) do if spans[k] then
      ribbon(cam, q, spans[k][1], spans[k][2],
        function(i) return -(q.hw[i] + math.max(10, q.hw[i] * 0.16)) end,
        function(i) return q.hw[i] + math.max(10, q.hw[i] * 0.16) end)
    end end
    -- The shallows.
    lg.setColor(RIVER.shallow)
    for k, q in ipairs(paths) do if spans[k] then
      ribbon(cam, q, spans[k][1], spans[k][2], function(i) return -q.hw[i] end, function(i) return q.hw[i] end)
    end end
    -- The deep water, pushed to the outside of each bend.
    lg.setColor(RIVER.deep)
    for k, q in ipairs(paths) do if spans[k] then
      local bend, inner = bends(q)
      ribbon(cam, q, spans[k][1], spans[k][2],
        function(i) return -inner[i] * bend[i] * q.hw[i] * 0.3 - q.hw[i] * 0.52 end,
        function(i) return -inner[i] * bend[i] * q.hw[i] * 0.3 + q.hw[i] * 0.52 end)
    end end
    if fine then
      -- Point bars: sand on the inside of the tighter bends, fading in and out
      -- along the bend as one strip.
      for k, q in ipairs(paths) do if spans[k] then
        local bend, inner = bends(q)
        local verts = {}
        local function flush()
          if #verts >= 4 then
            local mesh = lg.newMesh({ { "VertexPosition", "float", 2 }, { "VertexColor", "float", 4 } }, verts, "strip", "stream")
            lg.setColor(1, 1, 1, 1); lg.draw(mesh); mesh:release()
          end
          verts = {}
        end
        for i = spans[k][1], spans[k][2] do
          local b = bend[i]
          if b > 0.2 and (i == spans[k][1] or inner[i] == inner[i - 1]) then
            local side = inner[i]
            local ax, ay = across(cam, q, i, side * q.hw[i])
            local bx, by = across(cam, q, i, side * (q.hw[i] * (1 - 0.5 * b)))
            local a = math.min(0.62, (b - 0.2) * 1.1)
            verts[#verts + 1] = { ax, ay, RIVER.sand[1], RIVER.sand[2], RIVER.sand[3], a }
            verts[#verts + 1] = { bx, by, RIVER.sand[1], RIVER.sand[2], RIVER.sand[3], 0 }
          else
            flush()
          end
        end
        flush()
      end end
    end
    -- The water's edge, left out wherever another channel runs in.
    lg.setColor(RIVER.edge[1], RIVER.edge[2], RIVER.edge[3], 0.32)
    lg.setLineWidth(math.max(1, 1.2 * cam.scale))
    for k, q in ipairs(paths) do if spans[k] then
      for _, side in ipairs({ -1, 1 }) do
        local px, py
        for i = spans[k][1], spans[k][2] do
          local wx, wy = q.x[i] + q.nx[i] * side * q.hw[i], q.y[i] + q.ny[i] * side * q.hw[i]
          local sx, sy = cam:toScreen(wx, wy)
          local open = (city:riverEdge(wx + q.nx[i] * side * 6, wy + q.ny[i] * side * 6) or 1) > 0
          if px and open then lg.line(px, py, sx, sy) end
          if open then px, py = sx, sy else px = nil end
        end
      end
    end end
    -- The current: short ripples drifting downstream, towards the sea. The
    -- narrower the channel, the faster it runs.
    if fine then
      local spacing = 150
      for k, q in ipairs(paths) do if spans[k] then
        local s0 = (spans[k][1] - 1) * City.riverStep
        local s1 = (spans[k][2] - 1) * City.riverStep
        for lane, off in ipairs({ -0.45, 0.05, 0.5 }) do
          local speed = 34 * 90 / math.max(40, q.maxHalf)
          local shift = (R.t * speed + lane * 57) % spacing
          local s = math.floor(s0 / spacing) * spacing - shift + lane * 41
          while s < s1 do
            if s > 0 then
              local x1, y1, hw1, nx1, ny1 = riverPoint(q, s)
              local x2, y2, hw2, nx2, ny2 = riverPoint(q, s + 26)
              local a = 0.10 + 0.08 * math.sin(s * 0.013 + lane)
              lg.setColor(0.75, 0.88, 1, a)
              lg.setLineWidth(math.max(1, 1.6 * cam.scale))
              local ax, ay = cam:toScreen(x1 + nx1 * off * hw1, y1 + ny1 * off * hw1)
              local bx, by = cam:toScreen(x2 + nx2 * off * hw2, y2 + ny2 * off * hw2)
              lg.line(ax, ay, bx, by)
            end
            s = s + spacing
          end
        end
      end end
    end
  end)
  if cam.scale > 0.28 then
    local i = math.min(p.n, math.floor(1400 / City.riverStep) + 1)
    local mx, my = cam:toScreen(p.x[i], p.y[i])
    label(city:riverName(), mx, my, P.with(RIVER.edge, 0.9), R.fonts.tiny)
  end
end

local function drawSeams(city, cam, state)
  for _, s in ipairs(city.deposits or {}) do
    if not s.taken and cam:sees(s.x, s.y, City.seamRange * cam.scale + 40) then
      local x, y = cam:toScreen(s.x, s.y)
      local d = city:districtAt(s.x, s.y)
      -- Surveyors report on ground the company has not bought yet, which is the
      -- whole reason to have them: you can see what a district holds before you
      -- write the cheque.
      if d and city:districtVisible(d) and (d.owned or (city.orders or {}).surveyors) then
        -- A deposit is the only place its trade can be taken out of the
        -- ground, so it is drawn in that trade's own colour and says which
        -- trade it is. The ring is the ground a works has to stand on.
        local spec = Graph.COMMODITIES[s.commodity] or Graph.COMMODITIES.water
        local r = City.seamRange * cam.scale
        local dim = not d.owned and 0.5 or 1
        local focused=state.tool=="source" and state.commodity==s.commodity
        if not focused then dim=dim*0.45 end
        -- A surveyed claim: a faint wash, a dashed ring, and four stakes at
        -- the compass points where the surveyor pegged it out.
        lg.setColor(P.with(spec.color, 0.07 * dim)); lg.circle("fill", x, y, r)
        -- A cleared patch, so a claim stays findable in the middle of a forest.
        lg.setColor(P.with(P.bg, 0.55 * dim)); lg.circle("fill", x, y, math.max(4, r * 0.4))
        lg.setColor(P.with(spec.color, 0.12 * dim)); lg.circle("fill", x, y, r * 0.45)
        Scenery.boundary({ r = City.seamRange }, x, y, cam.scale, spec.color, (focused and 0.7 or 0.5) * dim)
        if r > 14 then
          local st = math.max(2, r * 0.07)
          lg.setColor(P.with(P.energy, 0.55 * dim)); lg.setLineWidth(math.max(1, st * 0.45))
          for q = 0, 3 do
            local a = q * math.pi / 2 + math.pi / 4
            local sx, sy = x + math.cos(a) * r, y + math.sin(a) * r
            lg.line(sx, sy - st, sx, sy + st * 0.4)
            lg.circle("fill", sx, sy - st, st * 0.45)
          end
        end
        local mr=math.max(2.5,R.sym(9,cam.scale))
        occupied[#occupied+1]={x=x-mr-3,y=y-mr-5,w=mr*2+6,h=mr*2+6}
        Draw.mark(s.commodity, x, y - 2, mr)
        if focused and cam.scale > 0.45 then
          label(string.upper(s.commodity) .. "  x" .. string.format("%.1f", s.yield),
            x, y + (focused and r or 20) + 4, P.with(spec.color,focused and 1 or 0.7), R.fonts.tiny)
        end
      end
    end
  end
end

function Draw.focusGrid(state)
  return state.people and "people" or Graph.gridOf(state.commodity or "water")
end

local function edgeInGrid(e,grid)
  if Graph.gridOf(e.commodity)==grid then return true end
  for name in pairs(e.wagons or {}) do if Graph.gridOf(name)==grid then return true end end
  return false
end

local PASSENGER={stop=true,station=true,resort=true,intersection=true,roundabout=true,interchange=true}
local function nodeInGrid(city,n,grid)
  if grid=="people" and City.TRANSIT_NODES[n.kind] then return true end
  for key in pairs(n.demands or {}) do if Graph.gridOf(key)==grid then return true end end
  if n.commodity then return Graph.gridOf(n.commodity)==grid end
  if n.makes and Graph.gridOf(n.makes)==grid then return true end
  for name in pairs(n.wants or {}) do if Graph.gridOf(name)==grid then return true end end
  if City.INFRA.towers[n.kind] then return grid=="power" end
  if PASSENGER[n.kind] then return grid=="people" end
  for _,e in ipairs(city.g:edgesAt(n.id)) do if edgeInGrid(e,grid) then return true end end
  if grid=="people" then
    for _,l in ipairs(city.links or {}) do if l.alive and (l.a==n.id or l.b==n.id) then return true end end
    return false
  end
  -- An unconnected fitting belongs to whichever pipe or road grid is selected.
  return city.g:degree(n.id)==0 and grid~="power" and grid~="internet"
end

local function dashes(ax, ay, bx, by, on, off)
  local dx, dy = bx - ax, by - ay
  local len = math.max(1, math.sqrt(dx * dx + dy * dy))
  for d = 0, len, on + off do
    local t0, t1 = d / len, math.min(1, (d + on) / len)
    lg.line(ax + dx * t0, ay + dy * t0, ax + dx * t1, ay + dy * t1)
  end
end

-- A bus service highlights its existing road path; it never draws another road.
function Draw.linkSegments(cam,city,l)
  local parts={}
  if l.mode=='bus' then
    for _,road in ipairs(city:roadPath(l.a,l.b,'bus') or {}) do
      parts[#parts+1]={Draw.linkPoints(cam,city,road)}
    end
  else
    parts[1]={Draw.linkPoints(cam,city,l)}
  end
  return parts
end
local function drawLinks(city, cam, state)
  local byLink = (city.transit or {}).byLink or {}
  for _, l in ipairs(city.links or {}) do
    local na, nb = city.g.nodes[l.a], city.g.nodes[l.b]
    if l.alive and not state.filter and (l.mode=="bus" or cam:seesBox(math.min(na.x, nb.x), math.min(na.y, nb.y),
        math.max(na.x, nb.x), math.max(na.y, nb.y))) then
      fading(not state.people and state.link ~= l.id and state.hoverLink ~= l.id)
      for _,part in ipairs(Draw.linkSegments(cam,city,l)) do
      local ax, ay, bx, by = part[1],part[2],part[3],part[4]
      local hot = state.link == l.id or state.hoverLink == l.id
      local trips = (byLink[l.id] or {}).trips or 0
      local w = math.max(2, 5 * cam.scale)
      if l.mode~="air" and l.mode~="bus" then segments[#segments+1]={ax=ax,ay=ay,bx=bx,by=by,pad=w+3} end
      if hot then
        lg.setColor(P.with(P.text, 0.6)); lg.setLineWidth(w + 6)
        lg.line(ax, ay, bx, by)
      end
      if l.mode == "road" then
        local roadW = w + (l.roadType=="highway" and 5 or 2)
        lg.setColor(City.ROAD_TYPES[l.roadType or "road"].colour); lg.setLineWidth(roadW)
        lg.line(ax, ay, bx, by)
        -- Two straight segments meeting at a corner leave a flat-capped
        -- notch; filling a disc the road's own width at the shared vertex
        -- is a round join, and reads as an actual curb at any bend angle.
        if na.kind == "corner" then lg.circle("fill", ax, ay, roadW / 2) end
        if nb.kind == "corner" then lg.circle("fill", bx, by, roadW / 2) end
        lg.setColor(P.with(P.energy, 0.85)); lg.setLineWidth(math.max(1, 1.4 * cam.scale))
        dashes(ax, ay, bx, by, math.max(4, 12 * cam.scale), math.max(4, 10 * cam.scale))
        local rec=byLink[l.id] or {}
        for i,kind in ipairs({"car","truck","bus"}) do
          if (rec[kind] or 0)>0 then
            local t=(R.t*0.15+l.id*0.17+i*0.23)%1
            local vx,vy=ax+(bx-ax)*t,ay+(by-ay)*t
            local size=math.max(2,3*cam.scale)
            lg.setColor(kind=="bus" and P.energy or kind=="truck" and P.good or P.flow)
            lg.rectangle("fill",vx-size,vy-size,size*(kind=="car" and 2 or 4),size*2)
            if kind=="truck" then
              lg.setColor(P.bg); lg.rectangle("fill",vx+size,vy-size,math.max(1,cam.scale),size*2)
            end
          end
        end
      else
        local spec = City.ROUTES[l.mode]
        lg.setColor(P.with(spec.colour, 0.9)); lg.setLineWidth(math.max(1.4, 2.2 * cam.scale))
        if l.mode == "bus" then
          local dx, dy = bx - ax, by - ay
          local len = math.max(1, math.sqrt(dx * dx + dy * dy))
          local dot = math.max(1.5, 2.4 * cam.scale)
          for d = 0, (hot and len or -1), math.max(8, 18 * cam.scale) do
            local t = d / len
            lg.rectangle("fill", ax + dx * t - dot, ay + dy * t - dot, dot * 2, dot * 2)
          end
        elseif l.mode == "ferry" then
          dashes(ax, ay, bx, by, math.max(6, 16 * cam.scale), math.max(5, 12 * cam.scale))
        else
          local dx, dy = bx - ax, by - ay
          local cx, cy = (ax + bx) / 2 - dy * 0.18, (ay + by) / 2 + dx * 0.18
          local px, py = ax, ay
          for i = 1, 20 do
            local t = i / 20
            local qx = (1 - t) ^ 2 * ax + 2 * (1 - t) * t * cx + t * t * bx
            local qy = (1 - t) ^ 2 * ay + 2 * (1 - t) * t * cy + t * t * by
            segments[#segments+1]={ax=px,ay=py,bx=qx,by=qy,pad=4}
            if i % 2 == 1 then lg.line(px, py, qx, qy) end
            px, py = qx, qy
          end
        end
      end
      if hot then
        local price = l.mode == "road" and l.toll or l.fare
        label(string.format("$%d  /  %d trips", price or 0, trips), (ax + bx) / 2, (ay + by) / 2 - 20,
          trips > 0 and P.textDim or P.textFaint, R.fonts.tiny)
      end
      end -- physical road segments, or the ferry/air service geometry
      fading(false)
    end
  end
end


--------------------------------------------------------------------------------
-- The land view
--
-- Each plot for sale carries a deed: what it is, what it costs, whether it can
-- be bought right now and, if not, why, and what is on it. Plots are coloured
-- by that answer, so the map reads as "green: yours for the asking" before a
-- single word is read.
--------------------------------------------------------------------------------

-- Whether a plot can be bought now, and the colour and words for it.
function Draw.landStatus(city, d)
  local err = city:districtError(d.id)
  if d.owned then return "owned", P.flow, "Yours" end
  if not err then return "buy", P.good, "Click to buy" end
  if err == "not enough cash" then
    return "short", P.warn, "Need $" .. (city:districtCost(d) - math.floor(city.money)) .. " more"
  end
  if d.island then return "far", P.textFaint, "Needs a harbour" end
  return "far", P.textFaint, "Not next to your land"
end

-- What a plot holds, as the deed lists it. Deposits only if the company has
-- surveyed it: an owned plot, or anywhere while surveyors are on the books.
function Draw.landContents(city, d)
  local found = { deposits = {}, woods = 0, ranges = 0 }
  found.surveyed = d.owned or (city.orders or {}).surveyors
  for _, s in ipairs(city.deposits or {}) do
    if not s.taken and city:districtAt(s.x, s.y) == d then
      found.deposits[s.commodity] = (found.deposits[s.commodity] or 0) + 1
    end
  end
  for _, o in ipairs(city.obstacles) do
    if city:districtAt(o.x, o.y) == d then
      if o.kind == "park" then found.woods = found.woods + 1
      elseif o.kind == "bedrock" then found.ranges = found.ranges + 1 end
    end
  end
  return found
end

local function drawLandView(city, cam, state)
  local hoverD = state.hoverGround and city:districtAt(state.hoverGround[1], state.hoverGround[2])
  for _, d in ipairs(city.districts or {}) do
    if city:districtVisible(d) and cam:seesBox(d.x, d.y, d.x + d.w, d.y + d.h) then
      local x, y = cam:toScreen(d.x, d.y)
      local w, h = d.w * cam.scale, d.h * cam.scale
      local cx, cy = x + w / 2, y + h / 2
      local m = math.max(2, 10 * cam.scale)
      local round = math.max(3, 18 * cam.scale)
      local kind, colour, words = Draw.landStatus(city, d)
      local hot, hover = state.district == d.id, hoverD == d
      local function outline(alpha, width)
        lg.setLineWidth(width)
        lg.setColor(colour[1], colour[2], colour[3], alpha)
        if d.island then lg.ellipse("line", cx, cy, w / 2 - 1, h / 2 - 1)
        else lg.rectangle("line", x + m, y + m, w - m * 2, h - m * 2, round) end
      end
      if kind == "buy" then
        lg.setColor(P.good[1], P.good[2], P.good[3], (hover or hot) and 0.12 or 0.06 + 0.02 * math.sin(R.t * 2.2))
        if d.island then lg.ellipse("fill", cx, cy, w / 2, h / 2)
        else lg.rectangle("fill", x + m, y + m, w - m * 2, h - m * 2, round) end
        outline((hover or hot) and 1 or 0.75, (hover or hot) and 3 or 2)
      elseif kind == "short" then
        outline((hover or hot) and 0.9 or 0.55, (hover or hot) and 3 or 1.5)
      elseif kind == "owned" then
        outline(0.3, 1)
      elseif hover or hot then
        outline(0.5, 1.5)
      end
      if hot then
        lg.setColor(P.energy[1], P.energy[2], P.energy[3], 0.9)
        lg.setLineWidth(2)
        if d.island then lg.ellipse("line", cx, cy, w / 2 + 3, h / 2 + 3)
        else lg.rectangle("line", x + m - 4, y + m - 4, w - m * 2 + 8, h - m * 2 + 8, round + 3) end
      end
      if kind ~= "owned" then
        -- The deed itself. A full card when the plot is big enough on screen,
        -- a price pill when it is not.
        local f = Draw.landContents(city, d)
        local price = "$" .. city:districtCost(d)
        local disc = city:landDiscount(d)
        local cw = math.min(236, w * 0.78)
        if cw >= 150 and h >= 120 then
          local ch = 96
          local bx, by = math.floor(cx - cw / 2), math.floor(cy - ch / 2)
          lg.setColor(0, 0, 0, 0.35); lg.rectangle("fill", bx + 2, by + 4, cw, ch, 8)
          lg.setColor(P.bg[1], P.bg[2], P.bg[3], kind == "far" and 0.82 or 0.94); lg.rectangle("fill", bx, by, cw, ch, 8)
          lg.setColor(colour[1], colour[2], colour[3], kind == "far" and 0.35 or 0.9)
          lg.setLineWidth(kind == "far" and 1 or 1.5); lg.rectangle("line", bx, by, cw, ch, 8)
          lg.rectangle("fill", bx, by + 8, 4, ch - 16)
          local fade = kind == "far" and 0.7 or 1
          lg.setFont(R.fonts.body); lg.setColor(P.text[1], P.text[2], P.text[3], fade)
          lg.print(d.name, bx + 12, by + 8)
          local tag = d.island and "ISLAND" or (d.spec and d.spec.label) or "TOWN"
          lg.setFont(R.fonts.tiny); lg.setColor(P.textFaint[1], P.textFaint[2], P.textFaint[3], fade)
          lg.print(tag, bx + cw - 10 - R.fonts.tiny:getWidth(tag), by + 11)
          lg.setFont(R.fonts.mid); lg.setColor(kind == "far" and P.textDim or P.energy)
          lg.print(price, bx + 12, by + 28)
          if disc > 0 then
            local dx = bx + 18 + R.fonts.mid:getWidth(price)
            local dt = "-" .. math.floor(disc * 100) .. "% today"
            lg.setFont(R.fonts.tiny); lg.setColor(P.good)
            lg.print(dt, dx, by + 34)
          end
          lg.setFont(R.fonts.small); lg.setColor(colour[1], colour[2], colour[3], kind == "far" and 0.9 or 1)
          lg.print(words, bx + 12, by + 52)
          -- Contents: people, deposits by trade, and the ground that costs.
          local ix, iy = bx + 12, by + 74
          lg.setFont(R.fonts.tiny)
          if (d.population or 0) > 0 then
            lg.setColor(P.textDim); lg.print("POP " .. d.population, ix, iy); ix = ix + R.fonts.tiny:getWidth("POP " .. d.population) + 10
          end
          if f.surveyed then
            for _, name in ipairs(Graph.TRADES) do
              local n = f.deposits[name]
              if n then
                Draw.mark(name, ix + 5, iy + 6, 5)
                lg.setFont(R.fonts.tiny); lg.setColor(P.textDim); lg.print("x" .. n, ix + 12, iy)
                ix = ix + 12 + R.fonts.tiny:getWidth("x" .. n) + 8
              end
            end
          elseif not d.island then
            lg.setColor(P.textFaint); lg.print("deposits ?", ix, iy); ix = ix + R.fonts.tiny:getWidth("deposits ?") + 10
          end
          local ground = (f.woods > 0 and (f.woods .. (f.woods > 1 and " woods" or " wood")) or "")
            .. ((f.woods > 0 and f.ranges > 0) and ", " or "")
            .. (f.ranges > 0 and (f.ranges .. (f.ranges > 1 and " ranges" or " range")) or "")
          if ground ~= "" and ix + R.fonts.tiny:getWidth(ground) < bx + cw - 8 then
            lg.setColor(P.textFaint); lg.print(ground, ix, iy)
          end
          occupied[#occupied + 1] = { x = bx, y = by, w = cw, h = ch }
        else
          local tw = R.fonts.small:getWidth(price) + 14
          local bx, by = math.floor(cx - tw / 2), math.floor(cy - 10)
          lg.setColor(P.bg[1], P.bg[2], P.bg[3], 0.92); lg.rectangle("fill", bx, by, tw, 20, 6)
          lg.setColor(colour[1], colour[2], colour[3], kind == "far" and 0.4 or 0.9); lg.setLineWidth(1)
          lg.rectangle("line", bx, by, tw, 20, 6)
          lg.setFont(R.fonts.small); lg.setColor(kind == "far" and P.textDim or colour)
          lg.print(price, bx + 7, by + 3)
          occupied[#occupied + 1] = { x = bx, y = by, w = tw, h = 20 }
        end
      elseif cam.scale > 0.12 then
        lg.setFont(R.fonts.tiny); lg.setColor(P.flow[1], P.flow[2], P.flow[3], 0.8)
        lg.print("YOURS", x + m + 8, y + m + 6)
      end
    end
  end
end

function Draw.world(city, cam, state)
  UNFOCUSED_ALPHA = city.hideUnfocusedNetworks and 0 or 0.4
  labels,occupied,segments={},{},{}; labelPriority=0
  local _,height = R.dimensions()
  lg.setScissor(cam.vx, cam.vy, cam.vw, cam.vh)
  R.drawGrid(cam, city.bounds.w, city.bounds.h)
  drawSea(city, cam, state)
  drawDistrictGround(city, cam)
  drawRiver(city, cam)
  for _,d in ipairs(city.districts) do
    if (d.pollution or 0)>1 and cam:seesBox(d.x,d.y,d.x+d.w,d.y+d.h) then
      local x,y=cam:toScreen(d.x,d.y)
      lg.setColor(0.52,0.29,0.10,math.min(0.28,d.pollution/200))
      lg.rectangle("fill",x+4,y+4,d.w*cam.scale-8,d.h*cam.scale-8,6)
      if cam.scale>0.3 then label(string.format("POLLUTION %.0f%%",d.pollution),x+d.w*cam.scale/2,y+44,P.warn,R.fonts.small) end
    end
  end
  for _,n in ipairs(city.g:aliveNodes()) do
    local recipe=City.RECIPES[n.recipe or ""]
    if recipe and recipe.farm and cam:sees(n.x,n.y,City.INFRA.farmRadius*cam.scale+20) then
      local x,y=cam:toScreen(n.x,n.y)
      local r=City.INFRA.farmRadius*cam.scale
      lg.setColor(P.with(P.good,0.09)); lg.rectangle("fill",x-r,y-r,r*2,r*2,5)
      lg.setColor(P.with(P.good,0.3)); lg.setLineWidth(1); lg.rectangle("line",x-r,y-r,r*2,r*2,5)
      for i=-2,2 do lg.line(x-r+6,y+i*r/3,x+r-6,y+i*r/3) end
    elseif n.kind=="lab" and (state.node==n.id or state.hoverNode==n.id) then
      for _,d in ipairs(city.districts) do if city:labCovers(n,d) then
        local x,y=cam:toScreen(d.x,d.y)
        lg.setColor(P.with(P.good,0.09)); lg.rectangle("fill",x,y,d.w*cam.scale,d.h*cam.scale)
      end end
    end
  end

  for _, o in ipairs(city.obstacles) do
    if city:districtVisible(city:districtAt(o.x,o.y) or {}) and cam:sees(o.x, o.y, o.r * cam.scale + 60) then
    local spec = City.OBSTACLES[o.kind]
    local x, y = cam:toScreen(o.x, o.y)
    local r = o.r * cam.scale
    local freed = city.permits and city.permits[o.kind]
    local d = city:districtAt(o.x, o.y)
    local function terrain()
      Scenery.draw(o, x, y, cam.scale, R.t, (d and not d.owned) and 0.7 or 1, function()
        -- Surveyed claims stand in a clearing, so the marker is never lost in
        -- the canopy.
        local spots = {}
        for _, s in ipairs(city.deposits or {}) do
          if (s.x - o.x) ^ 2 + (s.y - o.y) ^ 2 < (o.r + City.seamRange) ^ 2 then
            spots[#spots + 1] = { s.x - o.x, s.y - o.y, math.min(City.seamRange * 0.6, o.r * 0.3) }
          end
        end
        return spots
      end)
      Scenery.boundary(o, x, y, cam.scale, freed and P.good or spec.color, freed and 0.45 or (o.massive and 0.5 or 0.3))
    end
    -- Ground that reaches the coast stops at it: no trees in the sea.
    if o.y >= 0 and o.y - o.r < 0 then
      local _, coast = cam:toScreen(0, 0)
      withinRows(coast, cam.vy + cam.vh, terrain)
    else terrain() end
    -- Close in only: further out the hover card says the same thing without
    -- a tag on every wood.
    if cam.scale > 0.95 then
      local cross = city:groundCross(o.kind, o)
      local tag = (o.massive and (o.kind=="park" and "PROTECTED PARK" or "MOUNTAIN RANGE") or spec.name) .. (cross and (cross > 1 and string.format("  x%.1f", cross) or "  OPEN") or "  CLOSED")
      label(tag, x, y+Shape.reach(o, o.x, o.y+1)*cam.scale+3, freed and P.good or P.textDim, R.fonts.tiny)
    end
    end
  end
  -- Works that take from the ground leave a mark on it: a forestry fells a
  -- clearing with stumps and stacked logs, a quarry cuts a terraced pit.
  for _, n in ipairs(city.g:aliveNodes()) do
    if (n.recipe == "forestry" or n.recipe == "quarry") and cam:sees(n.x, n.y, 80 * cam.scale + 20) then
      local x, y = cam:toScreen(n.x, n.y)
      local r = (n.recipe == "forestry" and 80 or 62) * cam.scale
      local h = function(k) return Shape.hash(n.x, n.y, k) end
      if n.recipe == "forestry" then
        -- Felled ground: solid in the middle, thinning out into the trees.
        for _, ring in ipairs({ { 1.0, 0.18 }, { 0.9, 0.35 }, { 0.8, 0.6 }, { 0.7, 1 } }) do
          lg.setColor(0.15, 0.20, 0.14, ring[2])
          lg.circle("fill", x, y, r * ring[1])
        end
        lg.setColor(0.24, 0.22, 0.14, 0.35); lg.circle("fill", x - r * 0.1, y + r * 0.1, r * 0.35)
        for i = 1, 9 do
          local a, d = h(i) * 6.28, (0.45 + h(i + 20) * 0.5) * r
          local sx, sy, sr = x + math.cos(a) * d, y + math.sin(a) * d, math.max(1, (2.2 + h(i + 40) * 1.6) * cam.scale)
          lg.setColor(0.30, 0.22, 0.14); lg.circle("fill", sx, sy, sr)
          lg.setColor(0.62, 0.50, 0.33); lg.circle("fill", sx, sy - sr * 0.2, sr * 0.62)
        end
        -- A stack of logs, ends facing the viewer.
        local lx, ly, lr = x + r * 0.55, y + r * 0.35, math.max(1.2, 3 * cam.scale)
        for row = 0, 2 do
          for col = 0, 2 - row do
            local cx, cy = lx + (col + row * 0.5) * lr * 2.1, ly - row * lr * 1.8
            lg.setColor(0.36, 0.26, 0.16); lg.circle("fill", cx, cy, lr)
            lg.setColor(0.70, 0.56, 0.36); lg.circle("fill", cx, cy, lr * 0.6)
          end
        end
      else
        -- Terraces stepping down into the pit, each a little darker.
        for i = 0, 4 do
          local k = 1 - i * 0.18
          local pts = {}
          for j = 0, 23 do
            local a = j / 24 * math.pi * 2
            local f = 1 + 0.08 * math.sin(3 * a + h(1) * 6) + 0.05 * math.sin(5 * a + h(2) * 6)
            pts[#pts + 1] = x + math.cos(a) * r * k * f * 1.1
            pts[#pts + 1] = y + math.sin(a) * r * k * f * 0.8
          end
          local tone = 0.30 - i * 0.045
          lg.setColor(tone, tone * 0.96, tone * 0.92, 0.95); lg.polygon("fill", pts)
          lg.setColor(0.52, 0.50, 0.48, 0.35); lg.setLineWidth(1); lg.polygon("line", pts)
        end
        for i = 1, 5 do
          local a, d = h(i + 60) * 6.28, (0.6 + h(i + 70) * 0.35) * r
          local bx, by, bs = x + math.cos(a) * d * 1.1, y + math.sin(a) * d * 0.8, math.max(1.5, (3 + h(i + 80) * 3) * cam.scale)
          lg.setColor(0.58, 0.56, 0.54); lg.rectangle("fill", bx - bs, by - bs * 0.7, bs * 2, bs * 1.4, bs * 0.3)
          lg.setColor(0.38, 0.36, 0.36); lg.rectangle("fill", bx - bs, by + bs * 0.3, bs * 2, bs * 0.4)
        end
      end
    end
  end
  -- A harbour runs a jetty across the beach into deep water, with a ship
  -- tied up at the end of it riding the swell.
  for _, n in ipairs(city.g:aliveNodes()) do
    if n.kind == "terminal" and (n.haven or "port") == "port" and n.y < City.havenReach + 60
       and cam:sees(n.x, -60, 200 * cam.scale + 40) then
      local x0, y0 = cam:toScreen(n.x, n.y)
      local _, y1 = cam:toScreen(n.x, -110)
      local w = math.max(3, 16 * cam.scale)
      -- Pilings, then the deck over them.
      lg.setColor(0.18, 0.13, 0.09)
      for wy = n.y - 20, -110, -24 do
        local px, py = cam:toScreen(n.x, wy)
        lg.circle("fill", px - w * 0.55, py, math.max(1, 2.2 * cam.scale))
        lg.circle("fill", px + w * 0.55, py, math.max(1, 2.2 * cam.scale))
      end
      lg.setColor(0, 0, 0, 0.3); lg.rectangle("fill", x0 - w / 2 + 2, y1 + 3, w, y0 - y1)
      lg.setColor(0.46, 0.35, 0.24); lg.rectangle("fill", x0 - w / 2, y1, w, y0 - y1)
      lg.setColor(0.30, 0.22, 0.15); lg.setLineWidth(1)
      local plank = math.max(3, 6 * cam.scale)
      for py = y1 + plank, y0, plank do lg.line(x0 - w / 2, py, x0 + w / 2, py) end
      -- The ship, moored alongside the jetty head.
      local bob = math.sin(R.t * 1.3 + n.id) * 1.5 * cam.scale
      local sx, sy = x0 + w / 2 + 22 * cam.scale, y1 + 40 * cam.scale + bob
      local L, B = 50 * cam.scale, 14 * cam.scale
      lg.setColor(0.85, 0.92, 0.96, 0.25)
      lg.ellipse("line", sx, sy + L * 0.1, B * 1.6, L * 1.15)
      lg.setColor(0.12, 0.14, 0.18)
      lg.polygon("fill", sx - B, sy + L, sx + B, sy + L, sx + B, sy - L * 0.6, sx, sy - L, sx - B, sy - L * 0.6)
      lg.setColor(0.62, 0.20, 0.18)
      lg.polygon("fill", sx - B * 0.8, sy + L * 0.9, sx + B * 0.8, sy + L * 0.9, sx + B * 0.8, sy - L * 0.5, sx, sy - L * 0.85, sx - B * 0.8, sy - L * 0.5)
      -- Containers stacked on deck, and the bridge at the stern.
      local cols = { { 0.30, 0.55, 0.75 }, { 0.85, 0.62, 0.25 }, { 0.40, 0.65, 0.40 }, { 0.70, 0.35, 0.35 } }
      for i = 0, 3 do
        lg.setColor(cols[(i + n.id) % #cols + 1])
        lg.rectangle("fill", sx - B * 0.6, sy - L * 0.45 + i * L * 0.28, B * 1.2, L * 0.24)
      end
      lg.setColor(0.90, 0.90, 0.88); lg.rectangle("fill", sx - B * 0.6, sy + L * 0.62, B * 1.2, L * 0.2)
    end
  end
  -- Land gateways get ground of their own, drawn under everything built: a
  -- road head is a loop of trunk road with its slip roads, an air freight
  -- haven an apron and a short runway, turned to its own heading.
  for _, n in ipairs(city.g:aliveNodes()) do
    local kind = n.kind == "terminal" and (n.haven or "port")
    if (kind == "highway" or kind == "airfield") and cam:sees(n.x, n.y, 140 * cam.scale + 20) then
      local x, y = cam:toScreen(n.x, n.y)
      local k = cam.scale
      lg.push(); lg.translate(x, y)
      lg.rotate((math.floor(Shape.hash(n.x, n.y, 90) * 4) - 1.5) * 0.35)
      if kind == "highway" then
        local w = math.max(2, 14 * k)
        -- The trunk road running through, then the loop and its slips.
        lg.setColor(0, 0, 0, 0.25); lg.setLineWidth(w + 4); lg.line(-130 * k, 2, 130 * k, 2)
        lg.setColor(0.20, 0.21, 0.23); lg.setLineWidth(w); lg.line(-130 * k, 0, 130 * k, 0)
        lg.setLineWidth(math.max(1.5, 9 * k))
        lg.circle("line", 0, -34 * k, 26 * k)
        lg.circle("line", 0, 34 * k, 26 * k)
        lg.setColor(0.82, 0.72, 0.36, 0.7); lg.setLineWidth(math.max(1, 1.2 * k))
        for dx = -124, 116, 16 do lg.line(dx * k, 0, (dx + 8) * k, 0) end
        -- Traffic along the trunk road, both ways.
        for i = 0, 3 do
          local ph = ((R.t * 0.12 + i / 4 + Shape.hash(n.x, n.y, 91)) % 1) * 2 - 1
          local dir = i % 2 == 0 and 1 or -1
          local cx = ph * 130 * k * dir
          lg.setColor(i % 2 == 0 and { 0.90, 0.88, 0.80 } or { 0.85, 0.45, 0.30 })
          lg.rectangle("fill", cx - 4 * k, (dir * 3.5 - 1.5) * k, 8 * k, 3 * k, 1)
        end
      else
        -- Apron, runway with its centre line and threshold bars, a parked plane.
        lg.setColor(0, 0, 0, 0.25); lg.rectangle("fill", -40 * k + 2, -46 * k + 3, 80 * k, 44 * k, 6 * k)
        lg.setColor(0.28, 0.29, 0.30); lg.rectangle("fill", -40 * k, -46 * k, 80 * k, 44 * k, 6 * k)
        lg.setColor(0.18, 0.19, 0.20); lg.rectangle("fill", -140 * k, 14 * k, 280 * k, 26 * k, 3 * k)
        lg.setColor(0.90, 0.90, 0.86, 0.8); lg.setLineWidth(math.max(1, 1.4 * k))
        for dx = -110, 100, 20 do lg.line(dx * k, 27 * k, (dx + 10) * k, 27 * k) end
        for side = -1, 1, 2 do
          for j = 0, 3 do
            local tx = side * 132 * k
            lg.line(tx, (17 + j * 6.5) * k, tx - side * 8 * k, (17 + j * 6.5) * k)
          end
        end
        lg.setColor(0.28, 0.29, 0.30); lg.rectangle("fill", -6 * k, -4 * k, 12 * k, 20 * k)
        local px, py, q = 18 * k, -24 * k, 1.5 * k
        lg.setColor(0.86, 0.88, 0.90)
        lg.polygon("fill", px - 14 * q, py, px + 14 * q, py - 2 * q, px + 14 * q, py + 2 * q)
        lg.polygon("fill", px + 2 * q, py - 12 * q, px + 6 * q, py - 12 * q, px + 5 * q, py + 12 * q, px + 1 * q, py + 12 * q)
        lg.polygon("fill", px - 13 * q, py - 5 * q, px - 11 * q, py - 5 * q, px - 11 * q, py + 5 * q, px - 13 * q, py + 5 * q)
      end
      lg.pop()
    end
  end
  -- Power plants spread over their site: a turbine for every row of a wind
  -- park, a bank of panels for every array, a cooling tower beside the
  -- reactors, turbine housings along a weir. Drawn with the ground, under the
  -- network, so no cable is ever hidden by a blade.
  if cam.scale > 0.45 then
    for _, n in ipairs(city.g:aliveNodes()) do
      if n.kind == "source" and n.plant and cam:sees(n.x, n.y, 120 * cam.scale + 30) then
        local x, y = cam:toScreen(n.x, n.y)
        local k, units = cam.scale, math.max(1, n.level or 1)
        local fade = math.min(1, (cam.scale - 0.45) / 0.25)
        if n.plant == "wind" then
          for i = 1, units do
            local a = (i - 1) / units * math.pi * 2 + 0.6
            local tx, ty = x + math.cos(a) * 58 * k, y + math.sin(a) * 40 * k
            lg.setColor(0, 0, 0, 0.25 * fade); lg.ellipse("fill", tx + 6 * k, ty + 2 * k, 7 * k, 2.5 * k)
            lg.setColor(0.88, 0.90, 0.92, fade); lg.setLineWidth(math.max(1, 2 * k))
            lg.line(tx, ty, tx, ty - 26 * k)
            local spin = R.t * 2.2 + i * 1.3
            for b = 0, 2 do
              local ba = spin + b * math.pi * 2 / 3
              lg.setLineWidth(math.max(1, 1.6 * k))
              lg.line(tx, ty - 26 * k, tx + math.cos(ba) * 14 * k, ty - 26 * k + math.sin(ba) * 14 * k)
            end
            lg.circle("fill", tx, ty - 26 * k, math.max(1, 2 * k))
          end
        elseif n.plant == "solar" then
          for i = 1, units do
            local row, col = math.floor((i - 1) / 3), (i - 1) % 3
            local px, py = x + (col - 1) * 30 * k - 13 * k, y + 26 * k + row * 20 * k
            lg.setColor(0, 0, 0, 0.25 * fade); lg.rectangle("fill", px + 2 * k, py + 2 * k, 26 * k, 14 * k)
            lg.setColor(0.14, 0.22, 0.40, fade); lg.rectangle("fill", px, py, 26 * k, 14 * k)
            lg.setColor(0.45, 0.60, 0.85, 0.6 * fade); lg.setLineWidth(1)
            for c = 1, 3 do lg.line(px + c * 6.5 * k, py, px + c * 6.5 * k, py + 14 * k) end
            lg.line(px, py + 7 * k, px + 26 * k, py + 7 * k)
            lg.setColor(1, 1, 1, (0.10 + 0.08 * math.sin(R.t * 0.8 + i)) * fade)
            lg.polygon("fill", px + 2 * k, py + 1 * k, px + 9 * k, py + 1 * k, px + 5 * k, py + 13 * k, px, py + 13 * k)
          end
        elseif n.plant == "nuclear" then
          -- Reactor domes in a row, and one cooling tower breathing steam.
          for i = 1, units do
            local dx = x - 34 * k + (i - 1) * 17 * k
            lg.setColor(0, 0, 0, 0.25 * fade); lg.ellipse("fill", dx + 2 * k, y + 32 * k, 8 * k, 3 * k)
            lg.setColor(0.70, 0.72, 0.74, fade); lg.rectangle("fill", dx - 7 * k, y + 22 * k, 14 * k, 9 * k)
            lg.arc("fill", "pie", dx, y + 22 * k, 7 * k, math.pi, math.pi * 2)
          end
          local cx, cy = x + 44 * k, y + 6 * k
          lg.setColor(0, 0, 0, 0.25 * fade); lg.ellipse("fill", cx + 4 * k, cy + 22 * k, 16 * k, 5 * k)
          lg.setColor(0.66, 0.67, 0.69, fade)
          lg.polygon("fill", cx - 14 * k, cy + 20 * k, cx + 14 * k, cy + 20 * k, cx + 9 * k, cy, cx + 11 * k, cy - 14 * k,
            cx - 11 * k, cy - 14 * k, cx - 9 * k, cy)
          lg.setColor(0.50, 0.51, 0.53, fade); lg.ellipse("fill", cx, cy - 14 * k, 11 * k, 3 * k)
          for p = 0, 3 do
            local ph = (R.t * 0.25 + p / 4) % 1
            lg.setColor(0.90, 0.92, 0.95, 0.35 * (1 - ph) * fade)
            lg.circle("fill", cx + ph * 14 * k, cy - 18 * k - ph * 26 * k, (5 + ph * 9) * k)
          end
        elseif n.plant == "hydro" then
          -- The weir runs from the plant to the water: find which way the
          -- river is and set the turbine housings along that line, the last
          -- one on the bank with foam at its outfall.
          local best, bestA = math.huge, 0
          for q = 0, 15 do
            local a = q / 16 * math.pi * 2
            local e = city:riverEdge(n.x + math.cos(a) * 60, n.y + math.sin(a) * 60)
            if e and e < best then best, bestA = e, a end
          end
          local reach = math.max(40, math.min(160, (city:riverEdge(n.x, n.y) or 60) + 10))
          local dx, dy = math.cos(bestA), math.sin(bestA)
          local ex, ey = x + dx * reach * k, y + dy * reach * k
          -- A headrace: a stone-edged channel of river water up to the plant.
          lg.setColor(0.42, 0.40, 0.36, 0.9 * fade); lg.setLineWidth(math.max(2, 7 * k)); lg.line(x, y, ex, ey)
          lg.setColor(0.18, 0.36, 0.54, fade); lg.setLineWidth(math.max(1, 4.5 * k)); lg.line(x, y, ex, ey)
          local flow = (R.t * 0.5) % 1
          lg.setColor(0.60, 0.78, 0.92, 0.5 * fade); lg.setLineWidth(math.max(1, 1.2 * k))
          for q = 0, 3 do
            local t = (q / 4 + flow) % 1
            local fx, fy = ex + (x - ex) * t, ey + (y - ey) * t
            lg.line(fx, fy, fx + (x - ex) * 0.04, fy + (y - ey) * 0.04)
          end
          for i = 1, units do
            local t = 0.35 + 0.65 * (i / units)
            local hx, hy = x + (ex - x) * t, y + (ey - y) * t
            lg.setColor(0.60, 0.61, 0.63, fade); lg.rectangle("fill", hx - 6 * k, hy - 5 * k, 12 * k, 10 * k, 2 * k)
            lg.setColor(0.85, 0.92, 0.96, (0.4 + 0.3 * math.sin(R.t * 4 + i)) * fade)
            lg.circle("fill", hx - dy * 8 * k, hy + dx * 8 * k, 3 * k)
          end
        end
      end
    end
  end
  Scenery.clouds(cam, R.t)
  drawDistrictChrome(city, cam, state)
  drawSeams(city, cam, state)

  -- What each distribution hub runs. Drawn faintly all the time, because the
  -- radius is the thing the player grew it for, and with a spoke to every
  -- customer it looks after when it is picked up, dimmer for the ones below
  -- its minimum price.
  for _, h in ipairs(city:distributionHubs()) do
    local radius = city:hubRadius(h)
    if cam:sees(h.x, h.y, radius * cam.scale + 40) then
      local hx, hy = cam:toScreen(h.x, h.y)
      local rr = radius * cam.scale
      local live = state.node == h.id or state.hoverNode == h.id
      local colour = Graph.KINDS.exchange.color
      lg.setColor(P.with(colour, live and 0.10 or 0.04)); lg.circle("fill", hx, hy, rr)
      lg.setColor(P.with(colour, live and 0.6 or 0.22)); lg.setLineWidth(live and 1.5 or 1)
      lg.circle("line", hx, hy, rr)
      if live then
        local floor, trades = city:hubFloor(h), city:hubTrades(h)
        for _, c in ipairs(city:hubClients(h)) do
          if trades[c.commodity] then
            local cx, cy = cam:toScreen(c.x, c.y)
            local paying = (c.rate or 0) >= floor
            lg.setColor(P.with(paying and colour or P.textFaint, paying and 0.45 or 0.25)); lg.setLineWidth(1)
            lg.line(hx, hy, cx, cy)
          end
        end
      end
    end
  end

  -- The reach a building would have at its next level, while the upgrade
  -- button is under the pointer.
  if state.previewRadius then
    local pr = state.previewRadius
    local px, py = cam:toScreen(pr.x, pr.y)
    local rr = pr.r * cam.scale
    lg.setColor(P.with(Graph.KINDS.exchange.color, 0.08 + 0.04 * math.sin(R.t * 3))); lg.circle("fill", px, py, rr)
    lg.setColor(P.with(Graph.KINDS.exchange.color, 0.7)); lg.setLineWidth(2)
    local segs = 64
    for i = 0, segs - 1, 2 do
      local a0, a1 = i / segs * math.pi * 2 + R.t * 0.2, (i + 1) / segs * math.pi * 2 + R.t * 0.2
      lg.line(px + math.cos(a0) * rr, py + math.sin(a0) * rr, px + math.cos(a1) * rr, py + math.sin(a1) * rr)
    end
  end

  local selected = city.g.nodes[state.node or 0]
  if selected and selected.alive and selected.kind == "tower" then
    local x,y = cam:toScreen(selected.x,selected.y)
    lg.setColor(P.with(P.energy,0.10)); lg.circle("fill",x,y,220*cam.scale)
    lg.setColor(P.with(P.energy,0.45)); lg.circle("line",x,y,220*cam.scale)
  end

  local route=state.bottlenecks and E.route(city,state.node) or {}
  local grid=Draw.focusGrid(state)
  for _, e in ipairs(city.g.edges) do
    local ea, eb = city.g.nodes[e.a], city.g.nodes[e.b]
    if e.alive and (not state.filter or e.commodity==state.filter)
       and cam:seesBox(math.min(ea.x,eb.x), math.min(ea.y,eb.y),
                       math.max(ea.x,eb.x), math.max(ea.y,eb.y)) then
      fading(state.edge ~= e.id and state.hoverEdge ~= e.id and not edgeInGrid(e,grid))
      local ax, ay, bx, by = Draw.edgePoints(cam,city,e)
      local spec = Graph.COMMODITIES[e.commodity] or Graph.COMMODITIES.water
      local c = spec.color
      local width = math.min(10,2+e.capMax*0.6)*cam.scale+1
      segments[#segments+1]={ax=ax,ay=ay,bx=bx,by=by,pad=width/2+4}
      if state.bottlenecks and (route[e.id] or e.leaking or math.abs(city.detail.edge[e.id] or 0)>=(e.effectiveCap or e.cap)) then
        lg.setColor(P.with((e.leaking or math.abs(city.detail.edge[e.id] or 0)>=(e.effectiveCap or e.cap)) and P.warn or P.flow,0.3))
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
        if e.bulk=="highway" then
          lg.setColor(P.with(mode.colour,0.35)); lg.setLineWidth(1)
          dashes(ax,ay,bx,by,4,9)
        else lg.line(ax,ay,bx,by) end
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
        for i,name in ipairs(e.bulk=="highway" and {} or loaded) do
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
        -- A main is a pipe lying on the ground: a soft shadow under it, a dark
        -- casing, the trade colour, and a highlight along its crown.
        lg.setColor(0,0,0,0.30); lg.setLineWidth(width+3); lg.line(ax,ay+1.5,bx,by+1.5)
        lg.setColor(P.with(P.bg,0.85)); lg.setLineWidth(width+2); lg.line(ax,ay,bx,by)
        lg.setColor(P.with((e.leaking or e.unboosted) and P.bad or (e.commodity == "oil" and spec.fill or c),
          e.cap == 0 and 0.35 or (e.commodity == "oil" and 0.95 or 0.72)))
        lg.setLineWidth(width); lg.line(ax,ay,bx,by)
        if width >= 3 and e.cap ~= 0 then
          local dx, dy = bx-ax, by-ay
          local len = math.max(1, math.sqrt(dx*dx+dy*dy))
          local ox, oy = dy/len*width*0.18, -dx/len*width*0.18
          if oy > 0 then ox, oy = -ox, -oy end
          lg.setColor(1,1,1,0.16); lg.setLineWidth(math.max(1,width*0.28))
          lg.line(ax+ox,ay+oy,bx+ox,by+oy)
        end
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
      if flow ~= 0 and e.bulk~="highway" and not e.goodsRoad then
        local count = math.min(12,math.ceil(math.abs(flow)))
        for i=1,count do
          local t = (R.t*0.22+i/count)%1
          if flow < 0 then t = 1-t end
          lg.setColor(c)
          lg.circle("fill", ax+(bx-ax)*t, ay+(by-ay)*t, math.max(1, R.sym(2.8, cam.scale)))
        end
      end
      -- The main a dry house was blamed on, flashing for a moment.
      if state.flashEdge == e.id then
        lg.setColor(P.with(P.bad, 0.5 + 0.5 * math.sin(R.t * 18)))
        lg.setLineWidth(width + 4); lg.line(ax,ay,bx,by)
      end
      if e.leaking then
        local x,y = (ax+bx)/2,(ay+by)/2
        lg.setColor(P.with(P.bad,0.6+0.3*math.sin(R.t*5)))
        lg.setLineWidth(2); lg.circle("line",x,y,10+2*math.sin(R.t*4))
        -- What is escaping: droplets of whatever the main carries, thrown up
        -- and falling back, more of them the worse it has got.
        if cam.scale>0.3 then
          local col=(Graph.COMMODITIES[e.commodity] or {}).color or P.flow
          local drops=e.cap<=0 and 9 or 5
          local reach=18*math.sqrt(cam.scale)
          for i=1,drops do
            local ph=(R.t*1.25+i/drops)%1
            local ang=-math.pi/2+(i-drops/2)*0.34+math.sin(i*2.1)*0.2
            local dx=math.cos(ang)*reach*ph*1.3
            local dy=math.sin(ang)*reach*ph*1.6+reach*1.8*ph*ph
            lg.setColor(col[1],col[2],col[3],0.85*(1-ph))
            lg.circle("fill",x+dx,y+dy,math.max(1.2,2.4*math.sqrt(cam.scale)*(1-ph*0.5)))
          end
        end
      end
      if e.unboosted then
        label("NO BOOSTER",(ax+bx)/2,(ay+by)/2-22,P.bad,R.fonts.tiny)
      elseif e.leaking or state.edge == e.id or state.hoverEdge == e.id or state.bottlenecks then
        label(city:quantityPair(e.commodity,math.abs(flow),e.effectiveCap or e.cap)..(e.voltage and ("  "..City.INFRA.voltages[e.voltage].kv.." kV") or ""),(ax+bx)/2,(ay+by)/2-22,e.leaking and P.bad or P.textDim,R.fonts.tiny)
      end
      fading(false)
    end
  end

  drawLinks(city, cam, state)

  for _, n in ipairs(city.g:aliveNodes()) do
    if (not state.filter or not n.commodity or n.commodity==state.filter or (n.demands and n.demands[state.filter]))
       and cam:sees(n.x, n.y, 90) then
    fading(state.node ~= n.id and state.hoverNode ~= n.id and not nodeInGrid(city,n,grid))
    local x,y = cam:toScreen(n.x,n.y)
    -- Sized through R.sym, so pulling the camera back always makes a node
    -- smaller. The symbol inside is drawn at every zoom: one flat shape reads
    -- at eleven pixels, and swapping it for something else on the way out
    -- would only mean two things to learn instead of one.
    local r = math.max(3, R.sym(n.kind == "source" and 23 or 17, cam.scale))
    -- Two thresholds, in pixels of disc radius. A label wider than the thing
    -- it names is worse than no label, and a pip under a pixel is grit.
    local focused=state.node==n.id or state.hoverNode==n.id
    local named, fine = r >= 7.5 and focused, r >= 10 and focused
    labelPriority=(state.node==n.id or state.hoverNode==n.id) and 3 or 1
    occupied[#occupied+1]={x=x-r*1.5-3,y=y-r*1.5-3,w=r*3+6,h=r*3+6}
    local spec = n.commodity and Graph.COMMODITIES[n.commodity]
      or (n.makes and Graph.COMMODITIES[n.makes])
    local color = spec and spec.color or Graph.KINDS[n.kind].color
    local served = city.served[n.id] or 0
    if n.prospect then color = P.textDim end
    if n.roundHouse and n.dry then color = P.bad end
    local supplied = not n.prospect and (n.kind=="client" and city:fullyServed(n) or n.kind~="client" and served >= (n.demand or 0))
    if state.node == n.id or state.hoverNode == n.id then
      lg.setColor(P.text); lg.setLineWidth(math.max(1, r * 0.09))
      lg.circle("line", x, y, r + math.max(4, r * 0.5))
    end
    if n.kind == "client" and not n.prospect and not n.roundHouse and not city:fullyServed(n) then
      lg.setColor(P.with(n.grace == 1 and P.bad or P.warn,0.65))
      lg.setLineWidth(math.max(1.3, r * 0.13))
      lg.arc("line","open",x,y,r + math.max(3, r * 0.3),
        -math.pi/2,-math.pi/2+math.pi*2*(n.grace/n.patience))
    end
    if n.kind == "client" and supplied then
      lg.setColor(P.with(P.good,0.10)); lg.circle("fill",x,y,r * 1.42)
    end
    -- Close in, a customer is its building; further out, its disc.
    local building = (n.kind == "client" and not n.roundHouse and r >= 14)
      or (n.kind == "source" and not n.plant and r >= 14)
      or (n.kind == "works" and n.recipe ~= "forestry" and n.recipe ~= "quarry" and r >= 14)
      or ((n.kind == "tower" or n.kind == "pole" or n.kind == "pylon" or n.kind == "hvtower"
        or n.kind == "depot" or n.kind == "pump" or n.kind == "stop"
        or n.kind == "station" or n.kind == "resort" or n.kind == "dc") and r >= 14)
    if building and n.kind ~= "client" and n.kind ~= "source" and n.kind ~= "works" then
      -- Older saves keep the tower ladder as three kinds; they are the same
      -- pylon, one level each.
      local oldTower = ({ pole = 1, pylon = 2, hvtower = 3 })[n.kind]
      Draw.structureBuilding(oldTower and "tower" or n.kind, x, y, r, color, oldTower or n.level or 1,
        n.kind == "depot" and (n.stored or 0) / (n.capacityStore or City.depotCapacity or 1),
        math.abs((city.detail.node or {})[n.id] or 0) > 0, n.id * 0.7)
    elseif building and n.kind == "client" then
      Draw.clientBuilding(n.clientType, x, y, r, color, n.commodity, n.prospect)
    elseif building and n.kind == "source" then
      Draw.sourceBuilding(n.commodity, x, y, r, color, n.id)
    elseif building then
      local recipe = City.RECIPES[n.recipe or ""]
      Draw.worksBuilding(n.makes or (recipe and recipe.makes), x, y, r, color, (n.ready or 0) > 0, n.id * 0.13)
    else
      Draw.disc(x, y, r, color, n.prospect and 0.14 or 0.20)
    end

    if n.kind == "client" then
      lg.setColor(color)
      if not building then Draw.clientGlyph(n.clientType, x, y + r * 0.06, r / 15) end
      -- An open offer carries a beating mark, so the map says where the work is.
      if n.prospect and r >= 5 then
        local br = math.max(5, r * 0.4) * (1 + 0.12 * math.sin(R.t * 4 + n.id))
        local bx, by = x + r * 0.78, y - r * 0.78
        lg.setColor(P.energy); lg.circle("fill", bx, by, br)
        lg.setColor(P.bg); lg.setLineWidth(math.max(1.2, br * 0.28))
        lg.line(bx, by - br * 0.5, bx, by + br * 0.1)
        lg.circle("fill", bx, by + br * 0.45, math.max(0.8, br * 0.14))
      end
      if r>=7.5 and (focused or (not n.prospect and (n.supplyClosed or not city:fullyServed(n)))) then
        local title = n.prospect and "OFFER" or n.dry and "DRY" or n.supplyClosed and "SHUT"
          or n.demands and n.demands.water and n.demands.power and (city:fullyServed(n) and "Water + electricity supplied" or "Water / electricity short")
          or city:quantityPair(n.commodity,served,n.demand)
        label(title,x,y+r*1.5+8,n.prospect and P.energy or (city:fullyServed(n) and P.good or P.warn))
      end
      if focused then
        local premium = city:ratePremium(n)
        local tag = E.clientName(city,n) .. "  $" .. n.rate
        label(tag, x, y-r*1.5-24,
          premium > 0.10 and P.good or premium < -0.10 and P.bad or P.textDim, R.fonts.tiny)
      end
    elseif n.kind == "source" then
      if n.plant == "wind" then
        lg.setColor(color)
        Draw.turbine(x, y, r * 0.9)
      elseif n.plant == "nuclear" then
        lg.setColor(color)
        Draw.reactor(x, y - r * 0.04, r * 0.86)
      elseif n.plant=="solar" then
        lg.setColor(color); lg.setLineWidth(1.5)
        lg.rectangle("line",x-r*0.65,y-r*0.45,r*1.3,r*0.9)
        lg.line(x,y-r*0.45,x,y+r*0.45); lg.line(x-r*0.65,y,x+r*0.65,y)
      elseif n.plant=="hydro" then
        Draw.mark('water',x-r*0.25,y,r*0.45)
        Draw.mark('power',x+r*0.28,y,r*0.45)
      elseif not building then
        Draw.mark(n.commodity, x, y - r * 0.04, r * 0.58)
      end
      local level = n.level or 1
      -- How hard the well is actually being worked, not just how deep it is.
      -- A well reading 22/22 is the reason a customer downstream is short, and
      -- that has to be visible without opening anything.
      local drawn = (city.produced or {})[n.id] or 0
      local maxed = drawn >= (n.output or 0) and (n.output or 0) > 0
      if named or (r>=7.5 and maxed) then
        label((n.plant and string.upper((City.PLANTS[n.plant] or {}).name or "PLANT")
          or string.upper(n.commodity))
          .. "  " .. drawn .. "/" .. (n.output or 0),
          x, y+r*1.5+8, maxed and P.warn or color)
      end
      -- A capacity bar across the bottom of the well, so the ratio reads at a
      -- glance from any zoom the labels survive.
      if focused and cam.scale > 0.5 and (n.output or 0) > 0 then
        local bw = r * 1.5
        occupied[#occupied+1]={x=x-bw/2-2,y=y+r*1.5+26,w=bw+4,h=7}
        local frac = math.min(1, drawn / n.output)
        lg.setColor(P.with(P.textFaint, 0.7))
        lg.rectangle("fill", x - bw/2, y + r*1.5 + 28, bw, 3, 1.5)
        lg.setColor(maxed and P.warn or color)
        lg.rectangle("fill", x - bw/2, y + r*1.5 + 28, bw * frac, 3, 1.5)
      end
      if fine then
        -- Level pips: how far the well has been deepened.
        local pips, gap = city:maxLevel(n), math.max(3.6, r * 0.25)
        local pr = math.max(1, r * 0.085)
        for i = 1, pips do
          lg.setColor(i <= level and color or P.with(P.textFaint, 0.6))
          lg.setLineWidth(math.max(0.9, pr * 0.5))
          lg.circle(i <= level and "fill" or "line",
            x - (pips - 1) * gap / 2 + (i - 1) * gap, y - r - pr * 3, pr)
        end
        -- Port ring: one pip per output pipe, filled as pipes are taken up.
        -- Drawn as a ring around the well (not above it) so it never reads
        -- as more depth pips.
        local ppr = math.max(1, R.sym(1.9, cam.scale))
        for i=1,n.ports do
          local a = i/n.ports*math.pi*2
          lg.setColor(i<=city.g:degree(n.id) and color or P.textFaint)
          lg.circle("fill",x+math.cos(a)*(r+ppr*1.6),y+math.sin(a)*(r+ppr*1.6),ppr)
        end
      end

    else
      lg.setColor(color)
      -- A corner's own bend is now drawn by the road itself (drawLinks'
      -- round join), so the fixed schematic icon here would just duplicate
      -- it -- with the wrong angle. The palette button still shows it.
      if n.kind ~= "corner" and not building then Draw.structureGlyph(n.kind, x, y, r / 15) end
      -- A building on a ladder wears its level: pips over it, and a distribution
      -- hub a second ring in its own colour, so the top of the ladder reads as
      -- a different thing from across the map.
      local family = city:levelFamily(n)
      if family and r >= 5 then
        local level = city:levelOf(n)
        if city:isDistribution(n) then
          lg.setColor(Graph.KINDS.exchange.color); lg.setLineWidth(math.max(1.2, r * 0.12))
          lg.circle("line", x, y, r * 1.28)
        end
        if level > 1 and fine then
          local count, gap = city:levelCount(n), math.max(3.6, r * 0.25)
          local pr = math.max(1, r * 0.085)
          for i = 1, count do
            lg.setColor(i <= level and color or P.with(P.textFaint, 0.6))
            lg.setLineWidth(math.max(0.9, pr * 0.5))
            lg.circle(i <= level and "fill" or "line", x - (count - 1) * gap / 2 + (i - 1) * gap, y - r * 1.28 - pr * 3, pr)
          end
        end
      end
      -- A tower's upgrade as a corner badge: the two-coil transformer symbol,
      -- or an upward chevron for a booster.
      if n.upgrade and r >= 5 then
        local bx, by, br = x + r * 0.72, y - r * 0.72, math.max(2.5, r * 0.34)
        lg.setColor(P.bg); lg.circle("fill", bx, by, br + 1)
        lg.setColor(n.upgrade == "booster" and P.energy or P.good)
        lg.setLineWidth(math.max(1, br * 0.28))
        if n.upgrade == "booster" then
          lg.line(bx - br * 0.6, by + br * 0.35, bx, by - br * 0.35, bx + br * 0.6, by + br * 0.35)
        else
          lg.circle("line", bx - br * 0.3, by, br * 0.45); lg.circle("line", bx + br * 0.3, by, br * 0.45)
        end
      end
      if n.kind == "gate" then
        if named then
          label(tostring(n.throughput or 0), x, y+r*1.5+8,
            (n.throughput or 0) == 0 and P.bad or P.warn)
        end
      elseif n.kind == "terminal" then
        if named then
          label((City.HAVENS[n.haven or "port"] or {}).name or "HAVEN", x, y+r*1.5+8, color)
        end
        local landed = (city.produced or {})[n.id] or 0
        if landed > 0 and r >= 6 then
          -- A freight terminal used to change only by a number once a day.
          -- While it has live freight, run a small truck/plane/ship back and
          -- forth beside it continuously, the same R.t-driven technique the
          -- pipe-flow dots and road traffic already use.
          local span = r * 1.6
          local phase = (R.t * 0.35 + n.id * 0.11) % 2
          local ping01 = math.abs(phase - 1) -- 1 -> 0 -> 1, a smooth ping-pong
          local vx = x + r * 1.5 + span * ping01
          Draw.freightVehicle(n.haven or "port", vx, y, phase < 1 and -1 or 1, r * 0.32)
        end
        if focused then
          local _, bill = city:importBill()
          label(landed > 0 and (landed .. " landed  -$" .. math.floor((bill[n.id] or 0) + 0.5))
            or "no freight moving", x, y-r*1.5-24, landed > 0 and P.textDim or P.warn, R.fonts.tiny)
        end
      elseif n.kind == "works" then
        local recipe = City.RECIPES[n.recipe or ""]
        if recipe and r>=7.5 and (focused or (n.ready or 0)<recipe.rate) then
          label((n.ready or 0) .. "/" .. recipe.rate .. " " .. recipe.makes, x, y+r*1.5+8,
            (n.ready or 0) >= recipe.rate and P.good or (n.ready or 0) > 0 and P.warn or P.bad)
        end
        if focused and recipe then
          label(recipe.name, x, y-r*1.5-24, P.textDim, R.fonts.tiny)
        end
      elseif n.kind == "station" then
        if named then
          local tank = city.served[n.id] or 0
          label(tank .. " in the tank", x, y+r*1.5+8, tank > 0 and P.good or P.warn)
        end
      elseif n.kind == "resort" then
        if named then label("LEVEL " .. (n.level or 1), x, y+r*1.5+8, color) end
      elseif n.kind == "stop" then
        local rec = (((city.transit or {}).byNode) or {})[n.id]
        if named and rec and rec.boarded then label(rec.boarded .. " boarded", x, y+r*1.5+8, P.textDim) end
      elseif n.kind == "depot" then
        local fill=math.min(1,(n.stored or 0)/(n.capacityStore or City.depotCapacity))
        lg.setColor(P.panelEdge); lg.rectangle("fill",x-r,y+r+4,r*2,4)
        lg.setColor(Graph.COMMODITIES[n.commodity or "water"].color); lg.rectangle("fill",x-r,y+r+4,r*2*fill,4)
        if named then
          label(city:quantity(n.commodity,n.stored or 0), x, y+r*1.5+8,
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
    fading(false)
    end
  end

  -- The opening guide, where it points at the map: the spring to sink the well
  -- on, the house to sign, or a ghost of the drag from one to the other.
  local guide = E.tutorialTarget(city,state)
  if guide and (guide.x or guide.from) then
    local pulse = 0.5+0.5*math.sin(R.t*5)
    lg.setColor(P.with(P.good,0.55+0.45*pulse)); lg.setLineWidth(3)
    if guide.from then
      local ax,ay = cam:toScreen(guide.from.x,guide.from.y)
      local bx,by = cam:toScreen(guide.to.x,guide.to.y)
      lg.circle("line",ax,ay,30+4*pulse)
      lg.circle("line",bx,by,30+4*pulse)
      local len = math.max(1,math.sqrt((bx-ax)^2+(by-ay)^2))
      lg.setLineWidth(2)
      for d=0,len,16 do
        local t0,t1 = d/len,math.min(1,(d+8)/len)
        lg.line(ax+(bx-ax)*t0,ay+(by-ay)*t0,ax+(bx-ax)*t1,ay+(by-ay)*t1)
      end
      local t = (R.t*0.6)%1
      lg.circle("fill",ax+(bx-ax)*t,ay+(by-ay)*t,8)
    else
      local x,y = cam:toScreen(guide.x,guide.y)
      lg.circle("line",x,y,30+5*pulse)
      local ty = y-36+6*math.sin(R.t*6)
      lg.polygon("fill",x,ty,x-11,ty-16,x+11,ty-16)
      lg.rectangle("fill",x-4,ty-34,8,19)
    end
    lg.setLineWidth(1)
  end
  -- Single points of failure, and whatever upgrade the advisor is pointed at.
  do
    local pulse = 0.5+0.5*math.sin(R.t*4)
    local function mark(kind,id,colour)
      if kind=="edge" then
        local e = city.g.edges[id]
        if not (e and e.alive) then return end
        local a,b = city.g.nodes[e.a],city.g.nodes[e.b]
        local ax,ay = cam:toScreen(a.x,a.y)
        local bx,by = cam:toScreen(b.x,b.y)
        lg.setColor(P.with(colour,0.30+0.40*pulse)); lg.setLineWidth(7); lg.line(ax,ay,bx,by)
      else
        local n = city.g.nodes[id]
        if not (n and n.alive) then return end
        local x,y = cam:toScreen(n.x,n.y)
        lg.setColor(P.with(colour,0.45+0.45*pulse)); lg.setLineWidth(3)
        lg.circle("line",x,y,22+4*pulse)
      end
    end
    local report = state.spof and city:resilienceReport()
    if report then
      for i=1,math.min(#report.points,8) do mark(report.points[i].kind,report.points[i].id,P.bad) end
    end
    if state.advisorFocus then mark(state.advisorFocus.kind,state.advisorFocus.id,P.good) end
    lg.setLineWidth(1)
  end
  R.drawEffects(cam)
  local mx,my = love.mouse.getPosition()
  if state.drag and state.transit then
    local from = city.g.nodes[state.drag]
    local x,y = cam:toScreen(from.x,from.y)
    local target = state.hoverNode
    local err = target and target ~= from.id and city:linkError(from.id,target,state.transit)
    lg.setColor(err and P.bad or P.good); lg.setLineWidth(2); lg.line(x,y,mx,my)
    if target and target ~= from.id then
      local cost = not err and city:linkQuote(from.id,target,state.transit)
      label(err or ("Build for $"..cost..((cost > city.money) and "  (need more cash)" or "")),
        (x+mx)/2,(y+my)/2-24,err and P.bad or P.energy)
    end
  elseif state.drag then
    local from = city.g.nodes[state.drag]
    local x,y = cam:toScreen(from.x,from.y)
    local target = state.hoverNode
    -- The size in hand decides how far the drag may reach, so the ring and the
    -- refusal both have to know which main is being drawn.
    local drawn = not state.rail and state.size or nil
    local err = target and city:pipeError(from.id,target,state.commodity,state.rail,drawn)
    lg.setColor(P.with(state.rail and P.accent or P.textDim,0.25)); lg.setLineWidth(1)
    lg.circle("line",x,y,city:rangeBetween(from.id,from.id,state.rail,state.commodity,drawn)*cam.scale)
    lg.setColor(err and P.bad or P.good); lg.setLineWidth(2); lg.line(x,y,mx,my)
    -- Ground the run would cross lights up along its real outline, in what it
    -- does to the price: red closed, amber dearer, green open.
    local crossing = {}
    if not state.rail then
      local tx, ty
      if target and city.g.nodes[target] then tx, ty = city.g.nodes[target].x, city.g.nodes[target].y
      else tx, ty = cam:toWorld(mx, my) end
      for _, o in ipairs(city.obstacles) do
        if Shape.crosses(o, from.x, from.y, tx, ty) then
          local cross = city:groundCross(o.kind, o)
          local colour = not cross and P.bad or cross > 1 and P.warn or P.good
          local pts = {}
          for _, pt in ipairs(Shape.outline(o)) do
            local sx, sy = cam:toScreen(pt[1], pt[2]); pts[#pts + 1] = sx; pts[#pts + 1] = sy
          end
          pts[#pts + 1] = pts[1]; pts[#pts + 1] = pts[2]
          lg.setColor(colour[1], colour[2], colour[3], 0.18); lg.setLineWidth(8); lg.line(pts)
          lg.setColor(colour[1], colour[2], colour[3], 0.85 + 0.15 * math.sin(R.t * 6)); lg.setLineWidth(2); lg.line(pts)
          local name = o.massive and (o.kind == "park" and "Protected park" or "Mountain range")
            or (o.kind == "park" and "Woodland" or "Bedrock")
          local ox, oy = cam:toScreen(o.x, o.y)
          label((not cross and "CLOSED" or cross > 1 and string.format("x%.1f", cross) or "open") .. "  " .. name, ox, oy - 8, colour, R.fonts.small)
          crossing[#crossing + 1] = { name = name, cross = cross }
        end
      end
      if city:segRiver(from.x, from.y, tx, ty) then
        local cross = city:groundCross("river")
        crossing[#crossing + 1] = { name = "the river", cross = cross }
      end
    end
    if target and target~=from.id then
      if err then
        label(err,(x+mx)/2,(y+my)/2-24,P.bad)
      else
        -- The quote, itemised, right where the pipe is being drawn.
        local want = state.rail and state.capacity or (state.size or "small")
        local grade = math.min(city.lining or 1, state.grade or 1)
        local q = city:pipeQuote(from.id,target,state.commodity,want,state.rail,grade)
        local p=E.pipePreview(city,from.id,target,state.commodity,want,state.rail,grade)
        if not p.error then
          local unsigned=city.g.nodes[target].prospect
          local note=unsigned and "Unsigned offer: sign before earning income."
            or p.displaced>0 and (p.displaced.." other customers would receive less.")
          local qw=math.min(350,cam.vw-32)
          local rows={
            {"Build for $"..q.total,R.fonts.mid,P.energy},
            {string.format("%d m  /  Capacity %s",math.floor(q.metres),q.capacity),R.fonts.small,P.textDim},
            {(p.demand and (p.delivery.."/"..p.demand.." supplied  /  ") or "")..
              string.format("Profit $%+d/day",p.net),R.fonts.body,p.net>0 and P.good or p.net<0 and P.bad or P.textDim},
            {p.cash<0 and ("Need $"..(-p.cash).." more") or ("Cash remaining: $"..p.cash),R.fonts.body,p.cash<0 and P.bad or P.text},
          }
          -- The one number that says whether it is worth it.
          if p.net>0 then
            local days=math.ceil(q.total/p.net)
            table.insert(rows,3,{"Pays for itself in "..days..(days==1 and " day" or " days"),R.fonts.small,
              days<=10 and P.good or days<=30 and P.text or P.warn})
          end
          if note then rows[#rows+1]={note,R.fonts.small,P.warn} end
          -- Why the price is what it is, when the ground is the reason.
          local worst
          for _, c in ipairs(crossing) do
            if c.cross and c.cross > 1 and (not worst or c.cross > worst.cross) then worst = c end
          end
          if worst then
            table.insert(rows, 3, {string.format("Crosses %s: x%.1f on this main", string.lower(worst.name) == "the river" and "the river" or string.lower(worst.name), worst.cross), R.fonts.small, P.warn})
          end
          local qh=20
          for _,row in ipairs(rows) do
            local _,lines=row[2]:getWrap(row[1],qw-28)
            row.height=#lines*row[2]:getHeight()*row[2]:getLineHeight()
            qh=qh+row.height+8
          end
          local qx=math.max(cam.vx+16,math.min(cam.vx+cam.vw-qw-16,mx+20))
          local qy=math.max(cam.vy+12,math.min(cam.vy+cam.vh-70-qh,my-qh-22))
          occupied[#occupied+1]={x=qx-4,y=qy-4,w=qw+8,h=qh+8}
          lg.setColor(P.panel); lg.rectangle("fill",qx,qy,qw,qh,7)
          lg.setColor(p.cash<0 and P.bad or P.flow); lg.setLineWidth(1)
          lg.rectangle("line",qx,qy,qw,qh,7)
          local yy=qy+12
          for _,row in ipairs(rows) do
            lg.setFont(row[2]); lg.setColor(row[3]); lg.printf(row[1],qx+14,yy,qw-28)
            yy=yy+row.height+8
          end
        else
          label(p.error,(x+mx)/2,(y+my)/2-24,P.bad)
        end
      end
    end
  elseif state.tool and mx>cam.vx and my>cam.vy and my<cam.vy+cam.vh then
    local wx,wy = cam:toWorld(mx,my)
    -- Ground that refuses the building in hand shows its whole outline, so
    -- the refusal has a shape and not only a sentence.
    local under = city:obstacleAt(wx, wy)
    if under and not under.river and not (city.permits and city.permits[under.kind]) then
      local pts = {}
      for _, pt in ipairs(Shape.outline(under)) do
        local sx, sy = cam:toScreen(pt[1], pt[2]); pts[#pts + 1] = sx; pts[#pts + 1] = sy
      end
      pts[#pts + 1] = pts[1]; pts[#pts + 1] = pts[2]
      lg.setColor(P.bad[1], P.bad[2], P.bad[3], 0.14); lg.setLineWidth(8); lg.line(pts)
      lg.setColor(P.bad[1], P.bad[2], P.bad[3], 0.8); lg.setLineWidth(2); lg.line(pts)
    end
    local err, cost, seam
    if state.tool=="source" then
      err = city:sourceError(state.commodity,wx,wy,state.plant)
      cost, seam = city:sourceCost(state.commodity,wx,wy,state.plant)
      if not err and state.commodity=="power" then
        err = city:materialError(city:materialsFor("source",state.plant))
      end
    else
      err = city:placementError(wx,wy)
      -- One tower tool stands for three voltages; the choice is in the panel.
      local kind = state.tool=="grid" and City.INFRA.voltages[state.voltage or "low"].tower or state.tool
      local unlock = City.BUILD_UNLOCK[kind]
      if not err and unlock and not city:unlocked(unlock) then err = "not available yet" end
      if not err and state.tool=="resort" then err = city:resortSiteError(wx,wy) end
      cost = city:nodeCost(kind)
      if state.tool=="terminal" then
        local haven = state.havenKind or "port"
        cost = city:havenCost(haven)
        if not err then err = select(2, city:havenSite(wx,wy,haven)) end
      elseif state.tool=="works" then
        cost = (City.RECIPES[state.recipe or ""] or {}).cost or cost
        if not err and (City.RECIPES[state.recipe or ""] or {}).farm then err=city:farmSiteError(wx,wy) end
      end
      -- The bill of materials, before the click rather than after it.
      if not err then
        local bill = state.tool=="works" and city:materialsFor("works",state.recipe)
          or city:materialsFor(kind)
        err = city:materialError(bill)
      end
    end
    local color = (err or cost>city.money) and P.bad or P.good
    lg.setColor(P.with(color,0.3)); lg.setLineWidth(1)
    local carries = City.INFRA.towers[state.tool=="grid" and City.INFRA.voltages[state.voltage or "low"].tower or state.tool]
    local range = state.tool=="pump" and City.INFRA.pumpRange or carries and City.INFRA.voltages[carries].span
      or state.tool=="binder" and City.INFRA.binderRange or state.tool=="tower" and 220
      or 300
    lg.circle("line",mx,my,range*cam.scale)
    if state.tool=='works' and (City.RECIPES[state.recipe or ''] or {}).farm then
      local r=City.INFRA.farmRadius*cam.scale
      lg.rectangle('line',mx-r,my-r,2*r,2*r)
    elseif state.tool=='lab' then
      for _,d in ipairs(city.districts) do if city:labCovers({x=wx,y=wy},d) then
        local x,y=cam:toScreen(d.x,d.y)
        lg.setColor(P.with(color,0.1)); lg.rectangle('fill',x,y,d.w*cam.scale,d.h*cam.scale)
      end end
    end
    lg.setColor(color); lg.circle("line",mx,my,18*cam.scale)
    label(err or ("$"..cost),mx,my+30,color)

  end
  fading(false)
  if state.tab == "map" then drawLandView(city, cam, state) end
  drawLabels(cam)
  lg.setScissor()
end

return Draw
