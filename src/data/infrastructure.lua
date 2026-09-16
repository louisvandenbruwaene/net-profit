-- Everyday engineering and environmental balance. Distances are map metres.
return {
  kinds = {
    filtration={name="FILTRATION",ports=2,throughput=999,cost=180,color={0.42,0.85,0.83}},
    binder={name="PIPE BINDER",ports=6,throughput=9999,cost=650,color={0.72,0.76,0.84}},
    hvtower={name="HIGH VOLTAGE TOWER",ports=4,throughput=9999,cost=160,color={0.88,0.62,1.00}},
    pylon={name="STANDARD TOWER",ports=4,throughput=9999,cost=65,color={0.80,0.65,0.96}},
    pole={name="LOW VOLTAGE POLE",ports=4,throughput=9999,cost=25,color={0.70,0.66,0.90}},
    -- Only found in saves from before tower upgrades; loading turns each one
    -- into a tower fitted with a transformer.
    transformer={name="TRANSFORMER",ports=6,throughput=9999,cost=260,color={0.82,0.67,0.98},legacy=false},
    lab={name="ENVIRONMENT LAB",ports=2,throughput=999,cost=2200,color={0.54,0.85,0.53}},
  },
  -- The voltage each tower carries.
  towers={hvtower="high",pylon="medium",pole="low"},
  -- span: the longest cable between two structures at this voltage.
  -- boost: the most cable after a generator, transformer or booster before the
  -- next one is needed. Higher voltage carries the same power on less current,
  -- so it loses less and runs further, as on a real grid.
  voltages={
    low={name="Low voltage",kv=0.4,span=150,boost=300,tower="pole"},
    medium={name="Medium voltage",kv=11,span=200,boost=1000,tower="pylon"},
    high={name="High voltage",kv=110,span=300,boost=2500,tower="hvtower"},
  },
  voltageOrder={"low","medium","high"},
  -- What each power customer takes. Every customer not listed, and every
  -- works, hub and depot yard, takes medium voltage.
  customerVoltage={home="low",house="low",estate="low"},
  -- A tower holds one upgrade. A transformer lets it take cables at its own
  -- voltage and every lower one, and it is the only way to connect customers.
  -- A booster restarts the booster distance on its own voltage.
  upgrades={
    transformer={name="Transformer",ports=6,cost={hvtower=900,pylon=260,pole=90}},
    booster={name="Booster",cost={hvtower=600,pylon=150,pole=45}},
  },
  voltageCost={low=1,medium=1.3,high=2}, -- multiplier on tie-ins, trench and bore
  -- Three-phase AC, unity power factor. One simulation unit is 5 kWh delivered over a 24-hour day.
  amps={small=500,medium=1250,large=2500,massive=5000},
  resistance={small=0.12,medium=0.06,large=0.03,massive=0.015}, -- ohm/km
  binderRange=95, pumpRange=950,
  water={diameter={small=0.05,medium=0.08,large=0.12,massive=0.24},head=30,pumpHead=95,friction=0.025},
  filterRisk=0.25,
  binderPrices={1800,5000,12000}, binderClients={12,20,30},
  pollution={stopAt=30,pipeFactor=0.7,shipRisk=0.035,shipFactor=0.45,
    rigPerDay=0.8,decay=0.3,cleanup=8,labUpkeep=24},
  farmRadius=140,
  farmRecipes={
    crops={name="CROP FARM",makes="wheat",rate=12,cost=1400,upkeep=16,
      inputs={water=3,oil=0.1,power=0.2},materials={},farm=true,
      blurb="Large fields. Uses 36 water, 1.2 oil and 12 kWh daily at full output."},
    dairy={name="DAIRY FARM",makes="food",rate=8,cost=1800,upkeep=22,
      inputs={water=4,wheat=1,oil=0.1,power=0.3},materials={},farm=true,product="Milk",
      blurb="Milk for food customers. Requires water, feed, oil and electricity."},
    poultry={name="POULTRY FARM",makes="food",rate=8,cost=1600,upkeep=20,
      inputs={water=3,wheat=1,oil=0.1,power=0.2},materials={},farm=true,product="Eggs and chicken",
      blurb="Eggs and chicken for food customers. Requires water, feed, oil and electricity."},
    pigs={name="PIG FARM",makes="food",rate=10,cost=2200,upkeep=26,
      inputs={water=4,wheat=2,oil=0.1,power=0.2},materials={},farm=true,product="Pork",
      blurb="Pork for food customers. Requires water, feed, oil and electricity."},
    cattle={name="CATTLE FARM",makes="food",rate=12,cost=3000,upkeep=32,
      inputs={water=5,wheat=3,oil=0.1,power=0.3},materials={},farm=true,product="Beef",
      blurb="Beef for food customers. Heavy water and feed demand."},
  },
}
