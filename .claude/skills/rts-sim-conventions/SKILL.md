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
ADR 0013 (C++ kernels for the hot phases with GDScript twins, accepted 2026-10-12).
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
  re-integrated when the map changes. No slice on checkpoint ticks (`Sim.step` passes a budget
  of 0 to `FlowCache.run` on the ticks `MatchLoop` hashes). `flow_cells_per_tick` comes from
  the release run's headroom (ADR 0012 §5): 512 (P27b), which the rule gives with ADR 0013's C++
  slice, so P27f is withdrawn; never a literal in code. `FlowCache.configure()` sizes every
  slot's arrays once; nothing resizes them afterwards (ADR 0013 §2). References are
  derived from the World's `field` column every tick, never released by hand. A group move
  shares one field.
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
  the view which cells changed. Each player's dirty list is a fixed block of one flat
  `PackedInt32Array` with count and "full" arrays, sized in `configure()`; `begin_update` resets
  a count and never resizes (ADR 0013 §2).
- AI code reads the World only through `PlayerView` once it exists (reserved by ADR 0010). Easy
  and Normal AI read only their own player's visibility.

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
- Determinism does not depend on the mode: the golden hashes are equal in `SYNC` and `WORKER`.

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
- `SimProbe.Phase` ids are fixed (`COMMANDS` 0 to `FOG` 10, `COUNT` 11). A new phase takes an id
  in pipeline order through an ADR, never by renumbering.
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
  fails silently). `check_world(world, phase)` is pure and returns a status; a kernel that gets a
  non-zero status logs one error and returns without writing. No mismatch message is ever
  allowlisted.
- FLOW (§2, "Arrays of helper objects"): fetch the typed slot `Array` once, then each touched
  slot's arrays and scalars once (bounded by `flow_cache_size`, never per row or cell). The
  buffer swap is two `set` calls, after which both pointers are fetched again; no slot array is
  resized in a tick (P30b's `configure()` sizes them). One recorded exception (plan, P26m): the
  slot pick re-reads `pending` of every `ACTIVE` slot per pick, because reading it once would
  need a capacity literal.
- Forbidden: a `Packed*Array` parameter anywhere in `bind/` (by value or by reference: both write
  to a silent copy); keeping a pointer, Variant, array or Object between calls; `get` or `set`
  per row; calling back into GDScript while holding a `ptrw()` pointer; resizing a held array.
  The only resizes in a tick are the event appends, one per appending kernel after its loop.
- Two layers: `core/` is plain C++17 over the contract's `WorldView` and includes no Godot
  header. `WorldView` is realised as `ArrayView<T>` per array (`core/array_view.h`) "with
  flow::Slot as the aggregate" (`core/flow.h`: one FlowField slot's views and scalars, loaded
  and stored back per slot turn; the World and cache arrays reach `core/` as separate
  `ArrayView`s and ints, so `Slot` is no per-kernel aggregate); in the header's words, "The raw
  pointer is private, so core/ reaches an element only through get() and set()", "An index outside the window reads
  0 and writes nothing" and "Only bind/world_access.h builds a view from a pointer". `bind/`
  (`SimKernels`, `world_access.h`, `register_types`, one `kernel_<phase>.cpp` each, one line per
  kernel in `kernel_list.h`) is the only code that touches Godot types. A `core/` function lands
  only with the kernel that calls it, and that kernel's tests run in the same PR.
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

**Determinism in C++ (§4).**
- `int64_t` wherever GDScript holds an `int`. Every element read from an `int32` or `uint8` array
  is widened to `int64_t` before any arithmetic (through `ArrayView<T>::get`, which returns
  `int64_t`); raw `int32_t`/`uint8_t` pointers stay private to `ArrayView`, whose `set` and
  `fill` hold the explicit `static_cast` at the store. No
  `char`, `short`, `int` or `long` as a type in `core/`.
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
  - every declarator after the first in a view's pointer list (`const int32_t *pos_x, *pos_y;`
    collects only `pos_x`), and a view method that returns the raw pointer;
  - rarer float helpers missing from the word lists: `UtilityFunctions` `asinh`, `acosh`,
    `atanh`, `is_nan`, `is_inf`, `ease`, `remap` and similar; `std::` `nextafter`, `erf`,
    `tgamma` and similar;
  - a namespace-scope `static const StringName n(NAME);` and a function-local
    `static const auto x = make();` (static objects the scan does not see);
  - `std::array<const T, N>`: a `const` among the template arguments reads as a const variable;
  - false positives: static members inside `extern "C" { }` and `struct alignas(8) S { }` (the
    scan does not read those heads as scopes);
  - the blind spot the test's header names: a global without `static` or `inline`.
