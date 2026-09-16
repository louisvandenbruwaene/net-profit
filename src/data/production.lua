-- Edit these values, then restart the game with make run. See EDITING.md.
local Data = {}

Data.RECIPES = {
  -- Electricity is the first thing a company can make for itself, and the only
  -- one that needs nothing but water. Everything else on this list needs
  -- electricity, which is why it comes first and why a turbine hall is cheap.
  turbine    = { name = "TURBINE HALL",   makes = "power",  rate = 8,  cost = 800,  upkeep = 14,
                 inputs = { water = 2 }, materials = {},
                 blurb = "Water in, electricity out. The one works that needs nothing you do not already have." },

  -- Everything else needs a chain, and the chain is the game. A works with an
  -- input missing makes nothing at all: there is no half recipe and no way to
  -- fake the thing it is short of.
  maltings   = { name = "MALTINGS",       makes = "malt",   rate = 10, cost = 1400, upkeep = 14,
                 inputs = { wheat = 1, water = 1, power = 1 }, materials = { steel = 20 },
                 blurb = "Wheat, water and power become what a brewery actually wants." },
  brewery    = { name = "BREWERY",        makes = "beer",   rate = 10, cost = 1800, upkeep = 20,
                 inputs = { malt = 1, water = 2, power = 1 }, materials = { steel = 20 },
                 blurb = "Malt, water and power. Beer is the end of the longest chain in the game and it pays like it." },
  foodworks  = { name = "FOODWORKS",      makes = "food",   rate = 10, cost = 1300, upkeep = 16,
                 inputs = { wheat = 1, salt = 1, water = 1, power = 1 }, materials = {},
                 blurb = "Wheat, salt, water and power. Nobody mines salt here, so a haven is part of the recipe." },
  refinery   = { name = "REFINERY",       makes = "diesel", rate = 6,  cost = 2200, upkeep = 22,
                 inputs = { oil = 2, power = 1 }, materials = { steel = 30, concrete = 20 },
                 blurb = "Your own crude becomes your own fuel, and the haulage bill drops." },
  sawmill    = { name = "SAWMILL",        makes = "planks", rate = 6,  cost = 1600, upkeep = 16,
                 inputs = { timber = 2, power = 1 }, materials = { steel = 20 },
                 blurb = "Parkland becomes timber becomes planks." },
  steelworks = { name = "STEELWORKS",     makes = "steel",  rate = 4,  cost = 3600, upkeep = 38,
                 inputs = { ore = 2, coke = 1, power = 3 }, materials = { steel = 60, concrete = 40 },
                 blurb = "Ore from the frontier and coke off a ship. Everything the company builds is made of this." },
  glassworks = { name = "GLASSWORKS",     makes = "glass",  rate = 4,  cost = 2200, upkeep = 20,
                 inputs = { sand = 2, power = 2 }, materials = { steel = 30, concrete = 20 },
                 blurb = "Coastal sand, and a furnace." },
  cementworks= { name = "CEMENT WORKS",   makes = "cement", rate = 5,  cost = 2400, upkeep = 22,
                 inputs = { rock = 2, power = 2 }, materials = { steel = 30, concrete = 20 },
                 blurb = "Bedrock stops being a wall and becomes the other half of concrete." },
  concrete   = { name = "CONCRETE PLANT", makes = "concrete", rate = 6, cost = 1900, upkeep = 18,
                 inputs = { cement = 1, sand = 2, water = 1 }, materials = { steel = 20 },
                 blurb = "Cement, sand and water. Half of every big building on the map." },

  -- Water's second source. It takes nothing off the network -- the sea is the
  -- input, and the sea is not modelled as a commodity -- so it never competes
  -- with a well for anything but the ground it stands on, which is why it
  -- answers to no deposit and the map's one truly endless input.
  purifier   = { name = "PURIFICATION CENTRE", makes = "water", rate = 16, cost = 2600, upkeep = 24,
                 inputs = {saltwater=1}, coproduct="salt", materials = { steel = 20, concrete = 20 },
                 blurb = "Piped saltwater becomes equal quantities of clean water and salt. Place on any owned land." },

  -- The businesses a population opens. Each is hidden until there is somebody
  -- to sell to: nobody refines petrol for a city with no roads.
  petrolworks= { name = "PETROL WORKS",   makes = "gasoline", rate = 8, cost = 2400, upkeep = 22,
                 inputs = { oil = 2, power = 1 }, materials = { steel = 30, concrete = 20 }, unlock = "fuel",
                 blurb = "Crude becomes what every car in the city burns, sold at your filling stations." },
  carworks   = { name = "CAR WORKS",      makes = "cars",   rate = 3,  cost = 5200, upkeep = 40,
                 inputs = { steel = 2, glass = 1, rubber = 1, power = 3 }, materials = { steel = 60, concrete = 40 },
                 unlock = "fuel",
                 blurb = "Steel, glass, imported rubber and power. Cars reaching a yard are sold to the districts, and more drivers pay more tolls and buy more petrol." },
  datacentre = { name = "DATA CENTRE",    makes = "internet", rate = 20, cost = 9000, upkeep = 70,
                 inputs = { water = 2, power = 3 }, materials = { steel = 80, concrete = 60 }, unlock = "internet",
                 blurb = "Drinks water and power by the tanker-load and puts out the internet, cabled to subscribers like power to a workshop." },
}

Data.RECIPES.jeweler={name="JEWELER",makes="jewelry",rate=2,cost=8000,upkeep=35,inputs={gems=1,power=1},materials={steel=30},blurb="Rare gems become valuable jewelry. Deliver to a depot yard for sale."}
Data.EXTRACTORS = {
  well     = { out = "water",  name = "WELL",       on = "deposit",
               tip = "Only on a marked water deposit." },
  rig      = { out = "oil",    name = "RIG",        on = "deposit",
               tip = "Only on a marked oil deposit." },
  mine     = { out = "ore",    name = "MINE",       on = "deposit",
               tip = "Only on a marked ore deposit, and the ore is out on the frontier." },
  farm     = { out = "wheat",  name = "FARM",       on = "archetype", archetype = "farm",
               tip = "Only on farmland. Buy ground out where the city thins out." },
  forestry = { out = "timber", name = "FORESTRY",   on = "obstacle",  obstacle = "park",
               tip = "Only on parkland, which needs the parkland easement first." },
  quarry   = { out = "rock",   name = "QUARRY",     on = "obstacle",  obstacle = "bedrock",
               tip = "Only on bedrock, which needs the blasting licence first." },
  pit      = { out = "sand",   name = "SAND PIT",   on = "coast",
               tip = "Only within 150m of the coast, or on an island." },
}

Data.PLANTS = {
  nuclear = { name = "NUCLEAR PLANT", base = 3600, growth = 1.35, output = 45,
              upkeep = 52, fuel = 0.55, ground = "land",
              blurb = "High build cost. Produces electricity." },
  wind    = { name = "WIND PARK",     base = 1800, growth = 1.28, output = 12,
              upkeep = 14, fuel = 0,   ground = "island",
              blurb = "Requires an island. Produces electricity. No fuel needed." },
}

Data.sourceMaxLevel = 6

Data.sourcePorts = 4

Data.seamRange = 70

return Data
