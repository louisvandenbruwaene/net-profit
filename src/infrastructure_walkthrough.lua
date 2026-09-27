-- Isolated, real-callback coverage for the engineering controls.
local City=require('city')
return function(app,capture,click,scrollTo,check)
  local c=City.new({seed=24,obstacles=0})
  c.money=50000; c.obstacles={}; c.stock={steel=500,concrete=500,panels=24}
  c.licences.power=true; c.licences.oil=true; c.licences.food=true
  c.guideDismissed=true
  for _,d in ipairs(c.districts) do d.owned=true end
  c.permits={park=true,bedrock=true,river=true}
  app.setTestCity(c)
  click('power')
  scrollTo(app,'plant-nuclear'); click('plant-nuclear')
  check(app.state.tool=='source' and app.state.plant=='nuclear','reactor toolbar selects the right generator')
  app.action('buySource','power',1200,900,'nuclear')
  local source=c.g.nodes[app.state.node]
  check(source and source.plant=='nuclear','reactor is commissioned through an application action')
  app.action('build',1450,920,'hvtower'); local hv=c.g.nodes[app.state.node]
  app.action('build',1530,950,'pylon'); local tower=c.g.nodes[app.state.node]
  local customer=assert(c:addClient('workshop',true)); customer.x,customer.y=1610,950; customer.demand=5
  app.action('layPipe',source.id,hv.id,'power','small')
  app.action('focusNode',hv.id)
  scrollTo(app,'upgrade-transformer')
  capture('net-profit-27a-tower-upgrades',app,1100,700)
  click('upgrade-transformer')
  check(hv.upgrade=='transformer','the tower inspector fits a transformer')
  app.action('layPipe',hv.id,tower.id,'power','small')
  app.action('upgradeTower',tower.id,'transformer')
  app.action('layPipe',tower.id,customer.id,'power','medium')
  app.action('acceptClient',customer.id)
  check(c.served[customer.id]==5,'application actions deliver power through towers with transformers')
  -- A drag out of a power tower is a cable, whatever the panel had in hand.
  -- The panel follows the two structures rather than the other way round, so
  -- picking up a pylon with water selected does not have to be undone first.
  local E=require('experience')
  app.state.commodity='water'; app.state.rail=nil; app.state.tool=nil
  check(E.dragTrade(c,tower.id,nil,app.state)=='power','a tower in hand asks for electricity')
  app.action('build',1530,1060,'pylon'); local spare=c.g.nodes[app.state.node]
  check(E.dragTrade(c,tower.id,spare.id,app.state)=='power','and so does a drag from one tower to another')
  local cam=app.camera()
  cam.scale,cam.targetScale=1,1
  cam:centerOn(tower.x,tower.y)
  local sx,sy=cam:toScreen(tower.x,tower.y)
  love.mousepressed(sx,sy,1)
  check(app.state.drag==tower.id,'pressing a tower starts a drag out of it')
  check(app.state.commodity=='power','and switches the trade in hand to electricity')
  love.mousereleased(sx,sy,1)
  check(E.dragTrade(c,source.id,hv.id,app.state)=='power','a generator and a tower still agree on electricity')
  app.action('focusNode',tower.id)
  capture('net-profit-27-transformer',app,1100,700)
  app.action('focusNode',spare.id)
  scrollTo(app,'voltage-high'); capture('net-profit-27b-tower-voltage',app,1100,700); click('voltage-high')
  check(spare.kind=='hvtower','a tower is raised to high voltage in its inspector')
  local p2=assert(c:build(tower.x+60,tower.y+60,'pylon')); assert(c:upgradeTower(p2.id,'transformer'))
  local cable=assert(c:layPipe(tower.id,p2.id,'power','small'))
  check(cable.voltage=='low','a new cable takes the lowest voltage both towers accept')
  app.action('focusEdge',cable.id)
  capture('net-profit-27c-cable-voltage',app,1100,700)
  scrollTo(app,'cable-voltage'); click('cable-voltage')
  check(cable.voltage=='medium','and the cable inspector upgrades it')
  click('tab-network')
  click('power')
  scrollTo(app,'tool-grid'); click('tool-grid')
  check(app.state.tool=='grid','the tower is in the power toolbar')
  app.state.tool=nil; app.state.scroll=0
  local setColor=love.graphics.setColor
  app.state.commodity='water'
  capture('net-profit-34-grid-focus',app,1100,700)
  check(love.graphics.setColor==setColor,'fading other grids never leaks into the sidebar')
  app.state.commodity='power'
  scrollTo(app,'plant-solar'); click('plant-solar')
  check(app.state.plant=='solar','solar generator is selectable')
  scrollTo(app,'plant-hydro'); click('plant-hydro')
  check(app.state.plant=='hydro','river generation is selectable')
  app.state.tool=nil; app.state.scroll=0
  capture('net-profit-28-power-tools',app,1100,700)
  -- First imported commodity must not crash the source/tool panel.
  local haven=assert(c:build(1700,1200,'terminal','highway'))
  app.state.commodity='panels'; app.state.scroll=0
  capture('net-profit-29-panel-imports',app,1100,700)
  check(haven.kind=='terminal','imported panels have a usable freight entry point')
  app.state.commodity='water'; app.state.scroll=0
  scrollTo(app,'tool-filtration'); click('tool-filtration')
  check(app.state.tool=='filtration','filtration is available in the water toolbar')
  app.state.tool=nil
  local farm
  for _,d in ipairs(c.districts) do
    local x,y=d.x+d.w/2,d.y+d.h/2
    if not farm and not c:placementError(x,y) and not c:farmSiteError(x,y) then
      farm=assert(c:build(x,y,'works','dairy'))
    end
  end
  check(farm~=nil,'a livestock farm can reserve a clean plot')
  app.action('focusNode',farm.id)
  capture('net-profit-30-farm',app,1100,700)
  local d=c:districtAt(farm.x,farm.y); d.pollution=45; c:refresh()
  app.action('build',farm.x+200,farm.y,'lab')
  local lab=c.g.nodes[app.state.node]
  check(lab and lab.kind=='lab','environment lab can be built beside agricultural land')
  capture('net-profit-31-environment',app,1100,700)
  app.action('undo')
  check(not c.g.nodes[lab.id].alive or app.city()~=c,'environment construction participates in undo')
  local terrain=City.new({seed=4242})
  terrain.guideDismissed=true
  for col=6,12 do
    for row=2,7 do terrain:dressCell(terrain:surveyCell(col,row)) end
  end
  app.setTestCity(terrain)
  local seen={}
  for _,o in ipairs(terrain.obstacles) do
    if o.massive and not seen[o.kind] then
      seen[o.kind]=true
      local district=terrain:districtAt(o.x,o.y)
      district.owned=true
      local cam=app.camera()
      cam:centerOn(district.x+district.w/2,district.y+district.h/2)
      cam.scale=0.68; cam.targetScale=0.68
      capture('net-profit-33-massive-'..o.kind,app,1440,880,true)
    end
  end
  check(seen.park and seen.bedrock,'massive parks and mountains render in distant regions')

  -- The close-up scene: one of everything drawn as a building or a site, a
  -- quarry cutting its range, forestry in its clearing, a wood growing back.
  -- A kind that stops drawing shows up here instead of in a player's game.
  local show=City.new({seed=24,obstacles=0})
  show.guideDismissed=true; show.money=1e7
  local home=show.districts[City.MAP.start]
  local cx,cy=home.x+home.w/2,home.y+home.h/2
  local function put(kind,dx,dy,fields)
    local n=show.g:addNode(cx+dx,cy+dy,kind)
    for k,v in pairs(fields or {}) do n[k]=v end
    return n
  end
  show.obstacles={{x=cx-330,y=cy+150,r=95,kind='bedrock'},{x=cx+330,y=cy+150,r=95,kind='park'}}
  show.permits={park=true,bedrock=true,river=true}
  local quarry=put('source',-330,150,{commodity='rock',output=12})
  put('source',330,150,{commodity='timber',output=12})
  show.regrowth={{x=cx,y=cy+260,r=80,kind='park',cleared=show.day-25}}
  local row={
    {'client',{clientType='house',commodity='water',demand=2}},{'client',{clientType='estate',commodity='water',demand=2}},
    {'client',{clientType='workshop',commodity='power',demand=2}},{'client',{clientType='pub',commodity='beer',demand=2}},
    {'client',{clientType='factory',commodity='oil',demand=2}},{'client',{clientType='market',commodity='food',demand=2}},
    {'source',{commodity='water',output=10}},{'source',{commodity='oil',output=10}},
    {'pylon',{level=3,commodity='power'}},{'depot',{level=4,commodity='water',stored=10}},{'pump',{}},
    {'stop',{}},{'station',{}},{'resort',{level=2}},{'dc',{}},
  }
  for i,spec in ipairs(row) do
    local f=spec[2]; f.patience=f.patience or 3; f.grace=f.grace or 3; f.rate=f.rate or 7
    put(spec[1],-420+((i-1)%8)*120,-150+math.floor((i-1)/8)*110,f)
  end
  put('source',-300,40,{plant='wind',level=3,commodity='power'})
  put('source',0,40,{plant='nuclear',level=2,commodity='power'})
  put('source',300,40,{plant='solar',level=3,commodity='power'})
  app.setTestCity(show)
  show:refresh()
  local cam=app.camera()
  cam:centerOn(cx,cy+40); cam.scale=1.0; cam.targetScale=1.0
  -- The map alone: no banner, no floating numbers, the panel folded away for
  -- this one frame and put back after, since later steps expect it open.
  local drawer=app.state.drawer
  app.state.banner=nil; app.state.dusk=nil; app.state.toast=nil; app.state.drawer=nil
  require('render').fx={}
  capture('net-profit-40-closeup-buildings',app,1440,880,true)
  app.state.drawer=drawer
  check(show:quarryRange(quarry) ~= nil,'the showcase quarry stands on its range')

  -- Every kind of line side by side: cables at each voltage, then mains at
  -- each size, so each reads differently at a glance.
  local lines=City.new({seed=24,obstacles=0})
  lines.guideDismissed=true; lines.obstacles={}
  local lh=lines.districts[City.MAP.start]
  local lx,ly=lh.x+lh.w/2,lh.y+lh.h/2
  local function span(kind,commodity,row,size,voltage,x0,x1)
    local a=lines.g:addNode(lx+x0,ly+row,kind); local b=lines.g:addNode(lx+x1,ly+row,kind)
    local cap=City.sizeOf(size).cap
    local e=lines.g:addEdge(a.id,b.id,cap); e.commodity=commodity; e.size=size; e.capMax=cap; e.grade=1; e.voltage=voltage
    return e
  end
  for i,v in ipairs({{'pole','low'},{'pylon','medium'},{'hvtower','high'}}) do
    span(v[1],'power',-210+i*70,'medium',v[2],-360,-60)
  end
  for i,size in ipairs({'small','medium','large','massive','trunk'}) do
    span('junction','water',-170+i*55,size,nil,60,380)
  end
  app.setTestCity(lines); lines:refresh()
  cam=app.camera(); cam:centerOn(lx-120,ly); cam.scale=1.2; cam.targetScale=1.2
  app.state.drawer=nil
  capture('net-profit-40b-line-kinds',app,1440,880,true)
  app.state.drawer=drawer

end
