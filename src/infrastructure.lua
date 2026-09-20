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
  City.trade.panels={importCost=22,wholesale=0,wholesalePerUnit=0,sourceUpkeep=0,form='solid'}
  for k,v in pairs(City.FORMS.solid) do City.trade.panels[k]=v end
  City.BUILD_UNLOCK.binder='massive'
  City.BUILD_UNLOCK.lab='works'
  local base={}
  for _,k in ipairs({'new','migrate','build','buySource','sourceCost','sourceError','placementError','pipeError','rangeBetween','sizeRange','pipeQuote','layPipe','replaceQuote','replacePipe','refresh','worksOutput','leakChance','endDay','sourceIncome','expenseBreakdown','convertError'}) do base[k]=City[k] end

  local RANK={low=1,medium=2,high=3}
  local function dist(a,b) return math.sqrt((a.x-b.x)^2+(a.y-b.y)^2) end
  local function generator(n) return n.kind=='source' and (n.commodity=='power' or (n.demands and n.demands.power)) end
  local function farm(n) return (City.RECIPES[n.recipe or ''] or {}).farm end
  local function electrical(n)
    return n.kind=='transformer' or D.towers[n.kind] or (n.commodity=='power' or (n.demands and n.demands.power)) or n.kind=='works' or n.kind=='exchange' or n.kind=='dc'
  end
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
      if dist(o,{x=x,y=y})<r+o.r then return 'farm fields overlap protected terrain' end
    end
  end
  function City:placementError(x,y)
    local err=base.placementError(self,x,y)
    if err then return err end
    for _,n in ipairs(self.g:aliveNodes()) do
      if farm(n) and math.abs(n.x-x)<D.farmRadius and math.abs(n.y-y)<D.farmRadius then return 'that land is used by a farm' end
    end
  end
  function City:sourceError(commodity,x,y,plant)
    if commodity=='wheat' then return 'choose Crop farm under More buildings; farms need utilities' end
    if commodity=='power' and plant=='wind' and y<0 and not self:districtAt(x,y) then
      if not self:licensed('power') then return 'no licence for power' end
      local coast=self:districtAt(x,1)
      if not coast or not coast.owned or y < -220 then return 'offshore wind needs owned coastline within 220m' end
      for _,n in ipairs(self.g:aliveNodes()) do if dist(n,{x=x,y=y})<City.rules.minSpacing then return 'too close to another structure' end end
      return nil
    end
    local err=base.sourceError(self,commodity,x,y,plant)
    if err then return err end
    if commodity=='power' and plant=='hydro' and (self:riverEdge(x,y) or math.huge)>100 then return 'a river turbine needs a river within 100m' end
    if commodity=='water' and self:pollutionAt(x,y)>=D.pollution.stopAt then return 'water polluted: an environment lab must clean the district' end
    if commodity=='power' and plant=='solar' then return self:materialError(City.MATERIALS.solar) end
  end
  function City:sourceCost(commodity,x,y,plant)
    local cost,seam=base.sourceCost(self,commodity,x,y,plant)
    if commodity=='power' and plant=='wind' and y and y<0 and not self:districtAt(x,y) then cost=math.ceil(cost*1.6) end
    return cost,seam
  end
  function City:buySource(commodity,x,y,plant)
    local n,err=base.buySource(self,commodity,x,y,plant)
    if n then
      if commodity=='water' then
        n.output,n.level=n.intake and City.INTAKE.output or D.wellOutput,1
        -- A well answers through one outlet, which is what stops a source
        -- being a distribution point in its own right. An intake gets a
        -- second, and keeps the ceiling the channel gave it.
        n.ports=n.intake and D.intakePorts or D.wellPorts
        n.cap=n.intake and n.cap or D.wellCap
      end
      if commodity=='power' then n.voltage='high' end
      if plant=='wind' and y and y<0 and not self:districtAt(x,y) then n.offshore=true; n.upkeep=math.ceil(n.upkeep*1.5) end
      self:refresh()
    end
    return n,err
  end
  function City:build(x,y,kind,recipe)
    if kind=='works' and recipe=='turbine' then return self:buySource('power',x,y,'hydro') end
    local spec=City.RECIPES[recipe or '']
    if kind=='works' and spec and spec.farm then
      local err=self:farmSiteError(x,y)
      if err then return nil,err end
    end
    local n,err=base.build(self,x,y,kind,recipe)
    if n then
      if kind=='binder' then n.bundleLanes=2 end
      if kind=='works' and spec and spec.farm then n.farm=true end
      if kind=='lab' then self:note('Lab protects its district and eight adjacent districts; cleanup runs at day close.') end
      self:refresh()
    end
    return n,err
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
    if n.kind=='works' or n.kind=='exchange' or n.kind=='dc' then return 'medium' end
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
        return nil,(want=='low' and 'homes take ' or 'this customer takes ')..D.voltages[want].kv..' kV: connect a '..label..' with a transformer'
      end
      if tower.kind~='transformer' and tower.upgrade~='transformer' then return nil,'add a transformer to this '..label..' to connect customers' end
      return want
    end
    local sa,sb=self:voltagesAt(na),self:voltagesAt(nb)
    for i=#D.voltageOrder,1,-1 do
      local key=D.voltageOrder[i]
      if sa[key] and sb[key] then return key end
    end
    if generator(na) or generator(nb) then return nil,'generators send out high voltage: connect a high voltage tower' end
    return nil,'voltage mismatch: add a transformer to step between voltages'
  end
  -- Cables laid before tower upgrades keep working at their installed length.
  local function cableLength(self,e) return e.legacySpan and 0 or dist(self.g.nodes[e.a],self.g.nodes[e.b]) end
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
        return 'needs a booster every '..limit..' m at '..D.voltages[voltage].kv..' kV: upgrade a tower on this line'
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
  function City:sizeRange(a,b)
    local na,nb=self.g.nodes[a],self.g.nodes[b]
    if na and nb and (D.towers[na.kind] or D.towers[nb.kind]) then return 1,#City.PIPE_SIZES end
    return base.sizeRange(self,a,b)
  end
  function City:rangeBetween(a,b,rail,commodity,size)
    if rail then return base.rangeBetween(self,a,b,rail) end
    local na,nb=self.g.nodes[a],self.g.nodes[b]
    -- Electricity has a size ladder of its own in the voltages, so the pipe
    -- sizes do not reach any further on a cable than they already do in kV.
    if commodity=='power' then
      if na.kind=='transformer' or nb.kind=='transformer' then return 95 end
      local voltage=a~=b and self:cableVoltage(a,b)
      if not voltage then
        local set=self:voltagesAt(na)
        for i=#D.voltageOrder,1,-1 do if set[D.voltageOrder[i]] then voltage=D.voltageOrder[i]; break end end
      end
      -- Farms connect at the field boundary, not at the central map badge.
      return D.voltages[voltage or 'low'].span+((farm(na) or farm(nb)) and D.farmRadius or 0)
    end
    -- An attachment to a binder is a short spur by design, so it does not get
    -- the trunk's reach however wide it is.
    if (na.kind=='binder')~=(nb.kind=='binder') then return D.binderRange end
    if na.kind=='pump' or nb.kind=='pump' then return D.pumpRange*City.reachFor(size) end
    return base.rangeBetween(self,a,b,rail,commodity,size)
  end
  function City:pipeError(a,b,commodity,rail,size)
    if rail then return base.pipeError(self,a,b,commodity,rail) end
    local na,nb=self.g.nodes[a],self.g.nodes[b]
    if not na or not nb or not na.alive or not nb.alive or a==b then return 'choose two different live buildings' end
    if not self:licensed(commodity) then return 'no licence for that' end
    if na.kind=='terminal' or nb.kind=='terminal' then return 'a haven ships by bulk line only' end
    local voltage
    if commodity=='power' then
      if not electrical(na) or not electrical(nb) then return 'electricity needs power towers, not water fittings' end
      local why
      voltage,why=self:cableVoltage(a,b)
      if not voltage then return why end
    elseif D.towers[na.kind] or D.towers[nb.kind] or na.kind=='transformer' or nb.kind=='transformer' then return 'power towers carry electricity only'
    elseif (na.kind=='filtration' or nb.kind=='filtration') and commodity~='water' and commodity~='saltwater' then return 'filtration treats water only' end
    local count=0
    for _,e in ipairs(self.g:edgesAt(a)) do
      if e.commodity==commodity and ((e.a==a and e.b==b) or (e.b==a and e.a==b)) then count=count+1 end
    end
    if count>=self:parallelLimit(a,b) then return count>0 and 'parallel limit reached: use or upgrade pipe binders' or 'that pipe already exists' end
    for _,id in ipairs({a,b}) do
      if count==0 and self:connectionPorts(id)>=self.g.nodes[id].ports then return 'no free connections there' end
    end
    local reach=self:rangeBetween(a,b,nil,commodity,size)
    if dist(na,nb)>reach then
      return voltage and ('too long at '..D.voltages[voltage].kv..' kV: a tower every '..reach..' m')
        or 'too far: use a pump, lay a bigger main, or keep binder spurs short'
    end
    local mult,blocker=self:crossingCost(na.x,na.y,nb.x,nb.y)
    if not mult then return 'cannot cross '..string.lower(City.OBSTACLES[blocker.kind].name) end
    if not self:sizeRange(a,b) then return 'needs a structure between them to change pipe size' end
    if voltage then return self:boostError(a,b,voltage) end
  end
  function City:powerRating(e)
    local voltage=D.voltages[e.voltage or 'medium']
    local amps=D.amps[e.size or 'small'] or 500
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
  function City:pipeQuote(a,b,commodity,size,rail,grade)
    local q=base.pipeQuote(self,a,b,commodity,size,rail,grade)
    if commodity=='power' and not rail then
      q.voltage=self.quoteVoltage or self:cableVoltage(a,b) or 'low'
      local multiplier=D.voltageCost[q.voltage]
      q.tiein=math.ceil(q.tiein*multiplier); q.trench=math.ceil(q.trench*multiplier); q.bore=math.ceil(q.bore*multiplier)
      q.total=q.tiein+q.trench+q.bore
      q.capacity=self:powerRating({a=a,b=b,cap=1,capMax=1,size=City.asSize(size).key,voltage=q.voltage})
    end
    return q
  end
  function City:treatedWater(id)
    local seen,queue={[id]=true},{id}
    local filtered,source=false,false
    for _,nodeId in ipairs(queue) do
      local n=self.g.nodes[nodeId]
      filtered=filtered or n.kind=='filtration'
      source=source or (n.kind=='source' and n.commodity=='water' and (n.effectiveOutput or n.output or 0)>0)
      for _,e in ipairs(self.g:edgesAt(nodeId)) do
        if e.commodity=='water' and e.cap>0 then
          local other=e.a==nodeId and e.b or e.a
          if not seen[other] then seen[other]=true; queue[#queue+1]=other end
        end
      end
    end
    return filtered and source
  end
  function City:layPipe(a,b,commodity,size,rail,grade)
    -- Existing parallel mains must have the same bore and lining.
    if not rail and self:pipeBetween(a,b,commodity) then
      local existing=self.g.edges[self:pipeBetween(a,b,commodity)]
      if existing.size~=City.asSize(size).key or existing.grade~=(grade or self.lining or 1) then return nil,'parallel mains must use identical size and lining' end
    end
    local voltage=commodity=='power' and not rail and self:cableVoltage(a,b) or nil
    local e,err=base.layPipe(self,a,b,commodity,size,rail,grade)
    if e then
      if voltage then e.voltage=voltage end
      if commodity=='water' then e.hydraulic=true; e.filtered=self:treatedWater(a) or self:treatedWater(b) end
      self:refresh()
    end
    return e,err
  end
  function City:replacePipe(id,size,grade)
    local e,err=base.replacePipe(self,id,size,grade)
    if e then
      e.calcification=0
      if e.commodity=='water' then e.filtered=self:treatedWater(e.a) end
      self:refresh()
    end
    return e,err
  end
  function City:replaceQuote(id,size,grade)
    local e=self.g.edges[id]
    local held=self.quoteVoltage
    self.quoteVoltage=e and e.voltage or nil
    local q=base.replaceQuote(self,id,size,grade)
    self.quoteVoltage=held
    return q
  end
  function City:convertError(id,kind)
    local n=self.g.nodes[id]
    if n and (n.kind=='binder' or D.towers[n.kind]) then return 'demolish and rebuild specialist equipment' end
    return base.convertError(self,id,kind)
  end
  function City:refresh()
    for _,n in ipairs(self.g:aliveNodes()) do
      n.effectiveOutput=self.shockOutput and self:shockOutput(n) or nil
      if n.kind=='source' and (n.commodity=='water' or n.commodity=='wheat') and self:pollutionAt(n.x,n.y)>=D.pollution.stopAt then n.effectiveOutput=0 end
    end
    local runs={}
    for _,key in ipairs(D.voltageOrder) do runs[key]=self:boostRuns(key) end
    for _,e in ipairs(self.g.edges) do
      e.effectiveCap=nil; e.unboosted=nil
      e.spillWanted=e.alive and ((e.bulk=='sea' and e.shipSpill) or (e.commodity=='oil' and not e.bulk and e.leaking and math.max(0,(e.capMax or e.cap)-e.cap))) or nil
      if e.alive and e.commodity=='power' and e.voltage and not e.rail then
        e.effectiveCap=self:powerRating(e)
        local r=runs[e.voltage]
        local near=math.min(r[e.a] or math.huge,r[e.b] or math.huge)
        -- A booster that has been demolished leaves the cable beyond it dead.
        if near<math.huge and near+cableLength(self,e)>D.voltages[e.voltage].boost then e.unboosted=true; e.effectiveCap=0 end
      end
      if e.alive and e.commodity=='water' and e.hydraulic then e.effectiveCap=self:waterRating(e) end
    end
    local result=base.refresh(self)
    if self.updateFiltration then self:updateFiltration() end
    return result
  end
  function City:worksOutput(n)
    if farm(n) and self:pollutionAt(n.x,n.y)>=D.pollution.stopAt then return 0 end
    return base.worksOutput(self,n)
  end
  function City:sourceIncome(n)
    if n.effectiveOutput==0 then return 0 end
    return base.sourceIncome(self,n)
  end
  function City:leakChance(e)
    if e.commodity=='power' and e.voltage then return City.rules.leakBase*0.55*self:gradeOf(e).risk end
    local pressure=1
    if e.commodity=='water' and e.hydraulic then local _,bar=self:waterRating(e); pressure=math.max(1,bar/3) end
    return math.min(1,base.leakChance(self,e)*pressure*(e.commodity=='water' and e.filtered and D.filterRisk or 1))
  end
  function City:expenseBreakdown()
    local b=base.expenseBreakdown(self)
    local extra=#self.g:nodesOfKind('lab')*(D.pollution.labUpkeep-1)+#self.g:nodesOfKind('filtration')*3
    b.structures=b.structures+extra; b.total=b.total+extra
    return b
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
  function City:endDay()
    if self.bankrupt then return nil end
    self:refresh()
    -- Spills and cleanup settle once; previews and refresh never change pollution.
    local spill=self:environmentDay()
    local report=base.endDay(self)
    if report then
      report.pollution=spill
      if spill>0 then report.event=string.format('Oil pollution added: %.1f. Inspect affected districts and cleanup labs.',spill) end
    end
    return report
  end
  function City:migrate()
    base.migrate(self)
    for _,n in ipairs(self.g:aliveNodes()) do
      if n.kind=='binder' then n.bundleLanes=n.bundleLanes or 2 end
    end
    -- Existing infrastructure keeps its installed ports, siting and cable capacity.
    -- New construction uses engineering rules; importing never strands old clients.
    if (self.infrastructureVersion or 0)<3 then
      -- Pylons and transformers become towers of the highest voltage they carry,
      -- and a transformer becomes that tower's upgrade. Their cables keep working
      -- at whatever length they were laid.
      for _,n in ipairs(self.g.nodes) do
        if n.kind=='pylon' or n.kind=='transformer' then
          local top
          for _,e in ipairs(self.g:edgesAt(n.id)) do
            if e.voltage and (not top or RANK[e.voltage]>RANK[top]) then top=e.voltage end
          end
          if n.kind=='transformer' then n.upgrade='transformer' end
          n.kind=D.voltages[top or 'medium'].tower
          n.ports=math.max(n.ports or 0,Graph.KINDS[n.kind].ports)
        end
      end
      for _,e in ipairs(self.g.edges) do
        if e.commodity=='power' and e.voltage then e.legacySpan=true end
      end
      self.lineVoltage=nil
    end
    self.infrastructureVersion=3
  end
  function City.new(opts)
    local c=base.new(opts); c.infrastructureVersion=3; return c
  end
end
