# Infrastructure and production

The [September implementation guide](IDEAS-IMPLEMENTATION.md) contains the current rules from `ideas.rtf` and supersedes older balance and automation descriptions.

These rules apply to newly built equipment. Existing companies retain their installed legacy cables, source connections, wheat sources and turbine works, so the update does not dismantle working networks.

## Water

A new well has one outlet and produces 20 units; upgrades raise that to 30, 40 and 50. Route it through a three-connection T split or six-connection pipe hub to distribute water. Hubs and splits accept different pipe sizes. A two-connection pump extends the permitted route to 950 map metres and raises the design pressure head from 30 to 95 metres. Pipe diameter and length now limit usable water capacity.

A two-connection filtration plant protects downstream water pipes from new mineral buildup. Untreated pipes accumulate one point per day; deposits become harmful around day 100 and reset on repair or replacement. Incoming raw-water mains remain untreated, and raw-water bypasses defeat downstream protection. Existing pipes gain protection when the supplied network changes.

Pipe binders connect nearby equipment within 95 metres and bundle two identical parallel pipes into one connection at the equipment. Binder-to-binder routes use normal pipe ranges. Upgrade to three, four or five lanes for $1,800, $5,000 and $12,000, after reaching 12, 20 and 30 customers. Each lane still costs money and has finite capacity.

## Electricity

Power travels on three kinds of tower, and each tower carries one voltage.

| Tower | Voltage | Tower spacing | Booster distance |
| --- | --- | --- | --- |
| High voltage tower | 110 kV | 300 m | 2,500 m |
| Standard tower | 11 kV | 200 m | 1,000 m |
| Low voltage pole | 0.4 kV | 150 m | 300 m |

A cable can be no longer than the tower spacing of its voltage. Generators send out high voltage, so the first cable from a generator goes to a high voltage tower. Water fittings cannot carry electrical connections.

A tower holds one upgrade. A transformer lets the tower take cables at its own voltage and at every lower voltage, so a high voltage tower with a transformer steps down onto standard towers or poles. A booster restarts the booster distance on the tower's own voltage, and generators and transformers restart it too. A cable is refused if it would put any structure further than the booster distance from its nearest generator, transformer or booster. If a booster is lost later, the cables past it show NO BOOSTER and carry nothing until a tower closer to the supply is upgraded.

Customers connect to a tower with a transformer at their own voltage, or a standalone six-connection transformer within 95 m. Standalone transformers accept all three voltages. Homes take low voltage from a low voltage pole. Workshops, works, hubs and depot yards take medium voltage from a standard tower. A high voltage tower never feeds a customer directly. Farms connect at their field boundary. Cable options show current ratings in amperes. Inspect a cable for its voltage, capacity and loss allowance, and a tower for how far it is from the last boost.

Loading an older company turns each pylon into a tower of the voltage it carried and each transformer into a tower with a transformer. Cables laid under the old rules keep working at their installed length.

Reactors, river turbines, wind and solar generate electricity. River turbines require a river bank and do not consume piped utility water. Wind can be built on land or in the coastal sea beside owned mainland; offshore construction and upkeep cost more. Solar requires 12 imported panels: bring panels through the existing haven and storage system before construction.

## Farming and environment

Crop farms produce wheat. Dairy, poultry, pig and cattle farms produce food, labelled as milk, eggs and chicken, pork and beef. Livestock products share the food commodity to keep transport and customer management manageable. Livestock requires wheat feed as well as water, oil and electricity. Inputs are consumed in proportion to actual output; missing supplies limit production.

Farms reserve a clear 280 × 280 m mainland plot within an owned district. The placement preview shows the land requirement. Other buildings cannot occupy the plot. Inspect a farm to see its daily inputs, shortages and output.

Leaking oil routes pollute districts according to oil actually lost from the supplying network. Oil shipping accidents reduce delivered cargo and create pollution along the route. Oil rigs also create ongoing pollution. A district at pollution 30 or above stops water extraction and farm production. An environment lab cleans its own district and the eight surrounding districts, costs $24/day and removes up to eight pollution points per district each day. Natural recovery removes 0.3/day. Pollution and recovery notices appear when production thresholds are crossed.

## Deliberate simplifications

Distances are map metres. Water flow uses a per-segment Darcy–Weisbach design estimate with fixed friction and flat terrain, capped by the purchased pipe rating. This is not a full hydraulic pressure solver. Electrical capacity uses three-phase power at unity power factor, with each internal accounting increment representing 5 kWh delivered over 24 hours, and a conservative resistance-based capacity reduction at rated load. It is not an AC load-flow simulation or a separately metered energy-loss ledger.

Turns represent daily averages: no weather, night cycle, animal growth or seasonal harvest scheduling. Existing wholesale contracts, material inventories and customer economics remain game abstractions. Filtration and lab coverage update with the network to avoid repetitive maintenance orders.

The design follows the physical distinctions described by the [EIA electricity delivery overview](https://www.eia.gov/energyexplained/electricity/delivery-to-consumers.php), [DOE hydropower explanation](https://www.energy.gov/cmei/water/how-hydropower-works), and [DOE pumping guide](https://www.energy.gov/sites/prod/files/2014/05/f16/pump.pdf). Numerical values are game balance choices, not engineering specifications.

Change engineering values, farm recipes and environmental costs in `src/data/infrastructure.lua`. See [EDITING.md](EDITING.md) for the other balance files and how saved equipment responds to edits.

## Grids on the map

Selecting a trade in the build panel keeps its grid at full strength and fades every other grid, people included. Later goods share category grids, so selecting any one of them highlights the whole category: food (food, wheat, malt), metals (ore, coke, steel), stone (rock, sand, cement, concrete), wood (timber, planks), goods (salt, glass, rubber, solar panels, cars), and oil with diesel and gasoline. The categories live in `Graph.GRIDS` in `src/graph.lua`.

## Larger terrain outside the opening

From two regions away, ordinary parks and bedrock vary from small patches to broad obstacles. Distant massive features have 400–850 m radii and can span multiple regions. They stay clear of the nine starting regions. Ordinary features leave a border and avoid the river; massive terrain can span the river. Hidden neighboring features are generated before construction is possible. Existing surveyed terrain remains saved. Change the ranges in `src/data/terrain.lua`; see the September guide for clearing costs, resource yields and gems.


## Daily household electricity

An ampere (A) measures electric current through a cable. A kilowatt (kW) measures power, while a kilowatt-hour (kWh) measures energy: a 1 kW appliance running all day uses 24 kWh. The interface displays electricity in kWh/day, including household requests, generation, factory inputs and cable capacity. Cable energy limits use three-phase power, `sqrt(3) × kV × A × 24 hours`, reduced for resistance.

A household signs for one utility. A second one is a possibility rather than a condition: about a third of houses and estates ever want electricity as well, decided once per building from the company's seed, and one of those asks on any given day the licence is held. Buying the power licence puts the question to the ones that want it; the rest are never asked and are fully supplied by their water alone. The share and the daily rate are `DUAL` in `src/data/customers.lua`.

An electricity request is a separate offer with its own rate, accepted or declined like any other, and only then does the household demand both. A typical house requests 10 kWh/day. Each utility has its own delivery and billing; both must be supplied for a dual household to be satisfied. Hubs aggregate both demands. Generator sizes and prices remain scaled for game balance.

## Roads and daily destinations

Choose the Roads symbol, then Offroad, Normal or Highway. Connect buildings with access roads and use the appropriate junctions:

| Road | Vehicles | Junctions | Payment |
| --- | --- | --- | --- |
| Offroad | Cars only | Offroad intersections | Free |
| Normal road | Cars, trucks, buses | Roundabouts | Free |
| Highway | Cars, trucks, buses | Highway interchanges | Toll per vehicle per segment |

Highway segments connect dedicated interchanges. Normal roads connect buildings and bus stops to those interchanges. Roundabouts and offroad intersections cannot terminate highways. Geometric crossings do not create connections; roads must share a junction.

Each household has a daily car journey; factories, food stores and depots have a daily truck journey. Passenger destinations are houses, workplaces, shops, resorts and bus stops attached to roads, including those in other disconnected components. Water wells, utility fittings and freight-only facilities are not passenger destinations. Truck journeys use freight destinations separately. The choice stays fixed for the day and across saving. A journey takes the shortest compatible road path when one exists. Every vehicle crossing a highway segment pays its toll. Disconnected trips do not generate toll income.

Bus stops are eligible daily destinations for people. Only buses board passengers there. Bus stops attach only to normal roads, and cannot be placed on highway segments. Roads can connect houses directly without bus stops. Buses share those same roads with cars; their service is highlighted along the existing road path rather than drawn as a separate road. Select a bus stop to inspect its bus services. Bus routes require an intact normal-road/highway path and stop carrying passengers when that path breaks. Ferry and airline services retain their own terminals.

## Container trucks and storage

Build normal roads or highways first, then select a commodity and TRUCK to open a container service between depots, factories, food stores, freight sources or havens. Additional containers carry other commodities. Electricity and internet cannot be shipped. Truck services charge for vehicles and handling; the road is built separately. Haulage follows the actual road distance, including detours. Broken roads stop deliveries.

The local goods-road tool builds a normal road with a commodity allocation. That road also participates in daily traffic. Existing freight highways migrate to free normal access roads plus their existing truck service.

Freight-connected storage depots accept a batch when empty, up to their daily intake and storage limits. Delivered cargo is credited at the close of the day; stored cargo can be shipped onward the following day. A depot does not refill itself from its own stock. Highway tolls also count loaded container trucks and the buses operating that day.
