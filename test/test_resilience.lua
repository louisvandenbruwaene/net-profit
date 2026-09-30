package.path='test/?.lua;src/?.lua;'..package.path
local T=require('support')
local City=require('city')
City.FLAT_USAGE = true -- these checks are about flow: customers draw their whole contract
local Graph=require('graph')
local Save=require('company_save')
local check=T.check

local function city() return T.sandbox(31,true) end
-- Fixture sources and junctions take any number of mains.
local function node(c,kind,x,y,commodity,output)
  local n=T.node(c,kind,x,y,commodity,output)
  if kind=='source' or kind=='junction' then n.ports=16 end
  return n
end
local function house(c,x,y,demand)
  local n=node(c,'client',x,y,'water')
  n.demand=demand or 2; n.clientType='house'; n.rate=6; n.rateBase=6; n.grace=3; n.patience=3; n.prospect=false
  return n
end
-- Which sizes a structure will take depends on both ends, so try them all.
local function pipe(c,a,b)
  local why
  for _,size in ipairs({'small','medium','large'}) do
    local e,err=c:layPipe(a.id,b.id,'water',size)
    if e then return e end
    why=err
  end
  error(why)
end
local function signed(c,count)
  for i=1,count do house(c,3000+i*5,3000,1) end
end

-- Levels: a building starts weak and is grown in place.
do
  local c=city()
  local j=assert(c:build(1300,1300,'junction'))
  check(c:levelOf(j)==1 and j.ports==3 and j.throughput==60,'a new junction is a level 1 T split')
  local up=assert(c:upgradeLevel(j.id))
  check(up.kind=='manifold' and c:levelOf(up)==2 and up.ports==6 and up.throughput==140,'level 2 turns it into a hub with six ports')
  check(c:levelError(j.id)=='needs 6 signed customers','level 3 waits for the company to grow')
  signed(c,6)
  assert(c:upgradeLevel(j.id))
  check(j.ports==8 and c:levelName(j)=='Large hub','level 3 gives eight ports')
  signed(c,8)
  assert(c:upgradeLevel(j.id))
  check(j.ports==10 and j.throughput==999 and c:levelError(j.id)=='already at the highest level','level 4 is the top')

  local m=assert(c:build(1400,1300,'manifold'))
  check(c:levelOf(m)==2 and m.ports==6,'a manifold built directly is already a hub')

  local pole=assert(c:build(1500,1300,'pole'))
  local hv=assert(c:build(1600,1300,'hvtower'))
  check(pole.ports==3 and pole.throughput==40 and hv.throughput==160,'towers start weak and carry more at higher voltage')
  local a=assert(c:build(1500,1400,'pole'))
  local base=c:rangeBetween(pole.id,a.id,nil,'power')
  assert(c:upgradeLevel(pole.id))
  check(pole.ports==4 and pole.throughput==90 and c:reachBonus(pole)==0.10,'a tower upgrade adds connections, capacity and reach')
  check(math.abs(c:rangeBetween(pole.id,a.id,nil,'power')-base*1.1)<0.001,'reach applies to cables out of an upgraded tower')

  local pump=assert(c:build(1700,1300,'pump'))
  check(pump.throughput==80 and c:levelOf(pump)==1,'a pump starts at 80 a day')
  assert(c:upgradeLevel(pump.id))
  check(c:reachBonus(pump)==0.25,'a booster pump reaches further')

  local legacy=node(c,'pole',1800,1300)
  check(c:levelOf(legacy)==2 and c:reachBonus(legacy)==0 and legacy.ports==4,'a pole from before levels keeps its stats')
  assert(c:upgradeLevel(legacy.id))
  check(legacy.ports==6 and legacy.throughput>=200 and legacy.level==3,'and is upgraded from level 2')

  local saved=assert(Save.unpack(Save.pack(c)))
  check(saved.g.nodes[j.id].level==4 and saved.g.nodes[pole.id].level==2 and saved.g.nodes[pole.id].ports==4,'levels survive saving')
end

local function mesh(redundant)
  local c=city()
  local w1=node(c,'source',1300,1300,'water',20)
  local w2=node(c,'source',1300,1500,'water',20)
  local j1=node(c,'junction',1400,1350)
  local j2=node(c,'junction',1400,1450)
  local h1=house(c,1500,1350)
  local h2=house(c,1500,1450)
  pipe(c,w1,j1); pipe(c,w2,j2); pipe(c,j1,h1); pipe(c,j2,h2)
  -- A customer takes one line, so the second feeder ties the two fittings.
  if redundant then pipe(c,j1,j2) end
  c:refresh()
  return c,{w1=w1,w2=w2,j1=j1,j2=j2,h1=h1,h2=h2}
end

-- The N-1 check.
do
  local c,n=mesh(false)
  check(c:resilienceReport()==nil,'nothing is assessed until asked')
  local r=c:assessResilience()
  check(r.base>0 and r.worst and r.worst.share>0.4,'a house on one feeder is a single point of failure')
  check(r.grade=='D' or r.grade=='F','and the grade says so')
  check(r.exposure[n.h1.id] and r.exposure[n.h2.id],'both houses are exposed')
  local rev=c.revision
  check(c.revision==rev and c.g.nodes[n.j1.id].alive,'the check leaves the real company alone')
  local _,stale=c:resilienceReport()
  check(stale==false,'a fresh check is not stale')
  c:build(1900,1900,'junction')
  local _,after=c:resilienceReport()
  check(after==true,'building anything makes the last check stale')

  local d,m=mesh(true)
  local rd=d:assessResilience()
  check(rd.grade=='A' and rd.share==0 and next(rd.exposure)==nil,'two feeders and two wells survive any single failure')
  check(d:exposureOf(m.h1.id)==false,'so no customer is exposed')
  check(rd.checked>0,'and it did check something')
end

-- Shocks come from a hash, never from the shared random stream.
do
  local c,n=mesh(true)
  signed(c,7)
  c:refresh()
  local well=n.w1
  well.output=20
  c.shock={key='drought',commodity='water',output=0.55,left=3,head='x'}
  c:refresh()
  check(well.effectiveOutput==11,'a drought holds a well to its share')
  c.shock=nil; c:refresh()
  check(well.effectiveOutput==nil,'and lets go afterwards')

  local seen,fired={},0
  for day=1,400 do
    local d=City.new({seed=31,obstacles=0})
    d.day=day
    check(d:unit(day,1)>=0 and d:unit(day,1)<1,'the unit hash stays in [0,1)')
    seen[d:unit(day,1)]=true
  end
  local distinct=0 for _ in pairs(seen) do distinct=distinct+1 end
  check(distinct>380,'the daily draw varies from day to day')

  local before=c.rng
  local report={}
  c.day=20
  for _=1,50 do c:advanceShock(report); c.shock=nil end
  check(c.rng==before,'rolling shocks consumes none of the shared random stream')

  -- Ground shift cracks mains near one point.
  local g,gn=mesh(true)
  signed(g,7)
  local hit
  for day=8,600 do
    g.day=day; g.shock=nil
    local rep={}
    g:advanceShock(rep)
    if rep.cracked then hit=rep; break end
  end
  check(hit and hit.cracked>=0 and hit.shock:find('Ground shift'),'a ground shift eventually lands')

  local small=city()
  small.day=30
  for day=8,300 do small.day=day; small:advanceShock({}) end
  check(small.shock==nil,'a company with no customers is never hit')
end

-- Secure contracts pay more and refund shortfalls.
do
  local c,n=mesh(true)
  signed(c,9)
  local found
  for _=1,120 do
    local offer=c:addClient('house',true)
    if offer and offer.secure then found=offer; break end
  end
  check(found,'some offers come as secure contracts once the company is big enough')
  check(found.rateBase==math.floor(City.CLIENTS.house.rate*City.SECURE.rate+0.5) and found.patience==2 and found.grace==2,'they pay a premium and lose patience sooner')
  local plain=city()
  local early=plain:addClient('house',true)
  check(not early.secure,'a small company is never offered one')

  n.h1.secure=true
  c:refresh()
  check(c:fullyServed(n.h1) and c:serviceCredit(n.h1)==0,'a supplied secure customer is owed nothing')
  local held=house(c,1600,1350,4)
  held.secure=true; held.rate=8; held.demands=nil
  c.served[held.id]=1
  check(c:serviceCredit(held)==(4-1)*8,'a short day refunds the missing units at their rate')
  -- Water at 8 and power at 5: a household short of both is refunded each at its own rate.
  local both=house(c,1600,1400,4)
  both.secure=true; both.rate=8; both.utilityRates={power=5}; both.demands={water=4,power=2}
  c.served[both.id]=3; c.servedBy[both.id]={water=3,power=0}
  check(c:serviceCredit(both)==math.floor(((4-3)*8+(2-0)*5)*City.SECURE.credit+0.5),'a missing utility is refunded at its own rate')
  local ordinary=house(c,1600,1450,4)
  c.served[ordinary.id]=0
  check(c:serviceCredit(ordinary)==0,'an ordinary customer is owed nothing')
end

-- The advisor prices upgrades by doing them on a copy.
do
  local E=require('experience')
  local c=city()
  local w=node(c,'source',1300,1300,'water',5); w.cap=100
  local h=house(c,1450,1300,8)
  local j0=node(c,'junction',1375,1300)
  pipe(c,w,j0)
  assert(c:layPipe(j0.id,h.id,'water','small'))
  c:refresh()
  check((c.served[h.id] or 0)<8,'a starved well leaves a customer short')
  local list=E.advise(c)
  check(#list>=1 and list[1].kind=='source' and list[1].id==w.id,'the advisor finds the well pumping flat out')
  check(list[1].net>0 and list[1].payback and list[1].cost>0,'and says what deepening earns and when it pays back')
  local p=E.sourcePreview(c,w.id)
  check(p.net==list[1].net and p.customers>=1,'the preview reports the gain and the customer it saves')
  local money,day=c.money,c.day
  E.advise(c)
  check(c.money==money and c.day==day and (w.level or 1)==1 and w.output==5,'advising changes nothing in the real company')

  local j=assert(c:build(1300,1500,'junction'))
  local lp=E.levelPreview(c,j.id)
  check(lp.cost==c:levelNext(j.id).cost and lp.cost>0 and lp.net==0,'a level preview prices the upgrade, and an idle junction earns nothing from it')

  -- A secure customer left short is refunded at the day close.
  local d,n=mesh(true)
  signed(d,9)
  n.h1.secure=true; n.h1.demand=30
  d:refresh()
  local before=d.money
  local report=d:endDay()
  check((report.credits or 0)>0 and report.expenses>=report.credits,'a short secure customer is refunded at the day close')
end

print(T.checks..' resilience and upgrade checks passed')
