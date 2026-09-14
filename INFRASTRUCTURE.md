# Infrastructure and production

These rules apply to newly built equipment. Existing companies retain their installed legacy cables, source connections, wheat sources and turbine works, so the update does not dismantle working networks.

## Water

A new well has one outlet. Route it through a three-connection T split or six-connection pipe hub to distribute water. Hubs and splits accept different pipe sizes. A two-connection pump extends the permitted route to 950 map metres and raises the design pressure head from 30 to 95 metres. Pipe diameter and length now limit usable water capacity.

A two-connection filtration plant protects new or replaced water pipes in its connected, supplied water network: their maintenance risk is reduced by 75%. Existing pipes retain their installed treatment status. Treatment is a network-level maintenance abstraction; individual fittings do not accumulate mineral deposits.

Pipe binders connect nearby equipment within 95 metres and bundle two identical parallel pipes into one connection at the equipment. Binder-to-binder routes use normal pipe ranges. Upgrade to three, four or five lanes for $1,800, $5,000 and $12,000, after reaching 12, 20 and 30 customers. Each lane still costs money and has finite capacity.

## Electricity

Power travels on three kinds of tower, and each tower carries one voltage.

| Tower | Voltage | Tower spacing | Booster distance |
| --- | --- | --- | --- |
| High voltage tower | 110 kV | 300 m | 2,500 m |
| Standard tower | 11 kV | 100 m | 500 m |
| Low voltage pole | 0.4 kV | 50 m | 100 m |

A cable can be no longer than the tower spacing of its voltage. Generators send out high voltage, so the first cable from a generator goes to a high voltage tower. Water fittings cannot carry electrical connections.

A tower holds one upgrade. A transformer lets the tower take cables at its own voltage and at every lower voltage, so a high voltage tower with a transformer steps down onto standard towers or poles. A booster restarts the booster distance on the tower's own voltage, and generators and transformers restart it too. A cable is refused if it would put any structure further than the booster distance from its nearest generator, transformer or booster. If a booster is lost later, the cables past it show NO BOOSTER and carry nothing until a tower closer to the supply is upgraded.

Customers connect only to a tower with a transformer that carries their own voltage. Homes take low voltage from a low voltage pole. Workshops, works, hubs and depot yards take medium voltage from a standard tower. A high voltage tower never feeds a customer directly. Farms connect at their field boundary. Cable options show current ratings in amperes. Inspect a cable for its voltage, capacity and loss allowance, and a tower for how far it is from the last boost.

Loading an older company turns each pylon into a tower of the voltage it carried and each transformer into a tower with a transformer. Cables laid under the old rules keep working at their installed length.

Reactors, river turbines, wind and solar generate electricity. River turbines require a river bank and do not consume piped utility water. Wind can be built on land or in the coastal sea beside owned mainland; offshore construction and upkeep cost more. Solar requires 12 imported panels: bring panels through the existing haven and storage system before construction.

## Farming and environment

Crop farms produce wheat. Dairy, poultry, pig and cattle farms produce food, labelled as milk, eggs and chicken, pork and beef. Livestock products share the food commodity to keep transport and customer management manageable. Livestock requires wheat feed as well as water, oil and electricity. Inputs are consumed in proportion to actual output; missing supplies limit production.

Farms reserve a clear 280 × 280 m mainland plot within an owned district. The placement preview shows the land requirement. Other buildings cannot occupy the plot. Inspect a farm to see its daily inputs, shortages and output.

Leaking oil routes pollute districts according to oil actually lost from the supplying network. Oil shipping accidents reduce delivered cargo and create pollution along the route. Oil rigs also create ongoing pollution. A district at pollution 30 or above stops water extraction and farm production. An environment lab cleans its own district and the eight surrounding districts, costs $24/day and removes up to eight pollution points per district each day. Natural recovery removes 0.3/day. Pollution and recovery notices appear when production thresholds are crossed.

## Deliberate simplifications

Distances are map metres. Water flow uses a per-segment Darcy–Weisbach design estimate with fixed friction and flat terrain, capped by the purchased pipe rating. This is not a full hydraulic pressure solver. Electrical capacity uses three-phase power at unity power factor, with one power unit representing 100 kW, and a conservative resistance-based capacity reduction at rated load. It is not an AC load-flow simulation or a separately metered energy-loss ledger.

Turns represent daily averages: no weather, night cycle, animal growth or seasonal harvest scheduling. Existing wholesale contracts, material inventories and customer economics remain game abstractions. Filtration and lab coverage are automated to avoid repetitive maintenance orders.

The design follows the physical distinctions described by the [EIA electricity delivery overview](https://www.eia.gov/energyexplained/electricity/delivery-to-consumers.php), [DOE hydropower explanation](https://www.energy.gov/cmei/water/how-hydropower-works), and [DOE pumping guide](https://www.energy.gov/sites/prod/files/2014/05/f16/pump.pdf). Numerical values are game balance choices, not engineering specifications.

Change engineering values, farm recipes and environmental costs in `src/data/infrastructure.lua`. See [EDITING.md](EDITING.md) for the other balance files and how saved equipment responds to edits.

## Grids on the map

Selecting a trade in the build panel keeps its grid at full strength and fades every other grid, people included. Later goods share category grids, so selecting any one of them highlights the whole category: food (food, wheat, malt), metals (ore, coke, steel), stone (rock, sand, cement, concrete), wood (timber, planks), goods (salt, glass, rubber, solar panels, cars), and oil with diesel and gasoline. The categories live in `Graph.GRIDS` in `src/graph.lua`.

## Larger terrain outside the opening

From two regions away, parks and bedrock vary from small patches to large obstacles. From three regions away, some regions can contain a massive mountain range or protected park, covering approximately 40–46% of the region. These areas block direct construction routes until the matching permit is held. Every feature leaves a clear border inside its region and avoids the river, leaving space to plan detours. Existing surveyed terrain stays as saved; explore new regions or start a new company to see the new distribution. Size ranges and frequency live in `src/data/terrain.lua`.
