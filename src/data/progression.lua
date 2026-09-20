-- Edit these values, then restart the game with make run. See EDITING.md.
local Data = {}

Data.UNLOCKS = {
  everyday = { clients = 3,  name = "Treatment, valves and storage" },
  hub      = { clients = 6,  name = "Automation hubs" },
  -- Brine is a coastal, four-figure project, not something to offer a company
  -- that has not yet connected its first street.
  seawater = { clients = 6, name = "Sea pumps and purifiers" },
  works    = { licences = 2, name = "Works" },
  haven    = { clients = 9,  name = "Havens" },
  yard     = { haven = true, name = "Depot yards and bulk freight" },
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

Data.MILESTONES = {
  {name = "First supply", target = 1, reward = 60},
  {name = "Neighbourhood utility", target = 5, reward = 150},
  {name = "City supplier", target = 10, reward = 350},
  {name = "Utility empire", target = 20, reward = 800},
}

Data.ORDERS = {
  surveyors   = { name = "Surveyors",   hire = 420,  wage = 20, clients = 6,
                  blurb = "Shows deposits on land you do not own." },
  dispatchers = { name = "Dispatchers", hire = 900,  wage = 30, clients = 12,
                  blurb = "Accepts requests that meet your minimum price." },
  engineers   = { name = "Engineers",   hire = 1600, wage = 45, clients = 20,
                  blurb = "Replaces pipes after 3 full days. You pay the build cost." },
  estates     = { name = "Estates",     hire = 2600, wage = 60, clients = 32,
                  blurb = "Buys nearby land. Keeps the cash reserve you set." },
}

Data.PERMITS = {
  park    = { name = "Parkland easement",  cost = 760,  cross = 1.0, order = 1 },
  river   = { name = "River works charter", cost = 1500, cross = 1.6, order = 2 },
  bedrock = { name = "Blasting licence",    cost = 2900, cross = 4.0, order = 3 },
}

return Data
