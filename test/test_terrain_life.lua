-- Ground that changes with use: quarries that run out, woods that grow back.
package.path='test/?.lua;src/?.lua;'..package.path
local T=require('support')
local City=require('city')
local Save=require('company_save')
local Shape=require('terrain_shape')
local function check(v,m) T.check(v,m); print("  ok  "..m) end

local function city() return T.sandbox(31) end
local function home(c) local d=c.districts[City.MAP.start]; return d.x+d.w/2,d.y+d.h/2 end

print("a quarry is capped by what its range has left")
do
  local c=city(); local x,y=home(c)
  local o={x=x+200,y=y,r=90,kind='bedrock'}; c.obstacles[1]=o
  local n=c.g:addNode(o.x,o.y,'source'); n.commodity='rock'; n.output=12; n.cap=12; n.ports=4
  c:refresh()
  check(c:quarryRange(n)==o,"a rock source finds the range under it")
  check(c:rockLeft(o)==c:rockReserve(o) and c:rockReserve(o)>100,"a range in an old save starts full")
  check((n.effectiveOutput or n.output)==12,"a full range does not limit its quarry")
  o.mined=c:rockReserve(o)-5
  c:refresh()
  check(n.effectiveOutput==5,"a nearly worked-out range caps the quarry at what is left")
  o.mined=c:rockReserve(o)
  c:refresh()
  check(n.effectiveOutput==0,"a worked-out range stops the quarry")
  local back=assert(Save.unpack(Save.pack(c)))
  check(back.obstacles[1].mined==o.mined,"what has been cut survives a save")
end

print("rock that is used is cut from the range")
do
  local c=city(); local x,y=home(c)
  c.stock={steel=1000,concrete=1000}
  local o={x=x+200,y=y,r=90,kind='bedrock'}; c.obstacles[1]=o
  local q=c.g:addNode(o.x,o.y,'source'); q.commodity='rock'; q.output=12; q.cap=12; q.ports=4
  c.firstSource=q
  c.licences={water=true,power=true}
  local works=assert(c:build(x-150,y,'works','cementworks'))
  local power=c.g:addNode(x-150,y+120,'source'); power.commodity='power'; power.output=20; power.cap=20; power.ports=4
  for _,pair in ipairs({{q,works,'rock'},{power,works,'power'}}) do
    local e=c.g:addEdge(pair[1].id,pair[2].id,50); e.capMax=50; e.size='large'; e.grade=3; e.commodity=pair[3]
  end
  c.leakChance=function() return 0 end
  c:refresh()
  local used=(c.produced or {})[q.id] or 0
  check(used>0,"a cement works takes rock from the quarry")
  c:endDay()
  check((o.mined or 0)==used,"a day's cut is taken off the range")
  local full=math.floor(o.r*o.r/100)
  o.mined=c:rockReserve(o)-3
  check(c:clearYield(o)==math.min(full,3),"a worked range yields only the rock it has left")
end

print("a harvested wood grows back where nothing is built")
do
  local c=city(); local x,y=home(c)
  local o={x=x+250,y=y+60,r=80,kind='park'}; c.obstacles[1]=o
  local well=c.g:addNode(x-200,y,'source'); well.commodity='water'; well.output=10; well.cap=10; well.ports=4
  c.firstSource=well
  check(c:clearTerrain(1),"a wood can be harvested")
  check(#c.obstacles==0 and #(c.regrowth or {})==1,"the harvest is remembered for regrowth")
  for _=1,City.TERRAIN_LIFE.regrowDays-1 do c:endDay() end
  check(#c.obstacles==0,"the wood is not back before its time")
  c:endDay()
  check(#c.obstacles==1 and c.obstacles[1].kind=='park',"the wood grows back after its days")
  local g=c.obstacles[1]
  check(g.x==o.x and g.y==o.y and g.r==o.r,"it grows back on the same ground with the same outline")
  check(c.regrowth==nil,"nothing is left waiting")
end

print("ground kept in use stays clear")
do
  local c=city(); local x,y=home(c)
  local o={x=x+250,y=y+60,r=80,kind='park'}; c.obstacles[1]=o
  local well=c.g:addNode(x-200,y,'source'); well.commodity='water'; well.output=10; well.cap=10; well.ports=4
  c.firstSource=well
  c:clearTerrain(1)
  local j=c.g:addNode(o.x,o.y,'junction'); j.ports=3
  for _=1,City.TERRAIN_LIFE.regrowDays+5 do c:endDay() end
  check(#c.obstacles==0 and #(c.regrowth or {})==1,"a wood does not grow back over a structure")
  j.alive=false
  c:endDay()
  check(#c.obstacles==1,"once the ground is free the wood returns")
  local back=assert(Save.unpack(Save.pack(c)))
  local parks=0; for _,b in ipairs(back.obstacles) do if b.kind=="park" and b.x==o.x and b.y==o.y then parks=parks+1 end end
  check(parks==1,"the regrown wood survives a save")
end

print(T.checks.." terrain life checks passed")
