-- Terrain sizes in map metres. Existing surveyed terrain is saved unchanged.
return {
  small={min=45,max=110}, medium={min=110,max=200}, large={min=200,max=275},
  massive={min=400,max=850},
  massiveChance=0.30, -- one attempt per eligible region
  massiveDistance=3, -- Chebyshev distance from the starting region
  border=30, -- the least distance from an obstacle's centre to its region's edge
  spill=0.35, -- or this share of its radius: the rest may lie over the line
}
