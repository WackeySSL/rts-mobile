---
name: rts-sim-conventions
description: Rules and patterns for the deterministic RTS simulation of rts-mobile - 15 Hz fixed tick, fixed-point integers, DetRandom, the Command queue, entity storage, flow-field pathfinding, targeting, fog of war, state hashing, replays and the C++ sim kernels (ADR 0013). Use whenever writing, reviewing or debugging code in game/sim, game/ai, data, tests/sim or native/, including review of C++ kernel PRs, even for small changes.
paths:
  - "game/sim/**"
  - "game/ai/**"
  - "data/**"
  - "tests/sim/**"
  - "native/**"
---

# RTS simulation conventions

The simulation is a pure function of (initial state, seed, ordered command list). Every rule
below protects that, because it gives reproducible tests, AI-vs-AI balance runs, replays and a
path to multiplayer.

Decisions behind these rules: ADR 0003 (Phase 1 skeleton), ADRs 0007-0011 (Phase 2 core,
accepted 2026-10-12), ADR 0012 (worker-thread tick and view snapshot, accepted 2026-10-12) and
ADR 0013 (C++ kernels for the hot phases with GDScript twins, accepted 2026-10-12), ADR 0016
(derived state out of the hash) and ADRs 0017-0021 (Phase 3: buildings, economy, the AI hook,
accepted 2026-10-22; plan `docs/plans/2026-10-22-phase-3.md`, rows from P69 on).
Where this file and an ADR disagree, the ADR wins; fix this file.

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
- Validation is per type (`match command.type`). Unknown and reserved types (5-9, 16-19, 21-29)
  are dropped as unknown. ADR 0017 §4 fixes `PLACE` 10, `QUEUE` 11, `CANCEL` 12, `RALLY` 13,
  `HARVEST` 14 and `SURRENDER` 20 (P70b), ADR 0023 §10 `SUPERWEAPON` 15 (P109; applied by
  `Strike.apply_superweapon` from P110); `Sim._apply` gates each on an undefeated player
  (`_playing`), and each stays dropped and counted until its row (P73-P76) fills its module's
  `apply_*`. From P76 on, every Command is dropped once `match_end_tick` is above 0.
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

## Buildings and economy (ADRs 0017-0020, Phase 3)
- **Buildings are rows** of a type with a footprint (`type_foot_w`, `type_foot_h` above 0; data
  gives speed 0, radius 0, armour `BUILDING`). The position is the footprint centre; the origin is
  derived, never stored. `World.add_building` appends through `add_unit`, writes `move_cost` 0 on
  every footprint cell for every class, bumps `map_version` once and invalidates the flow cache;
  `remove_dead` restores the cells from `terrain_cost`. No kernel reads a footprint: blocking goes
  through `move_cost`. Mobile radii stay in 1..500 (a data test), which keeps separation off
  buildings.
- An `ATTACK` on a building aims at a passable ring cell (`Sim._apply_attack` writes it); the
  TARGETING twins rewrite the goal only for targets with `type_speed` above 0 (P71).
- Placement is one pure function, `Placement.reason(PlacementInput, ...)`, shared by the sim and
  the ghost; never in a per-tick loop.
- **New lists** (P70, each name in exactly one): `ROW_ARRAYS` + `harvest_mode`, `cargo`,
  `harvest_slot`, `home`; `PLAYER_ARRAYS` (per player, per player and tab `player * TABS + tab`,
  per queue slot); `ORE_ARRAYS` (`ore_amount`); `GHOST_ARRAYS` (last-seen records, in the World,
  not `FogGrid`); `MAP_ARRAYS` + `terrain_buildable`, `ore_cell`; `TYPE_ARRAYS` and
  `RULE_SCALARS` appended (in `defs_hash`); `HASHED_SCALARS` + `match_end_tick`, `winner`;
  `DERIVED_ARRAYS` (`power_made`, `power_used`, `building_rows`, `harvester_rows`).
- **Hashed versus derived:** credits, queues, rally points, harvest state, ore left, the ghost
  records (live entries only), defeat ticks, `had_producer` and the stats are hashed (sections
  `players`, `ore`, `ghosts` after `fog`, `STATE_FORMAT` 3). `STATE_FORMAT` 4 (ADR 0023 §10, P109)
  adds the strike state: the row columns `ready_tick` and `offline_until` and the player arrays
  `strike_x`, `strike_y` and `strike_tick`; the six strike type tables (`type_strike_kind`,
  `type_charge_ticks`, `type_strike_radius`, `type_strike_delay`, `type_strike_ticks`,
  `type_strike_weapon`) are in `TYPE_ARRAYS`, so in `defs_hash`. The power totals and the building
  and harvester lists are derived, rebuilt when `rows_version` moves, out of the hash, with a
  rebuild test at every checkpoint. `move_cost` stays in the map digest.
- **Three phases after FOG** (marks ascend): `ECONOMY` 11 (`Power.run`, `Harvest.run`),
  `PRODUCTION` 12 (`Production.run`, then `Outcome.run`), `MEMORY` 13 (`LastSeen.run`), then
  `tick += 1`. LastSeen also drops records in `REMOVE`: `World.remove_dead` calls
  `LastSeen.forget_dead` before its compaction, for a building that dies while a player sees a
  cell of its footprint (P77b), and those checks count in `MEMORY_CHECKS`. Loops go players,
  tabs, rows by id and ore cells ascending; no Phase 3 rule draws
  a random number. A placement in COMMANDS of tick t counts for power in t's ECONOMY; a produced
  unit enters the grids in t+1.
- Ticks of an outcome are stored as `tick + 1` (0 = playing or running). Only a player whose
  `had_producer` is 1 can lose by the producer rule, so unit-only worlds never end on their own.
- Sim rules give orders as the unit-group commands do (`order`, goal, `group_cell` -1,
  `Movement.reset_nav`), never through `reset_row` (Targeting's, with a C++ twin).
- **AI:** `game/ai` reads the World only through `PlayerView` (own rows, seen enemy rows, own
  economy, explored cells, `Placement` for its player). `AiDriver.think_all` calls the controllers
  inside the tick job before `loop.step`, so their Commands are stamped and recorded like a
  player's. A controller copies its `AiDef` into ints and arrays and keeps no Resource or Node.

## Movement and pathfinding
- Tile grid with passability per movement class (foot, wheeled, tracked).
- Units steer straight while the line to their goal is clear, checked staggered every
  `line_check_period_ticks`. A flow field is used only when the straight line is blocked.
- Flow fields per (goal cell, movement class, `map_version`): integer Dijkstra, time-sliced by
  `flow_cells_per_tick`, double-buffered (units read `cost` while `next` integrates), cached, and
  re-integrated when the map changes. No slice on checkpoint ticks (`Sim.step` passes a budget
  of 0 to `FlowCache.run` on the ticks `MatchLoop` hashes). `flow_cells_per_tick` comes from
  the release run's headroom (ADR 0012 §5): 512 (P27b), which the rule gives with ADR 0013's C++
  slice, so P27f is withdrawn; never a literal in code. `FlowCache.configure()` sizes every
  slot's arrays once; nothing resizes them afterwards (ADR 0013 §2). References are
  derived from the World's `field` column every tick, never released by hand. A group move
  shares one field.
- Field keys and endings (P37b, ADR 0008 §2/§3 notes of 2026-10-19): a blocked line keys its field
  on the row's `group_cell` (`Formation.assign`'s group centre for `MOVE` and `ATTACK_MOVE`; -1 from
  `Sim._apply_attack`, `Sim._apply_stop` and `Movement._end_order`), else on the unit's goal tile.
  `nav_next` is -1 (not looked up), `Movement.NO_NEXT` (-2, none) or a cell, looked up in INTEGRATE
  at events only; a next tile equal to the field's key and blocked for the class is none. With none
  on a key other than its goal tile, `Movement._take_own_field` takes the goal tile's field
  (`ATTACK` included) with a fresh `best_dist` and `stall`; a `FIELD` unit left with none stalls at
  any distance (`ATTACK` never stalls). Kernels mirror all of it: INTEGRATE (P37n) the own field,
  the blocked key, the fresh counts and `_end_order`'s `group_cell` write, with `group_cell` in its
  checked list; INTENTS (P37n2, if it fires) `_check_line`'s group key.
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
- Vision (P46b, ADR 0010 §1): a unit acquires, keeps and locks (`ATTACK`) only an enemy whose
  cell its player sees; `Targeting.sees(world, player, x, y)` is the rule, and the hot loops
  inline it on aliased `fog.visible`. A held target is re-tested on the row's turn, an `ATTACK`
  lock every tick (unseen: `ATTACK_MOVE` to the last seen position), and `Sim._enemy_target` drops
  an `ATTACK` on an unseen enemy. Owner 0 and players past `fog.player_count` see every cell.
- In tests: a row added after `prepare()` is blind (`fog_cell` -1) until its player's first FOG
  update, so stamp the fog (`stamp_fog` in `tests/sim/support/targeting_worlds.gd`) or reveal it
  before acting from tick 0. `targeting_rig.gd`'s `data_world` and `world_of` reveal the map
  unless a fog case passes `revealed = false`; `grid_world.gd`'s `from_rows` always reveals.

## Fog of war
- Per player `visible` counts (not bit grids) and `explored` bytes, stamped from precomputed sight
  masks. One player updates per tick (each player every `fog_period_ticks`), and dirty lists tell
  the view which cells changed. Each player's dirty list is a fixed block of one flat
  `PackedInt32Array` with count and "full" arrays, sized in `configure()`; `begin_update` resets
  a count and never resizes (ADR 0013 §2).
- AI code reads the World only through `PlayerView` (ADR 0010, ADR 0020 §1; P78). Easy and
  Normal AI read only their own player's visibility.

## Threading (ADR 0012 §2)
On Android and desktop `MatchRunner` runs each tick as a `TickJob` on one worker thread; `SYNC`
runs it inline (headless tests, replays, `tests/perf`, web). `Sim.step` is safe there only
because of these rules:
- No `static var` in `game/sim`; constants only.
- No `signal`, `.emit(` or `call_deferred(` in `game/sim`. Signals are emitted on the main
  thread only (`ticked`, at publish).
- No Resource load, read or write inside `Sim.step` or `MatchLoop.step`. `World.from_scenario`
  copies the defs into World arrays on the main thread before any job; nothing in the sim keeps
  a def.
- The sim never creates or waits on a thread (`Thread`, `Mutex`, `Semaphore`,
  `WorkerThreadPool`, `await` are banned in `game/sim`).
- A job touches only objects reachable from the World, the `MatchLoop`, the probe, the command
  list or its snapshot, and none of them is a Node or a Resource.
- **Alias before the loop, on both threads.** On the worker (all of `Sim.step`, including
  event-cadence code such as `Formation.assign` and command validation, and the snapshot
  capture) and in the main thread's per-row and per-item loops (`UnitLayer`, the pick snapshot,
  the layers' `_draw()`), read object properties into typed locals once before the loop; no loop
  reads `obj.prop` per row. Godot serializes cross-thread property access, so two threads doing
  it at once both run 2-4 times slower.
- No main-thread access during a job to the World, the loop, the replay, the probe, the command
  list or the job's snapshot (the runner's getters fail such a read).
- The main thread reads the World only inside a `ticked` handler or after `wait_idle()`, never
  from `_process`, a timer or an input handler.
- **The view reads `MatchSnapshot`, never the World.** View, input and UI code read
  `runner.snapshot` (events, fog and its dirty lists too); only tests touch `runner.world`, in
  `SYNC` or after `wait_idle()`. A published snapshot is never written by either thread.
- A submitted `Command` belongs to the runner; every `Command` factory duplicates the arrays it
  is given.
- GDScript shares a packed array by reference across assignment, member reads and Variant
  boundaries; only `duplicate()` copies. A view-like object (`PlayerView`) copies what a caller can
  reach or keeps it behind getters; `PlacementInput` and `MatchSnapshot.placement_input()` hand out
  aliases that are read at once and never written.
- Determinism does not depend on the mode: the golden hashes are equal in `SYNC` and `WORKER`.

## Determinism checks
- `World.state_hash()` is SHA-256 through `HashingContext` over the header, the map, every
  `ROW_ARRAYS` entry in ID order, the live projectile slots and `fog.explored`. The hashed lists
  cover helper objects too (their `HASHED` lists), and a coverage test fails on an unlisted array.
- Derived state stays out of the state hash, with a test that rebuilds it from hashed state and
  compares (ADR 0016): hash the state a rebuild starts from (rows, history such as `explored`,
  credits or ore left), list the derived arrays (caches, counts rebuilt from rows) as `UNHASHED`.
- `World.hash_hex(h)` is the only formatter for hashes in logs, reports and data.
- `MatchLoop` adds a checkpoint every `Replay.CHECKPOINT_PERIOD` (15) ticks: the state hash
  taken after `Sim.step` when the new tick is a multiple of 15, the first at tick 15 (none at
  tick 0). Inside `Sim.step` that tick is still `world.tick + 1`, so a rule that must stay off
  the hashing step tests `(world.tick + 1) % Replay.CHECKPOINT_PERIOD == 0`. Tests run the same
  seed and commands twice and compare the checkpoints.
- Replay = scenario path, seed, `defs_hash`, command log and checkpoints;
  `tests/sim/test_replay_play.gd` must reproduce the final hash.
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
- Use `len(s)` for a String's size: `test_sim_purity` bans `.length(` in `game/sim`, because
  `Vector2i.length()` returns a float.
- Write a typed name list as one literal. Godot 4.7.2 drops the element type of a typed const
  built with `+`: `const A: Array[StringName] = B + [...]` is untyped at runtime (P31b).

## Data
- Units, buildings, weapons and AI profiles are custom Resources in `data/`. Load them once at
  match start into plain arrays. Never read Resources inside the tick loop.
- `data/rules.tres` (`RulesDef`) holds every tuning int (cadences, slices, caps); its script
  defaults equal the file.

## Probe
- `SimProbe.Phase` ids are fixed (`COMMANDS` 0 to `FOG` 10, `COUNT` 11; from P70 `ECONOMY` 11,
  `PRODUCTION` 12, `MEMORY` 13, `COUNT` 14, ADR 0017 §5). A new phase takes an id in pipeline
  order through an ADR, never by renumbering.
- A probe never reads or writes the World; hashes are equal with and without one.

## Native kernels (ADR 0013)
**Scope (§1).** C++17 kernels in `native/sim_kernels/` for `FLOW`, `SEPARATION`, `INTEGRATE`,
`TARGETING` and `FOG`. `GRIDS`, `INTENTS`, `FIRE` and `PROJECTILES` get a port row only when
their `PERF` line meets the port rule: (a) phase mean x `ci_ratio_mean` above 0.67 ms, or (b) a
bursty phase whose per-active-tick cost sets a headroom value. `COMMANDS`, `REMOVE`, `World`,
`state_hash`, `MatchSnapshot`, `MatchLoop`, `Replay` and `DetRandom` stay GDScript.

**The twin rule (§5).**
- Every kernel keeps its GDScript version in `game/sim`: it is the web path, the readable spec
  and the lockstep oracle. Never delete it.
- The GDScript PR comes first; the port follows the module's last GDScript PR. After a port has
  merged, any change to that rule (whatever the PR's title) edits both versions and passes the
  kernel's lockstep test in the same PR.
- gameplay-dev writes both versions of a rule. Each kernel file names its twin and its lockstep
  test in a header comment.

**Boundary (§2).** The World stays GDScript; kernels borrow its arrays in place for one call.
- A kernel is a method of the stateless `SimKernels` (`RefCounted`) and takes the World (an
  `Object`) plus plain ints only.
- On entry it fetches each array once through `bind/world_access.h`: `Object::get(name)`, then a
  type and size check, then `ptrw()` for an array it writes and `ptr()` for one it only reads.
  Every name it gets or sets is in that header's checked table (`Object::set` on an unknown name
  fails silently). The header's `STAT_COUNT` mirrors `World.Stat.size()` and moves with it: a stat
  added to `World` without it makes every kernel that reads `stats` (all but INTEGRATE) refuse the
  World (P70 moved it from 7 to 10). `check_world(world, phase)` is pure and returns a status; a
  kernel that gets a non-zero status logs one error and returns without writing. No mismatch
  message is ever allowlisted.
- FLOW (§2, "Arrays of helper objects"): fetch the typed slot `Array` once, then each touched
  slot's arrays and scalars once (bounded by `flow_cache_size`, never per row or cell). The
  buffer swap is two `set` calls, after which both pointers are fetched again; no slot array is
  resized in a tick (P30b's `configure()` sizes them). Two recorded exceptions. FLOW (plan,
  P26m): the slot pick re-reads `pending` of every `ACTIVE` slot per pick, because reading it
  once would need a capacity literal. INTEGRATE (P37n; ADR 0013 §2's note of P26x docs): the
  pass asks a slot for `complete` once per slot and call and keeps the answer in a 63-slot mask
  (`integrate::MEMO_SLOTS`, pinned by `test_integrate_kernel_slots.gd`), which a recycle
  updates; the rest of a slot is fetched at event cadence, where a FIELD unit looks up its next
  tile; a slot past 63 is asked on each use. Never an `Object::get` per row.
- Forbidden: a `Packed*Array` parameter anywhere in `bind/` (by value or by reference: both write
  to a silent copy); keeping a pointer, Variant, array or Object between calls; `get` or `set`
  per row; calling back into GDScript while holding a `ptrw()` pointer; resizing a held array.
  The only resizes in a tick are the event appends, one per appending kernel after its loop.
- Two layers: `core/` is plain C++17 over the contract's `WorldView` and includes no Godot
  header. `WorldView` is realised as `ArrayView<T>` per array (`core/array_view.h`) "with
  flow::Slot as the aggregate" (`core/flow.h`: one FlowField slot's views and scalars, loaded
  and stored back per slot turn). `Slot` aggregates one slot, not a whole kernel: the World and
  cache arrays reach `core/` as separate `ArrayView`s and ints. In the header's words, "The raw
  pointer is private, so core/ reaches an element only through get() and set()", "An index
  outside the window reads 0 and writes nothing" and "Only bind/world_access.h builds a view
  from a pointer". A view's raw pointer is private (ADR 0013 §2's status note of P26n docs:
  "a struct of raw pointers and sizes" is superseded); `tests/project/test_native_purity.gd`'s
  `view_pointer` rule (P56b, #78) flags a raw pointer member of any element type declared public
  or protected in a `core/` `*View`, and its `raw_pointer` rule flags a use of a view's pointer
  outside the view, across files. `bind/` (`SimKernels`, `world_access.h`, `register_types`, one
  `kernel_<phase>.cpp` each, one line per kernel in `kernel_list.h`) is the only code that
  touches Godot types. A `core/` function lands only with the kernel that calls it, and that
  kernel's tests run in the same PR.
- Rule ints and def columns come from the World on entry, never from a C++ literal. The only
  literals in `core/` are 0, 1, -1 and `constexpr` mirrors of a twin's GDScript `const`, each
  naming it.

**Dispatch (§3).**
- `World.kernels` (null = GDScript) and `World.native_phases` (one bit per `SimProbe.Phase`, in
  `UNHASHED_SCALARS`); `kernels` is the one entry of `World.NON_STATE_MEMBERS`, which the
  coverage test, the hash walk and the reachability walk skip. The choice is never hashed.
- The dispatch is the first line of the phase's entry (`FlowCache.run(world, budget)` for FLOW,
  the module's `run(world)` or `Movement.integrate` for the others):
  `if ((world.native_phases >> SimProbe.Phase.X) & 1) == 1: world.kernels.x(world[, int]); return`.
- `game/sim` never names `SimKernels` or `ClassDB` (`test_sim_purity` bans both); the call is
  dynamic on an untyped `Object`.
- `MatchRunner.sim_impl` defaults to `GDSCRIPT`; scenes set `AUTO` from P50b. The mask always
  comes from `kernels.phases()`, and `tests/sim/support/sim_impls.gd` asserts it against
  `EXPECTED_PHASES`.
- A module's tests run under both implementations through `sim_impls.gd` (preloaded as
  `SimImpls`): the suite has `func _both() -> Array[Array]: return SimImpls.CASES.duplicate(true)`
  and each test is `func test_x(impl: int, _test_parameters := _both())`. gdUnit4 reads the
  parameter sets by calling the suite's member by name and writes into the sets it gets, so they
  are never the constant itself. The World a test builds is attached with
  `assert_array(SimImpls.attach(world, impl, SimProbe.Phase.X)).is_empty()`: `attach` is `use()`
  plus the check that the phase really runs in the implementation asked for.

**Determinism in C++ (§4).**
- `int64_t` wherever GDScript holds an `int`. Every element read from an `int32` or `uint8` array
  is widened to `int64_t` before any arithmetic (through `ArrayView<T>::get`, which returns
  `int64_t`); raw `int32_t`/`uint8_t` pointers stay private to `ArrayView`, whose `set` and
  `fill` hold the explicit `static_cast` at the store. No `char`, `short`, `int` or `long` as a
  type in `core/`.
- No `float`, `double`, `<cmath>` or float literal. No undefined behaviour: no signed overflow,
  shifts only on non-negative values by 0-62, no division by zero or `INT64_MIN / -1`, no index
  past the size checked on entry, no uninitialised read, `reinterpret_cast`/`const_cast` only in
  `world_access.h`. `/` and `%` truncate toward zero as in GDScript; each port's crafted cases
  include a negative operand. `-fwrapv` in every production and test build except the sanitizer
  (UBSan) build, which drops it so an overflow fails there (§4, §10).
- The same loops in the same ascending row order as the twin; no unordered containers,
  `std::hash`, pointer ordering, threads or SIMD intrinsics. No randomness in Phase 2 kernels.
- Proof: a 900-tick lockstep test per kernel that compares the full state after every call (and
  once on non-default rules), crafted tie, cap, division and opposite-corner cases, the module's
  tests under both implementations through `sim_impls.gd`, golden hashes under both, the
  sanitizer job, and the reviewer's mutants.

**Threading (§6).** ADR 0012 §2 applies unchanged. In a kernel: no Godot API except
`world_access.h` on entry and exit (no `OS`, `Time`, `Engine`, print on non-error paths,
signals, `call_deferred`, `ClassDB`, resource loading, Nodes or singletons); no mutable statics
(static locals included), `thread_local`, threads, atomics, mutexes, futures or OpenMP. `SimKernels`
holds no mutable state; its `StringName`s are made once in its constructor on the main thread
and only read afterwards (no function-local `static StringName`, which would be built lazily on
the worker). No heap allocation (`new`, `malloc`, std containers); fixed scratch lives in the
World's `SCRATCH_ARRAYS` or helper arrays.

**Review checklist for a C++ PR (§12).** `godot-code-review` is vendored unchanged, so the C++
checklist lives here; load both skills for any PR that touches `native/`:
- signatures: the World plus plain ints, no Packed parameter; the type and size check on every
  fetched array, through the checked table;
- pointer lifetime: nothing held across calls, re-fetched after the FLOW swap and after an
  event resize; no `Object*` taken from a Variant that dies before the pointer's last use (the
  use-after-free P54's review fixed, #70). Check this by eye: the freed memory is read inside
  engine code, so the sanitizer job cannot see it (valgrind with a fresh-copy probe did);
- views: a `core/` `*View` keeps its raw pointer private and hands out `int64_t` accessors; no
  public or protected pointer member, no use of a view's pointer outside the view (P56b's
  `view_pointer` and `raw_pointer` rules flag both; their blind spots are below);
- integer widths: widened reads, `static_cast` at every int32/uint8 store;
- undefined behaviour: overflow, shifts, division, bounds, uninitialised reads;
- order: the twin's loops in the twin's row order, no unordered containers;
- allocation: none inside a kernel except the event appends;
- a line-by-line mirror of the GDScript twin, plus the lead's mutants and a 20,000-tick lockstep
  run.
- what `tests/project/test_native_purity.gd` cannot see (P56 final check, 2026-10-13): check
  these by eye. A hardening PR comes only if a port PR's review finds one in real code (lead
  decision, 2026-10-13).
  - a mutable static with a named or expression direct-init (`static int64_t calls(K);`);
  - a `constexpr` lambda without a parameter list (`[] { ... }`), whose body the literal rule
    exempts;
  - for views, as the scan header names them since P56b (#78): a view method that returns the
    raw pointer, a `using` alias of it, a pointer in a struct nested in a view, a member defined
    outside the view body and a view that `VIEW` does not name (`class [[nodiscard]] FooView`);
    P56b's PR text adds an `alignas(...)` specifier, a macro without a `;`, a friend view
    reading another view's pointer and a contrived `operator*=`. Since P56b the scan reads every
    declarator of a view's pointer list (`const int32_t *pos_x, *pos_y;`). The qa follow-ups of
    P56b's review (the header's blind spots among them) are P56c's (plan, P26n docs);
  - rarer float helpers missing from the word lists: `UtilityFunctions` `asinh`, `acosh`,
    `atanh`, `is_nan`, `is_inf`, `ease`, `remap` and similar; `std::` `nextafter`, `erf`,
    `tgamma` and similar;
  - a namespace-scope `static const StringName n(NAME);` and a function-local
    `static const auto x = make();` (static objects the scan does not see);
  - `std::array<const T, N>`: a `const` among the template arguments reads as a const variable;
  - false positives: static members inside `extern "C" { }` and `struct alignas(8) S { }` (the
    scan does not read those heads as scopes);
  - the blind spot the test's header names: a global without `static` or `inline`.
