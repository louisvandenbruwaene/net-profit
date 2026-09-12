local P = require("palette")
local Graph = require("graph")
local City = require("city")
local R = require("render")
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
--------------------------------------------------------------------------------

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
  local pts = (spec.mark == "bolt") and boltPoints(x, y, r) or dropletPoints(x, y, r)
  lg.setColor(P.with(spec.fill, dim and 0.45 or 1))
  lg.polygon("fill", pts)
  lg.setColor(P.with(spec.color, dim and 0.5 or 1))
  lg.setLineWidth(1.4)
  lg.polygon("line", pts)
  -- Oil is nearly black, so it gets a highlight to stop it reading as a hole.
  if commodity == "oil" then
    lg.setColor(P.with(spec.color, dim and 0.30 or 0.62))
    lg.setLineWidth(1)
    lg.line(x - r * 0.30, y + r * 0.14, x - r * 0.34, y - r * 0.16)
  end
end

-- Kept as an alias: most of the game's trades really are droplets.
Draw.droplet = Draw.mark

-- Customer glyphs: a house for households, a filled glass for pubs, a works
-- with a chimney for factories.
function Draw.clientGlyph(kind, x, y, s)
  s = s or 1
  lg.setLineWidth(1.6)
  if kind == "factory" then
    lg.rectangle("line", x - 8 * s, y - 4 * s, 16 * s, 11 * s)
    lg.line(x - 8 * s, y - 4 * s, x - 8 * s, y - 11 * s, x - 4 * s, y - 11 * s, x - 4 * s, y - 4 * s)
    lg.line(x - 2 * s, y + 1 * s, x + 6 * s, y + 1 * s)
  elseif kind == "pub" then
    -- A glass with a head on it, which is the whole point of the trade.
    lg.polygon("line", x - 6 * s, y - 8 * s, x + 6 * s, y - 8 * s,
                       x + 4 * s, y + 8 * s, x - 4 * s, y + 8 * s)
    lg.line(x + 6 * s, y - 5 * s, x + 10 * s, y - 4 * s, x + 10 * s, y + 2 * s, x + 5 * s, y + 3 * s)
    lg.line(x - 5.4 * s, y - 3 * s, x + 5.4 * s, y - 3 * s)
  elseif kind == "workshop" then
    -- A workshop: a saw-tooth roof, the shape every light-industrial shed has.
    lg.rectangle("line", x - 9 * s, y - 1 * s, 18 * s, 9 * s)
    lg.line(x - 9 * s, y - 1 * s, x - 9 * s, y - 6 * s, x - 3 * s, y - 1 * s)
    lg.line(x - 3 * s, y - 1 * s, x - 3 * s, y - 6 * s, x + 3 * s, y - 1 * s)
    lg.line(x + 3 * s, y - 1 * s, x + 3 * s, y - 6 * s, x + 9 * s, y - 1 * s)
  elseif kind == "estate" then
    lg.line(x - 10 * s, y - 1 * s, x - 4 * s, y - 8 * s, x + 2 * s, y - 1 * s)
    lg.rectangle("line", x - 9 * s, y - 1 * s, 11 * s, 9 * s)
    lg.rectangle("line", x + 3 * s, y - 5 * s, 7 * s, 13 * s)
  else
    lg.line(x - 9 * s, y - 1 * s, x, y - 9 * s, x + 9 * s, y - 1 * s)
    lg.rectangle("line", x - 6 * s, y - 1 * s, 12 * s, 9 * s)
  end
end

function Draw.structureGlyph(kind, x, y)
  lg.setLineWidth(1.6)
  if kind == "pump" then
    lg.polygon("line", x - 5, y - 8, x + 7, y, x - 5, y + 8)
  elseif kind == "tower" then
    lg.rectangle("line", x - 7, y - 8, 14, 10)
    lg.line(x - 5, y + 2, x - 7, y + 9, x + 7, y + 9, x + 5, y + 2)
  elseif kind == "gate" then
    -- A valve: two seats closing on the line.
    lg.line(x - 9, y, x - 4, y); lg.line(x + 4, y, x + 9, y)
    lg.polygon("line", x - 4, y - 7, x - 4, y + 7, x + 4, y - 7, x + 4, y + 7)
  elseif kind == "depot" then
    lg.rectangle("line", x - 8, y - 3, 16, 11)
    lg.line(x - 8, y - 3, x, y - 10, x + 8, y - 3)
  elseif kind == "terminal" then
    -- A crane over a quay: the generic haven, whichever door it happens to be.
    lg.line(x - 8, y + 8, x + 9, y + 8)
    lg.line(x - 3, y + 8, x - 3, y - 8, x + 8, y - 8)
    lg.line(x + 8, y - 8, x + 8, y - 3)
    lg.line(x - 3, y - 4, x - 8, y - 8)
  elseif kind == "manifold" then
    lg.line(x - 8, y, x + 8, y); lg.line(x, y - 8, x, y + 8)
    lg.line(x - 6, y - 6, x + 6, y + 6); lg.line(x - 6, y + 6, x + 6, y - 6)
  else
    lg.line(x - 7, y, x + 7, y); lg.line(x, y - 7, x, y + 7)
  end
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
      offset = ({water=-6, beer=0, oil=6})[e.commodity]
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
      label(hv.name, x + w / 2, y + h - 22,
        d.owned and P.energy or P.with(P.energy, 0.55), R.fonts.tiny)
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
        Draw.mark(s.commodity, x, y - 2, math.max(6, 9 * cam.scale))
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
    for d = -r + 4, r - 4, 12 do
      local h = math.sqrt(math.max(0, r*r-d*d))
      lg.setColor(P.with(spec.color, freed and 0.09 or 0.18))
      if o.kind == "river" then lg.line(x-h, y+d, x+h, y+d)
      else lg.line(x+d, y-h, x+d, y+h) end
    end
    if cam.scale > 0.48 then
      local cross = city:groundCross(o.kind)
      local tag = spec.name .. (cross and (cross > 1 and string.format("  x%.1f", cross) or "  OPEN") or "  CLOSED")
      label(tag, x, y-6, freed and P.good or spec.color, R.fonts.tiny)
    end
  end
  drawSeams(city, cam)

  local selected = city.g.nodes[state.node or 0]
  if selected and selected.alive and selected.kind == "tower" then
    local x,y = cam:toScreen(selected.x,selected.y)
    lg.setColor(P.with(P.energy,0.10)); lg.circle("fill",x,y,220*cam.scale)
    lg.setColor(P.with(P.energy,0.45)); lg.circle("line",x,y,220*cam.scale)
  end

  for _, e in ipairs(city.g.edges) do
    if e.alive then
      local ax, ay, bx, by = Draw.edgePoints(cam,city,e)
      local spec = Graph.COMMODITIES[e.commodity] or Graph.COMMODITIES.water
      local c = spec.color
      local width = math.min(10,2+e.capMax*0.6)*cam.scale+1
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
          lg.setColor(c); lg.circle("fill",ax+(bx-ax)*t,ay+(by-ay)*t,2.5)
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
    local x,y = cam:toScreen(n.x,n.y)
    local r = math.max(12,(n.kind == "source" and 23 or 17)*cam.scale)
    local spec = n.commodity and Graph.COMMODITIES[n.commodity]
    local color = spec and spec.color or Graph.KINDS[n.kind].color
    local served = city.served[n.id] or 0
    if n.prospect then color = P.textDim end
    if state.node == n.id or state.hoverNode == n.id then
      lg.setColor(P.text); lg.setLineWidth(1.5); lg.circle("line",x,y,r+9)
    end
    if n.kind == "client" and not n.prospect and served < n.demand then
      lg.setColor(P.with(n.grace == 1 and P.bad or P.warn,0.65)); lg.setLineWidth(2)
      lg.arc("line","open",x,y,r+5,-math.pi/2,-math.pi/2+math.pi*2*(n.grace/n.patience))
    end
    lg.setColor(P.bg); lg.circle("fill",x,y,r)
    lg.setColor(P.with(color,0.2)); lg.circle("fill",x,y,r)
    lg.setColor(color); lg.setLineWidth(1.8); lg.circle("line",x,y,r)

    if n.kind == "client" then
      lg.setColor(color)
      Draw.clientGlyph(n.clientType, x, y, math.min(1, math.max(0.75, cam.scale)))
      -- The trade badge: which droplet this building drinks.
      if cam.scale > 0.55 then
        Draw.mark(n.commodity, x + r * 0.78, y - r * 0.78, math.max(5, 7 * cam.scale), n.prospect)
      end
      local title = n.prospect and "OFFER" or n.supplyClosed and "SHUT" or string.format("%d/%d",served,n.demand)
      label(title,x,y+r+6,n.prospect and P.energy or (served>=n.demand and P.good or P.warn))
      if cam.scale > 0.72 then
        local premium = city:ratePremium(n)
        local tag = City.CLIENTS[n.clientType].name .. "  $" .. n.rate
        label(tag, x, y-r-21,
          premium > 0.10 and P.good or premium < -0.10 and P.bad or P.textDim, R.fonts.tiny)
      end
    elseif n.kind == "source" then
      Draw.mark(n.commodity, x, y - 1, math.max(8, 12 * cam.scale))
      local level = n.level or 1
      label(string.upper(n.commodity) .. "  " .. n.output, x, y+r+8, color)
      if cam.scale > 0.6 then
        -- Level pips: how far the well has been deepened.
        for i = 1, City.sourceMaxLevel do
          lg.setColor(i <= level and color or P.with(P.textFaint, 0.6))
          lg.circle(i <= level and "fill" or "line", x - 14 + (i - 1) * 5.6, y - r - 8, 1.9)
        end
      end
      if n.seam then label("SEAM", x, y-r-24, P.energy, R.fonts.tiny) end
    else
      lg.setColor(color)
      Draw.structureGlyph(n.kind, x, y)
      if n.kind == "gate" then
        label(tostring(n.throughput or 0), x, y+r+6, (n.throughput or 0) == 0 and P.bad or P.warn)
      elseif n.kind == "terminal" then
        if n.commodity then
          Draw.mark(n.commodity, x + r * 0.8, y - r * 0.8, math.max(5, 7 * cam.scale))
        end
        label((City.HAVENS[n.haven or "port"] or {}).name or "TERMINAL", x, y+r+6, color)
        if cam.scale > 0.6 then
          label("lands "..(n.output or 0), x, y-r-21, P.textDim, R.fonts.tiny)
        end
      elseif n.kind == "depot" then
        if n.commodity then
          Draw.mark(n.commodity, x + r * 0.8, y - r * 0.8, math.max(5, 7 * cam.scale))
        end
        label((n.stored or 0) .. "/" .. (n.capacityStore or City.depotCapacity), x, y+r+6,
          (n.stored or 0) > 0 and P.good or P.textDim)
      end
      for i=1,n.ports do
        local a = i/n.ports*math.pi*2
        lg.setColor(i<=city.g:degree(n.id) and color or P.textFaint)
        lg.circle("fill",x+math.cos(a)*(r+4),y+math.sin(a)*(r+4),1.7)
      end
    end
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
        label("$"..q.total,(x+mx)/2,(y+my)/2-40,state.rail and P.accent or P.energy)
        label(string.format("%dm  %s $%d  %s $%d  bore $%d",math.floor(q.metres),
          state.rail and "yards" or "tie-in",q.tiein,
          state.rail and "track" or "trench",q.trench,q.bore),
          (x+mx)/2,(y+my)/2-22,P.textDim,R.fonts.tiny)
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
