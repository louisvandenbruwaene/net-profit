-- The September design requirements. Persistent state lives on the company,
-- nodes and edges; previews never advance time or consume random numbers.
local Graph=require('graph')
return function(City)
  City.PLANTS.seapump={name="SEAWATER PUMP",blurb="Pumps 50 saltwater from the sea. Connect a filter with armoured pipes."}
  City.BUILDABLE.tower=nil
  City.ORDERS.dispatchers.blurb='Each dispatcher reveals one ring of neighboring regions, up to four.'
  City.ORDERS.engineers.blurb='Replace failing lines before they lose delivery capacity. Replacement costs are charged.'
  City.ORDERS.estates.blurb='Buy discounted land within the minimum discount, maximum price and cash reserve you set.'
  City.INFRA.kinds.transformer.legacy=false
  City.BUILDABLE.transformer=true
  City.ORDERS.analysts={name='Market analysts',hire=1000,wage=25,clients=0,blurb='+10 percentage points expected return per analyst, +1 per week of service; wages grow 1% weekly.'}
  City.ORDER_LIST={'surveyors','dispatchers','engineers','estates','analysts'}
  City.trade.saltwater={}; for k,v in pairs(City.trade.water) do City.trade.saltwater[k]=v end
  City.trade.saltwater.sourceUpkeep=18; City.trade.saltwater.wholesale=0; City.trade.saltwater.wholesalePerUnit=0
  for _,key in ipairs({'gems','jewelry'}) do
    City.trade[key]={}; for k,v in pairs(City.FORMS.solid) do City.trade[key][k]=v end
    City.trade[key].importCost=0; City.trade[key].sourceUpkeep=0; City.trade[key].wholesale=0; City.trade[key].wholesalePerUnit=0
  end
  function City:workerCount(key)
    local n=(self.orders or {})[key]
    return n==true and 1 or tonumber(n) or 0
  end
  function City:investmentDistribution()
    local r=City.rules
    local mean=r.investMean
    for _,day in ipairs(self.analystHired or {}) do mean=mean+.10+.01*math.floor(math.max(0,self.day-day)/7) end
    -- Widening for ever turned a settlement into a lottery the house could not
    -- lose, because the payout floor clipped the left tail off. It stops where
    -- a total loss is still four deviations out: see the note in economy.lua.
    local cap=(1+mean)/r.investSdRuin
    return mean,math.min(cap,r.investSdPerDay*math.max(0,self.day-1))
  end
  function City:hireOrder(key)
    local spec=City.ORDERS[key]
    if not spec then return nil,'no such department' end
    local count=self:workerCount(key)
    local limit=key=='analysts' and math.huge or 4
    if count>=limit then return nil,'staff limit reached' end
    if not self:orderAvailable(key) then return nil,'needs '..spec.clients..' customers' end
    if self.money<spec.hire then return nil,'not enough cash' end
    self:spend(spec.hire); self.orders[key]=count+1
    if key=='analysts' then self.analystHired=self.analystHired or {}; table.insert(self.analystHired,self.day) end
    if key=='dispatchers' then self:survey() end
    self:refresh(); return true
  end
  function City:dismissOrder(key)
    local count=self:workerCount(key)
    if count==0 then return nil,'not on the books' end
    self.orders[key]=count>1 and count-1 or nil
    if key=='analysts' then table.remove(self.analystHired) end
    self:refresh(); return true
  end
  function City:orderWages()
    local total=0
    for key,spec in pairs(City.ORDERS) do
      if key~='analysts' then total=total+self:workerCount(key)*spec.wage end
    end
    for _,day in ipairs(self.analystHired or {}) do total=total+City.ORDERS.analysts.wage*1.01^math.floor(math.max(0,self.day-day)/7) end
    return math.ceil(total)
  end
  function City:preventLeak(e,report)
    if self:workerCount('engineers')==0 then return false end
    local quote=self:replaceQuote(e.id,e.size,e.grade)
    local cost=quote and quote.net or self:repairCost(e)
    if self.money<cost then return false end
    self:spend(cost); e.calcification=0; e.cap=e.capMax or e.cap; e.decayTick=nil
    if quote then e.paid=quote.total end
    report.prevented=(report.prevented or 0)+1; report.preventCost=(report.preventCost or 0)+cost
    return true
  end
  -- The same seed, coordinate and day always produce the same advertised offer,
  -- including regions discovered halfway through a day. No preview rerolls it.
  function City:landDiscount(d)
    if not d or not d.col or not d.row then return 0 end
    local n=((self.seed or 1)+d.col*73856093+d.row*19349663+self.day*83492791)%2147483647
    n=(n*16807)%2147483647
    local roll=n/2147483647
    if roll<.01 then return .5 elseif roll<.03 then return .4 elseif roll<.06 then return .3 elseif roll<.10 then return .2 elseif roll<.15 then return .1 end
    return 0
  end
  local districtCost=City.districtCost
  function City:districtCost(d) return math.ceil(districtCost(self,d)*(1-self:landDiscount(d))) end
  local districtError=City.districtError
  function City:districtError(id)
    local why=districtError(self,id)
    if why=='not next to your ground' then
      return self:districtCost(self.districts[id])>self.money and 'not enough cash' or nil
    end
    return why
  end
  function City:setEstatePolicy(discount,maxPrice)
    if type(discount)~='number' or type(maxPrice)~='number' or discount~=discount or maxPrice~=maxPrice then return nil,'invalid policy' end
    self.estateDiscount=math.floor(math.max(.1,math.min(.5,discount))*10+.5)/10; self.estateMax=math.max(0,math.min(100000000,math.floor(maxPrice)))
    return true
  end
  local runOrders=City.runOrders
  function City:runOrders(report)
    -- Dispatchers survey; requests remain the player's decisions. Engineers
    -- prevent failures at the wear step rather than widening arbitrary mains.
    local saved=self.orders
    self.orders={surveyors=saved.surveyors}
    runOrders(self,report)
    self.orders=saved
    if self:workerCount('estates')>0 then
      for _=1,self:workerCount('estates') do
        local best,price
        for _,d in ipairs(self.districts) do
          local cost=self:districtCost(d)
          if not d.owned and self:landDiscount(d)>=(self.estateDiscount or .3) and cost<=(self.estateMax or 4000)
            and self.money-cost>=(self.estateReserve or 4000) and not self:districtError(d.id)
            and (not price or cost<price) then best,price=d,cost end
        end
        if not best then break end
        self:buyDistrict(best.id); report.bought=best.name
      end
    end
  end
  function City:districtVisible(d)
    if not d or not d.col or not d.row then return false end
    if d.owned then return true end
    local radius=math.max(1,self:workerCount('dispatchers'))
    for _,home in ipairs(self.districts) do
      if home.owned and math.max(math.abs(home.col-d.col),math.abs(home.row-d.row))<=radius then return true end
    end
    return false
  end
  function City:updateFiltration()
    for _,commodity in ipairs({'water','saltwater'}) do
      local raw,clean={},{}
      local function spread(seen,start,stopFilter)
        local q={}
        for id in pairs(start) do seen[id]=true; q[#q+1]=id end
        local head=1
        while head<=#q do
          local id=q[head]; head=head+1
          local n=self.g.nodes[id]
          if not stopFilter or n.kind~='filtration' then
            for _,e in ipairs(self.g:edgesAt(id)) do
              if e.commodity==commodity and e.cap>0 then
                local other=e.a==id and e.b or e.a
                if not seen[other] then seen[other]=true; q[#q+1]=other end
              end
            end
          end
        end
      end
      local sources={}
      for _,n in ipairs(self.g:aliveNodes()) do
        if (n.kind=='source' and n.commodity==commodity and (n.effectiveOutput or n.output or 0)>0)
          or (n.kind=='works' and n.makes==commodity and (n.ready or 0)>0) then sources[n.id]=true end
      end
      spread(raw,sources,true)
      local filters={}
      for _,n in ipairs(self.g:nodesOfKind('filtration')) do if raw[n.id] then filters[n.id]=true end end
      spread(clean,filters,false)
      for _,e in ipairs(self.g.edges) do
        if e.alive and e.commodity==commodity then
          local a,b=self.g.nodes[e.a],self.g.nodes[e.b]
          e.filtered=clean[e.a] and clean[e.b] and (not raw[e.a] or a.kind=='filtration') and (not raw[e.b] or b.kind=='filtration') or false
        end
      end
    end
  end
  local leakChance=City.leakChance
  function City:leakChance(e)
    local chance=leakChance(self,e)
    if e.commodity=='saltwater' then return math.min(1,chance*8*(e.filtered and .25 or 1)) end
    if e.commodity=='water' then chance=chance+math.max(0,(e.calcification or 0)-99)*.001*self:gradeOf(e).risk end
    return math.min(1,chance)
  end
  local upgradeSource=City.upgradeSource
  function City:upgradeSource(id)
    local n=self.g.nodes[id]
    if n and n.commodity=='water' and (n.level or 1)>=4 then return nil,'maximum well output: 50' end
    return upgradeSource(self,id)
  end
  function City:loadDepot(id)
    local n=self.g.nodes[id]
    if not n or not n.alive or n.kind~='depot' then return nil,'select a storage depot' end
    local key=n.commodity or 'water'
    local amount=math.min(self.stock[key] or 0,(n.capacityStore or City.depotCapacity)-(n.stored or 0))
    if amount<=0 then return nil,'no stored goods or no room in this depot' end
    self.stock[key]=self.stock[key]-amount; n.stored=(n.stored or 0)+amount
    self:refresh(); return amount
  end
  local build=City.build
  function City:build(x,y,kind,recipe)
    if kind=='tower' then return nil,'use a filtration plant' end
    return build(self,x,y,kind,recipe)
  end
  local sourceCost=City.sourceCost
  function City:sourceCost(commodity,x,y,plant)
    if commodity=='saltwater' then return 1600 end
    return sourceCost(self,commodity,x,y,plant)
  end
  local sourceError=City.sourceError
  function City:sourceError(commodity,x,y,plant)
    if commodity~='saltwater' then return sourceError(self,commodity,x,y,plant) end
    if not y or y>=0 or self:districtAt(x,y) then return 'place the seawater pump on the sea' end
    local coast=self:districtAt(x,1)
    if not coast or not coast.owned or y< -220 then return 'needs owned coastline within 220 m' end
    for _,n in ipairs(self.g:aliveNodes()) do if (n.x-x)^2+(n.y-y)^2<City.rules.minSpacing^2 then return 'too close to another structure' end end
  end
  local buySource=City.buySource
  function City:buySource(commodity,x,y,plant)
    if commodity=='saltwater' then
      local why=self:sourceError(commodity,x,y,plant); if why then return nil,why end
      if self.money<1600 then return nil,'not enough cash' end
      self:spend(1600)
      local n=self.g:addNode(x,y,'source'); n.commodity=commodity; n.output=50; n.ports=1; n.paid=1600; n.plant='seapump'; n.upkeep=18
      self:refresh(); return n
    end
    local n,why=buySource(self,commodity,x,y,plant)
    if n and plant=='wind' then local d=self:districtAt(x,y); if d and d.island then n.output=math.ceil(n.output*1.5); n.islandBonus=true; self:refresh() end end
    return n,why
  end
  local licensed=City.licensed
  function City:licensed(key)
    if key=='saltwater' or key=='gems' or key=='jewelry' then return true end
    return licensed(self,key)
  end
  local replaceError=City.replaceError
  function City:replaceError(id,size,grade)
    local e=self.g.edges[id]
    if e and e.commodity=='saltwater' and (grade or e.grade or 1)<3 then return 'saltwater needs armoured or sealed pipes' end
    return replaceError(self,id,size,grade)
  end
  local convertError=City.convertError
  function City:convertError(id,kind)
    if kind=='tower' then return 'use filtration instead' end
    return convertError(self,id,kind)
  end
  local layPipe=City.layPipe
  function City:layPipe(a,b,commodity,size,rail,grade)
    if commodity=='saltwater' then
      local na,nb=self.g.nodes[a],self.g.nodes[b]
      if not na or not nb then return nil,'choose two buildings' end
      if (grade or self.lining or 1)<3 then return nil,'saltwater needs armoured or sealed pipes' end
      local filtered=na.kind=='filtration' or nb.kind=='filtration'
      for _,id in ipairs({a,b}) do for _,e in ipairs(self.g:edgesAt(id)) do filtered=filtered or e.commodity=='saltwater' and e.filtered end end
      if not filtered then return nil,'route saltwater through a filter first' end
    end
    return layPipe(self,a,b,commodity,size,rail,grade)
  end
  function City:requestPremium(c)
    if c.powerRequest and not c.prospect then return (c.powerOfferRate or 6)/6-1 end
    return self:ratePremium(c)
  end
  function City:offerElectricity(c)
    c.powerRequest=true; c.powerOfferRate=self:offerRate(6)
  end
  function City:nextRequest()
    local best
    for _,c in ipairs(self:clientList(true)) do
      if not best or self:requestPremium(c)>self:requestPremium(best) or self:requestPremium(c)==self:requestPremium(best) and c.id<best.id then best=c end
    end
    for _,c in ipairs(self:clientList()) do
      if c.powerRequest and (not best or self:requestPremium(c)>self:requestPremium(best)) then best=c end
    end
    return best
  end
  local acceptClient,declineClient=City.acceptClient,City.declineClient
  function City:acceptClient(id)
    local c=self.g.nodes[id]
    if c and c.powerRequest and not c.prospect then
      c.powerAccepted=true; c.powerRequest=nil; c.utilityRates=c.utilityRates or {}; c.utilityRates.power=c.powerOfferRate or 6; c.demands=c.demands or {[c.commodity]=c.demand}; c.demands.power=c.clientType=='estate' and 4 or 2
      self:refresh(); return c
    end
    return acceptClient(self,id)
  end
  function City:declineClient(id)
    local c=self.g.nodes[id]
    if c and c.powerRequest and not c.prospect then c.powerRequest=nil; c.powerDeclined=self.day; return c end
    return declineClient(self,id)
  end
  local buyLicence=City.buyLicence
  function City:buyLicence(key)
    local ok,why=buyLicence(self,key)
    if ok and key=='power' then
      for _,c in ipairs(self:clientList()) do if c.commodity=='water' and (c.clientType=='house' or c.clientType=='estate') then self:offerElectricity(c) end end
      self:refresh()
    end
    return ok,why
  end
  function City:clearTerrain(index)
    local o=self.obstacles[index]
    if not o or (o.kind~='park' and o.kind~='bedrock') then return nil,'select woodland or mountain' end
    if not self.permits[o.kind] then return nil,'requires the terrain permit' end
    -- Every affected region must belong to the company before a range is cleared.
    for col=math.floor((o.x-o.r)/City.MAP.w)+1,math.floor((o.x+o.r)/City.MAP.w)+1 do
      for row=math.floor((o.y-o.r)/City.MAP.h)+1,math.floor((o.y+o.r)/City.MAP.h)+1 do
        local d=self:cellAt(col,row); if not d or not d.owned then return nil,'buy all regions covered by this terrain first' end
      end
    end
    local units=math.floor(o.r*o.r/100)
    local cost=math.ceil(units*(o.kind=='park' and 4 or 35))
    if self.money<cost then return nil,'clearing costs $'..cost end
    self:spend(cost); local key=o.kind=='park' and 'timber' or 'rock'; self.stock[key]=(self.stock[key] or 0)+units
    if o.kind=='bedrock' and self:random()<.05 then self.stock.gems=(self.stock.gems or 0)+math.max(1,math.floor(units/100)) end
    table.remove(self.obstacles,index); self:refresh(); return true
  end
  local dailyRevenue=City.dailyRevenue
  function City:dailyRevenue()
    return dailyRevenue(self)+(((self.detail or {}).yard or {}).jewelry or 0)*900
  end
  local endDay=City.endDay
  function City:endDay()
    if self.bankrupt then return nil end
    self:updateFiltration()
    for _,e in ipairs(self.g.edges) do if e.alive and e.commodity=='water' and not e.filtered then e.calcification=(e.calcification or 0)+1 end end
    local report=endDay(self)
    if report then
      for _,c in ipairs(self:clientList()) do
        if self.licences.power and c.commodity=='water' and (c.clientType=='house' or c.clientType=='estate') and not (c.demands or {}).power
          and not c.powerRequest and (not c.powerDeclined or self.day-c.powerDeclined>=7) and self:random()<math.min(1,3*(City.rules.arriveBase+self.reputation/500+(self.adDaysLeft>0 and City.rules.adBoost or 0))) then self:offerElectricity(c) end
      end
      self:refresh()
    end
    return report
  end
  local new=City.new
  function City.new(opts)
    local c=new(opts); c.ideasVersion=1; return c
  end
  local migrate=City.migrate
  function City:migrate()
    migrate(self)
    self.analystHired=self.analystHired or {}
    if not self.ideasVersion then
      for _,n in ipairs(self.g:aliveNodes()) do
        if n.kind=='tower' then n.kind='filtration'; n.ports=math.max(2,self.g:degree(n.id)) end
        if n.kind=='depot' then n.capacityStore=math.max(100,n.capacityStore or 0) end
        if n.kind=='source' and n.commodity=='water' then
          n.level=math.min(4,n.level or 1); n.output=20+(n.level-1)*10; n.cap=50; n.ports=math.max(1,self:connectionPorts(n.id))
        end
      end
      self.ideasVersion=1
    end
    self:survey()
  end
end
