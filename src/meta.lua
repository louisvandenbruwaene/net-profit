-- meta.lua -- progression that survives a collapse.
-- Each unlock is a named theorem whose effect matches what the theorem says,
-- so the vocabulary is learned by spending it rather than by being told.
local Meta = {}

Meta.THEOREMS = {
  { key = "konig", name = "Konig", cost = 4,
    line = "Start each run with +40 energy.",
    note = "Konig's theorem: in bipartite graphs, maximum matching equals minimum vertex cover." },
  { key = "menger", name = "Menger", cost = 6,
    line = "Begin with a relay already linked to the source.",
    note = "Menger's theorem: the maximum number of disjoint paths equals the size of the minimum cut." },
  { key = "ford_fulkerson", name = "Ford-Fulkerson", cost = 9,
    line = "+15 energy every wave you hold.",
    note = "The augmenting path method: push flow along any path with slack until none remains." },
  { key = "dirac", name = "Dirac", cost = 11,
    line = "Every relay carries one extra port.",
    note = "Dirac's theorem: minimum degree at least n/2 forces a Hamiltonian cycle." },
  { key = "whitney", name = "Whitney", cost = 12,
    line = "Links cost 20% less.",
    note = "Whitney's inequality: vertex connectivity <= edge connectivity <= minimum degree." },
  { key = "euler", name = "Euler", cost = 16,
    line = "Absorb the first strike of every run.",
    note = "Euler: a connected graph has a closed walk over every edge exactly when all degrees are even." },
}

local FILE = "augment_save.lua"

local function blank()
  return { insight = 0, unlocked = {}, runs = 0, bestWave = 0, bestFlow = 0 }
end

function Meta.load()
  if not (love and love.filesystem and love.filesystem.getInfo(FILE)) then return blank() end
  local ok, chunk = pcall(love.filesystem.load, FILE)
  if not ok or not chunk then return blank() end
  local ok2, data = pcall(chunk)
  if not ok2 or type(data) ~= "table" then return blank() end
  local d = blank()
  d.insight  = tonumber(data.insight) or 0
  d.runs     = tonumber(data.runs) or 0
  d.bestWave = tonumber(data.bestWave) or 0
  d.bestFlow = tonumber(data.bestFlow) or 0
  if type(data.unlocked) == "table" then
    for _, t in ipairs(Meta.THEOREMS) do
      if data.unlocked[t.key] then d.unlocked[t.key] = true end
    end
  end
  return d
end

function Meta.save(d)
  if not (love and love.filesystem) then return end
  local parts = { "return {\n" }
  parts[#parts + 1] = string.format("  insight = %d,\n", d.insight or 0)
  parts[#parts + 1] = string.format("  runs = %d,\n", d.runs or 0)
  parts[#parts + 1] = string.format("  bestWave = %d,\n", d.bestWave or 0)
  parts[#parts + 1] = string.format("  bestFlow = %d,\n", d.bestFlow or 0)
  parts[#parts + 1] = "  unlocked = {\n"
  for _, t in ipairs(Meta.THEOREMS) do
    if d.unlocked[t.key] then parts[#parts + 1] = string.format("    [%q] = true,\n", t.key) end
  end
  parts[#parts + 1] = "  },\n}\n"
  love.filesystem.write(FILE, table.concat(parts))
end

function Meta.cost(key)
  for _, t in ipairs(Meta.THEOREMS) do if t.key == key then return t.cost end end
end

function Meta.unlock(d, key)
  if d.unlocked[key] then return false, "already known" end
  local cost = Meta.cost(key)
  if not cost then return false, "unknown theorem" end
  if (d.insight or 0) < cost then return false, "not enough insight" end
  d.insight = d.insight - cost
  d.unlocked[key] = true
  Meta.save(d)
  return true
end

function Meta.record(d, run)
  d.runs = (d.runs or 0) + 1
  d.bestWave = math.max(d.bestWave or 0, run.wave)
  d.bestFlow = math.max(d.bestFlow or 0, run.peakFlow)
  d.insight = (d.insight or 0) + run:insightEarned()
  Meta.save(d)
end

return Meta
