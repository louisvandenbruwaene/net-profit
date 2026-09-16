-- Temporary play assistant. It plays the way a careful person would: keep the
-- mains sound, fix whoever is short, sign the best offers it can actually
-- reach, grow supply before it runs out, take on electricity once water pays,
-- buy ground when it needs more, and only then close the day.
--
-- Every move uses normal game prices and actions. Each step makes one decision
-- on a copy of the company; a plan that fails halfway is thrown away whole, so
-- nothing half built is ever left behind. A plan tried today is not tried again
-- until tomorrow, which is what guarantees the day eventually closes.
local Save=require('company_save')
local City=require('city')
local D=require('data.infrastructure')
local A={}

local MAX_ACTIONS=30        -- decisions per day before the day is closed anyway
local BUDGET=0.05           -- seconds of planning per step once one plan has run
local tried,actions={},{}   -- per company and day, never saved
local function key(c) return tostring(c.seed)..':'..c.day end
local function dist(a,b) return math.sqrt((a.x-b.x)^2+(a.y-b.y)^2) end

-- A plan builds many things in a row, and solving every network after each one
-- is nearly all the time a plan takes. On a plan's copy the solve waits until
-- something actually asks how much is flowing.
local refresh=City.refresh
local function settle(c) if c.stale then c.stale=nil; refresh(c) end end
local function spendable(c)
  settle(c)
  -- What a sensible player keeps back so one bad day is not the end.
  return c.money-math.max(200,c:dailyExpenses()*4)
end

-- Ground has to earn itself back: no district costs more than about six weeks
-- of what the company clears in a day.
local function affordableLand(c,cost)
  settle(c)
  return cost<=40*math.max(50,c:dailyRevenue()-c:dailyExpenses()) and spendable(c)>=cost
end

local packed={}
local function attempt(c,id,plan)
  if id then
    local k=key(c)
    tried[k]=tried[k] or {}
    if tried[k][id] then return nil end
    tried[k][id]=true
  end
  -- Every plan in a step starts from the same company, so it is packed once.
  if packed.city~=c then packed.city,packed.text=c,Save.pack(c) end
  packed.ran=true
  local trial=assert(Save.unpack(packed.text))
  trial.refresh=function(self) self.stale=true end
  local ok,message=pcall(plan,trial)
  if not (ok and message) then return nil end
  trial.refresh,trial.stale=nil,nil
  refresh(trial)
  actions[key(c)]=(actions[key(c)] or 0)+1
  return trial,message
end

-- Somewhere free to stand near a point, on owned ground.
local function spot(c,x,y,ok)
  for r=0,120,12 do
    for i=0,(r==0 and 0 or 15) do
      local a=i*math.pi/8
      local px,py=x+math.cos(a)*r,y+math.sin(a)*r
      if not c:placementError(px,py) and (not ok or ok(px,py)) then return px,py end
    end
  end
end

-- Everything one network reaches over live mains of one trade.
local function component(c,start,commodity)
  local seen,queue={[start]=true},{start}
  for _,id in ipairs(queue) do
    for _,e in ipairs(c.g:edgesAt(id)) do
      if e.alive and e.commodity==commodity and e.cap>0 then
        local other=e.a==id and e.b or e.a
        if not seen[other] then seen[other]=true; queue[#queue+1]=other end
      end
    end
  end
  return seen
end

local function freePort(c,n) return c:connectionPorts(n.id)<(n.ports or 1) end
local function short(c) settle(c); return c:shortCustomers() end

-- What a customer is still waiting for, by trade.
local function need(c,n)
  settle(c)
  local want={}
  for commodity,amount in pairs(n.demands or {[n.commodity]=n.demand}) do
    local got=commodity==n.commodity and (c.served[n.id] or 0) or ((c.servedBy[n.id] or {})[commodity] or 0)
    if got<amount then want[commodity]=amount-got end
  end
  return want
end

--------------------------------------------------------------------------------
-- Water
--------------------------------------------------------------------------------

local FITTING={junction=true,manifold=true,pump=true}

-- Unused output of the wells feeding a network.
local function headroom(c,seen)
  settle(c)
  local spare=0
  for id in pairs(seen) do
    local n=c.g.nodes[id]
    if n.kind=='source' and n.commodity=='water' then
      spare=spare+math.max(0,(n.effectiveOutput or n.output or 0)-(c.produced[n.id] or 0))
    end
  end
  return spare
end

-- A chain of T splits from a fitting towards a building, finishing with a main
-- into it. True only if every link went in.
local function waterChain(c,from,target,last)
  local hops=math.max(1,math.ceil(dist(from,target)/240))
  if hops>6 then return false end
  local start=from
  for i=1,hops-1 do
    local t=i/hops
    local x,y=spot(c,start.x+(target.x-start.x)*t,start.y+(target.y-start.y)*t,function(px,py) return dist(from,{x=px,y=py})<290 end)
    local n=x and c:build(x,y,'junction')
    if not n or not c:layPipe(from.id,n.id,'water','medium',nil,c.lining) then return false end
    from=n
  end
  return c:layPipe(from.id,target.id,'water',last or 'small',nil,c.lining)~=nil
end

local function connectWater(c,target,want)
  local best
  for _,n in ipairs(c.g:aliveNodes()) do
    if FITTING[n.kind] and n.id~=target.id and not c:pipeBetween(n.id,target.id,'water')
      and dist(n,target)<1400 and (not best or dist(n,target)<dist(best,target))
      and (freePort(c,n) or n.kind=='junction' and dist(n,target)<500)
      and headroom(c,component(c,n.id,'water'))>=want then best=n end
  end
  if not best then return false end
  -- A full T split becomes a hub, which is what a person does when one runs out of room.
  if not freePort(c,best) and not c:convertNode(best.id,'manifold','water') then return false end
  return waterChain(c,best,target)
end

-- The cheapest well worth deepening, deepened.
local function deepenWell(c)
  local best
  for _,w in ipairs(c.g:nodesOfKind('source')) do
    if w.commodity=='water' and (w.level or 1)<4 and (not best or c:sourceUpgradeCost(w)<c:sourceUpgradeCost(best)) then best=w end
  end
  return best and c:sourceUpgradeCost(best)<c:sourceCost('water')*1.2 and spendable(c)>=c:sourceUpgradeCost(best)
    and c:upgradeSource(best.id)~=nil
end

-- A new well on owned ground with a hub beside it, joined to the nearest
-- network when `join` asks for it so its water is not stranded.
local function newWell(c,join)
  local best
  for _,d in ipairs(c.deposits) do
    local land=c:districtAt(d.x,d.y)
    if d.commodity=='water' and not d.taken and land and land.owned and not c:sourceError('water',d.x,d.y) then
      local near=math.huge
      for _,n in ipairs(c:clientList()) do near=math.min(near,dist(n,d)) end
      if not best or near<best.near then best={d=d,near=near} end
    end
  end
  if not best or spendable(c)<c:sourceCost('water')+120 then return nil end
  local well=c:buySource('water',best.d.x,best.d.y)
  if not well then return nil end
  local x,y=spot(c,well.x+80,well.y+60)
  local hub=x and c:build(x,y,'manifold')
  if not hub or not c:layPipe(well.id,hub.id,'water','large',nil,c.lining) then return nil end
  if not join then return 'Sank a new well with a hub beside it' end
  local mine,to=component(c,hub.id,'water'),nil
  for _,n in ipairs(c.g:aliveNodes()) do
    if FITTING[n.kind] and not mine[n.id] and freePort(c,n) and dist(n,hub)<700
      and (not to or dist(n,hub)<dist(to,hub)) then to=n end
  end
  return to and waterChain(c,hub,to,'medium') and 'Sank a new well and joined it to the network' or nil
end

--------------------------------------------------------------------------------
-- Electricity
--
-- Generators send out high voltage, so a grid starts at a high voltage tower
-- fitted with a transformer. Standard towers carry medium voltage across the
-- map; a standard tower with a transformer serves workshops and feeds low
-- voltage poles, and a pole with a transformer serves homes.
--------------------------------------------------------------------------------

local function generator(n) return n.kind=='source' and n.commodity=='power' end
local function energised(c)
  local live={}
  for _,n in ipairs(c.g:aliveNodes()) do
    if generator(n) then for id in pairs(component(c,n.id,'power')) do live[id]=true end end
  end
  return live
end
local function powerSpare(c)
  settle(c)
  local spare=0
  for _,n in ipairs(c.g:aliveNodes()) do
    if generator(n) then spare=spare+math.max(0,(n.effectiveOutput or n.output or 0)-(c.produced[n.id] or 0)) end
  end
  return spare
end
local function nearestLive(c,point,test)
  local best
  for id in pairs(energised(c)) do
    local n=c.g.nodes[id]
    if test(n) and freePort(c,n) and (not best or dist(n,point)<dist(best,point)) then best=n end
  end
  return best
end

-- A tower near a point that stays within reach of what it must cable to:
-- {structure, metres} pairs.
local function tower(c,kind,x,y,upgrade,reach)
  local px,py=spot(c,x,y,function(px,py)
    for _,r in ipairs(reach or {}) do if dist(r[1],{x=px,y=py})>r[2] then return false end end
    return true
  end)
  local n=px and c:build(px,py,kind)
  if n and upgrade and not c:upgradeTower(n.id,upgrade) then return nil end
  return n or nil
end

-- Cables between towers are trunks that carry many homes, so they go in a size
-- up from the drop to a single customer.
local function cable(c,a,b,size)
  size=size or 'medium'
  if c:layPipe(a.id,b.id,'power',size,nil,c.lining) then return true end
  -- A run past the booster distance needs its last tower boosted.
  if D.towers[a.kind] and not a.upgrade and (c:pipeError(a.id,b.id,'power') or ''):find('booster') then
    return c:upgradeTower(a.id,'booster')~=nil and c:layPipe(a.id,b.id,'power',size,nil,c.lining)~=nil
  end
  return false
end

-- Standard towers from the nearest live medium voltage tower to within
-- `within` metres of a point, the last one fitted with `finish`.
local function mediumTo(c,x,y,within,finish)
  local goal={x=x,y=y}
  local from=nearestLive(c,goal,function(n) return (D.towers[n.kind] or n.kind=='transformer') and c:voltagesAt(n).medium end)
  if not from then return nil end
  if dist(from,goal)<=within and (from.upgrade==finish or from.kind=='transformer') then return from end
  local hops=math.max(1,math.ceil((dist(from,goal)-within*0.5)/170))
  if hops>12 then return nil end
  local start=from
  for i=1,hops do
    local t=math.min(1,i*170/math.max(1,dist(start,goal)))
    local reach={{from,195}}
    if i==hops then reach[2]={goal,within} end
    local n=tower(c,'pylon',start.x+(x-start.x)*t,start.y+(y-start.y)*t,i==hops and finish or nil,reach)
    if not n or not cable(c,from,n) then return nil end
    from=n
  end
  return from
end

local function connectPower(c,target)
  local voltage=c:customerVoltage(target)
  if not voltage then return false end
  local span=D.voltages[voltage].span-5
  local server=nearestLive(c,target,function(n)
    return (n.kind=='transformer' or n.upgrade=='transformer' and n.kind==(voltage=='low' and 'pole' or 'pylon'))
      and dist(n,target)<=span and not c:pipeError(n.id,target.id,'power')
  end)
  if not server and voltage=='medium' then
    server=mediumTo(c,target.x,target.y,span,'transformer')
  elseif not server then
    -- A pole with a transformer beside the house, fed at low voltage by the
    -- nearest transformer, or by a standard tower brought close enough.
    local feed=nearestLive(c,target,function(n) return n.upgrade=='transformer' and c:voltagesAt(n).low and dist(n,target)<=2*span-40 end)
      or mediumTo(c,target.x,target.y,span+50,'transformer')
    server=feed and tower(c,'pole',(feed.x+target.x)/2,(feed.y+target.y)/2,'transformer',{{feed,span},{target,span}})
    if not server or not cable(c,feed,server,'small') then return false end
  end
  return server~=nil and c:layPipe(server.id,target.id,'power','small',nil,c.lining)~=nil
end

-- Riverbank a turbine could stand on, per district. The river never moves, so
-- each district is surveyed once.
local banks={}
local function riverbank(c,d)
  local id=tostring(c.seed)..':'..d.x..':'..d.y
  if not banks[id] then
    local list={}
    for x=d.x+30,d.x+d.w-30,30 do
      for y=d.y+30,d.y+d.h-30,30 do
        local edge=c:riverEdge(x,y)
        if edge and edge>30 and edge<95 then list[#list+1]={x=x,y=y} end
      end
    end
    banks[id]=list
  end
  return banks[id]
end

-- A river turbine on owned ground. It ties into the grid there is by a high
-- voltage line, or starts one with a substation towards the customers.
local function newGenerator(c)
  if spendable(c)<c:plantCost('hydro') then return nil end
  local anchor={x=0,y=0,n=0}
  for _,n in ipairs(c:clientList()) do anchor.x,anchor.y,anchor.n=anchor.x+n.x,anchor.y+n.y,anchor.n+1 end
  if anchor.n==0 then return nil end
  anchor.x,anchor.y=anchor.x/anchor.n,anchor.y/anchor.n
  local grid=nearestLive(c,anchor,function(n) return n.kind=='hvtower' end)
  local aim,best=grid or anchor,nil
  for _,d in ipairs(c:ownedDistricts()) do
    for _,p in ipairs(riverbank(c,d)) do
      if (not best or dist(p,aim)<dist(best,aim)) and not c:sourceError('power',p.x,p.y,'hydro') then best=p end
    end
  end
  if not best or grid and dist(best,grid)>1800 then return nil end
  local plant=c:buySource('power',best.x,best.y,'hydro')
  if not plant then return nil end
  if grid then
    local from=plant
    local hops=math.max(1,math.ceil(dist(plant,grid)/280))
    for i=1,hops-1 do
      local t=i/hops
      local n=tower(c,'hvtower',plant.x+(grid.x-plant.x)*t,plant.y+(grid.y-plant.y)*t,nil,{{from,295}})
      if not n or not cable(c,from,n,'large') then return nil end
      from=n
    end
    return dist(from,grid)<=300 and cable(c,from,grid,'large') and 'Built a river turbine and tied it into the grid' or nil
  end
  local toward=math.min(1,150/math.max(1,dist(plant,anchor)))
  local hv=tower(c,'hvtower',plant.x+(anchor.x-plant.x)*toward,plant.y+(anchor.y-plant.y)*toward,'transformer',{{plant,295}})
  return hv and cable(c,plant,hv,'large') and 'Built a river turbine and a grid substation' or nil
end

-- A river district next door, for a licensed company with no river of its own.
local function riverDistrict(c)
  local best
  for _,d in ipairs(c.districts) do
    if not d.owned and c:districtAdjacent(d) and not c:districtError(d.id) and #riverbank(c,d)>0
      and (not best or c:districtCost(d)<c:districtCost(best)) then best=d end
  end
  return best
end

--------------------------------------------------------------------------------
-- Customers
--------------------------------------------------------------------------------

-- The nearest full main between a customer and its supply. Another
-- customer's own stub is full because that customer is supplied, not because
-- it is in the way, so those are passed over.
local function bottleneck(c,n,commodity)
  settle(c)
  local seen,queue={[n.id]=true},{n.id}
  for _,id in ipairs(queue) do
    for _,ei in ipairs(c.g.adj[id] or {}) do
      local e=c.g.edges[ei]
      local other=e.a==id and e.b or e.a
      local far=c.g.nodes[other]
      if e.alive and e.commodity==commodity and not seen[other] and (far.kind~='client' or other==n.id) then
        if math.abs(c.detail.edge[ei] or 0)>=(e.effectiveCap or e.cap) then return e end
        seen[other]=true; queue[#queue+1]=other
      end
    end
  end
end

-- Make one signed customer whole: diagnose, fix the one thing in the way, and
-- look again, a few times over.
local function serve(c,n)
  for _=1,6 do
    local commodity,want=next(need(c,n))
    if not commodity then return true end
    local why=c:constraintFor(n.id)
    local e=why=='main' and bottleneck(c,n,commodity)
    if why=='main' and not e then why='output' end
    local edge=e and e.id
    if why=='valve' then c:toggleSupply(n.id)
    elseif why=='main' then
      -- Widen the full main, or when it cannot be widened (a customer only
      -- takes a small one) bring in a second route beside it.
      local bigger=c:biggerSize(e)
      if not (bigger and c:replacePipe(edge,bigger,e.grade))
        and not (commodity=='water' and connectWater(c,n,want) or commodity=='power' and connectPower(c,n)) then return false end
    elseif why=='output' and commodity=='water' then
      if not deepenWell(c) and not newWell(c,true) then return false end
    elseif why=='output' and commodity=='power' then
      if not newGenerator(c) then return false end
    elseif commodity=='water' then
      if not connectWater(c,n,want) then return false end
    elseif commodity=='power' then
      if powerSpare(c)<want and not newGenerator(c) then return false end
      if not connectPower(c,n) then return false end
    else return false end
  end
  return next(need(c,n))==nil
end

-- Sign an offer and connect it, as long as nobody already signed goes short.
-- A new connection can pull water or power away from a neighbour on the same
-- main, so that is put right as part of the same plan.
local function sign(c,id)
  local before={}
  for _,x in ipairs(short(c)) do before[x.id]=true end
  local n=c.g.nodes[id]
  if not c:acceptClient(id) or not serve(c,n) then return false end
  for _=1,3 do
    local hurt
    for _,x in ipairs(short(c)) do if not before[x.id] then hurt=x end end
    if not hurt then return true end
    if not (serve(c,hurt) and serve(c,n)) then return false end
  end
  for _,x in ipairs(short(c)) do if not before[x.id] then return false end end
  return true
end

local TRADES={water=true,power=true}
local function servable(c,n)
  for commodity in pairs(n.demands or {[n.commodity]=n.demand}) do
    if not TRADES[commodity] or not c:licensed(commodity) then return false end
  end
  return not n.powerRequest or c.licences.power
end

--------------------------------------------------------------------------------
-- One decision
--------------------------------------------------------------------------------

function A.step(city)
  if city.bankrupt then return city,'Company has stopped trading',true end
  local c=city
  local k=key(c)
  if A.day~=k then tried,actions,A.day={},{},k end
  local function close()
    local closed=assert(Save.unpack(Save.pack(c)))
    closed:endDay()
    return closed,'Day '..closed.day..': $'..closed.money,closed.bankrupt
  end
  if (actions[k] or 0)>=MAX_ACTIONS then return close() end
  -- Planning is spread over several steps so the game never stalls on one.
  -- Each step gets at least one plan in, and a plan is never tried twice in a
  -- day, so the day always moves on.
  local deadline=os.clock()+BUDGET
  packed.ran=false
  local function late() return packed.ran and os.clock()>deadline end
  local function try(id,plan)
    if late() then return nil end
    return attempt(c,id,plan)
  end

  -- The opening: a well on the marked spring and a T split towards the house.
  if #c.g:nodesOfKind('source')==0 then
    local springs={}
    for _,d in ipairs(c.deposits) do
      local land=c:districtAt(d.x,d.y)
      if d.commodity=='water' and not d.taken and land and land.owned then springs[#springs+1]=d end
    end
    table.sort(springs,function(a,b) return (a.opening and 1 or 0)>(b.opening and 1 or 0) end)
    for _,d in ipairs(springs) do
      local done,msg=attempt(c,'spring'..d.x..':'..d.y,function(t)
        local well=t:buySource('water',d.x,d.y)
        if not well then return end
        local house=t:clientList(true)[1] or {x=well.x+90,y=well.y+60}
        local x,y=spot(t,(well.x+house.x)/2,(well.y+house.y)/2)
        local split=x and t:build(x,y,'junction')
        return split and t:layPipe(well.id,split.id,'water','large') and 'Built a well and a T split'
      end)
      if done then return done,msg end
    end
    if c.money<c:sourceCost('water') then return city,'Not enough cash for a well; autoplay paused',true end
    return city,'No buildable well site; autoplay paused',true
  end

  local done,msg
  local function did(d,m) done,msg=d,m; return d~=nil end

  -- 1. Sound mains and no debt before anything new.
  local bill,broken=c:repairAllCost()
  if broken>0 and c.money>=bill and did(try('repair',function(t) return t:repairAll() and 'Repaired '..broken..' lines' end)) then return done,msg end
  if (c.loan or 0)>0 and spendable(c)>0
    and did(try('repay',function(t) return t:repay(math.min(t.loan,spendable(t))) and 'Repaid part of the loan' end)) then return done,msg end

  -- 2. Whoever is signed and short comes first: they are the ones about to leave.
  local waiting=short(c)
  table.sort(waiting,function(a,b) return (a.grace or 9)<(b.grace or 9) end)
  for _,n in ipairs(waiting) do
    if did(try('serve'..n.id,function(t) return serve(t,t.g.nodes[n.id]) and 'Restored supply to a customer' end)) then return done,msg end
  end

  -- 3. Offers, best price first: sign the ones the network can actually carry.
  local offers={}
  for _,n in ipairs(c:clientList(true)) do offers[#offers+1]=n end
  for _,n in ipairs(c:clientList()) do if n.powerRequest then offers[#offers+1]=n end end
  table.sort(offers,function(a,b) return c:requestPremium(a)>c:requestPremium(b) end)
  for _,n in ipairs(offers) do
    if servable(c,n) and c:requestPremium(n)>-0.3 and spendable(c)>0 then
      local what=n.powerRequest and 'Connected electricity to a household'
        or 'Signed and connected a '..string.lower(City.CLIENTS[n.clientType].name)
      if did(try('offer'..n.id,function(t) return sign(t,n.id) and what end)) then return done,msg end
    end
  end
  if late() then return city,'Weighing offers' end
  -- An offer it cannot serve is declined on its last day: a refusal costs less
  -- reputation than letting it lapse.
  for _,n in ipairs(c:clientList(true)) do
    if n.expires<=c.day and did(attempt(c,'decline'..n.id,function(t) return t:declineClient(n.id) and 'Declined an offer it could not serve' end)) then return done,msg end
  end

  -- 4. Supply ahead of demand.
  local thirst=0
  for _,n in ipairs(c:clientList(true)) do if n.commodity=='water' then thirst=thirst+n.demand end end
  for _,n in ipairs(waiting) do thirst=thirst+(need(c,n).water or 0) end
  if (c.spare.water or 0)<math.max(6,thirst) then
    if did(try('deepen',function(t) return deepenWell(t) and 'Deepened a well' end))
      or did(try('well-join',function(t) return newWell(t,true) end))
      or did(try('well',function(t) return newWell(t,false) end)) then return done,msg end
  end
  local power=0
  for _,n in ipairs(offers) do
    if n.powerRequest then power=power+(n.clientType=='estate' and 4 or 2)
    elseif n.commodity=='power' then power=power+n.demand end
  end
  if c.licences.power and power>0 and powerSpare(c)<math.min(power,16) and spendable(c)>=c:plantCost('hydro')+1500 then
    if did(try('generator',newGenerator)) then return done,msg end
    local river=riverDistrict(c)
    if river and affordableLand(c,c:districtCost(river)+c:plantCost('hydro')+1500)
      and did(try('river',function(t) return t:buyDistrict(river.id) and 'Bought '..river.name..' for its river' end)) then return done,msg end
  end

  -- 5. Growing the company once today's work is done.
  -- Once licensed, new houses ask for electricity as well as water, so the
  -- licence waits until the company can afford to build a grid for them.
  if not c.licences.power and #c:clientList()>=25 and spendable(c)>=City.price.powerLicence+12000
    and did(try('licence',function(t) return t:buyLicence('power') and 'Bought the electricity licence' end)) then return done,msg end
  local pipes=0
  for _,e in ipairs(c.g.edges) do if e.alive then pipes=pipes+1 end end
  if (c.crews or 0)<math.min(City.crewMax,math.floor(pipes/15)) and spendable(c)>=City.crewHire+300
    and did(try('crew',function(t) return t:hireCrew() and 'Hired a maintenance crew' end)) then return done,msg end
  local grade=City.GRADES[(c.lining or 1)+1]
  if grade and pipes>=25 and spendable(c)>=grade.price*4
    and did(try('lining',function(t) return t:upgradeQuality() and 'Unlocked '..grade.name..' pipes' end)) then return done,msg end
  -- More ground when the wells have nowhere left to go or the offers have
  -- dried up, bought only with money the company does not need.
  local freeSpring=false
  for _,d in ipairs(c.deposits) do
    local land=c:districtAt(d.x,d.y)
    if d.commodity=='water' and not d.taken and land and land.owned then freeSpring=true end
  end
  if not freeSpring or #c:clientList(true)==0 then
    local best,bestSprings
    for _,d in ipairs(c.districts) do
      if not d.owned and not d.island and c:districtAdjacent(d) and not c:districtError(d.id) then
        local springs=0
        for _,s in ipairs(c.deposits) do
          if s.commodity=='water' and not s.taken and s.x>=d.x and s.x<d.x+d.w and s.y>=d.y and s.y<d.y+d.h then springs=springs+1 end
        end
        if not best or springs>bestSprings or springs==bestSprings and c:districtCost(d)<c:districtCost(best) then best,bestSprings=d,springs end
      end
    end
    if best and affordableLand(c,c:districtCost(best)*2.5)
      and did(try('land',function(t) return t:buyDistrict(best.id) and 'Bought '..best.name end)) then return done,msg end
  end
  -- Idle cash works: a slice of a large surplus goes into the weekly market,
  -- one modest placement at a time.
  local surplus=spendable(c)-20000
  if surplus>5000 and c:investedTotal()==0 then
    local amount=math.floor(math.min(50000,surplus*0.25))
    if did(try('invest',function(t) return t:invest(amount) and 'Invested $'..amount end)) then return done,msg end
  end
  if late() then return city,'Planning' end
  return close()
end

return A
