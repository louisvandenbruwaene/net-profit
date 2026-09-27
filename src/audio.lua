-- audio.lua -- every sound is synthesised at load, so the game ships with no
-- audio files. The palette is deliberately narrow: soft sine blips for things
-- you build, filtered noise for things that break, and a rising interval for
-- things that succeed. Nothing here is a sample.
local A = {}

local RATE = 44100
local enabled = true
local master = 0.55


--------------------------------------------------------------------------------
-- Synthesis
--------------------------------------------------------------------------------

local function oscillate(kind, phase)
  if kind == "sine" then
    return math.sin(phase * 2 * math.pi)
  elseif kind == "tri" then
    local p = phase % 1
    return p < 0.5 and (4 * p - 1) or (3 - 4 * p)
  elseif kind == "square" then
    return ((phase % 1) < 0.5) and 1 or -1
  elseif kind == "saw" then
    return 2 * (phase % 1) - 1
  else -- noise
    return math.random() * 2 - 1
  end
end

-- One voice rendered into a sample buffer.
--   f0, f1   start and end frequency (exponential sweep)
--   attack   seconds of linear fade in, keeps clicks out of the attack
--   curve    exponential decay rate; higher is shorter
local function voice(buf, n, spec)
  local kind   = spec.wave or "sine"
  local f0     = spec.f0 or 440
  local f1     = spec.f1 or f0
  local gain   = spec.gain or 0.5
  local attack = spec.attack or 0.004
  local curve  = spec.curve or 12
  local delay  = math.floor((spec.delay or 0) * RATE)
  local phase  = 0

  for i = 0, n - 1 do
    local idx = i + delay
    if idx < n then
      local t = i / RATE
      local dur = n / RATE
      local k = (dur > 0) and (i / n) or 0
      local freq = f0 * ((f1 / f0) ^ k)
      phase = phase + freq / RATE

      local env
      if t < attack then
        env = t / attack
      else
        env = math.exp(-(t - attack) * curve)
      end

      buf[idx] = (buf[idx] or 0) + oscillate(kind, phase) * env * gain
    end
  end
end

-- Mixes voices, soft-clips, and hands back a love SoundData.
local function build(dur, voices)
  local n = math.max(1, math.floor(dur * RATE))
  local buf = {}
  for i = 0, n - 1 do buf[i] = 0 end
  for _, v in ipairs(voices) do voice(buf, n, v) end

  local data = love.sound.newSoundData(n, RATE, 16, 1)
  for i = 0, n - 1 do
    local s = buf[i]
    -- tanh-ish soft clip so stacked voices never crackle
    if s > 1 then s = 1 elseif s < -1 then s = -1 end
    s = s - (s * s * s) / 3
    -- short fade at the tail to avoid a click on cutoff
    local tail = n - i
    if tail < 220 then s = s * (tail / 220) end
    data:setSample(i, s)
  end
  return data
end

--------------------------------------------------------------------------------
-- The sound set
--------------------------------------------------------------------------------

local RECIPES = {
  -- Building: soft, short, upward.
  place = { dur = 0.16, voices = {
    { wave = "sine", f0 = 420, f1 = 720, gain = 0.42, curve = 20 },
    { wave = "sine", f0 = 840, f1 = 1440, gain = 0.12, curve = 26 },
  } },
  link = { dur = 0.22, voices = {
    { wave = "sine", f0 = 330, f1 = 495, gain = 0.38, curve = 13 },
    { wave = "sine", f0 = 660, f1 = 990, gain = 0.14, curve = 16 },
    { wave = "tri",  f0 = 495, f1 = 660, gain = 0.10, curve = 12, delay = 0.05 },
  } },
  upgrade = { dur = 0.26, voices = {
    { wave = "sine", f0 = 523, f1 = 523, gain = 0.30, curve = 16 },
    { wave = "sine", f0 = 659, f1 = 659, gain = 0.26, curve = 15, delay = 0.055 },
    { wave = "sine", f0 = 784, f1 = 784, gain = 0.24, curve = 14, delay = 0.11 },
  } },
  demolish = { dur = 0.24, voices = {
    { wave = "tri",  f0 = 420, f1 = 180, gain = 0.34, curve = 14 },
    { wave = "noise", f0 = 1, f1 = 1, gain = 0.07, curve = 30 },
  } },
  denied = { dur = 0.18, voices = {
    { wave = "square", f0 = 150, f1 = 118, gain = 0.20, curve = 18 },
  } },
  click = { dur = 0.06, voices = {
    { wave = "sine", f0 = 900, f1 = 700, gain = 0.16, curve = 60 },
  } },

  -- Resolving: a rising swell, then a held major triad on success.
  resolve = { dur = 0.34, voices = {
    { wave = "sine", f0 = 180, f1 = 420, gain = 0.30, curve = 7 },
    { wave = "tri",  f0 = 360, f1 = 840, gain = 0.11, curve = 9 },
  } },
  held = { dur = 0.70, voices = {
    { wave = "sine", f0 = 392, f1 = 392, gain = 0.26, curve = 4.2 },
    { wave = "sine", f0 = 494, f1 = 494, gain = 0.20, curve = 4.0, delay = 0.06 },
    { wave = "sine", f0 = 587, f1 = 587, gain = 0.18, curve = 3.8, delay = 0.12 },
    { wave = "sine", f0 = 784, f1 = 784, gain = 0.10, curve = 3.4, delay = 0.18 },
  } },

  -- Breaking: noise transient over a low thump.
  sever = { dur = 0.42, voices = {
    { wave = "noise", f0 = 1, f1 = 1, gain = 0.30, curve = 26, attack = 0.001 },
    { wave = "sine", f0 = 220, f1 = 70, gain = 0.40, curve = 11, attack = 0.001 },
    { wave = "square", f0 = 110, f1 = 55, gain = 0.10, curve = 15 },
  } },
  destroy = { dur = 0.75, voices = {
    { wave = "noise", f0 = 1, f1 = 1, gain = 0.34, curve = 12, attack = 0.001 },
    { wave = "sine", f0 = 180, f1 = 44, gain = 0.46, curve = 5.5, attack = 0.001 },
    { wave = "saw",  f0 = 90, f1 = 40, gain = 0.12, curve = 7 },
  } },

  -- Events.
  terminal = { dur = 0.85, voices = {
    { wave = "sine", f0 = 659, f1 = 659, gain = 0.22, curve = 3.6 },
    { wave = "sine", f0 = 988, f1 = 988, gain = 0.14, curve = 3.2, delay = 0.10 },
    { wave = "sine", f0 = 1319, f1 = 1319, gain = 0.07, curve = 3.0, delay = 0.20 },
  } },
  collapse = { dur = 1.6, voices = {
    { wave = "sine", f0 = 330, f1 = 82, gain = 0.40, curve = 1.9 },
    { wave = "tri",  f0 = 165, f1 = 55, gain = 0.22, curve = 1.7 },
    { wave = "noise", f0 = 1, f1 = 1, gain = 0.10, curve = 3.2 },
  } },
  unlock = { dur = 0.95, voices = {
    { wave = "sine", f0 = 523, f1 = 523, gain = 0.22, curve = 3.4 },
    { wave = "sine", f0 = 784, f1 = 784, gain = 0.19, curve = 3.2, delay = 0.09 },
    { wave = "sine", f0 = 1047, f1 = 1047, gain = 0.15, curve = 3.0, delay = 0.18 },
    { wave = "sine", f0 = 1319, f1 = 1319, gain = 0.09, curve = 2.8, delay = 0.27 },
  } },
  step = { dur = 0.20, voices = {
    { wave = "sine", f0 = 587, f1 = 880, gain = 0.22, curve = 16 },
  } },
}

local sounds = {}
A.datas = {}

function A.init()
  if not (love and love.sound and love.audio) then enabled = false; return end
  local ok = pcall(function()
    for name, r in pairs(RECIPES) do
      local data = build(r.dur, r.voices)
      -- A small pool per sound so rapid repeats overlap instead of cutting off.
      local pool = { idx = 1 }
      for i = 1, 4 do pool[i] = love.audio.newSource(data, "static") end
      sounds[name] = pool
      A.datas[name] = data
    end
  end)
  enabled = ok
  if not ok then sounds = {} end
end

-- pitch jitter keeps repeated builds from sounding mechanical
function A.play(name, volume, pitch)
  if not enabled then return end
  local pool = sounds[name]
  if not pool then return end
  local src = pool[pool.idx]
  pool.idx = (pool.idx % 4) + 1
  src:stop()
  src:setVolume((volume or 1) * master)
  src:setPitch(pitch or (0.97 + math.random() * 0.06))
  src:play()
end

-- Peak and RMS per sound, so a silent or clipped voice is caught by a test
-- rather than by an ear that is not present.
function A.report()
  local out = {}
  for name, data in pairs(A.datas) do
    local n = data:getSampleCount()
    local peak, sum = 0, 0
    for i = 0, n - 1 do
      local v = data:getSample(i)
      local a = math.abs(v)
      if a > peak then peak = a end
      sum = sum + v * v
    end
    out[#out + 1] = {
      name = name, peak = peak,
      rms = math.sqrt(sum / math.max(1, n)),
      dur = n / RATE,
    }
  end
  table.sort(out, function(a, b) return a.name < b.name end)
  return out
end

function A.setEnabled(v) enabled = v and true or false end

return A
