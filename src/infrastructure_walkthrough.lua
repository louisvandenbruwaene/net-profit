-- Isolated, real-callback coverage for the engineering controls.
local City=require('city')
local Draw=require('company_render')
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
  app.action('focusNode',tower.id)
  capture('net-profit-27-transformer',app,1100,700)
  click('back-to-build')
  click('power')
  click('voltage-help')
  check(app.state.voltageHelp==true,'the voltage info button expands its explanation')
  capture('net-profit-28b-voltage-help',app,1100,700)
  click('voltage-help')
  check(not app.state.voltageHelp,'and collapses it again')
  scrollTo(app,'tool-pole'); click('tool-pole')
  check(app.state.tool=='pole','the low voltage pole is in the power toolbar')
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

end
