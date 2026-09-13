package.path="src/?.lua;"..package.path
local City=require("city")
local Save=require("company_save")
local E=require("experience")
local checks=0
local function check(value,message) assert(value,message); checks=checks+1 end
local c=City.new({seed=24,obstacles=0})
local offer=c:clientList(true)[1]
local rep=c.reputation
assert(c:declineClient(offer.id))
check(c.reputation==rep-1,"declining costs one reputation")
check(not c:declineClient(offer.id) and c.reputation==rep-1,"declining twice cannot charge twice")
check(assert(Save.unpack(Save.pack(c))).reputation==rep-1,"decline penalty survives loading")
local ignored=assert(c:addClient("house",true))
ignored.expires=c.day
local r=assert(c:endDay())
check(r.ignored==1 and c.reputation==rep-3,"ignoring costs two reputation")
check(not ignored.alive,"expired requests are removed")
local last=0
for reputation=0,100 do
  c.reputation=reputation
  local limit=c:requestLimit()
  check(limit>=last and limit>=1 and limit<=10,"request limits grow with reputation")
  last=limit
end
c=City.new({seed=42,obstacles=0})
c.money=1000000
for _,d in ipairs(c.districts) do d.owned=true end
c.reputation=100
r=assert(c:endDay())
check(#r.arrivals==10,"maximum reputation brings ten requests with space available")
check(#c:clientList(true)==11,"all ten requests appear in the client list")
check(assert(Save.unpack(Save.pack(c))).lastReport.arrivals[10].id==r.arrivals[10].id,"all arrivals survive loading")
local p=c:riverPath()
check(p.y[1]+p.ny[1]*p.hw[1]==0 and p.y[1]-p.ny[1]*p.hw[1]==0,"both banks meet the sea exactly")
check(#p.branches==4,"river has four tributaries")
for _,branch in ipairs(p.branches) do
  check(c:riverAt(branch.x[35],branch.y[35]),"branch water is also water in construction rules")
  check(not c:riverAt(branch.x[1],-1),"river never extends into the sea")
  check(branch.hw[branch.n]==0,"upstream branches taper to a natural end")
  for i=2,branch.n do check(branch.y[i]>branch.y[i-1],"branches do not fold back") end
end
check(E.recipeSummary(City.RECIPES.turbine):find("Requires 16 water per day",1,true),"factory descriptions show full daily inputs")
check(E.recipeSummary(City.RECIPES.turbine):find("Produces 8 electricity per day",1,true),"factory descriptions show real daily output")
print(checks.." comfort checks passed")
