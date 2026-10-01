local Graph=require('graph')
return function(City)
 -- Carriageway widths in metres, and the pavement a normal road has either
 -- side. Traffic keeps to its lane and people to the pavement, off these.
 -- A highway is two lanes each way either side of a central reserve.
 City.ROAD_WIDTH={offroad=10,road=16,highway=32,bridge=16}
 City.PAVEMENT=5
 -- How far out to sea a harbour's jetty runs: a ship lies alongside it.
 City.JETTY_HEAD=-210
 City.ROAD_TYPES={offroad={name='OFFROAD',factor=.5,colour={.65,.48,.30}},road={name='NORMAL ROAD',factor=1,colour={.65,.68,.72}},highway={name='HIGHWAY',factor=2,colour={.96,.80,.35}},bridge={name='BRIDGE',factor=1,colour={.70,.72,.76}}}
 -- A bridge is the one road that may cross water, and the only way over it:
 -- none stands until the company builds it. It is priced by the metre of
 -- water it spans and charges a toll, like a highway.
 City.BRIDGE=require('data.freight').BRIDGE
 -- Is this spot water: the river, or the sea anywhere off an island's shore.
 function City:isWater(x,y)
  if self:riverAt(x,y) then return true end
  if y>=0 then return false end
  local d=self:districtAt(x,y)
  if d and d.island and ((x-d.x-d.w/2)/(d.w/2))^2+((y-d.y-d.h/2)/(d.h/2))^2<=0.9 then return false end
  return true
 end
 -- Metres of water along a straight line.
 function City:waterAlong(ax,ay,bx,by)
  local len=math.sqrt((bx-ax)^2+(by-ay)^2)
  local steps=math.max(2,math.ceil(len/8))
  local wet=0
  for i=0,steps-1 do
   local t=(i+0.5)/steps
   if self:isWater(ax+(bx-ax)*t,ay+(by-ay)*t) then wet=wet+len/steps end
  end
  return math.floor(wet+0.5)
 end
 -- Vehicles pay on a highway and on a bridge; every other road is free.

 --------------------------------------------------------------------------
 -- Drawing a road from anywhere to anywhere
 --------------------------------------------------------------------------
 -- A road is dragged out between two points. Each end joins whatever it lands
 -- on: a building or road node within reach, the middle of a road (which is
 -- split there, branching off it), or bare ground, where a road end is put
 -- down. Water on the way becomes a bridge of the same road; another road
 -- crossed on the level becomes a junction, and one crossed with a highway on
 -- either side goes over or under it with no junction at all. A run longer
 -- than one road reaches is split with bends. Every road node then becomes
 -- the junction its roads call for, and is charged the difference.
 City.ROAD_SNAP=24
 local JRANK={corner=1,intersection=2,roundabout=3,interchange=4}
 City.ROAD_JRANK=JRANK
 local function vis(l)
  if l.deck then return l.deck end
  local k=l.roadType or 'road'
  return k=='bridge' and 'road' or k
 end
 City.roadVisual=vis
 function City:roadsAt(id)
  local out={}
  for _,l in ipairs(self.links or {}) do if l.alive and l.mode=='road' and (l.a==id or l.b==id) then out[#out+1]=l end end
  return out
 end
 -- The junction a road node should be with these roads at it, plus `extra`
 -- (the kinds about to join). Never a step down.
 function City:roadNodeKind(n,extra,skip)
  if not JRANK[n.kind] then return n.kind end
  local kinds={}
  for _,l in ipairs(self:roadsAt(n.id)) do if l~=skip then kinds[#kinds+1]=vis(l) end end
  for _,k in ipairs(extra or {}) do kinds[#kinds+1]=k end
  local want='corner'
  if #kinds>=3 then
   local high,paved=false,false
   for _,k in ipairs(kinds) do if k=='highway' then high=true elseif k~='offroad' then paved=true end end
   want=high and 'interchange' or paved and 'roundabout' or 'intersection'
  end
  return JRANK[want]>JRANK[n.kind] and want or n.kind
 end
 function City:roadNodeUpgrade(n,extra)
  local want=self:roadNodeKind(n,extra)
  if want==n.kind then return 0,want end
  return math.max(0,(City.price[want] or 0)-(City.price[n.kind] or 0)),want
 end
 function City:fitRoadNode(id)
  local n=self.g.nodes[id]
  if not (n and n.alive) then return end
  local want=self:roadNodeKind(n)
  if want~=n.kind then
   n.paid=(n.paid or City.price[n.kind] or 0)+math.max(0,(City.price[want] or 0)-(City.price[n.kind] or 0))
   n.kind=want; n.ports=Graph.KINDS[want].ports; n.throughput=Graph.KINDS[want].throughput
  end
 end
 -- What a road dragged to (x, y) joins.
 function City:roadEndAt(x,y)
  local best,bd
  for _,n in ipairs(self.g:aliveNodes()) do
   if City.TRANSIT_NODES[n.kind] then
    local reach=JRANK[n.kind] and City.ROAD_SNAP or City.footprint(n.kind)+6
    local d=math.sqrt((n.x-x)^2+(n.y-y)^2)
    if d<reach and (not bd or d<bd) then best,bd=n,d end
   end
  end
  if best then return {node=best.id,x=best.x,y=best.y} end
  local bl,bt,bdist
  for _,l in ipairs(self.links or {}) do
   local na,nb=self.g.nodes[l.a],self.g.nodes[l.b]
   if l.alive and l.mode=='road' and na and nb and na.alive and nb.alive then
    local dx,dy=nb.x-na.x,nb.y-na.y
    local t=math.max(0,math.min(1,((x-na.x)*dx+(y-na.y)*dy)/math.max(1e-9,dx*dx+dy*dy)))
    local d=math.sqrt((na.x+dx*t-x)^2+(na.y+dy*t-y)^2)
    if d<City.ROAD_WIDTH[vis(l)]/2+8 and (not bdist or d<bdist) then bl,bt,bdist=l,t,d end
   end
  end
  if bl then
   local na,nb=self.g.nodes[bl.a],self.g.nodes[bl.b]
   local len=math.sqrt((nb.x-na.x)^2+(nb.y-na.y)^2)
   if bt*len<City.ROAD_SNAP*1.5 then return {node=na.id,x=na.x,y=na.y} end
   if (1-bt)*len<City.ROAD_SNAP*1.5 then return {node=nb.id,x=nb.x,y=nb.y} end
   return {link=bl.id,x=na.x+(nb.x-na.x)*bt,y=na.y+(nb.y-na.y)*bt}
  end
  return {x=x,y=y}
 end
 -- Whether a road end can be put down on bare ground here.
 function City:roadPointError(x,y)
  local d=self:districtAt(x,y)
  if not d then return y<0 and 'that is the sea' or 'unsurveyed ground' end
  if not d.owned then return 'you do not own '..d.name end
  if self:isWater(x,y) then return 'a road cannot end in the water' end
  local o=self:obstacleAt(x,y)
  if o and not (self.permits and self.permits[o.kind]) then return 'cannot build on '..string.lower(City.OBSTACLES[o.kind].name) end
  for _,n in ipairs(self.g:aliveNodes()) do
   if not JRANK[n.kind] then
    local body=City.footprint(n.kind)
    if (n.x-x)^2+(n.y-y)^2<(body+4)^2 then return 'a building stands there' end
   end
  end
  return nil
 end
 -- Everything a drag from (ax, ay) to (bx, by) would build, and its price,
 -- without building any of it. `err` says why it cannot be built.
 function City:roadPlan(ax,ay,bx,by,variant)
  variant=variant or self.buildRoadType or 'road'
  if variant=='bridge' then variant='road' end
  local plan={variant=variant,cost=0,stops={},pieces={},flyovers=0}
  local A,B=self:roadEndAt(ax,ay),self:roadEndAt(bx,by)
  plan.A,plan.B=A,B
  plan.ax,plan.ay,plan.bx,plan.by=A.x,A.y,B.x,B.y
  local function fail(why) plan.err=why; return plan end
  if not self:unlocked('roads') then return fail('nobody travels yet') end
  if A.node and A.node==B.node then return fail('a road needs two ends') end
  if A.link and A.link==B.link then return fail('that is already one road') end
  local len=math.sqrt((B.x-A.x)^2+(B.y-A.y)^2)
  if len<20 then return fail('too short for a road') end
  for _,E in ipairs({A,B}) do
   if E.node then
    local n=self.g.nodes[E.node]
    if n.kind=='stop' and variant~='road' then return fail('bus stops attach to normal roads only') end
    if variant=='highway' and not JRANK[n.kind] then return fail('a highway reaches buildings through a normal road') end
    if A.node and B.node and self:linkBetween(A.node,B.node,'road') then return fail('that road already exists') end
   elseif E.link then
    if self:isWater(E.x,E.y) then return fail('a road cannot join one on a bridge') end
   else
    local why=self:roadPointError(E.x,E.y)
    if why then return fail(why) end
   end
  end
  local stops={{t=0,ref=A},{t=1,ref=B}}
  -- Water on the way: a bridge, from dry bank to dry bank.
  local steps=math.max(2,math.ceil(len/6))
  local wet={}
  local open
  for i=0,steps do
   local t=i/steps
   local w=self:isWater(A.x+(B.x-A.x)*t,A.y+(B.y-A.y)*t)
   if w and not open then open=t end
   if not w and open then wet[#wet+1]={open,t}; open=nil end
  end
  if open then return fail('a road cannot end in the water') end
  local pad=12/len
  for _,span in ipairs(wet) do
   if span[1]<=0 then return fail('a road cannot start in the water') end
   for k,t in ipairs({math.max(0,span[1]-pad),math.min(1,span[2]+pad)}) do
    if t>0.001 and t<0.999 then
     local x,y=A.x+(B.x-A.x)*t,A.y+(B.y-A.y)*t
     local why=self:roadPointError(x,y)
     if why then return fail('no dry bank for a bridge: '..why) end
     stops[#stops+1]={t=t,ref={x=x,y=y,bank=true}}
    end
   end
   span[1],span[2]=math.max(0,span[1]-pad),math.min(1,span[2]+pad)
  end
  local function wetAt(t)
   for _,span in ipairs(wet) do if t>span[1] and t<span[2] then return true end end
   return false
  end
  -- Other roads crossed: a junction on the level, or a bridge over a highway.
  local RS=require('road_shape')
  for _,l in ipairs(self.links or {}) do
   local na,nb=self.g.nodes[l.a],self.g.nodes[l.b]
   if l.alive and l.mode=='road' and na and nb and na.alive and nb.alive
      and l.id~=A.link and l.id~=B.link and l.a~=A.node and l.b~=A.node and l.a~=B.node and l.b~=B.node then
    local t,u=RS.crossing(A.x,A.y,B.x,B.y,na.x,na.y,nb.x,nb.y)
    if t then
     local x,y=A.x+(B.x-A.x)*t,A.y+(B.y-A.y)*t
     if vis(l)=='highway' or variant=='highway' or l.roadType=='bridge' or wetAt(t) then
      plan.flyovers=plan.flyovers+1
     else
      stops[#stops+1]={t=t,ref={link=l.id,x=x,y=y,cross=true}}
     end
    end
   end
  end
  table.sort(stops,function(p,q) return p.t<q.t end)
  -- Two stops on top of each other are one.
  local function rank(s) return (s.t==0 or s.t==1) and 4 or s.ref.node and 3 or s.ref.link and 2 or 1 end
  local kept={}
  for _,s in ipairs(stops) do
   local last=kept[#kept]
   if last and (s.t-last.t)*len<14 then
    if rank(s)>rank(last) then kept[#kept]=s end
   else kept[#kept+1]=s end
  end
  stops=kept
  -- A dry run longer than one road reaches is split with bends.
  local range=City.PEOPLE.roadRange
  local filled={stops[1]}
  for i=2,#stops do
   local a,b=filled[#filled],stops[i]
   local span=(b.t-a.t)*len
   if span>range and not wetAt((a.t+b.t)/2) then
    local parts=math.ceil(span/range)
    for k=1,parts-1 do
     local t=a.t+(b.t-a.t)*k/parts
     local x,y=A.x+(B.x-A.x)*t,A.y+(B.y-A.y)*t
     if self:roadPointError(x,y) then return fail('too far for one road, and no ground for a bend between') end
     filled[#filled+1]={t=t,ref={x=x,y=y}}
    end
   end
   filled[#filled+1]=b
  end
  stops=filled
  plan.stops=stops
  -- The pieces, and what each costs. The tie-ins are paid once per road.
  local cost=City.PEOPLE.roadTiein*2*(City.ROAD_TYPES[variant] or City.ROAD_TYPES.road).factor
  for i=1,#stops-1 do
   local s,e=stops[i],stops[i+1]
   local bridge=wetAt((s.t+e.t)/2)
   local mult,blocker=self:crossingCost(s.ref.x,s.ref.y,e.ref.x,e.ref.y,bridge)
   if not mult then return fail('cannot cross '..string.lower(City.OBSTACLES[blocker.kind] and City.OBSTACLES[blocker.kind].name or 'that')) end
   local b=self:buildingOnLine(s.ref.x,s.ref.y,e.ref.x,e.ref.y,s.ref.node,e.ref.node)
   if b and not JRANK[b.kind] then return fail('a building is in the way') end
   local d=(e.t-s.t)*len
   local piece=d*City.PEOPLE.roadPerM*mult
   if bridge then piece=piece+self:waterAlong(s.ref.x,s.ref.y,e.ref.x,e.ref.y)*City.BRIDGE.perWaterM end
   piece=math.ceil(piece*(City.ROAD_TYPES[variant] or City.ROAD_TYPES.road).factor)
   plan.pieces[#plan.pieces+1]={from=i,to=i+1,roadType=bridge and 'bridge' or variant,deck=bridge and variant or nil,cost=piece}
   cost=cost+piece
  end
  -- Road ends put down, roads split, and junctions that grow.
  local joining={}
  for i,s in ipairs(stops) do
   local n=(i>1 and 1 or 0)+(i<#stops and 1 or 0)
   local kinds={}
   for _=1,n do kinds[#kinds+1]=variant end
   if s.ref.node then
    cost=cost+self:roadNodeUpgrade(self.g.nodes[s.ref.node],kinds)
   else
    local l=s.ref.link and self.links[s.ref.link]
    if l then kinds[#kinds+1]=vis(l); kinds[#kinds+1]=vis(l) end
    local want=self:roadNodeKind({kind='corner',id=-1},kinds)
    cost=cost+(City.price[want] or 30)
   end
  end
  plan.cost=math.ceil(cost)
  return plan
 end
 -- A road split where another joins it: the near half keeps its id.
 function City:splitRoad(id,x,y)
  local l=self.links[id]
  local n=self.g:addNode(x,y,'corner'); n.paid=City.price.corner; n.autoRoad=true
  local na,nb=self.g.nodes[l.a],self.g.nodes[l.b]
  local whole=math.max(1,math.sqrt((nb.x-na.x)^2+(nb.y-na.y)^2))
  local near=math.sqrt((x-na.x)^2+(y-na.y)^2)/whole
  local copy={id=#self.links+1,a=n.id,b=l.b,mode='road',roadType=l.roadType,deck=l.deck,alive=true,
   toll=l.toll,paid=math.floor((l.paid or 0)*(1-near)),goodsEdge=l.goodsEdge}
  l.paid=math.floor((l.paid or 0)*near)
  l.b=n.id
  self.links[copy.id]=copy
  return n.id
 end
 function City:drawRoad(ax,ay,bx,by,variant)
  local plan=self:roadPlan(ax,ay,bx,by,variant)
  if plan.err then return nil,plan.err end
  if plan.cost>self.money then return nil,'not enough cash' end
  self:spend(plan.cost)
  self.links=self.links or {}
  local ids={}
  for i,s in ipairs(plan.stops) do
   local r=s.ref
   if r.node then ids[i]=r.node
   elseif r.link then ids[i]=self:splitRoad(r.link,r.x,r.y)
   else local n=self.g:addNode(r.x,r.y,'corner'); n.paid=City.price.corner; n.autoRoad=true; ids[i]=n.id end
  end
  local last
  for _,p in ipairs(plan.pieces) do
   local l={id=#self.links+1,a=ids[p.from],b=ids[p.to],mode='road',roadType=p.roadType,deck=p.deck,alive=true,paid=p.cost}
   l.toll=p.roadType=='highway' and City.PEOPLE.tollDefault or p.roadType=='bridge' and City.BRIDGE.toll or 0
   if p.roadType=='bridge' and p.deck=='highway' then l.toll=math.max(l.toll,City.PEOPLE.tollDefault) end
   self.links[l.id]=l
   last=l
  end
  for _,id in ipairs(ids) do self:fitRoadNode(id) end
  self:note('%s laid for $%d',City.ROAD_TYPES[plan.variant].name:sub(1,1)..City.ROAD_TYPES[plan.variant].name:sub(2):lower(),plan.cost)
  self:refresh()
  return last
 end
 -- A road end left with no road at it goes with the last one.
 function City:clearRoadEnds(l)
  for _,id in ipairs({l.a,l.b}) do
   local n=self.g.nodes[id]
   if n and n.alive and n.autoRoad and #self:roadsAt(id)==0 then
    self.money=self.money+math.floor((n.paid or 0)*City.REFUND)
    self.g:killNode(id)
   end
  end
 end
 function City.tolled(l) return l.mode=='road' and (l.roadType=='highway' or l.roadType=='bridge') end
 -- A corner is the cheap one: two ports, for bending a road round something
 -- rather than for meeting another road at it.
 local junctions={corner='ROAD BEND',intersection='TRACK JUNCTION',roundabout='ROAD JUNCTION',interchange='HIGHWAY INTERCHANGE'}
 City.ROAD_JUNCTIONS=junctions
 local ports={corner=2}
 local costs={corner=30,interchange=400}
 for key,name in pairs(junctions) do
  Graph.KINDS[key]={name=name,ports=ports[key] or 8,throughput=999,cost=costs[key] or 80,color={.8,.75,.5}}
  City.price[key]=Graph.KINDS[key].cost; City.BUILDABLE[key]=true; City.BUILD_UNLOCK[key]='roads'; City.TRANSIT_NODES[key]=true
 end
 for _,key in ipairs({'client','works','depot','source'}) do City.TRANSIT_NODES[key]=true end
 City.MODES.highway.name='CONTAINER TRUCKS'
 City.MODES.highway.blurb='Container trucks use connected normal roads and highways.'
 local household={house=true,home=true,estate=true,subscriber=true}
 City.HOUSEHOLD=household
 -- Electricity reads as a flow and a voltage: the number is how much, and
 -- one, two or three bolts say low, medium or high voltage. The same number
 -- is the same flow at any voltage.
 local RANK={low=1,medium=2,high=3}
 function City.bolts(voltage) return string.rep(require('symbols').get('power'),RANK[voltage or 'low'] or 1) end
 -- The voltage a building is supplied at: its own, or its cable's, or low.
 function City:voltageOf(n)
  if not n then return 'low' end
  if n.voltage then return n.voltage end
  if n.kind=='client' then return City.INFRA.customerVoltage[n.clientType] or 'medium' end
  for _,e in ipairs(self.g:edgesAt(n.id)) do if e.alive and e.commodity=='power' and e.voltage then return e.voltage end end
  return 'low'
 end
 function City:quantity(key,value,voltage)
  if key=='power' then return string.format('%g ',value)..City.bolts(voltage) end
  return string.format('%g %s',value,require('symbols').get(key))
 end
 -- Two figures in one unit, the unit written once.
 function City:quantityPair(key,a,b,voltage)
  if key=='power' then return string.format('%g / %g ',a,b)..City.bolts(voltage) end
  return string.format('%g / %g %s',a,b,require('symbols').get(key))
 end
 -- Supplied means given all it used today; the contract is only the ceiling.
 function City:fullyServed(c)
  for key in pairs(c.demands or {}) do if (key==c.commodity and (self.served[c.id] or 0) or (((self.servedBy or {})[c.id] or {})[key] or 0))<self:want(c,key) then return false end end
  return (self.served[c.id] or 0)>=self:want(c)
 end
 function City:contractValue(c)
  local total=0
  for key,want in pairs(c.demands or {[c.commodity]=c.demand}) do total=total+want*(key==c.commodity and c.rate or (c.utilityRates or {})[key] or c.rate) end
  return total
 end
 -- Shortest physical path; freight and buses cannot use offroads.
 -- Which roads leave each place, for cars (offroads too) or for everything
 -- else. Every driver, truck line and bus asks for a path each day, so the
 -- table is built once per network: refresh forgets it, and nothing changes a
 -- road or a building without a refresh following.
 local roadAdjCache=setmetatable({},{__mode='k'})
 function City:forgetRoads() roadAdjCache[self]=nil end
 local function roadAdj(self,vehicle)
  local cache=roadAdjCache[self]
  if not cache or cache.rev~=self.revision then cache={rev=self.revision}; roadAdjCache[self]=cache end
  local key=vehicle=='car' and 'car' or 'road'
  if cache[key] then return cache[key] end
  local adj={}
  for _,l in ipairs(self.links or {}) do
   if l.alive and l.mode=='road' and (vehicle=='car' or l.roadType~='offroad') then
    local na,nb=self.g.nodes[l.a],self.g.nodes[l.b]
    if na and nb and na.alive and nb.alive then
     adj[l.a]=adj[l.a] or {}; adj[l.b]=adj[l.b] or {}; table.insert(adj[l.a],l); table.insert(adj[l.b],l)
    end
   end
  end
  cache[key]=adj
  return adj
 end
 function City:roadPath(a,b,vehicle)
  local adj=roadAdj(self,vehicle)
  -- Dijkstra: the nearest unsettled place first, the lower id on a tie. A
  -- place whose distance improved is pushed again and its older, longer
  -- entry skipped when it surfaces.
  local dist,prev,done={[a]=0},{},{}
  local heap=Graph.heap(); heap.push(0,a)
  while true do
   local best,u=heap.pop()
   if not best then return nil end
   if not done[u] and best==dist[u] then
    if u==b then
     local path={}; while prev[u] do local l=prev[u]; table.insert(path,1,l); u=l.a==u and l.b or l.a end
     return path,best
    end
    done[u]=true
    local list=adj[u]
    if list then
     for k=1,#list do
      local l=list[k]
      local v=l.a==u and l.b or l.a; local d=best+self:nodeDistance(l.a,l.b)
      if not done[v] and (not dist[v] or d<dist[v]) then dist[v],prev[v]=d,l; heap.push(d,v) end
     end
    end
   end
  end
 end
 function City:roadConnected(a,b) return self:roadPath(a,b,'bus')~=nil end
 -- Utility and freight access does not make a building a passenger destination.
 function City:dailyDestinationAllowed(n,vehicle)
  if not n or not n.alive or n.prospect then return false end
  if vehicle=='car' then return n.kind=='client' or n.kind=='works' or n.kind=='resort' or n.kind=='stop' end
  return n.kind=='works' or n.kind=='depot' or n.kind=='dc' or n.kind=='terminal'
    or n.kind=='client' and (n.clientType=='factory' or n.clientType=='market')
 end
end
