---
name: rts-sim-conventions
description: Rules and patterns for the deterministic RTS simulation of rts-mobile - 15 Hz fixed tick, fixed-point integers, DetRandom, the Command queue, entity storage, flow-field pathfinding, targeting, fog of war, state hashing and replays. Use whenever writing, reviewing or debugging code in game/sim, game/ai, data or tests/sim, even for small changes.
paths:
  - "game/sim/**"
  - "game/ai/**"
  - "data/**"
  - "tests/sim/**"
---

# RTS simulation conventions

The simulation is a pure function of (initial state, seed, ordered command list). Every rule
below protects that, because it gives reproducible tests, AI-vs-AI balance runs, replays and a
path to multiplayer.

Decisions behind these rules: ADR 0003 (Phase 1 skeleton) and ADRs 0007-0011 (Phase 2 core,
accepted 2026-10-12). Where this file and an ADR disagree, the ADR wins; fix this file.

## Time and units
- 15 ticks per second (`Sim.TICK_RATE = 15`). Durations in data are stored in ticks.
- Positions are integers in milli-tiles: 1 tile = 1000. Speeds are milli-tiles per tick, rounded
  in data and never at runtime (1.4 tiles/s = 93 per tick).
- Directions and the sine table arrive with the first rule that needs facing. Phase 2 has none:
  no direction state, no sine table and no `dir_to` in `game/sim`.
- No `sin`, `cos`, `atan2`, `sqrt` or any float in sim state. Compare squared distances with
  squared ranges.
- Health, damage, credits and power are plain ints.

## Randomness
- `DetRandom` is xoshiro128\*\* (not PCG32 or xorshift64\*), owned by the match and passed
  explicitly. Never global, never `randi()` or `randf()`. Its `mul32` keeps every shift in
  parentheses (GDScript `+` binds tighter than `<<`), and its state is a `PackedInt64Array` of
  four 32-bit words (ADR 0007 §7).
- `DetRng` is the Node-side factory autoload (`game/core/`) that creates the streams. It is never
  referenced from `game/sim`; `tests/project/test_sim_purity.gd` rejects it.
- Each AI player draws from its own stream seeded from (match seed, player index), so AI changes
  do not shift combat rolls.

## Commands
- `Command`: tick, player_id, sequence, type, unit_ids (PackedInt32Array), a target point in
  milli-tiles or target_id, payload (from Phase 2). Phase 1's Command v0 (attack-move) carries a
  target point in milli-tiles and no payload.
- Applied at the start of their tick in (tick, player_id, sequence) order. Invalid commands are
  dropped and counted; they never crash the sim.
- Validation is per type (`match command.type`). Unknown and reserved types (10-29) are dropped
  as unknown.
- `MatchLoop` stamps tick and sequence and records the command; it is the only tick driver
  (runner, replays, perf test, headless matches).
- Input and AI never touch entities directly.

## Entities
- Integer IDs from a monotonic counter, never reused within a match.
- Stored as struct-of-arrays in `World`, not as Nodes. Every row array is listed in `ROW_ARRAYS`.
- Iterate in ascending ID order. Remove dead entities at the end of the tick with a stable
  compaction over `ROW_ARRAYS` (no swap-remove), so rows stay in ascending ID order.
- Projectiles live in fixed slots (`max_projectiles`) with a free stack.
- A full table counts `spawn_refused` or `projectile_overflow` instead of raising an error.

## Movement and pathfinding
- Tile grid with passability per movement class (foot, wheeled, tracked).
- Units steer straight while the line to their goal is clear, checked staggered every
  `line_check_period_ticks`. A flow field is used only when the straight line is blocked.
- Flow fields per (goal cell, movement class, `map_version`): integer Dijkstra, time-sliced by
  `flow_cells_per_tick`, double-buffered (units read `cost` while `next` integrates), cached, and
  re-integrated when the map changes. References are derived from the World's `field` column
  every tick, never released by hand. A group move shares one field.
- Two spatial grids as linked lists (`head` per cell, `next` per row), rebuilt once per tick in
  the grids phase: a 1-tile separation grid and a 4-tile targeting grid (not one 2-tile grid).
  Processed in ID order.

## Targeting and combat
- Candidates from the targeting grid; acquisition staggered by id every
  `retarget_period_ticks`, not every tick.
- Priority: the highest damage percent against the candidate's armour, then the smaller
  distance, then the lower ID (no threat term).
- Chase a target only while the line to it is clear; otherwise keep the order's path.
- Projectiles fly in their slots with an integer flight time. Rifles are hitscan.
- Damage = base x armour-modifier percent from `data/`.

## Fog of war
- Per player `visible` counts (not bit grids) and `explored` bytes, stamped from precomputed sight
  masks. One player updates per tick (each player every `fog_period_ticks`), and dirty lists tell
  the view which cells changed.
- AI code reads the World only through `PlayerView` once it exists (reserved by ADR 0010). Easy
  and Normal AI read only their own player's visibility.

## Determinism checks
- `World.state_hash()` is SHA-256 through `HashingContext` over the header, the map, every
  `ROW_ARRAYS` entry in ID order, the live projectile slots and the fog. The hashed lists cover
  helper objects too (their `HASHED` lists), and a coverage test fails on an unlisted array.
- `World.hash_hex(h)` is the only formatter for hashes in logs, reports and data.
- `MatchLoop` adds a checkpoint every 15 ticks. Tests run the same seed and commands twice and
  compare the checkpoints.
- Replay = scenario path, seed, `defs_hash`, command log and checkpoints;
  `tests/sim/test_replay.gd` must reproduce the final hash.
- Golden seed-42 perf-arena hashes in `data/dev/perf_gate.tres` catch drift across platforms. A
  PR that changes them on purpose says why.

## Numbers and code
- No int64 overflow. Shift only non-negative values, by 0-62, in parentheses next to `+` or `-`.
- A `PackedInt32Array` never holds a squared distance or an unsigned 32-bit word (it truncates
  silently). No `hash()`.
- In per-row, per-candidate and per-cell loops: alias World arrays into typed locals, inline the
  cell, passability and visibility lookups, and never allocate (`# alloc-ok` marks a reviewed
  exception).
- Helper calls only at event cadence: line checks, and `best_neighbour` stored into `nav_next`.

## Data
- Units, buildings, weapons and AI profiles are custom Resources in `data/`. Load them once at
  match start into plain arrays. Never read Resources inside the tick loop.
- `data/rules.tres` (`RulesDef`) holds every tuning int (cadences, slices, caps); its script
  defaults equal the file.

## Probe
- `SimProbe.Phase` ids are fixed (`COMMANDS` 0 to `FOG` 10, `COUNT` 11). A new phase takes an id
  in pipeline order through an ADR, never by renumbering.
- A probe never reads or writes the World; hashes are equal with and without one.
