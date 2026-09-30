-- Big projects built on owned ground, and referrals from reliable customers.
package.path='test/?.lua;src/?.lua;'..package.path
local T=require('support')
local City=require('city')
local Save=require('company_save')
local function check(v,m) T.check(v,m); print("  ok  "..m) end

local c=T.sandbox(24)
local d=c.districts[City.MAP.start]
local cx,cy=d.x+d.w/2,d.y+d.h/2
local well=T.node(c,"source",cx-200,cy,"water",200)
local hub=assert(c:build(cx-60,cy,"manifold"))
assert(c:layPipe(well.id,hub.id,"water","large"))

print("a project waits for the company to be big enough")
check(c:projectLocked("hospital")==City.PROJECT_BY.hospital.clients.." customers first","a small company cannot build a hospital")
check(c:projectLocked("college"):find("licence"),"a college needs the power licence")
for _=1,City.PROJECT_BY.hospital.clients do assert(c:addClient("house",false)) end
check(c:projectLocked("hospital")==nil,"enough customers open it")

print("building one")
local money=c.money
local h=assert(c:buildProject("hospital",cx+60,cy+40))
check(c.money==money-City.PROJECT_BY.hospital.price,"it costs its price")
check(h.kind=="client" and not h.prospect and h.demand==City.PROJECT_BY.hospital.demand,"it stands as a signed customer with its demand")
check(c:projectLocked("hospital")=="already built","only one of each")
check(not c:buildProject("hospital",cx+160,cy+40),"a second is refused")
local lo,hi=c:sizeRange(hub.id,h.id)
check(hi>=select(2,City.sizeOf("medium")),"it takes a bigger main than a house")
assert(c:layPipe(hub.id,h.id,"water","medium"))
c:refresh()
check(c:fullyServed(h),"a medium main supplies it")
check(c:clientIncome(h)==City.projectIncome("hospital"),"and it pays demand times rate")

print("a supplied project draws offers round itself")
local r=assert(c:endDay())
local drawn=0
for _,a in ipairs(r.arrivals) do if a.drawnBy==h.id then drawn=drawn+1 end end
check(drawn==1,"one offer a close")
check(c.projects.hospital.attract==City.PROJECT_BY.hospital.attract-1,"from a limited draw")
local copy=assert(Save.unpack(Save.pack(c)))
check(copy:projectNode("hospital") and copy.projects.hospital.attract==c.projects.hospital.attract,"the project survives loading")

print("a reliable customer refers a neighbour")
local c2=T.sandbox(31)
local d2=c2.districts[City.MAP.start]
local w2=T.node(c2,"source",d2.x+d2.w/2-200,d2.y+d2.h/2,"water",200)
local hub2=assert(c2:build(w2.x+140,w2.y,"manifold"))
assert(c2:layPipe(w2.id,hub2.id,"water","large"))
local house=assert(c2:addClient("house",false,nil,hub2))
assert(c2:layPipe(hub2.id,house.id,"water","small"))
c2:refresh()
assert(c2:fullyServed(house))
local every=City.REFERRAL.every
local k=1
while c2:unit(house.id,900+every*k)>=City.REFERRAL.chance do k=k+1 end
house.streak=every*k-1
for _,p in ipairs(c2:clientList(true)) do c2:retireClient(p) end
local r2=assert(c2:endDay())
local ref=r2.referred and r2.referred[1]
check(ref and ref.from==house.id,"the customer sends a neighbour")
local n=c2.g.nodes[ref.id]
check(n.prospect and n.referredBy==house.id,"as an open offer")
check(c2:ratePremium(n)>=City.REFERRAL.premium-0.01,"over the going rate")
house.streak=every*k
local r3=assert(c2:endDay())
check(not r3.referred,"and not again the next close")
print(T.checks.." project and referral checks passed")
