-- Shops on the streets: footfall, full shops, price, benches, supply.
package.path='test/?.lua;src/?.lua;'..package.path
local T=require('support')
local City=require('city')
local Save=require('company_save')
local function check(v,m) T.check(v,m); print("  ok  "..m) end

local c=T.sandbox(24,true)
local d=c.districts[City.MAP.start]
local sy
local well=T.node(c,"source",d.x+150,d.y+330,"water",400)
local hub=assert(c:build(d.x+200,d.y+140,"manifold"))
assert(c:layPipe(well.id,hub.id,"water","large"))
for i=1,24 do
  local h=c.g:addNode(d.x+380+i*24,d.y+180+(i%3)*45,"client")
  h.clientType,h.commodity,h.demand,h.rate,h.patience,h.grace="house","water",3,7,3,3
end
c:refresh()

print("a shop must stand by a road the company laid")
check(c:shopLocked("cafe")=="lay a road first","no road, no shop")
check(not c:streetAt(d.x+200,d.y+10),"the edge of a plot is no street")
-- A road across the top of the plot, laid by the company.
d.population=500
local ra=c.g:addNode(d.x+40,d.y+50,"corner")
local rb=c.g:addNode(d.x+d.w-40,d.y+50,"corner")
assert(c:layLink(ra.id,rb.id,"road"))
sy=d.y+50+40
check(c:shopError("cafe",d.x+d.w/2+250,d.y+d.h/2+150)=="build beside a road","not in the middle of a plot")
local st=c:streetAt(d.x+200,sy)
check(st and st.key:sub(1,5)=="road:","a road is a street")
local money=c.money
local cafe=assert(c:buildShop("cafe",d.x+200,sy))
check(c.money==money-City.SHOP_BY.cafe.cost,"a shop costs its price")
check(City.isShop(cafe) and cafe.level==1,"it opens at level one")

print("people walk the street and some come in")
c:refresh()
check(cafe.passing>0,"the street has walkers ("..cafe.passing..")")
check(cafe.visitors>0 and cafe.visitors<=c:shopCapacity(cafe),"some come in, never more than it holds ("..cafe.visitors..")")
check(c:shopIncome(cafe)==0,"unsupplied, it serves nobody")
assert(c:layPipe(hub.id,cafe.id,"water","small"))
c:refresh()
check(c:shopServed(cafe)==cafe.visitors,"supplied, it serves everyone who came in")
check(c:clientIncome(cafe)==cafe.visitors*cafe.price,"and takes their money")

print("the weekend and the weather move the crowd")
local busiest,quietest
for day=1,60 do
  local w=c:streetWalkers(st,day)
  busiest=math.max(busiest or w,w); quietest=math.min(quietest or w,w)
end
check(busiest>quietest*1.4,"some days are much busier than others ("..quietest.." to "..busiest..")")
check(c:streetWalkers(st,6,true)>=c:streetWalkers(st,6),"the peak is the top of the day's range")

print("price, benches and neighbours steer them")
local base=c:shopChance(cafe)
assert(c:setShopPrice(cafe.id,cafe.price*2))
check(c:shopChance(cafe)<base,"a dearer shop draws fewer")
assert(c:setShopPrice(cafe.id,City.SHOP_BY.cafe.price))
assert(c:buildBench(cafe.x+30,d.y+50+20))
check(c:shopChance(cafe)>base,"a bench nearby draws more")
local alone=cafe.visitors
c:refresh(); alone=cafe.visitors
local rival=assert(c:buildShop("cafe",d.x+120,sy))
check(rival.visitors>0,"a second shop on the street gets customers")
check(cafe.visitors<=alone,"and takes some the first would have had")

print("a full shop sends people on")
cafe.level=1; c:setShopContract(cafe)
local oldAttract=City.SHOP_BY.cafe.attract
City.SHOP_BY.cafe.attract=0.9
c:refresh()
check(rival.visitors==c:shopCapacity(rival) or cafe.visitors==c:shopCapacity(cafe),"a shop can fill up")
City.SHOP_BY.cafe.attract=oldAttract

print("expanding")
local contract=cafe.demand
assert(c:expandShop(cafe.id))
check(cafe.level==2 and c:shopCapacity(cafe)==City.SHOP_BY.cafe.levels[2],"expanding raises how many it holds")
check(cafe.demand>=contract,"and what it may draw")

print("shops keep")
local copy=assert(Save.unpack(Save.pack(c)))
local n=copy.g.nodes[cafe.id]
check(City.isShop(n) and n.level==2 and n.price==cafe.price and #copy.benches==1,"a shop and its bench survive loading")
local grace=cafe.grace
for _=1,5 do assert(c:endDay()) end
check(cafe.alive and cafe.kind=="client" and cafe.grace==grace,"a shop never runs out of patience")
print(T.checks.." shop checks passed")
