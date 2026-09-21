local City = require("city")
local Camera = require("camera")
local Save = require("company_save")
local Draw = require("company_render")
local E = require("experience")
local UI = require("company_ui")
local R = require("render")
local A = require("audio")
local P = require("palette")
local Audit = require("layout_audit")
local Graph = require("graph")
local App = {}
local city,cam
local state={commodity="water",havenKind="port",plant="nuclear",recipe="turbine",size="small",recentSizes={"small"},grade=1,capacity=1,invest=100,borrow=500,tab="network",scroll=0,undo={}}
local testMode, frames = nil,0
-- Rounds mode lives in the same window, on a City of its own, saved beside the
-- companies and never in one of their slots.
local ROUND_FILE,RECORD_FILE,MODE_FILE="rounds_city.lua","rounds_records.lua","mode.txt"
local roundsTest=false
local walkthroughRunning=false
local saveBlocked=false

local function toast(message,bad)
  state.toast,state.toastBad,state.toastTime=tostring(message),bad,5
end

local function saveRounds()
  if testMode then return true end
  -- A round in progress is never written: the break before it is what a
  -- reload comes back to, so a round cannot be replayed by quitting.
  if city.rounds.phase=="round" then return true end
  local ok,err=love.filesystem.write(ROUND_FILE,Save.pack(city))
  if not ok then toast("Save failed: "..tostring(err),true) end
  return ok
end

local function saveRecords()
  if testMode then return end
  love.filesystem.write(RECORD_FILE,require("rounds_io").encode(state.records))
end

local function noteRecord()
  local rs=city.rounds
  local rec=state.records
  if rs.strict then rec.bestStrict=math.max(rec.bestStrict or 0,rs.round)
  else rec.best=math.max(rec.best or 0,rs.round) end
  saveRecords()
end

local function save()
  if city.rounds then return saveRounds() end
  if testMode then return true end
  if saveBlocked then
    toast("Saved company is damaged. Choose another company slot; the original file is protected.",true)
    return nil
  end
  local ok,err=Save.write(city)
  if not ok then toast("Save failed: "..tostring(err),true) end
  return ok
end

local function layout()
  local w,h=R.dimensions()
  cam:setViewport(UI.width,84,w-UI.width,h-142)
end

-- Pull back far enough to see every district, bought or not.
local function fitWorld()
  layout()
  -- Frame what the company holds plus the ground it could buy next, not every
  -- cell that has ever been surveyed. On an endless map those are very
  -- different numbers, and only one of them fits on a screen.
  local x0,y0,x1,y1=city:ownedBounds()
  local margin=City.MAP.w*0.8
  x0,y0,x1,y1=x0-margin,y0-margin,x1+margin,y1+margin
  cam.x,cam.y=(x0+x1)/2,(y0+y1)/2
  cam.scale=math.max(0.12,math.min(1.45,cam.vw/(x1-x0),cam.vh/(y1-y0)))
  cam.targetScale=cam.scale
end

local function fit()
  layout()
  local x0,y0,x1,y1=city.firstSource.x,city.firstSource.y,city.firstSource.x,city.firstSource.y
  for _,n in ipairs(city.g:aliveNodes()) do
    x0,y0,x1,y1=math.min(x0,n.x),math.min(y0,n.y),math.max(x1,n.x),math.max(y1,n.y)
  end
  cam.x,cam.y=(x0+x1)/2,(y0+y1)/2
  cam.scale=math.max(0.3,math.min(1.45,cam.vw/(x1-x0+330),cam.vh/(y1-y0+330)))
  cam.targetScale=cam.scale
end

local function clear()
  state.node,state.edge,state.tool,state.drag,state.pan=nil,nil,nil,nil,nil
  state.link=nil
  state.district=nil
  state.rename=nil; state.renameSelectAll=nil
end

-- Everything that belongs to the company being played rather than to the
-- player, reset when a different company is opened.
local function resetSession()
  clear()
  state.play,state.roundResult,state.roundSpeed,state.flashEdge=nil,nil,nil,nil
  state.undo={}
  state.modal,state.slotConfirm=nil,nil
  state.scroll=0
  state.tab="network"
  state.commodity="water"; state.people=nil
  state.capacity=1; state.size="small"; state.recentSizes={"small"}
  state.borrow=500
  state.autoRemaining=nil
  state.invest=100
  state.rail=nil; state.transit=nil
  state.filter=nil; state.bottlenecks=nil; state.spof=nil; state.advisorFocus=nil; state.job=nil; state.rename=nil; state.advanced=nil; state.lineOptions=nil; state.showPermits=nil
end

-- Putting a different trade in hand. Used when the structures being joined
-- only accept one, so the panel, the preview and the main that gets laid all
-- agree without the player having to go back and press the trade first.
local function setTrade(key)
  if not key or key==state.commodity then return end
  state.commodity=key
  state.people=nil
  -- Electricity and fibre have no bulk mode: nothing is landed at a haven.
  if Graph.formOf(key)=="energy" or Graph.formOf(key)=="data" then state.rail=nil end
  state.filter=nil
  toast(string.upper(key).." selected")
end

-- Selecting anything on the map is a question, and the sidebar is the answer.
-- Rather than leaving the player on whichever tab they happened to be reading,
-- every selection opens the tab that can act on it and scrolls straight to the
-- controls -- so clicking a burst main lands on its Repair button.
local function reveal(kind)
  if kind=="district" then
    state.tab="map"; state.scroll=0
  else
    state.tab="network"; state.scroll=UI.revealInspector()
  end
end

-- A test run must not read, show or touch the player's real companies, so the
-- harness gets a fabricated set of slots to drive the picker with.
local function slotSummaries()
  if not testMode then return Save.summaries() end
  local t={}
  for i=1,Save.SLOTS do
    t[i]=(i==1)
      and {slot=1,empty=false,day=3,money=400,clients=2,worth=900,districts=1,trades={"water"}}
      or {slot=i,empty=true}
  end
  return t
end

local function writeMode(mode)
  if not testMode then love.filesystem.write(MODE_FILE,mode) end
end

-- The run saved beside the companies, or a new one.
local function loadRounds()
  if not testMode and love.filesystem.getInfo(ROUND_FILE) then
    local loaded=Save.unpack(love.filesystem.read(ROUND_FILE))
    if loaded and loaded.rounds then return loaded end
  end
  return City.newRounds({seed=testMode and 3 or nil})
end

local function roundsEffects(n)
  if not n then return end
  if n.roundServed then
    R.ring(n.x,n.y,P.flow)
    A.play("click",0.35,0.9+math.min(0.6,(city.rounds.arrived or 0)/60))
  else
    R.burst(n.x,n.y,P.bad,18)
    R.floatText(n.x,n.y-30,"-"..n.demand..(n.demand==1 and " life" or " lives"),P.bad)
    cam:shakeBy(0.12+math.min(0.3,n.demand*0.02))
    A.play("sever",0.7)
    toast(City.ROUND_HOUSE[n.roundKind].name.." went dry: "..(n.dryReason or ""),true)
    if n.dryEdge then state.flashEdge,state.flashTime=n.dryEdge,1.6 end
  end
end

local function finishRound()
  local result=city:finishRound()
  state.play=nil
  if not result then return end
  state.roundResult=result
  state.modal=result.won and "roundWon" or "roundResult"
  if result.won then
    state.records.wins=(state.records.wins or 0)+1
    if city.rounds.strict then state.records.strictWins=(state.records.strictWins or 0)+1 end
    A.play("unlock",0.8)
  else
    A.play(result.log.dry==0 and "held" or "step",0.7)
  end
  noteRecord()
  save()
end

local function action(name,...)
  if name=="fit" then fit(); return end
  if name=="rounds" then
    if not testMode and not roundsTest then
      if not saveBlocked and not save() then return end
    end
    state.companySlot=city.slot
    city=loadRounds()
    resetSession(); writeMode("rounds"); fit()
    if city.rounds.phase=="lost" then state.modal="roundLost"
    elseif (state.records.runs or 0)==0 then state.modal="roundsHelp" end
    state.records.runs=math.max(1,state.records.runs or 0); saveRecords()
    state.tab="round"
    return
  end
  if name=="leaveRounds" then
    if city.rounds and city.rounds.phase=="round" then toast("Finish the round first",true); return end
    save()
    local loaded=not testMode and Save.read()
    city=loaded or City.new(testMode and {seed=24,obstacles=4} or nil)
    city.slot=city.slot or state.companySlot or Save.readCurrent()
    resetSession(); writeMode("company"); fit()
    toast("Back to your company. The run is saved.")
    return
  end
  if name=="newRun" then
    local strict=...
    city=City.newRounds({strict=strict,seed=testMode and 3 or nil})
    state.records.runs=(state.records.runs or 0)+1; saveRecords()
    resetSession(); save(); fit()
    state.tab="round"
    toast(strict and "Strict run: one dry house ends it" or "New run on a new map")
    return
  end
  if name=="focusZone" then
    local d=city.districts[...]
    if d then
      layout()
      cam.x,cam.y=d.x+d.w/2,d.y+d.h/2
      cam.targetScale=math.max(0.2,math.min(1.2,cam.vw/(d.w*1.25),cam.vh/(d.h*1.25)))
    end
    return
  end
  if name=="roundSpeed" then state.roundSpeed=(state.roundSpeed or 1)>1 and 1 or 3; return end
  if name=="startRound" then
    if state.modal then return end
    local plan,bursts=city:startRound()
    if not plan then return end
    state.undo={}; clear(); state.rename=nil
    state.play={t=0,wait=0,interval=math.max(0.08,math.min(0.45,6/math.max(1,#plan.houses)))}
    A.play("resolve",0.8)
    for _,e in ipairs(bursts or {}) do
      local a,b=city.g.nodes[e.a],city.g.nodes[e.b]
      R.burst((a.x+b.x)/2,(a.y+b.y)/2,P.bad,24)
    end
    if bursts and #bursts>0 then
      A.play("sever",0.8); cam:shakeBy(0.35)
      toast(#bursts==1 and "A main has burst. Repair it after the round." or (#bursts.." mains have burst. Repair them after the round."),true)
    end
    return
  end
  -- Nothing is built, sold or undone while houses are arriving.
  if city.rounds and city.rounds.phase~="build" and name~="focusNode" and name~="focusEdge"
     and name~="focusLink" and name~="focusDistrict" and name~="nextLeak" and name~="mute" and name~="solo"
     and name~="fitWorld" and name~="openSlots" then
    toast(city.rounds.phase=="lost" and "This run is over. Start a new one." or "Building opens again when the round ends",true)
    return
  end
  if name=="fitWorld" then fitWorld(); return end
  if name=="mute" then state.muted=not state.muted; A.setEnabled(not state.muted); return end
  if name=="solo" then city.hideUnfocusedNetworks=not city.hideUnfocusedNetworks; return end
  if name=="focusNode" then
    local id=...
    local n=city.g.nodes[id]
    clear(); state.filter=nil; state.modal=nil; state.node=id; reveal()
    cam:centerOn(n.x,n.y)
    return
  end
  -- The header's one request control. The contract opens, the house it is
  -- about sits under the pointer, and the map comes in closer than it was: a
  -- request is about one building, so the view should be about one building.
  if name=="focusRequest" then
    local id=...
    local n=city.g.nodes[id]
    if not n then return end
    clear(); state.filter=nil; state.modal=nil; state.node=id; reveal()
    cam:centerOn(n.x,n.y)
    cam.targetScale=math.min(2.2,math.max(cam.targetScale,1.35))
    return
  end
  if name=="focusEdge" then
    local id=...
    local e=city.g.edges[id]
    local a,b=city.g.nodes[e.a],city.g.nodes[e.b]
    clear(); state.filter=nil; state.modal=nil; state.edge=id; reveal()
    cam:centerOn((a.x+b.x)/2,(a.y+b.y)/2)
    return
  end
  if name=="focusLink" then
    local id=...
    local l=city.links[id]
    local a,b=city.g.nodes[l.a],city.g.nodes[l.b]
    clear(); state.filter=nil; state.modal=nil; state.link=id; reveal()
    cam:centerOn((a.x+b.x)/2,(a.y+b.y)/2)
    return
  end
  if name=="focusDistrict" then
    local id=...
    local d=city.districts[id]
    clear(); state.district=id; reveal("district")
    return
  end
  if name=="nextLeak" then
    local worst
    for _,pipe in ipairs(city.g.edges) do
      if pipe.alive and pipe.leaking and (not worst or pipe.cap<worst.cap) then worst=pipe end
    end
    if worst then action("focusEdge",worst.id) else toast("No leaking mains") end
    return
  end
  -- Six companies. Leaving one always saves it first: switching away should
  -- never be a way to lose a day's work.
  if name=="openSlots" then
    state.rename=nil
    save()
    state.modal="slots"; state.slotConfirm=nil
    state.slots=slotSummaries()
    return
  end
  if name=="loadSlot" then
    local slot=...
    if slot==(city.slot or 1) then state.modal=nil; return end
    if testMode then state.modal=nil; return end
    if not saveBlocked and not save() then return end
    local loaded,err=Save.read(slot)
    if not loaded then toast(err or "That company could not be opened",true); return end
    city=loaded
    saveBlocked=false
    resetSession(); Save.writeCurrent(slot)
    fit(); toast("Company "..slot.." opened")
    return
  end
  if name=="newSlot" then
    local slot=...
    if not Save.validSlot(slot) then toast("No such company slot",true); return end
    if not saveBlocked and not save() then return end
    if not testMode then
      local info=Save.summarize(slot)
      if info.error then toast("This slot contains a damaged save. Choose an empty slot.",true); return end
    end
    local fresh=City.new(); fresh.slot=slot
    if not testMode then
      local ok,err=Save.writeSlot(fresh,slot)
      if not ok then toast("Save failed: "..tostring(err),true); return end
    end
    city=fresh; saveBlocked=false
    resetSession()
    fit(); toast("New company in slot "..slot)
    return
  end
  if name=="deleteSlot" then
    local slot=...
    if not testMode then Save.deleteSlot(slot) end
    state.slotConfirm=nil
    if slot==(city.slot or 1) then
      city=City.new(); city.slot=slot
      clear(); state.undo={}; state.scroll=0; state.tab="network"
      if not testMode then Save.writeSlot(city,slot) end
      fit()
    end
    state.slots=slotSummaries()
    toast("Company "..slot.." deleted")
    return
  end
  if name=="restart" then
    if saveBlocked then save(); return end
    return action("newSlot",city.slot or 1)
  end
  if name=="undo" then
    local snap=table.remove(state.undo)
    if snap then city=assert(Save.unpack(snap)); clear(); save(); toast("Decision undone") end
    return
  end
  if name=="autoplay" then
    if state.autoRemaining then state.autoRemaining=nil; toast("Autoplay stopped")
    else state.autoRemaining=math.max(1,math.min(120,tonumber((...)) or 5))*60; state.autoTick=0; state.modal=nil; toast("Autoplay started; stop it in Stats") end
    return true
  end
  -- A resilience check changes nothing in the company, so it is neither an
  -- undoable decision nor a reason to write the save.
  if name=="assessResilience" then city:assessResilience(); return true end
  if name=="startResilience" then state.job=city:startResilience(); return true end
  if city.bankrupt then return end
  local snapshot=Save.pack(city)
  local result,err
  if name=="setDispatchRate" or name=="setReserve" then
    local field=name=="setReserve" and "estateReserve" or "dispatchRate"
    city[field]=math.max(0,select(1,...)); result=true
  elseif name=="setHubFloor" or name=="setHubAuto" then
    local id,value=...
    local n=city.g.nodes[id]
    if n and n.alive and n.kind=="exchange" then
      if name=="setHubFloor" then n.floor=math.max(0,math.floor(value))
      else n.autoWiden=value and true or nil end
      city:refresh(); result=true
    else err="Select a hub first" end
  else result,err=city[name](city,...) end
  if not result then toast(err or "Action unavailable",true); A.play("denied"); return nil end
  if name=="endDay" then
    state.undo={}; clear(); state.rename=nil; state.modal=city.bankrupt and "report" or nil; state.reportDetails=false
    toast("Day "..city.day.." started. Results in Stats.")
    for _,leak in ipairs(result.leaks) do R.ring(leak.x,leak.y,P.bad) end
    if result.arrived then R.ring(result.arrived.x,result.arrived.y,P.energy) end
    A.play(city.bankrupt and "collapse" or "held")
  else
    state.undo[#state.undo+1]=snapshot
    if #state.undo>30 then table.remove(state.undo,1) end
    if name=="layPipe" then
      state.edge=result.id; state.node=nil; A.play("link")
      for _,n in ipairs(city:clientList()) do
        if city:fullyServed(n) then R.ring(n.x,n.y,P.good) end
      end
    elseif name=="layLink" then
      state.link=result.id; state.node=nil; state.edge=nil; A.play("link")
    elseif name=="build" or name=="buySource" then
      state.node=result.id; state.edge=nil; state.tool=nil; R.ring(result.x,result.y,P.good); A.play("place")
    elseif name=="buyDistrict" then
      state.district=result.id; R.ring(result.x+result.w/2,result.y+result.h/2,P.good); A.play("place")
    else A.play("upgrade") end
    if name=="repairAll" then
      toast(result.fixed.." main"..(result.fixed==1 and "" or "s").." repaired for $"..result.spent)
    elseif name=="buyDistrict" then
      toast(result.name.." acquired")
    elseif name=="layPipe" then
      toast(city.rounds and ("Main laid for $"..(result.paid or 0))
        or city.unserved==0 and "Everyone supplied! Close the day to collect your earnings." or "Connection built. Keep the supply flowing.")
    else
      toast(({repairPipe="Pipe repaired",replacePipe="Main replaced",buyAds="Advertising booked",
        invest="Investment placed",upgradeQuality="Treatment upgraded",buyLicence="Trade licence acquired",
        acceptClient="Customer signed",declineClient="Offer declined",upgradeSource="Well deepened",
        hireCrew="Crew hired",dismissCrew="Crew stood down",buyPermit="Permit granted",
        borrow="Funds drawn",repay="Loan repaid",setGate="Gate set",
        layLink=(name=="layLink" and result.mode=="road") and "Road laid" or "Route opened",
        setLinkPrice="Price set",setEdgeToll="Toll set",setStationPrice="Pump price set",
        addVehicle="Vehicle added",removeVehicle="Vehicle sold",demolishLink="Line lifted",
        upgradeResort="Resort built up",upgradeTower="Tower upgraded",upgradeLevel="Building upgraded"})[name] or "Network updated")
    end
  end
  save()
  return result
end

local function pointDistance(x,y,ax,ay,bx,by)
  local dx,dy=bx-ax,by-ay
  local t=math.max(0,math.min(1,((x-ax)*dx+(y-ay)*dy)/math.max(1,dx*dx+dy*dy)))
  return math.sqrt((x-ax-t*dx)^2+(y-ay-t*dy)^2)
end

local function hit(x,y)
  if x<UI.width or y<84 or y>love.graphics.getHeight()-58 then return nil,nil end
  for _,n in ipairs(city.g:aliveNodes()) do
    local sx,sy=cam:toScreen(n.x,n.y)
    if (not state.filter or not n.commodity or n.commodity==state.filter or (n.demands and n.demands[state.filter])) and
      (sx-x)^2+(sy-y)^2<math.max(13,R.sym(25,cam.scale))^2 then return n.id,nil end
  end
  local nearest,dist=nil,10
  for _,e in ipairs(city.g.edges) do
    if e.alive and (not state.filter or e.commodity==state.filter) then
      local ax,ay,bx,by=Draw.edgePoints(cam,city,e)
      local d=pointDistance(x,y,ax,ay,bx,by)
      if d<dist then nearest,dist=e.id,d end
    end
  end
  if nearest or state.filter then return nil,nearest,nil end
  local link,linkDist=nil,10
  for _,l in ipairs(city.links or {}) do
    if l.alive and l.mode~="bus" then
      local ax,ay,bx,by=Draw.linkPoints(cam,city,l)
      local d=pointDistance(x,y,ax,ay,bx,by)
      if d<linkDist then link,linkDist=l.id,d end
    end
  end
  return nil,nil,link
end

function love.load(args)
  local audit=false
  for _,a in ipairs(args or {}) do
    if a=="--smoke" or a=="--soak" or a=="--shot" or a=="--tut" or a=="--audio"
       or a=="--probe" then testMode=a end
    if a=="--audit" then audit=true end
  end
  R.init(); A.init()
  -- After R.init, so the recorder wraps the symbol-aware print rather than
  -- being wrapped by it.
  if audit then Audit.enable(true) end
  if love.window and love.window.setIcon and love.image then love.window.setIcon(love.image.newImageData("assets/net-profit.png")) end
  -- Reports where this build keeps its company and what it found there, then
  -- quits. The one question that is genuinely hard to answer any other way,
  -- because the answer depends on how the game was launched.
  if testMode=="--probe" then
    print("save directory: "..love.filesystem.getSaveDirectory())
    print("fused:          "..tostring(love.filesystem.isFused()))
    for _,dir in ipairs(Save.candidates()) do print("candidate:      "..dir) end
    print("current slot:   "..Save.readCurrent())
    for slot=1,Save.SLOTS do
      local loaded=Save.readSlot(slot)
      if loaded then
        print(string.format("  slot %d:       day %d, $%d, %d structures%s",slot,
          loaded.day,loaded.money,#loaded.g:aliveNodes(),
          loaded.adoptedFrom and ("  (carried over from "..loaded.adoptedFrom..")") or ""))
      else
        print(string.format("  slot %d:       empty",slot))
      end
    end
    love.event.quit()
    return
  end
  -- Keep the harness off the user's screen: offscreen, minimised and silent.
  if testMode then
    A.setEnabled(false)
    state.muted = true
    pcall(love.window.setPosition, -5000, -5000)
    pcall(love.window.minimize)
  end
  state.records={best=0,bestStrict=0,wins=0,strictWins=0,runs=0}
  local fs=love.filesystem
  if not testMode and fs and fs.getInfo(RECORD_FILE) then
    state.records=require("rounds_io").decode(love.filesystem.read(RECORD_FILE)) or state.records
  end
  for _,a in ipairs(args or {}) do if a=="--rounds" then roundsTest=true end end
  local err
  if not testMode then city,err=Save.read() end
  city=city or City.new(testMode and {seed=24,obstacles=4} or nil)
  city.slot=city.slot or (testMode and 1 or Save.readCurrent())
  cam=Camera.new(city.bounds.w,city.bounds.h); cam:follow(city.bounds); fit()
  if err then
    saveBlocked=true
    toast("Saved company is damaged and protected. Open Companies to choose another slot.",true)
    state.modal="slots"; state.slots=slotSummaries()
  end
  if city.bankrupt then state.modal="report" end
  -- Whichever of the two was open when the window closed opens again.
  local mode=not testMode and fs and fs.getInfo(MODE_FILE) and fs.read(MODE_FILE) or ""
  if roundsTest or (mode:match("^rounds") and not err) then
    local slot=city.slot
    city=loadRounds(); state.companySlot=slot
    resetSession(); fit()
    state.tab="round"
    if city.rounds.phase=="lost" then state.modal="roundLost" end
  end
  if testMode=="--audio" then
    local report=A.report()
    assert(#report>0,"no audio generated")
    for _,sound in ipairs(report) do
      assert(sound.peak>0 and sound.peak<1 and sound.rms>0,"silent or clipped sound: "..sound.name)
      print(string.format("%s: peak %.3f, RMS %.3f",sound.name,sound.peak,sound.rms))
    end
    print(#report.." sounds checked")
    love.event.quit()
    return
  end
  App.state,App.action,App.hit=state,action,hit
  App.finishRound=finishRound
  App.city=function() return city end
  App.camera=function() return cam end
  App.setTestCity=function(value)
    assert(testMode,"test cities are only available in isolated test runs")
    city=value; resetSession(); fit()
  end
end

function love.update(dt)
  R.update(dt); cam:update(dt)
  if state.autoRemaining then
    state.autoRemaining=state.autoRemaining-dt
    state.autoTick=(state.autoTick or 0)+dt
    if state.autoRemaining<=0 then state.autoRemaining=nil; save(); toast("Autoplay finished")
    elseif state.autoTick>=.3 then
      state.autoTick=0
      local nextCity,message,stop=require("autoplay").step(city)
      city=nextCity; state.undo={}; toast(message); save()
      if stop then state.autoRemaining=nil end
    end
  end
  if state.flashTime then
    state.flashTime=state.flashTime-dt
    if state.flashTime<=0 then state.flashTime,state.flashEdge=nil,nil end
  end
  if city.rounds and city.rounds.phase=="round" and state.play then
    local play=state.play
    if city:pendingHouses()>0 then
      play.t=play.t+dt*(state.roundSpeed or 1)
      while play.t>=play.interval and city:pendingHouses()>0 and city.rounds.phase=="round" do
        play.t=play.t-play.interval
        roundsEffects(city:roundArrive())
      end
      if city.rounds.phase=="lost" then
        state.play=nil; state.modal="roundLost"
        A.play("collapse",0.9); noteRecord()
        city:clearRoundHouses(); city:refresh(); save()
      end
    else
      play.wait=play.wait+dt*(state.roundSpeed or 1)
      if play.wait>0.9 then finishRound() end
    end
  end
  state.hoverNode,state.hoverEdge,state.hoverLink=hit(love.mouse.getPosition())
  -- Every frame, not only when the mouse moves: whatever is under the cursor
  -- can change under a held drag, and the preview must never quote a size
  -- either end would refuse.
  if state.drag and not state.rail and not state.transit then
    local target=state.hoverNode~=state.drag and state.hoverNode or nil
    -- A cable dragged out of a tower is a cable whatever was selected in the
    -- panel: the trade follows the two structures, and the panel follows it.
    if target then setTrade(E.dragTrade(city,state.drag,target,state)) end
    state.size=E.dragSize(city,state.drag,target,state)
  end
  if state.toastTime then
    state.toastTime=state.toastTime-dt
    if state.toastTime<=0 then state.toast=nil; state.toastBad=nil end
  end
  state.scroll=math.max(0,math.min(state.scroll,UI.maxScroll or 0))
  if testMode and not walkthroughRunning then
    frames=frames+1
    if frames==3 then
      walkthroughRunning=true
      require(roundsTest and "rounds_walkthrough" or "company_walkthrough").start(App,testMode)
      walkthroughRunning=false
    end
    if frames>3 then require(roundsTest and "rounds_walkthrough" or "company_walkthrough").update(App,testMode,frames,dt) end
  end
end

function love.draw()
  Audit.begin(state.modal and ("modal:"..state.modal) or state.tab)
  love.graphics.clear(P.bg)
  Draw.world(city,cam,state)
  UI.draw(city,state,action)
  Audit.finish()
end

function love.mousepressed(x,y,button)
  if button==1 and UI.click(x,y) then return end
  if state.modal then return end
  if x<UI.width or y<84 or y>love.graphics.getHeight()-58 then return end
  -- Right-click puts down whatever is in hand. With nothing in hand, a right
  -- click that does not turn into a pan clears the selection on release.
  if button==2 or button==3 then
    state.pan={x=x,y=y,moved=false,deselect=not state.tool}
    state.tool=nil
    return
  end
  if button~=1 then return end
  if state.tool then
    local wx,wy=cam:toWorld(x,y)
    if state.tool=="source" then action("buySource",state.commodity,wx,wy,state.plant)
    elseif state.tool=="terminal" then action("build",wx,wy,state.tool,state.havenKind or "port")
    elseif state.tool=="works" then action("build",wx,wy,state.tool,state.recipe or "brewery")
    else
      local kind=state.tool=="grid" and City.INFRA.voltages[state.voltage or "low"].tower or state.tool
      action("build",wx,wy,kind,state.commodity)
    end
    return
  end
  local node,edge,link=hit(x,y)
  if node or edge or link then
    -- Clicking what is already selected puts it down. A structure waits for the
    -- release, because pressing on it is also how a main is dragged out of it.
    if edge and not node and state.edge==edge then state.edge=nil; return end
    if link and state.link==link then state.link=nil; return end
    state.deselect=node and state.node==node and node or nil
    state.node,state.edge,state.link,state.district=node,edge,link,nil
    reveal()
    if node then
      if state.people then state.transit=state.transit or "road"; state.rail=nil end
      state.drag=node
      if not state.rail and not state.transit then
        setTrade(E.dragTrade(city,node,nil,state))
        state.size=E.dragSize(city,node,nil,state)
      end
    end
    return
  end
  -- Empty ground: dragging just pans the camera. A plain click (no drag) on
  -- unowned ground opens the Map tab so it can be bought; owned ground has
  -- nothing left to show, so it only clears the selection.
  local wx,wy=cam:toWorld(x,y)
  local d=city:districtAt(wx,wy)
  state.node,state.edge,state.link,state.district=nil,nil,nil,nil
  state.pan={x=x,y=y,moved=false,district=(d and city:districtVisible(d)) and d.id or nil}
end

function love.mousemoved(x,y,dx,dy)
  state.hoverNode,state.hoverEdge,state.hoverLink=hit(x,y)
  if state.pan then
    local p=state.pan
    if p.moved then cam:pan(dx,dy)
    elseif (x-p.x)^2+(y-p.y)^2>16 then p.moved=true; cam:pan(x-p.x,y-p.y) end
  end
end

function love.mousereleased(x,y,button)
  if state.drag and button==1 then
    local target=hit(x,y)
    if target and target~=state.drag and state.transit then
      action("layLink",state.drag,target,state.transit)
    elseif target and target~=state.drag and not state.people then
      if not state.rail then setTrade(E.dragTrade(city,state.drag,target,state)) end
      local size=not state.rail and E.dragSize(city,state.drag,target,state) or nil
      if size then state.size=size end
      if action("layPipe",state.drag,target,state.commodity,
        state.rail and state.capacity or size,state.rail,
        math.min(city.lining or 1,state.grade or 1)) and size then
        E.useSize(state,size)
      end
    elseif target==state.drag and state.deselect==state.drag then
      state.node=nil
    end
  end
  if state.pan and state.pan.deselect and not state.pan.moved and button~=1 then
    state.node,state.edge,state.link,state.district=nil,nil,nil,nil
  end
  if state.pan and not state.pan.moved and button==1 then
    if state.pan.district then
      state.district=state.pan.district
      reveal("district")
    else
      -- Ground you already own, or nothing at all: there is nothing to show
      -- for it, so a plain click just goes back to building.
      reveal()
    end
  end
  state.drag,state.pan,state.deselect=nil,nil,nil
end

function love.wheelmoved(_,dy)
  if state.modal then return end
  local x,y=love.mouse.getPosition()
  if x<UI.width then state.scroll=math.max(0,math.min(UI.maxScroll or 0,state.scroll-dy*42))
  else cam:zoomAt(x,y,dy) end
end

function love.keypressed(key)
  if state.rename then
    if key=="escape" then state.rename=nil
    elseif key=="return" then
      if action("setCompanyName",state.rename) then state.rename=nil end
    elseif key=="backspace" then
      if state.renameSelectAll then state.rename=""; state.renameSelectAll=nil
      else
        local utf8=require("utf8")
        local offset=utf8.offset(state.rename,-1)
        if offset then state.rename=state.rename:sub(1,offset-1) end
      end
    elseif key=="a" and love.keyboard.isDown("lgui","rgui","lctrl","rctrl") then
      state.renameSelectAll=true
    end
    return
  end
  if state.modal then
    if state.modal=="roundLost" then return end
    if key=="escape" or key=="return" or (key=="space" and city.rounds) then
      if not city.bankrupt or state.modal=="slots" then state.modal=nil end
    end
    return
  end
  if city.rounds and (key=="return" or key=="space") then
    if city.rounds.phase=="round" then action("roundSpeed") elseif city.rounds.phase=="build" then action("startRound") end
    return
  end
  if key=="escape" then clear()
  elseif key=="return" then action("endDay")
  elseif key=="f" then fit()
  elseif key=="t" and (#city.g:nodesOfKind("terminal")+#city.g:nodesOfKind("dc")>0) then state.rail=(state.rail==nil) and "rail" or nil
  elseif key=="z" then action("undo")
  elseif key=="m" then action("mute")
  elseif key=="h" then action("solo")
  elseif key=="u" and state.edge then action("upgradePipe",state.edge)
  elseif key=="r" then
    if state.edge then action("repairPipe",state.edge) else action("repairAll") end
  elseif key=="l" then action("nextLeak")
  elseif key=="e" and state.edge then action("upgradePipe",state.edge)
  elseif key=="e" and state.node and city.g.nodes[state.node].kind=="source" then
    action("upgradeSource",state.node)
  elseif key=="delete" then
    if state.edge then action("demolishPipe",state.edge)
    elseif state.link then action("demolishLink",state.link)
    elseif state.node then action("demolishNode",state.node) end
  elseif tonumber(key) and tonumber(key)>=1 and tonumber(key)<=9 then
    state.tool=({"junction","grid","pump","tower","gate","depot","exchange","terminal","dc"})[tonumber(key)]
  end
end

function love.textinput(value)
  if state.rename then
    local previous=state.renameSelectAll and "" or state.rename
    if #previous+#value<=48 then state.rename=previous..value; state.renameSelectAll=nil end
  end
end

function love.resize() R.retune(); fit() end
function love.quit()
  Audit.report()
  if city.rounds and city.rounds.phase=="round" then
    city:finishRound()
    if city.rounds.phase=="lost" then city:clearRoundHouses(); city:refresh() end
  end
  if saveBlocked then return end
  if not save() then return true end
end

return App
