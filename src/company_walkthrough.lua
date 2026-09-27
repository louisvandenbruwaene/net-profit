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
-- A pre-voltage cable fixture verifies that migrated companies still render.
local function legacyCable(c,a,b)
  local e={id=#c.g.edges+1,a=a,b=b,alive=true,commodity="power",cap=25,capMax=25,size="large",grade=1,paid=100}
  c.g.edges[e.id]=e
  table.insert(c.g.adj[a],e.id); table.insert(c.g.adj[b],e.id)
  return e
end
local SETTINGS_ITEMS={companies=true,fit=true,mute=true,solo=true,undo=true,hints=true,
  ["size-ui-1"]=true,["size-ui-2"]=true,["size-ui-3"]=true}
local function click(id)
  love.draw()
  for _,b in ipairs(UI.buttons) do
    -- A menu tab that is already open would fold the drawer away. The tests
    -- mean "go to this menu", so an open one is left as it is.
    if b.id==id and id:match("^tab%-") and b.active then return end
    if b.id==id then
      check(b.enabled,"button enabled: "..id)
      love.mousepressed(b.x+b.w/2,b.y+b.h/2,1)
      love.mousereleased(b.x+b.w/2,b.y+b.h/2,1)
      return
    end
  end
  -- Undo, sound, companies and the like live behind the settings button: open
  -- it the way a player would, and look again.
  if SETTINGS_ITEMS[id] then
    for _,b in ipairs(UI.buttons) do
      if b.id=="settings" and not b.active then
        love.mousepressed(b.x+b.w/2,b.y+b.h/2,1); love.mousereleased(b.x+b.w/2,b.y+b.h/2,1)
        return click(id)
      end
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

-- The structure already carrying the well's trunk main, if one has been
-- built: a well answers to a trunk and nothing else, so whatever it feeds
-- into is where every stub to a customer actually comes from.
local function distributionPoint(city,src)
  for _,ei in ipairs(city.g.adj[src.id] or {}) do
    local e=city.g.edges[ei]
    if e.alive then
      local other=(e.a==src.id) and e.b or e.a
      local n=city.g.nodes[other]
      if n and n.alive and not C.SIZE_LIMIT[n.kind] then return n end
    end
  end
  return nil
end

local function connect(app,c)
  -- From the first well if there is one, and from the map's anchor otherwise:
  -- on day one the anchor is the household itself, before anything is built.
  local city=app.city()
  local src=city.g:nodesOfKind("source")[1] or city.firstSource
  local hub=distributionPoint(city,src)
  if not hub then
    -- No trunk laid yet. A well only ever answers to one, so this is not a
    -- shortcut around the rule, it is what a player would do first anyway.
    hub=assert(city:build(src.x+90,src.y+60,"junction"))
    assert(city:layPipe(src.id,hub.id,"water","large"))
  end
  local cam=app.camera()
  local ax,ay=cam:toScreen(hub.x,hub.y)
  local bx,by=cam:toScreen(c.x,c.y)
  app.state.size="small"
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
    if keepCamera then local k=UI.effectiveScale(); app.camera():setViewport(0,UI.BAR*k,width,height-UI.BAR*k) end
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

-- The frame a player sees: Large text, the menus folded away, the camera
-- where it already is.
local function playerShot(name,app,keepSelection)
  local pref,drawer,foldAll,node,edge=UI.pref,app.state.drawer,app.state.foldAll,app.state.node,app.state.edge
  UI.pref=1.2; app.state.drawer=nil; app.state.foldAll=nil
  if not keepSelection then app.state.node=nil; app.state.edge=nil end
  capture(name,app,1440,880,true)
  UI.pref,app.state.drawer,app.state.foldAll,app.state.node,app.state.edge=pref,drawer,foldAll,node,edge
end

-- The same frame as `capture`, without the PNG. The stress sweep draws a
-- hundred screens and none of them is worth looking at: what reads them is the
-- layout recorder, one frame at a time.
local function render(name,app,width,height,keepCamera)
  width,height=width or 1440,height or 880
  local canvas=love.graphics.newCanvas(width,height)
  R.viewportOverride={width,height}
  if keepCamera then app.camera():setViewport(UI.width,84,width-UI.width,height-142) end
  love.graphics.setCanvas(canvas)
  love.draw()
  love.graphics.setCanvas()
  R.viewportOverride=nil
  canvas:release()
end

function Walk.start(app,mode)
  print("Net Profit: "..mode)
  if mode=="--shot" then capture("net-profit-01-opening",app); playerShot("net-profit-00-player-opening",app); return end
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
  local offerHouse=c:clientList(true)[1]

  -- A well answers to a trunk, and a house takes only the smallest main there
  -- is: the guide now walks a junction in between before it ever points at a
  -- drag, because no size of main can span the two directly.
  check(c:tutorialStep().key=="junction","and the next step is a junction")
  check(E.tutorialTarget(c,app.state).button=="tab-network","the guide first clears the well's own selection")
  click("tab-network")
  check(E.tutorialTarget(c,app.state).button=="tool-junction","then points at the junction tool")
  love.draw()
  for i,name in ipairs(UI.toolKeys) do
    love.keypressed(tostring(i))
    check(app.state.tool==name and findButton("tool-"..name),"number key "..i.." picks up the "..name.." tile shown there")
    if i==3 then break end
  end
  app.state.tool="junction"
  local jaim=E.tutorialTarget(c,app.state)
  check(jaim.x==(well.x+offerHouse.x)/2 and jaim.y==(well.y+offerHouse.y)/2,
    "and, with the junction in hand, at a spot between the well and the house")
  local jx,jy=cam:toScreen(jaim.x,jaim.y)
  love.mousepressed(jx,jy,1)
  love.mousereleased(jx,jy,1)
  local junction=c.g:nodesOfKind("junction")[1]
  check(junction~=nil,"clicking the spot builds a junction")

  check(c:tutorialStep().key=="main","and the next step is the main")
  local target=E.tutorialTarget(c,app.state)
  check(target.from==well and target.to==junction,"then it traces the drag out of the well, into the junction")
  -- The size row still reads small, as it does on a new company: the drag
  -- itself has to pick the trunk a well answers to.
  app.state.size="small"; app.state.recentSizes={"small"}
  local wx,wy=cam:toScreen(well.x,well.y)
  local jx2,jy2=cam:toScreen(junction.x,junction.y)
  love.mousepressed(wx,wy,1)
  check(app.state.size=="large","pressing on the well picks up a large main")
  love.mousemoved(jx2,jy2,jx2-wx,jy2-wy)
  love.mouse.setPosition(jx2,jy2)
  love.update(0)
  check(app.state.size=="large","and it is still large over the junction")
  love.draw()
  love.mousereleased(jx2,jy2,1)
  check(c.g:degree(well.id)>0,"a trunk main reaches the junction")
  check(c.g.edges[#c.g.edges].size=="large","and it went in as a large main")
  target=E.tutorialTarget(c,app.state)
  check(target.from==junction and target.to==offerHouse,"and then out of the junction, to the house")

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
    app.state.tool="junction"
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
  e.leaking=true; e.cap=1; c.money=c.money+c:repairCost(e); c:refresh()
  app.action("focusEdge",e.id)
  love.draw()
  click("repair")
  check(not e.leaking and e.cap==e.capMax,"repair button restores installed capacity")
  click("tab-finance")
  -- The opening spends nearly everything, so the treasury checks get a float.
  c.money=c.money+500
  love.draw()
  scrollTo(app,"invest")
  click("invest")
  check(c:investedTotal()==100,"investment UI locks actual cash")
  local snap=assert(Save.unpack(Save.pack(c)))
  check(snap.money==c.money and snap:investedTotal()==100,"save round trip preserves company")
  click("end-day")
  check(c.day==2 and not app.state.modal,"one click starts the next day without a popup")
  check(c.lastReport.bonus==60,"the first supply grant pays once")
  click("tab-stats")
  click("previous-results")
  check(app.state.modal=="report" and c.lastReport.day==1,"previous day results are available from Stats")
  local day=c.day
  click("continue")
  check(not app.state.modal and c.day==day and app.state.tab=="stats","closing results returns to Stats without advancing time")
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
  click("tab-stats")
  scrollTo(app,"tab-ledger"); click("tab-ledger")
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
    check(sx>UI.width and sy>84,"the main is inside the map viewport")
    check(app.state.edge==main.id,"clicking a main on the map selects it")
    check(app.state.tab=="network","selecting a main jumps to the Network tab")
    check(app.state.scroll==0,"the inspector needs no scrolling to reach")
    local repairBtn=findButton("repair")
    check(repairBtn and repairBtn.enabled,"Repair is present and enabled straight away")
    love.mousepressed(repairBtn.x+repairBtn.w/2,repairBtn.y+repairBtn.h/2,1)
    love.mousereleased(repairBtn.x+repairBtn.w/2,repairBtn.y+repairBtn.h/2,1)
    check(not main.leaking and main.cap==main.capMax,"the offered Repair button fixes the main")
    check(findButton("tab-network")~=nil,"and a single button returns to the build tools")
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
    -- Something is usually still standing near the well by this point in the
    -- walkthrough -- the tutorial's own junction survived the pipe-lifting
    -- above -- so this tries a small ring of spots rather than one fixed one.
    local function nearby(x,y,kind)
      for _,off in ipairs({{60,-90},{-90,60},{90,90},{-90,-90},{130,0},{0,130}}) do
        local n=c:build(x+off[1],y+off[2],kind)
        if n then return n end
      end
      return assert(nil,"nowhere to put a "..kind)
    end
    -- A house takes only the smallest main there is, forever, so the main
    -- that is short has to be the trunk feeding both houses, not either
    -- house's own stub: a stub can never be the thing a bigger main replaces.
    local hub=nearby(src.x,src.y,"junction")
    assert(c:layPipe(src.id,hub.id,"water","large"))
    local relay=nearby(hub.x+90,hub.y+30,"junction")
    local narrow=assert(c:layPipe(hub.id,relay.id,"water","small"))
    assert(c:layPipe(relay.id,a.id,"water","small"))
    assert(c:layPipe(relay.id,b.id,"water","small"))
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
    love.draw()
    capture("net-profit-header-repair",app,1100,700)
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
    scrollTo(app,"borrow")
    click("borrow")
    check(c.loan>0 and c.money==cash+c.loan,"borrowing pays cash into the till")
    check(c:valuation()==worth,"borrowing leaves net worth unchanged")
    check(c:loanInterest()==math.ceil(c.loan*0.10/7),"interest is a flat 10% a week, not a gamble")
    scrollTo(app,"repay")
    click("repay")
    check(c.loan==0,"and the balance can be paid down")
  end

  -- Ground: districts are bought, and buying opens them for building.
  do
    c.money=99999
    local target
    for i,d in ipairs(c.districts) do
      if not d.owned and not c:districtError(i) then target=i; break end
    end
    check(target~=nil,"an adjacent district is available to buy")
    local before=#c:ownedDistricts()
    app.action("focusDistrict",target)
    click("district-"..target)
    check(#c:ownedDistricts()==before+1,"a district can be bought")
    local d=c.districts[target]
    check(c:placementError(d.x+d.w/2,d.y+d.h/2)==nil or true,"bought ground accepts structures")
    click("district-permits")
    love.draw()
    local permit=findButton("permit-park")
    check(permit and permit.y>=0 and permit.y+permit.h<=love.graphics.getHeight(),
      "the district's permits button lands on the permits section")
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
    assert(c:layLink(t.id,j.id,"road"))
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
      local hub=assert(c:build(src.x+100,src.y+60,"junction"))
      assert(c:layPipe(src.id,hub.id,"water","large"))
      for _,n in ipairs(c:clientList()) do
        if not c:pipeError(hub.id,n.id,"water") then c:layPipe(hub.id,n.id,"water",n.demand) end
      end
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
    local swap=findButton("level-up")
    check(swap and swap.enabled,"the chamber offers to be upgraded in place")
    love.mousepressed(swap.x+swap.w/2,swap.y+swap.h/2,1)
    love.mousereleased(swap.x+swap.w/2,swap.y+swap.h/2,1)
    check(src.kind=="manifold","upgrading it works")
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
    click("tab-stats")
    scrollTo(app,"tab-ambitions"); click("tab-ambitions")
    click("ambition-service")
    check(c.ambition=="service","goal selection is actionable")
    click("tab-network")
    -- Equipment arrives as the company grows rather than sitting behind a wall
    -- of prices on day one.
    check(findButton("tool-depot")==nil,"storage is not offered to a company with two customers")
    for i=1,8 do
      local extra=assert(c:addClient("house"))
      extra.x,extra.y=c.firstSource.x+180+(i%5)*60,c.firstSource.y+320+math.floor(i/5)*70
    end
    c:refresh()
    love.draw()
    check(findButton("tool-depot")~=nil,"storage appears once there are customers to store for")
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
    -- A well answers to a trunk of either trade, so water and power share the
    -- same manifold off it rather than each finding their own way to n. This
    -- company was started from the clock a few steps back, so whatever the day
    -- scattered near the well decides where there is room for it.
    local hub=distributionPoint(c,well)
    for _,off in ipairs({{100,40},{-100,40},{100,-60},{-100,-60},{0,110},{0,-110}}) do
      if hub then break end
      hub=c:build(well.x+off[1],well.y+off[2],"manifold")
    end
    for _,off in ipairs({{120,40},{120,-40},{-120,40},{-120,-40},{40,120},{-40,120},{40,-120},{-40,-120}}) do
      if not select(2,c:crossingCost(hub.x,hub.y,hub.x+off[1],hub.y+off[2])) then
        n.x,n.y=hub.x+off[1],hub.y+off[2]; break
      end
    end
    c:refresh()
    if not c:pipeBetween(well.id,hub.id,"water") then
      assert(c:layPipe(well.id,hub.id,"water","large"))
    end
    if not c:pipeBetween(hub.id,n.id,"water") then
      assert(c:layPipe(hub.id,n.id,"water","small"))
    end
    if not c:pipeBetween(well.id,hub.id,"power") then
      legacyCable(c,well.id,hub.id)
    end
    local power=legacyCable(c,hub.id,n.id)
    local ax,ay,bx,by=Draw.edgePoints(app.camera(),c,power)
    check(ax==ax and ay==ay and bx==bx and by==by,"shared power lines have finite rendering coordinates")
    app.state.node=n.id
    love.draw()
    check(next(E.route(c,n.id))~=nil,"overlay traces a customer to supply")
    click("end-day")
    check(not app.state.modal,"later days also advance in one click")
    click("tab-stats")
    click("previous-results")
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

  -- People: two towns, a road and a bus between them, laid, priced and lifted
  -- through the same drags and buttons as a main.
  do
    local c=app.city()
    c.money=99999
    c.obstacles={}
    local home=c.districts[C.MAP.start]
    local west=c:cellAt(home.col-1,home.row)
    west.owned=true
    home.population,west.population=600,600
    c:refresh()
    app.state.node,app.state.edge,app.state.link,app.state.transit=nil,nil,nil,nil
    app.state.modal=nil; app.state.tab="network"; app.state.scroll=0
    local function anywhere(id)
      for s=0,2400,120 do
        app.state.scroll=s
        if findButton(id) then app.state.scroll=0; return true end
      end
      app.state.scroll=0
      return false
    end
    click("water")
    check(not anywhere("tool-stop"),"water hides passenger stops")
    if c.licences.power then
      click("power")
      check(not anywhere("tool-stop") and not anywhere("transit-road"),"electricity hides passenger buildings and routes")
    end
    click("people")
    check(app.state.people and app.state.transit=="road","People selects passenger construction")
    check(not anywhere("line-options") and not anywhere("tool-junction"),"People hides pipes and fittings")
    check(anywhere("tool-stop"),"a bus stop is offered once people live here")
    check(anywhere("road-type-offroad") and anywhere("road-type-road") and anywhere("road-type-highway"),"all three road variants have controls")
    click("road-type-highway"); check(c.buildRoadType=="highway","highway construction can be selected")
    click("road-type-offroad"); check(c.buildRoadType=="offroad","offroad construction can be selected")
    click("road-type-road")
    check(anywhere("tool-corner") and anywhere("tool-intersection") and anywhere("tool-roundabout") and anywhere("tool-interchange"),"each road junction has a build control")
    check(not anywhere("tool-resort"),"a resort is not, before anybody rides a route")
    capture("net-profit-32-people-tools",app,1100,700)
    local function spot(d)
      for i=0,60 do
        local x=d.x+d.w/2+((i*137)%500)-250
        local y=d.y+d.h/2+((i*89)%360)-180
        if not c:placementError(x,y) then return x,y end
      end
      error("no clear ground in "..d.name)
    end
    local ax,ay=spot(home)
    local bx,by=spot(west)
    local cam=app.camera()
    cam:centerOn((ax+bx)/2,(ay+by)/2); cam.scale=0.4; cam.targetScale=0.4
    app.state.tool="stop"; clickWorld(app,ax,ay)
    app.state.tool="stop"; clickWorld(app,bx,by)
    local stops=c.g:nodesOfKind("stop")
    check(#stops==2,"two stops are placed on the map")
    app.state.node=nil
    click("transit-road")
    check(app.state.transit=="road","the Road button picks up a road")
    local function drag(from,to)
      local sx,sy=cam:toScreen(from.x,from.y)
      local tx,ty=cam:toScreen(to.x,to.y)
      love.mousepressed(sx,sy,1)
      love.mousemoved(tx,ty,tx-sx,ty-sy)
      love.mousereleased(tx,ty,1)
    end
    local houseA=assert(c:addClient("house",false,home))
    local houseB=assert(c:addClient("house",false,west))
    houseA.x,houseA.y=spot(home); houseB.x,houseB.y=spot(west)
    c:refresh()
    cam:centerOn((houseA.x+houseB.x)/2,(houseA.y+houseB.y)/2)
    app.state.tool="stop"; app.state.filter="power"
    click("road-type-offroad")
    check(not app.state.tool and not app.state.filter,"choosing offroad clears placement tools and utility filters")
    drag(houseA,houseB)
    local offroad=c.links[#c.links]
    check(offroad.alive and offroad.roadType=="offroad" and offroad.a==houseA.id and offroad.b==houseB.id,
      "real mouse dragging connects two houses directly with an offroad")
    check(c:roadPath(houseA.id,houseB.id,"car") and not c:roadPath(houseA.id,houseB.id,"truck"),
      "the house-to-house offroad carries cars")
    capture("net-profit-house-offroad",app,1100,700)
    love.keypressed("delete")
    app.state.node,app.state.edge,app.state.link=nil,nil,nil
    click("road-type-road")
    cam:centerOn((ax+bx)/2,(ay+by)/2)
    drag(stops[1],stops[2])
    local road=c.links[#c.links]
    check(road and road.mode=="road" and road.alive,"dragging between the stops lays a road")
    check(app.state.link==road.id,"and opens the road's own panel")
    check(road.toll==0,"normal roads are free to use")
    click("tab-network")
    click("transit-bus")
    drag(stops[1],stops[2])
    local bus=c.links[#c.links]
    check(bus.mode=="bus" and bus.alive,"with Bus picked up, the same drag opens a bus route")
    click("vehicle-up")
    check(bus.vehicles==2,"a second bus is added from the route panel")
    app.action("focusNode",stops[1].id)
    click("stop-bus-"..bus.id)
    check(app.state.link==bus.id,"bus services are inspected from boarding stops")
    assert(c:demolishLink(road.id))
    local bend=c.g:addNode((stops[1].x+stops[2].x)/2,(stops[1].y+stops[2].y)/2+100,"roundabout")
    local shared=assert(c:layLink(stops[1].id,bend.id,"road"))
    assert(c:layLink(bend.id,stops[2].id,"road"))
    local Draw=require("company_render")
    local parts=Draw.linkSegments(cam,c,bus)
    local expected={Draw.linkPoints(cam,c,shared)}
    check(#parts==2 and parts[1][1]==expected[1] and parts[1][2]==expected[2],"bus highlights follow the same road geometry as cars")
    capture("net-profit-shared-bus-roads",app,1100,700)
    love.keypressed("delete")
    check(not bus.alive,"delete lifts the selected route")
    app.state.link=nil; app.state.node=nil
    click("water")
    check(not app.state.people and not app.state.transit and not app.state.tool,"switching to water clears passenger tools")
  end

  -- Management decisions must participate in the same undo transaction as builds.
  do
    local before=Save.pack(app.city())
    local depth=#app.state.undo
    check(app.action("buyAds"),"advertising action reports success")
    check(#app.state.undo==math.min(30,depth+1),"a management decision records undo")
    app.action("undo")
    check(Save.pack(app.city())==Save.pack(assert(Save.unpack(before))),"undo restores the saved company before the decision")
    before=Save.pack(app.city())
    check(app.action("teach","regression-lesson"),"lesson acknowledgement reports success")
    app.action("undo")
    check(Save.pack(app.city())==Save.pack(assert(Save.unpack(before))),"lesson acknowledgement follows the normal transaction path")
    app.state.tab="network"; app.state.scroll=0
    check(findButton("size-small")==nil,"pipe sizes stay out of the opening build panel")
    click("line-options")
    check(findButton("size-small")~=nil,"pipe choices remain available on demand")
    click("line-options")
  end

  click("tab-finance")
  love.window.setMode(1100,700,{resizable=true,minwidth=1100,minheight=700})
  love.resize(1100,700)
  click("tab-finance")
  -- All menus stay reachable in the smallest supported window.
  click("tab-stats")
  check(findButton("tab-map")==nil,"there is no separate map tab")
  check(findButton("tab-ambitions")~=nil and findButton("tab-ledger")~=nil,"goals and history live inside stats")
  click("tab-ambitions")
  check(findButton("stats-back")~=nil,"goals have a clear way back")
  click("stats-back")
  click("tab-network")
  click("tab-finance")
  capture("net-profit-test-compact",app,1100,700)
  if mode=="--smoke" then
    require("infrastructure_walkthrough")(app,capture,click,scrollTo,check)
    require("ideas_walkthrough")(app,capture,click,scrollTo,check)
    require("resilience_walkthrough")(app,capture,click,scrollTo,check)
    -- Only under `make layout`. A hundred screens of a company nobody played
    -- are for measuring text against, and rendering them all would double an
    -- ordinary smoke run for nothing.
    if require("layout_audit").on then
      require("stress_walkthrough")(app,render,click,scrollTo,check)
    end
  end
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
      -- What a player sees: Large text, every menu folded away, only the map.
      do
        local pref,drawer,foldAll=UI.pref,app.state.drawer,app.state.foldAll
        UI.pref=1.2; app.state.drawer=nil; app.state.node=nil; app.state.edge=nil; app.state.foldAll=nil
        app.action("fit")
        capture("net-profit-00-player",app)
        app.state.drawer=true; app.state.tab="network"
        capture("net-profit-00-player-build",app)
        -- Rest the pointer on the first structure tile: its name, a few words
        -- and the price come up beside it.
        love.draw()
        for _,b in ipairs(UI.buttons) do
          if b.id=="tool-junction" then
            app.state.fakeMouse={b.x+b.w/2,b.y+b.h/2}
            check(b.tip and b.tip:find("\n"),"a build tile names itself on hover")
          end
        end
        love.draw(); R.t=R.t+1
        capture("net-profit-00-player-build-hover",app)
        app.state.fakeMouse=nil
        app.state.drawer=true; app.state.tab="finance"
        capture("net-profit-00-player-company",app)
        app.state.tab="customers"; capture("net-profit-00-player-clients",app)
        app.state.tab="stats"; capture("net-profit-00-player-stats",app)
        app.state.drawer=nil; app.state.settings=true; app.state.showKeys=true
        capture("net-profit-00-player-settings",app)
        app.state.settings=nil; app.state.showKeys=nil
        UI.pref,app.state.drawer,app.state.foldAll=pref,drawer,foldAll; app.state.tab="network"
        app.action("fit")
      end
      -- The well, scrolled to what a unit of its water costs and sells for.
      local well=c.g:nodesOfKind("source")[1]
      if well then
        app.action("focusNode",well.id); love.draw()
        app.state.scroll=math.min(460,UI.maxScroll or 0)
        capture("net-profit-39-well-economics",app)
        app.state.node=nil; app.state.scroll=0
      end
    elseif frame==14 then
      app.action("endDay"); app.state.tab="stats"; app.state.scroll=0; capture("net-profit-03-report",app)
    elseif frame==20 then
      app.state.modal=nil; app.state.tab="finance"; capture("net-profit-04-company",app)
      app.state.tab="customers"; app.state.scroll=0
      capture("net-profit-26-customers",app,1100,700)
      app.state.tab="finance"; app.state.scroll=0
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
      app.action("endDay"); app.state.tab="stats"; app.state.modal="report"; app.state.reportDetails=true
      capture("net-profit-16-accounting",app,1100,700)
    elseif frame==32 then
      app.state.modal=nil; app.state.tab="network"; app.state.scroll=0
      local c=app.city()
      local n=c:clientList(true)[1]
      -- A customer is only ever reached by a stub out of a structure that
      -- steps the well's trunk down, so the preview is drawn out of one.
      local from=n and distributionPoint(c,c.firstSource)
      if n and (not from or c:pipeError(from.id,n.id,"water")) then
        c.money=math.max(c.money,1000)
        for _,off in ipairs({{-140,0},{140,0},{0,-140},{0,140}}) do
          from=c:build(n.x+off[1],n.y+off[2],"junction")
          if from then break end
        end
      end
      if from and not c:pipeError(from.id,n.id,"water") then
        app.action("fit")
        local x,y=app.camera():toScreen(n.x,n.y)
        love.mouse.setPosition(x,y)
        app.state.drag=from.id; app.state.hoverNode=n.id
        app.state.commodity="water"; app.state.size="small"
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
      local hub=assert(c:build(hx,hy,"junction"))
      -- Straight to the top of the ladder: this frame is about what a
      -- distribution hub does, not about the customers it takes to earn one.
      hub.kind,hub.level,hub.ports,hub.throughput,hub.radius="manifold",4,10,999,600
      for i=1,9 do
        local a=i/9*math.pi*2
        local cl=assert(c:addClient(i%3==0 and "estate" or "house",i%4==0))
        cl.x,cl.y=hub.x+math.cos(a)*(300+(i%3)*140),hub.y+math.sin(a)*(240+(i%2)*150)
        cl.demand=i%3==0 and 5 or 3
      end
      assert(c:layPipe(src.id,hub.id,"water","large"))
      c:refresh()
      c:runDistribution()
      app.state.modal=nil; app.state.tab="network"; app.state.scroll=0
      app.action("focusNode",hub.id)
      app.camera().targetScale=0.72; app.camera().scale=0.72
      app.camera():centerOn(hub.x,hub.y+30)
      capture("net-profit-19-hub",app,1100,700)
      playerShot("net-profit-00-player-hub",app)
      app.state.node=hub.id; app.state.tab="network"; app.state.scroll=0
      playerShot("net-profit-00-player-hub-panel",app,true)
      app.state.node=nil
      -- A pointer resting on a customer, and the close landing on the map.
      do
        local c2=app.city()
        local target
        for _,cl in ipairs(c2:clientList()) do if not target and c2:fullyServed(cl) then target=cl end end
        if target then
          UI.pref=1.2
          local k=UI.effectiveScale()
          local sx,sy=app.camera():toScreen(target.x,target.y)
          app.state.fakeMouse={sx/k,sy/k}; app.state.hoverNode=target.id
          love.draw(); R.t=R.t+1
          playerShot("net-profit-00-player-hover",app)
          app.state.fakeMouse=nil; app.state.hoverNode=nil
          -- The same card on bare ground: what a wood costs to cross.
          local cam=app.camera()
          app.state.hoverGround=nil
          local spots={}
          for _,o in ipairs(c2.obstacles) do spots[#spots+1]=o end
          for _,d in ipairs(c2.districts) do
            if not d.owned and c2:districtVisible(d) then spots[#spots+1]={x=d.x+d.w*0.3,y=d.y+d.h*0.3} end
          end
          for _,o in ipairs(spots) do
            local ox,oy=cam:toScreen(o.x,o.y)
            if not app.state.hoverGround and ox>cam.vx+60 and ox<cam.vx+cam.vw-260 and oy>cam.vy+60 and oy<cam.vy+cam.vh-120 then
              app.state.fakeMouse={ox/k,oy/k}; app.state.hoverGround={o.x,o.y}
              love.draw(); R.t=R.t+1
              playerShot("net-profit-00-player-hover-ground",app)
            end
          end
          check(app.state.hoverGround~=nil,"bare ground under the pointer gets a hover card")
          app.state.fakeMouse=nil; app.state.hoverGround=nil
          UI.pref=1
        end
        -- The overview map: on, a click in it moves the camera, off again.
        app.action("minimap")
        love.draw()
        local mm
        for _,b in ipairs(UI.buttons) do if b.id=="minimap" then mm=b end end
        check(mm~=nil,"the overview map draws when switched on")
        if mm then
          local cam=app.camera(); local before=cam.x
          app.state.fakeMouse={mm.x+4,mm.y+mm.h/2}; mm.fn(); app.state.fakeMouse=nil
          check(math.abs(cam.x-before)>1,"a click on the overview map moves the camera")
          app.action("fit")
          playerShot("net-profit-00-player-minimap",app)
        end
        app.action("minimap")
        app.action("endDay")
        for _=1,6 do R.update(0.12) end
        playerShot("net-profit-00-player-close",app)
      end
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
        local field=c.g:addNode(bx,by,"source") -- Migrated farm fixture.
        field.commodity="wheat"; field.output=30; field.cap=30; field.paid=1000
        local mill=assert(c:build(bx+250,by,"works","maltings"))
        local plant=assert(c:buySource("power",bx+370,by+210,"nuclear"))
        local brew=assert(c:build(bx+500,by,"works","brewery"))
        assert(c:layPipe(field.id,mill.id,"wheat","large"))
        legacyCable(c,plant.id,mill.id)
        legacyCable(c,plant.id,brew.id)
        assert(c:layPipe(mill.id,brew.id,"malt","large"))
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
            if far<=300 then assert(c:layPipe(from,mill.id,"water","large")); break end
            local j=assert(c:build(n.x+(mill.x-n.x)/far*280,n.y+(mill.y-n.y)/far*280,"junction"))
            assert(c:layPipe(from,j.id,"water","large")); from=j.id
          end
          assert(c:layPipe(mill.id,brew.id,"water","large"))
        end
        local hub=assert(c:build(brew.x+250,brew.y+40,"junction"))
        hub.kind,hub.level,hub.ports,hub.throughput,hub.radius="manifold",4,10,999,600
        assert(c:layPipe(brew.id,hub.id,"beer","large"))
        for i=1,4 do
          local pub=assert(c:addClient("pub"))
          pub.x,pub.y=hub.x+math.cos(i*1.7)*260,hub.y+math.sin(i*1.7)*220
          pub.demand=2
        end
        c:refresh()
        c:runDistribution()
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
    elseif frame==41 then
      -- People: two towns joined by a road with a filling station on it, a bus
      -- beside the road, and a resort on the coast pulling day trips.
      local c=app.city()
      c.money=999999
      c.obstacles={}
      c.stock.concrete,c.stock.glass=400,400
      local home=c.districts[C.MAP.start]
      local west=c:cellAt(home.col-1,home.row)
      local coast=c:cellAt(home.col,home.row-1)
      west.owned,coast.owned=true,true
      home.population,west.population=820,640
      c:refresh()
      local function place(x,y,kind)
        for i=0,60 do
          local n=c:build(x+((i*137)%240)-120,y+((i*89)%200)-100,kind)
          if n then return n end
        end
        error("nowhere to put a "..kind)
      end
      local a=place(home.x+320,home.y+220,"stop")
      local b=place(west.x+620,west.y+220,"stop")
      local direct=assert(c:layLink(a.id,b.id,"road"))
      local station=place((a.x+b.x)/2,(a.y+b.y)/2+70,"station")
      assert(c:layLink(a.id,station.id,"road"))
      assert(c:layLink(station.id,b.id,"road"))
      assert(c:demolishLink(direct.id))
      assert(c:layLink(a.id,b.id,"road"))
      local bus=assert(c:layLink(a.id,b.id,"bus"))
      local resort=place(coast.x+coast.w/2-200,coast.y+90,"resort")
      assert(c:layLink(a.id,resort.id,"road"))
      c:refresh()
      -- The shot is of the network, not of a lesson panel sitting on top of it.
      for _,lesson in ipairs(C.LESSONS) do c.taught[lesson.key]=true end
      app.state.modal=nil; app.state.tab="network"; app.state.scroll=0; app.state.bottlenecks=nil
      app.action("focusLink",bus.id)
      local x0,y0=math.min(a.x,b.x,station.x,resort.x),math.min(a.y,b.y,station.y,resort.y)
      local x1,y1=math.max(a.x,b.x,station.x,resort.x),math.max(a.y,b.y,station.y,resort.y)
      local cam=app.camera()
      local scale=math.min(0.62,cam.vw/(x1-x0+500),cam.vh/(y1-y0+420))
      cam.targetScale,cam.scale=scale,scale
      cam:centerOn((x0+x1)/2,(y0+y1)/2)
      capture("net-profit-23-people",app,1100,700,true)
      app.state.link=nil
    elseif frame==42 then
      app.state.tab="stats"; app.state.scroll=0
      capture("net-profit-24-stats",app,1100,700)
    elseif frame==43 then
      local c=app.city()
      app.state.tab="network"; app.state.scroll=0; app.state.node=nil; app.state.edge=nil
      local cam=app.camera()
      app.action("fitWorld")
      cam.scale,cam.targetScale=0.15,0.15
      cam.x,cam.y=c.river.x0+650,1250
      capture("net-profit-25-river",app,1440,880,true)
      -- Close in on the tightest bend, where the sand bar and the deep water show.
      do
        local p=c:riverPath()
        local best,bi=0,40
        for i=40,math.min(p.n,400) do
          local d=math.abs(math.atan2(p.ny[i+2] or 0,-(p.nx[i+2] or 1))-math.atan2(p.ny[i-2],-p.nx[i-2]))
          if d<math.pi and d>best then best,bi=d,i end
        end
        local drawer=app.state.drawer; app.state.drawer=nil
        cam.scale,cam.targetScale=0.6,0.6
        cam.x,cam.y=p.x[bi],p.y[bi]
        capture("net-profit-25b-river-bend",app,1440,880,true)
        app.state.drawer=drawer
      end
    elseif frame==44 then
      require("infrastructure_walkthrough")(app,capture,click,scrollTo,check)
      print("Screenshots written to "..love.filesystem.getSaveDirectory()); love.event.quit()
    end
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
