package.path='src/?.lua;'..package.path
local City=require('city')
local Graph=require('graph')
local Save=require('company_save')
local checks=0
local function check(v,m) assert(v,m); checks=checks+1 end
local function near(a,b) return math.abs(a-b)<0.001 end
local function city()
  local c=City.new({seed=24,obstacles=0})
  c.money=1000000; c.obstacles={}; c.stock={steel=1000,concrete=1000,panels=100}
  for _,d in ipairs(c.districts) do d.owned=true end
  c.licences={water=true,power=true,oil=true,food=true,beer=true,internet=true}
  c.permits={park=true,bedrock=true,river=true}
  return c
end
local function node(c,kind,x,y,commodity,output)
  local n=c.g:addNode(x,y,kind); n.commodity=commodity
  if output then n.output=output; n.cap=output end
  return n
end
local function clients(c,count)
  for i=1,count do local n=node(c,'client',1800+i,1200,'water'); n.demand=0; n.clientType='house'; n.rate=4; n.grace=3 end
end
-- Water fittings and finite capacity.
do
  local c=city()
  local spring
  for _,d in ipairs(c.deposits) do if d.opening then spring=d end end
  local well=assert(c:buySource('water',spring.x,spring.y))
  check(well.ports==2,'a newly sunk well has two outlets')
  local filter=assert(c:build(well.x+70,well.y,'filtration'))
  local main=assert(c:layPipe(well.id,filter.id,'water','large'))
  check(filter.ports==2,'filtration has two connections')
  local split=assert(c:build(filter.x+70,filter.y,'junction'))
  local pipe=assert(c:layPipe(filter.id,split.id,'water','large'))
  check(pipe.filtered and main.filtered,'new mains joined to treatment remember filtration')
  local raw={a=pipe.a,b=pipe.b,cap=25,capMax=25,size='large',commodity='water',grade=1}
  check(c:leakChance(pipe)<c:leakChance(raw),'treated mains calcify less')
  check(c:pipeError(well.id,split.id,'water')==nil,'a well can now acquire a second outlet')
  check(Graph.KINDS.junction.ports==3 and Graph.KINDS.manifold.ports==6,'T splits and pipe hubs retain distinct connections')
  local _,bar=c:waterRating(pipe)
  check(bar>2 and bar<4,'ordinary pipe pressure is in a plausible service range')
  local pump=node(c,'pump',split.x+100,split.y)
  local boosted={a=split.id,b=pump.id,cap=7,capMax=7,size='small',commodity='water',hydraulic=true,grade=1}
  local _,boost=c:waterRating(boosted)
  check(boost>bar and c:rangeBetween(split.id,pump.id,nil,'water')>City.rules.linkRange,'pumps increase pressure and reach')
  local restored=assert(Save.unpack(Save.pack(c)))
  check(restored.g.nodes[well.id].ports==2 and restored.g.edges[pipe.id].filtered,'fittings and treatment survive saving')
end
-- Binders consume source supply once; duplicate routes do not create water.
do
  local c=city(); clients(c,30)
  local source=node(c,'source',1250,1050,'water',200); source.ports=1
  local a=assert(c:build(1320,1050,'binder'))
  local b=assert(c:build(1570,1050,'binder'))
  local sink=node(c,'client',1640,1050,'water'); sink.demand=180; sink.rate=4; sink.grace=3; sink.clientType='house'
  -- Large endpoint fixtures let the test examine bundled flow independently of household nozzle sizing.
  sink.kind='gate'; sink.throughput=999
  local terminal=node(c,'client',1690,1050,'water'); terminal.demand=6; terminal.rate=4; terminal.grace=3; terminal.clientType='house'
  assert(c:layPipe(source.id,a.id,'water','massive'))
  assert(c:layPipe(source.id,a.id,'water','massive'))
  local e1=assert(c:layPipe(a.id,b.id,'water','massive'))
  local e2=assert(c:layPipe(a.id,b.id,'water','massive'))
  check(e1.id~=e2.id,'two identical parallel mains are separate assets')
  check(not c:layPipe(a.id,b.id,'water','massive'),'two-lane binder refuses a third main')
  check(not c:layPipe(a.id,b.id,'water','small'),'parallel mains must match')
  assert(c:upgradeBinder(a.id)); assert(c:upgradeBinder(b.id))
  check(c:layPipe(a.id,b.id,'water','massive'),'both upgraded binders permit a third main')
  check(c:connectionPorts(source.id)==1,'a bundled connection uses one well outlet')
  assert(c:layPipe(b.id,sink.id,'water','massive'))
  assert(c:layPipe(sink.id,terminal.id,'water','small'))
  check(c.served[terminal.id]==6 and (c.produced[source.id] or 0)<=source.output,'bundles deliver water without multiplying production')
  local copied=assert(Save.unpack(Save.pack(c)))
  check(copied.g.nodes[a.id].bundleLanes==3,'binder upgrade persists')
end
-- Electricity must use a voltage transition, and current limits are meaningful.
do
  local c=city()
  local source=node(c,'source',1250,1050,'power',45); source.voltage='high'
  local transformer=assert(c:build(1320,1050,'transformer'))
  local customer=node(c,'client',1390,1050,'power'); customer.demand=5; customer.rate=10; customer.grace=3; customer.clientType='workshop'
  check(c:pipeError(source.id,customer.id,'power'):find('voltage'),'generation cannot connect directly to a low-voltage consumer')
  local trunk=assert(c:layPipe(source.id,transformer.id,'power','small'))
  local cable=assert(c:layPipe(transformer.id,customer.id,'power','medium'))
  check(trunk.voltage=='high' and cable.voltage=='low','auto voltage selects both sides of the transformer')
  check(c.served[customer.id]==5,'transformed electricity serves the customer')
  local cap,amps,kv,loss=c:powerRating(cable)
  check(amps==1250 and kv==0.4 and cap>=5 and loss>0,'current rating, voltage and resistive losses constrain carrying capacity')
  cable.leaking=true; cable.cap=math.floor(cable.capMax/4); c:refresh()
  check(c.served[customer.id]<5,'degraded electrical lines can cause a real shortfall')
  assert(c:repairPipe(cable.id)); check(c.served[customer.id]==5,'repair restores electrical supply')
  local pylon=assert(c:build(1550,1050,'pylon'))
  c.lineVoltage='high'; local high=assert(c:layPipe(source.id,pylon.id,'power','small'))
  c.lineVoltage='low'
  check(c:pipeError(pylon.id,customer.id,'power'):find('voltage'),'a pylon cannot silently change voltage')
  c.lineVoltage=nil
  local split=node(c,'junction',1500,1200)
  check(c:pipeError(source.id,split.id,'power'):find('water fittings'),'water fittings cannot carry new power lines')
  local saved=assert(Save.unpack(Save.pack(c)))
  check(saved.g.edges[high.id].voltage=='high' and saved.served[customer.id]==5,'voltage and delivery persist')
end
-- Higher voltage carries a line further, as on a real grid.
do
  local c=city()
  local V=City.INFRA.voltages
  check(V.low.range<V.medium.range and V.medium.range<V.high.range,'each step up in voltage reaches further')
  local a=node(c,'pylon',1250,1050); a.ports=3
  local b=node(c,'pylon',1250+5000,1050); b.ports=3
  c.lineVoltage='medium'
  check(c:pipeError(a.id,b.id,'power'):find('too long'),'a 5 km run is beyond an 11 kV feeder')
  c.lineVoltage='high'
  check(c:pipeError(a.id,b.id,'power')==nil,'a 5 km run is within reach of 110 kV transmission')
  local line=assert(c:layPipe(a.id,b.id,'power','large'))
  local _,_,_,loss=c:powerRating(line)
  check(loss<0.05,'a long transmission line loses only a few percent')
end
-- Pollution is deterministic and only actual oil supply can leak.
do
  local c=city()
  local source=node(c,'source',1250,1050,'oil',8)
  local endNode=node(c,'junction',1450,1050)
  local pipe=assert(c:layPipe(source.id,endNode.id,'oil','large'))
  pipe.leaking=true; pipe.cap=0; c:refresh()
  check(near(c.oilSpills[pipe.id],8),'a broken main spills no more than its source can produce')
  check(near(c.produced[source.id],c.oilSpills[pipe.id]),'spilled oil is counted against production')
  c:environmentDay()
  local polluted=c:pollutionAt(1250,1050)
  check(polluted>0,'oil spills contaminate the traversed district')
  source.output=0; c:refresh()
  check((c.oilSpills[pipe.id] or 0)==0,'an empty oil source cannot keep spilling')
  local d=c:districtAt(1250,1050); d.pollution=50
  local well=node(c,'source',1550,1050,'water',20)
  local customer=node(c,'client',1620,1050,'water'); customer.demand=3; customer.rate=4; customer.grace=3; customer.clientType='house'
  local fitting=node(c,'junction',1580,1120)
  assert(c:layPipe(well.id,fitting.id,'water','large'))
  assert(c:layPipe(fitting.id,customer.id,'water','small'))
  check((c.served[customer.id] or 0)==0 and c:sourceIncome(well)==0,'polluted wells neither supply water nor earn wholesale revenue')
  local lab=assert(c:build(1700,1050,'lab'))
  check(c:labCovers(lab,d),'lab covers its own district')
  local adjacent=c:cellAt(d.col+1,d.row+1)
  check(adjacent and c:labCovers(lab,adjacent),'lab covers diagonal neighbouring districts')
  local cash=c.money
  for _=1,4 do c:environmentDay() end
  c:refresh()
  check(c:pollutionAt(well.x,well.y)<30 and c.served[customer.id]==3,'cleanup restores water production')
  check(c:expenseBreakdown().structures>=24,'labs have a daily operating cost')
  local pollution,rng,day=c:pollutionAt(well.x,well.y),c.rng,c.day
  c:refresh()
  check(c.money==cash and c.rng==rng and c.day==day and c:pollutionAt(well.x,well.y)==pollution,
    'refresh does not advance money, random state, time or pollution')
end
-- Oil cargo cannot be both delivered and spilled; imports include lost cargo.
do
  local g=Graph.new()
  local port=g:addNode(0,0,'terminal')
  local yard=g:addNode(100,0,'dc')
  local client=g:addNode(200,0,'client'); client.commodity='oil'; client.demand=100
  local ship=g:addEdge(port.id,yard.id,100)
  ship.commodity='oil'; ship.wagons={oil=100}; ship.bulk='sea'; ship.shipSpill=40; ship.spillWanted=40
  local main=g:addEdge(yard.id,client.id,100); main.commodity='oil'
  local flow,_,served,detail,produced=g:maxflow(false,'oil')
  check(served[client.id]==60 and detail.spill[ship.id]==40,'a ship spill reduces delivered oil by the lost cargo')
  check(produced[port.id]==100 and flow==100,'delivered and spilled cargo are both counted in imports')
end
-- Farms reserve land, need inputs, and produce a named crop or livestock batch.
do
  local c=city(); local farm
  for _,d in ipairs(c.districts) do
    local x,y=d.x+d.w/2,d.y+d.h/2
    if not farm and not c:farmSiteError(x,y) and not c:placementError(x,y) then farm=assert(c:build(x,y,'works','crops')) end
  end
  check(farm and farm.farm,'crop farms are constructible on sufficiently large clean land')
  check(c:placementError(farm.x+100,farm.y)~=nil,'farm acreage excludes overlapping construction')
  check(farm.ready==0,'a farm cannot produce crops without its inputs')
  local inputs=City.RECIPES.crops.inputs
  c.detail.works[farm.id]={water=36,oil=1.2,power=2.4}
  check(c:worksOutput(farm)==12,'complete farm inputs yield rated crops')
  c.detail.works[farm.id].water=18
  check(c:worksOutput(farm)==6,'a farm scales down when water is short')
  c:districtAt(farm.x,farm.y).pollution=40
  check(c:worksOutput(farm)==0,'dirty soil stops farm production')
  for _,key in ipairs({'dairy','poultry','pigs','cattle'}) do
    local spec=City.RECIPES[key]
    check(spec.product and spec.inputs.water and spec.inputs.power and spec.inputs.oil and spec.inputs.wheat,'livestock needs feed and utilities: '..key)
  end
end
-- A complete farm chain must work through real construction and the flow solver.
do
  local c=city(); local farm
  for _,d in ipairs(c.districts) do
    local x,y=d.x+d.w/2,d.y+d.h/2
    if not farm and not c:farmSiteError(x,y) and not c:placementError(x,y) then farm=assert(c:build(x,y,'works','crops')) end
  end
  local x,y=farm.x,farm.y
  local w1=node(c,'source',x-210,y,'water',30)
  local w2=node(c,'source',x-210,y+180,'water',30)
  local oil=node(c,'source',x,y+220,'oil',3)
  local power=node(c,'source',x+250,y,'power',20); power.voltage='high'
  local transformer=assert(c:build(x+180,y,'transformer'))
  assert(c:layPipe(w1.id,farm.id,'water','large'))
  assert(c:layPipe(w2.id,farm.id,'water','large'))
  assert(c:layPipe(oil.id,farm.id,'oil','large'))
  assert(c:layPipe(power.id,transformer.id,'power','small'))
  assert(c:layPipe(transformer.id,farm.id,'power','medium'))
  local fitting=node(c,'junction',x,y-190)
  assert(c:layPipe(farm.id,fitting.id,'wheat','large'))
  for i=1,2 do
    local n=node(c,'client',x+(i==1 and -80 or 80),y-220,'wheat')
    n.demand=6; n.rate=4; n.grace=3; n.clientType='market'
    assert(c:layPipe(fitting.id,n.id,'wheat','small'))
  end
  check(farm.ready==12 and c.flowBy.wheat==12,'real pipes deliver all farm inputs and carry its crops away')
  check(near(c.detail.works[farm.id].water,36) and near(c.detail.works[farm.id].power,2.4),'farm inputs are debited from the real utility networks')
  local restored=assert(Save.unpack(Save.pack(c)))
  check(restored.g.nodes[farm.id].ready==12,'the complete agricultural chain survives loading')
end
-- New generator site and import requirements.
do
  local c=city()
  check(c:sourceError('power',1500,1050,'hydro')~=nil,'river turbines cannot be placed arbitrarily inland')
  c.stock.panels=0
  check(c:sourceError('power',1600,1200,'solar')~=nil,'solar cannot be built before panels are imported')
  c.stock.panels=12
  local solar=assert(c:buySource('power',1600,1200,'solar'))
  check(c.stock.panels==0 and solar.output==10,'solar construction consumes its imported panels')
  local wind=assert(c:buySource('power',1700,1200,'wind'))
  check(wind.plant=='wind','wind generation also works on mainland')
  local offshore=assert(c:buySource('power',1600,-100,'wind'))
  check(offshore.offshore and offshore.upkeep>wind.upkeep,'offshore wind requires coastal ownership and costs more to operate')
  check(c:sourceError('power',1600,-500,'wind')~=nil,'offshore construction is restricted to the leased coastal shelf')
end
print(checks..' infrastructure checks passed')
