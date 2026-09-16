-- Private-use glyphs have a procedural font fallback, so every platform shows
-- the same icons even when its installed fonts lack emoji or alchemy symbols.
local S={keys={},glyphs={}}
local keys={'water','saltwater','salt','power','steel','timber','rock','gems','jewelry','crews','surveyors','dispatchers','engineers','estates','analysts','roads','people','goods','oil','food','beer','internet','panels','wheat','malt','ore','coke','sand','cement','diesel','gasoline','rubber','planks','glass','concrete','cars'}
for i,key in ipairs(keys) do
 local cp=0xE000+i
 S.keys[i]=key; S.glyphs[key]=string.char(0xE0+math.floor(cp/4096),0x80+math.floor(cp/64)%64,0x80+cp%64)
end
function S.get(key) return S.glyphs[key] or key end
return S
