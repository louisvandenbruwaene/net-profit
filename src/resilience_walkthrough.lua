-- Real-callback coverage for levels, the advisor and secure contracts.
local City=require('city')
return function(app,capture,click,scrollTo,check)
  local c=City.new({seed=31,obstacles=0})
  c.money=200000; c.obstacles={}; c.guideDismissed=true
  c.stock={steel=500,concrete=500,panels=24}
  for _,d in ipairs(c.districts) do d.owned=true end
  app.setTestCity(c)
  local function node(kind,x,y,commodity,output)
    local n=c.g:addNode(x,y,kind); n.commodity=commodity
    if output then n.output=output; n.cap=100 end
    if kind=='source' or kind=='junction' then n.ports=16 end
    return n
  end
  local function house(x,y,demand)
    local n=node('client',x,y,'water')
    n.demand=demand; n.clientType='house'; n.rate=6; n.rateBase=6; n.grace=3; n.patience=3; n.prospect=false
    return n
  end
  local well=node('source',1300,1300,'water',5)
  local j=assert(c:build(1420,1320,'junction'))
  local home=house(1520,1320,8)
  assert(c:layPipe(well.id,j.id,'water','large'))
  assert(c:layPipe(j.id,home.id,'water','small'))
  for i=1,8 do house(3000+i*5,3000,1) end
  home.secure=true
  c:refresh()

  -- A building starts weak and the inspector offers the next level.
  app.action('focusNode',j.id)
  check(j.kind=='junction' and j.ports==3,'a junction starts as a three connection T split')
  capture('net-profit-35-level-panel',app,1100,700)
  scrollTo(app,'level-up'); click('level-up')
  check(j.kind=='manifold' and c:levelOf(j)==2 and j.ports==6,'the level button turns the junction into a hub')
  click('back-to-build')

  -- The automation hub has its own levels.
  c.money=200000
  local hub=assert(c:build(1900,1300,'exchange'))
  check(hub.ports==4 and c:hubRadius(hub)==450,'a new automation hub is small')
  app.action('focusNode',hub.id)
  scrollTo(app,'level-up'); click('level-up')
  check(c:levelOf(hub)==2 and hub.ports==6 and c:hubRadius(hub)==580,'and grows in ports and range')
  click('back-to-build')

  -- The advisor: the resilience check and the ranked upgrades.
  click('tab-stats')
  click('tab-advisor')
  check(c:resilienceReport()==nil,'nothing is checked until the player asks')
  capture('net-profit-36-advisor',app,1100,700)
  click('assess')
  check(app.state.job~=nil,'the check starts as a background job')
  capture('net-profit-36b-advisor-working',app,1100,700)
  while app.state.job do
    if c:stepResilience(app.state.job,math.huge) then app.state.job=nil end
  end
  local report=c:resilienceReport()
  check(report and report.grade,'the resilience check runs from the advisor')
  check(app.state.tab=='advisor','and stays on the advisor')
  click('spof-toggle')
  check(app.state.spof==true,'single points of failure can be shown on the map')
  capture('net-profit-37-spof-map',app,1100,700)
  click('spof-toggle')
  check(not app.state.spof,'and hidden again')
  local list=require('experience').advise(c)
  check(#list>=1 and list[1].kind=='source','the advisor ranks deepening the starved well first')
  click('advice-1')
  check((well.level or 1)==2 and well.output>5,'a ranked upgrade is bought from the list')
  -- The secure customer says whether one failure would cut it off.
  app.action('focusNode',home.id)
  capture('net-profit-38-secure-client',app,1100,700)
  click('back-to-build')
end
