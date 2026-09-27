-- The September design requirements. Persistent state lives on the company,
-- nodes and edges; previews never advance time or consume random numbers.
return function(City)
  City.PLANTS.seapump={name="SEAWATER PUMP",blurb="Pumps 50 saltwater from the sea. Connect a filter with armoured pipes."}
  City.BUILDABLE.tower=nil
  City.INFRA.kinds.transformer.legacy=false
  City.BUILDABLE.transformer=true
  City.trade.saltwater={}; for k,v in pairs(City.trade.water) do City.trade.saltwater[k]=v end
  City.trade.saltwater.sourceUpkeep=18
  for _,key in ipairs({'gems','jewelry'}) do
    City.trade[key]={}; for k,v in pairs(City.FORMS.solid) do City.trade[key][k]=v end
    City.trade[key].importCost=0; City.trade[key].sourceUpkeep=0
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
  function City:loadDepot(id)
    local n=self.g.nodes[id]
    if not n or not n.alive or n.kind~='depot' then return nil,'select a storage depot' end
    local key=n.commodity or 'water'
    local amount=math.min(self.stock[key] or 0,(n.capacityStore or City.depotCapacity)-(n.stored or 0))
    if amount<=0 then return nil,'no stored goods or no room in this depot' end
    self.stock[key]=self.stock[key]-amount; n.stored=(n.stored or 0)+amount
    self:refresh(); return amount
  end
  function City:requestPremium(c)
    if c.powerRequest and not c.prospect then return (c.powerOfferRate or 6)/6-1 end
    return self:ratePremium(c)
  end
  -- Whether this household would ever take a second utility. Decided from a
  -- hash of the company and the building rather than from City:random(), so it
  -- neither reshuffles the stream a save shares with its leaks and offers nor
  -- changes when the company is reloaded.
  --
  -- A house wants water. Some houses also want electricity, and those are the
  -- only ones ever asked: a household is not two contracts by definition.
  function City:wantsSecondUtility(c)
    if c.clientType~='house' and c.clientType~='estate' then return false end
    return self:unit(c.id,29)<City.DUAL.share
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
end
