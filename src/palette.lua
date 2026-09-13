-- palette.lua -- one place for every colour, so the game reads as a system.
local P = {}

P.bg          = { 0.045, 0.065, 0.080 }
P.grid        = { 0.105, 0.115, 0.150 }
P.gridMajor   = { 0.140, 0.155, 0.200 }
P.panel       = { 0.068, 0.092, 0.115 }
P.panelEdge   = { 0.155, 0.210, 0.245 }

P.text        = { 0.880, 0.905, 0.960 }
P.textDim     = { 0.650, 0.700, 0.770 }
P.textFaint   = { 0.490, 0.550, 0.630 }

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
