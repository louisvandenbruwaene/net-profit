-- Imports: ordering goods at a haven, paid now, landed in its store tomorrow.
package.path='test/?.lua;src/?.lua;'..package.path
local T=require('support')
local City=require('city')
local Save=require('company_save')
local function check(v,m) T.check(v,m); print("  ok  "..m) end

local c=T.sandbox(24)
c.stock={}
c.orders={surveyors=1}
local port=c.g:addNode(400,60,"terminal"); port.haven="port"
local road=c.g:addNode(900,60,"terminal"); road.haven="highway"
c:refresh()

print("what is for sale")
local goods=c:importable()
local has={}
for _,k in ipairs(goods) do has[k]=true end
check(has.panels and has.steel and not has.power and not has.water and not has.jewelry,"solid goods with a world price, never power")
check(c:importPrice("steel","highway")>c:importPrice("steel","port"),"a road head charges more freight than a harbour")

print("ordering")
local money=c.money
local cost=c:shipmentCost(port.id,"panels",12)
local o=assert(c:orderImport(port.id,"panels",12))
check(c.money==money-cost and cost==math.ceil(City.trade.panels.importCost*12),"paid up front at the landed price")
check(c:materialStock("panels")==0,"nothing is in store until it lands")
local coming=c:havenShipments(port.id)
check(coming.panels==12,"the haven shows it on the way")
check(c:shipmentError(port.id,"panels",c:storeRoom("panels")+1)=="no room in store: raise the solar panels store","the store's room counts what is already coming")
check(c:shipmentError(port.id,"power",1)=="not for sale abroad","electricity is never imported")

print("landing")
local packed=assert(Save.unpack(Save.pack(c)))
check(#packed.shipments==1,"an order at sea survives a save")
c:endDay()
check(c:materialStock("panels")==12,"the next morning it is in stock")
check(#c.shipments==0,"and off the books")
local _,landed=c:havenShipments(port.id)
check(landed.panels==12,"the haven shows what landed today")
check(c.orders.surveyors==1,"departments are untouched by freight")
c:endDay()
_,landed=c:havenShipments(port.id)
check(not landed.panels,"yesterday's landing is no longer today's")

print("stores")
do
  local c=T.sandbox(24)
  c.stock={}
  c.money=100000
  local port=c.g:addNode(400,60,"terminal"); port.haven="port"
  local road=c.g:addNode(1400,600,"terminal"); road.haven="highway"
  c:refresh()
  local quay=City.STORE.cap[0]
  check(c:storeCap("steel")==2*quay,"every haven has room on its quay for every good")
  check(c:storeRoom("steel")==2*quay and c:storeRoom("glass")==2*quay,"and each good has room of its own")
  local money=c.money
  assert(c:upgradeStore(port.id,"steel"))
  check(c.money==money-City.STORE.cost[1] and c:storeLevel(port,"steel")==1,"a store is raised for one good")
  check(c:storeCap("steel")==quay+City.STORE.cap[1] and c:storeCap("glass")==2*quay,"and only that good gets the room")
  for _=2,City.STORE_MAX do assert(c:upgradeStore(port.id,"steel")) end
  check(select(2,c:upgradeStore(port.id,"steel"))=="the store is as big as it goes","up to its last level")
  check(select(2,c:upgradeStore(port.id,"water"))=="nothing to store","water is not kept in a store")
  local copy=assert(Save.unpack(Save.pack(c)))
  check(copy:storeLevel(copy.g.nodes[port.id],"steel")==City.STORE_MAX,"a store's level survives a save")

  -- An order goes straight into store: no haulage, no convoy.
  assert(c:orderImport(road.id,"panels",30))
  c:endDay()
  check(c:materialStock("panels")==30 and #(c.convoys or {})==0,"the next morning it is in store, with nothing on the road")
  check(select(2,c:orderImport(road.id,"panels",c:storeRoom("panels")+1))~=nil,"and no more than there is room for")

  -- A site delivery: building with materials sends them out to the site.
  c.stock.panels=40
  c:spendMaterials({panels=12},1,1800,900)
  local site=c.convoys[#c.convoys]
  check(site and site.key=="panels" and site.units==12 and not site.stock,"materials are driven out to the site from a haven")
  check(site.pts[#site.pts-1]==1800 and site.pts[#site.pts]==900,"all the way to where they are used")
  c:endDay()
  local gone=true
  for _,cv in ipairs(c.convoys) do if cv==site then gone=false end end
  check(gone,"a site delivery is done by the next day")
end

print("a haven takes made goods into store, never its own imports")
do
  local Graph=require("graph")
  local g=Graph.new()
  local haven=g:addNode(0,0,"terminal")
  haven.intake={steel=25}
  local check0=function(v,m) check(v,m) end
  local flow,_,served=g:maxflow(false,"steel")
  check0((served[haven.id] or 0)==0,"a haven alone does not buy abroad to fill its store")
  local works=g:addNode(200,0,"source"); works.commodity="steel"; works.output=10
  local road=g:addEdge(works.id,haven.id,50); road.commodity="steel"
  flow,_,served=g:maxflow(false,"steel")
  check0(served[haven.id]==10,"what a works sends it by road goes into store")
  local client=g:addNode(-200,0,"client"); client.commodity="beer"; client.demand=5
  local main=g:addEdge(haven.id,client.id,50); main.commodity="beer"
  local _,_,servedBeer=g:maxflow(false,"beer")
  check0((servedBeer[client.id] or 0)==0,"what it lands never leaves by a main")
end

print("a solar array is assembled from its panels")
do
  local c=T.sandbox(24,true)
  c.stock.panels=100
  local d=c.districts[City.MAP.start]
  c.g:addNode(d.x+200,d.y+200,"terminal").haven="highway"
  local array
  for dx=0,600,60 do
    array=c:buySource("power",d.x+400+dx,d.y+420,"solar")
    if array then break end
  end
  assert(array,"somewhere to put an array")
  c:refresh()
  check(array.assembling and (array.effectiveOutput or 0)==0,"the day it is built it is still being put together")
  local site
  for _,cv in ipairs(c.convoys or {}) do if cv.key=="panels" and not cv.stock then site=cv end end
  check(site~=nil,"while its panels are driven out to it")
  c:endDay(); c:refresh()
  check(not array.assembling and (array.effectiveOutput or array.output or 0)>0,"and it runs from the next day")
end

print("a bridge reaches an island")
do
  local c=T.sandbox(1)
  for _,d in ipairs(c.districts) do d.population=500 end
  local island
  for _,d in ipairs(c.districts) do if d.island then island=d; break end end
  if island then
    local ix,iy=island.x+island.w/2,island.y+island.h/2
    local a=c.g:addNode(ix,150,"corner"); local b=c.g:addNode(ix,iy,"corner")
    c.buildRoadType="road"
    check(select(2,c:layLink(a.id,b.id,"road"))=="water in the way: build a bridge","no road runs out to sea")
    c.buildRoadType="bridge"
    local l=c:layLink(a.id,b.id,"road")
    check(l and l.roadType=="bridge" and c:waterAlong(a.x,a.y,b.x,b.y)>0,"a bridge does, over the open water")
  end
end

print("works and reactors go up from their delivered materials")
do
  local c=T.sandbox(24,true)
  c.stock.steel, c.stock.concrete=2000, 2000
  local d=c.districts[City.MAP.start]
  c.g:addNode(d.x+150,d.y+150,"terminal").haven="highway"
  local mill
  for dx=0,600,60 do mill=c:build(d.x+300+dx,d.y+300,"works","maltings"); if mill then break end end
  assert(mill,"somewhere for a maltings")
  check(mill.assembling==c.day and next(mill.wants)==nil and mill.ready==0,"a works built today takes nothing in and makes nothing")
  local reactor
  for dx=0,600,60 do reactor=c:buySource("power",d.x+300+dx,d.y+520,"nuclear"); if reactor then break end end
  assert(reactor,"somewhere for a reactor")
  check(reactor.assembling and (reactor.effectiveOutput or 0)==0,"a reactor built today is not yet generating")
  c:endDay(); c:refresh()
  check(not mill.assembling and next(mill.wants)~=nil,"the next day the works asks for its inputs")
  check(not reactor.assembling and (reactor.effectiveOutput or reactor.output or 0)>0,"and the reactor runs")
end

print("imports by rail and by river barge")
do
  local c=T.sandbox(24)
  c.stock={}
  -- A spot on the river bank, and one well away from it.
  local bank, dry
  for y=300,1600,50 do
    for x=-1000,4000,20 do
      if not bank and c:nearRiver(x,y) and not c:riverAt(x,y) and c:riverAt(x+40,y) then bank={x=x,y=y} end
      if not dry and not c:nearRiver(x,y) and not c:obstacleAt(x,y) then dry={x=x,y=y} end
    end
  end
  assert(bank and dry,"a river bank and dry ground")
  check(select(2,c:havenSite(dry.x,dry.y,"wharf"))=="a wharf stands on the river bank","a wharf needs the river")
  check(c:havenSite(bank.x,bank.y,"wharf")=="wharf","and stands on its bank")
  local wharf=assert(c:build(bank.x,bank.y,"terminal","wharf"))
  local rail=assert(c:build(dry.x,dry.y,"terminal","railhead"))
  check(wharf.haven=="wharf" and rail.haven=="railhead","both are havens")
  check(c:importPrice("steel","wharf")<c:importPrice("steel","railhead") and c:importPrice("steel","railhead")<c:importPrice("steel","highway"),
    "a barge lands cheaper than a train, a train cheaper than lorries")
  assert(c:orderImport(wharf.id,"steel",30))
  assert(c:orderImport(rail.id,"panels",20))
  c:endDay()
  check(c:materialStock("steel")==30 and c:materialStock("panels")==20,"what they land is in store the next morning")
  local _,landedW=c:havenShipments(wharf.id)
  local _,landedR=c:havenShipments(rail.id)
  check(landedW.steel==30 and landedR.panels==20,"and each shows what it landed")
  local bx,by=c:wharfBerth(wharf)
  check(c:riverAt(bx,by),"a wharf's berth is out on the water")
  local ux,uy=c:railAxis(rail)
  check(math.abs(ux*ux+uy*uy-1)<1e-9,"a rail terminal lies on a main line")
end

print("rail lines run on through havens")
do
  local c=T.sandbox(24,true)
  local d=c.districts[City.MAP.start]
  local x0,y0=d.x+150,d.y+200
  local rail=assert(c:build(x0,y0,"terminal","railhead"))
  local mid=c.g:addNode(x0+500,y0,"terminal"); mid.haven="highway"
  local far=c.g:addNode(x0+500,y0+400,"terminal"); far.haven="highway"
  c:refresh()
  assert(c:layPipe(rail.id,mid.id,"steel",1,"rail"))
  assert(c:layPipe(mid.id,far.id,"steel",1,"rail"))
  c:refresh()
  local stops,cap=c:railPath(rail,far)
  check(stops and #stops==3 and stops[2]==mid and cap>0,"the railway runs on through the haven between")
  local route=c:haulRoute(rail,far.x,far.y,far)
  check(route and route.mode=="train","a load from one haven to another goes by train")
end

print("river barges carry loads between wharves")
do
  local c=T.sandbox(24)
  c.stock={}
  -- Bank spots along the river, far apart.
  local banks={}
  for y=200,2400,40 do
    for x=-1000,5000,20 do
      if c:nearRiver(x,y) and not c:riverAt(x,y) and c:riverAt(x+40,y) and not c:placementError(x,y,"terminal") then
        if #banks==0 or (banks[#banks].y+900<y) then banks[#banks+1]={x=x,y=y} end
        break
      end
    end
  end
  assert(#banks>=2,"two stretches of river bank")
  local up,down=banks[1],banks[2]
  local wharf=assert(c:build(up.x,up.y,"terminal","wharf"))
  local bankHaven=c.g:addNode(down.x-60,down.y,"terminal"); bankHaven.haven="highway"
  c:refresh()
  local cv=c:haulRoute(wharf,bankHaven.x,bankHaven.y,bankHaven)
  check(cv.mode=="barge" and not cv.legs,"to a haven by the river it goes all the way by barge")
  check(c:riverAt(cv.pts[1],cv.pts[2]) and c:riverAt(cv.pts[#cv.pts-1],cv.pts[#cv.pts]),"and the barge stays on the water, berth to berth")

  -- Away from the river: by barge to the wharf nearest it, then by land.
  local wharf2=assert(c:build(down.x,down.y+120,"terminal","wharf"))
  local inland=c.g:addNode(down.x-400,down.y+120,"terminal"); inland.haven="highway"
  c:refresh()
  local route=c:haulRoute(wharf,inland.x,inland.y,inland)
  check(route.mode=="barge" and route.legs and #route.legs==2 and route.legs[2].mode~="barge","inland: barge to the next wharf, then on by land")
  local barge=c:haulCost({mode="barge",pts=route.legs[1].pts},100)
  local land=c:haulCost({mode=route.legs[2].mode,pts=route.legs[2].pts},100)
  check(c:haulCost(route,100)<=barge+land+1 and c:haulCost(route,100)>=barge+land-1,"each leg billed at its own rate")
end
print(T.checks.." import checks passed")
