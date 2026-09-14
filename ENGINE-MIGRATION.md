# Engine assessment

Godot with GDScript is my recommendation for Net Profit's stated goal: editing a 2D management game through visible properties, short gameplay scripts and replaceable assets. The installed engine reports Godot 4.7 stable. This document is an assessment; the playable game still runs in LÖVE, and no Godot port is represented as complete.

The inspected source has roughly 14,000 Lua lines, including an archived contract game, automated walkthroughs, procedural drawing and the active company simulation. Before the editing refactor, `city.lua` alone had 4,323 lines. The migration must preserve shared graph behaviour while leaving the optional archived contract mode out of the initial company port unless it is explicitly wanted.

## The editing experience to build

Select a building definition such as `turbine.tres` in Godot's FileSystem dock. Its Inspector should expose construction cost, daily upkeep, output, inputs, unlock conditions and its scene. A household definition should expose demand, payment and patience. An economy resource should expose starting cash, interest and maintenance parameters. Small resource scripts define those fields once; routine edits happen in the Inspector.

Each building should use a reusable `.tscn` scene with external artwork. Replacing an assigned image changes its appearance without editing loading code. Interface panels should be Control scenes with container layouts, so moving a button or changing spacing is an editor task.

Keep simulation code independent of scene nodes: separate scripts for network flow, construction, production, day accounting, progression, world generation, transport and persistence. Signals connect those systems to the interface. Simply translating the existing giant files into giant GDScript files would not deliver the requested improvement.

Godot supports this through [custom Resources](https://docs.godotengine.org/en/stable/tutorials/scripting/resources.html) and [exported Inspector properties](https://docs.godotengine.org/en/stable/tutorials/scripting/gdscript/gdscript_exports.html). GDScript is one of its [official scripting languages](https://docs.godotengine.org/en/stable/getting_started/step_by_step/scripting_languages.html); Lua is not a built-in drop-in replacement. The proposed approach ports the simulation rather than adding a Lua compatibility layer to maintain.

Unity is also capable of separating editable data from behaviour. For this project's modest 2D presentation and the preference for simple scripts, I would choose Godot/GDScript over introducing a Unity/C# workflow. Staying with LÖVE has the lowest conversion cost and now offers focused value files, but a visual scene and property editor would still have to be added. These are project-specific judgments, not a claim that any engine eliminates programming.

## Migration sequence and acceptance criteria

1. **Capture reference behaviour.** Export deterministic scenarios from the Lua game: topology, capacities, production, revenues, expenses, reputation and resulting state. Include failed construction, shortages and purchases. Retain the original as the behavioural reference.
2. **Build the opening in Godot.** Use real scenes and Inspector-editable resources. Implement a well, junction, household, pipe quotes and endpoint constraints, contracts, closing a day, reports, undo and camera controls. Check calculated results against those scenarios. This is a playable milestone, not full game parity.
3. **Port the complete company simulation.** Add every commodity and recipe, terrain and permits, procedural expansion and islands, freight and storage, hubs, population and transit, staffing, credit, progression, service problems and bankruptcy. Preserve the topology-aware flow solver, including shared node capacity and recipe dependency order.
4. **Move saves deliberately.** Export Lua saves to an engine-neutral data format using the existing loader, validate their topology and fields, and import copies into a separate Godot save directory. Preserve IDs, ownership, RNG state, contracts, pipe state, history and all six slots. Do not execute Lua save files in Godot or overwrite original companies during development. Compare several subsequent day closes after import, not only the initial balances.
5. **Verify the finished game.** Repeat the opening walkthrough, company switching, failed-save regressions, prolonged simulations, multi-trade supply checks and small-window interface checks. Profile a large late-game city. Only designate the Godot build as the replacement after those pass.

The main conversion risk is silently simplifying the simulation while reproducing its appearance. An opening-only remake would omit much of the existing game. The review changes already made separate 39 balance definitions into seven files without changing their default values, creating a clearer source for future Godot resources.

## Review findings addressed

- Company switching and creation previously continued after failing to save the current company. They now stop and report the failure; a failed write of a new company also preserves the active company in memory.
- Quitting after a failed save previously discarded unsaved state. The application now remains open and reports the failure.
- Unreadable-as-a-company save contents previously appeared as an empty slot. Damaged slots are now shown as occupied with an error, and empty-slot selection skips them.
- A damaged startup save previously caused a fresh company to be constructed and subsequently autosaved over that slot. The original slot is now protected from autosave, and the company picker opens for selecting another slot.
- A duplicate `terminalUpkeep` assignment was removed during extraction of the balance data.

This review does not certify every rule or every filesystem failure path. In particular, cross-directory save mirroring still uses its original best-effort writes; the new tests cover application handling of primary save failures and damaged slot contents.
