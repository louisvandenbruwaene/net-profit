local P = require("palette")
local City = require("city")
local Graph = require("graph")
local R = require("render")
local UI = {width=320, buttons={}}
local lg = love.graphics
local state, city, act, scroll, H, W

local function text(s,x,y,font,color,width)
  lg.setFont(R.fonts[font or "body"])
  lg.setColor(color or P.text)
  if width then lg.printf(tostring(s),x,y,width) else lg.print(tostring(s),x,y) end
end

local function button(id,label,x,y,w,h,fn,enabled,tip,active,color)
  enabled = enabled ~= false
  local mx,my = love.mouse.getPosition()
  local hover = mx>=x and mx<x+w and my>=y and my<y+h
  local inClip = not scroll or (y>=160 and y+h<=H-62)
  color = color or P.flow
  lg.setColor(active and P.with(color,0.22) or hover and P.gridMajor or P.panel)
  lg.rectangle("fill",x,y,w,h,4)
  lg.setColor(active and color or P.panelEdge); lg.setLineWidth(1)
  lg.rectangle("line",x,y,w,h,4)
  local font = R.fonts.body
  if font:getWidth(label)>w-16 then font=R.fonts.small end
  lg.setFont(font); lg.setColor(enabled and (active and color or P.text) or P.textFaint)
  lg.printf(label,x+6,y+(h-font:getHeight())/2,w-12,"center")
  if inClip then UI.buttons[#UI.buttons+1]={id=id,x=x,y=y,w=w,h=h,fn=fn,enabled=enabled,tip=tip} end
end

local function line(y)
  lg.setColor(P.panelEdge); lg.setLineWidth(1); lg.line(20,y,300,y)
end

local function row(label,value,y,color)
  text(label,22,y,"small",P.textDim)
  lg.setFont(R.fonts.body); lg.setColor(color or P.text)
  lg.printf(tostring(value),145,y-1,151,"right")
end

local toolTips = {
  junction="Junction: 3 ports, $22; $1 daily upkeep.",
  manifold="Manifold: 6 ports, $46; $1 daily upkeep. Shares ground across trades.",
  pump="Pump: 2 ports, reaches 520m, $38; $1 daily upkeep.",
  tower="Treatment station: halves nearby pipe risk again (220m radius), $92; $1 daily upkeep.",
}

local function network()
  local y=174-state.scroll
  text("PIPE NETWORK",22,y,"small",P.textDim)
  for i,name in ipairs({"water","beer","oil"}) do
    button(name,string.upper(name),22+(i-1)*94,y+25,88,32,function() state.commodity=name end,
      city.licences[name],city.licences[name] and "Separate "..name.." network" or "Acquire the licence in Company",state.commodity==name,Graph.COMMODITIES[name].color)
  end
  text("Pipe capacity",22,y+77,"body",P.textDim)
  button("capacity-minus","-",169,y+69,32,32,function() state.capacity=math.max(1,state.capacity-1) end,true,"Decrease capacity")
  text(state.capacity,218,y+77)
  button("capacity-plus","+",264,y+69,32,32,function() state.capacity=math.min(24,state.capacity+1) end,true,"Increase capacity; $12 per extra unit")
  local names={"junction","manifold","pump","tower"}
  local symbols={"+","++",">","T"}
  for i,name in ipairs(names) do
    button("tool-"..name,symbols[i],22+(i-1)*70,y+123,64,44,function() state.tool=state.tool==name and nil or name end,
      city.money>=City.price[name],toolTips[name],state.tool==name,Graph.KINDS[name].color)
    text("$"..City.price[name],36+(i-1)*70,y+174,"small",P.textDim)
  end
  button("source","New "..state.commodity.." source  $"..city:sourceCost(state.commodity),22,y+205,274,34,
    function() state.tool=state.tool=="source" and nil or "source" end,
    city.money>=city:sourceCost(state.commodity),"Place a source: water output 14, other trades 10; $12 daily wholesale, $6 upkeep",state.tool=="source",P.good)
  line(y+260)
  local n=city.g.nodes[state.node or 0]
  local e=city.g.edges[state.edge or 0]
  y=y+278
  if n and n.alive then
    text(n.kind=="client" and City.CLIENTS[n.clientType].name.." "..n.id or Graph.KINDS[n.kind].name.." "..n.id,22,y,"mid")
    y=y+34
    if n.kind=="client" then
      row("Commodity",string.upper(n.commodity),y,Graph.COMMODITIES[n.commodity].color)
      row("Daily contract","$"..n.demand*n.rate,y+26,P.energy)
      row("Delivery",(city.served[n.id] or 0).." / "..n.demand,y+52)
      row(n.prospect and "Offer expires" or "Patience",n.prospect and (n.expires-city.day+1).." days" or n.grace.." days",y+78,P.warn)
      if n.prospect then
        button("accept","Sign contract",22,y+115,173,34,function() act("acceptClient",n.id) end,true,"Delivery deadline starts when signed")
        button("decline","Decline",202,y+115,94,34,function() act("declineClient",n.id) end,true,"Decline without a reputation penalty")
      else
        button("supply-valve",n.supplyClosed and "[ ]  Customer supply" or "[x]  Customer supply",22,y+115,274,34,
          function() act("toggleSupply",n.id) end,true,
          "Controls this customer's delivery only. The main stays open; unsupplied customers still lose patience.",
          not n.supplyClosed,P.good)
      end
    else
      row("Ports",city.g:degree(n.id).." / "..n.ports,y)
      if n.kind=="source" then row("Daily output",n.output.." "..n.commodity,y+26,P.good)
      elseif n.kind=="tower" then row("Local leak risk","-55%",y+26,P.energy)
      elseif n.kind=="pump" then row("Reach","520m",y+26,P.flow) end
      if n.kind~="source" then
        button("demolish-node","Demolish  +$"..math.floor((n.paid or city:nodeCost(n.kind))*0.4),22,y+68,274,34,
          function() act("demolishNode",n.id) end,true,"Removes attached pipes; recovers 40% of structure price")
      end
    end
  elseif e and e.alive then
    text(string.upper(e.commodity).." MAIN "..e.id,22,y,"mid",Graph.COMMODITIES[e.commodity].color)
    y=y+34
    row("Flow / capacity",math.abs(city.detail.edge[e.id] or 0).." / "..e.cap,y)
    row("Installed capacity",e.capMax,y+26)
    row("Condition",e.leaking and (e.cap==0 and "OUT OF SERVICE" or "LEAKING") or "Sound",y+52,e.leaking and P.bad or P.good)
    row("Daily leak risk",string.format("%.1f%%",city:leakChance(e)*100),y+78)
    button("upgrade","+ Capacity  $12",22,y+113,274,32,function() act("upgradePipe",e.id) end,city.money>=12 and e.capMax<24,"One more unit of installed capacity")
    button("repair","Repair  $"..city:repairCost(e),22,y+154,132,32,function() act("repairPipe",e.id) end,e.leaking and city.money>=city:repairCost(e),"Stops the leak and restores all installed capacity")
    button("reinforce","Line pipe  $26",162,y+154,134,32,function() act("reinforcePipe",e.id) end,e.grade<2 and city.money>=26,"Permanent lining halves this pipe's leak risk")
    button("demolish-pipe","Demolish  +$"..math.floor((e.paid or 0)*0.4),22,y+195,274,32,function() act("demolishPipe",e.id) end,true,"Recovers 40% of installation and capacity costs")
  else
    text("NETWORK HEALTH",22,y,"small",P.textDim)
    local leaks=0
    for _,pipe in ipairs(city.g.edges) do if pipe.alive and pipe.leaking then leaks=leaks+1 end end
    row("Open leaks",leaks,y+32,leaks>0 and P.bad or P.good)
    row("Supply shortfalls",city.unserved,y+58,city.unserved>0 and P.warn or P.good)
    row("Treatment grade",city.quality.." / 5",y+84)
    if leaks>0 then
      button("find-leak","Inspect next leak",22,y+121,274,34,function()
        for _,pipe in ipairs(city.g.edges) do if pipe.alive and pipe.leaking then act("focusEdge",pipe.id); break end end
      end,true,"Inspect a damaged pipe")
    end
  end
  UI.contentBottom=y+240+state.scroll
end

local function finance()
  local y=174-state.scroll
  text("TREASURY",22,y,"small",P.textDim)
  row("Projected revenue","+$"..city:dailyRevenue(),y+34,P.good)
  row("Operating costs","-$"..city:dailyExpenses(),y+62,P.warn)
  row("Daily net",string.format("$%+d",city:dailyRevenue()-city:dailyExpenses()),y+90,P.energy)
  row("Company value","$"..city:valuation(),y+118)
  line(y+154)
  text("CAPITAL & GROWTH",22,y+174,"small",P.textDim)
  button("invest-minus","-",22,y+204,34,34,function() state.invest=math.max(50,state.invest-50) end,true,"Decrease deposit by $50")
  button("invest","Invest $"..state.invest,63,y+204,192,34,function() act("invest",state.invest) end,city.money>=state.invest,"7 days locked; expected return 10%, standard deviation 5%; losses possible")
  button("invest-plus","+",262,y+204,34,34,function() state.invest=state.invest+50 end,true,"Increase deposit by $50")
  text("7-day fund / mean +10% / SD 5%",22,y+248,"small",P.textDim)
  local iy=y+274
  for _,inv in ipairs(city.investments) do
    row("$"..inv.amount.." invested",city:daysToMaturity(inv).." days left",iy,P.energy); iy=iy+26
  end
  button("ads",city.adDaysLeft>0 and "Advertising: "..city.adDaysLeft.." days left" or "Advertising campaign  $90",22,iy+8,274,34,function() act("buyAds") end,city.money>=90 and city.adDaysLeft==0,"Five days of increased customer enquiries")
  button("quality",city.quality>=5 and "Treatment fully upgraded" or "Treatment grade "..(city.quality+1).."  $"..city:qualityCost(),22,iy+51,274,34,function() act("upgradeQuality") end,city.quality<5 and city.money>=city:qualityCost(),"Each grade reduces base leak risk by 13% across all pipes")
  for i,name in ipairs({"beer","oil"}) do
    local cost=City.price[name.."Licence"]
    button("licence-"..name,city.licences[name] and string.upper(name).." licence held" or string.upper(name).." licence  $"..cost,22,iy+94+(i-1)*43,274,34,function() act("buyLicence",name) end,not city.licences[name] and city.money>=cost,"Opens "..name.." sources and high-value customer offers",false,Graph.COMMODITIES[name].color)
  end
  line(iy+192)
  text("RECENT CASH FLOW",22,iy+212,"small",P.textDim)
  local start=math.max(1,#city.history-6)
  local gy=iy+242
  for i=start,#city.history do
    local h=city.history[i]
    row("Day "..h.day,string.format("$%+d",h.revenue-(h.expenses or 0)),gy,h.revenue-(h.expenses or 0)>=0 and P.good or P.bad)
    gy=gy+25
  end
  UI.contentBottom=gy+state.scroll+25
end

local function customers()
  local y=174-state.scroll
  for _,prospect in ipairs({true,false}) do
    text(prospect and "CONNECTION ENQUIRIES" or "ACTIVE CUSTOMERS",22,y,"small",P.textDim)
    y=y+32
    local clients=city:clientList(prospect)
    if #clients==0 then text(prospect and "No open enquiries" or "No signed contracts",22,y,"small",P.textFaint); y=y+35 end
    for _,c in ipairs(clients) do
      local met=(city.served[c.id] or 0)>=c.demand
      local status=prospect and "Offer" or met and "Supplied" or (c.supplyClosed and "Valve shut / " or "")..c.grace.." days left"
      button("client-"..c.id,City.CLIENTS[c.clientType].name.." "..c.id.."   $"..c.rate*c.demand.."/day",22,y,274,33,function() act("focusNode",c.id) end,true,"Locate and inspect customer",state.node==c.id,Graph.COMMODITIES[c.commodity].color)
      text(c.demand.." "..c.commodity.." / "..status,30,y+40,"small",prospect and P.energy or met and P.good or P.warn)
      y=y+73
    end
    y=y+20
  end
  UI.contentBottom=y+state.scroll
end

local function ledger()
  local y=174-state.scroll
  text("COMPANY JOURNAL",22,y,"small",P.textDim)
  y=y+36
  if #city.log==0 then text("The company opened today.",22,y,"body",P.textDim) end
  for _,entry in ipairs(city.log) do
    text("DAY "..entry.day,22,y,"tiny",P.flow)
    local _,lines=R.fonts.body:getWrap(entry.text,268)
    text(entry.text,22,y+18,"body",P.text,268)
    y=y+28+#lines*R.fonts.body:getHeight()+17
  end
  UI.contentBottom=y+state.scroll
end

local function report()
  local r=city.lastReport
  local w,h=560,500
  local x,y=(W-w)/2,(H-h)/2
  lg.setColor(0,0,0,0.7); lg.rectangle("fill",0,0,W,H)
  lg.setColor(P.panel); lg.rectangle("fill",x,y,w,h,6)
  lg.setColor(P.panelEdge); lg.rectangle("line",x,y,w,h,6)
  if state.modal=="restart" then
    text("Start a new company?",x+32,y+34,"big")
    text("The current company save will be replaced.",x+32,y+95,"body",P.textDim,w-64)
    button("cancel-restart","Keep company",x+32,y+h-64,235,36,function() state.modal=nil end)
    button("confirm-restart","Start fresh",x+283,y+h-64,245,36,function() act("restart") end)
    return
  end
  text(city.bankrupt and "Company insolvent" or "Day "..r.day.." closed",x+32,y+30,"big")
  text("DAILY STATEMENT",x+32,y+78,"small",P.textDim)
  local entries={
    {"Customer & wholesale revenue",string.format("+$%d",r.revenue),P.good},
    {"Operating expenses",string.format("-$%d",r.expenses),P.warn},
    {"Investment profit / loss",string.format("$%+d",r.interest),P.energy},
    {"Municipal grants",string.format("+$%d",r.bonus or 0),P.good},
    {"Cash available","$"..city.money,P.text},
  }
  for i,v in ipairs(entries) do
    text(v[1],x+32,y+108+(i-1)*32,"body",P.textDim)
    text(v[2],x+390,y+108+(i-1)*32,"body",v[3])
  end
  local summary=string.format("%d supply shortfalls    %d customers lost",r.unhappy,#r.left)
  text(summary,x+32,y+296,"body",r.unhappy>0 and P.warn or P.good)
  text(string.format("%d leaking mains    %d out of service",#r.leaks,#r.burst),x+32,y+329,"body",#r.leaks+#r.burst>0 and P.bad or P.textDim)
  text(r.arrived and "New enquiry: "..r.arrived.name or "No new connection enquiries",x+32,y+362,"body",P.flow)
  if city.bankrupt then
    button("new-company","New company",x+32,y+h-66,w-64,38,function() state.modal="restart" end)
  else
    button("continue","Open day "..city.day,x+32,y+h-66,w-64,38,function() state.modal=nil end,true,"Return to the network")
  end
end

function UI.draw(c,s,action)
  city,state,act=c,s,action
  W,H=R.dimensions()
  UI.buttons={}; scroll=false
  lg.setColor(P.panel); lg.rectangle("fill",0,0,320,H)
  lg.rectangle("fill",320,0,W-320,80)
  lg.setColor(P.panelEdge); lg.line(320,0,320,H); lg.line(0,80,W,80)
  text("NET PROFIT",22,17,"big")
  text("MUNICIPAL WATER COMPANY",23,55,"tiny",P.textDim)
  local net=city:dailyRevenue()-city:dailyExpenses()
  local metrics={{"DAY",city.day,P.text},{"CASH","$"..city.money,P.energy},{"NET / DAY",string.format("$%+d",net),net>=0 and P.good or P.bad},{"CUSTOMERS",#city:clientList(),P.flow},{"REPUTATION",city.reputation.."%",P.text}}
  local width=(W-354)/5
  for i,m in ipairs(metrics) do
    local x=342+(i-1)*width
    local font=R.fonts.big:getWidth(tostring(m[2]))>width-14 and "mid" or "big"
    text(m[1],x,15,"tiny",P.textDim); text(m[2],x,35,font,m[3])
  end
  local tabs={{"network","Network"},{"finance","Company"},{"customers","Clients"},{"ledger","Log"}}
  for i,t in ipairs(tabs) do
    button("tab-"..t[1],t[2],12+(i-1)*77,103,73,34,function() state.tab=t[1]; state.scroll=0 end,true,nil,state.tab==t[1])
  end
  lg.setScissor(0,160,319,H-222); scroll=true
  if state.tab=="network" then network() elseif state.tab=="finance" then finance() elseif state.tab=="customers" then customers() else ledger() end
  scroll=false; lg.setScissor()
  UI.maxScroll=math.max(0,(UI.contentBottom or H)-(H-65))
  if UI.maxScroll>0 then
    lg.setColor(P.panelEdge); lg.rectangle("fill",311,165,3,H-236)
    lg.setColor(P.textDim); lg.rectangle("fill",311,165+(H-266)*math.min(1,state.scroll/UI.maxScroll),3,30)
  end

  local milestone
  for i,m in ipairs(City.MILESTONES) do if not city.milestones[i] then milestone=m; break end end
  lg.setColor(P.with(P.bg,0.94)); lg.rectangle("fill",321,81,W-321,47)
  if milestone then
    local count=#city:clientList()-city.unserved
    text(milestone.name.."   "..count.." / "..milestone.target.." supplied",342,97,"body",P.text)
    text("$"..milestone.reward.." grant",math.max(720,W-170),97,"small",P.energy)
  else text("UTILITY EMPIRE  /  Continue expanding",342,97,"body",P.good) end
  lg.setColor(P.panel); lg.rectangle("fill",0,H-58,W,58)
  lg.setColor(P.panelEdge); lg.line(0,H-58,W,H-58)
  button("undo","<",16,H-44,36,32,function() act("undo") end,#state.undo>0,"Undo last decision (Z); day closes are final")
  button("fit","[ ]",62,H-44,36,32,function() act("fit") end,true,"Fit the network (F)")
  button("mute",state.muted and "o" or "~",108,H-44,36,32,function() act("mute") end,true,"Toggle sound (M)")
  button("restart","New company",158,H-44,142,32,function() state.modal="restart" end,true,"Start another company")
  local message=state.toast or (state.tool and string.upper(state.tool).." selected" or "Operations open")
  text(message,340,H-34,"small",state.toastBad and P.bad or P.textDim,math.max(100,W-565))
  button("end-day","Close day "..city.day,W-193,H-46,173,36,function() act("endDay") end,not city.bankrupt,"Settle revenue, expenses, investments and pipe wear (Enter)",true,P.good)
  if state.modal then UI.buttons={}; report() end
  local mx,my=love.mouse.getPosition()
  for _,b in ipairs(UI.buttons) do
    if b.tip and mx>=b.x and mx<=b.x+b.w and my>=b.y and my<=b.y+b.h then
      local tw=math.min(320,W-24)
      local _,lines=R.fonts.small:getWrap(b.tip,tw-20)
      local th=#lines*R.fonts.small:getHeight()+20
      local tx=math.min(W-tw-12,math.max(12,mx+12))
      local ty=math.max(10,math.min(H-th-12,my-th-12))
      lg.setColor(P.bg); lg.rectangle("fill",tx,ty,tw,th,4)
      lg.setColor(P.panelEdge); lg.rectangle("line",tx,ty,tw,th,4)
      text(b.tip,tx+10,ty+10,"small",P.text,tw-20)
      break
    end
  end
end

function UI.click(x,y)
  for _,b in ipairs(UI.buttons) do
    if x>=b.x and x<=b.x+b.w and y>=b.y and y<=b.y+b.h then
      if b.enabled then b.fn() end
      return true
    end
  end
  return false
end

return UI
