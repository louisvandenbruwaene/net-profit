-- Edit these values, then restart the game with make run. See EDITING.md.
local Data = {}

Data.UNLOCKS = {
  everyday = { clients = 3,  name = "Treatment, valves and storage" },
  hub      = { clients = 12, name = "Distribution hubs" },
  -- Brine is a coastal, four-figure project, not something to offer a company
  -- that has not yet connected its first street.
  seawater = { clients = 6, name = "Sea pumps and purifiers" },
  works    = { licences = 2, name = "Works" },
  haven    = { clients = 9,  name = "Havens" },
  yard     = { haven = true, name = "Bulk freight" },
  orders   = { clients = 6,  name = "Departments" },
  massive  = { clients = 15, name = "Massive mains" },
  -- A trunk main is what a company lays when it has one source big enough to
  -- fill one, so it waits for the works on running water as well as for the
  -- customers. Sinking wells will never open it, however many there are.
  trunk    = { clients = 30, intake = true, name = "Trunk mains" },
  -- The people network opens as there are people to move, and not before:
  -- nothing to toll, fuel or fly until somebody lives somewhere.
  roads    = { population = true, name = "Roads and stops" },
  routes   = { road = true, name = "Passenger routes" },
  fuel     = { road = true, name = "Filling stations and cars" },
  resort   = { passengers = true, name = "Resorts" },
  internet = { reactor = true, name = "Data centres and the internet" },
}

-- Tools arrive one at a time, by customers signed. The well and the T split
-- are there from the start; anything not listed follows its unlock above.
Data.TOOL_UNLOCK = {
  { tool = "pump",       clients = 4,  name = "Pump" },
  { tool = "depot",      clients = 5,  name = "Tank" },
  { tool = "gate",       clients = 7,  name = "Valve" },
  { tool = "filtration", clients = 8,  name = "Filter" },
  { tool = "binder",     clients = 10, name = "Binder" },
  { tool = "lab",        clients = 12, name = "Env. lab" },
}
-- The next trade's chip shows from this many customers.
Data.NEXT_TRADE_AT = 5
-- Roads and routes wait for this many customers, even where people live.
-- The same as the first shop, which needs a road to stand on.
Data.ROADS_AT = 6
-- Projects and shops show, dim, this many customers before they open.
Data.TEASE = 4
-- Leaks ramp up over the first days, so an opening is not a repair bill.
Data.GENTLE_DAYS = 14

Data.MILESTONES = {
  {name = "First supply", target = 1, reward = 60},
  {name = "Neighbourhood utility", target = 5, reward = 150},
  {name = "City supplier", target = 10, reward = 350},
  {name = "Utility empire", target = 20, reward = 800},
}

Data.ORDERS = {
  surveyors   = { name = "Surveyors",   hire = 420,  wage = 20, clients = 6,
                  blurb = "Shows deposits on land you do not own." },
  dispatchers = { name = "Scouts",      hire = 900,  wage = 30, clients = 12,
                  blurb = "Each scout reveals one more ring of regions around your land, up to four." },
  analysts    = { name = "Market analysts", hire = 1000, wage = 25, clients = 0,
                  blurb = "+10 percentage points expected return per analyst, +1 per week of service; wages grow 1% weekly." },
}

Data.ORDER_LIST = { "surveyors", "dispatchers", "analysts" }

Data.PERMITS = {
  park    = { name = "Parkland easement",  cost = 760,  cross = 1.0, order = 1 },
  river   = { name = "River works charter", cost = 1500, cross = 1.6, order = 2 },
  bedrock = { name = "Blasting licence",    cost = 2900, cross = 4.0, order = 3 },
}

return Data
