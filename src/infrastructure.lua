-- Engineering rules, kept separate from the company ledger and interface.
local Graph=require('graph')
local D=require('data.infrastructure')
return function(City)
  City.INFRA=D
  for key,spec in pairs(D.kinds) do City.price[key]=spec.cost; City.BUILDABLE[key]=(not spec.legacy) or nil end
  City.PLANTS.wind.ground='any'
  City.PLANTS.wind.blurb='Wind generation on owned land or an island.'
  -- Every station grows by taking further units on the one site rather than
  -- by a second site elsewhere: a weir holds more turbines, a field holds more
  -- arrays. `growth` on the site itself is steep enough that the second site
  -- waits until the first is full, and `maxUnits` stops any of it running away.
  City.PLANTS.hydro={name='RIVER TURBINE',base=850,growth=1.5,output=8,upkeep=14,fuel=0,ground='river',
    unitBase=520,unitGrowth=1.20,unitStep=8,maxUnits=5,unitName='turbine',
    blurb='Uses river flow. Must stand beside a river. The weir takes five turbines.'}
  City.PLANTS.solar={name='SOLAR ARRAY',base=1200,growth=1.48,output=10,upkeep=5,fuel=0,ground='land',
    unitBase=760,unitGrowth=1.16,unitStep=10,maxUnits=6,unitName='array',
    blurb='Daily-average solar output. Requires 12 imported solar panels per array.'}
  City.PLANT_ORDER={'nuclear','hydro','wind','solar'}
  City.MATERIALS.solar={panels=12}
  City.trade.panels={importCost=22,sourceUpkeep=0,form='solid'}
  for k,v in pairs(City.FORMS.solid) do City.trade.panels[k]=v end
  City.BUILD_UNLOCK.binder='massive'
  City.BUILD_UNLOCK.lab='works'

  local RANK={low=1,medium=2,high=3}
  local function dist(a,b) return math.sqrt((a.x-b.x)^2+(a.y-b.y)^2) end
  local function generator(n) return n.kind=='source' and (n.commodity=='power' or (n.demands and n.demands.power)) end
  local function farm(n) return (City.RECIPES[n.recipe or ''] or {}).farm end
  City.isFarm = farm
  -- A customer who has asked for electricity counts before they sign, so the
  -- cable can be run to them first and the request accepted when it is live.
  local function electrical(n)
    return n.kind=='transformer' or D.towers[n.kind] or (n.commodity=='power' or (n.demands and n.demands.power))
      or n.powerRequest or n.kind=='works' or n.kind=='dc'
  end
  City.isElectrical = electrical
  function City:pollutionAt(x,y)
    local d=self:districtAt(x,y)
    return d and (d.pollution or 0) or 0
  end
  function City:labCovers(n,d)
    local home=self:districtAt(n.x,n.y)
    return home and math.abs((home.col or 0)-(d.col or 0))<=1 and math.abs((home.row or 0)-(d.row or 0))<=1
  end
  function City:farmSiteError(x,y)
    local d=self:districtAt(x,y)
    if not d or not d.owned or d.island then return 'farms need owned mainland' end
    local r=D.farmRadius
    if x-r<d.x or x+r>d.x+d.w or y-r<d.y or y+r>d.y+d.h then return 'the whole farm must fit inside owned land' end
    if self:pollutionAt(x,y)>=D.pollution.stopAt then return 'soil polluted: build an environment lab nearby' end
    if (self:riverEdge(x,y) or math.huge)<r then return 'farm fields would overlap the river' end
    for _,n in ipairs(self.g:aliveNodes()) do
      local radius=farm(n) and r*2 or r
      if math.abs(n.x-x)<radius and math.abs(n.y-y)<radius then return 'farm fields need more open space' end
    end
    for _,o in ipairs(self.obstacles) do
      if dist(o,{x=x,y=y})<r*1.2+require('terrain_shape').reach(o,x,y) then return 'farm fields overlap protected terrain' end
    end
  end
  function City:upgradeBinder(id)
    local n=self.g.nodes[id]
    if not n or not n.alive or n.kind~='binder' then return nil,'select a pipe binder' end
    local level=n.bundleLanes or 2
    if level>=5 then return nil,'five lanes is the maximum' end
    local cost=D.binderPrices[level-1]
    if #self:clientList()<D.binderClients[level-1] then return nil,'needs '..D.binderClients[level-1]..' signed clients' end
    if self.money<cost then return nil,'not enough cash' end
    self:spend(cost); n.paid=(n.paid or 0)+cost; n.bundleLanes=level+1; n.ports=2*(level+1)+2
    self:refresh(); return n
  end

  -- Electricity. Every tower carries one voltage. A transformer on a tower lets
  -- it also take cables at every lower voltage, and customers only connect to a
  -- tower with a transformer that carries their own voltage.
  function City:customerVoltage(n)
    if n.kind=='client' then return (n.commodity=='power' or (n.demands and n.demands.power)) and (D.customerVoltage[n.clientType] or 'medium') or nil end
    if n.kind=='works' or n.kind=='dc' then return 'medium' end
  end
  function City:voltagesAt(n)
    if n.kind=='transformer' then return {low=true,medium=true,high=true} end
    local home=D.towers[n.kind]
    if home then
      if n.upgrade~='transformer' then return {[home]=true} end
      local set={}
      for key,rank in pairs(RANK) do if rank<=RANK[home] then set[key]=true end end
      return set
    end
    if generator(n) then return {high=true} end
    local want=self:customerVoltage(n)
    return want and {[want]=true} or {}
  end
  function City:cableVoltage(a,b)
    local na,nb=self.g.nodes[a],self.g.nodes[b]
    local ca,cb=self:customerVoltage(na),self:customerVoltage(nb)
    if (ca or generator(na)) and (cb or generator(nb)) then return nil,'power runs through towers: build one between them' end
    if ca or cb then
      local want,tower=ca or cb,ca and nb or na
      local label=string.lower(Graph.KINDS[D.voltages[want].tower].name)
      if tower.kind~='transformer' and D.towers[tower.kind]~=want then
        return nil,(want=='low' and 'homes take ' or 'this customer takes ')..string.lower(D.voltages[want].name)..': connect a '..label..' with a transformer'
      end
      if tower.kind~='transformer' and tower.upgrade~='transformer' then return nil,'add a transformer to this '..label..' to connect customers' end
      return want
    end
    -- The lowest voltage both ends take that also spans the gap; a longer gap
    -- than any shared voltage spans gets the highest, and fails on length.
    local sa,sb=self:voltagesAt(na),self:voltagesAt(nb)
    local metres,bonus,best=dist(na,nb),1+math.max(self:reachBonus(na),self:reachBonus(nb))
    for _,key in ipairs(D.voltageOrder) do
      if sa[key] and sb[key] then
        best=key
        if metres<=D.voltages[key].span*bonus then return key end
      end
    end
    if best then return best end
    if generator(na) or generator(nb) then return nil,'generators send out high voltage: connect a high voltage tower' end
    return nil,'voltage mismatch: add a transformer to step between voltages'
  end
  -- Cables laid before tower upgrades keep working at their installed length.
  local function cableLength(self,e) return e.legacySpan and 0 or dist(self.g.nodes[e.a],self.g.nodes[e.b]) end
  City.cableLength = cableLength
  -- Metres of cable from the nearest generator, transformer or booster, for every
  -- structure on this voltage. Customers take power but do not pass it on.
  function City:boostRuns(voltage,extra)
    local runs,queue,links={},{},{}
    local function link(a,b,w)
      links[a]=links[a] or {}; links[a][#links[a]+1]={b,w}
      links[b]=links[b] or {}; links[b][#links[b]+1]={a,w}
    end
    for _,n in ipairs(self.g:aliveNodes()) do
      local boost=n.kind=='transformer' or (voltage=='high' and generator(n))
        or (D.towers[n.kind] and n.upgrade and self:voltagesAt(n)[voltage])
      if boost then runs[n.id]=0; queue[#queue+1]=n.id end
    end
    for _,e in ipairs(self.g.edges) do
      if e.alive and e.commodity=='power' and e.voltage==voltage and not e.rail then link(e.a,e.b,cableLength(self,e)) end
    end
    if extra then link(extra.a,extra.b,extra.length) end
    local head=1
    while head<=#queue do
      local id=queue[head]; head=head+1
      if runs[id]==0 or not self:customerVoltage(self.g.nodes[id]) then
        for _,l in ipairs(links[id] or {}) do
          local far=runs[id]+l[2]
          if far<(runs[l[1]] or math.huge) then runs[l[1]]=far; queue[#queue+1]=l[1] end
        end
      end
    end
    return runs
  end
  -- A new cable may not bring any structure onto the grid further than the
  -- booster distance from its nearest generator, transformer or booster.
  function City:boostError(a,b,voltage)
    local limit=D.voltages[voltage].boost
    local before=self:boostRuns(voltage)
    local after=self:boostRuns(voltage,{a=a,b=b,length=dist(self.g.nodes[a],self.g.nodes[b])})
    for id,run in pairs(after) do
      if run>limit and not before[id] then
        return 'needs a booster every '..limit..' m at '..string.lower(D.voltages[voltage].name)..': upgrade a tower on this line'
      end
    end
  end
  function City:upgradeTower(id,upgrade)
    local n=self.g.nodes[id]
    if not n or not n.alive or not D.towers[n.kind] then return nil,'select a power tower' end
    local spec=D.upgrades[upgrade]
    if not spec then return nil,'choose a transformer or a booster' end
    if n.upgrade then return nil,'a tower holds one upgrade: demolish and rebuild to change it' end
    local cost=spec.cost[n.kind]
    if self.money<cost then return nil,'not enough cash' end
    self:spend(cost); n.paid=(n.paid or 0)+cost; n.upgrade=upgrade
    if spec.ports then n.ports=math.max(n.ports,spec.ports) end
    self:note('%s %d fitted with a %s for $%d',Graph.KINDS[n.kind].name,id,string.lower(spec.name),cost)
    self:refresh(); return n
  end

  -- A tower is built at low voltage and raised to the one it needs. It costs
  -- the difference between the two towers, levels and fitted upgrade included,
  -- so a raised tower has cost what it would have cost built that way. Cables
  -- already on it keep their voltage until they are upgraded themselves.
  local function towerPrice(self,n,kind)
    local total=City.price[kind] or 0
    for lv=2,self:levelOf(n) do total=total+(City.LEVELS.LEVELS.tower[lv].cost[kind] or 0) end
    if n.upgrade then total=total+D.upgrades[n.upgrade].cost[kind] end
    return total
  end
  function City:towerVoltageCost(n,key)
    return towerPrice(self,n,D.voltages[key].tower)-towerPrice(self,n,n.kind)
  end
  function City:towerVoltageError(id,key)
    local n=self.g.nodes[id]
    if not (n and n.alive and D.towers[n.kind]) then return 'select a power tower' end
    if not D.voltages[key] or RANK[key]<=RANK[D.towers[n.kind]] then return 'already at that voltage or above' end
    if self.money<self:towerVoltageCost(n,key) then return 'not enough cash' end
  end
  function City:raiseTowerVoltage(id,key)
    local err=self:towerVoltageError(id,key)
    if err then return nil,err end
    local n=self.g.nodes[id]
    local cost=self:towerVoltageCost(n,key)
    self:spend(cost); n.paid=(n.paid or 0)+cost
    n.kind=D.voltages[key].tower
    if n.level then City.setLevel(self,n,self:levelOf(n),false) end
    self:note('Tower %d raised to %s for $%d',id,string.lower(D.voltages[key].name),cost)
    self:refresh(); return n
  end

  -- A cable is laid at the lowest voltage its ends share, and upgraded one
  -- step at a time once both ends take the next one. It costs the difference
  -- between the two cables.
  function City:cableUpgradeTarget(e)
    if not (e and e.alive and e.voltage) then return nil end
    local sa,sb=self:voltagesAt(self.g.nodes[e.a]),self:voltagesAt(self.g.nodes[e.b])
    if self:customerVoltage(self.g.nodes[e.a]) or self:customerVoltage(self.g.nodes[e.b]) then return nil end
    for _,key in ipairs(D.voltageOrder) do
      if RANK[key]>RANK[e.voltage] and sa[key] and sb[key] then return key end
    end
  end
  function City:cableUpgradeCost(e,key)
    local held=self.quoteVoltage
    self.quoteVoltage=e.voltage
    local now=self:pipeQuote(e.a,e.b,'power',e.size or 'small',false,e.grade).total
    self.quoteVoltage=key
    local up=self:pipeQuote(e.a,e.b,'power',e.size or 'small',false,e.grade).total
    self.quoteVoltage=held
    return math.max(0,up-now)
  end
  function City:cableUpgradeError(id)
    local e=self.g.edges[id]
    if not (e and e.alive and e.voltage) then return 'select a cable' end
    local key=self:cableUpgradeTarget(e)
    if not key then return 'raise both ends to a higher voltage first' end
    if self.money<self:cableUpgradeCost(e,key) then return 'not enough cash' end
    -- The cable leaves its old voltage's grid and joins the new one's.
    local runs=self:boostRuns(key,{a=e.a,b=e.b,length=cableLength(self,e)})
    local before=self:boostRuns(key)
    for nid,run in pairs(runs) do
      if run>D.voltages[key].boost and not before[nid] then
        return 'needs a booster every '..D.voltages[key].boost..' m at '..string.lower(D.voltages[key].name)
      end
    end
  end
  function City:upgradeCable(id)
    local err=self:cableUpgradeError(id)
    if err then return nil,err end
    local e=self.g.edges[id]
    local key=self:cableUpgradeTarget(e)
    local cost=self:cableUpgradeCost(e,key)
    self:spend(cost); e.paid=(e.paid or 0)+cost; e.voltage=key
    self:note('Cable raised to %s for $%d',string.lower(D.voltages[key].name),cost)
    self:refresh(); return e
  end

  function City:connectionPorts(id)
    local used,groups=0,{}
    for _,e in ipairs(self.g:edgesAt(id)) do
      local other=e.a==id and e.b or e.a
      local key=tostring(other)..':'..tostring(e.commodity)
      if self.g.nodes[other].kind=='binder' or self.g.nodes[id].kind=='binder' then
        if not groups[key] then groups[key]=true; used=used+1 end
      else used=used+1 end
    end
    return used
  end
  function City:parallelLimit(a,b)
    local na,nb=self.g.nodes[a],self.g.nodes[b]
    if na.kind=='binder' and nb.kind=='binder' then return math.min(na.bundleLanes or 2,nb.bundleLanes or 2) end
    if na.kind=='binder' then return na.bundleLanes or 2 end
    if nb.kind=='binder' then return nb.bundleLanes or 2 end
    return 1
  end
  -- A cable carries what its size carries, at any voltage: the number is the
  -- flow and the voltage is what it costs and how far it reaches. Companies
  -- from before this (no `powerFlux`) keep the old kV-times-amps rating until
  -- migrate() has widened any cable that would otherwise run short.
  function City:powerRating(e)
    local voltage=D.voltages[e.voltage or 'medium']
    local amps=D.amps[e.size or 'small'] or 500
    if self.powerFlux then
      local healthy=math.max(0,e.cap)/math.max(1,e.capMax or e.cap)
      return math.floor(City.sizeOf(e.size or 'small').cap*healthy),amps,voltage.kv,0
    end
    local healthy=math.max(0,e.cap)/math.max(1,e.capMax or e.cap)
    local kw=math.sqrt(3)*voltage.kv*amps
    local gross=kw*24/5 -- daily energy in 5 kWh accounting increments
    local resistance=(D.resistance[e.size or 'small'] or 0.12)*self:pipeLength(e)/1000
    local loss=math.min(0.8,3*amps*amps*resistance/(kw*1000))
    return math.max(0,math.floor(gross*(1-loss)*healthy)),amps,voltage.kv,loss
  end
  function City:waterRating(e)
    local a,b=self.g.nodes[e.a],self.g.nodes[e.b]
    local diameter=D.water.diameter[e.size or 'small']
    local head=(a.kind=='pump' or b.kind=='pump') and D.water.pumpHead or D.water.head
    -- Darcy-Weisbach design limit, flat terrain, m3/hour. This is a segment
    -- design envelope; the game does not pretend to solve transient hydraulics.
    local velocity=math.sqrt(2*9.81*head*diameter/(D.water.friction*math.max(1,self:pipeLength(e))))
    local capacity=math.pi*diameter*diameter/4*velocity*3600
    return math.min(e.cap,math.floor(capacity))*math.max(0.1,1-math.max(0,(e.calcification or 0)-100)/200),head*0.0981
  end
  function City:polluteSegment(a,b,amount)
    local length=dist(a,b)
    local steps=math.max(1,math.ceil(length/200))
    local touched={}
    for i=0,steps do
      local t=i/steps
      local d=self:districtAt(a.x+(b.x-a.x)*t,a.y+(b.y-a.y)*t)
      if d then touched[d.id]=d end
    end
    local count=0; for _ in pairs(touched) do count=count+1 end
    for _,d in pairs(touched) do d.pollution=math.min(100,(d.pollution or 0)+amount/math.max(1,count)) end
  end
  function City:environmentDay()
    local spilled=0
    for _,n in ipairs(self.g:aliveNodes()) do
      if n.kind=='source' and n.commodity=='oil' then self:polluteSegment(n,n,D.pollution.rigPerDay) end
    end
    for _,e in ipairs(self.g.edges) do
      e.shipSpill=nil
      if e.alive and e.bulk=='sea' and (e.wagons or {}).oil and self:random()<D.pollution.shipRisk then
        local moved=math.abs(((self.edgeFlowBy or {}).oil or {})[e.id] or 0)
        e.shipSpill=math.min(e.wagons.oil,moved)*D.pollution.shipFactor
        if e.shipSpill>0 then self:note('Oil spill on shipping route %d: cargo lost and replacement imports billed',e.id) end
      end
    end
    -- Cargo lost at sea is a real drain on supply, with less carrying room
    -- left for deliveries. It cannot be delivered and spilled simultaneously.
    self:refresh()
    for _,e in ipairs(self.g.edges) do
      if e.alive then
        local amount=0
        if e.commodity=='oil' and not e.bulk and e.leaking then amount=(self.oilSpills[e.id] or 0)*D.pollution.pipeFactor end
        if e.bulk=='sea' then amount=(self.oilSpills[e.id] or 0)*D.pollution.pipeFactor end
        if amount>0 then self:polluteSegment(self.g.nodes[e.a],self.g.nodes[e.b],amount); spilled=spilled+amount end
      end
    end
    local labs=self.g:nodesOfKind('lab')
    for _,d in ipairs(self.districts) do
      local cleanup=D.pollution.decay
      for _,n in ipairs(labs) do if self:labCovers(n,d) then cleanup=cleanup+D.pollution.cleanup end end
      d.pollution=math.max(0,(d.pollution or 0)-cleanup)
      local blocked=d.pollution>=D.pollution.stopAt
      if blocked and not d.pollutionBlocked then self:note('%s: polluted water and soil have stopped local wells and farms',d.name) end
      if not blocked and d.pollutionBlocked then self:note('%s: water and soil are clean enough for production again',d.name) end
      d.pollutionBlocked=blocked or nil
    end
    return spilled
  end
end
