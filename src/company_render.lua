local P = require("palette")
local Graph = require("graph")
local City = require("city")
local R = require("render")
local E = require("experience")
local Scenery = require("scenery")
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

-- Every node on the map is a disc: a dark body tinted by its trade, and a rim
-- in the trade colour. Flat, so the symbol on top of it is what the eye finds.
function Draw.disc(x, y, r, color, tint)
  lg.setColor(0,0,0,0.22)
  lg.circle("fill", x, y+2, r+2)
  lg.setColor(P.bg)
  lg.circle("fill", x, y, r)
  lg.setColor(P.with(color, tint or 0.20))
  lg.circle("fill", x, y, r)
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
        lg.setColor(d.owned and {P.land[1],P.land[2],P.land[3],0.96} or {0.100,0.122,0.128,0.92})
        lg.rectangle("fill",px,py,pw,ph,round)
        Scenery.grass(d.x+10,d.y+10,d.w-20,d.h-20,px,py,cam.scale,d.owned and 1 or 0.55)
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
      lg.setColor(P.with(P.bg, 0.2))
      if d.island then lg.ellipse("fill", cx, cy, w / 2, h / 2)
      else lg.rectangle("fill", x, y, w, h) end
      local hot = state.district == d.id
      local buyable = not city:districtError(d.id)
      lg.setColor(P.with(hot and P.energy or buyable and P.good or P.textFaint, hot and 0.9 or 0.25))
      lg.setLineWidth(hot and 2 or 1)
      local m = math.max(2, 10 * cam.scale)
      if d.island then lg.ellipse("line", cx, cy, w / 2 - 2, h / 2 - 2)
      else lg.rectangle("line", x + m, y + m, w - m * 2, h - m * 2, math.max(3, 18 * cam.scale)) end
      -- Prices only when land is the question: the land view, the overview
      -- from far out, or the plot just clicked. Close in, a city of price
      -- tags is noise over the network being built.
      local pricing = hot or state.tab == "map" or cam.scale <= 0.34
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
  -- The coastline itself.
  local cx0, cy = cam:toScreen(left - 200, 0)
  local cx1 = cam:toScreen(right + 200, 0)
  lg.setColor(P.with({ 0.40, 0.64, 0.88 }, 0.6)); lg.setLineWidth(2)
  -- Broken where the river runs out into the sea: an estuary has no shore
  -- across it.
  local p = city:riverPath()
  if p and p.n > 0 then
    local mx0 = cam:toScreen(p.x[1] - p.hw[1], 0)
    local mx1 = cam:toScreen(p.x[1] + p.hw[1], 0)
    if mx0 > cx0 then lg.line(cx0, cy, math.min(mx0, cx1), cy) end
    if mx1 < cx1 then lg.line(math.max(mx1, cx0), cy, cx1, cy) end
  else
    lg.line(cx0, cy, cx1, cy)
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
            spots[#spots + 1] = { s.x - o.x, s.y - o.y, City.seamRange + 18 }
          end
        end
        return spots
      end)
      Scenery.boundary(o, x, y, cam.scale, freed and P.good or spec.color, freed and 0.45 or (o.massive and 0.5 or 0.3))
    end
    -- Ground that reaches the coast stops at it: no trees in the sea.
    if o.y - o.r < 0 then
      local _, coast = cam:toScreen(0, 0)
      withinRows(coast, cam.vy + cam.vh, terrain)
    else terrain() end
    if cam.scale > 0.48 then
      local cross = city:groundCross(o.kind, o)
      local tag = (o.massive and (o.kind=="park" and "PROTECTED PARK" or "MOUNTAIN RANGE") or spec.name) .. (cross and (cross > 1 and string.format("  x%.1f", cross) or "  OPEN") or "  CLOSED")
      label(tag, x, y+r+3, freed and P.good or P.textDim, R.fonts.tiny)
    end
    end
  end
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
        lg.setColor(P.with((e.leaking or e.unboosted) and P.bad or (e.commodity == "oil" and spec.fill or c),
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
    Draw.disc(x, y, r, color, n.prospect and 0.14 or 0.20)

    if n.kind == "client" then
      lg.setColor(color)
      Draw.clientGlyph(n.clientType, x, y + r * 0.06, r / 15)
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
      else
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
      if n.kind ~= "corner" then Draw.structureGlyph(n.kind, x, y, r / 15) end
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
  drawLabels(cam)
  lg.setScissor()
end

return Draw
