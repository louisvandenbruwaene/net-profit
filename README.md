# AUGMENT

A roguelike about growing a flow network that survives its own minimum cut.

You start as a single source. Terminals appear across the field, each demanding
its own supply every wave. You buy nodes and lay links to reach them. Then an
adversary computes your minimum cut and severs it.

That last part is the game. Your maximum flow equals the capacity of your
minimum cut, so whatever is cheapest to cut is exactly what limits you, and the
adversary attacks precisely there. One thick trunk is a cut of width one: lose
it and you lose everything. Five thin disjoint routes are a cut of width five:
lose one and you keep four fifths. Redundancy is not caution, it is survival.

Fail to meet demand and the run ends. You keep the theorems you unlocked.

## Running

Needs [LÖVE](https://love2d.org) 11.x (`pacman -S love`).

    make run          # play
    make test         # graph algorithm unit tests (lua5.4, headless)
    make smoke        # input layer driven through the real love callbacks
    make soak         # plays whole runs to collapse with every screen rendered
    make tutorial     # walks all twelve tutorial steps through the real callbacks
    make audio        # peak and RMS of every synthesised sound
    make sim          # balance telemetry from the reference bot
    make tune         # parameter sweep over the economy
    make dist         # build dist/augment.love

## Start here

If you have not played it, press **TUTORIAL** on the title screen. It takes about
two minutes and teaches the game on your own graph: it watches what you build and
each step completes when your network actually satisfies it. It introduces
capacity, flow, the minimum cut, the adversary and redundancy in that order,
because that is the order in which each one becomes the thing blocking you.

## Controls

| | |
|---|---|
| `1` `2` `3` | arm relay / hub / conduit, then click the field to place |
| drag node to node | lay a link |
| click | inspect a node or link |
| `U` | upgrade the selection (link capacity, node throughput) |
| `X` | demolish the selection, for a partial refund |
| `space` | resolve the wave |
| right-drag, wheel | pan, zoom |
| `C` `T` | centre on source, cycle terminals |
| `H` `M` | help, theorems |
| `S` | mute or unmute sound |

## Reading the field

- **Link thickness** is capacity: what it could carry.
- **Moving dots** are flow: what it does carry.
- **The ring** around a node is its ports, one tick per link it can hold.
- **A node's inner fill** is how close it is to its throughput limit.
- **The red pulse** is the minimum cut, and it is where the next strike lands.

## The graph theory, and where it lives

Nothing here is decorative. Each mechanic is a theorem you have to act on.

| Concept | How you meet it |
|---|---|
| Max-flow min-cut | Delivery is a max flow; the adversary strikes the min cut |
| Menger's theorem | Surviving *k* strikes requires *k+1* disjoint routes |
| Degree constraints | Ports cap how many links a node can hold |
| Vertex capacities | Node throughput, modelled by splitting each node in two |
| Vertex connectivity | From wave 8 the adversary destroys nodes, not just links |
| Articulation points | Cut vertices are flagged live; each one is a single point of failure |
| Connectivity | A terminal severed from the source is served nothing |

## Layout

    main.lua            love callbacks, input, camera, screenshot and smoke modes
    conf.lua            window config
    src/graph.lua       graph structure, Dinic max flow, min cut, Tarjan, stats
    src/game.lua        run state, economy, wave pacing, the adversary
    src/render.lua      the field: links, nodes, flow, cut, effects
    src/ui.lua          sidebar, inspector, overlays
    src/meta.lua        persistence and the theorem unlocks
    src/tutorial.lua    the twelve guided steps and their completion predicates
    src/audio.lua       procedural synthesis; the game ships with no audio files
    src/camera.lua      pan and zoom
    src/palette.lua     every colour, in one place
    test/test_graph.lua unit tests with hand-computed expectations
    test/bot.lua        reference player, shared by sim and tune
    test/sim.lua        balance telemetry
    test/tune.lua       parameter sweep

`src/graph.lua` and `src/game.lua` have no LÖVE dependency, which is why the
rules and the algorithms can be tested headless with `lua5.4`.

## Sound

Every sound is synthesised at load from oscillators and envelopes in
`src/audio.lua`, so there are no audio files in the repository. The palette is
narrow on purpose: soft sine blips for what you build, filtered noise over a low
thump for what breaks, and a rising major triad for a wave held. `make audio`
prints peak and RMS per sound, which is how a silent or clipped voice gets
caught without an ear in the loop.

## Design notes

The economy was tuned by simulation rather than by feel. `test/bot.lua` plays
the strategy the game means to teach, `test/tune.lua` sweeps the constants, and
the target was a median around the mid-teens for that bot, leaving a thinking
player real headroom. Current numbers: median wave 13, range 9 to 24 over 40
runs.

Three findings from that process shaped the design, and each is worth knowing
before changing the balance:

1. **Strikes must be capped.** Redundancy is bounded above by ports, so a strike
   count that grows without limit eventually exceeds any achievable cut width
   and kills even perfect play. Pressure comes from the economy of rebuilding.
2. **Demand is per terminal and scales with that terminal's own age.** Pooled
   demand made expansion optional; demand at full current value made a new
   terminal cost more in one wave than the whole network earned.
3. **Delivery and capacity are different flows.** Delivery caps each terminal at
   its demand and decides survival. Capacity ignores those caps and yields the
   cut the adversary attacks. Without the split, meeting demand exactly left the
   minimum cut empty and made the player untouchable.
4. **Insight is paced against the theorem list.** Earning `wave/2 + peak/4`
   against 108 total cost puts a full unlock around a dozen runs. An earlier
   rate handed out every theorem within three.

## State

Complete and playable end to end: title, runs, waves, collapse, persistent
unlocks. Verified by 33 unit tests, an 18-assertion input smoke test, and a soak
that plays whole runs to collapse with every screen rendered. A normal launch
writes nothing to stdout or stderr.

Not done, in rough order of what would add most:

- The three node types are the whole build vocabulary. Hubs and conduits are
  situational enough that relays carry most runs.
- One adversary with one behaviour. Variants that target articulation points, or
  that strike twice in one wave, would use the existing machinery.
- No run modifiers or branching choices between waves, which is where roguelite
  variety usually comes from.
- Terminal placement is random within a growing radius, not designed.
- Mouse and keyboard only.

## Running under a tiling WM

Floating the window suits it better. For Hyprland:

    windowrulev2 = float, class:^(love)$
