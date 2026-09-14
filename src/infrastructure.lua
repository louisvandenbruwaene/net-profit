-- Engineering rules, kept separate from the company ledger and interface.
local Graph=require('graph')
local D=require('data.infrastructure')
return function(City)
  City.INFRA=D
  for key,spec in pairs(D.kinds) do City.price[key]=spec.cost; City.BUILDABLE[key]=true end
  City.PLANTS.wind.ground='any'
  City.PLANTS.wind.blurb='Wind generation on owned land or an island.'
  City.PLANTS.hydro={name='RIVER TURBINE',base=850,growth=1.3,output=8,upkeep=14,fuel=0,ground='river',blurb='Uses river flow. Must stand beside a river.'}
  City.PLANTS.solar={name='SOLAR ARRAY',base=1200,growth=1.3,output=10,upkeep=5,fuel=0,ground='land',blurb='Daily-average solar output. Requires 12 imported solar panels.'}
  City.PLANT_ORDER={'nuclear','hydro','wind','solar'}
  City.MATERIALS.solar={panels=12}
  City.trade.panels={importCost=22,wholesale=0,wholesalePerUnit=0,sourceUpkeep=0,form='solid'}
  for k,v in pairs(City.FORMS.solid) do City.trade.panels[k]=v end
  City.BUILD_UNLOCK.binder='massive'
  City.BUILD_UNLOCK.lab='works'
  local base={}
  for _,k in ipairs({'new','migrate','build','buySource','sourceCost','sourceError','placementError','pipeError','rangeBetween','sizeRange','pipeQuote','layPipe','replaceQuote','replacePipe','refresh','worksOutput','leakChance','endDay','sourceIncome','expenseBreakdown','convertError'}) do base[k]=City[k] end

  local function dist(a,b) return math.sqrt((a.x-b.x)^2+(a.y-b.y)^2) end
  local function electrical(n)
    return n.kind=='transformer' or n.kind=='pylon' or n.commodity=='power'
      or n.kind=='works' or n.kind=='exchange' or n.kind=='dc'
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
      local radius=(City.RECIPES[n.recipe or ''] or {}).farm and r*2 or r
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
      if (City.RECIPES[n.recipe or ''] or {}).farm and math.abs(n.x-x)<D.farmRadius and math.abs(n.y-y)<D.farmRadius then return 'that land is used by a farm' end
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
      if commodity=='water' then n.ports=2 end
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
  function City:voltageAt(id)
    local n=self.g.nodes[id]
    if n.kind=='transformer' then return nil end
    if n.kind=='source' and n.commodity=='power' then return n.voltage or 'high' end
    if n.kind=='client' or n.kind=='works' or n.kind=='exchange' then return 'low' end
    for _,e in ipairs(self.g:edgesAt(id)) do if e.commodity=='power' and e.voltage then return e.voltage end end
    return n.voltage
  end
  function City:lineVoltageFor(a,b)
    return self.lineVoltage or self:voltageAt(a) or self:voltageAt(b) or 'medium'
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
    if na and nb and (na.kind=='transformer' or nb.kind=='transformer' or na.kind=='pylon' or nb.kind=='pylon') then return 1,#City.PIPE_SIZES end
    return base.sizeRange(self,a,b)
  end
  function City:rangeBetween(a,b,rail,commodity)
    if rail then return base.rangeBetween(self,a,b,rail) end
    local na,nb=self.g.nodes[a],self.g.nodes[b]
    if commodity=='power' then
      if na.kind=='transformer' or nb.kind=='transformer' then
        -- Farms connect at the field boundary, not at the central map badge.
        local farm=(City.RECIPES[na.recipe or ''] or {}).farm or (City.RECIPES[nb.recipe or ''] or {}).farm
        return D.transformerRange+(farm and D.farmRadius or 0)
      end
      return D.voltages[self:lineVoltageFor(a,b)].range
    end
    if (na.kind=='binder')~=(nb.kind=='binder') then return D.binderRange end
    if na.kind=='pump' or nb.kind=='pump' then return D.pumpRange end
    return base.rangeBetween(self,a,b,rail)
  end
  function City:pipeError(a,b,commodity,rail)
    if rail then return base.pipeError(self,a,b,commodity,rail) end
    local na,nb=self.g.nodes[a],self.g.nodes[b]
    if not na or not nb or not na.alive or not nb.alive or a==b then return 'choose two different live buildings' end
    if not self:licensed(commodity) then return 'no licence for that' end
    if na.kind=='terminal' or nb.kind=='terminal' then return 'a haven ships by bulk line only' end
    if commodity=='power' then
      if not electrical(na) or not electrical(nb) then return 'electricity needs pylons and transformers, not water fittings' end
      local voltage=self:lineVoltageFor(a,b)
      if not D.voltages[voltage] then return 'choose a valid voltage' end
      local va,vb=self:voltageAt(a),self:voltageAt(b)
      if (va and va~=voltage) or (vb and vb~=voltage) then return 'voltage mismatch: use a transformer' end
    elseif na.kind=='transformer' or nb.kind=='transformer' or na.kind=='pylon' or nb.kind=='pylon' then return 'power equipment carries electricity only'
    elseif (na.kind=='filtration' or nb.kind=='filtration') and commodity~='water' then return 'filtration treats water only' end
    local count=0
    for _,e in ipairs(self.g:edgesAt(a)) do
      if e.commodity==commodity and ((e.a==a and e.b==b) or (e.b==a and e.a==b)) then count=count+1 end
    end
    if count>=self:parallelLimit(a,b) then return count>0 and 'parallel limit reached: use or upgrade pipe binders' or 'that pipe already exists' end
    for _,id in ipairs({a,b}) do
      if count==0 and self:connectionPorts(id)>=self.g.nodes[id].ports then return 'no free connections there' end
    end
    if dist(na,nb)>self:rangeBetween(a,b,nil,commodity) then
      return commodity=='power' and 'line too long: use higher voltage or place a pylon closer' or 'too far: use a pump; binder attachments must be short'
    end
    local mult,blocker=self:crossingCost(na.x,na.y,nb.x,nb.y)
    if not mult then return 'cannot cross '..string.lower(City.OBSTACLES[blocker.kind].name) end
    if not self:sizeRange(a,b) then return 'needs a structure between them to change pipe size' end
  end
  function City:powerRating(e)
    local voltage=D.voltages[e.voltage or 'medium']
    local amps=D.amps[e.size or 'small'] or 500
    local healthy=math.max(0,e.cap)/math.max(1,e.capMax or e.cap)
    local gross=math.sqrt(3)*voltage.kv*amps/100 -- 100 kW game units
    local resistance=(D.resistance[e.size or 'small'] or 0.12)*self:pipeLength(e)/1000
    local loss=math.min(0.8,3*amps*amps*resistance/(gross*100000))
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
    return math.min(e.cap,math.floor(capacity)),head*0.0981
  end
  function City:pipeQuote(a,b,commodity,size,rail,grade)
    local q=base.pipeQuote(self,a,b,commodity,size,rail,grade)
    if commodity=='power' and not rail then
      q.voltage=self:lineVoltageFor(a,b)
      local multiplier=({low=1,medium=1.3,high=2})[q.voltage]
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
    local e,err=base.layPipe(self,a,b,commodity,size,rail,grade)
    if e then
      if commodity=='power' and not rail then e.voltage=self:lineVoltageFor(a,b) end
      if commodity=='water' then e.hydraulic=true; e.filtered=self:treatedWater(a) or self:treatedWater(b) end
      self:refresh()
    end
    return e,err
  end
  function City:replacePipe(id,size,grade)
    local e,err=base.replacePipe(self,id,size,grade)
    if e then
      if e.commodity=='water' then e.filtered=self:treatedWater(e.a) end
      self:refresh()
    end
    return e,err
  end
  function City:replaceQuote(id,size,grade)
    local e=self.g.edges[id]
    local selected=self.lineVoltage
    if e and e.voltage then self.lineVoltage=e.voltage end
    local q=base.replaceQuote(self,id,size,grade)
    self.lineVoltage=selected
    return q
  end
  function City:convertError(id,kind)
    local n=self.g.nodes[id]
    if n and (n.kind=='binder' or n.kind=='transformer') then return 'demolish and rebuild specialist equipment' end
    return base.convertError(self,id,kind)
  end
  function City:refresh()
    for _,n in ipairs(self.g:aliveNodes()) do
      n.effectiveOutput=nil
      if n.kind=='source' and (n.commodity=='water' or n.commodity=='wheat') and self:pollutionAt(n.x,n.y)>=D.pollution.stopAt then n.effectiveOutput=0 end
    end
    for _,e in ipairs(self.g.edges) do
      e.effectiveCap=nil
      e.spillWanted=e.alive and ((e.bulk=='sea' and e.shipSpill) or (e.commodity=='oil' and not e.bulk and e.leaking and math.max(0,(e.capMax or e.cap)-e.cap))) or nil
      if e.alive and e.commodity=='power' and e.voltage then e.effectiveCap=self:powerRating(e) end
      if e.alive and e.commodity=='water' and e.hydraulic then e.effectiveCap=self:waterRating(e) end
    end
    return base.refresh(self)
  end
  function City:worksOutput(n)
    if (City.RECIPES[n.recipe or ''] or {}).farm and self:pollutionAt(n.x,n.y)>=D.pollution.stopAt then return 0 end
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
    self.infrastructureVersion=2
  end
  function City.new(opts)
    local c=base.new(opts); c.infrastructureVersion=2; return c
  end
end
