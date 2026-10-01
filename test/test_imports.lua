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
end
print(T.checks.." import checks passed")
