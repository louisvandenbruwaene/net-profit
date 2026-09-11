local UI = require("company_ui")
local Save = require("company_save")
local R = require("render")
local Walk = {checks=0}
local function check(condition,message)
  assert(condition,message)
  Walk.checks=Walk.checks+1
  print("  ok  "..message)
end
local function click(id)
  love.draw()
  for _,b in ipairs(UI.buttons) do
    if b.id==id then
      check(b.enabled,"button enabled: "..id)
      love.mousepressed(b.x+b.w/2,b.y+b.h/2,1)
      love.mousereleased(b.x+b.w/2,b.y+b.h/2,1)
      return
    end
  end
  error("missing visible button: "..id)
end

local function connect(app,c)
  local src=app.city().firstSource
  local cam=app.camera()
  local ax,ay=cam:toScreen(src.x,src.y)
  local bx,by=cam:toScreen(c.x,c.y)
  love.mousepressed(ax,ay,1)
  love.mousemoved(bx,by,bx-ax,by-ay)
  love.mousereleased(bx,by,1)
end

local function capture(name,app,width,height)
    width,height=width or 1440,height or 880
    local canvas=love.graphics.newCanvas(width,height)
    R.viewportOverride={width,height}
    app.action("fit")
    love.graphics.setCanvas(canvas)
    love.draw()
    love.graphics.setCanvas()
    local data=canvas:newImageData()
    local samples={}
    for x=10,data:getWidth()-10,37 do
      for y=10,data:getHeight()-10,31 do
        local r,g,b=data:getPixel(x,y)
        samples[math.floor(r*32)..":"..math.floor(g*32)..":"..math.floor(b*32)]=true
      end
    end
    local count=0
    for _ in pairs(samples) do count=count+1 end
    check(count>15,"render contains varied nonblank pixels: "..name)
    data:encode("png",name..".png")
    R.viewportOverride=nil
    app.action("fit")
    canvas:release()
    data:release()
end

function Walk.start(app,mode)
  print("Net Profit: "..mode)
  if mode=="--shot" then capture("net-profit-01-opening",app); return end
  local c=app.city()
  check(c.money==300,"new company has cash")
  for _,n in ipairs(c:clientList()) do connect(app,n) end
  check(c.unserved==0,"real drags supply both starting customers")
  check(c.money<300 and c.money>100,"route costs deducted")
  love.keypressed("z")
  c=app.city()
  check(c.unserved==1,"undo restores graph and delivery")
  connect(app,c:clientList()[2])
  check(c.unserved==0,"route can be laid after undo")
  local x=app.camera().x
  love.mousepressed(440,210,1)
  love.mousemoved(480,220,40,10)
  love.mousereleased(480,220,1)
  check(app.camera().x~=x,"left drag on empty ground actually pans")
  love.keypressed("f")
  local e=c.g.edges[1]
  e.leaking=true; e.cap=1; c:refresh()
  app.action("focusEdge",e.id)
  love.draw()
  click("repair")
  check(not e.leaking and e.cap==3,"repair button restores installed capacity")
  click("tab-finance")
  click("invest")
  check(c:investedTotal()==100,"investment UI locks actual cash")
  local snap=assert(Save.unpack(Save.pack(c)))
  check(snap.money==c.money and snap:investedTotal()==100,"save round trip preserves company")
  click("end-day")
  check(c.day==2 and app.state.modal=="report","closing day opens financial statement")
  check(c.lastReport.bonus==60,"first-supply milestone pays once")
  local day=c.day
  love.mousepressed(100,250,1)
  check(c.day==day,"report prevents background actions")
  click("continue")
  check(not app.state.modal,"report returns to operations")
  click("tab-customers")
  local offer=c:addClient("house",true)
  check(offer and offer.prospect,"new prospect available")
  app.action("focusNode",offer.id)
  love.draw(); click("accept")
  check(not offer.prospect,"customer accepted from inspector")
  click("tab-ledger")
  love.draw()
  love.window.setMode(1100,700,{resizable=true,minwidth=1100,minheight=700})
  love.resize(1100,700)
  click("tab-finance")
  capture("net-profit-test-compact",app,1100,700)
end

function Walk.update(app,mode,frame)
  if mode=="--shot" then
    if frame==8 then
      for _,c in ipairs(app.city():clientList()) do connect(app,c) end
      app.state.node=nil; app.state.edge=nil
      capture("net-profit-02-supplied",app)
    elseif frame==14 then
      app.action("endDay"); capture("net-profit-03-report",app)
    elseif frame==20 then
      app.state.modal=nil; app.state.tab="finance"; capture("net-profit-04-company",app)
    elseif frame==26 then
      love.window.setMode(1100,700,{resizable=true,minwidth=1100,minheight=700})
      love.resize(1100,700); app.state.tab="network"; app.action("fit")
      capture("net-profit-05-compact",app,1100,700)
    elseif frame==32 then print("screenshots complete"); love.event.quit() end
    return
  end
  if mode=="--soak" and frame<70 then
    local c=app.city()
    app.state.modal=nil
    for _,e in ipairs(c.g.edges) do
      if e.alive and e.leaking and c.money>=c:repairCost(e) then c:repairPipe(e.id) end
    end
    if not c.bankrupt then app.action("endDay") end
    if frame%8==0 then
      check(assert(Save.unpack(Save.pack(c))).day==c.day,"soak save on day "..c.day)
      app.state.modal=nil
      app.state.tab=({"network","finance","customers","ledger"})[frame%4+1]
    end
    return
  end
  if (mode~="--soak" and frame==8) or (mode=="--soak" and frame==72) then
    print("Net Profit: "..Walk.checks.." UI checks passed")
    love.event.quit()
  end
end

return Walk
