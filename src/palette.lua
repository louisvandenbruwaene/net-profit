-- palette.lua -- one place for every colour, so the game reads as a system.
local P = {}

P.bg          = { 0.065, 0.092, 0.105 }
P.grid        = { 0.087, 0.117, 0.132 }
P.gridMajor   = { 0.110, 0.146, 0.160 }
P.panel       = { 0.094, 0.125, 0.148 }
P.panelEdge   = { 0.205, 0.270, 0.302 }
P.surface     = { 0.125, 0.165, 0.190 }
P.hover       = { 0.170, 0.225, 0.252 }
P.land        = { 0.107, 0.167, 0.158 }

P.text        = { 0.910, 0.931, 0.925 }
P.textDim     = { 0.697, 0.755, 0.776 }
P.textFaint   = { 0.535, 0.608, 0.645 }

P.energy      = { 0.980, 0.820, 0.380 }
P.flow        = { 0.420, 0.820, 0.980 }
P.good        = { 0.360, 0.850, 0.620 }
P.warn        = { 0.980, 0.700, 0.330 }
P.bad         = { 0.960, 0.370, 0.420 }
P.cut         = { 0.980, 0.300, 0.380 }
P.accent      = { 0.620, 0.560, 0.980 }

P.link        = { 0.300, 0.360, 0.470 }
P.linkLive    = { 0.380, 0.720, 0.930 }
P.ghost       = { 0.500, 0.560, 0.680 }

function P.with(c, a)
  return { c[1], c[2], c[3], a }
end

return P
