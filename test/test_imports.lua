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
print(T.checks.." import checks passed")
