# Editing Net Profit

Most everyday balance changes now live in `src/data/`. These files contain values and descriptions, without drawing, input, loading or saving code.

| What you want to change | File | Examples |
| --- | --- | --- |
| Money and running costs | `src/data/economy.lua` | `rules.startMoney`, `price.junction`, `trade.water.sourceBase`, loan interest, crew wages |
| Pipes and connections | `src/data/pipes.lua` | capacities, lining costs, leakage modifiers, endpoint size limits |
| Engineering, farms and environment | `src/data/infrastructure.lua` | tower spacing, booster distances, upgrade prices, customer voltages, amperage, pump head, filtration, pollution, cleanup and farm recipes |
| Terrain size and frequency | `src/data/terrain.lua` | park and mountain size ranges, massive obstacle chance and distance from the start |
| Customers | `src/data/customers.lua` | daily rates, demand ranges, patience, spawn weights |
| Factories and sources | `src/data/production.lua` | recipes, inputs, output, construction cost, extractors and power plants |
| Freight and storage | `src/data/freight.lua` | transport modes, hubs, havens, material bills and warehouse limits |
| Unlocks and rewards | `src/data/progression.lua` | customer thresholds, municipal grants, departments and permits |
| Population and transport | `src/data/population.lua` | settlement, trips, fares and passenger routes |

For example, change `startMoney = 750` to `startMoney = 1000` in `economy.lua`. Restart with `make run` and create a company in an empty slot to try the new opening. An existing company's cash is saved, so changing starting money does not change its bank balance.

To make households pay more, change the `house` entry's `rate = 6` in `customers.lua`. Newly generated households use the new value; existing customers retain their saved contracts. Built pipes retain purchased capacities and sources retain their saved output. Factory recipe rates and inputs are read from the definitions, so those changes also affect existing factories after restarting. Use a new company for a clean balance comparison.

## The shape of a network

Four numbers decide whether a company grows a branching tree or a spiderweb of point-to-point mains, and they are worth understanding together before any of them is moved.

`trench` in `pipes.lua` follows **Murray's law**, the small-vessel half of the West/Brown/Enquist model of vascular networks. Minimising pumping power against the cost of maintaining the fluid gives `Q ~ r^3`, so cross-section, and with it the dig, goes as `Q^(2/3)`. Keeping the four sizes on that curve (1.00, 2.08, 2.92, 4.64) is what makes one trunk that splits cheaper than two mains laid side by side. Flatten the curve and every rung above SMALL becomes a trap. Steepen it and nobody lays a trunk at all.

`reach` in the same table is the other half of the physics. Pressure gradient goes as `Q/r^4`, so at each size's design flow it falls as `Q^(-1/3)`, and a trunk runs further between pumps than a stub does. These multipliers are checked against the Darcy-Weisbach model in `City:waterRating`, which throttles a main that is asked to carry its rating too far. Raise `reach` past the point where that model still delivers the full rating and mains will be legal to lay but quietly short on arrival.

`upgradeGrowth` in `economy.lua` sits **below** `sourceGrowth` in every trade. That inversion is what makes growing a source the cheaper unit of supply at the margin, and it is the reason a company settles on one deep source and two or three shallow ones rather than a dozen identical wells. Put `upgradeGrowth` back above `sourceGrowth` and the sprawl returns immediately.

`City.INTAKE` in `city.lua` is the heart. A water source standing within `reach` of the river or the coast is a treatment works rather than a well: its ceiling is `riverBase + riverPerHalf * halfWidth`, so a broad estuary hosts a city's whole supply and a headwater branch does not. It is finite, like every other source, and sized against what two MASSIVE mains can carry out of it. Ordinary wells stay capped at `wellCap` in `infrastructure.lua`, which is what keeps them accessory organs.

Plants follow the same rule through `unitBase`, `unitGrowth`, `unitStep` and `maxUnits` in `production.lua`: another reactor on a commissioned site reuses the grid connection, the cooling and the crew, so it is always cheaper per megawatt than a second site.

In recipes, `inputs` are **per output unit**: crop farm output `rate = 12` with `water = 3` consumes 36 water per day at full production. Costs are dollars; probabilities such as `leakBase = 0.07` mean 7%. Keep pipe sizes in ascending capacity order and recipe chains acyclic. Keep existing keys such as `water`, `house` and `turbine`: rules and old saves use those identifiers.

Run `make test` after an edit. Some tests deliberately assert the current balance, so an intentional balance change may require updating those expectations after checking its effect. `make smoke` exercises the real interface with isolated test companies. `make run` runs source edits immediately; the installed app requires `make mac-install` to rebuild it.

Colours live in `src/palette.lua` and commodity colours in `src/graph.lua`. Much of the current map art is drawn procedurally in `src/company_render.lua`; there is no individual building PNG to replace yet. This is one reason an engine migration should include reusable building scenes with external textures.

These files cover common balance edits, not every game rule. Adding an entirely new mechanic still needs simulation and interface changes. World generation settings remain in `src/city.lua`, and goals and presentation helpers live in `src/experience.lua`.

## September requirements

See [IDEAS-IMPLEMENTATION.md](IDEAS-IMPLEMENTATION.md) for the new rules and their controls. Staffing, daily land offers, saltwater validation and migration are in `src/ideas.lua`. Temporary autoplay is in `src/autoplay.lua`; its regression tests use isolated companies. The primary app logo is `assets/net-profit.png`; `assets/net-profit.icns` must be an actual macOS icon container, not a renamed PNG.

## Levels, shocks and secure contracts

**Levels** (`src/data/upgrades.lua`, logic in `src/upgrades.lua`). Junctions, towers, automation hubs and pumps are one building each with four levels. A new one starts at level 1 and is grown in place: `ports`, `throughput`, `reach` (towers and pumps) and `radius` (hubs) per level, `cost` to reach it, and `clients` the company must have signed before it is allowed. A junction becomes a manifold (a six port hub) at level 2 and keeps every main tied in. Towers scale throughput by the voltage they carry (`TOWER_SCALE`). `LEGACY` is the level a building from an older save counts as. Saves need no migration because a level only ever adds to what a building already has, and reach only counts once a building has been upgraded. The old kinds (`manifold`, `pole`, `pylon`, `hvtower`) still exist in saves and tests; the build panel sells one Junction and one Tower, and the tower's voltage is chosen above the tools.

**Shocks** (`src/data/resilience.lua`, logic in `src/resilience.lua`). Droughts and grid faults hold a trade's sources to a fraction of their output for a few days; a ground shift cracks the mains around one point. Nothing lands before `SHOCK_CLIENTS` customers or day `SHOCK_FROM`, and never more often than `SHOCK_CHANCE` a day. Shocks are rolled from a hash of the seed and the day and never from `City:random()`, so they do not reshuffle a save's offers and leaks.

**Secure contracts.** `SECURE.share` percent of new offers pay `SECURE.rate` times the going rate, refund `SECURE.credit` times the missing revenue for every short day, and leave after `SECURE.patience` short days. Hubs and autoplay never sign them on the player's behalf.

**The Advisor** (Stats, then Advisor). *Check resilience* fails each loaded main and structure in turn on a copy of the company (`City:startResilience`, run a little each frame) and grades the worst single failure, A to F by `GRADES`. *Best next upgrades* (`experience.lua`, `E.advise`) does each candidate upgrade on a copy and ranks by payback. Neither changes the company. Upgrade buttons elsewhere quote what the upgrade would earn when pointed at.
