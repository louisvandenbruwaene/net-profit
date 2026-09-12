-- Where the company lives, when the game can be launched two different ways.
--
-- LOVE gives a fused .app a different save directory from the same game run out
-- of a source folder. Nobody should lose an eighty-day company because of how
-- they happened to start it, so the lookup falls back to the other location.
package.path = "src/?.lua;" .. package.path
-- Stub enough of love for company_save to load headlessly.
_G.love={filesystem={}}
local Save=dofile("src/company_save.lua")
local pass,fail=0,0
local function ok(m,c) if c then pass=pass+1; print("  ok  "..m) else fail=fail+1; print("FAIL  "..m) end end

local files={["/appdata/LOVE/net-profit/company.lua"]="LEGACY"}
local function env(saveDir,primary)
  return {
    saveDirectory=saveDir,
    candidates={"/appdata/LOVE/net-profit","/appdata/net-profit"},
    primaryExists=function() return primary~=nil end,
    primaryRead=function() return primary end,
    fileRead=function(p) return files[p] end,
  }
end
-- fused build, company only in the unfused location
local text,from=Save.locate(env("/appdata/net-profit",nil))
ok("a fused build finds a company saved by the source build",text=="LEGACY" and from=="/appdata/LOVE/net-profit")
-- unfused build, company only in the fused location
files={["/appdata/net-profit/company.lua"]="FUSED"}
text,from=Save.locate(env("/appdata/LOVE/net-profit",nil))
ok("and the source build finds one saved by the fused app",text=="FUSED" and from=="/appdata/net-profit")
-- a company in the current location always wins
files={["/appdata/LOVE/net-profit/company.lua"]="LEGACY"}
text,from=Save.locate(env("/appdata/net-profit","CURRENT"))
ok("the current save directory takes priority",text=="CURRENT" and from==nil)
-- nothing anywhere
files={}
text,from=Save.locate(env("/appdata/net-profit",nil))
ok("a genuinely new company is reported as new",text==nil and from==nil)
-- never re-read our own empty directory as a legacy candidate
files={["/appdata/net-profit/company.lua"]="SELF"}
text,from=Save.locate(env("/appdata/net-profit",nil))
ok("the current directory is not adopted from itself",text==nil)
-- Mirroring: a write reaches the other location, but only if it already has a
-- company there. The game must never invent a save directory.
do
  local written={}
  local existing={["/appdata/LOVE/net-profit/company.lua"]=true}
  local realOpen=io.open
  io.open=function(path,mode)
    if mode=="w" then
      return {write=function(_,t) written[path]=t end, close=function() end}
    end
    if existing[path] then return {read=function() return "X" end, close=function() end} end
    return nil
  end
  Save.candidates=function() return {"/appdata/LOVE/net-profit","/appdata/net-profit"} end
  Save.mirror("PAYLOAD","/appdata/net-profit")
  io.open=realOpen
  ok("a write is mirrored into the other save directory",
    written["/appdata/LOVE/net-profit/company.lua"]=="PAYLOAD")
  ok("and not into one that has never held a company",
    written["/appdata/net-profit/company.lua"]==nil)
end

-- Slots.
do
  ok("there are six companies",Save.SLOTS==6)
  ok("slots are named predictably",Save.slotName(1)=="company1.lua" and Save.slotName(6)=="company6.lua")
  ok("only six slots are valid",
    Save.validSlot(1) and Save.validSlot(6)
    and not Save.validSlot(0) and not Save.validSlot(7)
    and not Save.validSlot(1.5) and not Save.validSlot("2") and not Save.validSlot(nil))
  -- The pre-slot company becomes slot one without being rewritten.
  local first=Save.namesForSlot(1)
  ok("slot one answers to its own name first",first[1]=="company1.lua")
  ok("and falls back to the company that existed before slots",first[2]=="company.lua")
  ok("no other slot inherits that file",#Save.namesForSlot(2)==1
    and Save.namesForSlot(2)[1]=="company2.lua")

  -- Each slot resolves across both save directories independently.
  files={["/appdata/LOVE/net-profit/company3.lua"]="THREE"}
  local text,from=Save.locate(env("/appdata/net-profit",nil),"company3.lua")
  ok("a fused build finds slot three saved by the source build",
    text=="THREE" and from=="/appdata/LOVE/net-profit")
  text=Save.locate(env("/appdata/net-profit",nil),"company5.lua")
  ok("and an untouched slot stays empty",text==nil)
end

print(pass.." passed, "..fail.." failed")
os.exit(fail==0 and 0 or 1)
