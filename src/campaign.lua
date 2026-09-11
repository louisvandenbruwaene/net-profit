-- campaign.lua -- a run: twelve contracts of rising difficulty.
--
-- Failure is not fatal. A contract can be re-laid as many times as you like,
-- because the interesting act is finding a cheaper network, not surviving a
-- coin flip. What carries forward is the tools you hold and how far under par
-- you came in.
local G = require("generate")
local C = require("contract")

local Campaign = {}
Campaign.__index = Campaign

function Campaign.new(seed)
  local self = setmetatable({}, Campaign)
  self.seed = seed or os.time()
  self.specs = G.campaign(self.seed)
  self.index = 1
  self.results = {}
  self.totalUnder = 0
  self.complete = false
  if self.specs then self.contract = C.new(self.specs[1]) end
  return self
end

function Campaign:ok() return self.specs ~= nil end

function Campaign:current() return self.contract end

function Campaign:spec() return self.specs and self.specs[self.index] end

-- Re-lay the current contract from an empty site.
function Campaign:retry()
  self.contract = C.new(self.specs[self.index])
  return self.contract
end

function Campaign:record(result)
  self.results[self.index] = result
  self.totalUnder = self.totalUnder + math.max(0, result.under or 0)
end

function Campaign:advance()
  if self.index >= #self.specs then
    self.complete = true
    return false
  end
  self.index = self.index + 1
  self.contract = C.new(self.specs[self.index])
  return true
end

function Campaign:newToolThisContract()
  return G.toolUnlockedAt(self.index)
end

function Campaign:progress()
  return self.index, #self.specs
end

return Campaign
