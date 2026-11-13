# ADR 0030: The opponent AI: managers, think slots, a counted budget, and difficulty as data

**In short, for Michael:** the computer opponent becomes one player made of five parts (economy,
production, intel and scouting, army, superweapon). Each part thinks once a second, the three
groups of parts on three different ticks, so no single tick carries the whole AI. It sees only
what its side sees. Easy, Normal and Hard are three data files with different numbers, never
three programs. Michael answered the three questions on 2026-11-06 (Acceptance note).

Status: **accepted, 2026-11-06** (Michael: 1 C, 2 A, 3 ja; Acceptance note below). Proposed
2026-11-06 (architect, docs row P170, PR #345); revised the same day after the lead's docs lens on
fe338f5 (ten blockers, 29 nits); accepted by the docs row P170b on the same PR. Base: `main` at
f51e3ff (the Phase 3 gate passed on 2026-11-05, issue #340). Plan:
`docs/plans/2026-11-06-phase-4.md`. Amends ADR 0020 §2 (the think
period and tick of the new controller; who is seated where) and §4 (the Skirmish routes leave the
dummy); the dummy's own rules are unchanged (§9). Changes no sim rule, Command, state column or
golden hash, except the one conditional setup row of §8 (answer 1 C).

Status note (2026-11-06, P26bd docs; wave 1 merged: P171 #349, P172 #347, P184 #348, main
98f0a3a): §7 gains one read, `own_strike_tick`, and §4's code pointer moves; the note at the end
of §7 says what and why. §4's "`PerfHud.gd:438`" now reads `PerfHud.record_snapshot`, where the
card keeps the checkpoint ticks apart (P184 moved the card's text to `PerfCard.gd`). The Phase 4
plan's live P181 rows name the Lumen Accord's strike building Dusk Array (ADR 0032); §6's "a
Blackout Array fires" keeps the name of its day (read Dusk Array, ADR 0032 §7). No accepted text
changed; this note amends §4's pointer.

Status note (2026-11-06, P26be docs; wave 2 merged: P174 #352, P175 #353, P171b #354, main
9c16815): the reviews of wave 3 (P176 economy, P177 and P177b intel and scouting) found two gaps
and one reading in §6 and one gap in §1, and the lead decided them. The note at the end of §6
records them; P182's `think_usec` of at least 1 on a think tick (§4) is in the plan's note under
"Interface contracts". No accepted text changed; the note makes one exception to §1's field "that
P175 declares" (`scout_wanted`, declared by P177b).

Status note (2026-11-07, P26bf docs; wave 3 merged: P176 #355, P177 #358, P177b #359, P182 #356,
main fd4eb15): the reviews of wave 4 (P178 production, P179 the army's first part) decided how the
ARMY slot keeps §4's pass budget, who yields a goal key at the cap, and how production counts the
economy's QUEUEs of the same think; the note at the end of §4 records them. No accepted text
changed; the note makes a second exception to §1's field "that P175 declares" (the army's input
lists), one to §1's "writes only its own part of the memory" (the army releases the scout's key at
the cap) and one to §3's "every id list is at most `unit_cap`" (the seen list holds up to
(players - 1) times `unit_cap`, the same bound when two players play).

Status note (2026-11-07, P26bg docs; wave 4 merged: P178 #362, P179 #363, main 0781901): the
reviews of wave 5 (P179b the unseen-hit response, P180 the army's waves) decided how the unseen
hit and the waves read §6's *Army* line; the note at the end of §4 records them. No accepted text
changed. The note makes one exception to §2's reaction delay (a hit is answered at once) and one
to §4's cap of `target_tests_max` tests per slot (the hit's range tests have their own cap). It
makes a third exception to §1's field "that P175 declares" (`unit_hp` and `seen_site_id`,
declared by P179b). It reads §6's "moves its squad's goal" as the home squad's, and it moves §6's
wave recall in the field to row P180b.

Status note (2026-11-07, P26bh docs; wave 5 merged: P179b #365, P180 #366, main f3e80f8): the
reviews of wave 6 (P180b Hard's unit control and the recall, P181 the strikes, P183 the level
choice) decided how §2's reaction delay in the field, §4's single cap, §4's "sectors first", §6's
*Army* recall and §6's *Strikes* are read; the third note at the end of §4 records them. No accepted
text changed. The note makes a fourth exception to §1's field "that P175 declares"
(`own_mobile_id`, `seen_mobile_id` and the sector grid, filled by `AiIntel` for `AiStrikes`,
declared by P181) and one to §3's "every id list is at most `unit_cap`" (`seen_mobile_id`).

Status note (2026-11-09, P26bi docs; wave 6 merged: P180b #370, P183 #368, P181 #369, main
f3a63d8): the reviews of wave 7 decided how §6's *Strikes* reads after a recall (P181b's staging
stand-in), what §4's time line carries and times (P189: `thinks=`, two more `WATCH ai` lines, a
workload without contact until P189b) and when §4's flow-cache choice is made; the fourth note at
the end of §4 records them. P188's and P190's decisions are in ADR 0031's notes, P185's in the
plan. No accepted text changed; the note adds `thinks=` to §4's `WATCH ai think` keys.

Status note (2026-11-09, P26bj docs; wave 7 merged: P181b #372, P185 #375, P188 #373, P189 #374,
P190 #376, main b6bfe95): balance run 1 and the reviews of P189b and P194 decided §4's flow-cache
choice (P194, `flow_cache_size` 12 in the shipped rules), the timed workload (contact since P189b,
on the card too) and what §4's "the Perf AI card measures it" now means; the fifth note at the end
of §4 records them. The previous status note's "a workload without contact until P189b" and the
fourth note's "no contact" and "191 of 900" describe P189's workload, not P189b's. No accepted
text changed.

Status note (2026-11-09, P230/P270b docs; ADRs 0036 and 0037 accepted 2026-11-09): the managers
gain duties and no new manager: ADR 0036 §14 (air tiers, layer-aware counters, raids, the
satellite on Normal and Hard, fired once charged) and ADR 0037 §10 (mend, repair, medics, rides,
`AiMines` in `AiStrikes`' slot, `hold_types`). Easy builds no space centre, engineering centre,
transport or wave-3 unit. No accepted text changed.

## Acceptance note (2026-11-06)
Michael answered the eight questions of this ADR and ADR 0031 in chat on 2026-11-06. The lead had
numbered them 1-8 in chat (1-3 are this ADR's, 4-8 are ADR 0031's). Verbatim: "1 C, 2 A, 3 Ja, 4 A,
5 A, 6 forstår ikke hvordor der er noget der skla køre om natten? er det ikke et færdig spil uden
noget server? men hvis jeg skal vælge lyder A fornuftigt, 7 Ja, 8 A."

The lead records this ADR's three as "1 C, 2 A, 3 ja":
1. **C (Hard and money):** no income bonus at first; Hard is better play only. Once the AI is
   complete (P181) and the first balance report has merged (P191), the lead runs one 100-match
   Hard-against-Normal set on held-out seeds (the plan's "Gate procedure", step 0). If Hard's share
   is under 600 per-mille, P173 and P183b run (+20 % income on Hard, shown beside its button);
   otherwise both are withdrawn. Options A (the bonus from the start) and B (never a bonus) were
   not chosen.
2. **A (superweapon):** Normal and Hard build and fire their side's superweapon; Easy never builds
   it (`uses_strike` 0, and the weak build-order tier has no radar and no strike building).
   Options B (all levels) and C (none) were not chosen.
3. **ja (the two rule files):** the lead updated `.claude/agents/ai-dev.md` (lines 3 and 19) and
   `.claude/skills/balance-report/SKILL.md` (lines 9 and 12, steps 1 and 5) in P170b, as question 3
   words it, with "nightly" read as "balance run" after Michael's follow-up on ADR 0031's question
   3 (ADR 0031's Acceptance note). The question below is kept as it was asked.

The decision below is the accepted text; P170b changed only the status, this note, the wording that
named open answers, and the questions' "answered" marks. The two lead decisions stay lead
decisions. Nothing is applied in code yet: the plan's rows apply it.

## Context
- **ROADMAP Phase 4, box 1 and 2:** "AI with build orders from data, scouting, army grouping,
  attack waves and retreat"; "Easy, Normal and Hard as parameter sets".
- **GDD** (`docs/GDD.md`): pillar 4 (line 20), "Fair: the AI plays by the same rules and has no
  map vision it has not scouted"; "AI difficulty" (lines 123-126): Easy "slow reactions, weak build
  order, small attack waves", Normal "standard build order, scouting, mixed armies", Hard "better
  economy and unit control plus a 20% income bonus. No extra vision"; line 116: "The Phase 3 dummy
  opponent never builds or fires [a superweapon]; Phase 4's AI does."
- **`.claude/agents/ai-dev.md`:** three layers (strategy, operations, tactics); difficulty is
  parameters; line 19 "Decide every 15 ticks (1 second) ... Keep each decision under 1 ms on CI";
  lines 14-15 "Hard may get an income bonus from `data/ai/*.tres`, never map vision it has not
  scouted".
- **ADR 0020 (accepted) and the code as merged:**
  - `AiController` (`game/ai/AiController.gd:14-25`): `player_id`, `think_period`, `think_offset`,
    `rng`, `think(view, out)`. A controller keeps no Resource and no Node
    (`tests/core/test_tick_job.gd` walks the job).
  - `AiDriver.think_all` (`game/core/AiDriver.gd:19-45`) calls each due controller with a fresh
    `PlayerView.of(world, player)`, in player order, on ticks with `(tick + think_offset) %
    think_period == 0`; nothing thinks once the match has ended. It returns nothing.
  - `TickJob.run` (`game/core/TickJob.gd:60-77`) calls `think_all` before `loop.step` on the
    thread that runs the job (the worker in `WORKER`). `job_usec` spans the thinks, the step, the
    hash and the capture; `step_usec` spans only `Sim.step`. **So a think lands in
    `job_minus_step`** (ADR 0016's watch line), on the half of the tick it runs on.
  - `MatchRunner` seats computer players from player 2 up (`FIRST_OPPONENT` 2,
    `game/core/MatchRunner.gd:59-60`; "player 1 is the human", `:133-134`; `opponents`, `:142`, not
    exported) and `_opponent_controllers` (`:520-529`) builds `DummyAi.create(def, player, rng)`.
    The perf scene drives a `MatchRunner` too (`game/ui/perf_arena.gd:76`).
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
  line 3.0-3.6 ms. **Michael** deferred P66/P66b on 2026-11-06 with his revisit trigger: any release
  card with `sim_p95_ms` above 10 ms or `job_minus_step_p95_cp_ms` above 5 ms. The phone ratios are
  in `data/dev/perf_gate.tres`: GDScript `ci_ratio_p95` 5.9, native 12.1. The AI is GDScript.
- **Flow cache:** 8 slots (`flow_cache_size`, `data/rules.tres:11`), each keyed by **goal cell,
  move class and map version** (`game/sim/FlowCache.gd:3`, `acquire` at `:86-116`). Infantry move
  as FOOT (class 0, `UnitDef`'s default) and every vehicle as TRACKED (class 2), so one goal for a
  mixed group takes two slots. A unit that finds every slot referenced steers straight
  (`Movement.gd:209-212`) and can stall behind a wall. A placement bumps `map_version`, so old keys
  die with it.
- **Sim randomness:** no Phase 3 sim rule draws a random number. If the AI drew none either, a
  hundred seeds would play one match a hundred times (§5).

## Lead decisions (recorded, not questions)
- **The level is chosen in the dev menu in Phase 4** (it was question 3 of the first draft): three
  buttons, Easy, Normal and Hard, Normal chosen at start, above the two Skirmish buttons; Restart
  and "Play again" keep the level. The gate's phone check plays every level, so the choice cannot
  wait for Phase 5's menus. Plan row P183.
- **The dummy stays** (it was question 4 of the first draft): `DummyAi`, `DummyDefence`,
  `PlacementSpiral` and `data/ai/dummy_*.tres` remain as the Phase 3 suites' and end-to-end tests'
  opponent and as the balance run's fixed yardstick ("Easy beats the dummy", ADR 0031 §5). It is
  test infrastructure (§9).

## Decision

### 1. One controller, five managers, three layers
`OpponentAi extends AiController` (`game/ai/OpponentAi.gd`, ai-dev) plays one computer player. It
owns one `AiMemory` and five managers, each a `RefCounted` in its own file under `game/ai/`. The
layers are ai-dev.md's:

| Layer | Manager | Decides | Commands it sends |
| --- | --- | --- | --- |
| Strategy | `AiEconomy` | the build order from data, power upkeep, harvesters per refinery, rebuilding, where a structure goes | `QUEUE` (structures, tankers), `PLACE` |
| Strategy | `AiProduction` | the army's mix: role weights from data, shifted toward counters of what intel has seen | `QUEUE` (units) |
| Operations | `AiIntel` | the sector map, the memory of sightings, the enemy base estimate, scouting | `MOVE` / `ATTACK_MOVE` of the one scout |
| Operations and tactics | `AiArmy` | the staging point, squads, defence, attack waves and their targets, retreat, Hard's unit retreat and focus fire | `RALLY` (the one rally to the staging point), `ATTACK_MOVE`, `ATTACK`, `MOVE` |
| Tactics | `AiStrikes` | when and where the superweapon fires | `SUPERWEAPON` |

- A manager reads the `PlayerView` of the think and the shared `AiMemory`, appends Commands to the
  think's list and writes only its own part of the memory. Managers never call each other; the
  order inside a slot is fixed (§2). Where one manager uses another's result, it reads a memory
  field that P175 declares with a "none" value, so a manager's row can be built and tested before
  the row that fills the field (the staging point, written by `AiArmy`, read by `AiEconomy` for
  defence placement).
- Every Command is checked before it is sent, as the dummy does: a `QUEUE` only for an item with a
  producer, room, its requirement owned and credits; a `PLACE` only where `placement` answers `OK`;
  unit orders only for own unit ids of this view; `ATTACK` only on a seen row; `SUPERWEAPON` only
  from an own, charged, online strike building and not while the player's rupture is pending.
  **The AI never sends a Command the sim drops** (`dropped_commands` stays 0; ADR 0031's harness
  fails on any).
- Names are functional (economy, intel, army); no personality, commander or doctrine is named,
  and no build order is modelled on an existing game's (§10).

### 2. Think cadence: period 5, three slots, never on a checkpoint tick
- `OpponentAi` has `think_period` 5. Its calls rotate through three slots, chosen from the tick
  (stateless): `slot = ((tick + think_offset) / think_period) % 3`.
  - **Slot 0, ECONOMY:** `AiEconomy`, then `AiProduction`.
  - **Slot 1, ARMY:** `AiIntel.refresh` (the sector map from this view), then `AiArmy`.
  - **Slot 2, INTEL:** `AiIntel` (memory, scouting), then `AiStrikes`.

  So every manager runs once per 15 ticks (1 s), as ai-dev.md asks, and a think tick carries about
  a third of the AI. The driver's turn rule needs no change.
- **No think on a checkpoint tick, for players 1 to 4.** A checkpoint hashes in the step that
  starts at `tick % 15 == 14` (ADR 0020 §2), so a think must never fall on `tick % 5 == 4`.
  `OpponentDef.think_tick` is **6**, and the offset is the dummy's formula,
  `think_offset = posmod(-(think_tick + p - 2), 5)`, so player p thinks on `tick % 5 == (p + 4) %
  5`: player 1 on residue 0, player 2 on 1, player 3 on 2, player 4 on 3, never on 4. A data test
  pins players 1 to 4 (the dummy's suite pins 2 to 4 the same way,
  `tests/ai/test_ai_def_data.gd:165-174`). As a side effect no two players think on the same
  tick.
- **Reaction delay** (difficulty, §6): a manager acts on a sighting, a threat or a loss only once
  it is `reaction_ticks` old in `AiMemory`. With the slot cadence the shortest reaction is one
  slot round (15 ticks).

### 3. State: `AiMemory`, ints only, ids never rows
- `AiMemory` (`game/ai/AiMemory.gd`) holds everything a controller keeps between thinks, as ints
  and packed int arrays: the staging point, squads (role, state, goal point, launch value, member
  ids ascending), the scout's id and waypoint index, the last seen count and tick per enemy type,
  the first-seen tick of the current threat, the hp each own unit had at the last ARMY slot (for
  "hit by something unseen"), the wave counter, the live goal keys (§4) and the placement spiral's
  resume index.
- **Bounded:** every id list is at most `unit_cap` (75); squads at most `OpponentDef.squads_max`
  (P: 4); sectors at most `sectors_max` (P: 64); goal keys at most `goal_keys_max` (§4). Sorted
  ascending where it is searched.
- **Ids, never rows:** a row index is good for one tick (`PlayerView`'s header). Memory keeps unit
  ids and positions; a think maps ids to rows through `view.row_of(id)`.
- **The last-seen buildings are the sim's** (`PlayerView.ghost_*`, ADR 0017 §3): the AI keeps no
  second copy of enemy buildings; it reads the ghosts and the seen rows each think.
- **Not in the World and not hashed.** A controller's state is a pure function of the views it got
  and its own stream; a replay holds its Commands and needs no AI (ADR 0020 §3). Phase 5's save and
  resume will need it written out: `AiMemory` keeps to ints so that a later `to_ints()` /
  `from_ints()` is a small row (named in the plan's risks, not built here).
- **Counters** live on `AiController` as plain ints, so a harness reads any controller without a
  cast: `work` (reset at the start of a think), `work_max`, `waves`, `retreats`, `scouts`,
  `strikes`, `commands`. `DummyAi` leaves them 0 except `commands`.

### 4. The budget per think, the flow cache, and how a card shows it
- **Counted work, asserted in tests (deterministic).** Each think counts its work in
  `AiController.work`, and each manager its own items. The caps are `OpponentDef` fields (§6),
  never code literals:
  - one pass over the rows inside `PlayerView.of`, and at most two more passes over own and seen
    rows per slot;
  - the sector map: at most `sectors_max` sectors of `sector_tiles` (P: 8, so 64 on a 64 x 64 map);
  - placement: at most `place_tries_per_think` (P: 8) `placement` calls, resuming the spiral where
    the last think stopped (the dummy asks up to 64 at once);
  - targets: at most `target_tests_max` (P: 512) candidate tests per slot (focus fire and a
    strike's point read sectors first, then the rows of the best sectors);
  - Commands: at most `AiDifficultyDef.commands_per_think_max` per think (§6).
  The headless suites pin these bounds on fixed-seed matches; a session never times anything.
- **Flow-cache keys** (the cap counts keys, not points). A key is a (goal cell, move class) pair
  that the AI's live orders use; a group of infantry and vehicles sent to one cell is two keys.
  `OpponentDef.goal_keys_max` (P: **4**) caps the AI's live keys. Which order uses which goal:

  | Order | Goal | Keys |
  | --- | --- | --- |
  | `RALLY` of new units; a group's retreat; Hard's unit step-back; the return after a defence | the staging point | up to 2 (FOOT, TRACKED) |
  | A wave's `ATTACK_MOVE`; a defence's `ATTACK_MOVE`; the unseen-hit shift; Hard's focus-fire `ATTACK` | the **army goal**: one cell at a time, replaced, never added | up to 2 |
  | The scout's `MOVE` | its waypoint | 1 (TRACKED), only while the army goal is free or single-class |

  So one AI holds at most 4 keys, and a Normal-vs-Normal match up to 8, which is the whole cache
  before tankers and fights. The harness counts `flow_full_ticks` (ticks after which every slot is
  referenced; ADR 0031 §1), P188 and P189 report it on their matches and the balance run on every
  match. If it is above 0, the lead chooses, by data: `goal_keys_max` 3 (the rally follows the
  army goal, so the staging point holds no keys while a wave is out), or the conditional plan row
  P194, `flow_cache_size` 12 in the shipped `data/rules.tres` (gameplay-dev). P194 moves no golden
  (the arenas' frozen rules keep 8, ADR 0031 §8), costs memory once at `configure` (four more
  fields of `cols x rows` cells) and adds a few slots to each `acquire` scan; integration stays
  sliced by `flow_cells_per_tick`, and the Perf AI card measures it.
- **Time, on CI only.** A new perf suite (`tests/perf/test_ai_perf.gd`, plan row P189) runs two
  Normal AIs from the base arena's layout (`data/scenarios/perf_ai.tres`, P174, on frozen defs)
  for 900 ticks and prints `WATCH ai think impl=<impl> slots=<n> p95_us=<..> max_us=<..>
  est_phone_p95_ms=<..>` (report-only, the phone estimate at `ci_ratio_p95` 5.9). **Target: a
  think slot's p95 at or below 0.15 ms on CI**, about 0.9 ms on the phone. After the last AI row,
  qa-engineer calibrates an `[ai]` ratchet in `tests/perf/budget.cfg` as P49b did (P189b).
- **On the phone.** `TickJob` stamps `think_usec` into the snapshot (P182; `AiDriver.think_all`
  returns how many controllers thought, so the field is 0 on a tick without a think). A dev route
  "Perf AI" (P185) runs the perf scene on `perf_ai.tres` with an `OpponentAi` on **each** player:
  P182 gives `MatchRunner` a `first_opponent` (default 2, typed, not exported; 1 seats a computer
  player on player 1 too, the local view stays player 1's). The card prints, report-only:
  `ai_think_p95_ms` (over think ticks), `ai_think_max_ms`, `ai_thinks`, beside the usual verdicts
  with unchanged thresholds. Reading it:
  - the two AIs think on 6 of every 15 ticks, more than the 5 % a p95 ignores, so `sim_p95_ms`
    and `job_minus_step_p95_noncp_ms` show the dearest slot plus the step;
  - **`job_minus_step_p95_cp_ms` shows no AI**, because no think falls on a checkpoint tick (§2;
    the card's checkpoint snapshots are `snap.tick % 15 == 0`, `PerfHud.gd:438`);
  - the watch value is `ai_think_p95_ms` at or below 1.0 ms. With the gate's 6.4-7.3 ms that keeps
    `sim_p95_ms` near 8.5 ms, under Michael's 10 ms revisit trigger. A card above his trigger goes
    back to him for P66/P66b.
- **Over budget:** more slots (period 5 to 3, five slots), smaller caps, cheaper sector reads,
  always in GDScript. Porting AI code to C++ is not on the table: ADR 0013 allows C++ only for the
  sim's hot-phase kernels, and a change would need its own ADR.
- **The web preview** runs `SYNC` on the main thread, so a think lands in a frame there; the web
  has no gate (ADR 0013 §7).
- `game/ai` stays exempt from the sim's allocation check (ADR 0020 §3's note); managers keep their
  scratch arrays between thinks (`resize`, not new arrays) where it is cheap to.

Note (2026-11-07, P26bf docs; lead decisions from the wave-4 reviews):
- **The ARMY slot's two passes** are `AiIntel.refresh`'s pass over own rows and its pass over seen
  rows. `refresh` also fills, in those same passes, the lists `AiArmy` reads (the Headquarters'
  tile, the own buildings, the own combat units other than `scout_type`, the seen enemy combat
  units), declared in `AiMemory` with "none" values by P179; `AiArmy` iterates those lists and
  makes no pass over the view's rows, so the slot's `work` stays 3. The seen list holds up to
  (players - 1) times `unit_cap` ids, more than §3's `unit_cap` bound when more than two players
  play.
- **Who yields a key at the cap:** the army and the staging point come first. When the cap is full
  and only the scout uses a key, the army releases it; the scout's MOVE already sent finishes
  its leg (its flow-cache slot stays in use until then, one more than the AI's keys show), and
  its next MOVE waits for room under the key rule above. The army's key helpers, a unit type's
  move class and the point mirror live in `AiMemory`; `AiIntel` keeps its own key-room
  arithmetic until a follow-up shares one copy.
- **Production in the ECONOMY slot** counts the economy's unit `QUEUE`s of the same think toward
  its queue room and the unit cap (the view is taken before the think, so it cannot show them).

Note (2026-11-07, P26bg docs; lead decisions from the wave-5 reviews):
- **The unseen hit** moves the home squad's goal only, once, as a probe. A home member the shift
  named holds the goal while it is alive and not idle, or idle with a seen enemy in its weapon
  range; then the squad returns to the staging point and the army keys go. A hit is answered at
  once, without `reaction_ticks` (an exception to §2's reaction delay: a hit is an event, not an
  aged sighting). The range tests have their own cap (`hit_tests`, at most `target_tests_max`), so
  one ARMY slot may run up to twice that many tests.
- **The army keys of a wave in the field** stay held until the wave retreats or disbands, or a
  home order with members (a defence or an unseen-hit shift) takes the army goal cell. The home
  return and an empty defence never release them. A launch and the all-in join move the home goal
  to the staging point.
- **The all-in** (`all_in_tick`, 0 means never) overrides the defence. Before that tick a wave
  launches only when this think's threat search finds nothing (at once, not after
  `reaction_ticks`). From that tick no defence order is sent, the launch and join ignore a standing
  threat, and the wave no longer retreats.
- **Wave strength** compounds: each wave asks `wave_growth_percent` more than the one before.
- **Moved to P180b:** §6's recall of a wave in the field when the threat outweighs the home
  squad, and armed seen enemy buildings in the retreat ratio (P180 counts combat units only).

Note (2026-11-07, P26bh docs; lead decisions from the wave-6 reviews):
- **One cap for the army's searches.** Hard's focus search, the recall, the retreat ratio and the
  threat search share one `target_tests_max` per ARMY slot (the unseen-hit tests keep their own,
  as above). A focus search the cap cuts off keeps a living target. Focus fire reads no sector
  map: its search is local (`defend_radius_tiles` round the group's centre), so it tests the seen
  enemy combat units in id order inside the box round that circle (an uncounted pre-filter, as
  the threat search's).
- **The focus key.** A focus `ATTACK` books the target's tile at order time; the sim re-keys each
  unit's field toward a moving target, so for a few ticks two cells per move class may be live
  while the books hold one (like the scout's leg above).
- **Sectors first, as read by `AiStrikes`.** The things are the first `target_tests_max` of the
  lists in id order. The Deep Bore returns early when the sector map's enemy total is under
  `strike_min_value`; both weapons rank the things by sector value, then by value. The rows are
  then tested under `target_tests_max`; a check the cap cuts off is not clear.
- **§3's memory:** `AiIntel.run`'s own and seen passes fill `own_mobile_id` and `seen_mobile_id`,
  and `AiIntel` writes its sector grid (`sector_side`, `sector_cols`), all for `AiStrikes` (a
  fourth exception to §1's field "that P175 declares"); `work` stays at most 3. `seen_mobile_id`
  holds up to (players - 1) times `unit_cap` ids, more than §3's bound when more than two players
  play, as P26bf's seen list. P180b's `withdrawn_id` (at most `unit_cap` ids) and `squad_focus`
  are read by `AiArmy` alone, and P181's `strike_wave` by `AiStrikes` alone.
- **§2's reaction delay in the field:** the wave's focus, its retreat ratio and the recall read
  sightings at once; the delay stays on the base's threat and the home squad's answer to it.
- **§6, *Army*:** the recall disbands the wave into the home squad and the defence (on Hard, the
  home focus) sends it. A Hard unit that steps back stays out of a wave's launch only (the sim has
  no healing).
- **§6, *Strikes*:** the Deep Bore also keeps a live army goal out of its radius (the wave's goal
  while a wave is in the field, the home goal while a threat stands): the army walks there and the
  shot lands 45 ticks later. The Dusk Array's "as a wave launches against it" is read as once per
  wave, while the wave is in the field and has a live member, on the producers within reach of the
  wave's goal, else on the best producer cluster.

Note (2026-11-09, P26bi docs; lead decisions from the wave-7 reviews):
- **The staging stand-in (P181b):** while a threat stands and the home goal is NONE (a recall
  cleared it because it was the staging point), the Deep Bore keeps the staging point out of its
  radius instead, until an order sets the home goal again. Like the home goal it replaces, it
  passes the box pre-filter and costs one counted test per anchor checked only when it lies
  inside the things' box grown by the radius; the counting rule does not change.
- **The time line (P189):** `WATCH ai think` carries the keys above, with `thinks=` after `slots=`;
  `WATCH ai flow` and `WATCH ai peaks` (count-only) follow it. `perf_ai.tres`'s 900 ticks make no
  contact, so the timed workload is a building AI; the frozen AI defs of P189b add an early scout
  and first wave before the `[ai]` ratchet is set.
- **`flow_full_ticks`** is above 0 on `perf_ai` (191 of 900) and in the smoke's full matches. The
  choice above (`goal_keys_max` 3 or P194) is made on the first balance run's counts.

Note (2026-11-09, P26bj docs; lead decisions from balance run 1 and the wave-8 reviews):
- **The flow-cache choice is P194.** Balance run 1 (run 42639401142, issue #378) found the cache
  full in every set where the opponent AI plays both sides. `goal_keys_max` stays 4. The frozen
  rules and `perf_ai` keep 8 (`perf_ai.tres` loads the shared frozen rules), so no card and no CI
  budget times the larger cache: "the Perf AI card measures it" above no longer holds. The balance
  run's `flow_full_ticks` is its measure (a `custom` run on P194: 242 ticks over 100 matches, was
  46 722). The Context's "8 slots" now holds for the frozen rules only. Its cost: four more
  fields at `configure` (about 76 KB each on a 64 x 64 map), four more slots per `acquire` scan
  and per FLOW pick's re-read of `pending`, and the bind layer's `check()` reading each slot's
  names on every call.
- **Contact in the timed workload (P189b).** `test_ai_perf.gd` and the Perf AI route play the
  frozen AI defs, copies but for Normal's early scout and first wave (no jitter). Both sides scout
  and launch a wave inside the 900 ticks; `flow_full_ticks` on `perf_ai` reads 200 of 900 (191
  before). Not exercised there: the Dusk Array's search (player 2 sees no enemy building),
  `hit_tests`, `withdrawn_id` and `seen_mobile_id`. Lead decision: accepted. The Array's tests share
  `target_tests_max` with the rest (the bound is asserted), and the `[ai]` ratchet times the Deep
  Bore's search. Plan row P189c sets the `[ai]` value from 11 CI runs after P189b.
- **The first CI read** (P189's peaceful workload, before P189b): `WATCH ai think` p95 453 us, max
  545 us, `est_phone_p95_ms` 2.673, against the 1.0 ms watch value and the 0.15 ms CI target
  above. The lead raised it with Michael on 2026-11-09; no remedy from "Over budget" is chosen yet.

Note (2026-11-10, P26bm, the lead; the Phase 4 gate):
- **The phone read** (Michael's Pixel 9a, three Perf AI runs on `main` 688ef32, issue #398):
  `ai_think_p95_ms` 9.25-9.48 against the 1.0 ms watch; `sim_p95_ms` 12.1-12.6, over Michael's
  10 ms revisit trigger and under the 13.3 ms verdict; `job_minus_step_p95_cp_ms` 3.1-3.4, under its
  5 ms trigger (no think on a checkpoint tick, as above). CI's `WATCH ai think` p95 on the same
  commit was 507 us, so AI code ran about 18.5 times slower on the phone than on CI (mean 9.40 ms
  against 0.507 ms; 18.2-18.7 per run), where the estimate assumed about 5.9 (`est_phone_p95_ms`
  2.991). At that ratio the target above (0.15 ms on CI) is about 2.8 ms on the phone, not 0.9.
- **The remedy:** the lead proposed "Over budget"'s levers on #398 (plan row P198: more slots,
  smaller caps, cheaper sector reads, in GDScript; `ai_think_p95_ms` at or below about 2 ms on the
  Pixel 9a), with P66/P66b staying deferred: the trigger fired on `sim_p95_ms`, and the cause is
  the AI's think time, not checkpoint hashing. Michael said yes in chat on 2026-11-10 ("Ja, kør
  AI-optimeringen"). The gate passed with this read; P198 runs after it.

Note (2026-11-10, P198, cheaper reads; changes no accepted text above):
- **Where the time went** (per-stage CI means on an experiment branch, `perf_ai` workload, run
  42848948951 on a slow VM): the ARMY slot. The view cost 61 us, `AiIntel.refresh` 398,
  `AiArmy.run` 276, the whole ECONOMY slot (economy and production) 117 and the intel run and
  strikes 141. The cost was calls, not rows: each row went through `row_type`, `row_pos`,
  `row_id`, `row_hp` and `value_of`, a dozen GDScript calls, and each threat or strike test was a
  function call. The phone ratio is the one the P26bm note above gives (about 18.5), not the gate's
  `ci_ratio_p95` 5.9.
- **The remedy is cheaper reads, GDScript only; no cap and no slot moved.**
  `PlayerView.columns()` hands out copies of the row columns (index them only at visible rows, ADR
  0020 section 1's note of this date); the managers' passes index them through locals; the threat,
  strike and wave-ratio searches count their tests in a local and a unit's or an anchor's at once;
  `AiArmy._join` and `_unseen_hit` walk two ascending lists instead of a bsearch a unit. **No
  decision changes:** the `perf_ai` state hash `cbe70a78d01ee7c1` (run 42859084281, as main's run
  42816856270), its peaks and every balance match are main's, per seed.
- **Result** (CI `WATCH ai think` p95): 278 us (run 42859084281) and 473 us (run 42859139046)
  against main's 505 us (run 42859146551) and 810 us (run 42859090560) in the same hours: 0.55 to
  0.58 of main. After the review round (head 00b4bdfb, run 42867700421, hash `cbe70a78d01ee7c1`)
  401 us against main's 882 us in its paired run 42867706193 (its log line was read while that run
  was still going): 0.45. A runner's `p95_us` moves by up to 60 % from one VM to the next, so
  compare two commits only on runs of the same hour. At about 18.5 that is **about 5.2-5.5 ms on
  the phone, which misses P198's target of about 2 ms: the target stays open**, as do the 0.15 ms
  CI target and the 1.0 ms phone watch value above. The stage means after the first cut were
  refresh 63 us, army 168, view 44, economy 37, production 18, intel 30, strikes 13: the view and the ARMY slot's sum
  (view, refresh, army) are what is left, so that slot is still two to three times the ECONOMY and
  INTEL slots. What would meet the target is a change of behaviour or interface, not of reads:
  five slots on period 3 (which also moves `AiArmy`'s inputs a think earlier), a view built only as
  far as a slot needs, the static type tables shared between the views of a match. `AiArmy.gd` is
  at the 1000-line lint limit and `PlayerView` at its 20 public methods, so the next row splits
  them first (for example `_threat`, `_near` and `_value_in` into a reads helper).

Note (2026-11-10, P26bn, the lead; Michael's answers in chat the same day, "Ja til 1, 2 og 3"):
**the phone after P198, and what binds.** It changes the watch value and the "goes back to him for
P66/P66b" sentence above, and withdraws P198's 2 ms target (the P198 note's "the target stays
open"); no other accepted text.
- **The phone read** (Michael's Pixel 9a, three Perf AI runs on the perf APK of `main` a27803bd):
  `ai_think_p95_ms` 5.94, 5.87 and 6.03 (mean 5.95, 0.63 of the gate's 9.40); `sim_p95_ms` 9.87,
  9.85 and 9.93, under Michael's 10 ms trigger by 0.07-0.15 ms (the gate read 12.1-12.6);
  `job_minus_step_p95_cp_ms` 3.07-3.34; every verdict passes, 0 hitches, about 60 fps, and the
  hash `cbe70a78d01ee7c1` with `self_check` `match` on all three. CI's `WATCH ai think` p95 on the
  same commit was 390 us (run 42901639565), so the phone read about 15.3 times CI, where the gate
  read about 18.5: the ratio moves with the runner as much as the CI value does.
- **What binds now** (Michael, point 2): the 1.0 ms watch value no longer binds. The binding phone
  check is Michael's revisit trigger on every Perf AI card, with the AI in it: `sim_p95_ms` at or
  below 10 ms and `job_minus_step_p95_cp_ms` at or below 5 ms. `ai_think_p95_ms` is read, not
  judged. On CI, P189c's `[ai] p95_us` ratchet (1.5 times the worst of 11 runs, after P198c) keeps
  the AI's cost from growing unnoticed.
- **The lead's reading of point 2** (not Michael's words): the 0.15 ms CI target above falls with
  the watch value it was derived from; at the measured ratio it stood for about 2.8 ms on the
  phone. A card over the trigger still goes back to Michael, now with the AI's and the sim's share
  of the job, so he can weigh an AI-side row under "Over budget" against P66/P66b.
- **Five slots (P198b) is not merged** (Michael, point 3, and earlier the same day: "lad P198b
  ligge"): period 3 with five slots cut the CI p95 only to 0.78 of P198's (391 us against 503, runs
  42895222413 and 42895227397), built the view five times a round instead of three and moved
  `AiArmy`'s inputs a think earlier. Its balance runs stayed within noise of P198's (a 40-match set
  has a standard error near 80 per-mille) except Easy, 469 per-mille over 80 matches against the
  band's 450. The branch `claude/p198b-five-slots` (68ae4858) stays as a reference.
- **Next lever: P198c** (Michael, point 1): the match's fixed type tables built once
  and shared, read-only, by every view, so a think stops rebuilding them. No decision changes; its
  own note records the result.

Note (2026-11-11, P26bp, the lead; Michael's answers in chat the same day): **P198c and P198b on the
phone; the AI-time work stops here.** It changes P26bn's "after P198c" (P189c's 11 runs come from
`main` after P198) and its "Next lever"; no accepted text.
- **P198c is closed unmerged** (#403; "Luk P198c"). It builds the type tables once a match, slims
  `PlayerView.new()` and fills the row lists by index. Three Perf AI runs on its APK (run
  42979530576) read `ai_think_p95_ms` 5.77, 6.16 and 5.79 (mean 5.91 against P198's 5.95) and
  `sim_p95_ms` 9.79, 10.23 and 10.05 (mean 10.02 against 9.88; two of the three over 10 ms). The
  difference is inside the phone's
  run-to-run spread of about 0.2 ms, which does not pay for 419 production lines and a second
  non-state World member. The branch `claude/p198c-shared-type-tables` (e00b5c1f) stays.
- **P198b is parked again** ("Ja til at parkere P198b og starte Phase 4b?"; the lead reads it as a
  yes). It was taken up on the same day ("Luk P198c, og kør A med P198b": A was the lead's option to
  take it up again), and its reviews found three behaviour faults of the shorter cadence, all fixed
  on its branch:
  - Hard's focus centred on dead members.
  - Economy and production no longer shared Easy's command cap.
  - The credit reserve counted the economy's queued costs twice, because production now reads a
    later view.

  After the fixes, three Perf AI runs on its APK (run 43064793477, `perf_ai` hash
  `f54da93bf8d7b60d`) read `ai_think_p95_ms` 4.63, 4.69 and 4.76 (mean 4.69), about 1.3 ms under
  P198, but `sim_p95_ms` only 9.46, 9.80 and 9.96 (mean 9.74 against 9.88). With five slots the two
  AIs think on 10 of every 15 ticks instead of 6, so more of the step's slow ticks carry a think
  (the lead's reading). The binding number moved by about 0.14 ms on the mean, inside the same
  run-to-run spread.

  Its balance run also showed a seat edge in the fossil mirror: the bottom seat won 750 and 700
  per-mille (the top seat 250 and 300) on seeds 1-40 and 41-80 (runs 43064765778 and 43065367406),
  against ADR 0033 §8's 400-600.

  The branch `claude/p198b-five-slots` (29457471) keeps the fixes, the notes and the run ids. A row
  that takes five slots up again starts there and owns that seat edge.
- **What stands:** P198 (#401) on `main`. Michael's phone reads `sim_p95_ms` 9.85-9.93 with it, so
  the trigger (P26bn's note) has almost no margin.
- **Next steps:** the Perf AI rule of P26bn's plan note covers Phase 4b's rows. A card over the
  trigger goes back to Michael with the AI's and the sim's share. The levers left are "Over
  budget"'s smaller caps, P66/P66b, or a new ADR that opens ADR 0013 §1 and CLAUDE.md's Stack line
  to the AI's hot loops (the lead's reading; Michael picks).

Note (2026-11-13, P26bu, the lead; Michael's "Ja" in chat the same day): the Perf AI rule
of P26bn's plan note now runs once per merge wave. The card runs three times on `main` after the
wave merges, not on each row before it merges (`docs/plans/2026-11-06-phase-4.md`, P26bu's note).
This note changes no other text.

Note (2026-11-13, P26bv, the lead; Michael's "3" in chat the same day): the revisit trigger on
`sim_p95_ms` (P26bn's note) rises from 10 ms to 11 ms. `job_minus_step_p95_cp_ms` keeps 5 ms.
Wave 4's cards on `main` read 9.95, 10.01 and 10.36. The lever this note's "Next steps" names
(smaller caps, or a new ADR for the AI's hot loops in C++) goes to Michael before P250. P198b
is not taken up again: on the phone it moved `sim_p95_ms` by 0.14 ms (the P26bp note).
Details are in the Phase 4 plan's P26bv note. This note changes no other text.

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
the files, and the data tests pin script defaults equal to the files. Every number a manager uses
is one of these fields.
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
  | `uses_strike` | 0 | 1 | 1 | answer 2 A |
  | `commands_per_think_max` | 3 | 8 | 12 | Easy's slow hands |
  | `mend_below_percent` | 0 (never) | 50 | 70 | P274: `MEND` on for a building under this percent of its max hp (ADR 0037 section 4) |
  | `mend_floor` | 0 | 400 | 250 | P274: credits that must stay above it after the think's spending (a building of price 0 ignores it) |
  | `income_percent` | 100 | 100 | 100 (120 only if question 1's trigger fires, answer C) | §8 |

  Note (2026-11-12, P274; changes no accepted text above): the two mend rows are added. Their script
  defaults are 0 (off), not Normal's values, so "the data tests pin script defaults equal to the
  files" has this one exception: the frozen arena files (`data/dev/arena/ai/difficulty/`) name
  neither field and must play as before (default-off, as P271's rules). A data test names the two
  fields, pins their defaults and asserts Normal's file differs.

- **`OpponentDef extends AiDef`** (`game/ai/OpponentDef.gd`; `data/ai/opponent_fossil.tres`,
  `opponent_renew.tres`): one per faction.
  - **Inherited and used:** `id`, `hq_type`, `harvester_type`, `queue_target`, `place_stride_tiles`,
    `defend_radius_tiles`, `think_period` (5 in these files), `think_tick` (6).
  - **Inherited and ignored by `OpponentAi`:** `build_order`, `place_tries`, `harvesters_wanted`,
    `guard_offset_tiles` (replaced by `build_orders`, `place_tries_per_think`, the level's
    `harvesters_per_refinery` and the staging point). The data test requires them at their script
    defaults in the opponent files, so no one tunes a dead field.
  - **Added:** the role table (`scout_type`, `anti_infantry_type`, `anti_vehicle_types`,
    `tank_type`, `artillery_type`, `defence_type`, `strike_type`); role weights per tier;
    `build_orders: Array[AiBuildOrderDef]` by tier; `power_margin` (P: 20, the power surplus kept
    before a consumer is queued); `staging_offset_tiles` (P: 6); `unseen_hit_shift_tiles` (P: 4);
    `sector_tiles` (P: 8); `sectors_max` (P: 64); `squads_max` (P: 4); `place_tries_per_think`
    (P: 8); `target_tests_max` (P: 512); `goal_keys_max` (P: 4); `strike_min_value` (P: 3000).
  - A def lists only its faction's type ids (a data test walks every id against the faction's
    roster and its `requires` chain, as `test_ai_def_data.gd` does for the dummy).
- **`AiBuildOrderDef`** (`data/ai/build_orders/<faction>_<tier>.tres`, six files): `steps:
  Array[StringName]` with the dummy's meaning (the player wants as many of a type as the list has
  up to the item, so a lost building is wanted again at its place), then the loop of §1's economy
  row (power while the surplus is under `power_margin`, refineries, factories and defences up to
  the level's caps). The weak tier has no radar and no strike building; the strong tier gets the
  second refinery and the factory earlier.
- **Building the controller:** `AiFactory.create(def: AiDef, level: AiDifficultyDef, player: int,
  rng: DetRandom) -> AiController` (`game/ai/AiFactory.gd`): an `OpponentDef` gives `OpponentAi`, a
  plain `AiDef` gives `DummyAi` (the level is ignored and may be null). `MatchRunner` gains
  `opponent_levels: Array[AiDifficultyDef]` beside `opponents` and `first_opponent: int` (both
  typed, not exported, for ADR 0020 §3's note's leak), and `_opponent_controllers` calls the
  factory (lead, P182).
- **The managers in short** (each row's acceptance in the plan holds the detail):
  - *Economy:* the tier's steps, then the loop; power upkeep before any consumer; harvesters per
    refinery; rebuilds in order; placement on `PlacementSpiral` round the Headquarters, resumed
    across thinks; a defence goes to the free slot nearest the staging point when `AiArmy` has set
    it, else to the first free slot.
  - *Production:* both unit queues kept at `queue_target`; the next unit is a weighted draw over
    the roles whose type can be queued, the weights shifted by `counter_percent` toward the role
    whose weapon does most against the armour classes intel has seen most of
    (`type_vs_armour`, §7); the build order's next structure keeps its credits first.
  - *Intel:* the sector map (own and enemy value per sector, from the view's rows and ghosts); the
    enemy base estimate: the seen or remembered enemy producer nearest to the own Headquarters,
    else the point mirror of the own Headquarters (`map - 1 - tile` on both axes); scouting with
    one unit of the scout role, first to that mirror point, then to the nearest unexplored
    sectors, home when hit, within the key rule of §4.
  - *Army:* the staging point is `staging_offset_tiles` from the Headquarters toward the base
    estimate, written to `AiMemory` and sent once as `RALLY` (again when it moves); new combat units
    gather there; a threat within `defend_radius_tiles` of a building becomes the army goal (the
    home squad, and a wave in the field when the threat outweighs the home squad by
    `retreat_ratio_percent`); a unit hit by something unseen moves its squad's goal
    `unseen_hit_shift_tiles` toward the base estimate (ADR 0009 §2: "an idle unit hit from beyond
    its weapon range does not react. The Phase 4 AI handles that"); a wave launches when the home
    squad's value reaches the wave's strength and the tick has passed `wave_first_tick` plus its
    jitter, and attacks the nearest known enemy producer or Headquarters (the outcome rule's
    buildings), else the base estimate; it re-targets when the target is gone; it retreats with
    `MOVE` (no fire on the way, ADR 0009 §2) to the staging point and rejoins the home squad.
    Hard's units under `unit_retreat_hp_percent` step back to the staging point on their own, and
    Hard's groups `ATTACK` the weakest seen enemy in reach (bounded by `target_tests_max`; that
    target is the army goal).
  - *Strikes:* a Deep Bore fires on the point of the most enemy value within its radius with no own
    row inside it, once the value passes `strike_min_value`; a Blackout Array fires on the enemy's
    producer cluster as a wave launches against it. Both read only seen rows and ghosts.

Note (2026-11-06, P26be docs; lead decisions from the wave-3 reviews):
- **`spiral_slots`** (P: 64) joins `OpponentDef`'s added fields: the number of `PlacementSpiral`
  slots the economy asks about; its search resumes across thinks and wraps over them, and it is at
  least `place_tries_per_think` (the data test pins the 64 and that rule). This section named no
  field for the spiral's length when it replaced `place_tries` with a budget per think;
  `place_tries` stays inherited and ignored.
- **The credits the next structure keeps** (*Production* above) are `AiMemory.reserve_credits`:
  what the economy queued in this think plus the price of the structure, or the tanker, it waits
  to queue next. Production spends at most `view.credits - reserve_credits`. Both managers read
  the same view in the ECONOMY slot and the economy's `QUEUE`s apply first, so a reserve without
  the economy's own spend would let production send a `QUEUE` the sim drops (§1).
- **The scout is queued by production.** No role and no build order holds `scout_type`, and §1
  leaves the unit `QUEUE`s other than tankers to `AiProduction`. So `AiIntel` sets
  `AiMemory.scout_wanted` (NONE, else the scout type's index) while a trip is due, no unit of
  `scout_type` lives and the key rule would allow it. While it is set and no unit of that type is
  in its queue, production queues one ahead of its role draw: a queued unit does not live, so
  intel keeps asking during the build. Intel still sends only the scout's moves (§1's table).
  P177b declares the field, not P175 as §1 has it for a field another manager reads; P178 waits
  for P177b, so no row reads it before its writer exists.
- **The scout's first waypoint** is the point mirror of the own Headquarters even when a producer
  is already known (the *Intel* line above), and the base estimate is the nearest of the seen and
  the remembered producers together (ties to the lower id).

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

Note (2026-11-06, P26bd docs; P172 #347 as merged): one read is added to the list above, from the
P172 review (a lead decision). **`own_strike_tick`**: the viewing player's own pending rupture,
its landing tick, 0 when none. §1 says no `SUPERWEAPON` while the player's rupture is pending,
and the warned lists name no owner, so without it the AI could not tell its own entry from an
enemy's. It is own state only. Test it for 0 and never against a stamp: the sim drops a
`SUPERWEAPON` stamped at the landing tick itself too, and a blackout never sets it (so in one
think a rupture may follow a blackout, but nothing may follow a rupture). The type tables, own
rows, warned lists and caps are as listed; `type_vs_armour` is indexed `type * 4 + class`, read
through the type's weapon (`PlayerView.ARMOUR_CLASSES` is 4, pinned to `World.Armour`).
`type_sight` is in milli-tiles.

Note (2026-11-10, P198; changes no accepted text above): "nothing hidden" and "stays read-only" now
have one reading more. `PlayerView.columns()` exposes the id, owner, type, position, hp and
`build_left` columns of every World row, hidden rows included, as copies (copy on write; a write
never reaches the World). A manager indexes them only at rows of `own_rows`, `seen_rows` or a
`row_of()` answer of 0 or more, the rows whose values the getters give. The poisoned-view oracle
(`tests/ai/test_ai_poisoned_view.gd`) and the scan in `tests/project/test_view_reads_snapshot.gd`
enforce it; ADR 0020 section 1 has the same note.

### 8. Difficulty is parameters; the AI never sees more than its side
- One code path for all three levels; only `AiDifficultyDef` differs. A test runs the same seed at
  two levels and checks that the controllers are the same class with different ints.
- **Vision:** never. Every level reads only `PlayerView` (the `game/ai` scan of
  `test_view_reads_snapshot.gd` and `test_sim_purity.gd` stays). The point-mirror guess of §6 is
  map knowledge a player has too, not a sight of the enemy.
- **Resources:** the AI gets nothing a player cannot (Michael's answer 1 C): Hard starts without a
  bonus. Only if the trigger run of the Acceptance note shows Hard under 600 per-mille against
  Normal does Hard get +20 % income, the one place the AI would then not play by the same rules.
  That bonus is match setup, not a cheat in the AI's code: row P173 adds `World.income_percent` per
  player (set at load from the opponent's level, 100 for a human), applied where a tanker unloads
  (`credits += ore * credits_per_ore * income_percent / 100`), outside the state hash and inside
  `defs_hash` like the rule ints, and carried in the replay's header (`Replay.FORMAT` 2). At 100 the
  arithmetic is the same, so **no state hash and no golden moves**; every World's `defs_hash` value
  changes once (a new input), which no literal pins (`tests/sim/test_world_hash.gd:274-292` compares
  values with each other). The Skirmish's Hard button then shows the bonus, formed from
  `income_percent - 100` (P183b), never a literal.

### 9. The dummy stays (lead decision above)
`DummyAi`, `DummyDefence`, `PlacementSpiral` and `data/ai/dummy_*.tres` stay as they are.
`OpponentAi` reuses `PlacementSpiral`. The Skirmish routes switch to `OpponentAi` in P183, which
waits for P180, so the AI the player meets builds, produces, defends and attacks; the player never
meets one weaker than the dummy. ADR 0020's §1-§3 and §5 hold for both controllers.

### 10. Legal
No name, personality, faction doctrine, build order or AI behaviour is taken from Command &
Conquer, Red Alert, OpenRA or any other game; no code from EA's release or OpenRA. Difficulty
names are the GDD's generic Easy, Normal, Hard. Managers have plain functional names. Build orders
are written from this game's own roster and `requires` chains.

## Consequences
- The AI's cost is spread over three ticks of fifteen and counted; it shows on the phone as its own
  key and never on a checkpoint tick. The noncheckpoint half of the watch line and `sim_p95_ms` will
  rise by about the dearest slot in matches against the AI.
- The AI holds at most four flow-cache keys; AI-vs-AI can fill the cache, which the harness counts.
- Balance tuning has a parameter set per level and a role table per faction, all data; ADR 0031's
  balance run reads their effect.
- `PlayerView` grows by a dozen copied tables (read-only). `MatchRunner` builds controllers through
  one factory and can seat a computer player on player 1.
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
- **Counting goal points instead of keys:** wrong for mixed groups (two classes per point).
- **A cheating Hard (more vision):** against pillar 4 and ai-dev.md; never.
- **Porting the AI to C++:** outside ADR 0013's scope (hot sim kernels only), and a second
  implementation of fast-changing code.
- **Replacing the dummy:** loses a fixed baseline and rewrites the Phase 3 end-to-end suites.

## Questions for Michael (answered 2026-11-06: 1 C, 2 A, 3 ja)
1. **Hard and money.** **Answered: C.** Recommended: **C**, because it keeps the computer fair
   unless better play proves not to be enough, and the bonus is ready if it is needed.
   - A (not chosen): keep the GDD: Hard gets +20 % income from the start, and the Hard button says
     so.
   - B (not chosen): no bonus: Hard is only better play (economy, reactions, retreat, focus fire).
   - C (chosen): no bonus first. After the AI is complete (row P181) and the first tuning, the lead
     runs 100 Hard-against-Normal matches once (each level on each side half the time, seeds that
     tuning never used). If Hard wins under 60 % of them, the +20 % comes in (row P173) and the Hard
     button says so.
2. **Superweapon.** **Answered: A.** Recommended: **A**, because the GDD promises it for the Phase 4
   AI and a newcomer on Easy should not face a strike.
   - A (chosen): Normal and Hard build and fire their side's superweapon; Easy never builds it.
   - B (not chosen): all three levels.
   - C (not chosen): none in Phase 4.
3. **Two rule files that would go stale.** **Answered: ja** (applied in P170b). May the lead update
   `.claude/agents/ai-dev.md` and the skill `.claude/skills/balance-report/SKILL.md` so they match
   these two ADRs? (ja/nej; recommended: **ja**, because otherwise ai-dev works to a time rule that
   is about six times too loose on the phone and reads reports from a folder the nightly does not
   write.)
   - `ai-dev.md` line 19: "Keep each decision under 1 ms on CI" becomes "Keep each think slot at
     most 0.15 ms p95 on CI (the `WATCH ai think` line), about 1 ms on the phone". Line 3: the
     harness is qa-engineer's to build and ai-dev's to read.
   - `SKILL.md` line 12: "read the latest report in `docs/balance/`" becomes "read the latest
     comment on the `balance` issue or the nightly's artifact"; line 9's seeds and step 1 get the
     new flags and `scripts/balance-summary.sh`; step 5 posts one comment block per set.

Note (2026-11-10, P26bl, the lead): §8's trigger fired. Hard got 350 per-mille against Normal on
`d43b4bd` in the balance run's 40-match ladder-hard set (run 42760470364), not in a 100-match
step-0 run. P173 (#394) wires `World.income_percent` as §8 describes. Every level still says
100. Hard's 120 lands together with P183b, the label beside Hard. P183b also picks the result
screen's wording: `stat_harvested` counts the cargo before the bonus, which is right for balance
reports, but "Credits harvested" would read about 1/6 low for a player at 120. Hard is still weaker
than Normal with 120 (362.5 per-mille). Its own fields (`retreat_percent` 50,
`retreat_ratio_percent` 150, `unit_retreat_hp_percent` 30, `defences_max` 3, `factories_max` 2)
are the suspects. Michael decided on 2026-11-10 to tune Hard and the number balance once, in
Phase 4b's balance run. P197's wave assembly, siege focus and press (`claude/p197-ai-finishes`,
not merged) are a reference for that run, not rules of this ADR.
With Michael's yes to item B (2026-11-10), row P192b drops the strike building from Normal's
standard orders. This overturns answer 2 A ("Normal and Hard build and fire") for Normal: Normal's
`uses_strike` 1 is left with nothing to fire, and Hard keeps its strike.
