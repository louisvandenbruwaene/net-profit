package.path='test/?.lua;src/?.lua;'..package.path
local T=require('support')
local City=require('city')
local Graph=require('graph')
local Save=require('company_save')
local check=T.check
local function near(a,b) return math.abs(a-b)<0.001 end
local function city() return T.sandbox(24,true) end
local node=T.node
local function clients(c,count)
  for i=1,count do local n=node(c,'client',1800+i,1200,'water'); n.demand=0; n.clientType='house'; n.rate=4; n.grace=3 end
end
-- Water fittings and finite capacity.
do
  local c=city()
  local spring
  for _,d in ipairs(c.deposits) do if d.opening then spring=d end end
  local well=assert(c:buySource('water',spring.x,spring.y))
  check(well.ports==1,'a newly sunk well has one outlet')
  local filter=assert(c:build(well.x+70,well.y,'filtration'))
  local main=assert(c:layPipe(well.id,filter.id,'water','large'))
  check(filter.ports==2,'filtration has two connections')
  local split=assert(c:build(filter.x+70,filter.y,'junction'))
  local pipe=assert(c:layPipe(filter.id,split.id,'water','large'))
  check(pipe.filtered and not main.filtered,'only downstream mains receive filtration')
  local raw={a=pipe.a,b=pipe.b,cap=25,capMax=25,size='large',commodity='water',grade=1}
  check(c:leakChance(pipe)<c:leakChance(raw),'treated mains calcify less')
  check(c:pipeError(well.id,split.id,'water')~=nil,'a well cannot acquire a second outlet')
  check(Graph.KINDS.junction.ports==3 and Graph.KINDS.manifold.ports==6,'T splits and pipe hubs retain distinct connections')
  local _,bar=c:waterRating(pipe)
  check(bar>2 and bar<4,'ordinary pipe pressure is in a plausible service range')
  local pump=node(c,'pump',split.x+100,split.y)
  local boosted={a=split.id,b=pump.id,cap=7,capMax=7,size='small',commodity='water',hydraulic=true,grade=1}
  local _,boost=c:waterRating(boosted)
  check(boost>bar and c:rangeBetween(split.id,pump.id,nil,'water')>City.rules.linkRange,'pumps increase pressure and reach')
  local restored=assert(Save.unpack(Save.pack(c)))
  check(restored.g.nodes[well.id].ports==1 and restored.g.edges[pipe.id].filtered,'fittings and treatment survive saving')
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
-- The three towers are built like any structure; bare transformers are not.
do
  local c=city()
  check(c:build(1320,1050,'hvtower') and c:build(1550,1050,'pylon') and c:build(1700,1050,'pole'),'all three power towers can be built')
  check(c:build(1450,1200,'transformer'),'standalone transformers are available')
end
-- Power steps down through towers, and customers hang off transformer towers.
do
  local c=city()
  local plant=node(c,'source',1250,1050,'power',45); plant.voltage='high'
  local hv=node(c,'hvtower',1450,1050)
  local std=node(c,'pylon',1540,1050)
  local workshop=node(c,'client',1640,1050,'power'); workshop.demand=5; workshop.rate=10; workshop.grace=3; workshop.clientType='workshop'
  local home=node(c,'client',1540,1140,'power'); home.demand=2; home.rate=6; home.grace=3; home.clientType='home'
  check(City.CLIENTS.home.commodity=='power' and City.INFRA.customerVoltage.home=='low','homes are low voltage power customers')
  check(c:pipeError(plant.id,std.id,'power'):find('high voltage'),'a generator only feeds a high voltage tower')
  check(c:pipeError(plant.id,workshop.id,'power'):find('towers'),'generation never connects straight to a customer')
  local trunk=assert(c:layPipe(plant.id,hv.id,'power','small'))
  check(trunk.voltage=='high','the generator cable is high voltage')
  check(c:pipeError(hv.id,std.id,'power'):find('transformer'),'a bare tower cannot change voltage')
  assert(c:upgradeTower(hv.id,'transformer'))
  local feeder=assert(c:layPipe(hv.id,std.id,'power','medium'))
  check(feeder.voltage=='medium','a transformer steps high voltage down onto a standard tower')
  check(c:pipeError(std.id,workshop.id,'power'):find('transformer'),'customers need a transformer on their tower')
  check(c:pipeError(hv.id,workshop.id,'power')~=nil,'a high voltage tower never feeds a customer directly')
  assert(c:upgradeTower(std.id,'transformer'))
  check(not c:upgradeTower(std.id,'booster'),'a tower holds one upgrade')
  local drop=assert(c:layPipe(std.id,workshop.id,'power','medium'))
  check(drop.voltage=='medium' and c.served[workshop.id]==5,'a standard tower with a transformer serves a workshop at medium voltage')
  check(c:pipeError(std.id,home.id,'power'):find('low voltage pole'),'homes take low voltage from a pole')
  local pole=node(c,'pole',1540,1100)
  local low=assert(c:layPipe(std.id,pole.id,'power','small'))
  check(low.voltage=='low','a standard transformer also steps down to low voltage')
  assert(c:upgradeTower(pole.id,'transformer'))
  assert(c:layPipe(pole.id,home.id,'power','small'))
  check(c.served[home.id]==2,'a pole with a transformer serves a home')
  local cap,amps,kv,loss=c:powerRating(drop)
  check(amps==1250 and kv==11 and cap>=5 and loss>0,'current rating, voltage and resistive losses constrain carrying capacity')
  drop.leaking=true; drop.cap=0; c:refresh()
  check((c.served[workshop.id] or 0)<5,'a failed cable causes a real shortfall')
  assert(c:repairPipe(drop.id)); check(c.served[workshop.id]==5,'repair restores electrical supply')
  local split=node(c,'junction',1500,1200)
  check(c:pipeError(hv.id,split.id,'power'):find('water fittings'),'water fittings cannot carry power')
  local saved=assert(Save.unpack(Save.pack(c)))
  check(saved.g.nodes[std.id].upgrade=='transformer' and saved.g.edges[low.id].voltage=='low' and saved.served[home.id]==2,
    'towers, upgrades, voltages and delivery survive saving')
end
-- A tower is built low and raised; a cable is laid at the lowest shared
-- voltage and upgraded once both ends take the next one.
do
  local c=city(); c.money=100000
  local a=node(c,'pole',1250,1050); local b=node(c,'pole',1370,1050)
  c.setLevel(c,a,1,true); c.setLevel(c,b,1,true)
  assert(c:upgradeTower(a.id,'transformer')); assert(c:upgradeTower(b.id,'transformer'))
  check(c:towerVoltageCost(a,'medium')==(65-25)+(260-90),'raising a tower costs the difference, fitted transformer included')
  local cable=assert(c:layPipe(a.id,b.id,'power','small'))
  check(cable.voltage=='low' and not c:cableUpgradeTarget(cable),'two poles share only low voltage')
  local money=c.money
  assert(c:raiseTowerVoltage(a.id,'high'))
  check(a.kind=='hvtower' and c.money==money-c:towerVoltageCost({kind='pole',level=1,upgrade='transformer'},'high'),'a tower is raised straight to the voltage wanted')
  check(a.throughput==40*City.LEVELS.TOWER_SCALE.hvtower,'a raised tower carries more')
  check(cable.voltage=='low' and not c:towerVoltageError(b.id,'medium'),'its cables keep their voltage')
  check(c:towerVoltageError(a.id,'medium')~=nil,'a tower is never lowered')
  assert(c:raiseTowerVoltage(b.id,'high'))
  check(c:cableVoltage(a.id,b.id)=='low','a new cable takes the lowest voltage both ends accept')
  check(c:cableUpgradeTarget(cable)=='medium' and c:cableUpgradeCost(cable,'medium')>0,'an upgrade goes one voltage up and costs money')
  local before=c:powerRating(cable)
  assert(c:upgradeCable(cable.id)); assert(c:upgradeCable(cable.id))
  check(cable.voltage=='high' and c:powerRating(cable)>before and c:cableUpgradeTarget(cable)==nil,'upgraded cables carry more, up to high voltage')
  local far=node(c,'hvtower',1250+250,1080); c.setLevel(c,far,1,true)
  assert(c:upgradeTower(far.id,'transformer'))
  check(c:cableVoltage(a.id,far.id)=='high','a gap only a higher voltage spans gets that voltage')
end
-- Each voltage has a tower spacing and a booster distance.
do
  local c=city()
  local V=City.INFRA.voltages
  check(V.high.span==300 and V.medium.span==200 and V.low.span==150,'a tower every 300, 200 and 150 m')
  check(V.high.boost==2500 and V.medium.boost==1000 and V.low.boost==300,'a booster every 2500, 1000 and 300 m')
  for kind,voltage in pairs({hvtower='high',pylon='medium',pole='low'}) do
    local a=node(c,kind,1250,1050)
    local b=node(c,kind,1250+V[voltage].span+1,1050)
    check(c:pipeError(a.id,b.id,'power'):find('too long'),kind..' cables stop at '..V[voltage].span..' m')
    b.x=1250+V[voltage].span
    check(c:pipeError(a.id,b.id,'power')==nil,kind..' cables reach exactly '..V[voltage].span..' m')
  end
  local function chain(kind,root,y,count,step)
    local prev,list=root,{}
    for i=1,count do
      local t=node(c,kind,root.x+i*step,y)
      assert(c:layPipe(prev.id,t.id,'power','large'))
      list[i]=t; prev=t
    end
    return list,node(c,kind,root.x+(count+1)*step,y)
  end
  local gen=node(c,'source',1250,1190,'power',40); gen.voltage='high'
  local hvs,ninth=chain('hvtower',gen,1190,8,300)
  check(c:pipeError(hvs[8].id,ninth.id,'power'):find('booster'),'high voltage runs 2500 m from its generator, then needs a booster')
  local root=node(c,'hvtower',1250,1120); root.upgrade='transformer'; root.ports=6
  local towers,sixth=chain('pylon',root,1120,5,200)
  check(c:pipeError(towers[5].id,sixth.id,'power'):find('booster'),'medium voltage needs a booster after 1000 m')
  assert(c:upgradeTower(towers[3].id,'booster'))
  check(c:pipeError(towers[5].id,sixth.id,'power')==nil,'a booster restarts the booster distance')
  local last=assert(c:layPipe(towers[5].id,sixth.id,'power','large'))
  towers[3].upgrade=nil; c:refresh()
  check(last.unboosted and last.effectiveCap==0,'without its booster the cable beyond 1000 m carries nothing')
  local poleRoot=node(c,'pole',1250,1260); poleRoot.upgrade='transformer'; poleRoot.ports=6
  local poles,third=chain('pole',poleRoot,1260,2,150)
  check(c:pipeError(poles[2].id,third.id,'power'):find('booster'),'low voltage needs a booster after 300 m')
  local far=node(c,'hvtower',1250+2500,1330)
  local _,_,_,loss=c:powerRating({a=gen.id,b=far.id,cap=25,capMax=25,size='large',voltage='high'})
  check(loss<0.05,'a 2.5 km transmission line loses only a few percent')
end
-- Companies saved before tower upgrades convert and keep their supply.
do
  local c=city()
  local plant=node(c,'source',1250,1050,'power',45); plant.voltage='high'
  local oldPylon=node(c,'pylon',1900,1050)
  local oldTransformer=node(c,'transformer',1960,1050)
  local shop=node(c,'client',2020,1050,'power'); shop.demand=4; shop.rate=10; shop.grace=3; shop.clientType='workshop'
  local function cable(a,b,voltage)
    local e=c.g:addEdge(a.id,b.id,25); e.commodity='power'; e.capMax=25; e.size='large'; e.grade=1; e.voltage=voltage
    return e
  end
  local long=cable(plant,oldPylon,'high'); cable(oldPylon,oldTransformer,'high'); cable(oldTransformer,shop,'low')
  c.infrastructureVersion=2
  local loaded=assert(Save.unpack(Save.pack(c)))
  local p,t=loaded.g.nodes[oldPylon.id],loaded.g.nodes[oldTransformer.id]
  check(p.kind=='hvtower' and not p.upgrade,'an old high voltage pylon becomes a high voltage tower')
  check(t.kind=='hvtower' and t.upgrade=='transformer' and t.ports>=6,'an old transformer becomes a tower with a transformer')
  check(loaded.g.edges[long.id].legacySpan and not loaded.g.edges[long.id].unboosted,'a 650 m cable laid under the old rules keeps working')
  check(loaded.served[shop.id]==4 and loaded.infrastructureVersion==3,'a converted company keeps supplying its customers')
end
-- Every commodity belongs to a grid, and late goods share category grids.
do
  for _,name in ipairs(Graph.ALL) do check(Graph.GRIDS[name],'every commodity has a grid: '..name) end
  check(Graph.gridOf('steel')=='metals' and Graph.gridOf('concrete')=='stone' and Graph.gridOf('wheat')=='food'
    and Graph.gridOf('gasoline')=='oil' and Graph.gridOf('water')=='water','late goods are grouped into food, metals, stone and more')
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
  check((c.served[customer.id] or 0)==0,'polluted wells supply no water')
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
  local hv=node(c,'hvtower',x+200,y); hv.upgrade='transformer'; hv.ports=6
  local std=node(c,'pylon',x+110,y); std.upgrade='transformer'; std.ports=6
  assert(c:layPipe(w1.id,farm.id,'water','large'))
  assert(c:layPipe(w2.id,farm.id,'water','large'))
  assert(c:layPipe(oil.id,farm.id,'oil','large'))
  assert(c:layPipe(power.id,hv.id,'power','small'))
  assert(c:layPipe(hv.id,std.id,'power','medium'))
  assert(c:layPipe(std.id,farm.id,'power','medium'))
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
print(T.checks..' infrastructure checks passed')
