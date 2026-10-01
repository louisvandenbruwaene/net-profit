-- Imports: ordering goods at a haven, paid now, landed in the yards tomorrow.
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
check(c:materialStock("panels")==0,"nothing is in the yards until it lands")
local coming=c:havenShipments(port.id)
check(coming.panels==12,"the haven shows it on the way")
check(c:shipmentError(port.id,"panels",c:storeRoom("panels")+1)=="no room in the yards","the yards' room counts what is already coming")
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

print("hauled inland")
do
  local c=T.sandbox(24)
  c.stock={}
  local port=c.g:addNode(400,60,"terminal"); port.haven="port"
  local yard=c.g:addNode(1400,600,"dc")
  c:refresh()
  assert(c:orderImport(port.id,"panels",30))
  c:endDay()
  check(c:materialStock("panels")==0,"landed at the harbour is not yet in the yard")
  local cv=c.convoys[1]
  check(cv and cv.stock and cv.from==port.id and cv.to==yard.id and cv.mode=="lorry","with no road or line it goes overland by lorry")
  check(c:storeRoom("panels")==c:storeRoom("steel")-30,"what is on the road still counts against the yard's room")
  check(#c.shipments==0 and cv.cost>0,"and the haulage is paid")
  local copy=assert(Save.unpack(Save.pack(c)))
  local back=copy.convoys and copy.convoys[1]
  check(back and back.units==cv.units and back.to==cv.to and #back.pts==#cv.pts and back.arrive==cv.arrive,"a load on the road survives a save")
  copy:endDay()
  check(copy:materialStock("panels")==30,"and still reaches the yard after loading")
  c:endDay()
  check(c:materialStock("panels")==30,"the next morning it is in the yard")
  check(#c.convoys==0,"and the convoy is done")

  -- With a road all the way, a semi takes it along the road.
  c.buildRoadType="road"
  local function link(a,b) c.buildRoadType=c:waterAlong(a.x,a.y,b.x,b.y)>0 and "bridge" or "road"; return assert(c:layLink(a.id,b.id,"road")) end
  for _,d in ipairs(c.districts) do d.population=500 end
  local mid=c.g:addNode(900,300,"corner")
  link(port,mid); link(mid,yard)
  assert(c:orderImport(port.id,"steel",10)); c:endDay()
  local road=c.convoys[#c.convoys]
  check(road.mode=="semi" and #road.pts==6,"along the company's roads it goes by semi, by the roads")

  -- A site delivery: building with materials sends them out to the site.
  local before=#c.convoys
  c.stock.panels=40
  local bill={panels=12}
  c:spendMaterials(bill,1,1800,900)
  local site=c.convoys[#c.convoys]
  check(#c.convoys==before+1 and site.key=="panels" and site.units==12 and not site.stock,"materials are driven out to the site")
  check(site.pts[#site.pts-1]==1800 and site.pts[#site.pts]==900,"all the way to where they are used")
  c:endDay()
  local gone=true
  for _,cv in ipairs(c.convoys) do if cv==site then gone=false end end
  check(gone,"a site delivery is done by the next day")
end

print("to a chosen yard")
do
  local c=T.sandbox(24)
  c.stock={}
  local port=c.g:addNode(400,60,"terminal"); port.haven="port"
  local near=c.g:addNode(700,300,"dc")
  local far=c.g:addNode(1400,600,"dc")
  c:refresh()
  assert(c:orderImport(port.id,"steel",20,far.id))
  c:endDay()
  check(c.convoys[1].to==far.id,"an order goes on to the yard it was sent to, not the nearest")
  assert(c:orderImport(port.id,"steel",20))
  c:endDay()
  check(c.convoys[#c.convoys].to==near.id,"and to the nearest when none was chosen")

  -- A haven's own choice: every order goes there unless it says otherwise.
  assert(c:setImportYard(port.id,far.id))
  check(c:importYardOf(port)==far,"a haven keeps the yard its orders go to")
  local copy=assert(Save.unpack(Save.pack(c)))
  check(copy:importYardOf(copy.g.nodes[port.id]).id==far.id,"and keeps it across a save")
  assert(c:orderImport(port.id,"steel",20)); c:endDay()
  check(c.convoys[#c.convoys].to==far.id,"orders then go there by default")
  assert(c:orderImport(port.id,"steel",20,near.id)); c:endDay()
  check(c.convoys[#c.convoys].to==near.id,"an order can still name another yard")
  assert(c:setImportYard(port.id,nil))
  assert(c:orderImport(port.id,"steel",20)); c:endDay()
  check(c.convoys[#c.convoys].to==near.id,"and clearing the choice goes back to the nearest")
  check(select(2,c:setImportYard(port.id,port.id))=="choose a yard","only a yard can be chosen")
end

print("a solar array is assembled from its panels")
do
  local c=T.sandbox(24,true)
  c.stock.panels=100
  local d=c.districts[City.MAP.start]
  local yard=c.g:addNode(d.x+200,d.y+200,"dc")
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
  c.g:addNode(d.x+150,d.y+150,"dc")
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
  check(c:materialStock("steel")==30 and c:materialStock("panels")==20,"with no yard, what they land is on their quays the next morning")
  local _,landedW=c:havenShipments(wharf.id)
  local _,landedR=c:havenShipments(rail.id)
  check(landedW.steel==30 and landedR.panels==20,"and each shows what it landed")
  local bx,by=c:wharfBerth(wharf)
  check(c:riverAt(bx,by),"a wharf's berth is out on the water")
  local ux,uy=c:railAxis(rail)
  check(math.abs(ux*ux+uy*uy-1)<1e-9,"a rail terminal lies on a main line")
end

print("rail lines carry imports inland from the rail terminal")
do
  local c=T.sandbox(24,true)
  c.stock.steel=2000; c.stock.glass=0
  local d=c.districts[City.MAP.start]
  local x0,y0=d.x+150,d.y+200
  local rail=assert(c:build(x0,y0,"terminal","railhead"))
  local mid=c.g:addNode(x0+500,y0,"dc")
  local far=c.g:addNode(x0+500,y0+400,"dc")
  c:refresh()
  assert(c:layPipe(rail.id,mid.id,"steel",1,"rail"))
  assert(c:layPipe(mid.id,far.id,"steel",1,"rail"))
  c:refresh()
  local stops,cap=c:railPath(rail,far)
  check(stops and #stops==3 and stops[2]==mid and cap>0,"the railway runs on through the yard between")
  assert(c:setImportYard(rail.id,far.id))
  assert(c:orderImport(rail.id,"glass",math.min(cap,20)))
  c:endDay()
  local cv=c.convoys[#c.convoys]
  check(cv.mode=="train" and #cv.pts==6 and cv.to==far.id,"an order goes inland by train, stop by stop")
  c:endDay()
  check(c:materialStock("glass")==math.min(cap,20),"and is in the far yard the next morning")

  -- More than the line has room for in a day goes up a trainload a day.
  c:refresh()
  local _,room=c:railPath(rail,far)
  local units=room*2+5
  assert(c:orderImport(rail.id,"glass",units))
  c:endDay()
  local loads={}
  for _,v in ipairs(c.convoys) do if v.key=="glass" and v.stock then loads[#loads+1]=v end end
  check(#loads==3,"a big order is split into trainloads ("..#loads..")")
  check(loads[1].arrive+1==loads[2].arrive and loads[2].arrive+1==loads[3].arrive,"one a day")
  local before=c:materialStock("glass")
  c:endDay()
  check(c:materialStock("glass")==before+loads[1].units,"the first trainload is in the next morning")
  c:endDay(); c:endDay()
  check(c:materialStock("glass")==before+units,"and the last two days later")
end

print("river barges carry imports inland from the wharf")
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
  -- A yard on the bank downriver: the barge takes it all the way.
  local bankYard=c.g:addNode(down.x-60,down.y,"dc")
  c:refresh()
  assert(c:orderImport(wharf.id,"steel",40,bankYard.id))
  c:endDay()
  local cv=c.convoys[#c.convoys]
  check(cv.mode=="barge" and not cv.legs and cv.to==bankYard.id,"to a yard by the river it goes all the way by barge")
  check(c:riverAt(cv.pts[1],cv.pts[2]) and c:riverAt(cv.pts[#cv.pts-1],cv.pts[#cv.pts]),"and the barge stays on the water, berth to berth")
  c:endDay()
  check(c:materialStock("steel")==40,"in the yard the next morning")

  -- A yard away from the river: by barge to the wharf nearest it, then by land.
  local wharf2=assert(c:build(down.x,down.y+120,"terminal","wharf"))
  local inland=c.g:addNode(down.x-400,down.y+120,"dc")
  c:refresh()
  local route=c:haulRoute(wharf,inland.x,inland.y,inland)
  check(route.mode=="barge" and route.legs and #route.legs==2 and route.legs[2].mode~="barge","a yard inland: barge to the next wharf, then on by land")
  local barge=c:haulCost({mode="barge",pts=route.legs[1].pts},100)
  local land=c:haulCost({mode=route.legs[2].mode,pts=route.legs[2].pts},100)
  check(c:haulCost(route,100)<=barge+land+1 and c:haulCost(route,100)>=barge+land-1,"each leg billed at its own rate")
  assert(c:orderImport(wharf.id,"glass",30,inland.id))
  c:endDay(); c:endDay()
  check(c:materialStock("glass")==30,"and it reaches the inland yard the morning after")
end
print(T.checks.." import checks passed")
