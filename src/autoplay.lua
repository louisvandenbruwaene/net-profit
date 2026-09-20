-- Temporary play assistant. It plays the way a careful person would: keep the
-- mains sound, fix whoever is short, sign the best offers it can actually
-- reach, and grow supply before it runs out. Then it grows the company the way
-- the game opens up: electricity, a freight hub to land materials and imported
-- trades, area hubs, roads with tolled highways, buses between towns, resorts,
-- filters, staff and more ground, and only then closes the day.
--
-- Every move uses normal game prices and actions. Each step makes one decision
-- on a copy of the company; a plan that fails halfway is thrown away whole, so
-- nothing half built is ever left behind. A plan tried today is not tried again
-- until tomorrow, which is what guarantees the day eventually closes.
local Save=require('company_save')
local City=require('city')
local Graph=require('graph')
local D=require('data.infrastructure')
local NB=require('network_builder')
local A={}

local MAX_ACTIONS=30        -- decisions per day before the day is closed anyway
A.budget=0.05               -- seconds of planning per step once one plan has run
local tried,actions={},{}   -- per company and day, never saved
local function key(c) return tostring(c.seed)..':'..c.day end
local dist=NB.dist

-- A plan builds many things in a row, and solving every network after each one
-- is nearly all the time a plan takes. On a plan's copy the solve waits until
-- something actually asks how much is flowing.
local refresh=City.refresh
local function settle(c) if c.stale then c.stale=nil; refresh(c) end end
local function net(c) settle(c); return c:dailyRevenue()-c:dailyExpenses() end
local function spendable(c)
  settle(c)
  -- What a sensible player keeps back so one bad day is not the end.
  return c.money-math.max(200,c:dailyExpenses()*4)
end
-- A project has to earn itself back: nothing costs more than about six weeks of
-- what the company clears in a day, and the cash has to be there as well.
local function worth(c,cost) return spendable(c)>=cost and cost<=40*math.max(60,net(c)) end

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

-- Somewhere free to stand near a point, on owned ground; a chain of T splits
-- from a fitting to a target; and the nearest fitting worth starting from.
-- Shared with the hub, which runs the same builder against the player's own
-- network -- see src/network_builder.lua.
local spot,place,carries,component=NB.spot,NB.place,NB.carries,NB.component

local haul -- a plan may need a trade landed at the road head
local function freePort(c,n) return c:connectionPorts(n.id)<(n.ports or 1) end
local function short(c) settle(c); return c:shortCustomers() end
local function count(c,kind) return #c.g:nodesOfKind(kind) end

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

local function centroid(list)
  local x,y=0,0
  for _,n in ipairs(list) do x,y=x+n.x,y+n.y end
  return {x=x/math.max(1,#list),y=y/math.max(1,#list)}
end

--------------------------------------------------------------------------------
-- Pipes: water from wells, and beer, oil and petrol landed at a haven
--------------------------------------------------------------------------------

local FITTING=NB.FITTING
local chain=NB.chain

-- Unused output of the wells feeding a network, or plenty if a haven feeds it:
-- the outside world does not run out. A trial copy may be stale, so settle it
-- first; the real company (see City:recomputeHubs) never needs to.
local function headroom(c,seen,commodity)
  settle(c)
  return NB.headroom(c,seen,commodity)
end

-- A trial copy may still be stale from an earlier step in the same plan;
-- settle it once up front so every headroom check the search makes below sees
-- this trial's own numbers, not last plan's.
local function connectPipe(c,target,want,commodity,last,mid)
  settle(c)
  return NB.connectPipe(c,target,want,commodity,last,mid)
end

-- Another unit on a source the company already has, taken whenever that is
-- cheaper per unit of supply than commissioning a fresh one somewhere else.
--
-- This is the single rule that decides the shape of the whole network. A unit
-- added here needs no new ground, no new route and no new tie-ins, so a
-- company that follows it grows a few deep sources feeding a tree of mains
-- rather than a field of half-used stubs each on its own stub of pipe.
local function extendSource(c,commodity)
  local best,bestRate
  for _,w in ipairs(c.g:nodesOfKind('source')) do
    if w.alive and (w.commodity or 'water')==commodity
       and (w.level or 1)<c:maxLevel(w) and (w.output or 0)<(w.cap or math.huge) then
      local cost=c:sourceUpgradeCost(w)
      local step=c:upgradeStep(w)
      if cost and step and step>0 and (not bestRate or cost/step<bestRate) then
        best,bestRate=w,cost/step
      end
    end
  end
  if not best then return nil end
  local cost=c:sourceUpgradeCost(best)
  if spendable(c)<cost then return nil end
  -- The alternative, priced the same way: what a second source of the same
  -- kind costs for the supply it brings, before any of the mains out to it.
  local fresh,step
  if commodity=='power' then
    local kind=best.plant or 'hydro'
    fresh,step=c:plantCost(kind),(City.PLANTS[kind] or {}).output
  else
    fresh,step=c:sourceCost(commodity),(City.trade[commodity] or City.trade.water).sourceOutput
  end
  if step and step>0 and bestRate>fresh/step then return nil end
  return c:upgradeSource(best.id)~=nil
end

-- Where the heart goes: a stretch of bank the company owns, with room on it
-- for a treatment works. Filled in below, once the bank walker exists.
local intakeSite

-- The nearest untaken water deposit on owned ground, and how far off it is.
local function spring(c,to)
  local best,far
  for _,d in ipairs(c.deposits) do
    local land=c:districtAt(d.x,d.y)
    if d.commodity=='water' and not d.taken and land and land.owned and not c:sourceError('water',d.x,d.y) then
      local near=math.huge
      if to then near=dist(to,d) else for _,n in ipairs(c:clientList()) do near=math.min(near,dist(n,d)) end end
      if not best or near<far then best,far=d,near end
    end
  end
  return best,far
end
-- A new source on owned ground with a hub beside it, joined to the nearest
-- network when `join` asks for it so its water is not stranded.
local function newWell(c,join,to)
  -- One intake, sited on running water, before any well is sunk on a field.
  -- After that the cost ladder makes the second one a bad idea on its own.
  -- A caller asking for supply next to something specific still gets it there:
  -- an intake on the far bank is no use to a hub that has to reach it.
  local best
  if (c.intakesBought or 0)==0 then
    local site=intakeSite(c)
    if site and (not to or dist(site,to)<1300) then best=site end
  end
  best=best or spring(c,to)
  if not best or spendable(c)<c:sourceCost('water',best.x,best.y)+120 then return nil end
  local well=c:buySource('water',best.x,best.y)
  if not well then return nil end
  local hub=place(c,'manifold',well.x+80,well.y+60)
  if not hub or not c:layPipe(well.id,hub.id,'water','large',nil,c.lining) then return nil end
  if to then return chain(c,hub,to,'water','large','large') and 'Sank a well for a hub' or nil end
  if not join then return 'Sank a new well with a hub beside it' end
  local mine,to=component(c,hub.id,'water'),nil
  for _,n in ipairs(c.g:aliveNodes()) do
    if FITTING[n.kind] and not mine[n.id] and freePort(c,n) and dist(n,hub)<700
      and (not to or dist(n,hub)<dist(to,hub)) then to=n end
  end
  return to and chain(c,hub,to,'water','medium') and 'Sank a new well and joined it to the network' or nil
end

--------------------------------------------------------------------------------
-- Electricity
--
-- Generators send out high voltage, so a grid starts at a high voltage tower
-- fitted with a transformer. Standard towers carry medium voltage across the
-- map; a standard tower with a transformer serves workshops, hubs and low
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
  local n=place(c,kind,x,y,nil,function(px,py)
    for _,r in ipairs(reach or {}) do if dist(r[1],{x=px,y=py})>r[2] then return false end end
    return true
  end)
  if n and upgrade and not c:upgradeTower(n.id,upgrade) then return nil end
  return n
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
  return server~=nil and c:layPipe(server.id,target.id,'power',voltage=='medium' and 'medium' or 'small',nil,c.lining)~=nil
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

-- The heart's site, from the banks the company already owns. A works needs
-- room around it the way any structure does, so the first stretch of bank that
-- will take one is the answer and the search stops there.
local sites={}
function intakeSite(c)
  local id=tostring(c.seed)..':'..(c.districtsBought or 0)
  -- A site only stops being a site because something was built on top of it,
  -- so the cached one is re-checked and the bank is only walked again when it
  -- has actually gone. Walking it costs a spacing test against every structure
  -- on the map, which is not a thing to do once per plan.
  local held=sites[id]
  if held and not c:sourceError('water',held.x,held.y) then return held end
  if held==false then return nil end
  sites[id]=false
  for _,d in ipairs(c:ownedDistricts()) do
    for _,p in ipairs(riverbank(c,d)) do
      if sites[id]==false and c:intakeCap(p.x,p.y) and not c:sourceError('water',p.x,p.y) then
        sites[id]=p
      end
    end
  end
  return sites[id] or nil
end

-- Another power station, whichever is cheaper per unit of electricity: a river
-- turbine on owned riverbank, or a wind park built from landed steel and
-- concrete. It ties into the grid there is by a high voltage line, or starts
-- one with a substation towards the customers.
local function newGenerator(c)
  local clients=c:clientList()
  if #clients==0 then return nil end
  local anchor=centroid(clients)
  local grid=nearestLive(c,anchor,function(n) return n.kind=='hvtower' end)
  if not grid and next(energised(c)) then
    -- Every high voltage tower is full: a new substation beside a standard
    -- tower joins the grid there instead of starting a second, separate one.
    local pylon=nearestLive(c,anchor,function(n) return n.kind=='pylon' end)
    grid=pylon and tower(c,'hvtower',pylon.x+60,pylon.y-60,'transformer',{{pylon,190}})
    if not grid or not cable(c,grid,pylon) then return nil end
  end
  local aim,best,plant=grid or anchor,nil,'hydro'
  for _,d in ipairs(c:ownedDistricts()) do
    for _,p in ipairs(riverbank(c,d)) do
      if (not best or dist(p,aim)<dist(best,aim)) and not c:sourceError('power',p.x,p.y,'hydro') then best=p end
    end
  end
  if best and grid and dist(best,grid)>1800 then best=nil end
  local windy=count(c,'dc')>0 and c:plantCost('wind')/City.PLANTS.wind.output<c:plantCost('hydro')/City.PLANTS.hydro.output
  if (windy or not best) and haul(c,'concrete') and not c:materialError(City.MATERIALS.wind) then
    local x,y=spot(c,aim.x+220,aim.y+160,function(px,py) return not c:sourceError('power',px,py,'wind') end,400)
    if x then best,plant={x=x,y=y},'wind' end
  end
  if not best or spendable(c)<c:plantCost(plant) then return nil end
  local station=c:buySource('power',best.x,best.y,plant)
  if not station then return nil end
  local name=plant=='wind' and 'a wind park' or 'a river turbine'
  if grid then
    local from=station
    local hops=math.max(1,math.ceil(dist(station,grid)/280))
    for i=1,hops-1 do
      local t=i/hops
      local n=tower(c,'hvtower',station.x+(grid.x-station.x)*t,station.y+(grid.y-station.y)*t,nil,{{from,295}})
      if not n or not cable(c,from,n,'large') then return nil end
      from=n
    end
    return dist(from,grid)<=300 and cable(c,from,grid,'large') and 'Built '..name..' and tied it into the grid' or nil
  end
  local toward=math.min(1,150/math.max(1,dist(station,anchor)))
  local hv=tower(c,'hvtower',station.x+(anchor.x-station.x)*toward,station.y+(anchor.y-station.y)*toward,'transformer',{{station,295}})
  return hv and cable(c,station,hv,'large') and 'Built '..name..' and a grid substation' or nil
end

--------------------------------------------------------------------------------
-- Customers
--------------------------------------------------------------------------------

-- The nearest full main or freight line between a customer and its supply.
-- Another customer's own stub is full because that customer is supplied, not
-- because it is in the way, so those are passed over.
local function bottleneck(c,n,commodity)
  settle(c)
  local seen,queue={[n.id]=true},{n.id}
  for _,id in ipairs(queue) do
    for _,ei in ipairs(c.g.adj[id] or {}) do
      local e=c.g.edges[ei]
      local other=e.a==id and e.b or e.a
      local far=c.g.nodes[other]
      if e.alive and carries(e,commodity) and not seen[other] and (far.kind~='client' or other==n.id) then
        local flow=math.abs((((c.edgeFlowBy or {})[commodity] or {})[ei]) or c.detail.edge[ei] or 0)
        if flow>=(e.wagons and e.wagons[commodity] or e.effectiveCap or e.cap) then return e end
        seen[other]=true; queue[#queue+1]=other
      end
    end
  end
end

-- Make one signed customer (or a hub) whole: diagnose, fix the one thing in the
-- way, and look again, a few times over.
local function serve(c,n)
  for _=1,6 do
    local commodity,want=next(need(c,n))
    if not commodity then return true end
    local why=c:constraintFor(n.id)
    local e=why=='main' and bottleneck(c,n,commodity)
    if why=='main' and not e then why='output' end
    if why=='valve' then c:toggleSupply(n.id)
    elseif why=='main' then
      -- Widen the full main, or when it cannot be widened (a customer only
      -- takes a small one) bring in a second route beside it.
      local bigger=not e.bulk and c:biggerSize(e)
      if not (bigger and c:replacePipe(e.id,bigger,e.grade))
        and not (commodity=='power' and connectPower(c,n) or commodity~='power' and connectPipe(c,n,want,commodity)) then return false end
    elseif why=='output' and commodity=='water' then
      if not extendSource(c,'water') and not newWell(c,true) then return false end
    elseif why=='output' and commodity=='power' then
      if not newGenerator(c) then return false end
    elseif commodity=='power' then
      if powerSpare(c)<want and not newGenerator(c) then return false end
      if not connectPower(c,n) then return false end
    elseif Graph.formOf(commodity)=='liquid' then
      if not connectPipe(c,n,want,commodity) then return false end
    else return false end
  end
  return next(need(c,n))==nil
end

-- Sign an offer and connect it, as long as nobody already signed goes short.
-- A new connection can pull supply away from a neighbour on the same main, so
-- that is put right as part of the same plan.
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

local function servable(c,n)
  for commodity in pairs(n.demands or {[n.commodity]=n.demand}) do
    if not c:licensed(commodity) then return false end
    if commodity~='water' and commodity~='power' and not (Graph.formOf(commodity)=='liquid' and count(c,'dc')>0) then return false end
  end
  return not n.powerRequest or c.licences.power
end

--------------------------------------------------------------------------------
-- Freight: a road head, a yard, and trucks between them
--------------------------------------------------------------------------------

local function yard(c) return c.g:nodesOfKind('dc')[1] end
local function freightLine(c)
  for _,e in ipairs(c.g.edges) do if e.alive and e.bulk then return e end end
end
-- Landed goods a plan will need: one more wagon on the line for a trade it
-- does not carry yet.
function haul(c,commodity)
  local line=freightLine(c)
  if not line then return false end
  return (line.wagons or {})[commodity]~=nil or c:addWagon(line.id,commodity)~=nil
end

local function freightHub(c)
  local clients=c:clientList()
  local middle=centroid(clients)
  local depot=place(c,'dc',middle.x+160,middle.y+140,nil,nil,400)
  if not depot then return nil end
  local haven
  for _,a in ipairs({0,1,2,3,4,5,6,7}) do
    haven=place(c,'terminal',depot.x+math.cos(a*math.pi/4)*260,depot.y+math.sin(a*math.pi/4)*260,'highway',
      function(px,py) return dist(depot,{x=px,y=py})<400 end)
    if haven then break end
  end
  if not haven then return nil end
  local held=c.buildRoadType
  c.buildRoadType='road'
  local road=c:layLink(haven.id,depot.id,'road')
  c.buildRoadType=held
  if not road or not c:layPipe(haven.id,depot.id,'steel',2,'highway') then return nil end
  return 'Opened a road head and a freight yard with trucks for steel'
end

-- An oil rig on an owned field, in a district with no wells for it to foul,
-- piped into the oil network so the company stops paying for landed crude.
local function newRig(c)
  local depot=yard(c)
  if not (depot and haul(c,'oil')) then return nil end
  local best
  for _,d in ipairs(c.deposits) do
    local land=c:districtAt(d.x,d.y)
    if d.commodity=='oil' and not d.taken and land and land.owned and dist(d,depot)<1400 and not c:sourceError('oil',d.x,d.y) then
      local wells=false
      for _,w in ipairs(c.g:nodesOfKind('source')) do wells=wells or w.commodity=='water' and c:districtAt(w.x,w.y)==land end
      if not wells and (not best or dist(d,depot)<dist(best,depot)) then best=d end
    end
  end
  if not best then return nil end
  local rig=c:buySource('oil',best.x,best.y)
  local hub=rig and place(c,'manifold',rig.x+80,rig.y+60)
  if not hub or not c:layPipe(rig.id,hub.id,'oil','large',nil,c.lining) then return nil end
  local mine,to=component(c,hub.id,'oil'),nil
  for _,n in ipairs(c.g:aliveNodes()) do
    if (n.kind=='dc' or FITTING[n.kind]) and not mine[n.id] and freePort(c,n) and dist(n,hub)<1400
      and headroom(c,component(c,n.id,'oil'),'oil')>0 and (not to or dist(n,hub)<dist(to,hub)) then to=n end
  end
  return to and chain(c,hub,to,'oil','medium') and 'Sank an oil rig and piped it into the network' or nil
end

-- An environment lab for a district whose wells are about to be fouled.
local function lab(c)
  for _,d in ipairs(c:ownedDistricts()) do
    local covered=false
    for _,n in ipairs(c.g:nodesOfKind('lab')) do covered=covered or c:labCovers(n,d) end
    if (d.pollution or 0)>=D.pollution.stopAt*0.5 and not covered then
      return place(c,'lab',d.x+d.w/2,d.y+d.h/2,nil,nil,300) and 'Built an environment lab in '..d.name or nil
    end
  end
end

--------------------------------------------------------------------------------
-- Area hubs: a neighbourhood served without a main to every house
--------------------------------------------------------------------------------

local function areaHub(c)
  local hubs=c.g:nodesOfKind('exchange')
  local offers={}
  -- A hub is built at level 1, so that is how far a new one will reach.
  local reach=City.LEVELS.LEVELS.hub[1].radius
  for _,n in ipairs(c:clientList(true)) do
    local covered=false
    for _,h in ipairs(hubs) do covered=covered or dist(h,n)<c:hubRadius(h) end
    if not covered and servable(c,n) then offers[#offers+1]=n end
  end
  local group
  for _,n in ipairs(offers) do
    local near={}
    for _,m in ipairs(offers) do if dist(n,m)<reach*0.8 then near[#near+1]=m end end
    if not group or #near>#group then group=near end
  end
  if not group or #group<3 then return nil end
  -- A hub picks up everyone in reach. Landed beer and oil come in by the
  -- truckload, not by the neighbourhood, so a hub only goes where everyone it
  -- would take needs water or electricity.
  local middle=centroid(group)
  for _,n in ipairs(c.g.nodes) do
    if n.alive and n.kind=='client' and c.g:degree(n.id)==0 and dist(n,middle)<=reach+200 then
      for commodity in pairs(n.demands or {[n.commodity]=n.demand}) do
        if commodity~='water' and commodity~='power' then return nil end
      end
    end
  end
  local before={}
  for _,x in ipairs(short(c)) do before[x.id]=true end
  local hub=place(c,'exchange',middle.x,middle.y,nil,nil,200)
  if not hub then return nil end
  settle(c)
  for commodity in pairs(hub.demandBy or {}) do
    if commodity=='power' then
      if not connectPower(c,hub) then return nil end
    elseif commodity=='water' then
      -- A hub is a neighbourhood's worth of demand: it gets a well of its own
      -- where there is one to sink, rather than drawing on somebody else's.
      local _,far=spring(c,hub)
      if not (far and far<1300 and newWell(c,false,hub) or connectPipe(c,hub,0,commodity,'large','large')) then return nil end
    elseif not connectPipe(c,hub,0,commodity,'large','large') then return nil end
  end
  -- The hub now answers for everyone it picked up, so its feed and its supply
  -- are brought up to what they take.
  for _=1,5 do
    settle(c)
    local shortfall
    for commodity,want in pairs(hub.demandBy or {}) do
      if (((c.detail.hub or {})[hub.id] or {})[commodity] or 0)<want then shortfall=commodity end
    end
    if not shortfall then break end
    local feed=bottleneck(c,hub,shortfall)
    local bigger=feed and not feed.bulk and c:biggerSize(feed)
    if not (bigger and c:replacePipe(feed.id,bigger,feed.grade)) then
      if shortfall=='water' then
        if not extendSource(c,'water') and not newWell(c,true) then return nil end
      elseif shortfall=='power' then
        if not newGenerator(c) then return nil end
      else return nil end
    end
  end
  -- Whoever the hub's draw left short on the old mains is put right as well.
  for _,x in ipairs(short(c)) do
    if not before[x.id] and not x.hub and not serve(c,x) then return nil end
  end
  for _,x in ipairs(short(c)) do if not before[x.id] then return nil end end
  return #(hub.covered or {})>=3 and 'Built an area hub serving '..#hub.covered..' customers' or nil
end

--------------------------------------------------------------------------------
-- Roads: households on offroads to an interchange, interchanges joined by a
-- tolled highway, a filling station where there is petrol to sell
--------------------------------------------------------------------------------

local function withRoad(c,variant,fn)
  local held=c.buildRoadType
  c.buildRoadType=variant
  local ok,a,b=pcall(fn)
  c.buildRoadType=held
  if not ok then error(a) end
  return a,b
end
local function onRoad(c,id)
  for _,l in ipairs(c.links or {}) do if l.alive and l.mode=='road' and (l.a==id or l.b==id) then return true end end
  return false
end
local HOUSEHOLD={house=true,estate=true,home=true,subscriber=true}

-- Seven households nobody has put on a road yet, around the one furthest from
-- the interchanges already standing, onto a new interchange in their middle.
local function roadCluster(c)
  local interchanges=c.g:nodesOfKind('interchange')
  local loose={}
  for _,n in ipairs(c:clientList()) do
    if HOUSEHOLD[n.clientType] and not onRoad(c,n.id) then loose[#loose+1]=n end
  end
  if #loose<4 then return nil end
  local seed,far
  for _,n in ipairs(loose) do
    local d=math.huge
    for _,i in ipairs(interchanges) do d=math.min(d,dist(i,n)) end
    if not far or d>far then seed,far=n,d end
  end
  table.sort(loose,function(a,b) return dist(a,seed)<dist(b,seed) end)
  local group={}
  for i=1,math.min(7,#loose) do if dist(loose[i],seed)<700 then group[#group+1]=loose[i] end end
  if #group<4 then return nil end
  local middle=centroid(group)
  local hub=place(c,'interchange',middle.x,middle.y,nil,nil,200)
  if not hub then return nil end
  local joined=0
  for _,n in ipairs(group) do
    if withRoad(c,'offroad',function() return c:layLink(n.id,hub.id,'road') end) then joined=joined+1 end
  end
  return joined>=3 and 'Put '..joined..' households on offroads to a new interchange' or nil
end

-- A tolled highway between the two nearest interchanges that no road joins yet.
local function highway(c)
  local list=c.g:nodesOfKind('interchange')
  local best
  for i=1,#list do
    for j=i+1,#list do
      local a,b=list[i],list[j]
      if dist(a,b)<=City.PEOPLE.roadRange and freePort(c,a) and freePort(c,b) and not c:roadPath(a.id,b.id,'car')
        and (not best or dist(a,b)<dist(best[1],best[2])) then best={a,b} end
    end
  end
  if not best then return nil end
  local road=withRoad(c,'highway',function() return c:layLink(best[1].id,best[2].id,'road') end)
  if not road then return nil end
  c:setLinkPrice(road.id,8)
  return 'Joined two interchanges with a tolled highway'
end

-- A filling station on the way into an interchange, fed with petrol landed at
-- the road head.
local function station(c)
  local line=freightLine(c)
  if not line then return nil end
  for _,i in ipairs(c.g:nodesOfKind('interchange')) do
    local fed=false
    for _,l in ipairs(c.links or {}) do
      if l.alive and (l.a==i.id or l.b==i.id) then
        local other=c.g.nodes[l.a==i.id and l.b or l.a]
        fed=fed or other.kind=='station'
      end
    end
    if not fed and freePort(c,i) then
      if not haul(c,'gasoline') then return nil end
      local s=place(c,'station',i.x+70,i.y+50)
      if not s then return nil end
      c:setStationPrice(s.id,8)
      if not withRoad(c,'road',function() return c:layLink(i.id,s.id,'road') end) then return nil end
      -- Households on this interchange now drive through the station.
      for _,l in ipairs(c.links) do
        if l.alive and l.mode=='road' and l.roadType=='offroad' and (l.a==i.id or l.b==i.id) and freePort(c,s) then
          local house=l.a==i.id and l.b or l.a
          c:demolishLink(l.id)
          if not withRoad(c,'offroad',function() return c:layLink(house,s.id,'road') end) then return nil end
        end
      end
      return connectPipe(c,s,1,'gasoline') and 'Opened a filling station on the way into an interchange' or nil
    end
  end
end

--------------------------------------------------------------------------------
-- Buses between towns, and resorts for them to visit
--------------------------------------------------------------------------------

local function stopIn(c,d)
  for _,s in ipairs(c.g:nodesOfKind('stop')) do
    if s.x>=d.x and s.x<d.x+d.w and s.y>=d.y and s.y<d.y+d.h then return s end
  end
  return place(c,'stop',d.x+d.w/2,d.y+d.h/2,nil,nil,250)
end

local function busRoute(c)
  local towns={}
  for _,d in ipairs(c:ownedDistricts()) do
    if not d.island and (d.population or 0)>=City.PEOPLE.tripAt then towns[#towns+1]=d end
  end
  local pair
  for i=1,#towns do
    for j=i+1,#towns do
      local a,b=towns[i],towns[j]
      local far=dist({x=a.x+a.w/2,y=a.y+a.h/2},{x=b.x+b.w/2,y=b.y+b.h/2})
      if far<=1500 and (not pair or far<pair[3]) then
        local sa,sb
        for _,s in ipairs(c.g:nodesOfKind('stop')) do
          if c:districtAt(s.x,s.y)==a then sa=s end
          if c:districtAt(s.x,s.y)==b then sb=s end
        end
        if not (sa and sb and c:linkBetween(sa.id,sb.id,'bus')) then pair={a,b,far} end
      end
    end
  end
  if not pair then return nil end
  local a,b=stopIn(c,pair[1]),stopIn(c,pair[2])
  if not (a and b) then return nil end
  if not c:roadConnected(a.id,b.id) then
    local road=withRoad(c,'road',function() return c:layLink(a.id,b.id,'road') end)
    if not road then
      -- Round whatever is in the way through a corner.
      for _,off in ipairs({250,-250,500,-500}) do
        local mx,my=(a.x+b.x)/2,(a.y+b.y)/2
        local len=math.max(1,dist(a,b))
        local bend=place(c,'corner',mx-(b.y-a.y)/len*off,my+(b.x-a.x)/len*off)
        if bend and withRoad(c,'road',function() return c:layLink(a.id,bend.id,'road') and c:layLink(bend.id,b.id,'road') end) then road=true; break end
      end
    end
    if not road then return nil end
  end
  return c:layLink(a.id,b.id,'bus') and 'Opened a bus route between '..pair[1].name..' and '..pair[2].name or nil
end

local function moreBuses(c)
  settle(c)
  for _,l in ipairs(c.links or {}) do
    local rec=((c.transit or {}).byLink or {})[l.id]
    if l.alive and l.mode=='bus' and rec and rec.trips>=City.ROUTES.bus.seats*(l.vehicles or 1)*0.9
      and (l.vehicles or 1)<City.PEOPLE.maxVehicles and c:addVehicle(l.id) then return 'Added a bus to a full route' end
  end
end

local function resort(c)
  if not (haul(c,'concrete') and haul(c,'glass')) then return nil end
  if c:materialError({concrete=40,glass=20}) then return nil end
  local stops=c.g:nodesOfKind('stop')
  for _,d in ipairs(c:ownedDistricts()) do
    for _,p in ipairs(riverbank(c,d)) do
      if not c:resortSiteError(p.x,p.y) then
        local r=place(c,'resort',p.x,p.y,nil,function(px,py) return not c:resortSiteError(px,py) end,40)
        if r then
          table.sort(stops,function(x,y) return dist(x,r)<dist(y,r) end)
          local s=stops[1]
          return s and withRoad(c,'road',function() return c:layLink(s.id,r.id,'road') end) and 'Built a riverside resort by the bus stop' or nil
        end
      end
    end
  end
end

--------------------------------------------------------------------------------
-- Upkeep of a long-lived network
--------------------------------------------------------------------------------

-- A filter straight after each well keeps the mains beyond it from calcifying.
local function filterWell(c)
  for _,w in ipairs(c.g:nodesOfKind('source')) do
    if w.commodity=='water' then
      for _,e in ipairs(c.g:edgesAt(w.id)) do
        local other=c.g.nodes[e.a==w.id and e.b or e.a]
        if e.alive and e.commodity=='water' and other.kind~='filtration' then
          local size=e.size
          c:demolishPipe(e.id)
          local f=place(c,'filtration',(w.x+other.x)/2,(w.y+other.y)/2)
          if f and c:layPipe(w.id,f.id,'water',size,nil,c.lining) and c:layPipe(f.id,other.id,'water',size,nil,c.lining) then
            return 'Put a filter after a well'
          end
          return nil
        end
      end
    end
  end
end

-- More ground, chosen for what it holds: springs where they are surveyed, a
-- river for turbines, a town for the buses, and a discount when one is offered.
local function buyLand(c,reason)
  local best,score
  for _,d in ipairs(c.districts) do
    if not d.owned and not d.island and c:districtAdjacent(d) and not c:districtError(d.id) then
      local s=c:landDiscount(d)*10
      if reason=='water' or c:workerCount('surveyors')>0 then
        for _,dep in ipairs(c.deposits) do
          if dep.commodity=='water' and not dep.taken and c:districtAt(dep.x,dep.y)==d then s=s+2 end
        end
      end
      -- A company with no intake is looking for one thing above all others: a
      -- stretch of bank. One works on running water outgrows every well on the
      -- map, so the ground it stands on is worth more than a deposit is.
      if reason=='water' and (c.intakesBought or 0)==0 and #riverbank(c,d)>0 then s=s+14 end
      if reason=='river' and #riverbank(c,d)>0 then s=s+10 end
      s=s-c:districtCost(d)/1000
      if not best or s>score then best,score=d,s end
    end
  end
  if not best or reason=='river' and #riverbank(c,best)==0 then return nil end
  return worth(c,c:districtCost(best)) and c:buyDistrict(best.id) and 'Bought '..best.name or nil
end

--------------------------------------------------------------------------------
-- One decision
--------------------------------------------------------------------------------

function A.step(city)
  local c=city
  local k=key(c)
  -- A new day, or a company this assistant did not hand back last time (a
  -- load, an undo, another slot), starts with a clean slate.
  if A.day~=k or A.last~=city then tried,actions,A.day={},{},k end
  local function out(result,...) A.last=result; return result,... end
  if city.bankrupt then return out(city,'Company has stopped trading',true) end
  local function close()
    local closed=assert(Save.unpack(Save.pack(c)))
    closed:endDay()
    return closed,'Day '..closed.day..': $'..closed.money,closed.bankrupt
  end
  if (actions[k] or 0)>=MAX_ACTIONS then return out(close()) end
  -- Planning is spread over several steps so the game never stalls on one.
  -- Each step gets at least one plan in, and a plan is never tried twice in a
  -- day, so the day always moves on.
  local deadline=os.clock()+A.budget
  packed.ran=false
  local function late() return packed.ran and os.clock()>deadline end
  local done,msg
  local function try(id,plan)
    if late() then return false end
    done,msg=attempt(c,id,plan)
    return done~=nil
  end

  -- The opening: a well on the marked spring and a T split towards the house.
  if count(c,'source')==0 then
    local springs={}
    for _,d in ipairs(c.deposits) do
      local land=c:districtAt(d.x,d.y)
      if d.commodity=='water' and not d.taken and land and land.owned then springs[#springs+1]=d end
    end
    table.sort(springs,function(a,b) return (a.opening and 1 or 0)>(b.opening and 1 or 0) end)
    for _,d in ipairs(springs) do
      if try('spring'..d.x..':'..d.y,function(t)
        local well=t:buySource('water',d.x,d.y)
        if not well then return end
        local house=t:clientList(true)[1] or {x=well.x+90,y=well.y+60}
        local split=place(t,'junction',(well.x+house.x)/2,(well.y+house.y)/2)
        return split and t:layPipe(well.id,split.id,'water','large') and 'Built a well and a T split'
      end) then return out(done,msg) end
    end
    if c.money<c:sourceCost('water') then return out(city,'Not enough cash for a well; autoplay paused',true) end
    return out(city,'No buildable well site; autoplay paused',true)
  end

  -- 1. Sound mains and no debt before anything new.
  local bill,broken=c:repairAllCost()
  if broken>0 and c.money>=bill and try('repair',function(t) return t:repairAll() and 'Repaired '..broken..' lines' end) then return out(done,msg) end
  if (c.loan or 0)>0 and spendable(c)>0
    and try('repay',function(t) return t:repay(math.min(t.loan,spendable(t))) and 'Repaid part of the loan' end) then return out(done,msg) end

  -- 2. Whoever is signed and short comes first: they are the ones about to leave.
  local waiting=short(c)
  table.sort(waiting,function(a,b) return (a.grace or 9)<(b.grace or 9) end)
  for _,n in ipairs(waiting) do
    if try('serve'..n.id,function(t) return serve(t,t.g.nodes[n.id]) and 'Restored supply to a customer' end) then return out(done,msg) end
  end

  -- 3. Offers, best price first: sign the ones the network can actually carry.
  local offers={}
  -- A secure contract refunds every short day, which is a promise for a person to make.
  for _,n in ipairs(c:clientList(true)) do if not n.secure then offers[#offers+1]=n end end
  for _,n in ipairs(c:clientList()) do if n.powerRequest then offers[#offers+1]=n end end
  table.sort(offers,function(a,b) return c:requestPremium(a)>c:requestPremium(b) end)
  -- A cluster of offers is cheaper to take with one area hub than one by one.
  if #offers>=3 and c:unlocked('hub') and not c:materialError(City.MATERIALS.exchange) and worth(c,City.price.exchange+600)
    and try('area-hub',areaHub) then return out(done,msg) end
  for _,n in ipairs(offers) do
    if servable(c,n) and c:requestPremium(n)>-0.3 and spendable(c)>0 then
      local what=n.powerRequest and 'Connected electricity to a household'
        or 'Signed and connected a '..string.lower(City.CLIENTS[n.clientType].name)
      if try('offer'..n.id,function(t) return sign(t,n.id) and what end) then return out(done,msg) end
    end
  end
  if late() then return out(city,'Weighing offers') end
  -- An offer it cannot serve is declined on its last day: a refusal costs less
  -- reputation than letting it lapse.
  for _,n in ipairs(c:clientList(true)) do
    if n.expires<=c.day and try('decline'..n.id,function(t) return t:declineClient(n.id) and 'Declined an offer it could not serve' end) then return out(done,msg) end
  end

  -- 4. Supply ahead of demand.
  local thirst=0
  for _,n in ipairs(c:clientList(true)) do if n.commodity=='water' then thirst=thirst+n.demand end end
  for _,n in ipairs(waiting) do thirst=thirst+(need(c,n).water or 0) end
  if (c.spare.water or 0)<math.max(6,thirst) then
    if try('deepen',function(t) return extendSource(t,'water') and 'Added supply at a source it already owns' end)
      or try('well-join',function(t) return newWell(t,true) end)
      or try('well',function(t) return newWell(t,false) end)
      or try('land-water',function(t) return buyLand(t,'water') end) then return out(done,msg) end
  end
  local power=0
  for _,n in ipairs(offers) do
    if n.powerRequest then power=power+(n.clientType=='estate' and 4 or 2)
    elseif n.commodity=='power' then power=power+n.demand end
  end
  if c.licences.power and power>0 and powerSpare(c)<math.min(power,16) and spendable(c)>=c:plantCost('hydro')+1500 then
    if try('extend-plant',function(t) return extendSource(t,'power') and 'Added a unit to a station it already owns' end)
      or try('generator',newGenerator) or try('land-river',function(t) return buyLand(t,'river') end) then return out(done,msg) end
  end

  -- 5. Growing the company once today's work is done, in the order the game
  --    opens up. Each project waits for the cash and the reason to exist.
  local clients=#c:clientList()
  local pipes=0
  for _,e in ipairs(c.g.edges) do if e.alive then pipes=pipes+1 end end
  local projects={
    -- Once licensed, new houses ask for electricity as well as water, so the
    -- licence waits until the company can afford to build a grid for them.
    {'licence-power',not c.licences.power and clients>=25 and worth(c,City.price.powerLicence+6000),
      function(t) return t:buyLicence('power') and 'Bought the electricity licence' end},
    {'crew',(c.crews or 0)<math.min(City.crewMax,math.floor(pipes/15)) and worth(c,City.crewHire+300),
      function(t) return t:hireCrew() and 'Hired a maintenance crew' end},
    {'freight',count(c,'terminal')==0 and c:unlocked('haven') and worth(c,City.HAVENS.highway.price+City.price.dc+900),freightHub},
    {'licence-beer',c.licences.beer==false and count(c,'dc')>0 and clients>=15 and worth(c,City.price.beerLicence+2500),
      function(t) return t:buyLicence('beer') and haul(t,'beer') and 'Bought the beer licence and trucks for it' end},
    {'licence-oil',c.licences.oil==false and count(c,'dc')>0 and clients>=25 and worth(c,City.price.oilLicence+3000),
      function(t) return t:buyLicence('oil') and haul(t,'oil') and 'Bought the oil licence and trucks for it' end},
    {'rig',c.licences.oil and count(c,'dc')>0 and worth(c,c:sourceCost('oil')+1200),newRig},
    {'lab',c:unlocked('works') and worth(c,City.price.lab+800),lab},
    {'roads',c:unlocked('roads') and worth(c,1600),roadCluster},
    {'highway',count(c,'interchange')>=2 and worth(c,1200),highway},
    {'station',c:unlocked('fuel') and count(c,'interchange')>0 and count(c,'dc')>0 and worth(c,City.price.station+900),station},
    {'bus',c:unlocked('roads') and worth(c,City.ROUTES.bus.vehicle+900),busRoute},
    {'buses',c:unlocked('routes') and worth(c,City.ROUTES.bus.vehicle*3),moreBuses},
    {'resort',c:unlocked('resort') and count(c,'resort')==0 and count(c,'dc')>0 and worth(c,City.price.resort+1500),resort},
    {'filter',c.day>=60 and pipes>=10 and worth(c,City.price.filtration*2+600),filterWell},
    {'lining',City.GRADES[(c.lining or 1)+1] and pipes>=25 and worth(c,(City.GRADES[(c.lining or 1)+1] or {}).price or 0),
      function(t) return t:upgradeQuality() and 'Unlocked better pipe lining' end},
    {'surveyors',c:workerCount('surveyors')==0 and c:orderAvailable('surveyors') and worth(c,City.ORDERS.surveyors.hire*3),
      function(t) return t:hireOrder('surveyors') and 'Hired surveyors' end},
    {'engineers',c:workerCount('engineers')==0 and pipes>=60 and c:orderAvailable('engineers') and worth(c,City.ORDERS.engineers.hire*3),
      function(t) return t:hireOrder('engineers') and 'Hired engineers' end},
    {'ads',#offers==0 and c.adDaysLeft==0 and worth(c,City.price.ads*6),
      function(t) return t:buyAds() and 'Booked an advertising campaign' end},
    {'permit-park',not c.permits.park and c.day>=30 and worth(c,City.PERMITS.park.cost*3),
      function(t) return t:buyPermit('park') and 'Bought the parkland easement' end},
    {'permit-river',not c.permits.river and c.day>=45 and worth(c,City.PERMITS.river.cost*3),
      function(t) return t:buyPermit('river') and 'Bought the river works charter' end},
    -- More ground when there is money to grow into it, or it is on offer cheap.
    {'land',(#offers==0 or c.day%7==0) and worth(c,1000),function(t) return buyLand(t) end},
    {'analyst',c:workerCount('analysts')==0 and worth(c,City.ORDERS.analysts.hire*10),
      function(t) return t:hireOrder('analysts') and 'Hired a market analyst' end},
  }
  for _,p in ipairs(projects) do
    if p[2] and try(p[1],p[3]) then return out(done,msg) end
  end
  -- Idle cash works: a slice of a large surplus goes into the weekly market,
  -- one modest placement at a time.
  local surplus=spendable(c)-20000
  if surplus>5000 and c:investedTotal()==0 then
    local amount=math.floor(math.min(50000,surplus*0.25))
    if try('invest',function(t) return t:invest(amount) and 'Invested $'..amount end) then return out(done,msg) end
  end
  if late() then return out(city,'Planning') end
  return out(close())
end

return A
