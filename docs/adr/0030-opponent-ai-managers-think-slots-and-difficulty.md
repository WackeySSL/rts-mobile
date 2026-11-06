# ADR 0030: The opponent AI: managers, think slots, a counted budget, and difficulty as data

**In short, for Michael:** the computer opponent becomes one player made of five parts (economy,
production, intel and scouting, army, superweapon). Each part thinks once a second, the three
groups of parts on three different ticks, so no single tick carries the whole AI. It sees only
what its side sees. Easy, Normal and Hard are three data files with different numbers, never
three programs. Five questions at the end.

Status: **proposed**, 2026-11-06 (architect, docs row P170). Base: `main` at f51e3ff (the Phase 3
gate passed on 2026-11-05, issue #340). Plan: `docs/plans/2026-11-06-phase-4.md`. Michael said yes
to starting Phase 4 on 2026-11-06; nothing here is built before he accepts this ADR, ADR 0031 and
the plan. Amends ADR 0020 §2 (the think period of the new controller) and §4 (the Skirmish
routes leave the dummy); the dummy's own rules are unchanged (§9). Changes no sim rule, Command,
state column or golden hash, except the one conditional setup row of §8 (question 1).

## Context
- **ROADMAP Phase 4, box 1 and 2:** "AI with build orders from data, scouting, army grouping,
  attack waves and retreat"; "Easy, Normal and Hard as parameter sets".
- **GDD** (`docs/GDD.md`): pillar 4 (line 20), "Fair: the AI plays by the same rules and has no
  map vision it has not scouted"; "AI difficulty" (lines 123-126): Easy "slow reactions, weak build
  order, small attack waves", Normal "standard build order, scouting, mixed armies", Hard "better
  economy and unit control plus a 20% income bonus. No extra vision"; line 116: "The Phase 3 dummy
  opponent never builds or fires [a superweapon]; Phase 4's AI does."
- **`.claude/agents/ai-dev.md`:** three layers (strategy, operations, tactics); difficulty is
  parameters; "Decide every 15 ticks (1 second) ... Keep each decision under 1 ms on CI"; "Hard
  may get an income bonus from `data/ai/*.tres`, never map vision it has not scouted".
- **ADR 0020 (accepted) and the code as merged:**
  - `AiController` (`game/ai/AiController.gd:14-25`): `player_id`, `think_period`, `think_offset`,
    `rng`, `think(view, out)`. A controller keeps no Resource and no Node
    (`tests/core/test_tick_job.gd` walks the job).
  - `AiDriver.think_all` (`game/core/AiDriver.gd:82-108`) calls each due controller with a fresh
    `PlayerView.of(world, player)`, in player order, on ticks with `(tick + think_offset) %
    think_period == 0`; nothing thinks once the match has ended.
  - `TickJob.run` (`game/core/TickJob.gd:60-77`) calls `think_all` before `loop.step` on the
    thread that runs the job (the worker in `WORKER`). `job_usec` spans the thinks, the step, the
    hash and the capture; `step_usec` spans only `Sim.step`. **So a think lands in
    `job_minus_step`** (ADR 0016's watch line), on the half of the tick it runs on.
  - `MatchRunner._opponent_controllers` (`game/core/MatchRunner.gd:520-529`) builds
    `DummyAi.create(def, player, rng)` for each `AiDef` of `opponents` (line 142, not exported).
  - The dummy (`game/ai/DummyAi.gd`, `DummyDefence.gd`, `PlacementSpiral.gd`; 454 lines with
    `AiController` and `AiDef`) builds from a list of type ids, keeps `harvesters_wanted`
    harvesters per refinery, places on a fixed spiral (up to 64 tries per think,
    `data/ai/dummy_*.tres`) and defends within 12 tiles. It never attacks, uses no random number
    and never sends a dropped Command. It queues structures and places them when ready: the
    place-first path of ADR 0026 is in the sim but unused (Michael, 2026-11-05; P129 closed).
- **`PlayerView`** (`game/sim/PlayerView.gd:166-178`, tables at 306-321) gives own and seen rows,
  public columns, the player's economy and queues, explored cells, `placement`, and the last-seen
  records. It has no max hp, armour class, weapon range, sight, strike columns or warned ruptures,
  which retreat, counters and strikes need (§7).
- **Perf** (the lead's brief, 2026-11-06): the Phase 3 gate's release cards on the Pixel 9a read a
  sim job p95 of 6.4-7.3 ms against the 13.3 ms verdict, and the checkpoint half of ADR 0016's watch
  line 3.0-3.6 ms. Michael deferred P66/P66b on 2026-11-06 with this revisit trigger: any release
  card with `sim_p95_ms` above 10 ms or `job_minus_step_p95_cp_ms` above 5 ms. The phone ratios are
  in `data/dev/perf_gate.tres`: GDScript `ci_ratio_p95` 5.9, native 12.1. The AI is GDScript.
- **Flow cache:** `flow_cache_size` is 8 slots (`data/rules.tres:11`), keyed by goal cell and move
  class. Every distinct goal an AI gives costs a slot while units use it.
- **Sim randomness:** no Phase 3 sim rule draws a random number. If the AI drew none either, a
  hundred seeds would play one match a hundred times (§5).

## Decision

### 1. One controller, five managers, three layers
`OpponentAi extends AiController` (`game/ai/OpponentAi.gd`, ai-dev) plays one computer player. It
owns one `AiMemory` and five managers, each a `RefCounted` in its own file under `game/ai/`. The
layers are ai-dev.md's:

| Layer | Manager | Decides | Commands it sends |
| --- | --- | --- | --- |
| Strategy | `AiEconomy` | the build order from data, power upkeep, harvesters per refinery, rebuilding, where a structure goes | `QUEUE` (structures, tankers), `PLACE` |
| Strategy | `AiProduction` | the army's mix: role weights from data, shifted toward counters of what intel has seen | `QUEUE` (units), `RALLY` (to the staging point) |
| Operations | `AiIntel` | the sector map, the memory of sightings, the enemy base estimate, scouting | `MOVE` / `ATTACK_MOVE` of the one scout |
| Operations and tactics | `AiArmy` | squads, the staging point, defence, attack waves and their targets, retreat, Hard's unit retreat and focus fire | `ATTACK_MOVE`, `ATTACK`, `MOVE` |
| Tactics | `AiStrikes` | when and where the superweapon fires | `SUPERWEAPON` |

- A manager reads the `PlayerView` of the think and the shared `AiMemory`, appends Commands to the
  think's list and writes only its own part of the memory. Managers never call each other; the
  order inside a slot is fixed (§2).
- Every Command is checked before it is sent, as the dummy does: a `QUEUE` only for an item with a
  producer, room, its requirement owned and credits; a `PLACE` only where `placement` answers `OK`;
  unit orders only for own unit ids of this view; `ATTACK` only on a seen row; `SUPERWEAPON` only
  from an own, charged, online strike building. **The AI never sends a Command the sim drops**
  (`dropped_commands` stays 0; ADR 0031's harness fails on any).
- Names are functional (economy, intel, army); no personality, commander or doctrine is named,
  and no build order is modelled on an existing game's (§10).

### 2. Think cadence: period 5, three slots, never on a checkpoint tick
- `OpponentAi` has `think_period` 5. Its calls rotate through three slots, chosen from the tick
  (stateless): `slot = ((tick + think_offset) / think_period) % 3`.
  - **Slot 0, ECONOMY:** `AiEconomy`, then `AiProduction`.
  - **Slot 1, ARMY:** `AiIntel.refresh` (the sector map from this view), then `AiArmy`.
  - **Slot 2, INTEL:** `AiIntel` (memory, scouting), then `AiStrikes`.

  So every manager runs once per 15 ticks (1 s), as ai-dev.md asks, and a think tick carries about
  a third of the AI. The driver needs no change: it already calls a controller every
  `think_period` ticks with a fresh view.
- **No think on a checkpoint tick.** A checkpoint hashes in the step that starts at
  `tick % 15 == 14` (ADR 0020 §2). Player p's think ticks are `tick % 5 == (think_tick + p - 2) %
  5`; with `think_tick` 7 that is 1 for player 1 and 2 for player 2, so no think falls on a tick
  with `tick % 15 == 14`, and the two players of an AI-vs-AI match never think on the same tick. A
  data test pins both for players 1 and 2 (the MVP is 1 vs 1; a 3- or 4-player map needs a new
  rule here first, because four consecutive residues of 5 always meet 4).
- **Reaction delay** (difficulty, §6): a manager acts on a sighting, a threat or a loss only once
  it is `reaction_ticks` old in `AiMemory`. With the slot cadence the shortest reaction is one
  slot round (15 ticks).

### 3. State: `AiMemory`, ints only, ids never rows
- `AiMemory` (`game/ai/AiMemory.gd`) holds everything a controller keeps between thinks, as ints
  and packed int arrays: squads (role, state, target point, launch strength, member ids
  ascending), the scout's id and waypoint index, the last seen count and tick per enemy type, the
  first-seen tick of the current threat, the hp each own unit had at the last ARMY slot (for
  "hit by something unseen"), the wave counter, the staging point, the placement spiral's resume
  index and the work counters (§4).
- **Bounded:** every list is at most `unit_cap` (75) ids or a fixed count from data (squads 4,
  sectors 64, goal points 4). Sorted ascending where it is searched.
- **Ids, never rows:** a row index is good for one tick (`PlayerView`'s header). Memory keeps
  unit ids and positions; a think maps ids to rows through `view.row_of(id)`.
- **The last-seen buildings are the sim's** (`PlayerView.ghost_*`, ADR 0017 §3): the AI keeps no
  second copy of enemy buildings; it reads the ghosts and the seen rows each think.
- **Not in the World and not hashed.** A controller's state is a pure function of the views it got
  and its own stream; a replay holds its Commands and needs no AI (ADR 0020 §3). Phase 5's save and
  resume will need it written out: `AiMemory` keeps to ints so that a later `to_ints()` /
  `from_ints()` is a small row (named in the plan's risks, not built here).

### 4. The budget per think, and how a card shows it
- **Counted work, asserted in tests (deterministic).** Each think counts its work in
  `AiController.work` (reset at the start of a think) and the most of a match in `work_max`; each
  manager also counts its own items. The caps come from `OpponentDef` (§6), never from code:
  - one pass over the rows inside `PlayerView.of`, and at most two more passes over own and seen
    rows per slot;
  - the sector map: at most `sectors_max` (64) sectors, `sector_tiles` 8 on a 64 x 64 map;
  - placement: at most `place_tries_per_think` (8) `placement` calls, resuming the spiral where the
    last think stopped (the dummy asks up to 64 at once);
  - targets: at most `target_tests_max` (512) candidate tests per slot (a group's focus fire and a
    strike's point read sectors first, then the rows of the best sectors);
  - Commands: at most `commands_per_think_max` per think (Easy fewer, §6), and at most
    `goal_points_max` (4) distinct goal cells live per player at a time (staging, wave target,
    defence point, scout waypoint), all snapped to tile centres, so two AIs cannot churn the
    8-slot flow cache.
  The headless suites pin these bounds on fixed-seed matches; a session never times anything.
- **Time, on CI only.** A new perf suite (`tests/perf/test_ai_perf.gd`, plan row P189) runs two
  Normal AIs from the base arena's layout (`data/scenarios/perf_ai.tres`, P174) for 900 ticks and
  prints `WATCH ai think impl=<impl> slots=<n> p95_us=<..> max_us=<..> est_phone_p95_ms=<..>`
  (report-only, the phone estimate at `ci_ratio_p95` 5.9). **Target: a think slot's p95 at or
  below 0.15 ms on CI**, about 0.9 ms on the phone. After the last AI row, qa-engineer calibrates
  an `[ai]` ratchet in `tests/perf/budget.cfg` as P49b did (1.5 x the worst min-of-3 of 11 CI runs;
  P189b).
- **On the phone.** `TickJob` stamps `think_usec` (the clock after `think_all`, P182) into the
  snapshot. A new dev route "Perf AI" (P185) runs the perf scene on `perf_ai.tres` with two Normal
  AIs and its card prints, report-only: `ai_think_p95_ms` (over think ticks), `ai_think_max_ms`,
  `ai_thinks`, beside the usual verdicts with unchanged thresholds. Reading it:
  - the thinks fall on 3 of every 15 ticks per AI (6 of 15 in AI-vs-AI), more than the 5 % a p95
    ignores, so `sim_p95_ms` and `job_minus_step_p95_noncp_ms` show the dearest slot plus the step;
  - **`job_minus_step_p95_cp_ms` shows no AI**, because no think falls on a checkpoint tick (§2);
  - the watch value is `ai_think_p95_ms` at or below 1.0 ms. With the gate's 6.4-7.3 ms that keeps
    `sim_p95_ms` near 8.5 ms, under the lead's 10 ms revisit trigger.
- **Over budget:** more slots (period 5 to 3, five slots), smaller caps, cheaper sector reads,
  always in GDScript. Porting AI code to C++ is not on the table: ADR 0013 allows C++ only for the
  sim's hot-phase kernels, and a change would need its own ADR.
- **The web preview** runs `SYNC` on the main thread, so a think lands in a frame there; the web
  has no gate (ADR 0013 §7).
- `game/ai` stays exempt from the sim's allocation check (ADR 0020 §3's note); managers keep their
  scratch arrays between thinks (`resize`, not new arrays) where it is cheap to.

### 5. Randomness
- The only draws are from the controller's stream (`DetRandom.STREAM_AI_BASE + player`, made by
  `DetRng` in `MatchRunner` and by `DetRandom.create` in the headless harness, as today).
- **The AI draws on purpose, so seeds differ:** a wave's start jitter (`wave_jitter_ticks`), the
  next unit among the affordable roles (a weighted draw on the role weights), ties between equal
  targets, and the scout's order among equal sectors. Each draw count per think is bounded.
  Without them a hundred seeds would replay one match; ADR 0031's report checks that the final
  hashes differ.
- No float, no clock, no `Dictionary` key order: lists are packed arrays in ascending id or fixed
  sector order.

### 6. Data: three resources in `data/ai/`
All numbers below are starting values (marked P) for the balance runs of ADR 0031; ai-dev owns
the files, and the data tests pin script defaults equal to the files.
- **`AiDifficultyDef`** (`game/ai/AiDifficultyDef.gd`; `data/ai/difficulty/easy.tres`,
  `normal.tres`, `hard.tres`): one parameter set per level, the only difference between levels.

  | Field | Easy | Normal | Hard | Meaning |
  | --- | --- | --- | --- | --- |
  | `build_order_tier` | 0 weak | 1 standard | 2 strong | which build order of the faction's `OpponentDef` |
  | `reaction_ticks` | 90 | 30 | 15 | age a sighting or threat must have before it is acted on |
  | `harvesters_per_refinery` | 1 | 2 | 2 | the refinery's free tanker included |
  | `refineries_max` / `factories_max` / `defences_max` | 1 / 1 / 1 | 2 / 1 / 2 | 2 / 2 / 3 | caps of the loop after the build order |
  | `scout_first_tick` / `scout_interval_ticks` | 0 / 0 (no scout) | 1800 / 2700 | 1350 / 1800 | GDD: Normal scouts |
  | `wave_first_tick` | 6300 | 4050 | 3600 | earliest first wave |
  | `wave_first_strength` | 2000 | 4000 | 5000 | army value (credits, hp-scaled) that launches the first wave |
  | `wave_growth_percent` / `wave_jitter_ticks` | 10 / 450 | 25 / 300 | 30 / 150 | each wave asks this much more; start jitter |
  | `all_in_tick` | 12600 | 10800 | 9900 | from here every combat unit joins the waves (ends stalemates) |
  | `retreat_percent` / `retreat_ratio_percent` | 0 / 0 (never) | 40 / 200 | 50 / 150 | a group pulls back below this share of its launch value, or when the enemy value near it passes this ratio |
  | `unit_retreat_hp_percent` / `focus_fire` | 0 / 0 | 0 / 0 | 30 / 1 | Hard's unit control |
  | `counter_percent` | 0 | 30 | 60 | how far the mix shifts toward counters of what was seen |
  | `uses_strike` | 0 | 1 | 1 | question 2 |
  | `commands_per_think_max` | 3 | 8 | 12 | Easy's slow hands |
  | `income_percent` | 100 | 100 | 100 (120 only on question 1's A or C trigger) | §8 |

- **`OpponentDef extends AiDef`** (`game/ai/OpponentDef.gd`; `data/ai/opponent_fossil.tres`,
  `opponent_renew.tres`): one per faction. It inherits `hq_type`, `harvester_type`,
  `place_stride_tiles`, `defend_radius_tiles`, `guard_offset_tiles`, `think_period` (5 here) and
  `think_tick` (7), and adds: the role table (`scout_type`, `anti_infantry_type`,
  `anti_vehicle_types`, `tank_type`, `artillery_type`, `defence_type`, `strike_type`), role weights
  per tier, `build_orders: Array[AiBuildOrderDef]` by tier, `staging_offset_tiles`, `sector_tiles`,
  `place_tries_per_think`, `target_tests_max`, `goal_points_max`, `strike_min_value`. A def lists
  only its faction's type ids (a data test walks every id against the faction's roster and its
  `requires` chain, as `test_ai_def_data.gd` does for the dummy).
- **`AiBuildOrderDef`** (`data/ai/build_orders/<faction>_<tier>.tres`, six files): `steps:
  Array[StringName]` with the dummy's meaning (the player wants as many of a type as the list has
  up to the item, so a lost building is wanted again at its place), then the loop of §1's economy
  row (power when the margin falls under `power_margin`, refineries, factories and defences up to
  the difficulty's caps). The weak tier has no radar and no strike building; the strong tier gets
  the second refinery and the factory earlier.
- **Building the controller:** `AiFactory.create(def: AiDef, level: AiDifficultyDef, player: int,
  rng: DetRandom) -> AiController` (`game/ai/AiFactory.gd`): an `OpponentDef` gives `OpponentAi`, a
  plain `AiDef` gives `DummyAi` (the level is ignored). `MatchRunner` gains `opponent_levels:
  Array[AiDifficultyDef]` beside `opponents` (typed, not exported, for ADR 0020 §3's note's leak),
  and `_opponent_controllers` calls the factory (lead, P182).
- **The managers in short** (each row's acceptance in the plan holds the detail):
  - *Economy:* the tier's steps, then the loop; power upkeep before any consumer; harvesters per
    refinery; rebuilds in order; placement on `PlacementSpiral` round the Headquarters, resumed
    across thinks; a defence goes to the free slot nearest the enemy base estimate.
  - *Production:* both unit queues kept at `queue_target`; the next unit is a weighted draw over
    the roles whose type can be queued, the weights shifted by `counter_percent` toward the role
    whose weapon does most against the armour classes intel has seen most of
    (`type_vs_armour`, §7); the build order's next structure keeps its credits first.
  - *Intel:* the sector map (own and enemy value per sector, from the view's rows and ghosts); the
    enemy base estimate: the seen or remembered enemy producer nearest to the own Headquarters,
    else the point mirror of the own Headquarters (`map - 1 - tile` on both axes); scouting with
    one unit of the scout role, first to that mirror point, then to the nearest unexplored
    sectors, home when hit.
  - *Army:* new combat units gather at the staging point (`staging_offset_tiles` from the
    Headquarters toward the base estimate); a threat within `defend_radius_tiles` of a building
    calls the home squad (and a wave in the field when the threat outweighs the home squad by
    `retreat_ratio_percent`); a unit hit by something unseen moves its squad a few tiles toward the
    base estimate (ADR 0009: "an idle unit hit from beyond its weapon range does not react. The
    Phase 4 AI handles that"); a wave launches when the home squad's value reaches the wave's
    strength and the tick has passed `wave_first_tick` plus its jitter, and attacks the nearest
    known enemy producer or Headquarters (the outcome rule's buildings), else the base estimate;
    it re-targets when the target is gone; it retreats with `MOVE` (no fire on the way, ADR 0009
    §2) to the staging point and rejoins the home squad. Hard's units under
    `unit_retreat_hp_percent` step back on their own, and Hard's groups `ATTACK` the weakest seen
    enemy in reach (bounded by `target_tests_max`).
  - *Strikes:* a Deep Bore fires on the point of the most enemy value within its radius with no own
    row inside it, once the value passes `strike_min_value`; a Blackout Array fires on the enemy's
    producer cluster as a wave launches against it. Both read only seen rows and ghosts.

### 7. `PlayerView` v2 (gameplay-dev, P172): the reads the managers need, nothing hidden
Added, all from data a player may know or its own state, so pillar 4 holds:
- **Type tables** (copies, as today): `type_max_hp`, `type_armour`, `type_range`, `type_min_range`,
  `type_sight`, `type_faction`, `type_strike_kind`, `type_strike_radius`, `type_charge_ticks`, and
  `type_vs_armour` (the type's weapon's percent against each armour class, flat `type * 4 +
  class`).
- **Own rows:** `row_ready_tick` (a strike building's charge) and `row_offline_until` (an own
  building that a blackout hit).
- **Warned ruptures:** the pending strikes every player sees (ADR 0023 §10's 3 s warning), as
  copies `warned_x`, `warned_y`, `warned_tick`.
- **Rule caps:** `unit_cap`, `building_cap`.
No enemy order, cargo, charge, credits or queue is exposed. `PlayerView` stays read-only, so no
hash moves.

### 8. Difficulty is parameters; the AI never sees more than its side
- One code path for all three levels; only `AiDifficultyDef` differs. A test runs the same seed at
  two levels and checks that the controllers are the same class with different ints.
- **Vision:** never. Every level reads only `PlayerView` (the `game/ai` scan of
  `test_view_reads_snapshot.gd` and `test_sim_purity.gd` stays). The point-mirror guess of §6 is
  map knowledge a player has too, not a sight of the enemy.
- **Resources:** the AI gets nothing a player cannot, unless Michael chooses otherwise (question
  1). The GDD and ai-dev.md already name a 20 % income bonus for Hard; this ADR asks again because
  it is the one place the AI would not play by the same rules. If he chooses a bonus, it is match
  setup, not a cheat in the AI's code: row P173 adds `World.income_percent` per player (set at load
  from the opponent's level, 100 for a human), applied where a tanker unloads (`credits +=
  ore * credits_per_ore * income_percent / 100`), outside the state hash and inside `defs_hash`
  like the rule ints, and carried in the replay's header (`Replay.FORMAT` 2). At 100 the
  arithmetic is the same, so **no golden hash moves** (the golden suites prove it in P173). The
  Skirmish setup then shows the bonus beside "Hard".

### 9. The dummy stays (question 4)
`DummyAi`, `DummyDefence`, `PlacementSpiral` and `data/ai/dummy_*.tres` stay as they are: the
Phase 3 suites, the end-to-end tests (`tests/e2e/`, the scripted player against the dummy) and
ADR 0031's nightly baseline ("Easy beats the dummy") use them. `OpponentAi` reuses
`PlacementSpiral`. The Skirmish routes switch to `OpponentAi` in P183, once it defends (P179), so
the player never meets an AI weaker than the dummy. ADR 0020's §1-§3 and §5 hold for both
controllers.

### 10. Legal
No name, personality, faction doctrine, build order or AI behaviour is taken from Command &
Conquer, Red Alert, OpenRA or any other game; no code from EA's release or OpenRA. Difficulty
names are the GDD's generic Easy, Normal, Hard. Managers have plain functional names. Build orders
are written from this game's own roster and `requires` chains.

## Consequences
- The AI's cost is spread over three ticks of fifteen and counted; it shows on the phone as its own
  key and never on a checkpoint tick. The noncheckpoint half of the watch line and `sim_p95_ms` will
  rise by about the dearest slot in matches against the AI.
- Balance tuning has three knobs per level and a role table per faction, all data; ADR 0031's
  nightly reads their effect.
- `PlayerView` grows by a dozen copied tables (read-only). `MatchRunner` builds controllers through
  one factory.
- Two controllers exist side by side: the dummy for tests and baselines, the opponent for players.
- The AI's behaviour lives in data and five small files, so Phase 5's tutorial can script an Easy
  opponent with its own `AiDifficultyDef` without new code.

## Alternatives considered
- **One think every 15 ticks doing everything** (ADR 0020's dummy cadence): simplest, but the whole
  AI lands on one tick, and the p95 reads it whole (1 tick in 14 of the noncheckpoint ticks is above
  5 %). Rejected for the slots.
- **A small slice of AI work on every tick:** the lowest peak, but a `PlayerView` per tick and a
  manager split across ticks that sees a different view each time. Rejected.
- **Behaviour trees or utility AI with a generic engine:** more code than the five decisions need,
  harder to bound and to read in a 400-line PR.
- **A cheating Hard (more vision):** against pillar 4 and ai-dev.md; never.
- **Porting the AI to C++:** outside ADR 0013's scope (hot sim kernels only), and a second
  implementation of fast-changing code.
- **Replacing the dummy:** loses a fixed baseline and rewrites the Phase 3 end-to-end suites.

## Questions for Michael
1. **Hard and money.** The GDD says Hard gets 20 % more income (never more vision). That is the
   one place the computer would not play by your rules.
   - A: keep the GDD: Hard gets +20 % income from the start, and the Skirmish setup says so.
   - B: no bonus: Hard is only better play (economy, reactions, retreat, focus fire).
   - C: no bonus first; the +20 % comes only if the nightly shows Hard winning under 60 % of its
     matches against Normal.
   Recommended: **C** (fair first, the bonus ready if better play is not enough).
2. **Superweapon.** Which levels build and fire their side's superweapon?
   - A: Normal and Hard; Easy never builds it.
   - B: all three.
   - C: none in Phase 4.
   Recommended: **A**.
3. **Choosing the level in Phase 4.** Phase 5 brings the real menus.
   - A: three buttons (Easy, Normal, Hard; Normal chosen) in the dev menu above the two Skirmish
     buttons; Restart and "Play again" keep the level.
   - B: no choice until Phase 5; the Skirmish always plays Normal.
   Recommended: **A** (you need it for the gate's phone check).
4. **The Phase 3 dummy** stays as a test opponent and a fixed yardstick in the nightly run ("Easy
   must beat the dummy"), and the Skirmish plays the new AI from row P183 on. (ja/nej; recommended:
   **ja**)
5. **ai-dev's time rule.** `.claude/agents/ai-dev.md` says "Keep each decision under 1 ms on CI".
   On the phone 1 ms on CI is about 6 ms, which would push the sim toward your 10 ms revisit line.
   May the lead change it to "each think slot at most 0.15 ms p95 on CI (the `WATCH ai think`
   line), about 1 ms on the phone"? (ja/nej; recommended: **ja**)
