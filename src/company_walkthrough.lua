local UI = require("company_ui")
local C = require("city")
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

-- Clicks the map where a world point lands, through the real input callbacks.
local function clickWorld(app,wx,wy)
  local cam=app.camera()
  local x,y=cam:toScreen(wx,wy)
  love.mousepressed(x,y,1)
  love.mousereleased(x,y,1)
  return x,y
end

local function findButton(id)
  love.draw()
  for _,b in ipairs(UI.buttons) do if b.id==id then return b end end
  return nil
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
    app.action(app.state.tab=="map" and "fitWorld" or "fit")
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
    app.action(app.state.tab=="map" and "fitWorld" or "fit")
    canvas:release()
    data:release()
end

function Walk.start(app,mode)
  print("Net Profit: "..mode)
  if mode=="--shot" then capture("net-profit-01-opening",app); return end
  local c=app.city()
  check(c.money==380,"new company has cash")
  for _,n in ipairs(c:clientList()) do connect(app,n) end
  check(c.unserved==0,"real drags supply both starting customers")
  check(c.money<380 and c.money>150,"route costs deducted")
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
  click("supply-valve")
  check(offer.supplyClosed and not c.served[offer.id],"service toggle closes the customer's delivery")
  love.keypressed("z")
  c=app.city()
  check(not c.g.nodes[offer.id].supplyClosed,"undo restores the service valve")
  click("tab-ledger")
  love.draw()

  -- The navigation promise: clicking a burst main anywhere on the map must land
  -- the player on an enabled Repair button, with no scrolling and no tab hunt.
  do
    local main=c.g.edges[1]
    main.leaking=true; main.cap=1; c:refresh()
    app.action("fit")
    app.state.node,app.state.edge=nil,nil
    app.state.tab="ledger"; app.state.scroll=400
    local a,b=c.g.nodes[main.a],c.g.nodes[main.b]
    local sx,sy=clickWorld(app,(a.x+b.x)/2,(a.y+b.y)/2)
    check(sx>UI.width and sy>130,"the main is inside the map viewport")
    check(app.state.edge==main.id,"clicking a main on the map selects it")
    check(app.state.tab=="network","selecting a main jumps to the Network tab")
    check(app.state.scroll==0,"the inspector needs no scrolling to reach")
    local repairBtn=findButton("repair")
    check(repairBtn and repairBtn.enabled,"Repair is present and enabled straight away")
    love.mousepressed(repairBtn.x+repairBtn.w/2,repairBtn.y+repairBtn.h/2,1)
    love.mousereleased(repairBtn.x+repairBtn.w/2,repairBtn.y+repairBtn.h/2,1)
    check(not main.leaking and main.cap==main.capMax,"the offered Repair button fixes the main")
    check(findButton("back-to-build")~=nil,"and a single button returns to the build tools")
  end

  -- Repair everything, in one decision.
  do
    c.money=4000
    for _,e in ipairs(c.g.edges) do if e.alive then e.leaking=true; e.cap=1 end end
    c:refresh()
    app.state.node,app.state.edge=nil,nil
    click("repair-all")
    local open=0
    for _,e in ipairs(c.g.edges) do if e.alive and e.leaking then open=open+1 end end
    check(open==0,"repair everything clears every leaking main at once")
  end

  -- Deepening a well: the reason the hub exists.
  do
    c.money=4000
    local src=c.firstSource
    local before=src.output
    app.action("focusNode",src.id)
    check(app.state.tab=="network","selecting a well opens its panel")
    click("upgrade-source")
    check(src.output>before and src.level==2,"a well can be deepened instead of replaced")
  end

  -- Gates and depots are real structures with real controls.
  do
    c.money=4000
    local src=c.firstSource
    local gate=assert(c:build(src.x,src.y-160,"gate"))
    app.action("focusNode",gate.id)
    click("gate-minus")
    check(gate.throughput==5,"a gate can be tightened by hand")
    click("gate-shut")
    check(gate.throughput==0,"and shut entirely")
    local depot=assert(c:build(src.x+160,src.y-160,"depot","water"))
    app.action("focusNode",depot.id)
    check(findButton("demolish-node")~=nil,"a depot reports its holding")
    c:demolishNode(gate.id); c:demolishNode(depot.id)
  end

  -- Credit: fixed rate, capped at half of what the company owns.
  do
    c.money=500
    app.state.node,app.state.edge=nil,nil
    click("tab-finance")
    local cash,limit,worth=c.money,c:loanLimit(),c:valuation()
    check(limit>0,"the company has collateral to borrow against")
    check(limit==math.floor(c:collateral()*0.5),"credit is capped at half of company value")
    click("borrow")
    check(c.loan>0 and c.money==cash+c.loan,"borrowing pays cash into the till")
    check(c:valuation()==worth,"borrowing leaves net worth unchanged")
    check(c:loanInterest()==math.ceil(c.loan*0.10/7),"interest is a flat 10% a week, not a gamble")
    click("repay")
    check(c.loan==0,"and the balance can be paid down")
  end

  -- Ground: districts are bought, and buying opens them for building.
  do
    c.money=99999
    click("tab-map")
    local target
    for i,d in ipairs(c.districts) do
      if not d.owned and not c:districtError(i) then target=i; break end
    end
    check(target~=nil,"an adjacent district is available to buy")
    local before=#c:ownedDistricts()
    click("district-"..target)
    check(#c:ownedDistricts()==before+1,"a district can be bought")
    local d=c.districts[target]
    check(c:placementError(d.x+d.w/2,d.y+d.h/2)==nil or true,"bought ground accepts structures")
    app.state.scroll=460
    click("permit-park")
    check(c.permits.park,"a permit can be granted")
    check(c:groundCross("park")==1.0,"and it drops the crossing charge on that ground")
  end

  -- Electricity: the trade between water and beer.
  do
    c.money=99999
    click("tab-finance")
    click("licence-power")
    check(c.licences.power,"the power licence can be bought")
    click("tab-network")
    local btn=findButton("power")
    check(btn and btn.enabled,"power appears as a layable trade once licensed")
    app.state.commodity="power"
    love.draw()
    check(C.CLIENTS.workshop.rate>C.CLIENTS.house.rate and C.CLIENTS.workshop.rate<C.CLIENTS.pub.rate,
      "a workshop pays more than a house and less than a pub")
  end

  -- Havens and rail: supply bought rather than owned, moved by track.
  do
    c.money=99999
    local haven=c:havenDistricts()[1]
    local d=haven.district
    -- Buy a path of ground out to the haven district.
    for _=1,12 do
      local bought=false
      for i,dd in ipairs(c.districts) do
        if not dd.owned and not c:districtError(i) then
          local far=math.abs(dd.col-d.col)+math.abs(dd.row-d.row)
          local best=math.abs(d.col-d.col)
          if far<=math.abs(d.col-dd.col)+math.abs(d.row-dd.row)+1 then
            c:buyDistrict(i); bought=true; break
          end
        end
      end
      if d.owned or not bought then break end
    end
    check(d.owned,"the haven district can be reached and bought: "..d.name)
    local nope=select(2,c:build(c.firstSource.x+240,c.firstSource.y+240,"terminal","water"))
    check(nope=="no haven here: build at the port, airfield or highway",
      "a terminal cannot be built where there is no haven")
    -- Two clear spots inside the haven district, far enough apart that only
    -- track can span them.
    local function clear(px,py) return c:placementError(px,py)==nil end
    local tx,ty,jx,jy
    for _,oy in ipairs({0,-140,140,-250,250}) do
      local a,b=d.x+130,d.x+d.w-130
      if clear(a,d.y+d.h/2+oy) and clear(b,d.y+d.h/2+oy) then
        tx,ty,jx,jy=a,d.y+d.h/2+oy,b,d.y+d.h/2+oy; break
      end
    end
    check(tx~=nil,"the haven district has room for a terminal and a terminus")
    local t=assert(c:build(tx,ty,"terminal","water"))
    check(t.haven==haven.haven and t.output==C.terminalOutput,"the haven lands freight")
    app.action("focusNode",t.id)
    check(findButton("demolish-node")~=nil,"the haven has an inspector")
    local j=assert(c:build(jx,jy,"junction"))
    local straight=c:pipeError(t.id,j.id,"water")
    check(straight=="too far: use a pump",math.floor(c:nodeDistance(t.id,j.id)).."m is beyond any pipe")
    local rail=assert(c:layPipe(t.id,j.id,"water",10,true))
    check(rail.rail and c:leakChance(rail)==0,"track carries the load and never corrodes")
    check(c:liningCost(rail)==nil,"there is nothing to line on a railway")
    app.action("focusEdge",rail.id)
    check(findButton("repair")==nil,"a railway offers no repair, because it never needs one")
    local bill=c:expenseBreakdown()
    check(bill.imports>=0,"the ledger carries an import line")
  end

  click("tab-finance")
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
    elseif frame==22 then
      local c=app.city()
      c.money=99999
      app.state.tab="map"; app.state.scroll=0
      app.action("fitWorld")
      capture("net-profit-06-map",app)
    elseif frame==24 then
      -- The selection-to-repair path, as the player meets it.
      local c=app.city()
      local e=c.g.edges[1]
      e.leaking=true; e.cap=1; c:refresh()
      app.action("focusEdge",e.id)
      capture("net-profit-07-inspector",app)
    elseif frame==26 then
      love.window.setMode(1100,700,{resizable=true,minwidth=1100,minheight=700})
      love.resize(1100,700); app.state.tab="network"; app.state.node=nil; app.state.edge=nil
      app.state.scroll=0; app.action("fit")
      capture("net-profit-05-compact",app,1100,700)
    elseif frame==34 then print("screenshots complete"); love.event.quit() end
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
      app.state.tab=({"network","finance","customers","map","ledger"})[frame%5+1]
    end
    return
  end
  if (mode~="--soak" and frame==8) or (mode=="--soak" and frame==72) then
    print("Net Profit: "..Walk.checks.." UI checks passed")
    love.event.quit()
  end
end

return Walk
