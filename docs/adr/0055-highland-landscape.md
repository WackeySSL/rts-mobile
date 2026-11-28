# ADR 0055: Playable high ground, a natural landscape and a skirmish map generator

**In short, for Michael:**
- **Two heights.** Ground is low or high. High ground (a plateau, a raised corner, a ridge) sits
  one step up, the same 32 px as today's raised rock. Units and buildings can stand on it.
- **Cliffs and ramps.** The outer ring of every plateau is a cliff: nobody walks on it. Ramps,
  3 tiles wide and 2 tiles long, are the only ways up. A plateau with a base gets two.
- **High ground sees down, low ground does not see up.** To see onto a plateau you need a unit on
  its ramp or on top, or an aircraft over it. Once one of your units sees, all your units can
  shoot up. There is no range or damage bonus: the sight is the advantage.
- **Woods, houses, bridges.** Woods (today's scrub, now with trees): soldiers walk through,
  vehicles go round. Small abandoned houses block the way and cannot be destroyed. Bridges cross
  water, 3 tiles wide, and cannot be destroyed; rivers have bridges and fords.
- **No more fixed skirmish maps.** A generator makes a new map for every skirmish, from a number
  (the map seed). The same seed always gives the same map, so replays, resumed matches, a shared
  map code and later multiplayer store only the seed. Fixed maps stay for the tutorials, the
  performance tests and future missions.
- **Three landscape types** take the place of the three maps and keep their ids, so your
  trophies, wins and unlocks carry over: open plains, a river valley and highlands.
- **Both sides get a mirror image of the same land**, as seen on the screen: one player starts
  at the left corner, the other at the right corner (question 7).
- You decide 16 questions at the end. Every one has a recommended answer.

Status: **proposed, 2026-11-28**, by the architect in row P680 on branch
`claude/p680-highland-plan` (base `main` at 05c900a4). Plan:
`docs/plans/2026-11-28-highland-landscape.md`.

**Michael's decisions** (2026-11-28, through the lead, translated from Danish):
1. Rock must not look like man-made walls. It is used as natural landforms, for example a whole
   corner of the map raised, or water lying right up against a cliff edge. The landscape is
   natural and realistic.
2. High ground is playable now, not scenery: "B, so we don't have to redo the map landscape again
   afterwards. There must be ramps up to the raised map landscape."
3. "The landscape must also have bridges and trees and small abandoned houses."
4. Still in force: ADR 0053 §7 option C (real occlusion and silhouettes, "we're making the best
   game"), and silhouette look B (55 % alpha plus a screen-space hatch), the default on
   `claude/p656d3-silhouettes` (744d5d70).
5. 13:35Z: "We need more than 3 maps. It would be best with a generator that just generates maps,
   so we have no fixed maps. That way the game feels new every time you play it. Fixed maps are
   only for when we build mission maps."

**Amends** (dated notes placed when this ADR is accepted; no accepted line is rewritten):
- ADR 0053 §7, amendments A1, A4, A5, A7, A8, A9 and A10 (§9 below says what holds and what
  changes in each). A2, A3, A6 and A11 hold and are extended.
- ADR 0008 §1 (the map as text): a second layer, `heights`, beside `rows` (§2).
- ADR 0007: `STATE_FORMAT` 8 (§15). `Replay.FORMAT` 4 (§12).
- ADR 0042: the resume file carries the map spec (§12).
- ADR 0033: the facing rule must be equivariant under the transpose too, if question 7 is
  answered A (§8).
- ADR 0054 and the progression data: the map ids `kestrel_flats`, `map_2` and `map_3` name
  landscape types from now on (§13). No key changes.
- `docs/GDD.md` "Maps (MVP)" is rewritten in row P699 after acceptance.

**Holds unchanged:** the sim/view split, the 15 Hz integer tick, `DetRandom` only, Commands only
(no new Command), balance numbers in `data/`, the one sorted world on one page with no material
(ADR 0023 §2, ADR 0053 §4), silhouette look B, the ground kit's per-cell piece choice (ADR 0053
§7), the tutorials and their maps.

## Context
- **Today's rock** (ADR 0053 §7, A1-A11, merged behind `walls_enabled`, off): every rock cell
  rises 64 texels (32 world px, one diamond height) and blocks every move class. Walls sit in
  `WorldSort`, one `Node2D` per diagonal d = c + r at y = (d + 1) x 16. Fog shows a wall lit, dim
  or hidden. A unit hidden behind a wall shows a silhouette (one shared shader at z 11, the exact
  three-cell cover test, `WallCover`). `WallCover.ground_at` resolves taps on walls. Aircraft
  shadows lift to z 19 on wall tops. `GhostMemoryLayer` is at z 12.
- **Today's maps** draw rock as 1-2-cell lines, 2 x 2 blocks and square rings round ore fields
  (Kestrel Flats, Heron Fords, Curlew Crags). Michael rejects that look. Every skirmish map is an
  exact half turn (`tests/sim/test_map_fairness.gd`), starts sit at the top and bottom corners of
  the screen, and the AI builds by half-turned spiral slots (`AiEconomy._turned`) and guesses
  the enemy base at the point mirror (`AiMemory.mirror`).
- **Terrain data** (`data/terrain/standard.tres`): grass `.`, sand `:` (both buildable), scrub `^`
  (foot only, cost 10/0/0), rock `#`, water `~` (both blocked), ore `o`. The sim stores a terrain
  index and a move cost per class per cell (`World.terrain`, `move_cost`), hashed through the map
  digest (`WorldHash.map_digest` over `MAP_ARRAYS`).
- **What is native** (ADR 0013): FLOW, SEPARATION, INTEGRATE, TARGETING and FOG have C++ twins.
  All of them read passability from `move_cost`. Only FOG would need a new rule.
- **The ground kit** chooses each cell's pieces from the cell's and its 8 neighbours' terrain and
  a fixed cell hash. A whole-map bake was rejected (183 MB, ADR 0053 §8 Alternatives). So any
  layout can be drawn from the kit, with no per-map bake.
- **What keys on a map id:** `MapCatalog` (`data/maps/catalog.tres`), the map select and its
  preview (P666b, #727), the deploy card, `MatchSetup.map_id`, the trophies' `WIN_GRID`
  (`data/meta/trophies.tres`: "a Hard win on each map"), `CareerStats.wins_grid`, the rank
  unlocks (`map_2` at rank 2, `map_3` at rank 4), the smoke's `--map`, the balance workflow's
  maps and about 30 test files. `game/ai` names no map.

## Decision

### 1. The height model in the sim
- **Two levels: low and high.** One step is exactly one diamond height, 32 world px, the raise
  ADR 0053 A1 already uses. A third level would rise 64 px; from 33 px on, a raise covers ring 2
  behind it as well, and the exact three-cell silhouette test and the per-diagonal sort (A4, A7)
  no longer hold. Two levels are also the most readable on a phone.
- **`World.height`**, one byte per cell, in `MAP_ARRAYS` (hashed through the map digest):
  - `LOW` 0;
  - `RAMP` 1: a slope between the levels, walkable;
  - `HIGH` 2: plateau ground, walkable;
  - `CLIFF` 3: a high cell with a low cell among its 8 neighbours (a ramp is not low). Derived
    at load, never authored. Blocked for every ground class (`move_cost` 0); the air plane stays
    open (ADR 0036 §4).
- **Why the cliff is a band of cells and not an edge between cells.** No walkable high cell is
  then ever a neighbour of a walkable low cell, so every continuous move from low to high passes
  a blocked cell or a ramp. Movement, separation, line checks, flow fields and their C++ kernels
  already treat a blocked cell correctly (rock works this way today), so **no movement code and
  no movement kernel changes**. Per-edge blocking would change FLOW, INTEGRATE, SEPARATION and
  the line checks in both twins (Alternatives). Visually the band is right too: a raised cell's
  front face covers its own ground diamond, so the cliff face stands on the cliff cell, and its
  top reads as the crest of the plateau.
- **A ridge** is a high strip one or two cells wide: all of it is `CLIFF`, so it is an impassable
  natural ridge with faces on both sides. Ridges replace the old straight rock lines.
- **Rock `#`** stays (tutorials, perf fixtures): a raised, blocked low cell, used by new maps only
  as small irregular outcrops. Rock, water, ore and bridges may stand only on low cells.
- **Heights never change during a match.** `set_terrain` keeps a `CLIFF` cell at cost 0.
  Buildings write and restore `move_cost` only on their footprint, which can never hold a cliff.

### 2. The map format: a `heights` layer beside `rows`
- `MapDef.heights: PackedStringArray`, the same size as `rows`, one character per cell: `0` low,
  `1` high, `r` ramp. Empty means every cell is low, so every existing map keeps its file
  unchanged. Hand-editable and mirror-checkable in the same way as `rows`.
- **Validation** (`MapDef.validate`, through a pure static helper `game/sim/MapRelief.gd` that
  `WorldLoad`, the generator, the view and the tests share):
  - only those three characters, the same size as `rows`;
  - `#`, `~`, `o` and the bridge terrain only on `0` cells;
  - **ramps:** each ramp component (4-connected) is a rectangle along one grid axis, 2 to 4 cells
    across (`ramp_width_min`, `ramp_width_max` in the map rules data) and 1 or 2 cells long. One
    long side borders walkable high cells, the opposite side borders low cells. Ramp cells are
    on passable, non-blocked terrain;
  - every walkable high component touches at least one ramp (no unreachable mesa holding
    walkable ground);
  - **no diagonal pinch:** two high cells that touch only at a corner, with low cells on the
    other two cells of that 2 x 2, are refused. The kit cannot draw it, and it breaks the prism
    cover rule;
  - no start footprint and no ore cell in ring 1 behind a raised cell (A1's rule, kept).
- The ramp's direction is derived (the axis towards its high side), never stored.
- `MapDef.relief: bool` (view only, like `ground_look`; `WorldLoad` never reads it): whether the
  view raises this map's rock and draws its relief. Generated maps, the showcase map and the perf
  fixtures set it. The tutorials and the retired fixed maps do not, so their straight rock stays
  flat (§13).

### 3. Movement and pathfinding
- Unchanged code: cliffs are cost 0 like rock, ramps and bridges are ordinary passable cells.
  FLOW, SEPARATION, INTEGRATE and the line checks, in GDScript and C++, need no edit, so the twin
  rule triggers no port row.
- **Performance:** a plateau adds blocked cells, as rock does today. Flow fields are integer
  Dijkstra over the same grid, so their cost per cell is unchanged. Longer detours through ramps
  mean somewhat more cells integrated per field; `flow_cells_per_tick` time-slices that as today.
  No timing figure is claimed; CI's perf report and the phone card (P692) are the check.

### 4. Vision: high ground sees down, low ground does not see up
- **The rule.** A cell of height `HIGH` or `CLIFF` is stamped into a player's sight only by a
  viewer that sees up: its stamped cell is `RAMP`, `HIGH` or `CLIFF`, or its type flies (move
  class AIR). Every viewer sees `LOW` and `RAMP` cells as today. A player's sight is shared by
  all its units, so one spotter on the ramp, on top or in the air lets the whole army acquire and
  shoot targets up there: `Targeting.sees` reads `fog.visible`, so targeting needs no change.
- **Where it lives.** `FogGrid.stamp` (the reference, also called by `World.prepare`'s first stamp
  and `World.remove_dead`'s unstamp) and the FOG kernel's stamp in `core/fog.cpp`, in one PR with
  the lockstep test (ADR 0013 §5). The signature does not change: the stamp reads the stamped
  cell's height and a per-mask "flies" byte that `FogGrid.configure` builds from the types. Stamp
  and unstamp of one row read the same static facts, so the counts stay symmetric.
- **Cost.** A viewer that sees up walks its spans as today. A low viewer reads one height byte
  per cell it walks. A map with no high cell takes the old path. `stats[FOG_CELLS]` still counts
  the cells walked, so the stat does not move.
- The satellite and the strike reveals (ADR 0036, ADR 0023) reveal every height, as from the sky.
- Easy and Normal AI read only their own player's sight (ADR 0010), so the rule binds the AI too.
- **Flat maps are unaffected:** with no high cell the stamp walks exactly the old cells, so no
  golden moves in that row (asserted).

### 5. Combat: no high-ground modifier
No range bonus and no damage or hit-chance change: the sight rule is the advantage, it needs no
new number, and it reads on a phone ("you cannot shoot what you cannot see"). A range bonus from
above is the lever if the balance runs show plateaus are too weak (question 1, option B).

### 6. Building on relief
- Buildings may stand on `HIGH` cells of buildable terrain. A footprint can never span levels,
  because the levels are separated by cliffs and ramps.
- **Ramp clearance:** a ramp cell and every cell orthogonally next to a ramp cell are not
  buildable (the rule int `ramp_clearance_tiles`, 1, in `data/rules.tres`). So no player or AI
  can seal a ramp with one row of buildings. `Placement` reads `height` through `PlacementInput`;
  the AI places through the same rule.

### 7. Woods, houses and bridges (terrain data)
- **Woods** are today's scrub `^`, re-skinned: trees stand on it (one to three per cell by the
  cell hash, some cells undergrowth only). The rule stays foot only (cost 10/0/0). No vision
  effect. The id `scrub` stays, so no data or test changes; the text calls it woods.
- **Houses:** a new terrain `house`, symbol `H`, cost 0/0/0, not buildable. One house per cell,
  in hamlets of 2 to 5. They cannot be destroyed or garrisoned (question 4).
- **Bridges:** a new terrain `bridge`, symbol `=`, cost 10/10/10, not buildable, only on low
  cells. A bridge run crosses water along one grid axis, 2 to 4 cells wide (3 by default), with
  land at both ends. The deck is a flat ground piece over water (it rises 0, ADR 0053 A2).
  Indestructible (question 5). Rivers get bridges and fords; fords stay sand.
- The two terrains are appended to `data/terrain/standard.tres`, so no index moves.

### 8. Symmetry and fairness
- **For two players the generated maps and the showcase are transpose-symmetric**, (c, r) to
  (r, c), and not half turns (question 7, recommended A). The transpose is a left-right mirror
  on the screen: what faces the camera on one side faces the camera on the other. Under a half
  turn the second seat sees the back of every cliff and every ramp towards the centre, so its
  approach is hidden behind its own plateau, and the human may sit in either seat. With relief,
  the half turn is no longer fair to the eye.
- Starts lie on the anti-diagonal (c + r = size - 1): the left and the right corner of the
  screen. There the point mirror and the transpose agree, so `AiMemory.mirror` estimates the
  enemy base correctly on both kinds of map.
- `MapDef.symmetry` (`half_turn` or `transpose`) is static map data. The sim copies it into the
  World as an unhashed scalar for `PlayerView`, so the AI knows its frame with no map-specific
  code. The fairness and seat tests check each map against its own symmetry.
- **The AI's build layout** must mirror with the map. Today's spiral turns by quarter turns,
  and no rotation is a reflection. `AiEconomy` gains a reflected frame for transpose maps, so
  the two AI bases are each other's mirror images (P684).
- **ADR 0033's facing rule** (nearest side towards the map centre) is geometric, so it is
  equivariant under the transpose, except for ties on an exact diagonal. P684 checks the tie
  rule on transpose maps and changes it only if a test shows the bias. A change that moves
  `bases_golden_hex` is a named re-pin.
- With four players later, the maps would be symmetric about both diagonals. Out of scope.

### 9. The view: relief in the sorted world
All of this is presentation. It reads the snapshot's `height` (static per match, aliased once)
and never writes the sim.
- **Lift.** A pure static helper, `game/view/Relief.gd`, gives each world point its lift: 0 on
  low cells, 32 px on high and cliff cells, and on a ramp a linear rise along its axis (0 to 16
  to 32 px over a two-cell ramp). Units, buildings, health bars, effects and projectiles are
  drawn at their ground point minus the lift. A projectile's lift is interpolated between its
  launch and its target over its flight, so it does not jump at a cliff edge.
- **What is drawn where** (one batch, one page, no material, as A4 and A5):
  - **Plateau tops**: the kit's base and blend pieces of the cell's terrain, drawn 32 px up as
    frames of `PAGE_SORTED`, in the A4 row nodes (one per diagonal, at y = (d + 1) x 16).
  - **Cliff cells**: the top with a ragged crest on its open edges, and the rock face on each
    front edge whose neighbour is lower (today's `wall_face` pieces, re-baked with the crest).
    A cliff whose foot is water gets the same face and a foam line on the water cell (a flat edge
    piece of the ground layer).
  - **Ramps**: sloped pieces per direction (four), each with its side cheeks. The wall kit treats
    a ramp neighbour as raised when it picks a face, so no full face stands where the ramp is.
  - **Rock outcrops**: as A1-A3.
  - **Trees and houses**: sorted props on their cell (lifted on high ground), frames of
    `PAGE_SORTED`.
  - **Bridges**: flat deck pieces in the ground layer, over the water piece.
- **The sort rule for lifted objects.** A unit or building standing on high ground sorts at its
  ground y plus its lift plus a pad (`Relief.SORT_PAD_PX`, 8; 40 px in all on a plateau). So it
  is drawn after every top of its level that it overlaps; a flat top never hides an object of
  its own level. It is drawn before a low object in front of the cliff, which stands at least two
  cells nearer. Units on a ramp scale the pad with their lift. A brute-force overlap test on
  crafted relief and on the quality-suite maps checks both directions (§16). The engine sorts the
  rig node; the sprites are offset by the lift and the pad, so `MODEL_MATRIX` is not the ground
  point of a lifted rig (see silhouettes).
- **Shadows and rings of lifted rigs** are drawn inside the sorted world, as the rig's first
  children: the shadow frame is already on `PAGE_SORTED`, and the selection ring art is packed
  there once. So they lie on the plateau top and not under it, with no batch break. A low rig
  keeps its shadow at z 2 and its ring at z 3, as today. Decals and craters on high cells are
  drawn as one strip per diagonal row in the sorted world, each after its row's top and before
  the units on it.
- **Fog.** Every relief piece and every prop takes A6's three states (lit, dim, hidden) from its
  cell. "Hidden" shows the fog's black at the flat cell. A relief look never falls back to flat:
  a look without its own relief pieces uses the standard look's, because high ground with units
  on it cannot be drawn flat. (Rock alone may still fall back to flat, as A1 says.)
- **Silhouettes** (A7, look B): a low ground unit behind a raised cell shows one, exactly as
  today. The raised mask is rock, `HIGH` and `CLIFF`; ramps are not in it. A lifted rig (lift
  above 0) shows none: nothing of its own level hides it, and its node is no longer at its ground
  point.
- **Taps** (A8): `WallCover.ground_at(p)` is extended. On a walkable top or ramp it returns the
  exact ground point under the finger (the flat inverse of p moved down by the lift, two
  fixed-point steps on a ramp), not the cell centre, so a move order lands where the finger is.
  On a cliff or rock it returns the cell centre as today. **Placement uses it too**, and the
  ghost is drawn lifted, so a site on a plateau is placed where it is seen. This replaces A8's
  "placement keeps the flat inverse".
- **Air** (A9): aircraft at z 20 unchanged. A shadow over high ground is drawn lifted at z 19,
  as over a wall top today. Remembered enemy buildings (`GhostMemoryLayer`, z 12) on high cells
  are drawn lifted.
- **Minimap and preview:** `TerrainPalette` gets a lighter tone for high ground, a darker line
  for cliffs, and colours for bridges and houses. `MinimapImage`, `MapView` and `MapPreview`
  read `height`.
- **Budgets:**
  - **Draw calls:** relief, props, lifted shadows and rings +0 (one page, no material). The
    silhouettes keep A10's +1 while any is on screen. So the forecast stays 18 / 19 / 25 (A10,
    after P656d3). P692 checks the figure on a relief perf scene.
  - **Sorted items:** at most cols + rows - 1 row nodes (127 on 64 x 64), as A4. The relief
    sprites are pinned per map: at most 2,400 on a 64 x 64 map over the quality suite. The lever,
    if the phone card shows the CPU cost, is to draw each row's tops in its row node's own
    `_draw()` (one canvas item per row).
  - **Page:** the relief band (lit and dim) at most 640 rows of 4096 px, so the cross-faction
    `PAGE_SORTED` stays under 3,584 rows (today about 2,756 plus A5's walls). Levers: dim by
    `self_modulate` instead of baked copies, if the web preview shows it keeps one batch (it
    halves the band); tighter packing of trimmed pieces.
  - **150 units at 60 fps:** the relief is static (made at match start), with no per-frame
    script work except one lift lookup per moving rig (a cell read and, on a ramp, one multiply).
    No timing claim; the phone card on a relief scene (P692) is the gate.

- **ADR 0053 §7's amendments, one by one** (dated notes at acceptance):
  - **A1** holds (32 px, ring 1, every rock cell rises) and is extended: `HIGH`, `CLIFF` and
    `RAMP` cells rise too. "When the map's look has the wall pieces" becomes "when the map sets
    `relief`" (§2). Its per-map counts (kestrel 119, curlew 281, heron 60, basics 13, drills 6)
    stay as fixture pins. "No start cell and no ore cell in ring 1" becomes a generator rule.
  - **A2** holds: no ground piece rises. The bridge deck and the foam line are flat ground
    pieces.
  - **A3** holds and is extended by the crest, ramp, foam and prop pieces (§10).
  - **A4** is extended: plateau tops, ramps and props join the row nodes; lifted objects sort
    with the lift and the pad. Its premise "a unit's ground point is never inside a rock diamond"
    now holds for low units only; lifted units take the sort rule above.
  - **A5** is superseded in its budget: the band of at most 224 rows becomes the relief band of
    at most 640 rows, the page still under 3,584. One page, no material, as written.
  - **A6** holds and applies to every relief piece and prop.
  - **A7** holds for low units (look B). It is extended by the mask (rock, `HIGH`, `CLIFF`) and by
    "a lifted rig shows none".
  - **A8**: taps are extended to exact points on tops and ramps; "placement keeps the flat
    inverse" is superseded (placement uses `ground_at`, the ghost is lifted).
  - **A9** is extended: air shadows lift onto high ground; remembered buildings on high ground
    are lifted; field props stay at z 1 (no ore on high ground, question 3).
  - **A10** holds: +0 for relief, the forecast 18 / 19 / 25; P692 re-checks it on relief.
  - **A11** holds and is extended by §16.

### 10. Art: the relief kit and the props
- Baked with `tools/prerender` in the pinned container (ADR 0053 §5), with P653's cliff method
  as re-baked in P656d4 (strata, ragged edge, flat top) for the faces, so cliffs, ridges and
  outcrops share one rock.
- New pieces per look: crest pieces per top terrain (grass, sand, woods); faces as today; foam
  foot; ramps in four directions (low and high half, left, middle and right column, cheeks);
  trees (4 to 6 variants); houses (4 variants, abandoned: broken roofs, no lights); bridge decks
  and piers per axis.
- Same-scene check (ADR 0053 §8) with the new pieces. Michael's look gate on the sheet.
- Legal: our own models, no reference to any existing game's houses, bridges or cliffs. Houses
  are generic rural ruins.

### 11. AI
- **No map-specific code** (a test greps `game/ai` for map ids and asserts none).
- `PlayerView` gets the static relief facts: `height`, the ramps (foot and top cell per ramp,
  the plateau they lead to) and a ground distance (tracked BFS from the own Headquarters over the
  static map, buildings ignored, computed once).
- **Economy:** ore fields and expansions are ranked by ground distance, not straight-line
  distance (a field across a cliff is far).
- **Army:** a target on a plateau gets a staging point at the foot of the nearest ramp by
  ground distance. The wave gathers there and climbs as one group, with no trickle. A unit hit
  from an unseen high cell (`AiUnseen`) sends its group up the nearest ramp of that plateau.
- **Scout:** the scout visits each plateau's ramp top once, so the AI's memory covers high
  ground.
- Placement keeps ramp clearance through the shared rule (§6).

### 12. The map generator
- **Where it runs.** A pure static module in `game/sim/mapgen/`: no Node, no float, no time, no
  `randi`/`randf`, no Resource load inside. It is called **once, on the main thread, before
  `World.from_scenario`**, never inside `Sim.step` or a `TickJob`. Each machine, each replay and
  each future peer runs the same code. A pre-generated pool made by a tool was rejected
  (Alternatives): it would not be "new every time".
- **Input:** a `MapSpec` (generator version, map seed, landscape type, size, player count) and
  one `DetRandom` stream. The stream is made outside `game/sim` by the `DetRng` factory, as
  `DetRng.create(map_seed, DetRandom.STREAM_MAPGEN)`, a new stream id 2 beside ADR 0007's
  `STREAM_SIM` 1 and `STREAM_AI_BASE` 100. The
  landscape type's numbers come from `data/mapgen/<type>.tres` (`MapGenPresetDef`), loaded by
  the caller and passed in: sizes, counts, thresholds, distances, ore yields. No balance number
  lives in code.
- **Output:** a `MapDef` (rows, heights, field kinds, look, `relief` on, symmetry) and the start
  tiles. The caller fills a template scenario per side pairing (factions, rules, spawn types,
  team triads) with the map and the start tiles.
- **The map seed is separate from the match seed** (question 12): the same map can be played
  again with fresh in-match randomness.
- **Versions.** `MapGen.VERSION` is an int that moves with every change to the output. The spec
  carries it. An app generates only its own version. A replay, a resume file or a map code of
  another version is refused with a short note ("made with another version of the game"), as the
  resume already refuses another app version (ADR 0042). Old generator versions are not kept
  (question 11). A golden test pins the digest of the generated maps of fixed seeds per version,
  so a change of output cannot pass unnoticed: it must bump `VERSION` and re-pin in the same PR.
- **Replays:** `Replay.FORMAT` 4 holds the map spec beside the scenario path. `Replay.play`
  regenerates the map. The resume file holds it through `MatchSetup.to_dict`.
- **Map code:** a short text such as `C56-7KQ3-M9TX` (type, size, seed in Crockford base 32,
  the version, and a check character). It is parsed and printed in `game/core`.
- **Building blocks** (integer only, organic by construction):
  - integer value noise: a lattice of `DetRandom` ints, bilinear in integers, thresholded;
  - cellular smoothing (majority passes) and opening and closing by one cell, so every feature
    is at least 2 cells thick: no 1-cell line, no single-cell hole, no square ring;
  - plateaus and raised corners from noise blobs; ridges as thin high strips; lakes and coasts
    (water against high ground gives a cliff into water); rivers as a meandering band;
  - ramps placed on plateau edges facing the routes (two on a plateau next to a start, one or
    two elsewhere); bridges and fords on rivers; woods in noise clusters; hamlets of houses near
    crossings and roads (roads as decoration, ADR 0053 question 4);
  - the generator draws one half and mirrors it with the map's symmetry, cell by cell in a fixed
    order, so both halves are exact images.
- **Landscape types** (presets; question 9):
  - `kestrel_flats`, open plains: low mesas, lakes, woods, hamlets;
  - `map_2`, river valley: a river along the symmetry axis with mirrored pairs of bridges and a
    ford on the axis, a gorge stretch where the river runs under a cliff;
  - `map_3`, highlands: raised corners on the axis, ridges, a central plateau, coast cliffs.
  - Sizes: small 48, medium 56, large 64 (question 10).
  - In this ADR's first version the starts stand on low ground, and there is no ore on high
    ground (question 3).
- **Validation before use** (`MapCheck`, pure, in `game/sim/mapgen/`):
  - every start reaches every other by ground, for foot and for tracked units (through ramps
    and bridges);
  - no isolated pocket: a passable cell that the tracked (or foot) class cannot reach from a
    start becomes the blocked terrain around it, unless it holds a start or ore; then the map
    fails;
  - ore balance: the same fields, cells, yields and kinds per side (exact by symmetry), at least
    the preset's safe fields within its ground distance of each start, and the ground distances
    of mirrored fields equal;
  - build space: a buildable rectangle of the preset's size at each start, clear of ramps,
    ramp clearance and cliffs, with the Headquarters' footprint inside;
  - the relief rules of §2, exact symmetry, and the map validating as a `MapDef`.
- **Re-roll:** on a failure the generator tries again, drawing on from the same stream. That is
  deterministic: the attempt count is a pure function of the seed. After `attempts_max`
  (preset data) it builds the preset's fallback recipe, which the quality suite proves valid.
  The attempt count is in the result for the tests and the perf report.
- **Budget:** generation is bounded by a deterministic count of cell visits (pinned per size in
  tests, at most 3 M on 64 x 64 with every re-roll). CI reports the wall time (`mapgen_ms`) with
  the perf report; the target on the reference phone is at most 150 ms typical and 400 ms worst,
  under the loading screen. No timing run in a session.
- **The kit draws any generated layout:** the ground and relief pieces are chosen per cell from
  the cell's neighbourhood, with no per-map bake. Only the look's pieces are packed, once per
  match, the same for every map of that look. The generator's shape rules keep every
  neighbourhood inside the set that has an exact piece. The quality suite counts nearest-piece
  fallbacks and requires 0.

### 13. Fixed maps, the catalog, trophies and stats
- **Stay fixed:** `tutorial_basics`, `tutorial_drills`, `controls_test`, `perf_arena`,
  `perf_bases`, the showcase map (a developer route; the first mission maps may start from it),
  and future mission maps.
- **Kestrel Flats, Heron Fords, Curlew Crags** leave the catalog when the generator ships
  (question 8). Their files stay where they are as frozen test fixtures for the AI and sim suites
  that use them (`relief` off, so their straight rock is never shown raised). Moving them would
  break about 30 paths for nothing. P699 lists which of their tests the generator suites now
  cover, and retires those.
- **The catalog's three ids become the three landscape types**, `kestrel_flats`, `map_2`,
  `map_3`. So the trophies' `WIN_GRID` ("a Hard win on each map" now means each landscape
  type), `CareerStats.wins_grid`, the rank unlocks (`map_2` at rank 2, `map_3` at rank 4) and
  every saved progress keep their keys: no save migration. The titles become the landscape
  names (question 9); the trophy text says "landscape".
- The map preview (#727) is keyed by the map code instead of the scenario path, and drawn from
  the generated `MapDef`.

### 14. Player options (what the skirmish screen needs from the generator)
The skirmish screen is parked for a UX redo, so this ADR designs no screen. The generator gives
it:
- the landscape type and the size as inputs;
- **"New map"**: a fresh map seed, and the preview of its map within the budget of §12;
- the **map code** of the current map, to show and share; entering a code is a later step
  (question 13);
- a refusal note for a code of another version.
Until the redo, P698 adds only the minimum to today's map select: the type cards as they are, a
size choice, a "New map" button and the code under the preview.

### 15. Hashes, formats and goldens
- **P681: `STATE_FORMAT` 8, one re-pin under exception 27.** `height` joins `MAP_ARRAYS`, and the
  two new terrains lengthen `terrain_cost` and `terrain_buildable` for every map on the standard
  set. So every map's digest moves, and with it every golden: `golden_hex`, `bases_golden_hex`,
  the frozen-scenario and replay hashes, with no run or rule change. The alternative, feeding
  `height` only when a cell is not low, keeps flat maps' hashes but is a special case in the
  hash walk (Alternatives).
- **P682** (vision) moves no golden: the perf maps have no high cell (asserted).
- **P692** gives `perf_bases` a plateau, a ramp and woods (or adds a relief perf scene), so the
  perf card measures relief: `bases_golden_hex` moves once more under exception 28.
- **The generator** adds new pins (the per-version map digests), not re-pins.
- **The smoke** plays generated maps from P696: its fixed seeds' outcomes change. They are not
  goldens; the PR states it.
- `Replay.FORMAT` 4 (P695). Saved resumes from before P681 are refused by the app version check
  (ADR 0042).

### 16. Tests
- **Headless (gdUnit4):**
  - `MapRelief`: every validation rule on crafted grids, the cliff derivation, ramp directions,
    the diagonal pinch;
  - `WorldLoad`: `height` and the cliff cost on crafted maps; `set_terrain` keeps a cliff at 0;
  - placement: ramp cells and the clearance refused, plateau tops accepted;
  - the vision rule under both implementations (`sim_impls.gd`), with the FOG lockstep test,
    crafted spotter, ramp, air and remove-dead cases, and goldens unchanged on flat maps;
  - the AI on crafted relief and on generated seeds: staging at the ramp foot, the climb as one
    group, ore by ground distance, no stall (`AiStall`) over 30 seeds per type;
  - the view: lift on every height and along ramps; the sort brute force (each lifted rig after
    every top it overlaps, before every low object that overlaps it from in front); the relief
    piece choice tables; the fog states and write bounds; `ground_at` on tops, ramps, cliffs and
    flat ground; no node made after warm-up over 300 frames; relief sprite counts; the page pin;
    the 0-fallback count;
  - the generator: the per-version digests of fixed seeds; **the quality suite**: 200 seeds per
    type and size validate, are exactly symmetric, have no artefacts by the shape rules (no
    1-cell line, hole or pinch, no square ring), give 0 kit fallbacks, stay under the cell-visit
    budget, and count their re-rolls (pinned bound); the map code round-trips; a replay and a
    resume of a generated match reproduce the final hash.
- **CI only:** the shader render test (A7), `mapgen_ms` in the perf report, and the seed-sweep
  balance job in GitHub Actions (never in a session).
- **Not headless:** the look (Michael's gates), the frame time (the phone card).

## Consequences
- High ground becomes a real tactic (sight, chokes at ramps), with no new number to balance at
  first.
- Every skirmish is a new map. Replays, resumes and map codes stay small (a spec), but each
  generator change invalidates old codes and replays.
- The movement code and four of the five kernels are untouched. Only FOG changes in both twins.
- The view's sorted world carries several thousand static pieces more on large relief maps. The
  page budget is the tightest number in this ADR.
- The three hand-made maps are no longer played. Their ids live on as landscape types, so no
  progress is lost.
- About 25 PRs (rows P681-P699 with splits) before the feature reaches players. It is player
  visible only at P698. ROADMAP gets a Phase 5 row (question 16).
- The AI gets relief awareness that also makes it better on any future mission map.

## Alternatives considered
- **Cliffs as edges between cells** (per-edge passability). Rejected: it changes FLOW, INTEGRATE,
  SEPARATION and the line checks in both twins, and the separation push across an edge. The
  cliff band costs one cell of plateau rim and no movement code.
- **Three or more levels.** Rejected: a 64 px raise covers ring 2, so the exact silhouette test
  and the per-diagonal sort fail, and readability on a phone suffers.
- **New symbols in `rows` for high variants of each terrain** (`,` for high grass). Rejected: it
  doubles the terrain set and makes the rows unreadable. A second layer keeps both readable.
- **The cliff band on the low side** (the cliff foot blocked). Rejected: a visible strip of low
  ground where no unit can walk, under every face.
- **Plateau tops in a lifted tile layer under the sorted world**, with a second fog image.
  Rejected for now: low objects behind a back rim and the crest's fog states need sorted pieces
  anyway, so it adds a second mechanism. It stays the lever if the sprite count is too high.
- **A pre-generated pool of maps** made by a tool and committed. Rejected: not new every time,
  and the pool needs QA per map. The quality suite tests the generator instead.
- **Keeping every old generator version** for old replays and codes. Rejected for now (question
  11): it freezes code forever for a feature (shared codes across versions) with no user yet.
- **Feeding `height` into the hash only when a cell is high**, to keep flat maps' goldens.
  Rejected: a special case in the hash walk to save one documented re-pin.
- **A high-ground range or damage bonus.** Not now (question 1); it needs both twins of
  TARGETING and a number to balance.
- **Destructible bridges and houses, garrisoned houses.** Not now (questions 4 and 5): they need
  neutral rows with health, AI rules and runtime terrain changes.

## Questions for Michael (answers recorded here at acceptance)
Each has options; **A is recommended** unless stated otherwise.
1. **High-ground advantage.** A: sight only (low ground does not see up without a spotter on the
   ramp, on top or in the air). B: A plus 1 tile more range when shooting down. C: A plus less
   damage from below.
2. **Ramps.** A: 3 tiles wide (2 to 4 allowed), 2 tiles long; two ramps on a plateau next to a
   start, one or two elsewhere. B: 2 wide, one ramp each (sharper chokes, more stalls).
3. **Plateau tops.** A: grass, sand, woods and houses, buildable; no ore and no start on high
   ground in this version (starts on low ground). B: ore and starts on high ground now (one more
   view row for raised oil fields).
4. **Houses.** A: they block the way, cannot be destroyed, in hamlets of 2-5. B: destructible.
   C: soldiers can hide inside (later phase).
5. **Bridges.** A: over water only, 3 wide, cannot be destroyed, together with fords. B:
   destructible bridges (later).
6. **Trees.** A: today's scrub becomes woods with trees; soldiers walk through, vehicles go
   round, no effect on sight. B: A, and units inside woods are seen only from close by. C: a
   second, dense forest that blocks everyone.
7. **Symmetry.** A: transpose, the left and the right corner, a mirror image on the screen, fair
   to the eye with cliffs. B: keep the half turn (top and bottom; one seat sees the back of its
   cliffs).
8. **Kestrel, Heron and Curlew.** A: leave the menu when the generator ships, kept only as test
   files; their ids become the landscape types. B: keep them playable as "classic maps" (they
   would need a natural redesign: three more rows). C: delete them.
9. **Landscape types and names.** A: three types with the old ids, titled "Open Plains",
   "River Valley" and "Highlands". B: keep the old titles as type names.
10. **Map sizes.** A: small 48, medium 56, large 64 (today's sizes). B: medium only at first.
11. **Old replays and map codes after a generator change.** A: refused with a short note; only
    the current version is generated. B: keep every old version (more code forever).
12. **Map seed and match seed.** A: separate, so the same map can be played again with fresh
    randomness. B: one seed for both.
13. **Skirmish options now** (the screen redo is parked). A: landscape type, size, "New map",
    the preview and the map code shown; entering a code later. B: also enter a code now.
14. **When relief turns on.** A: `walls_enabled` goes on in the main scene with the showcase map
    (P691), with relief only on maps that opt in; players see it in skirmish when the generator
    ships (P698). B: only with the generator.
15. **In-flight P656d work.** A: #733 (d1) and d4b merge as planned; d3 merges its code with the
    walls kept off in the main scene (its commit 4f9c3189 is reverted on the branch); the perf
    arena keeps its walls on. B: hold d3 until P691.
16. **Roadmap.** A: a new Phase 5 row before launch ("Natural landscape with high ground and a
    skirmish map generator"), with the acceptance criteria of the plan. B: after launch, as an
    update.
