-- city.lua -- the company: a persistent network, a ledger, and a day that ends.
--
-- You are the CEO of a utility. Wells produce, pipes carry, customers pay, and
-- pipes rot. Every day the same question is asked in a slightly different shape:
-- the money in hand can be spent on capacity, on resilience, on reputation, or
-- on nothing at all so it can earn interest. There is no single right answer,
-- which is the point.
local Graph = require("graph")
local NB = require("network_builder")
local Shape = require("terrain_shape")

local City = {}
City.__index = City

-- Structures. These are shared ground: a manifold hosts water and oil alike, so
-- their price does not depend on what flows through them.
City.price = require("data.economy").price

-- Everything a pipe costs, per trade.
--
-- A pipe is priced the way a contractor would price it: two tie-ins, a trench,
-- and a bore. The tie-ins are charged per end regardless of length, because
-- connecting a house to a main that runs past its door is still a day's work
-- with a digger. The trench is charged per metre. The bore -- extra capacity --
-- is charged both as fittings at the ends and as the wider pipe along the whole
-- run, so a fat trunk main across the map is the most expensive thing you can
-- build and a fat stub is nearly free.
--
-- Water is cheap and thin-margined. Beer is food-grade: sanitary fittings,
-- gentler pumps, more of everything. Oil is pressurised and hazardous, and its
-- prices say so -- which is the reason a factory pays $26 a unit and a house
-- pays $4.
City.trade = require("data.economy").trade

-- What a link costs, by what is going down it.
--
-- A main, a cable and a road are three different pieces of infrastructure and
-- they are priced as three different pieces of infrastructure. Which one is
-- being laid is decided by what is being moved: nobody pipes iron ore and
-- nobody puts water on a lorry, so the commodity picks the conduit and the
-- player never has to.
--
-- A road does not corrode. That is the trade for its higher running cost: it
-- never leaks, never bursts and never needs a crew, but every metre of it is
-- dearer to keep than a metre of water main.
City.FORMS = require("data.pipes").FORMS

-- Rail. A haven lands freight at the edge of the city and rail moves it inland,
-- which is a different problem from plumbing: the yard at each end is the
-- expensive part, the run itself is cheap by the metre once it exists, it
-- reaches across whole districts, and it does not corrode. Track never leaks,
-- so it is the one link in the game you build and then forget about.
--------------------------------------------------------------------------------
-- Building out of what the network carries
--
-- Cash is not the only thing a building costs. Steel and concrete are things
-- the company either imports through a haven or makes for itself, and either
-- way they have to be delivered: materials are taken in at the depot yards and
-- spent from there, which is the loop the whole map exists to close. The
-- network carries the materials that extend the network.
--
-- Nothing the company needs on day one is on this list. A haven and a yard are
-- cash, because otherwise there would be no way to land the first ton of steel,
-- and pipes, junctions and wells are cash because a utility can be run without
-- ever building a factory.
--------------------------------------------------------------------------------
City.MATERIALS = require("data.freight").MATERIALS

-- How much room a yard has for materials, and how fast it takes delivery.
City.yardStock = require("data.freight").yardStock
City.yardIntakeRate = require("data.freight").yardIntakeRate

function City:materialStock(key)
  return math.floor((self.stock or {})[key] or 0)
end

-- What a yard is still willing to take in today: what it has room for, capped
-- by what it can handle in a day.
function City:yardIntake(material)
  local yards = #self.g:nodesOfKind("dc")
  if yards == 0 then return 0 end
  local room = math.max(0, yards * City.yardStock - self:materialStock(material))
  return math.min(yards * City.yardIntakeRate, room)
end

-- The bill of materials for a thing, and whether it can be paid.
function City:materialsFor(kind, key)
  if kind == "source" or kind == "bulk" then return City.MATERIALS[key or ""] or {} end
  -- Each works carries its own bill, because the three that let a company into
  -- a new trade must cost nothing but cash and the rest are worth a real one.
  if kind == "works" then
    local recipe = City.RECIPES[key or ""]
    return recipe and recipe.materials or City.MATERIALS.works
  end
  return City.MATERIALS[kind] or {}
end

-- Walked in commodity order rather than with `pairs`, so the shortage the
-- player is told about is the same one every time rather than whichever key the
-- hash happened to hand back first.
function City:materialError(bill, scale)
  scale = scale or 1
  if not bill then return nil end
  for _, material in ipairs(Graph.ALL) do
    local amount = bill[material]
    if amount then
      local want = math.ceil(amount * scale)
      if self:materialStock(material) < want then
        return "needs " .. want .. " " .. require("symbols").get(material) .. ", and the yards hold "
          .. self:materialStock(material)
      end
    end
  end
  return nil
end

function City:spendMaterials(bill, scale)
  scale = scale or 1
  self.stock = self.stock or {}
  self.orders = self.orders or {}
  self.taught = self.taught or {}
  for material, amount in pairs(bill or {}) do
    self.stock[material] = math.max(0, (self.stock[material] or 0) - math.ceil(amount * scale))
  end
end

--------------------------------------------------------------------------------
-- Bulk freight
--
-- The second network. A main carries one thing to one place and is priced by
-- the metre; a bulk line carries whatever you load onto it, in wagons or holds,
-- between two places big enough to handle freight. It costs a fortune to build
-- and moves amounts a pipe cannot.
--
-- The four modes exist because each one owns a niche the others cannot take.
-- Rail is the workhorse: enormous to lay, almost free to run, and it reaches
-- across districts. A highway is quick and cheap to put down and expensive
-- every day it is used, because it is paid for in drivers and diesel. Shipping
-- is the cheapest thing on the map per unit per metre and only touches the
-- coast. Air costs more than the freight is usually worth and goes anywhere,
-- immediately, which is exactly what you want for something small and dear.
--------------------------------------------------------------------------------
City.MODES = require("data.freight").MODES
City.MODE_ORDER = { "rail", "highway", "sea", "air" }

-- Where freight can be handled at all: a haven, or a distribution centre.
City.BULK_NODES = { terminal = true, dc = true }

function City:isBulkNode(n)
  return n and n.alive and City.BULK_NODES[n.kind] == true
end

-- Whether a mode may run between these two, and why not.
function City:bulkError(a, b, mode)
  local spec = City.MODES[mode]
  if not spec then return "no such mode" end
  local na, nb = self.g.nodes[a], self.g.nodes[b]
  if not (self:isBulkNode(na) and self:isBulkNode(nb)) then
    return "bulk runs between havens and distribution centres"
  end
  if spec.needs == "coast" then
    if not (self:afloat(na) and self:afloat(nb)) then return "a ship calls at the coast or the river, not inland" end
  elseif spec.needs == "air" then
    if not (na.haven == "airfield" and nb.haven == "airfield") then
      return "air freight flies between air freight havens"
    end
  end
  return nil
end

-- Haulage is charged the way freight is really charged: a handling fee per unit
-- at the yard, and a rate per unit per metre for the run. It is the reason
-- water is rarely worth importing across the whole city and oil almost always
-- is -- the freight bill is the same for both, and one of them sells for six
-- times the other.
City.rail = require("data.freight").rail

-- Everything the city moves that is not one of the four original trades is
-- priced off its form, with its own landed price and its own wholesale value.
-- Only the numbers that actually differ are written down.
City.GOODS = require("data.freight").GOODS

-- Built once, at load: every commodity gets a full price list, made of its
-- form's numbers with its own on top. The four original trades keep the numbers
-- they were tuned with, which is why they are written out in full above.
for _, key in ipairs(Graph.ALL) do
  local spec = Graph.COMMODITIES[key]
  local form = City.FORMS[spec.form] or City.FORMS.liquid
  local trade = City.trade[key] or {}
  for field, value in pairs(form) do
    if trade[field] == nil then trade[field] = value end
  end
  for field, value in pairs(City.GOODS[key] or {}) do trade[field] = value end
  trade.form = spec.form
  City.trade[key] = trade
end

-- Pipe condition. Lining is never required -- a bare pipe works exactly as well
-- on the day it is laid. It buys three things at once: a pipe that fouls far
-- less often, a cheaper repair when it does, and a player who spends the day
-- building instead of chasing burst mains. On a short water stub that is a poor
-- trade. On a 600m oil trunk it pays for itself in about a fortnight.
--------------------------------------------------------------------------------
-- Pipe
--
-- A main is a thing that was put in the ground once. It comes in three sizes
-- and nothing widens it: if the small main you laid three years ago is too
-- small now, it comes out and a bigger one goes in, which is exactly what
-- happens in a real street.
--
-- The lining is decided the same way. Whatever the company knew how to lay on
-- the day the main went in is what that main has forever, so the old cheap
-- pipes at the centre of the network stay the weakest thing you own until
-- somebody digs them up. That is the whole reason to go back and replace
-- perfectly working mains.
--------------------------------------------------------------------------------
City.PIPE_SIZES = require("data.pipes").PIPE_SIZES

-- Whether this company may lay a size yet.
function City:sizeAllowed(spec)
  return not spec.unlock or self:unlocked(spec.unlock)
end

-- Callers may name a size or say how much they need carried. Saying how much
-- gets the smallest main that does it, which is what a contractor would sell
-- you and what every older caller in the game meant anyway.
function City.asSize(size)
  if type(size) == "number" then return (City.sizeFor(size)) end
  return (City.sizeOf(size))
end

-- How much further this size runs between pumps. Pressure gradient falls as
-- Q^(-1/3) at each size's design flow, so a trunk covers ground a stub cannot.
-- Callers that do not yet know the size get the smallest, which is the old
-- flat behaviour and is never an overestimate.
function City.reachFor(size)
  if not size then return 1 end
  local spec = City.asSize(size)
  return (spec and spec.reach) or 1
end

function City.sizeOf(key)
  for i, spec in ipairs(City.PIPE_SIZES) do
    if spec.key == key then return spec, i end
  end
  return City.PIPE_SIZES[1], 1
end

-- The smallest size that would carry this much, for migrating old mains and for
-- the departments deciding what to replace a full one with.
function City.sizeFor(capacity)
  for i, spec in ipairs(City.PIPE_SIZES) do
    if spec.cap >= capacity then return spec, i end
  end
  return City.PIPE_SIZES[#City.PIPE_SIZES], #City.PIPE_SIZES
end

--------------------------------------------------------------------------------
-- What a structure will answer to
--
-- The four sizes are not just a price ladder, they are what makes a network a
-- network rather than a spiderweb of point-to-point stubs. A house is a
-- nozzle: it could never use more than a small main and would not know what
-- to do with one. A well, a rig or a plant is the opposite end of the same
-- idea -- it is a lot of ground answering through one wellhead, so nothing
-- smaller than a trunk is allowed to be the whole of its output. Everything
-- between the two -- a junction, a manifold, a pump, a hub -- is not listed
-- here at all, because passing a trunk in and a stub out, at two different
-- sizes, is the entire reason to build one.
--------------------------------------------------------------------------------
City.SIZE_LIMIT = require("data.pipes").SIZE_LIMIT

-- The narrowest and widest size either end of a-b will accept, or nil if the
-- two ends want incompatible things -- a well cannot be wired straight to a
-- house at any size, and that is the point: something has to stand between
-- them and change the pipe's size.
function City:sizeRange(a, b)
  local lo, hi = 1, #City.PIPE_SIZES
  for _, id in ipairs({ a, b }) do
    local n = self.g.nodes[id]
    local lim = n and City.SIZE_LIMIT[n.kind]
    if lim then
      if lim.min then lo = math.max(lo, (select(2, City.sizeOf(lim.min)))) end
      if lim.max then hi = math.min(hi, (select(2, City.sizeOf(lim.max)))) end
    end
  end
  if lo > hi then return nil end
  return lo, hi
end

-- What the company knows how to lay. Each level is bought once and then costs
-- more every time it is used, and the top one is a main that practically never
-- fails and practically never pays for itself in money alone.
City.GRADES = require("data.pipes").GRADES

City.rules = require("data.economy").rules

-- Customers. Rich ones pay far more and forgive far less, which is the whole
-- reason to lay a beer main instead of another row of houses.
City.CLIENTS = require("data.customers").CLIENTS
City.DUAL = require("data.customers").DUAL

City.OBSTACLES = {
  bedrock = { name = "BEDROCK", cross = nil, color = {0.30, 0.28, 0.34} },
  park    = { name = "PARKLAND", cross = 2, color = {0.32, 0.52, 0.36} },
  river   = { name = "RIVER",   cross = 3, color = {0.30, 0.48, 0.72} },
}

--------------------------------------------------------------------------------

function City:random(lo, hi)
  local value
  -- While a cell is being generated every draw comes out of that cell's own
  -- stream, so ground never depends on the order it was looked at in.
  if self.cellRng then
    self.cellRng.state = (self.cellRng.state * 16807) % 2147483647
    value = (self.cellRng.state - 1) / 2147483646
  else
    self.rng = (self.rng * 16807) % 2147483647
    value = (self.rng - 1) / 2147483646
  end
  if hi then return math.floor(lo + value * (hi - lo + 1)) end
  if lo then return math.floor(1 + value * lo) end
  return value
end

function City:rand(lo, hi) return lo + self:random() * (hi - lo) end

-- Box-Muller: investment returns are normal, so a bad run of luck is possible
-- and a good one is not a bug.
local function gauss(self, mean, sd)
  local u1 = math.max(1e-9, self:random())
  local u2 = self:random()
  return mean + sd * math.sqrt(-2 * math.log(u1)) * math.cos(2 * math.pi * u2)
end

function City.new(opts)
  opts = opts or {}
  local self = setmetatable({}, City)
  self.seed = opts.seed or os.time()
  self.rng = self.seed % 2147483646 + 1
  self.bounds = { x = 0, y = 0, w = City.MAP.cols * City.MAP.w, h = City.MAP.rows * City.MAP.h }
  self.g = Graph.new()
  self.day = 1
  self.money = City.rules.startMoney
  self.reputation = 50
  self.quality = 0
  self.lining = 1
  self.adDaysLeft = 0
  self.investments = {}
  self.obstacles = {}
  self.deposits = {}
  self.licences = { water = true, power = false, beer = false, oil = false, food = false, internet = false }
  self.links = {}
  self.permits = { park = false, river = false, bedrock = false }
  self.sourcesBought = 0
  self.intakesBought = 0
  self.log = {}
  self.history = {}
  self.bankrupt = false
  self.lostClients = 0
  self.pipeGrade = {}
  self.milestones = {}
  self.crews = 0
  self.stock = {}
  self.orders = {}
  self.taught = {}
  self.loan = 0
  self.event = nil
  self.districtsBought = 0

  self:layOutRiver()
  self:layOutDistricts(opts)

  -- The opening is a job rather than a company: a spring the survey has marked
  -- in the middle of your ground, one household that has asked to be connected,
  -- and just enough money to sink the well and lay the main. Everything the
  -- player will do for the rest of the game, they do once here first.
  local home = self.districts[City.MAP.start]
  local cx, cy = home.x + home.w / 2, home.y + home.h / 2
  self.deposits[#self.deposits + 1] = {
    x = cx - 150, y = cy - 20, commodity = "water", taken = false,
    yield = 1.5, discount = 1.0, cap = City.depositCap("water", 0),
    -- Marked, so the opening can point at this one rather than at whichever
    -- spring the survey happened to scatter nearby.
    opening = true,
  }
  local first = self:addClient("house", true)
  -- Close enough to the spring that one main reaches it. The opening is three
  -- actions, and "you also need a junction halfway" is not one of them.
  first.x, first.y = cx + 110, cy + 45
  first.demand, first.rate = 3, City.CLIENTS.house.rate
  -- Nothing else is standing yet, so the map anchors on the household until
  -- there is a well to anchor on.
  self.firstSource = first

  self:refresh()
  return self
end

--------------------------------------------------------------------------------
-- The map: twelve districts, one of them yours
--------------------------------------------------------------------------------

-- Ground you have not bought is ground you cannot build on, and the map is
-- deliberately larger than one company can afford early. A district is the
-- single biggest cheque in the game, and buying one is the only way to reach
-- the trades that live out there.
City.MAP = { cols = 4, rows = 3, w = 1000, h = 700, start = 6 }

City.DISTRICTS = {
  { name = "Northgate",   bias = { house = 16, workshop = 5, estate = 3 },  rough = 2 },
  { name = "Hillcrest",   bias = { house = 5,  estate = 12 },             rough = 2 },
  { name = "The Moors",   bias = { house = 4,  estate = 4 },              rough = 5, seams = 2 },
  { name = "Ironworks",   bias = { factory = 14, workshop = 9, house = 4 },  rough = 3, seams = 1 },
  { name = "Old Town",    bias = { house = 12, pub = 8 },                 rough = 2 },
  { name = "Millbrook",   bias = { house = 10, estate = 3, workshop = 4, pub = 4, factory = 3 }, rough = 2 },
  { name = "Brewers Row", bias = { pub = 15, house = 5 },                 rough = 2, seams = 1 },
  { name = "Docklands",   bias = { factory = 13, workshop = 7, pub = 5 },   rough = 3 },
  { name = "Southfield",  bias = { estate = 13, house = 6 },              rough = 2 },
  { name = "Canalside",   bias = { pub = 10, house = 8 },                 rough = 3 },
  { name = "The Flats",   bias = { house = 14, workshop = 6, estate = 5 },  rough = 2 },
  { name = "Deepcut",     bias = { factory = 12, workshop = 8, estate = 4 }, rough = 5, seams = 3 },
}

City.districtPrice = { base = 700, growth = 1.42 }

--------------------------------------------------------------------------------
-- Ground beyond the authored twelve
--
-- The city does not stop. South, east and west of the authored core the map
-- carries on for as long as the company can pay for it, and every cell out
-- there is generated rather than written. North is the sea, which is the one
-- direction that ends.
--
-- Generation must not touch `self.rng`. That stream is shared with leaks,
-- offers and market events, so anything drawn from it would depend on the order
-- the player happened to pan around in, and the same ground would generate
-- differently on a reload. Each cell gets its own stream instead, mixed out of
-- the company seed and the cell's own coordinates, so a cell is the same ground
-- whoever surveys it first and however many times it is saved and loaded.
--------------------------------------------------------------------------------

-- How far outside the core a cell sits. Nought is the authored city, one is the
-- ring of ground touching it, and so on outward forever.
function City.ringOf(col, row)
  local dc = math.max(1 - col, 0, col - City.MAP.cols)
  local dr = math.max(1 - row, 0, row - City.MAP.rows)
  return math.max(dc, dr)
end

-- Ground the company can see. Two rings past what it owns: enough to plan a
-- direction, not enough to survey the whole world from the yard.
City.surveyRadius = 2

-- Names for generated ground. Two halves and a handful of whole names, which is
-- how English towns are built anyway.
City.NAMES = {
  head = { "Ash", "Bram", "Cold", "Dun", "East", "Fen", "Grey", "Har", "Kil",
           "Long", "Mar", "North", "Oak", "Pike", "Quar", "Red", "Stan",
           "Thorn", "Up", "Wick", "Yar", "Black", "Clay", "Hollow", "Swan" },
  tail = { "field", "ford", "hollow", "moor", "ridge", "stead", "thorpe",
           "vale", "wick", "worth", "bury", "combe", "gate", "mere", "row",
           "side", "bridge", "heath", "cross", "barrow" },
}

-- What kind of place a generated cell is. The character decides who asks you
-- for a connection out there and what the survey finds underneath.
City.ARCHETYPES = {
  { key = "suburb",   label = "SUBURB",     rough = 2, water = 3, oil = 0,
    bias = { house = 14, estate = 6, workshop = 3 },
    story = "Streets of new houses, laid out faster than anyone can supply them." },
  { key = "farm",     label = "FARMLAND",   rough = 1, water = 4, oil = 0,
    bias = { house = 8, estate = 3, pub = 3 },
    story = "Open country. Little demand, shallow water, and room to build." },
  { key = "forest",   label = "WOODLAND",   rough = 5, water = 3, oil = 0,
    bias = { house = 5, pub = 3 },
    story = "Timber country. Hard to cross, and the crossing charges say so." },
  { key = "quarry",   label = "QUARRY",     rough = 6, water = 2, oil = 1,
    bias = { workshop = 8, factory = 4 },
    story = "Worked rock and standing water. Everything here is under something." },
  { key = "works",    label = "INDUSTRY",   rough = 3, water = 2, oil = 2,
    bias = { factory = 12, workshop = 8, pub = 4 },
    story = "Heavy plant that pays heavy rates, if you can reach it." },
  { key = "frontier", label = "WILDERNESS", rough = 4, water = 2, oil = 3,
    bias = { house = 3, workshop = 2, factory = 3 },
    story = "Nobody out here yet. The deepest seams on the map are, though." },
  -- Only out past the second ring: a town that was here before the company,
  -- full of people and with nobody moving them.
  { key = "city",     label = "CITY",       rough = 2, water = 3, oil = 0, population = 900,
    bias = { house = 12, estate = 6, pub = 4, workshop = 4 },
    story = "A town that was here before the company. Thousands of people, and nobody moving them." },
}

-- What a deposit at this distance can give in a day, whatever is built on top
-- of it. This is the number that makes the map endless rather than merely
-- large: a well reaches its cap and then the only way to more supply is more
-- ground, further out.
--
-- These are set against the pipe ladder rather than in isolation. A source
-- must answer to a LARGE main, so ground that tops out under 50 is ground
-- that can only ever half-fill the trunk it is required to lay. Ordinary
-- ground is deliberately left a little short of that, and reaching it, and
-- then passing it, is what the river is for.
City.DEPOSIT = {
  water = { base = 34, perRing = 12 },
  oil   = { base = 26, perRing = 10 },
  buried = 1.35,
}

-- What unmarked ground gives, as a multiple of a trade's opening output.
City.groundYield = 1.9

--------------------------------------------------------------------------------
-- The intake
--
-- A well is a hole over a pocket of ground and it runs out. An intake is a
-- treatment works standing on running water, and what limits it is not the
-- water but the plant: how much can be lifted, settled and filtered in a day.
-- So it is finite, like everything else, but its ceiling is set by the channel
-- it stands on rather than by a constant. A wide estuary will carry a city's
-- whole supply through one building. A headwater branch will not, and no
-- amount of money will make it.
--
-- This is the organ the network is meant to grow around: one heart, deep
-- rather than many, with the hierarchy of mains fanning out from it.
--------------------------------------------------------------------------------
City.INTAKE = {
  -- Sized against what leaves the building rather than against a well. An
  -- intake has two outlets, and the widest main is a MASSIVE at 100, so a
  -- works on a broad estuary tops out at about what two trunks can carry away
  -- and not a drop more. A headwater branch gives roughly half that.
  riverBase = 60, riverPerHalf = 1.15,
  sea = 150,
  -- A works is commissioned bigger than a well is sunk, and every stage after
  -- that adds more than a well's deepening does. Thirteen stages of fourteen
  -- carry it to about two hundred, which is where two trunks stop it anyway.
  output = 34, step = 14, maxLevel = 13,
  -- How close to the water a works has to stand. Deliberately much tighter
  -- than the reach a well on the bank draws from: an intake is a building
  -- standing over the channel, not a shaft that happens to be near one, and
  -- if half the map counted as bank then nothing about siting would matter.
  reach = 110,
}

-- The ceiling on an intake at this spot, or nil if there is no running water
-- and no sea here. `hw` is the river's half-width where it is tapped.
function City:intakeCap(x, y)
  local edge, hw = self:riverEdge(x, y)
  if edge and edge >= 0 and edge <= City.INTAKE.reach then
    -- The flared estuary is tidal and brackish: an intake there lifts no more
    -- than one on the widest fresh reach.
    return math.floor(City.INTAKE.riverBase + City.INTAKE.riverPerHalf * math.min(hw or 0, 120)), "river"
  end
  if self:onCoast(x, y) then return City.INTAKE.sea, "sea" end
  return nil
end

-- How far a source of this kind can be pushed. An intake is a different organ
-- from a well and goes a great deal deeper.
function City:maxDepth(n)
  if n and n.intake then return City.INTAKE.maxLevel end
  return City.sourceMaxLevel
end

function City.depositCap(commodity, ring, buried)
  local spec = City.DEPOSIT[commodity] or City.DEPOSIT.water
  local cap = spec.base + spec.perRing * ring
  if buried then cap = cap * City.DEPOSIT.buried end
  return math.floor(cap)
end

-- A stream of its own for one cell, mixed from the company seed and the cell.
function City:cellSeed(col, row)
  local h = 2166136261
  local function mix(v)
    h = (h + (v % 4294967296)) % 4294967296
    h = (h * 16777619) % 4294967296
    h = (h + math.floor(h / 65536)) % 4294967296
  end
  mix(self.seed or 1)
  mix(col * 73856093 % 4294967296)
  mix(row * 19349663 % 4294967296)
  return h % 2147483646 + 1
end

-- Runs `fn` with every self:random() call coming out of one cell's own stream.
function City:withCell(col, row, fn)
  local previous = self.cellRng
  self.cellRng = { state = self:cellSeed(col, row) }
  local ok, err = pcall(fn)
  self.cellRng = previous
  if not ok then error(err, 0) end
end

function City.cellKey(col, row) return col .. "," .. row end

-- Every cell that exists, by key. Rebuilt on load rather than saved.
function City:indexCells()
  self.cellIndex = {}
  for _, d in ipairs(self.districts) do
    self.cellIndex[City.cellKey(d.col, d.row)] = d.id
  end
end

function City:cellAt(col, row)
  local id = (self.cellIndex or {})[City.cellKey(col, row)]
  return id and self.districts[id] or nil
end

-- Names for the ground out in the water, which is not named like a suburb.
City.ISLAND_NAMES = {
  head = { "Gull", "Slack", "Herring", "Cormorant", "Salt", "Wreck", "Storm",
           "Seal", "Tern", "Mussel", "Anchor", "Kelp", "Skerry", "Bell" },
  tail = { " Island", " Rock", " Holm", " Skerry", " Bank", " Sands", " Reef" },
}

City.ISLAND = {
  chance = 0.34,        -- of a surveyed sea cell having anything in it at all
  minW = 460, maxW = 680,
  minH = 300, maxH = 400,
  coastGap = 200,        -- minimum sea between an island's near edge and the coast
}

-- Bring one cell into being.
--
-- North of row one is sea. Most of it is water and generates nothing at all,
-- which is what stops the company walking north, but some of it is island: real
-- ground, bought outright rather than next door, and reachable only by a
-- company that already has a harbour.
function City:surveyCell(col, row)
  if row < 1 then return self:surveyIsland(col, row) end
  local existing = self:cellAt(col, row)
  if existing then return existing end

  local ring = City.ringOf(col, row)
  local core = ring == 0 and City.DISTRICTS[(row - 1) * City.MAP.cols + col]
  local id = #self.districts + 1
  local d = {
    id = id, col = col, row = row, ring = ring,
    x = (col - 1) * City.MAP.w, y = (row - 1) * City.MAP.h,
    w = City.MAP.w, h = City.MAP.h, owned = false,
  }
  self.districts[id] = d
  self.cellIndex = self.cellIndex or {}
  self.cellIndex[City.cellKey(col, row)] = id

  if core then
    d.name, d.spec = core.name, core
  else
    self:withCell(col, row, function()
      -- Further out is wilder: the settled archetypes thin out and the ground
      -- worth digging takes over.
      local pool = {}
      for _, a in ipairs(City.ARCHETYPES) do
        local weight = (a.key == "suburb" and math.max(1, 9 - ring * 3))
          or (a.key == "farm" and math.max(1, 8 - ring))
          or (a.key == "frontier" and math.min(9, ring * 3))
          or (a.key == "works" and math.min(7, 1 + ring))
          or (a.key == "city" and (ring >= 2 and 3 or 0))
          or 4
        for _ = 1, weight do pool[#pool + 1] = a end
      end
      d.spec = pool[self:random(#pool)]
      d.archetype = d.spec.key
      if d.spec.population then
        d.population = d.spec.population + 150 * ring
        d.founded = d.population
      end
      d.name = City.NAMES.head[self:random(#City.NAMES.head)]
        .. City.NAMES.tail[self:random(#City.NAMES.tail)]
    end)
  end
  self:growBounds(d)
  return d
end

function City:surveyIsland(col, row)
  local existing = self:cellAt(col, row)
  if existing then return existing end
  local seed = self:cellSeed(col, row)
  -- One draw decides whether there is anything here, taken from the cell's own
  -- stream so the same square of sea is empty or not for good.
  local roll = ((seed * 16807) % 2147483647 - 1) / 2147483646
  if roll > City.ISLAND.chance then return nil end

  local id = #self.districts + 1
  local d = { id = id, col = col, row = row, ring = City.ringOf(col, row), island = true }
  self.districts[id] = d
  self.cellIndex = self.cellIndex or {}
  self.cellIndex[City.cellKey(col, row)] = id
  self:withCell(col, row, function()
    self:random()
    d.w = self:rand(City.ISLAND.minW, City.ISLAND.maxW)
    d.h = self:rand(City.ISLAND.minH, City.ISLAND.maxH)
    local cellX, cellY = (col - 1) * City.MAP.w, (row - 1) * City.MAP.h
    d.x = cellX + self:rand(80, City.MAP.w - d.w - 80)
    -- The south edge of the cell borders the coast (row 0) or the next
    -- stretch of sea, so an island keeps clear water between it and that edge.
    d.y = cellY + self:rand(40, City.MAP.h - d.h - City.ISLAND.coastGap)
    d.name = City.ISLAND_NAMES.head[self:random(#City.ISLAND_NAMES.head)]
      .. City.ISLAND_NAMES.tail[self:random(#City.ISLAND_NAMES.tail)]
  end)
  -- Nobody lives out here and nothing is buried under it. What an island is for
  -- is the wind, and for being somewhere the mainland is not.
  d.spec = { key = "island", label = "ISLAND", rough = 0, water = 0, oil = 0, bias = {},
             story = "Bare rock in the sea. The wind never stops, and nobody objects to anything." }
  d.dressed = true
  self:growIslandGroves(d)
  self:growBounds(d)
  return d
end

-- Groves on an island: small woods round its rim, leaving the middle clear for
-- a wind park. They are ordinary parkland, charged and permitted like any
-- other, and they come from a hash of the island's own rectangle rather than
-- from any random stream, so adding them moved nothing else. `careful` is for
-- islands a company already stands on: a grove that would touch a structure,
-- a main or a link is simply not grown.
function City:growIslandGroves(d, careful)
  if d.groves then return end
  d.groves = true
  local h = function(k) return Shape.hash(d.x, d.y, 300 + k) end
  local cx, cy, ax, ay = d.x + d.w / 2, d.y + d.h / 2, d.w / 2 * 0.84, d.h / 2 * 0.84
  -- Two groves at the ends of the long axis, where there is room, and
  -- sometimes a smaller one on a flank.
  local long = d.w >= d.h and 0 or math.pi / 2
  local spots = { { long + math.pi + (h(3) - 0.5) * 0.7, 0.62 }, { long + (h(4) - 0.5) * 0.7, 0.62 } }
  if h(1) < 0.5 then spots[3] = { long + math.pi / 2 * (h(5) < 0.5 and 1 or -1) + (h(6) - 0.5) * 0.6, 0.55 } end
  for i, spot in ipairs(spots) do
    local t, f = spot[1], spot[2] + (h(20 + i) - 0.5) * 0.08
    local x, y = cx + math.cos(t) * ax * f, cy + math.sin(t) * ay * f
    local r = math.min(d.w, d.h) * (i == 3 and 0.22 or 0.32) * (0.9 + h(30 + i) * 0.2)
    -- Shrink until the whole grove sits on the island's grass.
    while r > 40 and ((math.abs(x - cx) + r * 0.8) / ax) ^ 2 + ((math.abs(y - cy) + r * 0.8) / ay) ^ 2 > 1 do r = r * 0.92 end
    local o = { x = x, y = y, r = r, kind = "park", grove = true }
    local ok = r > 40
    if ok and careful then
      for _, n in ipairs(self.g.nodes) do
        if n.alive and (n.x - x) ^ 2 + (n.y - y) ^ 2 < (Shape.reach(o, n.x, n.y) + 30) ^ 2 then ok = false; break end
      end
      for _, e in ipairs(ok and self.g.edges or {}) do
        local a, b = self.g.nodes[e.a], self.g.nodes[e.b]
        if e.alive and a and b and Shape.crosses(o, a.x, a.y, b.x, b.y) then ok = false; break end
      end
      for _, l in ipairs(ok and self.links or {}) do
        local a, b = self.g.nodes[l.a], self.g.nodes[l.b]
        if l.alive and a and b and Shape.crosses(o, a.x, a.y, b.x, b.y) then ok = false; break end
      end
    end
    if ok then self.obstacles[#self.obstacles + 1] = o end
  end
end

-- The ground features of a cell, in the cell's own stream so they never move.
function City:dressCell(d)
  if d.dressed then return d end
  d.dressed = true
  local spec = d.spec or City.ARCHETYPES[1]
  local rough = self.roughness or spec.rough or 2
  self:withCell(d.col, d.row, function()
    self:scatterObstacles(rough, d)
    -- Obstacles can be switched off for a test or a clean opening; deposits
    -- cannot, because with none of them the ground has no water in it.
    self:scatterDeposits(d, spec)
  end)
  return d
end

-- Everything within the survey radius of ground the company holds, brought into
-- being at once. Called when a district is bought and when a company loads, so
-- what the player can see is always exactly what they could buy next plus one.
function City:survey()
  local seeds = {}
  for _, d in ipairs(self.districts) do
    if d.owned then seeds[#seeds + 1] = d end
  end
  if #seeds == 0 then seeds = { self.districts[City.MAP.start] } end
  local want = {}
  for _, d in ipairs(seeds) do
    -- Generate a hidden terrain halo before construction is possible. A future
    -- mountain in the next cell must not appear over an existing building.
    local radius=math.max(1,self:workerCount("dispatchers"))+2
    for dc = -radius, radius do
      for dr = -radius, radius do
        want[#want + 1] = { d.col + dc, d.row + dr }
      end
    end
  end
  for _, cell in ipairs(want) do self:surveyCell(cell[1], cell[2]) end
  for _, d in ipairs(self.districts) do self:dressCell(d) end
  return self
end

-- The surveyed extent, which is what the camera is allowed to roam over and
-- what "outside the map" now means.
function City:growBounds(d)
  local b = self.bounds
  local x0, y0 = math.min(b.x, d.x), math.min(b.y, d.y)
  local x1 = math.max(b.x + b.w, d.x + d.w)
  local y1 = math.max(b.y + b.h, d.y + d.h)
  b.x, b.y, b.w, b.h = x0, y0, x1 - x0, y1 - y0
end

function City:layOutDistricts(opts)
  self.districts = {}
  self.cellIndex = {}
  self.roughness = opts.obstacles
  -- The authored city first, so the opening hand is the one that was tuned,
  -- and then everything the company can see from it.
  for row = 1, City.MAP.rows do
    for col = 1, City.MAP.cols do
      self:surveyCell(col, row)
    end
  end
  self.districts[City.MAP.start].owned = true
  self:survey()
end

-- Which cell a point falls in, by arithmetic rather than by search: the map is
-- a lattice, and on an endless one a linear scan is a promise you cannot keep.
function City:districtAt(x, y)
  local col = math.floor(x / City.MAP.w) + 1
  local row = math.floor(y / City.MAP.h) + 1
  local d = self:cellAt(col, row)
  -- A land cell fills its square. An island is a rock somewhere inside one, and
  -- the water around it is not ground.
  if d and (x < d.x or y < d.y or x >= d.x + d.w or y >= d.y + d.h) then return nil end
  return d
end

-- The extent of what the company holds, which is what the map view should
-- frame. Surveyed ground runs two rings past that in every direction and would
-- pull the camera back far enough to make the labels illegible.
function City:ownedBounds()
  local x0, y0, x1, y1
  for _, d in ipairs(self.districts) do
    if d.owned then
      x0 = math.min(x0 or d.x, d.x); y0 = math.min(y0 or d.y, d.y)
      x1 = math.max(x1 or d.x + d.w, d.x + d.w); y1 = math.max(y1 or d.y + d.h, d.y + d.h)
    end
  end
  if not x0 then local b = self.bounds; return b.x, b.y, b.x + b.w, b.y + b.h end
  return x0, y0, x1, y1
end

function City:ownedDistricts()
  local t = {}
  for _, d in ipairs(self.districts) do if d.owned then t[#t + 1] = d end end
  return t
end

-- Only next door. The company grows outward from its yard, not by teleporting
-- to the far corner of the map.
function City:districtAdjacent(d)
  for _, cell in ipairs({ {1,0}, {-1,0}, {0,1}, {0,-1} }) do
    local o = self:cellAt(d.col + cell[1], d.row + cell[2])
    if o and o.owned then return true end
  end
  return false
end

-- Ground gets dearer the more of it you hold and the further out it is. The
-- second term is what stops a company sprinting for the frontier: the richest
-- deposits are out there, and so is the biggest cheque.
-- Ground gets dearer the more of it you hold and the further out it is, and
-- cheaper the nearer it is to the coast. That last term is the map telling the
-- player which way to go: a harbour is the door to every trade the city cannot
-- make for itself, so the row the harbour stands on is the cheapest ground on
-- the map and every row south of it costs a little more.
function City:districtCost(d)
  local ring = (d and d.ring) or 0
  local row = (d and d.row) or 1
  local inland = math.min(1.45, 0.72 + 0.11 * math.max(0, row - 1))
  -- Waterfront still tempts the routes in cheapest, but the ground itself is
  -- the one everybody else wants too, and it prices accordingly.
  local coastal = (row == 1) and 1.15 or 1
  return math.ceil(City.districtPrice.base
    * (City.districtPrice.growth ^ self.districtsBought)
    * (1 + 0.55 * ring)
    * inland
    * coastal
    * ((d and d.island) and 1.9 or 1))
end

function City:districtError(id)
  local d = self.districts[id]
  if not d then return "no such district" end
  if d.owned then return "already owned" end
  if d.island then
    -- Ships do not care what is next door. A harbour is what an island is next
    -- to, so a company without one has no way to land on it.
    if not self:havenOf("port") then return "an island needs a harbour to reach it" end
  elseif not self:districtAdjacent(d) then return "not next to your ground" end
  if self:districtCost(d) > self.money then return "not enough cash" end
  return nil
end

function City:buyDistrict(id)
  local err = self:districtError(id)
  if err then return nil, err end
  local d = self.districts[id]
  local cost = self:districtCost(d)
  self:spend(cost)
  d.owned = true
  self.districtsBought = self.districtsBought + 1
  -- Owning ground puts the next ring of it on the map.
  self:survey()
  self:note("%s acquired for $%d: %d districts held", d.name, cost, #self:ownedDistricts())
  return d
end

--------------------------------------------------------------------------------
-- Permits: the ground you are not allowed to touch, until you are
--------------------------------------------------------------------------------

-- Each permit converts an obstacle from a wall into a toll. Parkland becomes
-- ordinary ground, the river becomes a manageable crossing, and bedrock becomes
-- expensive but passable -- which matters because the richest seams are under it.
City.PERMITS = require("data.progression").PERMITS
City.PERMIT_ORDER = { "park", "river", "bedrock" }

--------------------------------------------------------------------------------
-- The river
--
-- Not a scattered obstacle like a wood or a bedrock sill: one channel of water
-- that starts at the coast and runs on for as long as the map is generated,
-- because a real river does not stop at a district line and does not end
-- inland. It is placed once, off the home district's own ground so the opening
-- is never fought across it. Its general heading drifts away from that ground
-- and its bends never swing far enough back to reach it.
--
-- No river runs straight. The course meanders in long bends with shorter ones
-- riding on them, swings wider in some reaches than others, flares where it
-- meets the sea and narrows upstream.
--------------------------------------------------------------------------------
City.riverWidth = 170
-- How far a wellhead may stand off the bank and still draw on the river rather
-- than on the deposit under it. Wider than the river itself, because "beside
-- it" is the point -- a well sunk in the water is just a well sunk in the water.
City.riverWellReach = 220
City.riverStep = 40
City.riverLength = 30000

-- The course is a pure function of the river table, so it is rebuilt after a
-- load rather than written into the save.
local riverPaths = setmetatable({}, { __mode = "k" })

-- Laid out from the map's own arithmetic rather than from the district table,
-- so it exists before any cell is dressed and no cell scatters ground into it.
function City:layOutRiver()
  local homeCol = (City.MAP.start - 1) % City.MAP.cols + 1
  self.river = {
    x0 = homeCol * City.MAP.w + 300, y0 = 0,
    angle = math.rad(18),
    width = City.riverWidth,
    -- The bends come out of a stream of their own. The shared stream is spent
    -- by leaks and offers, so drawing on it here would move the river on reload.
    meander = self:cellSeed(-4096, -4096),
    style = 2,
  }
end

-- The second course: a river laid the way rivers lay themselves.
--
-- A meandering river does not follow a sine wave sideways. Its direction does:
-- the angle of the channel swings back and forth as a sine of the distance
-- travelled (Langbein and Leopold's sine-generated curve), which is what gives
-- real meanders their round, almost looping bends rather than a wiggle. The
-- bends scale with the channel, about eleven widths from one to the next, so
-- a river that is wide at its mouth swings in long loops there and in short
-- tight ones upstream where it has narrowed. A little third harmonic leans
-- each bend downstream, the way a real one migrates.
--
-- Tributaries join at an acute angle pointing downstream, each narrower than
-- the river it feeds and narrowing again towards its source.
--
-- Every sample still makes headway south, so the samples stay sorted by y and
-- the bank searches keep working on sorted heights.
local HEADWAY = math.rad(78)

local function sampleCourse(start, heading, length, width, rng, opts)
  opts = opts or {}
  local step = City.riverStep
  local p = { n = 0, x = {}, y = {}, hw = {}, nx = {}, ny = {}, maxHalf = 0 }
  local theta0 = opts.swing or rng(0.95, 1.15)  -- how far a bend swings, in radians
  local drift, driftWave, driftPhase = rng(0.10, 0.22), rng(9000, 14000), rng(0, 2 * math.pi)
  local phase = rng(0, 2 * math.pi)
  local x, y = start.x, start.y
  local steps = math.floor(length / step)
  for i = 0, steps do
    local s = i * step
    local w = width(s)
    local hw = w / 2
    -- The bend rate follows the width, with a slow wander in the wavelength so
    -- no two bends are the same size.
    local wave = 11 * w * (0.85 + 0.3 * (0.5 + 0.5 * math.sin(s / 2300 + phase * 1.7)))
    local ease = math.min(1, s / (opts.ease or 1)) ; ease = ease * ease * (3 - 2 * ease)
    local swing = theta0 * (0.8 + 0.2 * math.sin(s / 5100 + phase)) * ease
    local angle = heading + drift * math.sin(2 * math.pi * s / driftWave + driftPhase)
      + swing * (math.sin(phase) + 0.16 * math.cos(3 * phase))
    angle = math.max(-HEADWAY, math.min(HEADWAY, angle))
    local j = i + 1
    local tx, ty = math.sin(angle), math.cos(angle)
    p.x[j], p.y[j], p.hw[j] = x, y, hw
    p.nx[j], p.ny[j] = -ty, tx
    p.maxHalf = math.max(p.maxHalf, hw)
    p.n = j
    x, y = x + tx * step, y + ty * step
    phase = phase + 2 * math.pi * step / wave
  end
  -- The mouth meets the coast square on, so the estuary opens into the sea.
  if opts.mouth then p.nx[1], p.ny[1] = -1, 0 end
  return p
end

function City:riverPath2(r)
  local state = r.meander
  local function rng(lo, hi)
    state = (state * 16807) % 2147483647
    return lo + (state - 1) / 2147483646 * (hi - lo)
  end
  -- Wide at the mouth, a flared estuary, and narrowing all the way upstream.
  local function mainWidth(s)
    return 95 + 165 * math.exp(-s / 11000) + 150 * math.exp(-s / 420)
  end
  local home = (City.MAP.start - 1) % City.MAP.cols + 1
  local homeRight = home * City.MAP.w
  local homeBottom = (math.floor((City.MAP.start - 1) / City.MAP.cols) + 1) * City.MAP.h
  local path
  -- Keep the home ground dry: a course that swings back over it is thrown away
  -- and the next one tried, all from the same seed stream.
  for _ = 1, 12 do
    path = sampleCourse({ x = r.x0, y = r.y0 }, r.angle * 0.45, City.riverLength, mainWidth, rng, { ease = 1600, mouth = true })
    local clear = true
    for i = 1, path.n do
      if path.y[i] > homeBottom + 400 then break end
      if path.x[i] - path.hw[i] < homeRight + 80 then clear = false; break end
    end
    if clear then break end
  end
  path.branches = {}
  local joins = { 2600, 6200, 10400, 15800 }
  for b, sj in ipairs(joins) do
    local j = math.floor(sj / City.riverStep) + 1
    if j < path.n then
      local side = (b % 2 == 1) and 1 or -1
      -- The main channel's heading here, from its bank normal.
      local heading = math.atan2(path.ny[j], -path.nx[j])
      local w0 = path.hw[j] * 2 * rng(0.42, 0.58)
      local length = rng(5000, 9000)
      local stream = sampleCourse({ x = path.x[j], y = path.y[j] }, heading + side * rng(0.5, 0.7), length,
        function(t) return w0 * (0.45 + 0.55 * math.exp(-t / 5000)) * math.max(0, math.min(1, (length - t) / 1400)) end,
        rng, { ease = 600, swing = rng(0.7, 0.95) })
      -- A stream rises from nothing: its last sample is its source.
      stream.hw[stream.n] = 0
      path.branches[#path.branches + 1] = stream
    end
  end
  return path
end


-- The sampled course: centreline, half-width and unit bank normal per sample.
-- Amplitudes and wavelengths are bounded together: the tightest bend keeps a
-- radius wider than the channel, so the inner bank never folds over itself,
-- and the course always makes headway south, so samples stay sorted by y.
function City:riverPath()
  local r = self.river
  if not r or not r.meander then return nil end
  local path = riverPaths[r]
  if path then return path end
  if r.style == 2 then
    path = self:riverPath2(r)
    riverPaths[r] = path
    return path
  end

  local state = r.meander
  local function roll(lo, hi)
    state = (state * 16807) % 2147483647
    return lo + (state - 1) / 2147483646 * (hi - lo)
  end
  local bends = {
    { amp = 240, wave = 5200 * roll(0.92, 1.1), phase = roll(0, 2 * math.pi) },
    { amp = 35, wave = 1900 * roll(0.92, 1.1), phase = roll(0, 2 * math.pi) },
  }
  local swellWave, swellPhase = 5200 * roll(0.9, 1.1), roll(0, 2 * math.pi)
  local ux, uy = math.sin(r.angle), math.cos(r.angle)
  local function centre(s)
    local off = 0
    for _, b in ipairs(bends) do
      off = off + b.amp * math.sin(2 * math.pi * s / b.wave + b.phase)
    end
    -- The estuary leaves the coast on its heading and eases into its bends
    -- slowly, because that is where the channel is widest.
    local k = math.min(1, s / 900)
    off = off * k * k * (3 - 2 * k) * (0.75 + 0.25 * math.sin(2 * math.pi * s / swellWave + swellPhase))
    return r.x0 + ux * (s-500*(1-math.exp(-s/500))) + uy * off, r.y0 + uy * s
  end

  path = { n = 0, x = {}, y = {}, hw = {}, nx = {}, ny = {}, maxHalf = 0 }
  local steps = math.floor(City.riverLength / City.riverStep)
  for i = 0, steps do
    local s = i * City.riverStep
    local x, y = centre(s)
    local ax, ay = centre(s + 1)
    local tx, ty = ax - x, ay - y
    local len = math.sqrt(tx * tx + ty * ty)
    local hw = r.width / 2 * (0.85 + 0.55 * math.exp(-s / 300))
    local j = i + 1
    path.x[j], path.y[j], path.hw[j] = x, y, hw
    path.nx[j], path.ny[j] = -ty / len, tx / len
    if i==0 then path.nx[j],path.ny[j]=-1,0 end
    path.maxHalf = math.max(path.maxHalf, hw)
  end
  path.n = steps + 1
  path.branches={}
  for branch=1,4 do
    local join=math.floor((branch==1 and 1000 or branch==2 and 2200 or branch*1900)/City.riverStep)+1
    local side=branch%2==1 and 1 or -1
    local length=branch==1 and 5200 or 7200
    local stream={n=0,x={},y={},hw={},nx={},ny={},maxHalf=0}
    local function point(t)
      local spread=t*t/(t+700)
      local bend=95*math.sin(t/1100)*math.min(1,t/1200)
      return path.x[join]+side*(spread*0.60+bend),path.y[join]+t
    end
    for i=0,math.floor(length/City.riverStep) do
      local t=i*City.riverStep
      local x,y=point(t)
      local xx,yy=point(t+1)
      local dx,dy=xx-x,yy-y
      local len=math.sqrt(dx*dx+dy*dy)
      local j=i+1
      local half=path.hw[join]*0.72*math.min(1,(length-t)/700)
      stream.x[j],stream.y[j],stream.hw[j]=x,y,half
      stream.nx[j],stream.ny[j]=-dy/len,dx/len
      stream.maxHalf=math.max(stream.maxHalf,half); stream.n=j
    end
    path.branches[#path.branches+1]=stream
  end
  riverPaths[r] = path
  return path
end

local function firstSampleFrom(p, y)
  local lo, hi = 1, p.n
  while lo < hi do
    local mid = math.floor((lo + hi) / 2)
    if p.y[mid] < y then lo = mid + 1 else hi = mid end
  end
  return lo
end

-- The samples whose centreline lies between two heights, widened by one on each
-- side so the segments crossing either height are included.
function City:riverSpan(y0, y1, path)
  local p = path or self:riverPath()
  if not p then return nil end
  return math.max(1, firstSampleFrom(p, y0) - 1), math.min(p.n, firstSampleFrom(p, y1) + 1)
end

-- How far a point stands outside the bank (negative inside the channel) and the
-- half-width there, or nil at sea or where no reach of the river comes close.
function City:riverEdge(x, y)
  return self:riverEdgeOn(self:riverPath(), x, y)
end

function City:riverEdgeOn(p, x, y)
  if not p or y < 0 then return nil end
  local best,bestHw
  local paths={p}
  for _,branch in ipairs(p.branches or {}) do paths[#paths+1]=branch end
  for _,p in ipairs(paths) do
  local window = p.maxHalf + City.riverWellReach
  local first, last = self:riverSpan(y - window, y + window,p)
  for i = first, last - 1 do
    local ax, ay = p.x[i], p.y[i]
    local dx, dy = p.x[i + 1] - ax, p.y[i + 1] - ay
    local t = math.max(0, math.min(1, ((x - ax) * dx + (y - ay) * dy) / (dx * dx + dy * dy)))
    local hw = p.hw[i] + (p.hw[i + 1] - p.hw[i]) * t
    local edge = math.sqrt((x - ax - dx * t) ^ 2 + (y - ay - dy * t) ^ 2) - hw
    if not best or edge < best then best, bestHw = edge, hw end
  end
  end
  return best, bestHw
end

-- A river has a name, and it is the seed's: the same company always runs
-- along the same one.
City.RIVER_NAMES = { "THE WEY", "THE AVON", "THE OUSE", "THE LUNE", "THE TAVY", "THE MERE",
  "THE COLNE", "THE DART", "THE WEAR", "THE TEME" }
function City:riverName()
  local r = self.river
  if not r or not r.meander then return "THE RIVER" end
  return City.RIVER_NAMES[(r.meander % #City.RIVER_NAMES) + 1]
end

function City:riverAt(x, y)
  local edge = self:riverEdge(x, y)
  return edge ~= nil and edge <= 0
end

function City:nearRiver(x, y)
  local edge = self:riverEdge(x, y)
  return edge ~= nil and edge <= City.riverWellReach
end

-- Sampled rather than solved as a segment-against-a-band intersection: a main
-- is short enough that walking its length in two dozen steps never misses a
-- crossing worth charging for.
function City:segRiver(ax, ay, bx, by)
  for i = 0, 24 do
    local t = i / 24
    if self:riverAt(ax + (bx - ax) * t, ay + (by - ay) * t) then return true end
  end
  return false
end

function City:buyPermit(kind)
  local spec = City.PERMITS[kind]
  if not spec then return nil, "unknown permit" end
  if self.permits[kind] then return nil, "already held" end
  if spec.cost > self.money then return nil, "not enough cash" end
  self:spend(spec.cost)
  self.permits[kind] = true
  self:note("%s granted: %s is now workable ground", spec.name,
    string.lower(City.OBSTACLES[kind].name))
  self:refresh()
  return true
end

function City:note(fmt, ...)
  table.insert(self.log, 1, { text = string.format(fmt, ...), day = self.day })
  for i = #self.log, 40, -1 do self.log[i] = nil end
end

--------------------------------------------------------------------------------
-- Ground
--------------------------------------------------------------------------------

-- Ground features for one cell.
--
-- Nothing in here may look at the rest of the world. Not at the structures the
-- company has built, because a cell surveyed on day 80 would then generate
-- differently from the same cell surveyed on day 3, and not at obstacles in
-- other cells, because that would make a cell depend on which of its neighbours
-- happened to be surveyed first. Everything an obstacle is checked against is
-- placed by this same call, and everything placed stays inside the cell.
City.TERRAIN = require("data.terrain")

function City:scatterObstacles(n, district)
  -- The river is not one of these any more: it is one band running the length
  -- of the map, laid out once in layOutRiver rather than scattered per cell.
  local kinds = { "bedrock", "park" }
  local b = district or self.bounds
  local home = district and district.id == City.MAP.start
  local placed = {}
  local cfg=City.TERRAIN
  local homeCol=(City.MAP.start-1)%City.MAP.cols+1
  local homeRow=math.floor((City.MAP.start-1)/City.MAP.cols)+1
  local distance=district and math.max(math.abs(district.col-homeCol),math.abs(district.row-homeRow)) or 0
  local varied=distance>=2
  local massive=n>0 and distance>=cfg.massiveDistance and self:random()<cfg.massiveChance
  for slot = 1, n do
    local size
    if varied then
      local roll=self:random()
      size=roll<0.45 and cfg.small or roll<0.82 and cfg.medium or cfg.large
    end
    -- Keep the chosen size for all placement attempts: resampling on failure
    -- would silently bias crowded and river-side regions back to tiny features.
    local giant=massive and slot==1
    local chosen=varied and self:rand((giant and cfg.massive or size).min,(giant and cfg.massive or size).max)
    for _ = 1, 40 do
      local r = chosen or self:rand(70, 140)
      local margin=giant and cfg.border or r+cfg.border
      local x = self:rand(b.x + margin, b.x + b.w - margin)
      local y = self:rand(b.y + margin, b.y + b.h - margin)
      local clear = true
      if giant then
        local nearX=math.max(0,math.min(City.MAP.w*3,x))
        local nearY=math.max(0,math.min(City.MAP.h*3,y))
        if (x-nearX)^2+(y-nearY)^2<(r+30)^2 then clear=false end
      end
      -- The home district keeps a wide clearing so the opening is never a maze.
      if home and (x - (b.x + b.w / 2)) ^ 2 + (y - (b.y + b.h / 2)) ^ 2 < (r + 340) ^ 2 then
        clear = false
      end
      -- The river is the seed's alone, so keeping ground off it cannot make a
      -- cell depend on anything the player did.
      local edge = self:riverEdge(x, y)
      if edge and edge < (giant and 100 or r+30) then clear = false end
      for _, o in ipairs(placed) do
        if (o.x - x) ^ 2 + (o.y - y) ^ 2 < (o.r + r + 40) ^ 2 then clear = false; break end
      end
      if clear then
        local o = { x = x, y = y, r = r, kind = kinds[self:random(#kinds)], massive=giant or nil }
        placed[#placed + 1] = o
        self.obstacles[#self.obstacles + 1] = o
        break
      end
    end
  end
end

-- Deposits are the map's answer to where water and oil come from. Nothing the
-- city drinks or burns can be pumped out of open ground: the survey marks where
-- it is, and a well or a rig on the mark is the only way to it. Everything else
-- the city uses arrives at a haven, so a district with no deposit is a district
-- that has to be supplied from the edge of the map.
--
-- Water is common and lies almost everywhere; oil is where the geology put it,
-- which is what the industrial districts are for. The best of both sit under
-- bedrock, out of reach until somebody buys a blasting licence.
function City:scatterDeposits(district, spec)
  local b = district or self.bounds
  local ring = district and district.ring or 0
  local placed = {}
  local plan = {
    { commodity = "water", count = spec.water or (2 + ((spec.rough or 2) >= 3 and 1 or 0)) },
    { commodity = "oil",   count = spec.oil or spec.seams or 0 },
  }
  for _, want in ipairs(plan) do
    for _ = 1, want.count do
      for _ = 1, 60 do
        local x = self:rand(b.x + 90, b.x + b.w - 90)
        local y = self:rand(b.y + 90, b.y + b.h - 90)
        local far = true
        for _, s in ipairs(placed) do
          if (s.x - x) ^ 2 + (s.y - y) ^ 2 < 260 ^ 2 then far = false; break end
        end
        if far then
          local buried
          for _,o in ipairs(self.obstacles) do
            if self:districtAt(o.x,o.y)==district and Shape.contains(o,x,y) then buried=o; break end
          end
          if not buried and self:riverAt(x,y) then buried={kind="river",r=60} end
          local dep = {
            x = x, y = y, commodity = want.commodity, taken = false,
            yield = buried and 1.9 or 1.5, discount = buried and 0.45 or 0.62,
            -- What the ground can give in a day, however deep it is worked.
            cap = City.depositCap(want.commodity, ring, buried),
          }
          placed[#placed + 1] = dep
          self.deposits[#self.deposits + 1] = dep
          break
        end
      end
    end
  end
end

City.seamRange = require("data.production").seamRange

function City:seamAt(x, y)
  for _, s in ipairs(self.deposits or {}) do
    if not s.taken and (s.x - x) ^ 2 + (s.y - y) ^ 2 <= City.seamRange ^ 2 then return s end
  end
  return nil
end

-- Woods and ranges are lobed blobs, not circles: the outline in
-- terrain_shape.lua is the one the map draws, so the ground that charges is
-- exactly the ground that looks like it.
function City:obstacleAt(x, y)
  for _, o in ipairs(self.obstacles) do
    if Shape.contains(o, x, y) then return o end
  end
  -- The river reads as an obstacle to every caller that asks "what is standing
  -- here", so the park/river/bedrock permit machinery does not need to know it
  -- moved out of the scattered list and into a band of its own. `r` stands in
  -- for a radius so anything that scales off one (a deposit's yield bonus) does
  -- not have to know the difference either.
  local edge, hw = self:riverEdge(x, y)
  if edge and edge <= 0 then return { kind = "river", river = true, r = hw } end
  return nil
end

-- What one square of ground charges to be crossed, given the permits held.
function City:groundCross(kind, obstacle)
  if self.permits and self.permits[kind] then return City.PERMITS[kind].cross end
  if obstacle and obstacle.massive then return nil end
  return City.OBSTACLES[kind].cross
end

-- Returns a cost multiplier, or nil if the route is impossible.
function City:crossingCost(ax, ay, bx, by)
  local mult = 1
  for _, o in ipairs(self.obstacles) do
    if Shape.crosses(o, ax, ay, bx, by) then
      local cross = self:groundCross(o.kind, o)
      if not cross then return nil, o end
      mult = math.max(mult, cross)
    end
  end
  if self:segRiver(ax, ay, bx, by) then
    local cross = self:groundCross("river")
    if not cross then return nil, { kind = "river" } end
    mult = math.max(mult, cross)
  end
  return mult
end

function City:placementError(x, y)
  local d = self:districtAt(x, y)
  if not d then return y < 0 and "that is the sea" or "unsurveyed ground" end
  if not d.owned then return "you do not own " .. d.name end
  local o = self:obstacleAt(x, y)
  if o and not (self.permits and self.permits[o.kind]) then
    return "cannot build on " .. string.lower(City.OBSTACLES[o.kind].name)
  end
  for _, n in ipairs(self.g:aliveNodes()) do
    if (n.x - x) ^ 2 + (n.y - y) ^ 2 < City.rules.minSpacing ^ 2 then
      return "too close to another structure"
    end
  end
  return nil
end

function City:rangeBetween(a, b, rail, commodity, size)
  local ka, kb = self.g.nodes[a].kind, self.g.nodes[b].kind
  local mode = City.modeOf(rail)
  if mode then return City.MODES[mode].range end
  if rail then return City.rail.range end
  local reach = City.reachFor(size)
  if ka == "pump" or kb == "pump" then return City.rules.pumpRange * reach end
  return City.rules.linkRange * reach
end

-- `true` still means rail, because that is what the toggle used to be.
function City.modeOf(mode)
  if mode == true then return "rail" end
  return (type(mode) == "string" and City.MODES[mode]) and mode or nil
end

-- A bulk line is priced as infrastructure: two terminals, the run itself, and
-- one charge per wagon or hold fitted to it.
function City:railQuote(a, b, wagons, mode)
  mode = City.modeOf(mode) or "rail"
  local spec = City.MODES[mode]
  wagons = math.max(1, wagons or 1)
  local metres = self:nodeDistance(a, b)
  local na, nb = self.g.nodes[a], self.g.nodes[b]
  -- Ships and aircraft do not care what the ground is doing.
  local mult = (spec.needs == "land") and (self:crossingCost(na.x, na.y, nb.x, nb.y) or 1) or 1
  local q = {
    metres = metres, ground = mult, capacity = wagons, rail = true, mode = mode,
    tiein = math.ceil(spec.tiein * 2),
    trench = math.ceil(metres * spec.perM * mult),
    bore = math.ceil(wagons * spec.perWagon),
  }
  q.total = q.tiein + q.trench + q.bore
  return q
end

function City:bulkQuote(a, b, wagons, mode) return self:railQuote(a, b, wagons, mode) end

-- Only the trades the company sells by the day are licensed. Feedstock and
-- materials are things you buy, make and move: nobody licenses a lorry load of
-- sand.
function City:licensed(commodity)
  local spec = Graph.COMMODITIES[commodity]
  if not spec then return false end
  if spec.role ~= "utility" then return true end
  return self.licences[commodity] and true or false
end

function City:pipeError(a, b, commodity, rail, size)
  if not self:licensed(commodity) then return "no licence for that" end
  local mode = City.modeOf(rail)
  if rail and not mode then return "no such mode" end
  if mode then
    local why = self:bulkError(a, b, mode)
    if why then return why end
  else
    -- Freight is handled at a freight terminal. A main running straight out of
    -- a haven would be a pipeline to a port that has no pipeline, and it would
    -- dodge the haulage bill that makes distance cost something.
    if self:isBulkNode(self.g.nodes[a]) and self.g.nodes[a].kind == "terminal"
       or self:isBulkNode(self.g.nodes[b]) and self.g.nodes[b].kind == "terminal" then
      return "a haven ships by bulk line only"
    end
  end
  local ok, why = self.g:canLink(a, b)
  -- Two structures may carry one pipe of each commodity between them.
  if not ok and why ~= "link already exists" then return why end
  if self:pipeBetween(a, b, commodity) then return "that pipe already exists" end
  if self.g:freePorts(a) < 1 then return "no free ports there" end
  if self.g:freePorts(b) < 1 then return "no free ports there" end

  local na, nb = self.g.nodes[a], self.g.nodes[b]
  local d = math.sqrt((na.x - nb.x) ^ 2 + (na.y - nb.y) ^ 2)
  if d > self:rangeBetween(a, b, rail, commodity, size) then
    return mode and ("too far even for " .. string.lower(City.MODES[mode].name))
      or "too far: use a pump, or lay a bigger main"
  end
  local mult, blocker = self:crossingCost(na.x, na.y, nb.x, nb.y)
  if not mult then return "cannot cross " .. string.lower(City.OBSTACLES[blocker.kind].name) end
  if not mode and not self:sizeRange(a, b) then
    return "needs a structure between them to change pipe size"
  end
  return nil
end

function City:pipeBetween(a, b, commodity)
  for _, ei in ipairs(self.g.adj[a] or {}) do
    local e = self.g.edges[ei]
    if e.alive and e.commodity == commodity
       and ((e.a == a and e.b == b) or (e.a == b and e.b == a)) then return ei end
  end
  return nil
end

--------------------------------------------------------------------------------
-- Prices
--------------------------------------------------------------------------------

function City:nodeCost(kind) return City.price[kind] or 0 end

-- What it costs to break into the network at a given structure. A wellhead is
-- the awkward end of the job; a manifold is a set of ports waiting for you.
City.TIEIN = require("data.pipes").TIEIN

function City:tieinCost(id, commodity)
  local n = self.g.nodes[id]
  local trade = City.trade[commodity] or City.trade.water
  return trade.tiein * (City.TIEIN[n and n.kind] or 1.0)
end

function City:nodeDistance(a, b)
  local na, nb = self.g.nodes[a], self.g.nodes[b]
  return math.sqrt((na.x - nb.x) ^ 2 + (na.y - nb.y) ^ 2)
end

function City:pipeLength(e)
  return self:nodeDistance(e.a, e.b)
end

-- The itemised quote. The UI shows this line by line, because a price the
-- player cannot decompose is a price they cannot plan around.
-- A quote for one main: two tie-ins, a trench, and what the lining adds to
-- both. `size` is a size key and `grade` is a lining level.
function City:pipeQuote(a, b, commodity, size, rail, grade)
  if rail then return self:railQuote(a, b, size) end
  local spec = City.asSize(size)
  local lining = City.GRADES[grade or 1] or City.GRADES[1]
  local trade = City.trade[commodity] or City.trade.water
  local na, nb = self.g.nodes[a], self.g.nodes[b]
  local metres = self:nodeDistance(a, b)
  local mult = self:crossingCost(na.x, na.y, nb.x, nb.y) or 1
  local tiein = (self:tieinCost(a, commodity) + self:tieinCost(b, commodity)) * spec.tiein
  local trench = metres * trade.trench * mult * spec.trench
  local bore = (tiein + trench) * (lining.cost - 1)
  local q = {
    metres = metres, ground = mult, commodity = commodity,
    size = spec.key, capacity = spec.cap, grade = grade or 1,
    tiein = math.ceil(tiein), trench = math.ceil(trench), bore = math.ceil(bore),
  }
  q.total = q.tiein + q.trench + q.bore
  return q
end


function City:pipeCost(a, b, commodity, size, rail, grade)
  return self:pipeQuote(a, b, commodity, size, rail, grade).total
end

-- One more unit through an existing trench: fittings at both ends plus the
-- wider bore over its whole length. Widening a long oil trunk is a real
-- decision; widening a stub is loose change.
-- What it costs to put a bigger main where this one is. Nothing widens, so
-- this is the price of the replacement, less what the old pipe is worth as
-- scrap.
function City:boreCost(e, _)
  if e.bulk then
    return math.ceil(City.MODES[e.bulk].perWagon * (1 + (e.wagonCount or 1) * 0.1))
  end
  local bigger = self:biggerSize(e)
  if not bigger then return nil end
  local q = self:replaceQuote(e.id, bigger, e.grade)
  return q and q.net or nil
end

function City:gradeOf(e) return City.GRADES[e.grade or 1] or City.GRADES[1] end

-- A burst main is charged by what it is and how far it runs, then discounted by
-- what it is lined with. This is where lining pays itself back.
function City:repairCost(e)
  local trade = City.trade[e.commodity] or City.trade.water
  local lost = (e.capMax or e.cap) - e.cap
  local raw = trade.repairBase
    + trade.repairPerLost * math.max(1, lost)
    + self:pipeLength(e) * trade.repairPerM
  return math.ceil(raw * self:gradeOf(e).repair)
end

-- Daily running cost of one pipe: a long pressurised oil main is not the same
-- liability as a garden stub, and the ledger should say so.
function City:pipeUpkeep(e)
  if e.rail then return City.rail.upkeep + self:pipeLength(e) * City.rail.upkeepPerM end
  local trade = City.trade[e.commodity] or City.trade.water
  return trade.upkeep + self:pipeLength(e) * trade.upkeepPerM
end

function City:sourceCost(commodity, x, y, plant)
  if commodity == "power" then return self:plantCost(plant or "nuclear") end
  local trade = City.trade[commodity] or City.trade.water
  -- An intake is counted, and charged, on a ladder of its own. A company that
  -- has one and wants a second is asking for a second heart, and the price
  -- says so. Wells carry on up their own gentler ladder beside it.
  if x and commodity == "water" and trade.intakeMult and self:intakeCap(x, y) then
    local built = self.intakesBought or 0
    return math.ceil(trade.sourceBase * trade.intakeMult * (trade.intakeGrowth ^ built))
  end
  local n = (commodity == "water") and self.sourcesBought or (self.premiumBought and self.premiumBought[commodity]) or 0
  local base = math.ceil(trade.sourceBase * (trade.sourceGrowth ^ n))
  if x then
    local seam = self:seamAt(x, y)
    if seam and seam.commodity == commodity then return math.ceil(base * seam.discount), seam end
  end
  return base
end

-- Upgrading a well is the hub's reason to exist: it needs no new route, no new
-- tie-in and no new ground, so it is the cheap way to add supply until the
-- levels get steep -- at which point sinking a new well is cheaper again.
--------------------------------------------------------------------------------
-- Making things out of other things
--
-- A works is a customer and a well at once: it draws its inputs off the network
-- and puts its output back on. Nine of them turn what the ground gives and what
-- the ships land into what the city actually buys, and every one of them needs
-- electricity, which is what makes a power station the spine of everything
-- rather than just another trade.
--
-- One output each. Two would double the interface and buy nothing the player
-- would thank anyone for.
--------------------------------------------------------------------------------
City.RECIPES = require("data.production").RECIPES
for key,spec in pairs(require("data.infrastructure").farmRecipes) do City.RECIPES[key]=spec end

-- Stable order for every list of works in the interface.
City.RECIPE_ORDER = {}
for key in pairs(City.RECIPES) do City.RECIPE_ORDER[#City.RECIPE_ORDER + 1] = key end
table.sort(City.RECIPE_ORDER, function(a, b)
  return City.RECIPES[a].name < City.RECIPES[b].name
end)

City.MADE_BY = {}
for key, recipe in pairs(City.RECIPES) do City.MADE_BY[recipe.makes] = key end
City.MADE_BY.food="foodworks"
City.MADE_BY.wheat="crops"

-- The order the networks have to be solved in.
--
-- Recipes make a graph: an edge from every input to the output. Solve the
-- commodities in topological order and one pass is enough, because nothing
-- downstream can feed anything upstream. The rule that keeps it acyclic is that
-- a well, a mine and a quarry never need power, so raw ground is always at the
-- bottom and the first thing solved.
local function solveOrder()
  local level = {}
  local function levelOf(key, seen)
    if level[key] then return level[key] end
    seen = seen or {}
    if seen[key] then
      error("recipes have a cycle at " .. key .. ": a commodity cannot need itself")
    end
    seen[key] = true
    local best = 0
    for _,recipe in pairs(City.RECIPES) do
    if recipe.makes==key or recipe.coproduct==key then
      for input in pairs(recipe.inputs) do
        best = math.max(best, levelOf(input, seen) + 1)
      end
    end
    end
    seen[key] = nil
    level[key] = best
    return best
  end
  local order = {}
  for _, key in ipairs(Graph.ALL) do order[#order + 1] = key end
  table.sort(order, function(a, b)
    local la, lb = levelOf(a), levelOf(b)
    if la ~= lb then return la < lb end
    return Graph.COMMODITIES[a].order < Graph.COMMODITIES[b].order
  end)
  return order, level
end

City.SOLVE_ORDER, City.SOLVE_LEVEL = solveOrder()

-- What a works wants per day at its rated output, and what it could make from
-- what actually turned up.
-- What a works can put out today: whichever input ran shortest decides, and
-- nothing exceeds the rated output. A works with no power makes nothing at all,
-- which is the whole reason a power station matters.
-- What a works can put out today: whichever input ran shortest decides, and
-- nothing exceeds the rated output. There is no partial recipe. A brewery with
-- no malt makes no beer at all, which is what makes the chain behind it worth
-- building rather than an optimisation to get round to.
function City:worksOutput(n)
  local recipe = City.RECIPES[n.recipe or ""]
  if not recipe then return 0 end
  local got = (self.detail.works or {})[n.id] or {}
  local best = recipe.rate
  for key, per in pairs(recipe.inputs) do
    best = math.min(best, math.floor((got[key] or 0) / per + 1e-9))
  end
  return math.max(0, best)
end

function City:worksWants(n)
  local recipe = City.RECIPES[n.recipe or ""]
  if not recipe then return {} end
  local wants = {}
  for key, per in pairs(recipe.inputs) do wants[key] = per * recipe.rate end
  return wants
end

--------------------------------------------------------------------------------
-- Taking things out of the ground
--
-- Every raw commodity comes from somewhere the map actually says it is, and
-- each one wants different ground. Water and oil are where the survey marked
-- them. Ore is the same, and only the frontier has much of it. Wheat grows
-- where the ground is farmland. Timber comes off parkland and rock out of
-- bedrock, which is what turns two obstacles the player has been paying to
-- avoid into two things worth owning, and makes those permits an investment
-- rather than a toll. Sand is dredged on the coast and on the islands.
--------------------------------------------------------------------------------
City.EXTRACTORS = require("data.production").EXTRACTORS

City.EXTRACTOR_OF = {}
for key, spec in pairs(City.EXTRACTORS) do City.EXTRACTOR_OF[spec.out] = key end

-- Where this commodity may be taken out of the ground, and why not here.
function City:extractorError(commodity, x, y)
  local key = City.EXTRACTOR_OF[commodity]
  local spec = key and City.EXTRACTORS[key]
  if not spec then return "that is not taken out of the ground" end
  if spec.on == "deposit" then
    -- Running water is its own deposit, and the best one on the map. An intake
    -- sinks no shaft: it stands on the bank, or on the coast, and lifts what is
    -- already going past. Everything else still needs a seam under it.
    if commodity == "water" and self:intakeCap(x, y) then return nil end
    local _, seam = self:sourceCost(commodity, x, y)
    if not seam then return "no " .. commodity .. " here: sink on a marked deposit" end
  elseif spec.on == "archetype" then
    local d = self:districtAt(x, y)
    if not (d and d.spec and d.spec.key == spec.archetype) then
      return "a farm belongs on farmland"
    end
  elseif spec.on == "obstacle" then
    local o = self:obstacleAt(x, y)
    if not (o and o.kind == spec.obstacle) then
      return "a " .. string.lower(spec.name) .. " belongs on "
        .. string.lower(City.OBSTACLES[spec.obstacle].name)
    end
    if not (self.permits and self.permits[spec.obstacle]) then
      return "that ground needs its permit first"
    end
  elseif spec.on == "coast" then
    local d = self:districtAt(x, y)
    if not (self:onCoast(x, y) or (d and d.island)) then
      return "sand is dredged on the coast"
    end
  end
  return nil
end

-- Electricity is generated, never landed, and there are two ways to generate
-- it. A reactor is an enormous cheque and a standing crew, and it turns
-- imported uranium into more power than anything else on the map. A wind park
-- is cheap, small, burns nothing at all, and can only stand where there is
-- nobody to object and nothing to shelter it: out in the sea.
City.PLANTS = require("data.production").PLANTS
City.PLANT_ORDER = { "nuclear", "wind" }

function City:plantCost(plant)
  local spec = City.PLANTS[plant] or City.PLANTS.nuclear
  local built = (self.plantsBuilt or {})[plant] or 0
  return math.ceil(spec.base * (spec.growth ^ built))
end

City.sourceMaxLevel = require("data.production").sourceMaxLevel
-- What a well, a rig or a plant answers to: enough to feed more than one
-- route, never enough to fan out like a hub.
City.sourcePorts = require("data.production").sourcePorts

-- A station grows by taking another unit, a well or an intake by going down a
-- level. Both are the same shape of ladder and both are deliberately gentler
-- than the ladder for building a second one somewhere else.
function City:sourceUpgradeCost(n)
  local level = n.level or 1
  if n.plant then
    local spec = City.PLANTS[n.plant] or {}
    if not spec.unitBase then return nil end
    return math.ceil(spec.unitBase * (spec.unitGrowth ^ (level - 1)))
  end
  local trade = City.trade[n.commodity] or City.trade.water
  return math.ceil(trade.upgradeBase * (trade.upgradeGrowth ^ (level - 1)))
end

-- How much one more level adds, and what to call the thing being added.
function City:upgradeStep(n)
  if n.plant then
    local spec = City.PLANTS[n.plant] or {}
    return spec.unitStep or 0, spec.unitName or "unit"
  end
  if n.intake then return City.INTAKE.step, "stage" end
  local trade = City.trade[n.commodity] or City.trade.water
  return trade.upgradeStep, "level"
end

function City:maxLevel(n)
  if n.plant then return (City.PLANTS[n.plant] or {}).maxUnits or 1 end
  return self:maxDepth(n)
end

function City:upgradeSource(id)
  local n = self.g.nodes[id]
  if not (n and n.alive and n.kind == "source") then return nil, "no such source" end
  local level = n.level or 1
  local cost = self:sourceUpgradeCost(n)
  if not cost then return nil, "this station is built, not extended" end
  if level >= self:maxLevel(n) then
    return nil, n.plant and "the site is full" or "this source is at full yield"
  end
  if n.cap and (n.output or 0) >= n.cap then
    return nil, (n.intake == "river" and "the channel gives no more: "
      or n.intake and "the works cannot lift more: "
      or "this ground gives no more: ") .. n.cap .. " a day is its limit"
  end
  if cost > self.money then return nil, "not enough cash" end
  -- Another unit on a station needs the same parts the first one did, so a
  -- second solar array wants its own panels landed and in the yards.
  local bill = n.plant and self:materialsFor("source", n.plant) or nil
  local short = bill and self:materialError(bill)
  if short then return nil, short end
  local step = self:upgradeStep(n)
  local trade = City.trade[n.commodity] or City.trade.water
  self:spend(cost)
  if bill then self:spendMaterials(bill) end
  n.level = level + 1
  n.output = (n.output or trade.sourceOutput) + step
  if n.cap then n.output = math.min(n.output, n.cap) end
  n.paid = (n.paid or 0) + cost
  if n.plant then
    local spec = City.PLANTS[n.plant] or {}
    n.upkeep = (n.upkeep or 0) + (spec.upkeep or 0)
    self:note("%s takes a %s: %d units a day from one site",
      spec.name or "STATION", spec.unitName or "unit", n.output)
  else
    self:note("%s %s to %s %d: output now %d",
      string.upper(n.commodity), n.intake and "works extended" or "well deepened",
      n.intake and "stage" or "level", n.level, n.output)
  end
  self:refresh()
  return n
end

-- What the next lining level costs to acquire. It is bought once and then paid
-- for again in every metre laid with it.
function City:liningPrice()
  local nextGrade = City.GRADES[(self.lining or 1) + 1]
  return nextGrade and nextGrade.price or nil
end

function City:qualityCost() return self:liningPrice() or 0 end

function City:spend(amount)
  if amount > self.money then return false end
  self.money = self.money - amount
  return true
end

--------------------------------------------------------------------------------
-- Building
--------------------------------------------------------------------------------

City.BUILDABLE = { junction = true, manifold = true, pump = true, tower = true,
                   gate = true, depot = true, terminal = true,
                   works = true, dc = true, stop = true, station = true, resort = true }

-- Hubs: see src/distribution.lua. A fitting levelled to the top of its ladder
-- runs its own neighbourhood; there is no separate hub building any more.

-- The outside world.
--
-- North of row one there is sea, and the sea does not end. It is the one
-- direction the company cannot buy its way into, which makes the coastline the
-- only fixed edge on an otherwise endless map, and the only place a harbour can
-- stand. Everything else the city trades through is a building the company
-- sites itself: a trunk road interchange or an air freight apron, anywhere on
-- ground it holds.
--
-- What comes through any of them is unlimited, because a shipping line does not
-- run out of ships. What differs is the freight. Sea is the cheap way in and
-- the long way round, road is dearer and goes where you put it, air is dearest
-- of all and goes anywhere at once. That difference is the whole reason to hold
-- more than one.
City.HAVENS = require("data.freight").HAVENS

City.GATEWAYS = { "port", "highway", "airfield" }

-- How close to the water a harbour has to be.
City.havenReach = require("data.freight").havenReach

-- Where the sea starts. Everything above it is water forever.
function City.coastLine() return 0 end

function City:onCoast(x, y)
  return y >= 0 and y <= City.havenReach
end

-- Each haven after the first of its kind costs more, the way a second berth on
-- the same coast costs more than the first.
function City:havenCost(key)
  local spec = City.HAVENS[key] or City.HAVENS.port
  local held = 0
  for _, n in ipairs(self.g:nodesOfKind("terminal")) do
    if n.haven == key then held = held + 1 end
  end
  return math.ceil(spec.price * (1.6 ^ held))
end

function City:havenOf(key)
  for _, n in ipairs(self.g:nodesOfKind("terminal")) do
    if n.haven == key then return n end
  end
  return nil
end

-- Why a haven of this kind cannot go here.
function City:havenSite(x, y, key)
  key = key or "port"
  local spec = City.HAVENS[key]
  if not spec then return nil, "no such haven" end
  if spec.gate == "coast" and not self:onCoast(x, y) then
    return nil, "a harbour stands on the coast"
  end
  if self:havenCost(key) > self.money then return nil, "not enough cash" end
  return key
end

City.terminalUpkeep = require("data.freight").terminalUpkeep

function City:build(x, y, kind, commodity)
  if not City.BUILDABLE[kind] then return nil, "choose a structure" end
  local err = self:placementError(x, y)
  if err then return nil, err end
  local gateway
  if kind == "terminal" then
    local err2
    gateway, err2 = self:havenSite(x, y, commodity)
    if not gateway then return nil, err2 end
  end
  local recipe = kind == "works" and City.RECIPES[commodity or ""] or nil
  if kind == "works" and not recipe then return nil, "choose what the works makes" end
  local unlock = City.BUILD_UNLOCK[kind] or (recipe and recipe.unlock)
  if unlock and not self:unlocked(unlock) then return nil, "not available yet" end
  if kind == "resort" then
    local why = self:resortSiteError(x, y)
    if why then return nil, why end
  end
  if recipe and not self:licensed(recipe.makes) then
    return nil, "no licence for " .. recipe.makes
  end
  if recipe and recipe.coastal then
    local d = self:districtAt(x, y)
    if not (self:onCoast(x, y) or (d and d.island)) then
      return nil, "a " .. string.lower(recipe.name) .. " stands on the coast"
    end
  end
  local cost = gateway and self:havenCost(gateway)
    or (recipe and recipe.cost)
    or self:nodeCost(kind)
  if cost > self.money then return nil, "not enough cash" end
  local bill = self:materialsFor(kind, kind == "works" and commodity or nil)
  local short = self:materialError(bill)
  if short then return nil, short end
  self:spend(cost)
  self:spendMaterials(bill)
  local n = self.g:addNode(x, y, kind)
  n.paid = cost
  if kind == "works" then
    n.throughput = 999
    n.recipe = commodity
    n.makes = recipe.makes
    n.wants = self:worksWants(n)
    self:note("%s built: %d %s a day when it is fed", recipe.name, recipe.rate, recipe.makes)
  elseif kind == "gate" then
    -- A gate starts wide open; the point of it is that the player narrows it.
    n.throughput = 6
  elseif kind == "depot" then
    n.throughput = 999
    n.commodity = commodity or "water"
    n.stored, n.capacityStore = 0, City.depotCapacity
  elseif kind == "station" then
    n.throughput = 999
    n.price, n.fuelWanted = City.PEOPLE.pumpPrice + 1, City.PEOPLE.stationTank
  elseif kind == "resort" then
    n.throughput = 999
    n.level = 1
  elseif kind == "terminal" then
    -- A haven has no commodity and no output: everything the outside world
    -- sells arrives here, in any quantity, and is paid for by the unit as it
    -- lands. What limits it is the track it leaves by and the price of the
    -- freight, never the berth.
    n.throughput = 999
    n.haven = gateway
    self:note("%s opened: every trade but power lands here, billed per unit",
      City.HAVENS[n.haven].name)
    self.havensBuilt = (self.havensBuilt or 0) + 1
  else
    n.throughput = 999
  end
  self:refresh()
  return n
end

City.depotCapacity = require("data.freight").depotCapacity
City.depotFillRate = require("data.freight").depotFillRate

-- A gate is the only structure whose value is in closing it. Setting it below a
-- branch's demand starves that branch on purpose, which is how scarce supply
-- gets pointed at the customers who actually pay.
function City:setGate(id, value)
  local n = self.g.nodes[id]
  if not (n and n.alive and n.kind == "gate") then return nil, "no such gate" end
  if type(value) ~= "number" or value ~= value then return nil, "invalid setting" end
  value = math.max(0, math.min(100, math.floor(value)))
  n.throughput = value
  self:refresh()
  return n
end

function City:layPipe(a, b, commodity, size, rail, grade)
  local mode = City.modeOf(rail)
  local wagons = mode and math.max(1, math.min(8, math.floor(tonumber(size) or 1))) or nil
  grade = math.max(1, math.min(self.lining or 1, grade or self.lining or 1))
  local err = self:pipeError(a, b, commodity, rail, not rail and size or nil)
  if err then return nil, err end
  if not mode then
    local spec = City.asSize(size)
    if not self:sizeAllowed(spec) then return nil, self:sizeGate(spec) end
    local lo, hi = self:sizeRange(a, b)
    local _, idx = City.sizeOf(spec.key)
    if idx < lo then return nil, City.PIPE_SIZES[lo].name .. " main or bigger, here" end
    if idx > hi then return nil, City.PIPE_SIZES[hi].name .. " main or smaller, here" end
  end
  local cost = self:pipeCost(a, b, commodity, wagons or size, rail, grade)
  if cost > self.money then return nil, "not enough cash" end
  -- A bulk line is built out of steel by the kilometre. Mains are not: a water
  -- main is a trench and a pipe, and the game has always priced it that way.
  local bill = mode and self:materialsFor("bulk", mode) or {}
  local scale = self:nodeDistance(a, b) / 1000
  local short = self:materialError(bill, scale)
  if short then return nil, short end
  self:spend(cost)
  self:spendMaterials(bill, scale)

  local spec = not mode and City.asSize(size) or nil
  local capacity = spec and spec.cap or 1
  local e = self.g:addEdge(a, b, capacity)
  -- canLink refuses a duplicate, so a second commodity needs the raw insert.
  if not e then
    e = { id = #self.g.edges + 1, a = a, b = b, cap = capacity, alive = true }
    self.g.edges[e.id] = e
    table.insert(self.g.adj[a], e.id)
    table.insert(self.g.adj[b], e.id)
  end
  e.commodity = commodity
  e.capMax = capacity
  e.paid = cost
  e.leaking = false
  -- The lining is decided here and never again. Whatever the company could lay
  -- on the day this main went in is what it has for the rest of its life.
  e.grade = grade
  if spec then e.size = spec.key end
  if mode then
    -- A bulk line is bought by the wagon, and the first wagon carries whatever
    -- the player was holding when they drew it.
    local modeSpec = City.MODES[mode]
    e.bulk, e.rail, e.size = mode, true, nil
    e.wagons = { [commodity] = wagons * modeSpec.wagonCap }
    e.wagonCount = wagons
    e.cap = wagons * modeSpec.wagonCap
    e.capMax = e.cap
    e.grade = 1
  end
  self:refresh()
  return e
end

--------------------------------------------------------------------------------
-- Replacing a main
--
-- Nothing widens. A main that is too small comes out of the ground and a bigger
-- one goes in, and the same is true of a main that was laid before the company
-- knew how to line properly. What comes back is scrap value on the old pipe,
-- which is a fraction of what it cost, so laying the right main first time is
-- worth real money and going back to fix an old mistake is a decision.
--------------------------------------------------------------------------------
City.salvage = require("data.economy").salvage

function City:replaceQuote(id, size, grade)
  local e = self.g.edges[id]
  if not (e and e.alive) then return nil end
  if e.bulk then return nil end
  grade = math.max(1, math.min(self.lining or 1, grade or e.grade or 1))
  local q = self:pipeQuote(e.a, e.b, e.commodity, size or e.size or (e.capMax or e.cap), false, grade)
  q.salvage = math.floor((e.paid or 0) * City.salvage)
  q.net = math.max(0, q.total - q.salvage)
  return q
end

function City:replaceError(id, size, grade)
  local e = self.g.edges[id]
  if not (e and e.alive) then return "no such main" end
  if e.bulk then return "a freight line is fitted with wagons, not replaced" end
  local spec = City.asSize(size or e.size)
  grade = math.max(1, math.min(self.lining or 1, grade or e.grade or 1))
  if spec.key == (e.size or "") and grade == (e.grade or 1) then
    return "that is what is already in the ground"
  end
  if not self:sizeAllowed(spec) then return self:sizeGate(spec) end
  local lo, hi = self:sizeRange(e.a, e.b)
  local _, idx = City.sizeOf(spec.key)
  if not lo then return "needs a structure between them to change pipe size" end
  if idx < lo then return City.PIPE_SIZES[lo].name .. " main or bigger, here" end
  if idx > hi then return City.PIPE_SIZES[hi].name .. " main or smaller, here" end
  local q = self:replaceQuote(id, size, grade)
  if q.net > self.money then return "not enough cash" end
  return nil
end

function City:replacePipe(id, size, grade)
  local err = self:replaceError(id, size, grade)
  if err then return nil, err end
  local e = self.g.edges[id]
  local spec = City.asSize(size or e.size)
  grade = math.max(1, math.min(self.lining or 1, grade or e.grade or 1))
  local q = self:replaceQuote(id, spec.key, grade)
  self:spend(q.net)
  e.size, e.grade = spec.key, grade
  e.cap, e.capMax = spec.cap, spec.cap
  e.paid = q.total
  e.leaking, e.burstReported, e.decayTick, e.fullFor = false, nil, nil, 0
  self:note("A %s main was dug out and replaced with %s %s pipe for $%d",
    e.commodity, string.lower(spec.name), string.lower(City.GRADES[grade].name), q.net)
  self:refresh()
  return e
end

-- The widest a main gets without the player deciding it. A hub wires the last
-- mile and the engineers keep it flowing; laying a trunk across the city is a
-- decision, not maintenance. Read off the ladder, which has grown a rung
-- twice, rather than written down as a number that goes stale.
function City.autoWidenCap()
  return City.sizeOf("large").cap
end

-- The next size up, for the departments and for the hub feeds. It answers nil
-- where a wider main could not be laid by hand either: a customer takes a
-- small main and nothing else, so a run of houses chained to each other has
-- no next size, and the honest answer is a junction rather than a bore.
function City:biggerSize(e)
  local _, index = City.sizeOf(e.size or City.sizeFor(e.capMax or e.cap).key)
  local nextSpec = City.PIPE_SIZES[index + 1]
  if not nextSpec or not self:sizeAllowed(nextSpec) then return nil end
  local _, hi = self:sizeRange(e.a, e.b)
  if not hi or index + 1 > hi then return nil end
  return nextSpec.key
end

-- Wagons, holds and aircraft. A bulk line carries as many commodities as it has
-- wagons fitted, which is the whole difference between it and a main: beer, oil
-- and water cannot share a pipe and can share a train.
function City:wagonError(id, commodity)
  local e = self.g.edges[id]
  if not (e and e.alive and e.bulk) then return "not a bulk line" end
  if not Graph.COMMODITIES[commodity] then return "no such commodity" end
  local form = Graph.COMMODITIES[commodity].form
  if form == "energy" then return "electricity travels by cable, not by freight" end
  if form == "data" then return "the internet travels by fibre, not by freight" end
  if not self:licensed(commodity) then return "no licence for that" end
  if (e.wagons or {})[commodity] then return "it already carries that" end
  if e.bulk == "air" then
    -- One aircraft type per route: a tanker cannot carry ore.
    for other in pairs(e.wagons or {}) do
      if Graph.COMMODITIES[other].form ~= Graph.COMMODITIES[commodity].form then
        return "this route flies " .. Graph.COMMODITIES[other].form .. " freight"
      end
    end
  end
  if (e.wagonCount or 1) >= 8 then return "eight wagons is the limit" end
  return nil
end

function City:wagonCost(id)
  local e = self.g.edges[id]
  if not (e and e.bulk) then return nil end
  return math.ceil(City.MODES[e.bulk].perWagon * (1 + (e.wagonCount or 1) * 0.1))
end

function City:addWagon(id, commodity)
  local err = self:wagonError(id, commodity)
  if err then return nil, err end
  local e = self.g.edges[id]
  local cost = self:wagonCost(id)
  if cost > self.money then return nil, "not enough cash" end
  self:spend(cost)
  local spec = City.MODES[e.bulk]
  e.wagons[commodity] = (e.wagons[commodity] or 0) + spec.wagonCap
  e.wagonCount = (e.wagonCount or 1) + 1
  e.cap = e.cap + spec.wagonCap
  e.capMax = e.cap
  e.paid = (e.paid or 0) + cost
  self:note("%s fitted for %s", City.MODES[e.bulk].name, commodity)
  self:refresh()
  return e
end

-- Widening a main is replacing it with the next size up, which is what
-- `boreCost` has always quoted for it.
--
-- It used to charge that whole quote and then add one single unit of
-- capacity, and stop at 24. Both numbers are from the version of this game
-- where capacity was a dial rather than a ladder of five discrete sizes, and
-- they survived every change to the ladder since. A main widened this way now
-- ends up as the size that was paid for, and answers to the same endpoint
-- limits as one laid by hand: a garden stub to a house stays a garden stub.
function City:upgradePipe(id)
  local e = self.g.edges[id]
  if not (e and e.alive) then return nil, "no such pipe" end
  if e.bulk then return nil, "a freight line is fitted with wagons, not widened" end
  local bigger = self:biggerSize(e)
  if not bigger then return nil, "maximum capacity reached" end
  return self:replacePipe(id, bigger, e.grade)
end

-- Every leak the company can afford, cheapest first, in one decision. The
-- point is not to save money -- it saves none -- but to save the twenty clicks
-- that stand between a player and the part of the game they came for.
function City:repairAll()
  local order = {}
  for _, e in ipairs(self.g.edges) do
    if e.alive and (e.leaking or e.cap < (e.capMax or e.cap)) then order[#order + 1] = e end
  end
  table.sort(order, function(a, b) return self:repairCost(a) < self:repairCost(b) end)
  local fixed, spent = 0, 0
  for _, e in ipairs(order) do
    local cost = self:repairCost(e)
    if cost <= self.money then
      self.money = self.money - cost
      e.cap = e.capMax or e.cap
      e.leaking, e.burstReported, e.decayTick = false, nil, nil
      e.calcification=0
      fixed, spent = fixed + 1, spent + cost
    end
  end
  if fixed == 0 then return nil, "nothing to repair" end
  self:note("Repaired %d main%s for $%d", fixed, fixed == 1 and "" or "s", spent)
  self:refresh()
  return { fixed = fixed, spent = spent }
end

-- Total bill to put the whole network back in order, for the button that does it.
function City:repairAllCost()
  local total, count = 0, 0
  for _, e in ipairs(self.g.edges) do
    if e.alive and (e.leaking or e.cap < (e.capMax or e.cap)) then
      total, count = total + self:repairCost(e), count + 1
    end
  end
  return total, count
end

function City:repairPipe(id)
  local e = self.g.edges[id]
  if not (e and e.alive) then return nil, "no such pipe" end
  if not e.leaking and e.cap >= (e.capMax or e.cap) then return nil, "nothing to repair" end
  local cost = self:repairCost(e)
  if cost > self.money then return nil, "not enough cash" end
  self:spend(cost)
  e.cap = e.capMax or e.cap
  e.leaking, e.decayTick = false, nil
  e.calcification=0
  e.burstReported = nil
  self:refresh()
  return cost
end


function City:demolishPipe(id)
  local e = self.g.edges[id]
  if not (e and e.alive) then return nil, "no such pipe" end
  local refund = math.floor((e.paid or self:pipeCost(e.a, e.b, e.commodity, e.capMax)) * 0.4)
  self.g:killEdge(id)
  self.money = self.money + refund
  self:refresh()
  return refund
end

--------------------------------------------------------------------------------
-- Taking things out again
--------------------------------------------------------------------------------

-- Every pipe in the network hangs off a node at each end. That is the whole
-- reason removing one is a real decision: take away the node and every main
-- that was tied into it goes with it, and nothing can be laid to that spot
-- again until something is standing there to tie into.
--
-- So a well is never simply deleted. If mains are tied into it, demolishing it
-- caps the wellhead: the production stops and the money comes back, but a
-- connection chamber is left behind holding every pipe exactly where it was.
-- The chamber is an ordinary structure after that, and removing *it* is the
-- move that actually costs you the network.

-- The cheapest structure that can hold this many pipes. A chamber left behind
-- by a well may be carrying more mains than any structure normally allows; it
-- keeps them, but it will not accept another until one is freed.
function City:chamberFor(degree)
  if degree <= Graph.KINDS.junction.ports then return "junction" end
  return "manifold"
end

-- What a node would take with it. Pulling out a structure does not recover the
-- mains tied into it -- they are cut, not lifted -- so this is a loss and not a
-- refund, and the inspector says so out loud before anything is pressed.
function City:demolitionCost(id)
  local n = self.g.nodes[id]
  if not (n and n.alive) then return nil end
  local pipes, sunk = 0, 0
  for _, ei in ipairs(self.g.adj[id] or {}) do
    local e = self.g.edges[ei]
    if e.alive then
      pipes = pipes + 1
      sunk = sunk + (e.paid or 0)
    end
  end
  return pipes, sunk
end

-- Customers who would stop being supplied if this structure came out. The
-- number that actually matters: pipes can be relaid, a lost account cannot.
function City:dependentsOf(id)
  local n = self.g.nodes[id]
  if not (n and n.alive) or n.kind == "client" then return 0 end
  local rev = self.revision
  local before = {}
  for _, c in ipairs(self:clientList()) do
    before[c.id] = (self.served[c.id] or 0)
  end
  -- Ask the graph, rather than guessing from the shape of the network.
  local kindWas, aliveWas = n.kind, n.alive
  n.alive = false
  self:refresh()
  local hurt = 0
  for _, c in ipairs(self:clientList()) do
    if (self.served[c.id] or 0) < (before[c.id] or 0) then hurt = hurt + 1 end
  end
  n.alive, n.kind = aliveWas, kindWas
  self:refresh()
  -- The probe changed nothing, so it must not look as though it did.
  self.revision = rev
  return hurt
end

-- The company's origin: used to anchor the camera and new enquiries. It starts
-- as the first well, but that well can be capped or removed like any other, so
-- it has to be able to move.
function City:rebaseOrigin()
  local current = self.firstSource
  if current and current.alive and current.kind == "source" then return current end
  local best
  for _, n in ipairs(self.g:nodesOfKind("source")) do
    best = best or n
  end
  if not best then
    -- No wells at all. Anchor on anything the company still owns, and failing
    -- that on the middle of the home district.
    for _, n in ipairs(self.g:aliveNodes()) do best = best or n end
  end
  if not best then
    local home = self.districts and self.districts[City.MAP.start]
    best = { x = home and home.x + home.w / 2 or self.bounds.w / 2,
             y = home and home.y + home.h / 2 or self.bounds.h / 2, id = 0 }
  end
  self.firstSource = best
  return best
end

function City:demolishNode(id)
  local n = self.g.nodes[id]
  if not (n and n.alive) then return nil, "no such structure" end
  if n.kind == "client" then return nil, "cannot demolish that" end
  local degree = self.g:degree(id)

  if n.kind == "source" then
    local refund = math.floor((n.paid or self:sourceCost(n.commodity or "water")) * 0.4)
    if degree == 0 then
      -- Nothing tied into it, so nothing to preserve.
      self.g:killNode(id)
      self:note("%s well closed for $%d", string.upper(n.commodity or "water"), refund)
    else
      -- Cap it. The chamber costs the company its own price out of the refund,
      -- because something has to be built to hold the pipes up.
      local kind = self:chamberFor(degree)
      local chamber = self:nodeCost(kind)
      refund = math.max(0, refund - chamber)
      n.kind = kind
      n.ports = Graph.KINDS[kind].ports
      n.throughput = Graph.KINDS[kind].throughput
      n.paid = chamber
      n.commodity, n.output, n.level, n.seam = nil, nil, nil, nil
      n.capped = true
      self:note("%s well capped for $%d: a %s keeps its %d main%s connected",
        string.upper((n.commodity) or "water"), refund, string.lower(Graph.KINDS[kind].name),
        degree, degree == 1 and "" or "s")
    end
    self.money = self.money + refund
    self:rebaseOrigin()
    self:refresh()
    return refund
  end

  local refund = math.floor((n.paid or self:nodeCost(n.kind)) * 0.4)
  self.g:killNode(id)
  self:cutLinks(id)
  self.money = self.money + refund
  self:rebaseOrigin()
  self:refresh()
  return refund
end

--------------------------------------------------------------------------------
-- Replacing a structure without taking the network down
--------------------------------------------------------------------------------

-- Swapping a junction for a manifold used to mean demolishing it, losing every
-- main tied into it, rebuilding, and laying them all again. That is a lot of
-- clicking and a lot of money to buy three more ports. A structure can now be
-- replaced where it stands: the pipes never come off, and you pay the
-- difference between what is there and what you want.
City.CONVERTIBLE = {
  junction = true, manifold = true, pump = true, tower = true, gate = true, depot = true,
}

function City:convertCost(id, kind)
  local n = self.g.nodes[id]
  if not n then return nil end
  -- The old structure is traded in at the same rate demolition would pay.
  local tradeIn = math.floor((n.paid or self:nodeCost(n.kind)) * 0.4)
  return math.max(0, self:nodeCost(kind) - tradeIn)
end

function City:convertError(id, kind)
  local n = self.g.nodes[id]
  if not (n and n.alive) then return "no such structure" end
  if not City.CONVERTIBLE[n.kind] then
    return n.kind == "source" and "a well must be capped, not replaced"
      or "that cannot be replaced"
  end
  if not City.CONVERTIBLE[kind] then return "cannot build that here" end
  if kind == n.kind then return "it is already that" end
  local degree = self.g:degree(id)
  if degree > Graph.KINDS[kind].ports then
    return string.format("a %s has %d ports and %d mains are tied in",
      string.lower(Graph.KINDS[kind].name), Graph.KINDS[kind].ports, degree)
  end
  if self:convertCost(id, kind) > self.money then return "not enough cash" end
  return nil
end

function City:convertNode(id, kind, commodity)
  local err = self:convertError(id, kind)
  if err then return nil, err end
  local n = self.g.nodes[id]
  local was = Graph.KINDS[n.kind].name
  local cost = self:convertCost(id, kind)
  self:spend(cost)
  n.kind = kind
  n.ports = Graph.KINDS[kind].ports
  n.paid = self:nodeCost(kind)
  n.capped = nil
  -- Kind-specific state has to be set up or cleared, exactly as build() would.
  n.stored, n.capacityStore, n.haven, n.output = nil, nil, nil, nil
  if kind == "gate" then
    n.throughput = 6
  elseif kind == "depot" then
    n.throughput = Graph.KINDS.depot.throughput
    n.commodity = commodity or n.commodity or "water"
    n.stored, n.capacityStore = 0, City.depotCapacity
  else
    n.throughput = Graph.KINDS[kind].throughput
    n.commodity = nil
  end
  self:note("%s %d replaced with a %s for $%d, mains left connected",
    was, id, string.lower(Graph.KINDS[kind].name), cost)
  self:refresh()
  return n
end

--------------------------------------------------------------------------------
-- Company decisions
--------------------------------------------------------------------------------

-- Where a works may stand, and why not.
--
-- Water and oil are not everywhere: they are where the survey found them, and
-- the mine, the well or the rig is what turns a marked deposit into supply. A
-- reactor answers to no deposit, only to ground. And nobody brews: beer comes
-- off a ship like everything else the city does not make for itself.
function City:sourceError(commodity, x, y, plant)
  if not self:licensed(commodity) then return "no licence for that" end
  -- Water is both dug and desalinated: an extractor for a commodity always
  -- wins this check, because a recipe existing besides it does not mean the
  -- ground stopped giving it up.
  local madeBy = commodity ~= "power" and not City.EXTRACTOR_OF[commodity]
    and City.RECIPES[City.MADE_BY[commodity] or ""]
  if madeBy then
    return string.lower(commodity) .. " is made in a " .. string.lower(madeBy.name)
  end
  local err = self:placementError(x, y)
  if err then return err end
  if commodity == "power" then
    local spec = City.PLANTS[plant or "nuclear"]
    if not spec then return "no such plant" end
    local d = self:districtAt(x, y)
    if spec.ground == "island" and not (d and d.island) then
      return "a wind park stands on an island"
    end
    if spec.ground == "land" and d and d.island then
      return "there is no room for a reactor out here"
    end
  elseif City.EXTRACTOR_OF[commodity] then
    local why = self:extractorError(commodity, x, y)
    if why then return why end
  else
    return string.lower(commodity) .. " is not taken out of the ground: land it or make it"
  end
  return nil
end

function City:buySource(commodity, px, py, plant)
  if not self:licensed(commodity) then return nil, "no licence" end
  local madeBy = commodity ~= "power" and not City.EXTRACTOR_OF[commodity]
    and City.RECIPES[City.MADE_BY[commodity] or ""]
  if madeBy then
    return nil, string.lower(commodity) .. " is made in a "
      .. string.lower(madeBy.name) .. ", not taken out of the ground"
  end
  plant = commodity == "power" and (plant or "nuclear") or nil
  if px then
    local err = self:sourceError(commodity, px, py, plant)
    if err then return nil, err end
    local cost, seam = self:sourceCost(commodity, px, py, plant)
    if cost > self.money then return nil, "not enough cash" end
    local bill = plant and self:materialsFor("source", plant) or {}
    local short = self:materialError(bill)
    if short then return nil, short end
    local trade = City.trade[commodity] or City.trade.water
    self:spend(cost)
    self:spendMaterials(bill)
    local s = self.g:addNode(px, py, "source")
    s.commodity, s.paid, s.level = commodity, cost, 1
    -- Four ports: enough for a well, a rig or a plant to feed a couple of
    -- routes, never enough to turn a producing building into a distribution
    -- point in its own right. That job belongs to a hub.
    s.ports = City.sourcePorts
    -- The ground, not the equipment, decides the ceiling. A works can be
    -- deepened up to what the deposit gives in a day and not one unit past it.
    if plant then
      local spec = City.PLANTS[plant]
      -- A station is commissioned with one unit in it and room for the rest.
      -- Its ceiling is the site, not the first machine on it.
      s.plant, s.output = plant, spec.output
      s.cap = spec.output * (spec.maxUnits or 1)
      s.upkeep, s.fuel = spec.upkeep, spec.fuel
      self.plantsBuilt = self.plantsBuilt or {}
      self.plantsBuilt[plant] = (self.plantsBuilt[plant] or 0) + 1
    elseif commodity == "water" and self:intakeCap(px, py) then
      -- Running water, so this is a treatment works and not a well. The
      -- channel sets the ceiling and the ladder runs twice as deep. See
      -- City.INTAKE.
      local cap, fed = self:intakeCap(px, py)
      s.intake, s.cap = fed, cap
      s.output = math.min(cap, City.INTAKE.output)
    elseif seam then
      local d = self:districtAt(px, py)
      s.cap = seam.cap or City.depositCap(commodity, (d and d.ring) or 0, false)
      s.output = math.min(s.cap, math.floor(trade.sourceOutput * (seam.yield or 1)))
    else
      -- Ground that is not a marked deposit still has a ceiling, and it is the
      -- ground that sets it: a bigger wood gives more timber, a deeper quarry
      -- more rock, and everything gives more the further out it is. It stays
      -- short of what a LARGE main carries, so ordinary ground never becomes
      -- a substitute for the intake.
      local d = self:districtAt(px, py)
      local o = self:obstacleAt(px, py)
      local scale = 1 + 0.3 * ((d and d.ring) or 0) + (o and math.max(0, (o.r - 70) / 180) or 0)
      s.cap = math.floor(trade.sourceOutput * scale * City.groundYield)
      s.output = math.min(s.cap, trade.sourceOutput)
    end
    if seam then
      seam.taken = true
      s.seam = true
      self:note("The %s deposit is opened: %d a day for $%d", commodity, s.output, cost)
    elseif plant then
      self:note("%s commissioned for $%d: %d units a day",
        City.PLANTS[plant].name, cost, s.output)
    else
      local spec = City.EXTRACTORS[City.EXTRACTOR_OF[commodity] or ""] or {}
      self:note("%s opened for $%d: %d %s a day",
        spec.name or "WORKS", cost, s.output, commodity)
    end
    self.premiumBought = self.premiumBought or {}
    if s.intake then self.intakesBought = (self.intakesBought or 0) + 1
    elseif commodity == "water" then self.sourcesBought = self.sourcesBought + 1
    else self.premiumBought[commodity] = (self.premiumBought[commodity] or 0) + 1 end
    self:refresh()
    return s
  end

  -- Somewhere legal, on ground the company owns, and not on top of the works.
  -- Water and oil have to be found first, so those go looking for a deposit
  -- rather than for empty ground.
  if commodity ~= "power" then
    local spec = City.EXTRACTORS[City.EXTRACTOR_OF[commodity] or ""]
    if not spec then return nil, commodity .. " is not taken out of the ground" end
    if spec.on == "deposit" then
      for _, seam in ipairs(self.deposits or {}) do
        if not seam.taken and seam.commodity == commodity
           and not self:sourceError(commodity, seam.x, seam.y) then
          return self:buySource(commodity, seam.x, seam.y)
        end
      end
      return nil, "no open " .. commodity .. " deposit on ground you hold"
    end
    -- Ground rather than a mark: walk the districts the company holds looking
    -- for somewhere this works is allowed to stand.
    for _, d in ipairs(self:ownedDistricts()) do
      for _ = 1, 40 do
        local x = self:rand(d.x + 90, d.x + d.w - 90)
        local y = self:rand(d.y + 70, d.y + d.h - 70)
        if not self:sourceError(commodity, x, y) then return self:buySource(commodity, x, y) end
      end
    end
    return nil, "nowhere on your ground suits a " .. string.lower(spec.name)
  end
  local owned = self:ownedDistricts()
  for _ = 1, 300 do
    local d = owned[self:random(#owned)]
    local x = self:rand(d.x + 90, d.x + d.w - 90)
    local y = self:rand(d.y + 90, d.y + d.h - 90)
    if not self:placementError(x, y) then
      local near = false
      for _, n in ipairs(self.g:aliveNodes()) do
        if (n.x - x) ^ 2 + (n.y - y) ^ 2 < 620 ^ 2 then near = true; break end
      end
      if near then
        return self:buySource(commodity, x, y)
      end
    end
  end
  return nil, "no room for a new well"
end

City.LICENSABLE = { power = true, beer = true, oil = true, food = true, internet = true }

function City:buyLicence(commodity)
  if not City.LICENSABLE[commodity] then return nil, "unknown trade" end
  if self.licences[commodity] then return nil, "already held" end
  local unlock = City.LICENCE_UNLOCK[commodity]
  if unlock and not self:unlocked(unlock) then return nil, "not available yet" end
  local cost = City.price[commodity .. "Licence"]
  if cost > self.money then return nil, "not enough cash" end
  self:spend(cost)
  self.licences[commodity] = true
  self:note("%s licence acquired: that trade can now be served",
    string.upper(commodity))
  return true
end

-- Buying the ability to lay better pipe. It changes nothing that is already in
-- the ground, which is the point: the old cheap mains at the centre of the
-- network stay the weakest thing the company owns until somebody digs them up.
function City:upgradeQuality()
  local cost = self:liningPrice()
  if not cost then return nil, "sealed pipe is the best there is" end
  if cost > self.money then return nil, "not enough cash" end
  self:spend(cost)
  self.lining = (self.lining or 1) + 1
  self.quality = self.lining - 1
  self:note("The company can now lay %s pipe. Mains already in the ground are unchanged.",
    string.lower(City.GRADES[self.lining].name))
  return true
end

function City:buyAds()
  if self.adDaysLeft > 0 then return nil, "campaign already running" end
  if City.price.ads > self.money then return nil, "not enough cash" end
  self:spend(City.price.ads)
  self.adDaysLeft = City.rules.adDays
  self:note("Advertising campaign booked for %d days", City.rules.adDays)
  return true
end

function City:invest(amount)
  if type(amount) ~= "number" or amount ~= amount or amount == math.huge then return nil, "invalid amount" end
  amount = math.floor(amount)
  if amount <= 0 then return nil, "nothing to invest" end
  if amount > self.money then return nil, "not enough cash" end
  self:spend(amount)
  -- Pays out at the end of the seventh day, counting today as the first, so
  -- "set aside for 7 days" ties the money up for exactly seven closes.
  self.investments[#self.investments + 1] = {
    amount = amount,
    matures = self.day + City.rules.investDays - 1,
  }
  self:note("$%d placed for %d days", amount, City.rules.investDays)
  return true
end

function City:daysToMaturity(inv)
  return math.max(0, inv.matures - self.day + 1)
end

function City:investedTotal()
  local t = 0
  for _, inv in ipairs(self.investments) do t = t + inv.amount end
  return t
end

--------------------------------------------------------------------------------
-- Customers
--------------------------------------------------------------------------------

function City:clientList(prospects)
  local t = {}
  for _, n in ipairs(self.g.nodes) do
    if n.alive and n.kind == "client" and (not not n.prospect) == (not not prospects) then t[#t + 1] = n end
  end
  return t
end

-- Each district has a character, so where you expand decides who comes calling.
-- Buying Brewers Row is how a company gets pubs; buying Docklands is how it
-- gets factories. This is the growth lever the map is for.
function City:pickClientType(district)
  local bias = district and City.DISTRICTS[district.id] and City.DISTRICTS[district.id].bias
  local pool = {}
  for _, key in ipairs({"house", "estate", "workshop", "pub", "factory", "subscriber", "market", "home"}) do
    local spec = City.CLIENTS[key]
    if self.licences[spec.commodity] then
      local leaning = bias and (bias[key] or (spec.follows and math.floor((bias[spec.follows] or 0) / 2)))
      local weight = leaning or (key=="market" and spec.weight) or (bias and 0) or spec.weight
      for _ = 1, weight do pool[#pool + 1] = key end
    end
  end
  if #pool == 0 then return "house" end
  return pool[self:random(#pool)]
end

-- Where the day-one follow-up request should stand: beside a water fitting
-- with a free connection, or beside the well itself.
function City:openingAnchor()
  local best
  for _, n in ipairs(self.g:aliveNodes()) do
    local fitting = n.kind == "junction" or n.kind == "manifold" or (n.kind == "source" and n.commodity == "water")
    if fitting and (n.commodity == nil or n.commodity == "water") and self:connectionPorts(n.id) < (n.ports or 1)
      and (not best or (best.kind == "source" and n.kind ~= "source")) then best = n end
  end
  return best
end

function City:addClient(kind, prospect, district, near)
  if near then
    district = self:districtAt(near.x, near.y)
    if not (district and district.owned) then near, district = nil, nil end
  end
  local owned = self:ownedDistricts()
  district = district or owned[self:random(#owned)]
  kind = kind or self:pickClientType(district)
  local spec = City.CLIENTS[kind]
  -- Customers appear near the works, farther out as the company grows, and
  -- always on ground the company actually owns.
  local sources = {}
  for _, n in ipairs(self.g:nodesOfKind("source")) do
    if n.commodity == spec.commodity then sources[#sources + 1] = n end
  end
  -- On the very first day there is nothing standing at all, so the anchor is
  -- the middle of the home district.
  local anchor = #sources > 0 and sources[self:random(#sources)] or self.firstSource
  if not anchor then
    local home = self.districts[City.MAP.start]
    anchor = { x = home.x + home.w / 2, y = home.y + home.h / 2 }
  end
  if district and not (anchor.x >= district.x and anchor.x < district.x + district.w
      and anchor.y >= district.y and anchor.y < district.y + district.h) then
    -- A customer in a newly bought district anchors on that district instead,
    -- so buying ground actually produces enquiries there.
    anchor = { x = district.x + district.w / 2, y = district.y + district.h / 2 }
  end
  local reach = 260 + #self:clientList() * 45
  if near then anchor = near end
  for attempt = 1, 160 do
    local ang = self:random() * math.pi * 2
    local r = near and attempt <= 120 and self:rand(110, math.min(220, City.rules.linkRange - 40))
      or self:rand(180, math.min(600, reach))
    local x = math.max(70, math.min(self.bounds.w - 70, anchor.x + math.cos(ang) * r))
    local y = math.max(70, math.min(self.bounds.h - 70, anchor.y + math.sin(ang) * r * 0.78))
    if not self:placementError(x, y) then
      local n = self.g:addNode(x, y, "client")
      n.clientType = kind
      n.commodity = spec.commodity
      n.demand = self:random(spec.demand[1], spec.demand[2])
      n.rateBase = spec.rate
      n.rate = self:offerRate(spec.rate)
      n.patience = spec.patience
      n.grace = spec.patience
      n.joined = self.day
      n.prospect = prospect or false
      n.expires = self.day + 5
      self:refresh()
      return n
    end
  end
  return nil
end

-- Every customer negotiates their own price. Early on the spread is almost
-- nothing, so a small company cannot be killed by drawing three bad offers in a
-- row; as the company grows the spread widens until a lowball house is worth
-- refusing outright and a premium factory is worth rerouting the map for.
-- Skipping offers only becomes a strategy once there is something to skip.
function City:marketSpread()
  local scale = #self:clientList() + 2 * (self.districtsBought or 0) + (self.sourcesBought or 0)
  return 0.05 + 0.50 * math.min(1, scale / 18)
end

function City:offerRate(base)
  local spread = self:marketSpread()
  -- Two uniforms make a triangular draw: middling offers are common, extreme
  -- ones are rare, and the mean stays where the trade says it should be.
  local factor = 1 + spread * (self:random() + self:random() - 1)
  return math.max(1, math.floor(base * factor + 0.5))
end

-- How far above or below the going rate this customer is paying, as a fraction.
function City:ratePremium(c)
  local base = c.rateBase or (City.CLIENTS[c.clientType] or {}).rate
  if not base or base == 0 then return 0 end
  return c.rate / base - 1
end

--------------------------------------------------------------------------------
-- Flow
--------------------------------------------------------------------------------

function City:refresh()
  self.served = {}
  self.servedBy = {}
  self.detail = { edge = {}, node = {}, hub = {}, works = {} }
  self.flowBy = {}
  self.edgeFlowBy = {}
  self.oilSpills = {}
  self.produced = {}
  -- A well makes one thing, so `produced` says all there is to say about it. A
  -- haven lands a dozen, each at its own price, so what it owes has to be kept
  -- trade by trade.
  self.producedBy = {}
  self.spare = {}
  self.wellSpare = {}
  self.capacityBy = {}

  -- What the yards will take in today, shared out between them.
  local yards = self.g:nodesOfKind("dc")
  for _, yard in ipairs(yards) do
    yard.intake = {}
    for _, name in ipairs(Graph.ALL) do
      local role = Graph.COMMODITIES[name].role
      if role == "material" or role == "vehicle" then
        local share = math.floor(self:yardIntake(name) / #yards)
        if share > 0 then yard.intake[name] = share end
      end
    end
  end

  -- What every works is asking for, before anything is solved.
  local works = self.g:nodesOfKind("works")
  for _, w in ipairs(works) do
    local recipe = City.RECIPES[w.recipe or ""]
    w.makes = recipe and recipe.makes or nil
    w.wants = self:worksWants(w)
    w.ready = 0
    self.detail.works[w.id] = {}
  end

  -- Which networks are worth solving at all.
  --
  -- There are eighteen commodities and a company touches a handful of them. A
  -- network with nothing feeding it, or nothing asking for it, has no flow in
  -- it by definition, and building it to discover that costs a pass over every
  -- node and every edge in the company. So: solve a commodity only where both
  -- ends of it exist.
  -- Every commodity reports a flow, including the ones that were never solved:
  -- "no beer moved today" is a number, not an absence.
  for _, name in ipairs(City.SOLVE_ORDER) do self.flowBy[name] = 0 end

  local feeds, wants = {}, {}
  for _, n in ipairs(self.g:aliveNodes()) do
    if n.kind == "source" and n.commodity then feeds[n.commodity] = true
    elseif n.kind == "works" then
      if n.makes then feeds[n.makes] = true end
      local recipe=City.RECIPES[n.recipe]; if recipe and recipe.coproduct then feeds[recipe.coproduct]=true end
      for key in pairs(n.wants or {}) do wants[key] = true end
    elseif n.kind == "depot" then
      if (n.stored or 0)>0 then feeds[n.commodity]=true end
      if n.intakeRequest then wants[n.commodity]=true end
    elseif n.kind == "terminal" then
      for _, key in ipairs(Graph.ALL) do
        if Graph.COMMODITIES[key].landed ~= false then feeds[key] = true end
      end
    elseif n.kind == "dc" then
      for key in pairs(n.intake or {}) do wants[key] = true end
    elseif n.kind == "client" and not n.prospect then
      wants[n.commodity] = true
      for key in pairs(n.demands or {}) do wants[key] = true end
    elseif n.kind == "station" then
      wants.gasoline = true
    end
  end

  for _,e in ipairs(self.g.edges) do if e.alive and (e.spillWanted or 0)>0 then wants.oil=true end end
  -- One pass, in dependency order. By the time a commodity is solved, every
  -- works that makes it has already been told what turned up for it, so its
  -- output is a number rather than a guess.
  for _, name in ipairs(City.SOLVE_ORDER) do
    -- What every works making this commodity managed to make, whether or not
    -- anybody is asking for it yet. A works with no customer still has an
    -- output, and the player needs to see it to know the chain works.
    for _, w in ipairs(works) do
      local recipe=City.RECIPES[w.recipe]
      if w.makes == name then w.ready = self:worksOutput(w) end
      if recipe and recipe.coproduct==name then w.coproduct=name; w.coproductReady=self:worksOutput(w) end
    end

    if feeds[name] and wants[name] then
    local flow, _, served, detail, produced = self.g:maxflow(false, name)
    self.flowBy[name] = flow
    self.edgeFlowBy[name]=(detail or {}).edge or {}
    if name=='oil' then self.oilSpills=(detail or {}).spill or {} end
    for id, v in pairs(served or {}) do
      local n = self.g.nodes[id]
      if n and n.kind == "depot" then
        self.detail.depot=self.detail.depot or {}
        self.detail.depot[id]=v
      elseif n and n.kind == "works" then
        self.detail.works[id][name] = v
      elseif n and n.kind == "dc" then
        self.detail.yard = self.detail.yard or {}
        self.detail.yard[name] = (self.detail.yard[name] or 0) + v
      else
        self.servedBy[id] = self.servedBy[id] or {}
        self.servedBy[id][name] = v
        if name == n.commodity or n.kind=="station" then self.served[id] = v end
      end
    end
    for id, v in pairs(produced or {}) do
      self.produced[id] = (self.produced[id] or 0) + v
      self.producedBy[id] = self.producedBy[id] or {}
      self.producedBy[id][name] = v
    end
    for id, v in pairs((detail or {}).edge or {}) do self.detail.edge[id] = v end
    for id, v in pairs((detail or {}).node or {}) do
      self.detail.node[id] = (self.detail.node[id] or 0) + v
    end
    end
  end

  -- Two different questions share the word "spare".
  --
  -- `wellSpare` is output that was pumped for and never sold: real product
  -- sitting in the works, which is the only thing a depot can take in. A
  -- haven's unused berths are not that -- nothing was landed and nothing was
  -- billed for -- so they do not count here.
  --
  -- `spare` is headroom: everything the network could still draw on today from
  -- any feed at all. That is the number that answers "can I sign this
  -- customer", so it is the one the sidebar shows and the one a starved
  -- customer's diagnosis is judged against.
  --
  -- Counted in one pass over the nodes rather than one pass per commodity,
  -- because there are eighteen commodities now and only one company.
  local wells, headroom = {}, {}
  for _, n in ipairs(self.g:aliveNodes()) do
    local key = n.commodity
    if key and n.kind == "source" then
      wells[key] = (wells[key] or 0) + (n.effectiveOutput or n.output or 0)
      headroom[key] = (headroom[key] or 0) + (n.effectiveOutput or n.output or 0)
    elseif key and n.kind == "depot" then
      headroom[key] = (headroom[key] or 0) + (n.stored or 0)
    elseif n.kind == "works" and n.makes then
      headroom[n.makes] = (headroom[n.makes] or 0) + (n.ready or 0)
      if n.coproduct then headroom[n.coproduct]=(headroom[n.coproduct] or 0)+(n.coproductReady or 0) end
    elseif n.kind == "terminal" then
      -- A haven never runs out. What it can actually put into the city is the
      -- capacity of the track leaving it, so that is what counts as headroom:
      -- quoting the truth here would be "infinity", which tells nobody whether
      -- the next customer can be signed.
      for _, e in ipairs(self.g:edgesAt(n.id)) do
        if e.rail and e.commodity ~= "power" then
          headroom[e.commodity] = (headroom[e.commodity] or 0) + e.cap
        end
      end
    end
  end
  for _, name in ipairs(City.SOLVE_ORDER) do
    self.capacityBy[name] = headroom[name] or 0
    self.wellSpare[name] = math.max(0, (wells[name] or 0) - (self.flowBy[name] or 0))
    self.spare[name] = math.max(0, (headroom[name] or 0) - (self.flowBy[name] or 0))
  end

  -- People travel on what the day's solve left in the filling stations.
  self:routeTrips()

  self.revision = (self.revision or 0) + 1
  self.unserved = 0
  for _, c in ipairs(self:clientList()) do
    if not self:fullyServed(c) then self.unserved = self.unserved + 1 end
  end
  return self.served
end

-- A market event multiplies what one trade pays for a few days. It is the only
-- thing in the game that changes a price without the player touching anything,
-- and it is what makes a depot full of yesterday's beer worth having.
City.EVENTS = {
  { key = "heatwave",  commodity = "water", rate = 1.45, days = 4,
    head = "Heatwave: households pay a premium for water" },
  { key = "festival",  commodity = "beer",  rate = 1.60, days = 3,
    head = "Beer festival: the pubs will take everything you have" },
  { key = "refit",     commodity = "oil",   rate = 1.55, days = 3,
    head = "Refinery refit: oil fetches a premium across the works" },
  { key = "mains",     commodity = "water", rate = 0.75, days = 3,
    head = "Rationing order: the council caps what water may be charged" },
  { key = "duty",      commodity = "beer",  rate = 0.72, days = 3,
    head = "Excise duty raised: beer margins squeezed" },
  { key = "glut",      commodity = "oil",   rate = 0.70, days = 3,
    head = "Oil glut: the factories renegotiate downward" },
}

function City:eventRate(commodity)
  if self.event and self.event.commodity == commodity and self.event.left > 0 then
    return self.event.rate
  end
  return 1
end

-- A customer supplied in full for `every` closes running raises its rate by
-- `step`, at most `max` times.
City.LOYALTY = { every = 10, step = 1, max = 3 }

function City:clientIncome(c)
  return math.floor((self.served[c.id] or 0) * c.rate * self:eventRate(c.commodity) + 0.5)
end

-- A well is paid for water somebody takes, not for water it could pump. The
-- flat fee is the standing contract with the network, so a well nobody draws
-- on earns nothing and is only an upkeep bill: customers are the business.
function City:sourceIncome(n)
  if n.kind ~= "source" then return 0 end
  local delivered = (self.produced or {})[n.id] or 0
  if delivered <= 0 then return 0 end
  local trade = City.trade[n.commodity] or City.trade.water
  return math.floor(trade.wholesale + delivered * trade.wholesalePerUnit)
end

--------------------------------------------------------------------------------
-- Why is this customer short?
--------------------------------------------------------------------------------

-- A customer showing 1/4 is a question, and the answer is almost always one
-- specific main that is already carrying everything it can. The flow solver
-- knows which one; there is no reason to make the player find it by eye.
--
-- Walks outward from the customer over mains of its own trade, in order of
-- distance, and reports the first constraint it meets: a shut valve, no route
-- to a well at all, wells already at full output, or -- most often -- the
-- nearest main running full.
function City:constraintFor(id)
  local c = self.g.nodes[id]
  if not (c and c.alive and c.kind == "client" and not c.prospect) then return nil end
  if self:fullyServed(c) then return nil end
  if c.supplyClosed then return "valve" end

  local com = c.commodity
  for key,want in pairs(c.demands or {}) do
    if ((self.servedBy[c.id] or {})[key] or 0)<want then com=key; break end
  end
  local seen, queue, head = { [id] = true }, { id }, 1
  -- Two answers: the first full main on the way here, and the first one that
  -- could actually be made wider. The advice points at the second where there
  -- is one, because pointing at a garden stub that may never be more than a
  -- garden stub is advice nobody can act on.
  local saturated, widenable, damaged, sawFeed = nil, nil, nil, false
  while head <= #queue do
    local u = queue[head]; head = head + 1
    local node = self.g.nodes[u]
    if node.kind == "source" or node.kind == "terminal"
       or (node.kind == "depot" and (node.stored or 0) > 0) then sawFeed = true end
    for _, ei in ipairs(self.g.adj[u] or {}) do
      local e = self.g.edges[ei]
      if e.alive and e.commodity == com then
        if math.abs(self.detail.edge[ei] or 0) >= e.cap then
          saturated = saturated or ei
          -- A main that is full because it is burst is not a main that is too
          -- small. It was reported as one, and the only fix offered was to
          -- lay a wider one, which is a strange thing to be told about a pipe
          -- with a hole in it.
          if not damaged and (e.leaking or e.cap < (e.capMax or e.cap)) then damaged = ei end
          if not widenable and self:biggerSize(e) then widenable = ei end
        end
        local v = (e.a == u) and e.b or e.a
        if not seen[v] and self.g.nodes[v] and self.g.nodes[v].alive then
          seen[v] = true
          queue[#queue + 1] = v
        end
      end
    end
  end

  if not sawFeed then return "unconnected" end
  if damaged then return "repair", damaged end
  -- If every well is already pumping flat out, a wider pipe changes nothing.
  if (self.spare[com] or 0) <= 0 then return "output" end
  if widenable or saturated then return "main", widenable or saturated end
  return "output"
end

-- Drawn against everything that could feed it, for one trade.
function City:supplyFor(commodity)
  return self.flowBy[commodity] or 0, self.capacityBy[commodity] or 0
end

-- The same question for the whole network, for the alert strip.
function City:shortCustomers()
  local t = {}
  for _, c in ipairs(self:clientList()) do
    if not self:fullyServed(c) then t[#t + 1] = c end
  end
  return t
end

function City:dailyRevenue()
  local rev = 0
  for _, c in ipairs(self:clientList()) do
    rev = rev + self:clientIncome(c)
  end
  for _, n in ipairs(self.g:aliveNodes()) do
    if n.kind == "source" then rev = rev + self:sourceIncome(n) end
  end
  return rev + self:transitIncome()
end

function City:leakChance(e)
  -- Steel track laid on ballast does not foul. Rail is the only link in the
  -- game with no maintenance story at all, which is most of what you are
  -- paying for when you lay it.
  if e.rail then return 0 end
  -- A road is not a pipe. It never leaks, which is what its higher running cost
  -- is buying.
  if (City.trade[e.commodity] or {}).noLeak then return 0 end
  local q = 1 - City.rules.qualityStep * self.quality
  local g = self:gradeOf(e).risk
  local a, b = self.g.nodes[e.a], self.g.nodes[e.b]
  for _, n in ipairs(self.g:nodesOfKind("tower")) do
    if (n.x - (a.x + b.x) / 2)^2 + (n.y - (a.y + b.y) / 2)^2 <= 220^2 then
      g = g * 0.45
      break
    end
  end
  return City.rules.leakBase * g
end

-- What replacing this main with a better lined one would save per day: the
-- repairs it avoids, weighted by how often they would have happened. The
-- inspector prints it beside the price of the work, so digging up a working
-- main is a decision with a number on it rather than a hunch.
function City:liningPayback(e, grade)
  local here = City.GRADES[e.grade or 1]
  local target = City.GRADES[grade or ((e.grade or 1) + 1)]
  if not target or target == here then return nil end
  local trade = City.trade[e.commodity] or City.trade.water
  local base = trade.repairBase + trade.repairPerLost * 2 + self:pipeLength(e) * trade.repairPerM
  local risk = self:leakChance(e) / here.risk
  local perDay = risk * (here.risk * base * here.repair - target.risk * base * target.repair)
  if perDay <= 0 then return nil end
  local q = self:replaceQuote(e.id, e.size, grade or ((e.grade or 1) + 1))
  return perDay, q and math.ceil(q.net / perDay) or nil
end

--------------------------------------------------------------------------------
-- The day ends
--------------------------------------------------------------------------------

function City:endDay()
  if self.bankrupt then return nil end
  self:refresh()

  local report = {
    day = self.day, revenue = 0, interest = 0, leaks = {}, burst = {}, expenses = self:dailyExpenses(),
    left = {}, arrived = nil, unhappy = 0,
  }

  -- 1. Customers pay for what arrived, and lose patience for what did not.
  for _, c in ipairs(self:clientList()) do
    local got = self.served[c.id] or 0
    report.revenue = report.revenue + self:clientIncome(c)
    if self:fullyServed(c) then
      c.grace = c.patience or City.CLIENTS[c.clientType].patience
      -- Loyalty: a customer kept fully supplied for a run of closes pays a
      -- little more, a few times over. Reliability is the product.
      c.streak = (c.streak or 0) + 1
      if c.streak % City.LOYALTY.every == 0 and (c.loyalty or 0) < City.LOYALTY.max then
        c.loyalty = (c.loyalty or 0) + 1
        c.rate = (c.rate or 0) + City.LOYALTY.step
        report.loyal = report.loyal or {}
        report.loyal[#report.loyal + 1] = { x = c.x, y = c.y, id = c.id }
      end
    else
      c.streak = 0
      -- A secure contract refunds what it was not given.
      local credit = self:serviceCredit(c)
      if credit > 0 then
        report.expenses = report.expenses + credit
        report.credits = (report.credits or 0) + credit
      end
      c.grace = c.grace - 1
      report.unhappy = report.unhappy + 1
      if c.grace <= 0 then
        report.left[#report.left + 1] = { name = City.CLIENTS[c.clientType].name, x = c.x, y = c.y }
        self:retireClient(c)
        self.reputation = math.max(0, self.reputation - City.rules.repLoss)
        self.lostClients = self.lostClients + 1
        self:note("%s left: unsupplied too long. Reputation %d",
          City.CLIENTS[c.clientType].name, self.reputation)
      end
    end
  end

  -- 2. Wholesale from the wells.
  for _, n in ipairs(self.g:aliveNodes()) do
    if n.kind == "source" then report.revenue = report.revenue + self:sourceIncome(n) end
  end
  -- 2a. Everybody who travelled today paid for it on the way.
  local transit = self.transit or {}
  report.trips, report.tripsCarried = transit.trips or 0, transit.carried or 0
  report.transitIncome = self:transitIncome()
  report.revenue = report.revenue + report.transitIncome
  self.money = self.money + report.revenue - report.expenses

  -- 2b. People settle where the service is good and drift away where it is not.
  report.grown = self:growPopulation()

  -- 3. Pipes foul. A leak is a condition, not an event: it keeps costing
  --    capacity every day until somebody pays to fix it.
  for _, e in ipairs(self.g.edges) do
    if e.alive then
      if not e.leaking and self:random() < self:leakChance(e) and true then
        e.leaking = true
        self:note("Leak found on a %s main", e.commodity)
      end
      if e.leaking then
        -- Armour buys time: the main still fails, but it bleeds out slowly
        -- enough that a crew or a player gets there first.
        e.decayTick = (e.decayTick or 0) + 1
        if e.decayTick >= self:gradeOf(e).decay then
          e.decayTick = 0
          e.cap = math.max(0, e.cap - 1)
        end
        local na, nb = self.g.nodes[e.a], self.g.nodes[e.b]
        if e.cap <= 0 then
          report.burst[#report.burst + 1] = { x = (na.x + nb.x) / 2, y = (na.y + nb.y) / 2 }
          if not e.burstReported then self:note("A %s main is out of service: repair required", e.commodity) end
          e.burstReported = true
        else
          report.leaks[#report.leaks + 1] = { x = (na.x + nb.x) / 2, y = (na.y + nb.y) / 2 }
        end
      end
    end
  end

  -- 3a1. Materials delivered into the yards today. This is the only way
  --      anything gets onto the books: steel in a wagon is not steel you can
  --      build with until it has been taken in somewhere.
  self.stock = self.stock or {}
  report.delivered = {}
  for material, units in pairs((self.detail or {}).yard or {}) do
    if units > 0 then
      self.stock[material] = (self.stock[material] or 0) + units
      report.delivered[material] = units
    end
  end

  -- Jewelry is sold at the receiving yard, once and before solvency settles.
  report.jewelryIncome=(report.delivered.jewelry or 0)*900
  if report.jewelryIncome>0 then
    self.stock.jewelry=math.max(0,(self.stock.jewelry or 0)-(report.delivered.jewelry or 0))
    self.money=self.money+report.jewelryIncome; report.revenue=report.revenue+report.jewelryIncome
  end

  -- 3a1b. Cars that reached a yard are sold to the districts that want them.
  report.carsSold, report.carIncome = self:sellCars()
  report.revenue = report.revenue + report.carIncome

  -- 3b. The crews work the backlog. This is what the wage buys: the worst main
  --     on the books gets fixed without anybody clicking on it.
  report.crewFixed, report.crewCost = 0, 0
  for _ = 1, (self.crews or 0) do
    local worst, worstCost
    for _, e in ipairs(self.g.edges) do
      if e.alive and e.leaking then
        local cost = self:repairCost(e)
        if cost <= self.money and (not worst or cost > worstCost) then worst, worstCost = e, cost end
      end
    end
    if not worst then break end
    self.money = self.money - worstCost
    worst.cap = worst.capMax or worst.cap
    worst.leaking, worst.burstReported, worst.decayTick = false, nil, nil
    worst.calcification=0
    report.crewFixed = report.crewFixed + 1
    report.crewCost = report.crewCost + worstCost
  end
  if report.crewFixed > 0 then
    self:note("Crews repaired %d main%s for $%d", report.crewFixed,
      report.crewFixed == 1 and "" or "s", report.crewCost)
    self:refresh()
  end

  -- 3c. Depots take in the day's unsold output and give back what they lent.
  report.stored, report.drawn = 0, 0
  for _, n in ipairs(self.g:nodesOfKind("depot")) do
    local incoming=(self.detail.depot or {})[n.id] or 0
    n.stored=(n.stored or 0)+incoming
    report.stored=report.stored+incoming
    local drawn = self.produced[n.id] or 0
    if drawn > 0 then
      n.stored = math.max(0, (n.stored or 0) - drawn)
      report.drawn = report.drawn + drawn
    end
  end
  for _, name in ipairs(Graph.TRADES) do
    local spare = self.wellSpare[name] or 0
    for _, n in ipairs(self.g:nodesOfKind("depot")) do
      if not n.freightStorage and n.commodity == name and spare > 0 and self.g:degree(n.id) > 0 then
        local room = (n.capacityStore or City.depotCapacity) - (n.stored or 0)
        local take = math.min(spare, room, n.fillRate or City.depotFillRate)
        if take > 0 then
          n.stored = (n.stored or 0) + take
          spare = spare - take
          report.stored = report.stored + take
        end
      end
    end
  end

  -- 4. Investments mature.
  for i = #self.investments, 1, -1 do
    local inv = self.investments[i]
    if self.day >= inv.matures then
      local mean,sd=self:investmentDistribution()
      local r = gauss(self, mean, sd)
      local payout = math.max(0,math.floor(inv.amount * (1 + r)))
      self.money = self.money + payout
      report.interest = report.interest + (payout - inv.amount)
      self:note("Investment returned $%d on $%d (%+.1f%%)", payout, inv.amount, r * 100)
      table.remove(self.investments, i)
    end
  end

  -- Expired requests hurt more than a clear refusal.
  report.ignored=0
  for _,c in ipairs(self:clientList(true)) do
    if c.expires<=self.day then
      self:retireClient(c)
      report.ignored=report.ignored+1
      self.reputation=math.max(0,self.reputation-City.rules.repIgnored)
    end
  end
  local limit=self:requestLimit()
  local chance=City.rules.arriveBase+self.reputation/500
    + (self.adDaysLeft>0 and City.rules.adBoost or 0)
  local count=0
  if limit>1 then
    count=self:random(limit-1,limit)
  elseif self.day%2==1 or self:random()<chance then count=1 end
  if self.adDaysLeft>0 then count=count+1 end
  report.arrivals={}
  local room=math.max(0,math.max(4,limit*3)-#self:clientList(true))
  for i=1,math.min(count,room) do
    -- The first close always leaves a second house within one pipe of the
    -- network just built, so day two opens on something to connect.
    local c=self.day==1 and i==1 and self:addClient("house",true,nil,self:openingAnchor()) or self:addClient(nil,true)
    if not c then break end
    local request={name=City.CLIENTS[c.clientType].name,x=c.x,y=c.y,id=c.id}
    report.arrivals[#report.arrivals+1]=request
    report.arrived=report.arrived or request
  end
  if #report.arrivals>0 then self:note("%d new requests",#report.arrivals) end
  -- 5a. The distribution hubs sign, connect and widen for today's offers too.
  self:runDistribution(report)
  if report.ignored>0 then self:note("%d requests expired. Reputation -%d.",report.ignored,report.ignored*City.rules.repIgnored) end
  if self.adDaysLeft>0 then self.adDaysLeft=self.adDaysLeft-1 end

  -- 5b. Whatever the market decided to do this week.
  self:refresh()
  if self.event then
    self.event.left = self.event.left - 1
    if self.event.left <= 0 then self.event = nil end
  end
  if not self.event and self.day > 6 and self:random() < 0.16 then
    local spec = City.EVENTS[self:random(#City.EVENTS)]
    if self.licences[spec.commodity] then
      self.event = { key = spec.key, commodity = spec.commodity, rate = spec.rate,
                     left = spec.days, head = spec.head }
      report.event = spec.head
      self:note("%s", spec.head)
    end
  end

  -- 5c. Drought, grid faults and ground shifts.
  self:advanceShock(report)

  report.bonus = self:awardMilestones()
  require("experience").close(self,report)

  if report.unhappy == 0 and #self:clientList() > 0 then
    self.reputation = math.min(100, self.reputation + City.rules.repGain)
  end

  self.history[#self.history + 1] = {
    day = self.day, money = self.money, clients = #self:clientList(),
    revenue = report.revenue, expenses = report.expenses,
  }

  report.interestPaid = self:loanInterest()
  self.day = self.day + 1
  if self.money < 0 and self:investedTotal() == 0 then
    self.bankrupt = true
    self:note("The company is insolvent.")
  end

  self:refresh()
  report.money = self.money
  report.bankrupt = self.bankrupt
  self.lastReport = report
  return report
end

--------------------------------------------------------------------------------
-- Bringing an older company forward
--------------------------------------------------------------------------------

-- Saves are the player's actual company, sometimes eighty days deep, so a new
-- mechanic has to arrive around them rather than in place of them. Everything
-- here is additive: missing fields get sensible defaults, and the ground the
-- company was already standing on becomes the districts it already owns.
function City:migrate()
  self.permits = self.permits or { park = false, river = false, bedrock = false }
  -- Islands surveyed before they grew groves get them now, around anything
  -- already built out there.
  for _, d in ipairs(self.districts or {}) do
    if d.island and not d.groves then self:growIslandGroves(d, true) end
  end
  self.deposits = self.deposits or {}
  -- Council tenders are gone. A bond already posted on one comes back.
  for _, t in ipairs(self.tenders or {}) do
    if t.status == "accepted" and (t.bond or 0) > 0 then self.money = self.money + t.bond end
  end
  self.tenders, self.tendersDone, self.nextTender = nil, nil, nil
  if self.ambition == "tenders" then self.ambition = nil end
  self.crews = self.crews or 0
  self.orders = self.orders or {}
  -- The automated departments are gone: nothing on the books buys land or
  -- replaces mains on the company's behalf any more, or draws a wage for it.
  self.orders.engineers, self.orders.estates = nil, nil
  -- The automation hub is gone too. One already standing becomes what it
  -- always was in spirit: a distribution hub at the top of the fitting ladder,
  -- keeping its floor, and its mains exactly where they are.
  for _, n in ipairs(self.g.nodes) do
    if n.kind == "exchange" then
      n.kind, n.level = "manifold", 4
      n.ports, n.throughput = math.max(n.ports or 0, 10), 999
      n.radius, n.covered, n.demandBy, n.signed, n.autoWiden = nil, nil, nil, nil, nil
    elseif n.kind == "client" then
      n.hub = nil
      -- Wells stopped being paid a wholesale fee and the going rate for water
      -- rose a dollar to make up for it. Contracts signed at the old going
      -- rate move with it, once: the new base is never the old one.
      local was = ({ house = 6, estate = 8 })[n.clientType]
      if was and n.rateBase == was and n.rate then
        n.rateBase, n.rate = was + 1, n.rate + 1
      end
    end
  end
  self.dispatchRate, self.estateReserve, self.estateMax, self.estateDiscount = nil, nil, nil, nil
  self.stock = self.stock or {}
  self.premiumBought = self.premiumBought or {}
  self.districtsBought = self.districtsBought or 0
  self.loan = self.loan or 0
  self.licences = self.licences or { water = true }
  if self.licences.power == nil then self.licences.power = false end
  if self.licences.food == nil then self.licences.food = false end
  if self.licences.internet == nil then self.licences.internet = false end
  self.links = self.links or {}

  if not self.districts then
    local old = self.bounds or { x = 0, y = 0, w = 2000, h = 1400 }
    self.bounds = { x = 0, y = 0, w = City.MAP.cols * City.MAP.w, h = City.MAP.rows * City.MAP.h }
    self.districts = {}
    for row = 1, City.MAP.rows do
      for col = 1, City.MAP.cols do
        local i = (row - 1) * City.MAP.cols + col
        local d = {
          id = i, col = col, row = row, name = City.DISTRICTS[i].name,
          x = (col - 1) * City.MAP.w, y = (row - 1) * City.MAP.h,
          w = City.MAP.w, h = City.MAP.h, owned = false,
        }
        -- Whatever the old, smaller map covered is ground already paid for.
        d.owned = d.x < old.x + old.w and d.y < old.y + old.h
        self.districts[i] = d
      end
    end
    -- Any structure already standing keeps its ground, wherever it ended up.
    for _, n in ipairs(self.g:aliveNodes()) do
      local d = self:districtAt(n.x, n.y)
      if d then d.owned = true end
    end
    local owned = #self:ownedDistricts()
    self.districtsBought = math.max(0, owned - 1)
    -- The new districts have never been surveyed, so give them their ground.
    for i, d in ipairs(self.districts) do
      if not d.owned then
        local spec = City.DISTRICTS[i]
        self:scatterObstacles(spec.rough, d)
        self:scatterDeposits(d, spec)
      end
    end
    self:note("Survey filed: %d districts held, %d more available to purchase",
      owned, #self.districts - owned)
  end

  -- A save from before the river existed, or from when it ran dead straight,
  -- still has a home district to lay a meandering one out from, and the
  -- river's geometry answers to nothing but that and the seed.
  -- A company whose river still runs the old course moves to the new one if,
  -- and only if, nothing it has built is in the way: no structure standing in
  -- the new channel, no main crossing water that was dry, and every river
  -- intake still on a bank. Otherwise the old course stays, because moving a
  -- river under somebody's works is not a migration, it is a flood.
  -- Several courses are tried, each from the seed, and the first that misses
  -- everything wins, so a single house on the bank does not keep the old river.
  local clear, candidate = false, nil
  for attempt = 0, (self.river and self.river.meander and self.river.style ~= 2) and 39 or -1 do
    candidate = {}
    for k, v in pairs(self.river) do candidate[k] = v end
    candidate.style = 2
    if attempt > 0 then candidate.meander = (self.river.meander * 48271 + attempt * 7919) % 2147483647 end
    local newPath = self:riverPath2(candidate)
    local oldPath = self:riverPath()
    clear = true
    for _, n in ipairs(self.g.nodes) do
      if n.alive then
        local now = self:riverEdgeOn(newPath, n.x, n.y)
        if n.intake == "river" then
          if not now or now <= 0 or now > City.riverWellReach then clear = false end
        elseif now and now <= 25 then clear = false end
      end
      if not clear then break end
    end
    if clear then
      for _, e in ipairs(self.g.edges) do
        local a, b = self.g.nodes[e.a], self.g.nodes[e.b]
        if e.alive and a and b then
          for i = 0, 24 do
            local t = i / 24
            local x, y = a.x + (b.x - a.x) * t, a.y + (b.y - a.y) * t
            local now = self:riverEdgeOn(newPath, x, y)
            local was = self:riverEdgeOn(oldPath, x, y)
            if now and now <= 0 and not (was and was <= 0) then clear = false; break end
          end
        end
        if not clear then break end
      end
    end
    if clear then break end
  end
  if clear and candidate then
      self.river = candidate
      for i = #self.obstacles, 1, -1 do
        local o = self.obstacles[i]
        local edge = self:riverEdge(o.x, o.y)
        if edge and edge < o.r then table.remove(self.obstacles, i) end
      end
      for i = #(self.deposits or {}), 1, -1 do
        local d = self.deposits[i]
        local edge = self:riverEdge(d.x, d.y)
        if not d.taken and edge and edge < 40 then table.remove(self.deposits, i) end
      end
  end

  if not (self.river and self.river.meander) then
    self:layOutRiver()
    -- The river replaces the old scattered ponds outright, and ground scattered
    -- before its course was known may stand in the new channel. Both go, or
    -- the map would show water and parkland painted over each other.
    for i = #self.obstacles, 1, -1 do
      local o = self.obstacles[i]
      local edge = self:riverEdge(o.x, o.y)
      if o.kind == "river" or (edge and edge < o.r) then table.remove(self.obstacles, i) end
    end
  end

  -- Ground saved before the map was endless: every cell was authored, none of
  -- them knew what ring they were in, and the survey stopped at twelve. Fill in
  -- what the generator would have put there and then open the frontier.
  self.seed = self.seed or self.rng or 1
  self.roughness = nil
  self.bounds = self.bounds or { x = 0, y = 0, w = City.MAP.w, h = City.MAP.h }
  for _, d in ipairs(self.districts or {}) do
    d.ring = d.ring or City.ringOf(d.col, d.row)
    d.spec = d.spec or (d.ring == 0 and City.DISTRICTS[(d.row - 1) * City.MAP.cols + d.col])
      or City.ARCHETYPES[1]
    d.name = d.name or d.spec.name or "District " .. d.id
    d.dressed = true
    self:growBounds(d)
  end
  self:indexCells()
  -- A deposit had no ceiling, and neither did what stood on it. Give both the
  -- ceiling the ground would have now, and never below what a well already
  -- produces: a company does not lose output to a rule change.
  for _, dep in ipairs(self.deposits or {}) do
    if not dep.cap then
      local d = self:districtAt(dep.x, dep.y)
      dep.cap = City.depositCap(dep.commodity, d and d.ring or 0, self:obstacleAt(dep.x, dep.y))
    end
  end
  for _, n in ipairs(self.g:nodesOfKind("source")) do
    if not n.cap then
      local d = self:districtAt(n.x, n.y)
      n.cap = math.max(n.output or 0,
        City.depositCap(n.commodity or "water", d and d.ring or 0, false))
    end
  end

  -- A well on the bank used to draw without limit. It becomes the intake it
  -- always was: a ceiling the channel sets, a ladder that runs twice as deep,
  -- and never less than it is already producing, because a company does not
  -- lose output to a rule change.
  for _, n in ipairs(self.g:nodesOfKind("source")) do
    if (n.commodity or "water") == "water" and not n.plant and not n.intake then
      local cap, fed = self:intakeCap(n.x, n.y)
      if cap then
        n.intake, n.cap = fed, math.max(n.output or 0, cap)
        self.intakesBought = (self.intakesBought or 0) + 1
        self.sourcesBought = math.max(0, (self.sourcesBought or 1) - 1)
      end
    end
  end
  self.intakesBought = self.intakesBought or 0

  -- A station used to be one machine and its ceiling was that machine. It can
  -- now take further units, so an existing one is given the room the site has
  -- always had rather than being left as the only plant nobody can extend.
  for _, n in ipairs(self.g:nodesOfKind("source")) do
    if n.plant then
      local spec = City.PLANTS[n.plant] or {}
      n.cap = math.max(n.cap or 0, (spec.output or 0) * (spec.maxUnits or 1))
    end
  end
  self:survey()

  -- Havens carried one trade and landed a fixed number of units a day. They
  -- now carry everything but power, without a ceiling, so an existing one is
  -- opened up rather than left as a second kind of haven nobody can build.
  -- Its old commodity and output are dropped; the track and mains already
  -- running out of it keep working exactly as they did.
  for _, n in ipairs(self.g:nodesOfKind("terminal")) do
    if n.commodity or n.output then
      n.commodity, n.output = nil, nil
      n.haven = n.haven or (self:onCoast(n.x, n.y) and "port") or "highway"
      self:note("%s now lands every trade but power, without limit",
        (City.HAVENS[n.haven] or City.HAVENS.port).name)
    end
  end
  -- Mains used to be any width between one and twenty four, and lining could be
  -- added to one already in the ground. Each of them becomes the size it would
  -- be sold as today, rounded up so nothing on the map carries less than it did
  -- yesterday, and the lining it already has is the lining it keeps.
  self.lining = self.lining or math.max(1, math.min(#City.GRADES, 1 + (self.quality or 0)))
  for _, e in ipairs(self.g.edges or {}) do
    if not e.bulk and not e.size then
      local spec = City.sizeFor(e.capMax or e.cap or 1)
      e.size = spec.key
      e.capMax = math.max(e.capMax or e.cap or 1, spec.cap)
      e.cap = math.min(e.cap or e.capMax, e.capMax)
    end
    -- Sizes have since grown (small 5 -> 7, medium 10 -> 15, large 20 -> 25).
    -- A main already in the ground carries what its size carries now, and a
    -- leaking one keeps the capacity it has lost.
    if not e.bulk and e.size then
      local spec = City.sizeOf(e.size)
      if (e.capMax or 0) < spec.cap then
        local lost = (e.capMax or spec.cap) - (e.cap or e.capMax or spec.cap)
        e.capMax = spec.cap
        e.cap = math.max(0, spec.cap - math.max(0, lost))
      end
    end
  end

  -- Track was the only bulk line there was, and it carried one commodity in
  -- whatever bore it was built to. It becomes a railway with a wagon big enough
  -- for exactly what it was already carrying, so nothing on the map moves less
  -- than it did yesterday.
  for _, e in ipairs(self.g.edges or {}) do
    if e.rail and not e.bulk then
      e.bulk = "rail"
      e.wagons = { [e.commodity] = e.cap }
      e.wagonCount = 1
    end
  end
  -- Nobody brews any more, so a beer deposit is a water deposit that was
  -- mislabelled by an older survey.
  for _, d in ipairs(self.deposits or {}) do
    if d.commodity == "beer" then d.commodity = "water" end
  end

  for _, n in ipairs(self.g.nodes) do
    if n.kind == "source" then
      n.level = n.level or 1
      n.output = n.output or (City.trade[n.commodity] or City.trade.water).sourceOutput
      if n.commodity ~= "water" then
        self.premiumBought[n.commodity] = (self.premiumBought[n.commodity] or 0) + 1
      end
    elseif n.kind == "client" and n.rate then
      n.rateBase = n.rateBase or (City.CLIENTS[n.clientType] or {}).rate or n.rate
    elseif n.kind == "gate" then
      n.throughput = n.throughput or 6
    elseif n.kind == "depot" then
      n.stored = n.stored or 0
      n.capacityStore = n.capacityStore or City.depotCapacity
    end
  end
  for _, e in ipairs(self.g.edges) do e.grade = e.grade or 1 end
  self:rebaseOrigin()
  return self
end

--------------------------------------------------------------------------------
-- Credit
--------------------------------------------------------------------------------

-- The bank lends against what the company owns, never against what is in the
-- till, so borrowing cannot bootstrap its own ceiling. Ten percent a week, flat
-- and knowable: unlike the investment fund, a loan has no variance at all. It
-- is the instrument for buying a district today and paying for it out of the
-- customers that district brings.
City.loanRate = require("data.economy").loanRate
City.loanRatio = require("data.economy").loanRatio

-- Everything the company owns except its cash: plant, ground and locked deposits.
function City:collateral()
  local v = self:investedTotal()
  for _, n in ipairs(self.g:aliveNodes()) do
    if n.kind ~= "client" then v = v + (n.paid or (n.kind == "source" and 260) or self:nodeCost(n.kind)) end
  end
  for _, e in ipairs(self.g.edges) do if e.alive then v = v + (e.paid or 0) end end
  -- Ground is an asset, and the priciest one the company owns.
  for i = 1, math.max(0, (self.districtsBought or 0)) do
    v = v + City.districtPrice.base * (City.districtPrice.growth ^ (i - 1))
  end
  return math.floor(v)
end

function City:loanLimit() return math.floor(self:collateral() * City.loanRatio) end
function City:loanAvailable() return math.max(0, self:loanLimit() - (self.loan or 0)) end
function City:loanInterest() return math.ceil((self.loan or 0) * City.loanRate / 7) end

function City:borrow(amount)
  if type(amount) ~= "number" or amount ~= amount or amount == math.huge then return nil, "invalid amount" end
  amount = math.floor(amount)
  if amount <= 0 then return nil, "nothing to borrow" end
  local room = self:loanAvailable()
  if room <= 0 then return nil, "no credit against current assets" end
  if amount > room then return nil, "only $" .. room .. " of credit available" end
  self.loan = (self.loan or 0) + amount
  self.money = self.money + amount
  self:note("Borrowed $%d at %d%% a week: $%d outstanding",
    amount, math.floor(City.loanRate * 100), self.loan)
  return true
end

function City:repay(amount)
  if (self.loan or 0) <= 0 then return nil, "nothing outstanding" end
  if type(amount) ~= "number" or amount ~= amount then return nil, "invalid amount" end
  amount = math.min(math.floor(amount), self.loan, self.money)
  if amount <= 0 then return nil, "not enough cash" end
  self.loan = self.loan - amount
  self.money = self.money - amount
  self:note("Repaid $%d: $%d outstanding", amount, self.loan)
  return true
end

-- Net worth: what is owned, less what is owed. Borrowing moves nothing here,
-- which is exactly what makes it borrowing rather than income.
function City:valuation()
  return math.floor(self.money + self:collateral() - (self.loan or 0))
end

function City:acceptClient(id)
  local c = self.g.nodes[id]
  if not (c and c.alive and c.prospect) then return nil, "no open offer" end
  c.prospect, c.joined = false, self.day
  self:note("%s contract signed: %d days to deliver", City.CLIENTS[c.clientType].name, c.grace)
  self:refresh()
  return c
end

function City:setCompanyName(name)
  if type(name)~="string" then return nil,"Enter a company name" end
  name=name:gsub("[%c]",""):match("^%s*(.-)%s*$")
  if #name<1 or #name>48 then return nil,"Use 1 to 48 bytes for the company name" end
  self.companyName=name
  return true
end

function City:chooseAmbition(id)
  for _,a in ipairs(require("experience").ambitions) do
    if a.id==id then self.ambition=id; return true end
  end
  return nil,"Unknown ambition"
end

function City:dismissGuide()
  self.guideDismissed=true
  return true
end

function City:toggleSupply(id)
  local c = self.g.nodes[id]
  if not (c and c.alive and c.kind == "client" and not c.prospect) then
    return nil, "no active customer"
  end
  c.supplyClosed = not c.supplyClosed
  self:note("%s %d service valve %s", City.CLIENTS[c.clientType].name, id,
    c.supplyClosed and "closed" or "opened")
  self:refresh()
  return c
end

function City:retireClient(c)
  if self.g:degree(c.id) == 0 then
    self.g:killNode(c.id)
  else
    -- The customer leaves the company; their installed through-pipes remain.
    c.kind, c.paid = "junction", 0
    c.commodity, c.demand, c.prospect, c.supplyClosed = nil, nil, nil, nil
  end
end

function City:requestLimit()
  local growth=math.max(0,math.min(1,(self.reputation-50)/50))
  local top=City.rules.requestMax
  return math.min(top,1+math.floor((top-1)*growth+1e-9))
end

function City:declineClient(id)
  local c = self.g.nodes[id]
  if not (c and c.alive and c.prospect) then return nil, "no open offer" end
  self:retireClient(c)
  self.reputation=math.max(0,self.reputation-City.rules.repDecline)
  self:note("Request declined. Reputation -%d.",City.rules.repDecline)
  self:refresh()
  return true
end

--------------------------------------------------------------------------------
-- What the company has grown into
--
-- Everything arrives when there is a reason for it. A player on day two is
-- looking at four buttons, not at nineteen commodities, four freight modes and
-- nine works behind a wall of prices they cannot pay. Each of these opens when
-- the company is the size where the thing it unlocks is the obvious next move.
--------------------------------------------------------------------------------
City.UNLOCKS = require("data.progression").UNLOCKS

function City:licenceCount()
  local n = 0
  for _, name in ipairs(Graph.TRADES) do if self.licences[name] then n = n + 1 end end
  return n
end

function City:unlocked(key)
  local spec = City.UNLOCKS[key]
  if not spec then return true end
  if spec.haven and #self.g:nodesOfKind("terminal") == 0 then return false end
  if spec.licences and self:licenceCount() < spec.licences then return false end
  if spec.clients and #self:clientList() < spec.clients then return false end
  if spec.population and not self:settled() then return false end
  if spec.road and not (self:settled() and self:hasRoad()) then return false end
  if spec.passengers and not self:hasPassengers() then return false end
  if spec.reactor and not self:hasReactor() then return false end
  if spec.intake and not self:hasIntake() then return false end
  return true
end

-- Whether a works on running water has been commissioned. A well will not do:
-- a trunk main is a main sized for a source that can fill one, and that is the
-- one kind of source that can.
function City:hasIntake()
  for _, n in ipairs(self.g:nodesOfKind("source")) do
    if n.alive and n.intake then return true end
  end
  return false
end

-- Why a thing is not available yet, in one line.
function City:unlockHint(key)
  local spec = City.UNLOCKS[key]
  if not spec or self:unlocked(key) then return nil end
  if spec.haven then return "Requires a port or road terminal" end
  if spec.population then return "Requires a populated district" end
  if spec.road then return "Requires people and a road" end
  if spec.passengers then return "Requires a used passenger route" end
  if spec.reactor then return "Requires a working reactor" end
  if spec.intake and not self:hasIntake() then
    return "Requires a works on the river or the coast"
  end
  if spec.licences and self:licenceCount() < spec.licences then
    return "Requires 2 trade licences"
  end
  return "Opens at " .. spec.clients .. " customers"
end

-- Why a main of this size cannot go in yet, in the words of whatever is
-- actually holding it up rather than of whichever size used to be the widest.
function City:sizeGate(spec)
  local key = spec and spec.unlock
  local gate = key and City.UNLOCKS[key]
  if not gate then return "that size is not open to this company yet" end
  return string.lower(gate.name) .. ": " .. string.lower(self:unlockHint(key) or "not open yet")
end

-- Trades arrive one at a time, in the order a company would actually take them
-- on: the cheap one that needs nothing but water, then the one that pays, then
-- the two that need the map.
-- Power first, because it needs nothing but water and everything else needs
-- it. Then oil, which is a rig on marked ground. Then food, which needs a farm
-- and a haven for the salt. Beer last: wheat, a maltings, a brewery, water and
-- power, which is the longest chain in the game.
City.LICENCE_ORDER = { "power", "oil", "food", "beer", "internet" }

-- A trade behind an unlock is not next until it is open: the internet licence
-- is not a greyed button waiting for a reactor, it is simply not there.
function City:nextLicence()
  for _, name in ipairs(City.LICENCE_ORDER) do
    local unlock = City.LICENCE_UNLOCK[name]
    if not self.licences[name] and not (unlock and not self:unlocked(unlock)) then return name end
  end
  return nil
end

--------------------------------------------------------------------------------
-- The first day
--
-- Four things, in the order they have to happen, each of them the thing the
-- player will go on doing for the rest of the game: find the water, sink a
-- well on it, run a main to somebody who wants it, and sign them up. The panel
-- shows one step at a time and disappears for good when they are done.
--------------------------------------------------------------------------------
City.TUTORIAL = {
  {
    key = "well", title = "Build your first well",
    body = "Pick Water well, then click a blue mark.",
    done = function(c) return #c.g:nodesOfKind("source") > 0 end,
  },
  {
    key = "junction", title = "Build a T split",
    body = "Place a T split between well and house.",
    done = function(c) return #c.g:nodesOfKind("junction") > 0 end,
  },
  {
    key = "main", title = "Connect the pipes",
    body = "Drag well to T split, then T split to house.",
    done = function(c)
      for _, n in ipairs(c.g.nodes) do
        if n.alive and n.kind == "client" and c.g:degree(n.id) > 0 then return true end
      end
      return false
    end,
  },
  {
    key = "sign", title = "Sign the contract",
    body = "Click the house and sign.",
    done = function(c) return #c:clientList() > 0 end,
  },
  {
    key = "close", title = "End the day",
    body = "Collect the day's income.",
    done = function(c) return c.day > 1 end,
  },
}

function City:tutorialStep()
  if self.guideDismissed then return nil end
  for i, step in ipairs(City.TUTORIAL) do
    if not step.done(self) then return step, i, #City.TUTORIAL end
  end
  -- Finished for good. Without this latch, a company that closes its only well
  -- a fortnight later would be told how to sink its first one.
  self.guideDismissed = true
  return nil
end

--------------------------------------------------------------------------------
-- Lessons
--
-- One short panel the first time something new is worth explaining, and never
-- again. They are written to be read in five seconds and to say the thing the
-- player cannot work out by looking: not what the button does, but why they
-- would press it.
--------------------------------------------------------------------------------
City.LESSONS = {
  {
    key = "trade", title = "A new trade",
    body = "Buy a licence in Company.",
    when = function(c) return c:licenceCount() > 1 end,
  },
  {
    key = "hub", title = "Distribution hubs",
    body = "Upgrade a hub to a distribution hub: it connects nearby clients itself.",
    when = function(c) return c:unlocked("hub") end,
  },
  {
    key = "cap", title = "Source limit",
    body = "This ground is maxed out. Build another well.",
    when = function(c)
      for _, n in ipairs(c.g:nodesOfKind("source")) do
        if n.cap and (n.output or 0) >= n.cap and not n.plant then return true end
      end
      return false
    end,
  },
  {
    key = "haven", title = "Ports",
    body = "Build a harbour on the coast to import goods.",
    when = function(c) return c:unlocked("haven") end,
  },
  {
    key = "yard", title = "Freight",
    body = "Yards take trains and trucks.",
    when = function(c) return c:unlocked("yard") end,
  },
  {
    key = "massive", title = "Massive mains",
    body = "Mains that carry 100 are open in Pipe options.",
    when = function(c) return c:unlocked("massive") end,
  },
  {
    key = "orders", title = "Staff",
    body = "Hire staff in Company.",
    when = function(c) return c:unlocked("orders") end,
  },
  {
    key = "people", title = "Roads",
    body = "Connect houses and factories to roads.",
    when = function(c) return c:unlocked("roads") end,
  },
  {
    key = "routes", title = "Bus, ferry and plane routes",
    body = "Link bus stops on roads with a route.",
    when = function(c) return c:unlocked("routes") end,
  },
  {
    key = "resort", title = "Resorts",
    body = "Build a resort by the water. Visitors pay.",
    when = function(c) return c:unlocked("resort") end,
  },
  {
    key = "internet", title = "Internet",
    body = "Buy the internet licence, then lay fibre.",
    when = function(c) return c:unlocked("internet") end,
  },
}

function City:pendingLesson()
  self.taught = self.taught or {}
  for _, lesson in ipairs(City.LESSONS) do
    if not self.taught[lesson.key] and lesson.when(self) then return lesson end
  end
  return nil
end

function City:teach(key)
  self.taught = self.taught or {}
  self.taught[key] = true
  return true
end

--------------------------------------------------------------------------------
-- Standing orders
--
-- The point where the company stops being a thing the player operates and
-- becomes a thing they run. Each rung is a rule they write once and then pay
-- for every day, and each one unlocks only when the company is big enough that
-- doing it by hand has become clerical work rather than a decision.
--
-- Nothing here does anything the player could not do themselves. That is the
-- test every one of them had to pass: automation buys back attention, never
-- money.
--------------------------------------------------------------------------------
City.ORDERS = require("data.progression").ORDERS
City.ORDER_LIST = { "surveyors", "dispatchers", "analysts" }

-- How big the company is, for the gates that open stronger buildings.
function City:progress() return #self:clientList() end

function City:orderAvailable(key)
  local spec = City.ORDERS[key]
  if not spec then return false end
  return self:progress() >= spec.clients
end

function City:hireOrder(key)
  local spec = City.ORDERS[key]
  if not spec then return nil, "no such department" end
  self.orders = self.orders or {}
  if self.orders[key] then return nil, "already on the books" end
  if not self:orderAvailable(key) then
    return nil, spec.name .. " are worth hiring at " .. spec.clients .. " customers"
  end
  if spec.hire > self.money then return nil, "not enough cash" end
  self:spend(spec.hire)
  self.orders[key] = true
  self:note("%s hired: $%d a day", spec.name, spec.wage)
  return true
end

function City:dismissOrder(key)
  self.orders = self.orders or {}
  if not self.orders[key] then return nil, "not on the books" end
  self.orders[key] = nil
  self:note("%s stood down", City.ORDERS[key].name)
  return true
end

function City:orderWages()
  local total = 0
  for key in pairs(self.orders or {}) do total = total + (City.ORDERS[key] or {}).wage end
  return total
end

City.crewWage = require("data.economy").crewWage
City.crewHire = require("data.economy").crewHire
City.crewMax = require("data.economy").crewMax

-- The itemised running cost. Pipes are no longer a flat half-dollar each: a
-- pressurised oil trunk across two districts is a standing liability, and the
-- ledger has to show that before the player builds three more of them.
-- What the havens charge today. A well's output is free once it is sunk; a
-- terminal bills for every unit it lands, so a haven is supply bought rather
-- than supply owned -- fast to stand up, and a permanent bite out of the margin.
function City:importBill()
  local total, by = 0, {}
  for _, n in ipairs(self.g:nodesOfKind("terminal")) do
    local mult = (City.HAVENS[n.haven] or {}).import or 1
    local landed = (self.producedBy or {})[n.id] or {}
    local cost = 0
    for _, name in ipairs(Graph.TRADES) do
      local trade = City.trade[name]
      cost = cost + (landed[name] or 0) * (trade.importCost or 0) * mult
    end
    total = total + cost
    by[n.id] = cost
  end
  return total, by
end

-- What the freight cost to move, as freight is really costed: a handling fee
-- per unit at the yard and a rate per unit per metre for the run. Only track
-- carries it, and only what actually moved today is charged.
function City:haulageBill()
  local total, by, fuelled = 0, {}, 0
  for _, e in ipairs(self.g.edges) do
    if e.alive and e.rail then
      local spec = City.MODES[e.bulk or "rail"]
      local units = 0
      for key in pairs(e.wagons or {[e.commodity]=e.cap}) do units=units+math.abs(((self.edgeFlowBy or {})[key] or {})[e.id] or 0) end
      local cost = units * (spec.haulPerUnit + self:pipeLength(e) * spec.haulPerM)
      if spec.diesel then fuelled = fuelled + cost end
      total = total + cost
      by[e.id] = cost
    end
  end
  -- Lorries and ships burn diesel. A company that refines its own runs its
  -- fleet on it and keeps the difference, which is the whole reason to put a
  -- refinery next to your own crude instead of selling it.
  local spare = (self.spare or {}).diesel or 0
  if fuelled > 0 and spare > 0 then
    local covered = math.min(1, spare / math.max(1, fuelled / 4))
    total = total - fuelled * 0.4 * covered
  end
  return math.max(0, total), by
end

-- Fuel for the reactors. A nuclear plant costs almost nothing to run per unit
-- and a great deal to keep standing, which is why its bill is split in two:
-- this line, and the upkeep it owes whether it generates or not.
function City:fuelBill()
  local total = 0
  for _, n in ipairs(self.g:nodesOfKind("source")) do
    local trade = City.trade[n.commodity or "water"] or City.trade.water
    local rate = n.fuel or trade.fuelPerUnit
    if rate and rate > 0 then
      total = total + ((self.produced or {})[n.id] or 0) * rate
    end
  end
  return total
end

function City:expenseBreakdown()
  local b = { office = 6, sources = 0, structures = 0, pipes = 0, crews = 0 }
  for _, n in ipairs(self.g:aliveNodes()) do
    if n.kind == "source" then
      local trade = City.trade[n.commodity] or City.trade.water
      b.sources = b.sources + (n.upkeep or trade.sourceUpkeep) + ((n.level or 1) - 1) * 2
    elseif n.kind == "works" then
      b.structures = b.structures + ((City.RECIPES[n.recipe or ""] or {}).upkeep or 20)
    elseif n.kind == "dc" then b.structures = b.structures + 12
    elseif n.kind == "terminal" then b.structures = b.structures + City.terminalUpkeep
    elseif n.kind == "depot" then b.structures = b.structures + 3
    elseif n.kind == "tower" then b.structures = b.structures + 2
    elseif n.kind ~= "client" then b.structures = b.structures + 1 end
  end
  b.imports = self:importBill()
  b.haulage = self:haulageBill()
  b.hubs = self:distributionBill()
  b.fuel = self:fuelBill()
  b.pumping = self:pumpingBill()
  b.transit = self:transitBill()
  for _, e in ipairs(self.g.edges) do
    if e.alive then b.pipes = b.pipes + self:pipeUpkeep(e) end
  end
  b.crews = (self.crews or 0) * City.crewWage + self:orderWages()
  b.interest = self:loanInterest()
  b.total = math.ceil(b.office + b.sources + b.structures + b.pipes + b.crews
    + b.interest + b.imports + b.haulage + b.fuel + b.pumping + b.hubs + b.transit)
  return b
end

function City:dailyExpenses()
  return self:expenseBreakdown().total
end

function City:hireCrew()
  if (self.crews or 0) >= City.crewMax then return nil, "no more crews available" end
  if City.crewHire > self.money then return nil, "not enough cash" end
  self:spend(City.crewHire)
  self.crews = (self.crews or 0) + 1
  self:note("Maintenance crew hired: %d on the books at $%d a day each",
    self.crews, City.crewWage)
  return true
end

function City:dismissCrew()
  if (self.crews or 0) <= 0 then return nil, "no crews on the books" end
  self.crews = self.crews - 1
  self:note("Maintenance crew stood down: %d remaining", self.crews)
  return true
end

City.MILESTONES = require("data.progression").MILESTONES

function City:awardMilestones()
  local count, total = 0, 0
  for _, c in ipairs(self:clientList()) do
    if c.alive and self:fullyServed(c) then count = count + 1 end
  end
  for i, m in ipairs(City.MILESTONES) do
    if not self.milestones[i] and count >= m.target then
      self.milestones[i] = true
      self.money = self.money + m.reward
      total = total + m.reward
      self:note("%s: $%d municipal grant", m.name, m.reward)
    end
  end
  return total
end

require("people")(City)
require("infrastructure")(City)
require("road_model")(City)
require("ideas")(City)
require("resilience")(City)
require("upgrades")(City)
require("distribution")(City)
require("costs")(City)
require("terrain_life")(City)

return City
