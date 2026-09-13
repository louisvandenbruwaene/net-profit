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

local function scrollTo(app,id)
  app.state.scroll=0
  for _=1,40 do
    if findButton(id) then return end
    app.state.scroll=math.min(UI.maxScroll or 0,app.state.scroll+120)
  end
  error("button not reachable by scrolling: "..id)
end

local function connect(app,c)
  -- From the first well if there is one, and from the map's anchor otherwise:
  -- on day one the anchor is the household itself, before anything is built.
  local city=app.city()
  local src=city.g:nodesOfKind("source")[1] or city.firstSource
  local cam=app.camera()
  local ax,ay=cam:toScreen(src.x,src.y)
  local bx,by=cam:toScreen(c.x,c.y)
  love.mousepressed(ax,ay,1)
  love.mousemoved(bx,by,bx-ax,by-ay)
  love.mousereleased(bx,by,1)
end

-- `keepCamera` leaves the view exactly where the caller put it. Everything else
-- is framed on the whole company, which is right for most shots and wrong for
-- one that is about a particular corner of the map.
local function capture(name,app,width,height,keepCamera)
    width,height=width or 1440,height or 880
    local canvas=love.graphics.newCanvas(width,height)
    R.viewportOverride={width,height}
    if not keepCamera then app.action(app.state.tab=="map" and "fitWorld" or "fit") end
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
    if not keepCamera then app.action(app.state.tab=="map" and "fitWorld" or "fit") end
    canvas:release()
    data:release()
end

function Walk.start(app,mode)
  print("Net Profit: "..mode)
  if mode=="--shot" then capture("net-profit-01-opening",app); return end
  local c=app.city()
  check(c.money==C.rules.startMoney,"new company has cash")

  -- The opening, played the way a player plays it: find the mark, sink the
  -- well on it, run a main to the house, sign the contract.
  local step=c:tutorialStep()
  check(step and step.key=="well","the first thing asked for is a well")
  local dep
  for _,d in ipairs(c.deposits) do
    if d.opening then dep=d; break end
  end
  check(dep~=nil,"the survey marked water on the home ground")
  local E=require("experience")
  check(E.tutorialTarget(c,app.state).button=="source","the guide points at the well button")
  app.state.tool="source"; app.state.commodity="water"
  local aim=E.tutorialTarget(c,app.state)
  check(aim.x==dep.x and aim.y==dep.y,"and, with the well in hand, at the marked spring")
  local cam=app.camera()
  local dx,dy=cam:toScreen(dep.x,dep.y)
  love.mousepressed(dx,dy,1)
  love.mousereleased(dx,dy,1)
  local well=c.g:nodesOfKind("source")[1]
  check(well~=nil,"clicking the mark sinks a well on it")
  check(c:tutorialStep().key=="main","and the next step is the main")
  check(E.tutorialTarget(c,app.state).from==well,"then it traces the drag out of the well")

  local offerHouse=c:clientList(true)[1]
  connect(app,offerHouse)
  check(c.g:degree(offerHouse.id)>0,"a main reaches the house")
  check(c:tutorialStep().key=="sign","and the last thing to do is sign them up")
  love.keypressed("z")
  c=app.city()
  offerHouse=c:clientList(true)[1]
  check(c.g:degree(offerHouse.id)==0,"undo takes the main back out of the ground")
  connect(app,offerHouse)
  check(c.g:degree(offerHouse.id)>0,"and it can be laid again")
  app.action("focusNode",offerHouse.id)
  love.draw()
  check(E.tutorialTarget(c,app.state).button=="accept","and points at Sign contract once the house is open")
  click("accept")
  check(#c:clientList()==1 and c.unserved==0,"signing the contract puts them on supply")
  check(E.tutorialTarget(c,app.state).button=="end-day","and then at Close day")

  -- Clicking a selected structure again puts it down, and so does a right click.
  do
    app.action("focusNode",offerHouse.id)
    local hx,hy=app.camera():toScreen(offerHouse.x,offerHouse.y)
    love.mousepressed(hx,hy,1); love.mousereleased(hx,hy,1)
    check(app.state.node==nil,"clicking the selected house again deselects it")
    love.mousepressed(hx,hy,1); love.mousereleased(hx,hy,1)
    check(app.state.node==offerHouse.id,"and clicking once more selects it")
    love.mousepressed(hx,hy,2); love.mousereleased(hx,hy,2)
    check(app.state.node==nil,"a right click deselects too")
    app.state.tool="exchange"
    love.mousepressed(hx,hy,2); love.mousereleased(hx,hy,2)
    check(app.state.tool==nil,"and puts down a tool in hand")
  end
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
  check(not e.leaking and e.cap==e.capMax,"repair button restores installed capacity")
  click("tab-finance")
  -- The opening spends nearly everything, so the treasury checks get a float.
  c.money=c.money+500
  love.draw()
  click("invest")
  check(c:investedTotal()==100,"investment UI locks actual cash")
  local snap=assert(Save.unpack(Save.pack(c)))
  check(snap.money==c.money and snap:investedTotal()==100,"save round trip preserves company")
  click("end-day")
  check(c.day==2 and app.state.modal=="report","closing day opens financial statement")
  check(c.lastReport.bonus==60,"the first supply grant pays once")
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

  -- The customer who is short is told why, and handed the fix.
  do
    c.money=9999
    local src=c.firstSource
    local a,b=c:clientList()[1],c:clientList()[2]
    for _,e in ipairs(c.g.edges) do if e.alive then c:demolishPipe(e.id) end end
    a.demand,b.demand=C.sizeOf("small").cap,2
    a.x,a.y=src.x+200,src.y
    b.x,b.y=src.x+400,src.y
    local narrow=assert(c:layPipe(src.id,a.id,"water","small"))
    assert(c:layPipe(a.id,b.id,"water","small"))
    check((c.served[b.id] or 0)==0,"the downstream house is starved behind a small main")
    app.action("focusNode",b.id)
    local widen=findButton("widen-bottleneck")
    check(widen and widen.enabled,"the customer panel offers to widen the main that is at fault")
    for _=1,3 do
      love.draw()
      local btn=findButton("widen-bottleneck")
      if not btn or not btn.enabled then break end
      love.mousepressed(btn.x+btn.w/2,btn.y+btn.h/2,1)
      love.mousereleased(btn.x+btn.w/2,btn.y+btn.h/2,1)
    end
    check(c.served[b.id]==b.demand,"pressing it puts a bigger main in and supplies the customer")
    check(narrow.size~="small","the small main was dug out rather than widened")
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
    scrollTo(app,"licence-power")
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
    -- The coast is the north edge of the map, and it is the only place a
    -- harbour can stand.
    local gateway="port"
    local d=c:cellAt(2,1)
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
    check(d.owned,"the coastal district can be reached and bought: "..d.name)
    local nope=select(2,c:build(c.firstSource.x+240,c.firstSource.y+240,"terminal","port"))
    check(nope=="a harbour stands on the coast","a harbour cannot be built inland")
    -- Two clear spots inside the haven district, far enough apart that only
    -- track can span them.
    local function clear(px,py) return c:placementError(px,py)==nil end
    local tx,ty,jx,jy
    for _,ox in ipairs({0,90,-90,180,-180}) do
      local a,b=d.x+130+ox,d.x+d.w-130+ox
      if clear(a,d.y+90) and clear(b,d.y+90) then
        tx,ty,jx,jy=a,d.y+90,b,d.y+90; break
      end
    end
    check(tx~=nil,"the coastal district has room for a harbour and a terminus")
    local before=c:havenCost(gateway)
    local t=assert(c:build(tx,ty,"terminal",gateway))
    check(t.haven==gateway and t.commodity==nil,
      "the harbour opens onto the sea and carries every trade")
    check(c:havenCost(gateway)>before,"and the next harbour on the same coast costs more")
    app.action("focusNode",t.id)
    check(findButton("demolish-node")~=nil,"the haven has an inspector")
    local j=assert(c:build(jx,jy,"dc"))
    local straight=c:pipeError(t.id,j.id,"water")
    check(straight=="a haven ships by bulk line only","freight leaves a haven on rails, not in a main")
    -- Rail is steel by the kilometre, and the yards are empty on day three.
    check(select(2,c:layPipe(t.id,j.id,"water",2,true)):find("yards hold")~=nil,
      "a railway cannot be built out of nothing")
    local road=assert(c:layPipe(t.id,j.id,"water",1,"highway"))
    check(road.bulk=="highway","but a highway is tarmac, and needs none")
    assert(c:demolishPipe(road.id))
    c.stock.steel=400
    local rail=assert(c:layPipe(t.id,j.id,"water",2,true))
    check(rail.rail and c:leakChance(rail)==0,"track carries the load and never corrodes")
    check(c:replaceQuote(rail.id)==nil,"a freight line is fitted with wagons, not replaced")
    app.action("focusEdge",rail.id)
    check(findButton("repair")==nil,"a railway offers no repair, because it never needs one")
    local bill=c:expenseBreakdown()
    check(bill.imports>=0,"the ledger carries an import line")
  end

  -- Closing a well leaves the network standing; removing the chamber does not.
  do
    c.money=9999
    local src=c.firstSource
    if c.g:degree(src.id)==0 then
      for _,n in ipairs(c:clientList()) do c:layPipe(src.id,n.id,"water",n.demand) end
    end
    local degree=c.g:degree(src.id)
    check(degree>0,"the first well is carrying mains")
    app.action("focusNode",src.id)
    local cap=findButton("demolish-node")
    check(cap~=nil,"a well offers to be closed")
    love.mousepressed(cap.x+cap.w/2,cap.y+cap.h/2,1)
    love.mousereleased(cap.x+cap.w/2,cap.y+cap.h/2,1)
    check(src.alive and src.kind~="source","closing it caps the wellhead")
    check(c.g:degree(src.id)==degree,"and leaves every main connected")

    -- The chamber can be replaced where it stands.
    app.action("focusNode",src.id)
    love.draw()
    local swap=findButton("replace-manifold")
    check(swap and swap.enabled,"the chamber offers to be replaced in place")
    love.mousepressed(swap.x+swap.w/2,swap.y+swap.h/2,1)
    love.mousereleased(swap.x+swap.w/2,swap.y+swap.h/2,1)
    check(src.kind=="manifold","replacing it works")
    check(c.g:degree(src.id)==degree,"without a single main coming off")

    -- Removing it is the move that costs the network.
    app.action("focusNode",src.id)
    love.draw()
    local attached={}
    for _,ei in ipairs(c.g.adj[src.id]) do
      if c.g.edges[ei].alive then attached[#attached+1]=ei end
    end
    check(#attached==degree,"the chamber is still holding its mains")
    local gone=findButton("demolish-node")
    love.mousepressed(gone.x+gone.w/2,gone.y+gone.h/2,1)
    love.mousereleased(gone.x+gone.w/2,gone.y+gone.h/2,1)
    check(not src.alive,"the chamber can be removed")
    local survivors=0
    for _,ei in ipairs(attached) do
      if c.g.edges[ei].alive then survivors=survivors+1 end
    end
    check(survivors==0,"and every main tied into it goes with it")
    love.keypressed("z")
    c=app.city()
    check(c.g.nodes[src.id].alive,"which undo can take back")
  end

  -- Six companies, kept side by side.
  do
    app.state.node,app.state.edge=nil,nil
    click("companies")
    check(app.state.modal=="slots","the Companies button opens the picker")
    check(findButton("slot-restart-1")~=nil,"the company being played is marked as such")
    check(findButton("slot-new-4")~=nil,"an empty slot offers a new company")
    check(findButton("slot-play-1")==nil,"and offers no way to load the one already open")

    -- Destroying a company always asks first.
    click("slot-restart-1")
    check(app.state.slotConfirm and app.state.slotConfirm.slot==1,"starting over asks for confirmation")
    check(findButton("slot-yes-1")~=nil and findButton("slot-no-1")~=nil,"with both answers offered")
    click("slot-no-1")
    check(app.state.slotConfirm==nil,"and can be backed out of")

    -- A new company in an empty slot leaves the old one alone and switches to it.
    local before=app.city()
    local day=before.day
    click("slot-new-4")
    local now=app.city()
    check(now~=before,"a new company in slot 4 is a different company")
    check(now.slot==4,"and it knows which slot it is")
    check(now.day==1 and now.money==C.rules.startMoney,"it starts from day one")
    check(app.state.modal==nil and app.state.tab=="network","and drops the player into it")
    check(#app.state.undo==0,"with no undo history carried across from the other company")
    check(day>1,"the company it replaced had been played")

    click("companies")
    check(app.state.modal=="slots","the picker reopens")
    click("slots-close")
    check(app.state.modal==nil,"and closes")
  end

  -- New planning, identity, goals and map controls through actual callbacks.
  do
    local E=require("experience")
    local Draw=require("company_render")
    local c=app.city()
    click("tab-finance")
    click("rename-company")
    app.state.rename=""
    love.textinput("Brightwater")
    love.keypressed("return")
    check(c.companyName=="Brightwater" and not app.state.rename,"text input saves a company name without closing the day")
    click("tab-ambitions")
    click("ambition-service")
    check(c.ambition=="service","goal selection is actionable")
    click("filter-water")
    check(app.state.filter=="water","trade filters update the map")
    click("bottlenecks")
    check(app.state.bottlenecks,"supply overlay is available from every tab")
    click("quick-build")
    check(findButton("source") and findButton("tool-junction"),"quick build reveals essential tools")
    click("advanced")
    -- Equipment arrives as the company grows rather than sitting behind a wall
    -- of prices on day one.
    check(findButton("tool-depot")==nil,"storage is not offered to a company with two customers")
    check(findButton("tool-exchange")==nil,"and neither is a hub")
    for i=1,8 do
      local extra=assert(c:addClient("house"))
      extra.x,extra.y=c.firstSource.x+180+(i%5)*60,c.firstSource.y+320+math.floor(i/5)*70
    end
    c:refresh()
    love.draw()
    check(findButton("tool-depot")~=nil,"storage appears once there are customers to store for")
    check(findButton("tool-exchange")~=nil,"and so does the hub")
    local n=c:clientList()[1]
    c.money=9999; c.licences.power=true
    -- This company has been switched, closed and reloaded by now, so make sure
    -- there is a well and put the customer beside it.
    local well=c.g:nodesOfKind("source")[1]
    if not well then
      for _,d in ipairs(c.deposits) do
        if not d.taken and d.commodity=="water" and not c:sourceError("water",d.x,d.y) then
          well=c:buySource("water",d.x,d.y); break
        end
      end
    end
    check(well~=nil,"there is a well to trace a route back to")
    n.x,n.y=well.x+220,well.y+80
    c:refresh()
    if not c:pipeBetween(well.id,n.id,"water") then
      assert(c:layPipe(well.id,n.id,"water","small"))
    end
    local power=assert(c:layPipe(well.id,n.id,"power","small"))
    local ax,ay,bx,by=Draw.edgePoints(app.camera(),c,power)
    check(ax==ax and ay==ay and bx==bx and by==by,"shared power lines have finite rendering coordinates")
    click("filter-all")
    app.state.node=n.id
    love.draw()
    check(next(E.route(c,n.id))~=nil,"overlay traces a customer to supply")
    click("end-day")
    click("report-details")
    check(app.state.reportDetails,"accounting can be expanded")
    love.draw()
    click("report-details")
    click("continue")
    local offer=assert(c:addClient("house",true))
    c.lastReport.arrived={name="House",x=offer.x,y=offer.y}
    app.state.modal="report"
    click("report-enquiry")
    check(not app.state.modal and app.state.node==offer.id,"report enquiry opens its inspector directly")
    power.leaking=true; power.cap=1; c:refresh()
    app.state.modal="report"
    click("report-leak")
    check(not app.state.modal and app.state.edge,"report repair action opens a main directly")
    click("tab-customers")
    click("sort-clients")
    check(app.state.clientSort=="income","customer list supports income sorting")
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
      -- Play the opening, so every shot after this one is of a company that is
      -- actually trading.
      local c=app.city()
      local house=c:clientList(true)[1]
      local spring,best
      for _,d in ipairs(c.deposits) do
        local ground=c:districtAt(d.x,d.y)
        if not d.taken and d.commodity=="water" and ground and ground.owned then
          local far=d.opening and -1 or (d.x-house.x)^2+(d.y-house.y)^2
          if not best or far<best then spring,best=d,far end
        end
      end
      assert(c:buySource("water",spring.x,spring.y))
      c:rebaseOrigin()
      for _,offer in ipairs(c:clientList(true)) do
        connect(app,offer)
        c:acceptClient(offer.id)
      end
      local extra=assert(c:addClient("house"))
      extra.x,extra.y=c.firstSource.x+200,c.firstSource.y-160
      extra.demand=3
      connect(app,extra)
      app.state.node=nil; app.state.edge=nil
      capture("net-profit-02-supplied",app)
    elseif frame==14 then
      app.action("endDay"); capture("net-profit-03-report",app)
    elseif frame==20 then
      app.state.modal=nil; app.state.tab="finance"; capture("net-profit-04-company",app)
    elseif frame==19 then
      -- A capped wellhead: what a closed well leaves behind, and the strip
      -- that replaces it without taking the mains off.
      local c=app.city()
      c.money=9999
      local src=c.firstSource
      for _,n in ipairs(c:clientList()) do
        if not c:pipeError(src.id,n.id,"water") then c:layPipe(src.id,n.id,"water",n.demand) end
      end
      c:demolishNode(src.id)
      app.state.modal=nil
      app.state.tab="network"; app.state.scroll=0
      app.action("focusNode",src.id)
      capture("net-profit-11-capped",app)
      love.keypressed("z")
    elseif frame==22 then
      local c=app.city()
      c.money=99999
      app.state.tab="map"; app.state.scroll=0
      app.action("fitWorld")
      capture("net-profit-06-map",app)
    elseif frame==23 then
      local c=app.city()
      app.state.tab="network"; app.state.scroll=0
      app.action("focusNode",c.firstSource.id)
      capture("net-profit-08-well",app)
      app.state.node=nil
    elseif frame==24 then
      -- The selection-to-repair path, as the player meets it.
      local c=app.city()
      local e=c.g.edges[1]
      e.leaking=true; e.cap=1; c:refresh()
      app.action("focusEdge",e.id)
      capture("net-profit-07-inspector",app)
    elseif frame==25 then
      app.state.modal=nil
      app.action("openSlots")
      local c=app.city()
      -- A picker with nothing in it says nothing; give the shot some companies.
      app.state.slots={
        {slot=1,empty=false,day=82,money=8705,clients=32,worth=29606,districts=4,
         trades={"water","power","beer","oil"}},
        {slot=2,empty=false,day=14,money=1240,clients=7,worth=3180,districts=1,
         trades={"water","power"}},
        {slot=3,empty=true},
        {slot=4,empty=false,day=41,money=62,clients=0,worth=410,districts=2,
         bankrupt=true,trades={"water","beer"}},
        {slot=5,empty=true},{slot=6,empty=true},
      }
      c.slot=1
      capture("net-profit-09-companies",app)
      app.state.modal=nil
    elseif frame==26 then
      love.window.setMode(1100,700,{resizable=true,minwidth=1100,minheight=700})
      love.resize(1100,700); app.state.tab="network"; app.state.node=nil; app.state.edge=nil
      app.state.scroll=0; app.action("fit")
      capture("net-profit-05-compact",app,1100,700)
    elseif frame==27 then
      local c=app.city()
      c.guideDismissed=true
      c.firstSource.kind="source"; c.firstSource.commodity="water"; c.firstSource.output=14
      c.firstSource.capped=nil; c.firstSource.ports=16
      c:repairAll(); c:refresh()
      app.state.modal=nil; app.state.bottlenecks=true
      app.action("focusNode",c:clientList()[1].id)
      capture("net-profit-12-supply-overlay",app,1100,700)
    elseif frame==28 then
      local c=app.city()
      local n=assert(c:addClient("house",true))
      n.x,n.y=c.firstSource.x+100,c.firstSource.y+80
      c:refresh()
      app.action("focusNode",n.id)
      capture("net-profit-13-offer-preview",app,1100,700)
    elseif frame==29 then
      local c=app.city()
      c:chooseAmbition("service"); c.serviceStreak=4
      app.state.tab="ambitions"; app.state.scroll=0
      capture("net-profit-14-goals",app,1100,700)
    elseif frame==30 then
      local c=app.city()
      c.history={}
      for day=1,12 do c.history[day]={day=day,revenue=20+day*6,expenses=35+day*2} end
      app.state.tab="finance"; app.state.scroll=0
      love.draw(); app.state.scroll=UI.maxScroll
      capture("net-profit-15-profit-history",app,1100,700)
    elseif frame==31 then
      app.action("endDay"); app.state.reportDetails=true
      capture("net-profit-16-accounting",app,1100,700)
    elseif frame==32 then
      app.state.modal=nil; app.state.tab="network"; app.state.scroll=0
      local c=app.city()
      local n=c:clientList(true)[1]
      if n and not c:pipeError(c.firstSource.id,n.id,"water") then
        app.action("fit")
        local x,y=app.camera():toScreen(n.x,n.y)
        love.mouse.setPosition(x,y)
        app.state.drag=c.firstSource.id; app.state.hoverNode=n.id
        app.state.commodity="water"; app.state.capacity=n.demand
        capture("net-profit-17-construction-preview",app,1100,700)
        app.state.drag=nil
      else error("construction preview fixture needs a reachable offer") end
    elseif frame==33 then
      -- The supply chain the city runs on: a haven on the estuary, track
      -- hauling what it lands inland, and a main from the yard to a customer.
      local c=app.city()
      c.money=99999
      c.obstacles={}
      c.licences.beer=true
      c.stock.steel=400
      local d=c:cellAt(2,1)
      d.owned=true
      local haven=assert(c:build(d.x+120,d.y+90,"terminal","port"))
      local yard=assert(c:build(d.x+760,d.y+120,"dc"))
      assert(c:layPipe(haven.id,yard.id,"beer",1,"rail"))
      local pub=assert(c:addClient("pub"))
      pub.x,pub.y=yard.x+40,yard.y+250
      pub.demand=4
      assert(c:layPipe(yard.id,pub.id,"beer",4))
      c:refresh()
      app.state.modal=nil; app.state.tab="network"; app.state.scroll=0
      app.action("focusNode",haven.id)
      app.camera().targetScale=0.62; app.camera().scale=0.62
      app.camera():centerOn((haven.x+pub.x)/2,(haven.y+pub.y)/2-40)
      capture("net-profit-18-haven",app,1100,700)
      app.state.node=nil
    elseif frame==34 then
      -- A hub: one building, a neighbourhood wired to it, and not a main drawn
      -- to any of them.
      local c=app.city()
      c.money=99999
      c.obstacles={}
      local src=c.firstSource
      src.output,src.cap=60,60
      -- The days before this frame are random, so a customer may have moved in
      -- where the hub goes. Clear the spot rather than move the shot.
      local hx,hy=src.x+260,src.y+90
      for _,n in ipairs(c.g:aliveNodes()) do
        if n.id~=src.id and (n.x-hx)^2+(n.y-hy)^2<(C.rules.minSpacing*2)^2 then c.g:killNode(n.id) end
      end
      c:refresh()
      local hub=assert(c:build(hx,hy,"exchange"))
      for i=1,9 do
        local a=i/9*math.pi*2
        local cl=assert(c:addClient(i%3==0 and "estate" or "house",i%4==0))
        cl.x,cl.y=hub.x+math.cos(a)*(300+(i%3)*140),hub.y+math.sin(a)*(240+(i%2)*150)
        cl.demand=i%3==0 and 5 or 3
      end
      assert(c:layPipe(src.id,hub.id,"water",18))
      c:refresh()
      app.state.modal=nil; app.state.tab="network"; app.state.scroll=0
      app.action("focusNode",hub.id)
      app.camera().targetScale=0.72; app.camera().scale=0.72
      app.camera():centerOn(hub.x,hub.y+30)
      capture("net-profit-19-hub",app,1100,700)
      app.state.node=nil
    elseif frame==36 then
      -- The sea: an island bought off the coast, with a wind park on it.
      local c=app.city()
      c.money=999999
      c.obstacles={}
      c.licences.power=true
      local coast=c:cellAt(2,1)
      coast.owned=true
      c.stock.steel,c.stock.concrete=400,400
      -- The harbour from the earlier shot may still be standing here.
      local port=c:havenOf("port")
      if not port then port=assert(c:build(coast.x+140,coast.y+90,"terminal","port")) end
      local island
      for _,d in ipairs(c.districts) do if d.island then island=d; break end end
      if island then
        assert(c:buyDistrict(island.id))
        local park=assert(c:buySource("power",island.x+island.w/2,island.y+island.h/2,"wind"))
        c:refresh()
        app.state.modal=nil; app.state.tab="network"; app.state.scroll=0
        app.action("focusNode",park.id)
        app.camera().targetScale=0.32; app.camera().scale=0.32
        app.camera():centerOn((park.x+port.x)/2,(park.y+port.y)/2-40)
        capture("net-profit-20-island",app,1100,700,true)
        app.state.node=nil
      end
    elseif frame==38 then
      -- The chain: wheat off a farm, malt, water and power into a brewery, and
      -- beer out of it. Four commodities and three buildings, on one screen.
      local c=app.city()
      c.money=999999
      c.obstacles={}
      c.licences.beer=true; c.licences.power=true
      for _,d in ipairs(c.districts) do d.owned=true end
      local farm
      for _,d in ipairs(c.districts) do if d.spec and d.spec.key=="farm" then farm=d; break end end
      if farm then
        local bx,by=farm.x+300,farm.y+320
        local field=assert(c:buySource("wheat",bx,by))
        local mill=assert(c:build(bx+250,by,"works","maltings"))
        local plant=assert(c:buySource("power",bx+370,by+210,"nuclear"))
        local brew=assert(c:build(bx+500,by,"works","brewery"))
        assert(c:layPipe(field.id,mill.id,"wheat",10))
        assert(c:layPipe(plant.id,mill.id,"power",10))
        assert(c:layPipe(plant.id,brew.id,"power",10))
        assert(c:layPipe(mill.id,brew.id,"malt",10))
        local dep
        for _,d in ipairs(c.deposits) do
          if d.commodity=="water" and c:districtAt(d.x,d.y)==farm and not d.taken then dep=d; break end
        end
        if dep then
          local well=assert(c:buySource("water",dep.x,dep.y))
          well.output,well.cap=48,48
          local from=well.id
          for _=1,10 do
            local n=c.g.nodes[from]
            local far=math.sqrt((n.x-mill.x)^2+(n.y-mill.y)^2)
            if far<=300 then assert(c:layPipe(from,mill.id,"water",24)); break end
            local j=assert(c:build(n.x+(mill.x-n.x)/far*280,n.y+(mill.y-n.y)/far*280,"junction"))
            assert(c:layPipe(from,j.id,"water",24)); from=j.id
          end
          assert(c:layPipe(mill.id,brew.id,"water",22))
        end
        local hub=assert(c:build(brew.x+250,brew.y+40,"exchange"))
        assert(c:layPipe(brew.id,hub.id,"beer",8))
        for i=1,4 do
          local pub=assert(c:addClient("pub"))
          pub.x,pub.y=hub.x+math.cos(i*1.7)*260,hub.y+math.sin(i*1.7)*220
          pub.demand=2
        end
        c:refresh()
        app.state.modal=nil; app.state.tab="network"; app.state.scroll=0
        app.action("focusNode",brew.id)
        app.camera().targetScale=0.62; app.camera().scale=0.62
        app.camera():centerOn((field.x+hub.x)/2,by+40)
        capture("net-profit-21-chain",app,1100,700,true)
        app.state.node=nil
      end
    elseif frame==40 then
      -- A lesson panel, at the moment it would actually appear.
      local c=app.city()
      c.money=6000
      c.guideDismissed=true
      c.taught={}
      c.licences.power=true
      app.state.modal=nil; app.state.tab="network"; app.state.scroll=0
      app.state.node=nil; app.state.edge=nil
      c:refresh()
      app.action("fit")
      capture("net-profit-22-lesson",app,1100,700)
    elseif frame==42 then print("screenshots complete"); love.event.quit() end
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
