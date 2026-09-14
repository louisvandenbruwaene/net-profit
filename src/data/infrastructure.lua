-- Everyday engineering and environmental balance. Distances are map metres.
return {
  kinds = {
    filtration={name="FILTRATION",ports=2,throughput=999,cost=180,color={0.42,0.85,0.83}},
    binder={name="PIPE BINDER",ports=6,throughput=9999,cost=650,color={0.72,0.76,0.84}},
    transformer={name="TRANSFORMER",ports=6,throughput=9999,cost=260,color={0.82,0.67,0.98}},
    pylon={name="POWER PYLON",ports=3,throughput=9999,cost=65,color={0.80,0.65,0.96}},
    lab={name="ENVIRONMENT LAB",ports=2,throughput=999,cost=2200,color={0.54,0.85,0.53}},
  },
  -- Range grows with voltage the way it does on a real grid: the same power at
  -- ten times the voltage needs a tenth of the current, so the resistive loss
  -- that limits a run falls a hundredfold. A street cable stops at a few
  -- hundred metres, a distribution feeder crosses a district, a transmission
  -- line crosses the map.
  voltages={
    low={name="Low voltage",kv=0.4,range=140},
    medium={name="Distribution",kv=11,range=1600},
    high={name="Transmission",kv=110,range=8000},
  },
  voltageOrder={"low","medium","high"},
  voltageCost={low=1,medium=1.3,high=2}, -- multiplier on tie-ins, trench and bore
  -- Three-phase AC, unity power factor. One simulation unit is 100 kW.
  amps={small=500,medium=1250,large=2500,massive=5000},
  resistance={small=0.12,medium=0.06,large=0.03,massive=0.015}, -- ohm/km
  transformerRange=90, binderRange=95, pumpRange=950,
  water={diameter={small=0.05,medium=0.08,large=0.12,massive=0.24},head=30,pumpHead=95,friction=0.025},
  filterRisk=0.25,
  binderPrices={1800,5000,12000}, binderClients={12,20,30},
  pollution={stopAt=30,pipeFactor=0.7,shipRisk=0.035,shipFactor=0.45,
    rigPerDay=0.8,decay=0.3,cleanup=8,labUpkeep=24},
  farmRadius=140,
  farmRecipes={
    crops={name="CROP FARM",makes="wheat",rate=12,cost=1400,upkeep=16,
      inputs={water=3,oil=0.1,power=0.2},materials={},farm=true,
      blurb="Large fields. Uses 36 water, 1.2 oil and 2.4 power daily at full output."},
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
