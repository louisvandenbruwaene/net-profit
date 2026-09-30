-- The top bar offers a crew once repairs are daily, and says who leaves tomorrow.
package.path="src/?.lua;"..package.path
local City=require("city")
local Save=require("company_save")
local checks=0
local function check(value,message) assert(value,message); checks=checks+1 end

local c=City.new({seed=24,obstacles=0})
c.money=10000
check(not c:crewPitch(),"no crew is offered before anything has been mended")
for _=1,2 do c:noteHandRepair(); c.day=c.day+1 end
check(not c:crewPitch(),"two days of repairs are not yet a chore")
c:noteHandRepair(); c:noteHandRepair()
check(#c.handRepairDays==3,"a day with several repairs counts once")
check(c:crewPitch() and c:crewPitch().hire==City.crewHire,"three days in five brings the offer")
c.day=c.day+5
check(not c:crewPitch(),"old repairs stop counting")
for _=1,3 do c:noteHandRepair(); c.day=c.day+1 end
check(c:crewPitch(),"the offer comes back while it is still unanswered")
local copy=assert(Save.unpack(Save.pack(c)))
check(copy:crewPitch(),"the repair days survive loading")
assert(c:declineCrew())
check(not c:crewPitch(),"declining puts the offer away for good")
check(not assert(Save.unpack(Save.pack(c))):crewPitch(),"and the answer survives loading")
assert(copy:hireCrew())
check(copy.crews==1 and not copy:crewPitch(),"hiring answers it too")

c=City.new({seed=24,obstacles=0})
local offer=c:clientList(true)[1]
assert(c:acceptClient(offer.id))
c:refresh()
check(not c:fullyServed(offer),"a new customer with no main is short")
offer.grace=3
check(not c:leavesTomorrow(offer) and #c:leavingTomorrow()==0,"patience left means nobody is leaving")
offer.grace=1
check(c:leavesTomorrow(offer) and #c:leavingTomorrow()==1,"a last day of patience is leaving tomorrow")
offer.grewOn=c.day
check(not c:leavesTomorrow(offer),"a customer who just grew is given time")
offer.grewOn=nil
c:endDay()
check(not offer.alive or offer.prospect,"and leaving tomorrow means gone at the close")
print(checks.." crew and leaving checks passed")
