-- Private-use codepoints that stand for a drawing rather than a letter, so a
-- quantity reads the same on every platform whatever fonts are installed.
-- symbol_font.lua draws them where they fall in a line of text.
local S={keys={},glyphs={}}
local keys={'water','saltwater','salt','power','steel','timber','rock','gems','jewelry','crews','surveyors','dispatchers','engineers','estates','analysts','roads','people','goods','oil','food','beer','internet','panels','wheat','malt','ore','coke','sand','cement','diesel','gasoline','rubber','planks','glass','concrete','cars','shield','clean'}
for i,key in ipairs(keys) do
 local cp=0xE000+i
 S.keys[i]=key; S.glyphs[key]=string.char(0xE0+math.floor(cp/4096),0x80+math.floor(cp/64)%64,0x80+cp%64)
end
function S.get(key) return S.glyphs[key] or key end
return S
