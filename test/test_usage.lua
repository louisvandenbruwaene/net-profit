-- Contracts and daily use: customers pay for a ceiling and draw less.
package.path='test/?.lua;src/?.lua;'..package.path
local T=require('support')
local City=require('city')
local Save=require('company_save')
local function check(v,m) T.check(v,m); print("  ok  "..m) end
City.FLAT_USAGE=nil

local c=T.sandbox(24)
check(City.weekdayName(1)=="Mon" and City.weekdayName(7)=="Sun" and City.weekdayName(8)=="Mon","day one is a Monday")
check(c:weatherOn(12)==c:weatherOn(12),"the weather for a day is fixed")
local copy=assert(Save.unpack(Save.pack(c)))
local same=true
for d=1,40 do if c:weatherOn(d).key~=copy:weatherOn(d).key then same=false end end
check(same,"and the same after loading")
local kinds={}
for d=1,200 do kinds[c:weatherOn(d).key]=true end
check(kinds.mild and kinds.hot and kinds.cold and kinds.wet,"every kind of weather turns up")

print("use stays inside the contract and averages below it")
local d=c.districts[City.MAP.start]
local cx,cy=d.x+d.w/2,d.y+d.h/2
local well=T.node(c,"source",cx-200,cy,"water",400)
local hub=assert(c:build(cx-60,cy,"manifold"))
assert(c:layPipe(well.id,hub.id,"water","large"))
local houses={}
for _=1,20 do houses[#houses+1]=assert(c:addClient("estate",false)) end
local used,contract,inside=0,0,true
for day=1,70 do
  c.day=day; c:refresh()
  for _,h in ipairs(houses) do
    if h.use<1 or h.use>h.demand then inside=false end
    used=used+h.use; contract=contract+h.demand
  end
end
check(inside,"every draw is between one unit and the contract")
local share=used/contract
check(share>0.5 and share<0.85,"customers use well under their contracts on average ("..string.format("%.2f",share)..")")
c.day=71; c:refresh()
local before={}
for i,h in ipairs(houses) do before[i]=h.use end
c:refresh()
local stable=true
for i,h in ipairs(houses) do if h.use~=before[i] then stable=false end end
check(stable,"a refresh on the same day does not redraw")
local lo,hi,total=c:forecast("water",72)
check(lo<=hi and hi<=total and lo>0,"the forecast is a range inside the contracts")

print("the load on a network is the use, not the contracts")
c.day=73; c:refresh()
local sum,use=0,0
for _,h in ipairs(houses) do sum=sum+h.demand; use=use+h.use end
check(use<sum,"today's draw ("..use..") is under the contracts ("..sum..")")
City.FLAT_USAGE=true; c:refresh()
local flat=0
for _,h in ipairs(houses) do flat=flat+h.use end
check(flat==sum,"with flat usage every contract is drawn in full")
City.FLAT_USAGE=nil; c.day=74; c:refresh()

print("pay follows the contract when today's use arrives")
local h=houses[1]
c:refresh()
c.served[h.id]=h.use
check(c:fullyServed(h),"given today's use, a customer is supplied")
check(c:clientIncome(h)==math.floor(h.demand*h.rate+0.5),"and pays the whole contract")
if h.use>1 then
  c.served[h.id]=h.use-1
  check(not c:fullyServed(h),"a unit short is short")
  check(c:clientIncome(h)<math.floor(h.demand*h.rate+0.5),"and pays less")
end
print(T.checks.." usage checks passed")
