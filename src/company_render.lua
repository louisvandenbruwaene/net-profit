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

function Draw.world(city, cam, state)
  local _,height = R.dimensions()
  lg.setScissor(cam.vx, 80, cam.vw, height-138)
  R.drawGrid(cam, city.bounds.w, city.bounds.h)
  for _, o in ipairs(city.obstacles) do
    local spec = City.OBSTACLES[o.kind]
    local x, y = cam:toScreen(o.x, o.y)
    local r = o.r * cam.scale
    lg.setColor(P.with(spec.color, 0.16))
    lg.circle("fill", x, y, r)
    lg.setColor(P.with(spec.color, 0.6))
    lg.setLineWidth(1)
    lg.circle("line", x, y, r)
    for d = -r + 4, r - 4, 12 do
      local h = math.sqrt(math.max(0, r*r-d*d))
      lg.setColor(P.with(spec.color, 0.18))
      if o.kind == "river" then lg.line(x-h, y+d, x+h, y+d)
      else lg.line(x+d, y-h, x+d, y+h) end
    end
    if cam.scale > 0.48 then label(spec.name .. (spec.cross and " x"..spec.cross or ""), x, y-6, spec.color, R.fonts.tiny) end
  end

  local selected = city.g.nodes[state.node or 0]
  if selected and selected.alive and selected.kind == "tower" then
    local x,y = cam:toScreen(selected.x,selected.y)
    lg.setColor(P.with(P.energy,0.10)); lg.circle("fill",x,y,220*cam.scale)
    lg.setColor(P.with(P.energy,0.45)); lg.circle("line",x,y,220*cam.scale)
  end
  for _, e in ipairs(city.g.edges) do
    if e.alive then
      local ax, ay, bx, by = Draw.edgePoints(cam,city,e)
      local c = Graph.COMMODITIES[e.commodity].color
      local width = math.min(10,2+e.capMax*0.6)*cam.scale+1
      if state.edge == e.id or state.hoverEdge == e.id then
        lg.setColor(P.with(P.text,0.7)); lg.setLineWidth(width+5); lg.line(ax,ay,bx,by)
      end
      lg.setColor(P.with(e.leaking and P.bad or c,e.cap == 0 and 0.35 or 0.65))
      lg.setLineWidth(width); lg.line(ax,ay,bx,by)
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
    local color = n.commodity and Graph.COMMODITIES[n.commodity].color or Graph.KINDS[n.kind].color
    local served = city.served[n.id] or 0
    if n.kind == "source" then color = P.good end
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
      if n.clientType == "factory" then
        lg.rectangle("line",x-7,y-4,14,11); lg.line(x-7,y-4,x-7,y-10,x-3,y-10,x-3,y-4)
      elseif n.clientType == "pub" then
        lg.rectangle("line",x-6,y-7,10,13); lg.rectangle("line",x+4,y-4,4,7)
      else
        lg.line(x-9,y-1,x,y-9,x+9,y-1); lg.rectangle("line",x-6,y-1,12,9)
      end
      local title = n.prospect and "OFFER" or n.supplyClosed and "SHUT" or string.format("%d/%d",served,n.demand)
      label(title,x,y+r+6,n.prospect and P.energy or (served>=n.demand and P.good or P.warn))
      if cam.scale > 0.72 then label(City.CLIENTS[n.clientType].name.." "..n.id,x,y-r-21,P.textDim,R.fonts.tiny) end
    elseif n.kind == "source" then
      lg.polygon("line",x,y-10,x+7,y+3,x,y+9,x-7,y+3)
      label(string.upper(n.commodity).." "..n.output,x,y+r+8,P.good)
    else
      if n.kind == "pump" then lg.polygon("line",x-5,y-8,x+7,y,x-5,y+8)
      elseif n.kind == "tower" then lg.rectangle("line",x-7,y-8,14,10); lg.line(x-5,y+2,x-7,y+9,x+7,y+9,x+5,y+2)
      else lg.line(x-7,y,x+7,y); lg.line(x,y-7,x,y+7) end
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
    local err = target and city:pipeError(from.id,target,state.commodity)
    lg.setColor(P.with(P.textDim,0.25)); lg.setLineWidth(1)
    lg.circle("line",x,y,city:rangeBetween(from.id,from.id)*cam.scale)
    lg.setColor(err and P.bad or P.good); lg.setLineWidth(2); lg.line(x,y,mx,my)
    if target and target~=from.id then
      label(err or ("$"..city:pipeCost(from.id,target,state.capacity)),(x+mx)/2,(y+my)/2-24,err and P.bad or P.energy)
    end
  elseif state.tool and mx>cam.vx and my>130 and my<height-58 then
    local wx,wy = cam:toWorld(mx,my)
    local err = city:placementError(wx,wy)
    local cost = state.tool=="source" and city:sourceCost(state.commodity) or city:nodeCost(state.tool)
    local color = (err or cost>city.money) and P.bad or P.good
    lg.setColor(P.with(color,0.3)); lg.setLineWidth(1)
    local range = state.tool=="pump" and 520 or state.tool=="tower" and 220 or 300
    lg.circle("line",mx,my,range*cam.scale)
    lg.setColor(color); lg.circle("line",mx,my,18*cam.scale)
    label(err or ("$"..cost),mx,my+30,color)
  end
  lg.setScissor()
end

return Draw
