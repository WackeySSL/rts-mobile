# Plan: ground support (sale, building repair, repair buildings, medics, a carrier, mines, hold)

Date: 2026-11-09. Base: `main` at b6bfe95. Author: architect (row P270, branch
`claude/design-ground-support`). Decision:
`docs/adr/0037-ground-support-repair-medics-carriers-mines.md` (**accepted, 2026-11-09**).
Reconciled the same day with ADR 0036 and its plan `docs/plans/2026-11-09-air-and-tech.md` (branch
`claude/design-air-and-tech`, 0c5cc75). Fix 1 the same day: gameplay-dev's docs lens (8 must, 10
should, 5 nits) and Michael's answers.

**Answered by Michael on 2026-11-09 (in chat, through the lead): 1 A, 2 A, 3 A, 4 B, 5 A.**
Everything comes before launch, after the Phase 4 gate and before Phase 5, in one block with ADR
0036 (Michael chose the same for the air design). Passengers cannot fire; the Bunk Wagon's squads
get out at half hp and the Linecar's die. Own mines never trigger under own units and never hurt
them. Hold position comes before launch; ranks and patrol stay for later updates. The names stay.
The status stays proposed: the lead accepts both ADRs in one docs row once both fix commits are in
and Michael has said yes to the `touch-ui-rules` text.

Note (2026-11-09, P270b done): ADR 0037 and ADR 0036 are accepted in one docs commit (P270b with
P230), before Michael's yes to the skill text. That yes now gates only the rows marked "skill yes"
(P272, P282, P294, P299), as it gates ADR 0036's P244 and P265. The draft text is in
`docs/plans/2026-11-09-air-and-tech.md`, section "touch-ui-rules text for Michael's yes (P230)".
(2026-11-09, later) Michael said yes; the text is applied to
`.claude/skills/touch-ui-rules/SKILL.md`, and no row waits for it.
ROADMAP Phase 4b holds both designs. The shared rows follow "Merge order of the shared rows"
below, the same text as in the air plan; P276, P277 and P289 carry dated notes for it.

- **Waves.** The old release split is now a build order inside the pre-launch block, set by the
  shared rows each wave needs:
  - wave 1: sale and building repair (P271-P275); needs none of ADR 0036's rows;
  - wave 2: repair buildings and medics (P276-P284); needs P231, P232 and P241b, art after P237;
  - wave 3: the ground carrier, mines and hold position (P285-P300); needs P262 and P263b, art
    after P237.
- **Row ids.** P270-P300. The lead asked for P260 upward, but ADR 0036's plan holds P230-P269, so
  this plan starts at P270. Checked free on every local and remote branch.
- **Named exceptions.** 22 is P189b's; ADR 0036 gives 23 to P232 and 24 to P262. This plan needs
  one: **25** for P286's re-pin (or the next free number when P286 starts).
- **Shared with ADR 0036** (ADR 0037 §2): Commands `LOAD` 5, `UNLOAD` 6, `REPAIR` 7; the repair
  role (declared on `UnitDef`, ADR 0037 amends ADR 0036 §2); `Carry.gd`; `STATE_FORMAT` 6 and 7;
  the Home, Board and Unload buttons; the DIED-flag readers; the page rule and P237. No second
  `LOAD` or `REPAIR`, and no tap overload: a tap on an own unit or building always selects.

## Goal
- **Wave 1:** a player can sell a finished building for part of its price and switch on a paid
  repair ("Mend") of a damaged building; the AI mends on Normal and Hard.
- **Wave 2:** the Weld Shed and the Drone Dock repair vehicles; Patchers and Menders heal squads;
  the AI builds and uses both.
- **Wave 3:** the Bunk Wagon and the Linecar carry squads; the Shot Truck and the Seeder lay hidden
  mines that detectors find; a Hold button keeps units from chasing; the AI uses all of it fairly.
- The block's gates (ADR 0036's P255 and P268) count 18 unit types after wave 2 and 26 at the end.
- Every row keeps the 150-unit budget. One kernel edit in all (TARGETING, P298).

## Out of scope (each needs a plan change and Michael's yes)
A repair vehicle; passengers firing; friendly-fire mines; ranks, patrol and hold fire (later
updates, ADR 0037 §15); auto-paths round known mines; mines on the radar; anything in ADR 0037's
"Out of scope".

## Affected modules
- **`game/sim`**
  - Changed: `Command` (types 8, 9, 17, 18 and their factories), `Sim` (the branches; every
    order-giving Command zeroes `carry_mode`), `World` (events 7 and 8, `SOLD` -3, the DIED-flag
    mapping in `remove_dead`, the stats, `repair_rows`, the role and mine type tables, the mine
    table, records and `stance` in P286), `WorldLoad`, `WorldHash` (section `mines`), `Buildings`
    (sale, a placed building removes a mine), `Outcome` (no loss for `SOLD`), `Strike` (a rupture
    clears mines), `Targeting` (hold position, twin), `PlayerView` (`row_mend`, `row_stance`,
    `own_mines`, `known_mines`, type tables), `Carry` (eject).
  - New: `Mend.gd`, `Repair.gd` (ECONOMY), `Mines.gd` (FIRE mark and ECONOMY), `MineMemory.gd`
    (MEMORY).
  - ECONOMY order: `Power.run`, `Harvest.run`, `Air.run`, `Carry.run`, `Repair.run`, `Mend.run`,
    `Mines.lay`.
  - Defs: `UnitDef` (the repair role declared here, `repair_slots`, `repair_seek_milli`,
    `mine_weapon`, `mine_cost`, `mine_aware`, `detect_milli`, `carry_eject_percent`), `WeaponDef`
    (`blast_milli`), `RulesDef` (`sell_refund_percent`, `mend_*`, `mine_*`, `sweep_ticks`).
- **`native/sim_kernels`:** TARGETING only (`core/targeting.cpp`, `bind/kernel_targeting.cpp`,
  `stance` in `bind/world_access.h`'s TARGETING list); the sanitizer's format-7 cases (P286).
- **`game/core`:** `MatchSnapshot` (`cargo` and `stance` of rows, own mines and the local player's
  records).
- **`game/view`:** `EffectsLayer` (`_add_death` matches the DIED flag), `BuildingCollapse`
  (`cancelled` matches flag 1; flag 3 = the pack-up), the glyph pass (wrench, own only),
  `RepairFx` (new), `MineLayer` (new, z 3, after `DecalLayer` and before `LifeFx` in `main.tscn`).
- **`game/input`, `game/ui`:** `CommandBar.ORDERS` (Repair, Mend, Sell, Mine, Hold; building
  orders), `OrderRules` (who the Repair button serves), `MineAim` (new, on `StrikeAim`'s pattern),
  the Surrender question card (reused for the last producer's sale), `data/input_settings.tres`
  (`sell_confirm_ms`).
- **`game/ai`:** `AiEconomy`, `AiProduction`, `AiArmy`, `AiStrikes` (calls `AiMines`, new),
  `OpponentDef` (`hold_types`), `AiDifficultyDef`, the build orders.
- **`data/`:** 8 new types and 2 mine weapons, rosters, `rules.tres`, AI data; frozen arenas
  (`data/dev/arena/`) untouched.
- **`tools/artgen/`, `assets/`:** 8 models, 2 x 2 mine marks, a drone fx, 5 glyphs, 8 item cards.
- **`docs/`:** HOW_TO_PLAY rows in each player-facing row; GDD, ROADMAP (a Phase 4b section for
  the block, with ADR 0036's) and the `touch-ui-rules` text in P270b.

## Command, state and data changes (summary of ADR 0037)
- **Commands:** `LAY_MINE` 8, `STANCE` 9, `SELL` 17, `MEND` 18 (new); `LOAD` 5, `UNLOAD` 6,
  `REPAIR` 7 (ADR 0036's, shared). 19 reserved for `PATROL`.
- **Events:** `MINE_BLAST` 7, `REPAIRED` 8; DIED flag 3 = sold (`SOLD` = -3; -1 cancelled -> 1,
  `Carry.BOARDED` -2 -> 2).
- **State:** waves 1 and 2 change no layout (the mend switch is a building's `cargo`). P286 adds
  the mine table, the records and `stance` after P262, on `STATE_FORMAT` 7, with one re-pin under
  exception 25.
- **"Hash-neutral" means the state hash only.** Every row that adds a def field or a type table
  changes `defs_hash`, which no literal pins.
- **Data:** every number in `data/*.tres`; starting values in ADR 0037 §3-§8 and §15.

## Test plan (what is proven headless)
ADR 0037 §16 lists the cases per feature. In short:
- **Determinism:** the replay test on a scenario that sells, mends, repairs, heals, loads, ejects,
  lays, blasts, sweeps and holds, under both implementations; hashes equal.
- **Hash neutrality (state hash):** P271, P276 and P298 move no golden and no `TICK_0_SEED_1`;
  P286 is the one re-pin.
- **Rules:** one suite per module (`test_sell.gd`, `test_mend.gd`, `test_repair_role.gd`,
  `test_medic.gd`, `test_carry_eject.gd`, `test_mines.gd`, `test_mine_memory.gd`,
  `test_stance.gd`), and the TARGETING lockstep cases with stances.
- **Fairness:** byte-equal AI Commands for two worlds that differ only in hidden things (an
  unknown mine, a loaded enemy carrier, an enemy's mend switch, an enemy's stance).
- **Budget:** counted bounds (`REPAIR_CHECKS`, `MINE_CHECKS`) on `perf_bases`; the draw-call guard
  +1 for `MineLayer`; page pins after each art row. No timing runs in a session.
- **Touch:** two-tap sell, its disarm and the question card; Repair beside Home; Board and Unload
  with a ground carrier; the Mine aim and the Hold toggle at ADR 0015's six sizes.
- **Mutation testing:** P271, P276, P287, P288, P298 (about 10 chosen mutants each).

## Rows
Owners: GD gameplay-dev, AI ai-dev, ART art-director, TUX touch-ux-dev, QA qa-engineer, LEAD the
lead, ARCH architect. Size = production lines (tests, fixtures and `.tres` do not count). Every
player-facing row adds its HOW_TO_PLAY rows. "Skill yes" = Michael's yes to the `touch-ui-rules`
skill text (asked in P270b, as ADR 0036's P244 and P265 wait for theirs).

### Docs
| Row | Owner | What | Size | Depends |
| --- | --- | --- | --- | --- |
| P270 | ARCH | This plan and ADR 0037 (proposed), fix 1 | 0 | - |
| P270b | LEAD | **Done 2026-11-09** (with P230, one commit on `claude/p230-phase4b-acceptance`; the skill text is drafted in the air plan and waits for Michael's yes). Acceptance with ADR 0036 in one docs row: the answers (recorded), dated notes in ADRs 0007, 0010, 0017, 0018, 0023, 0030, 0031 and 0036 (ADR 0037's list, ADR 0036 §2 to `UnitDef`); the GDD; ROADMAP Phase 4b; the `touch-ui-rules` text with Michael's yes | docs | Michael's yes to the skill text |

### Wave 1 (sale and building repair)
| Row | Owner | What | Size | Depends |
| --- | --- | --- | --- | --- |
| P271 | GD | `SELL` 17 and `MEND` 18: factories, `Sim` branches, `SOLD` -3 and `remove_dead`'s flag mapping (-1 -> 1, -2 -> 2, -3 -> 3), `Outcome` skips `SOLD`, `Mend.gd` (staggered, priced, stops at full), `RulesDef` fields (inert defaults), `PlayerView.row_mend`; state-hash-neutral test | 200 | P270b, the Phase 4 gate |
| P271b | GD | (2026-11-12, P26bq) Data: ADR 0037's starting values in `data/rules.tres`, `sell_refund_percent` 50, `mend_hp` 10, `mend_period_ticks` 15, `mend_cost_percent` 30 (P271 ships them inert at 0/0/15/30); the data test's pins follow. Moves no state hash; starts `balance.yml` | data | P271 |
| P272 | TUX | Building orders: **Mend** toggle and two-tap **Sell** with "+N", the question card for the last producer; wrench glyph for own buildings only (a view test with an enemy switch on); `EffectsLayer` and `BuildingCollapse` match the DIED flag (1 nothing, 3 the pack-up: no flash, no crater); `sell_confirm_ms` and (fix 1, 2026-11-09) `sell_arm_min_ms`, the fixed-width Sell button; HOW_TO_PLAY Buildings rows (Teach) (2026-11-12, P26br: the wrench, the DIED-flag readers and their view tests moved to P272b) | 270 (about 450 as built, 2026-11-12) | P271, P273 (2026-11-09: the skill text is accepted and applied, Michael's yes); P271b for the phone step (2026-11-12, P26bq); P272b (2026-11-12, P26br) |
| P272b | TUX | (2026-11-12, P26br) The view half of P272, split for size: the map wrench over own mending buildings (`HealthBarLayer`), the DIED-flag readers (`EffectsLayer`, `BuildingCollapse`: 1 and 2 nothing, 3 the pack-up) and the quiet pack-up (`CollapseFx`: dust only) | 115 | P271 |
| P273 | ART | Glyphs `glyph_repair` (wrench), `glyph_sell` and the seated map copy `glyph_repair_map`; STYLE.md glyph rows | SVG | P270b |
| P274 | AI | `AiEconomy` mends below `mend_below_percent` above `mend_floor` (Normal, Hard) | 80 | P271 |
| P275 | LEAD | Balance run after P274, phone check (sell and mend upright and sideways) | docs | P272, P274, P271b (2026-11-12, P26bq); P272b (2026-11-12, P26br) |

### Wave 2 (repair buildings and medics)
| Row | Owner | What | Size | Depends |
| --- | --- | --- | --- | --- |
| P276 | GD | The repair role on `UnitDef` (ADR 0036 §2 names; defs and World type tables built here if P231 and P232 have not), `repair_slots` (1-8 without pads), `repair_seek_milli`; `repair_rows`; `Repair.gd` after `Carry.run`: staggered by rank, one row scan per acting repairer (no `target_grid`), footprint-centre reach, slots order, price, `REPAIRED`, medic seek; `REPAIR_CHECKS` | 310 | P270b; P231 and P232 (2026-11-09, merge order 4: no longer "if merged"; P276 adds no defs or type tables) |
| P277 | GD | `REPAIR` 7 to `Buildings.aim`'s approach point (built here if P241b has not, else added to it); the data test that reach covers every ring point (+500); the shared contract test's ground cases | 100 | P276; P241b (2026-11-09, merge order 4: P241b builds `REPAIR`, P277 adds the footprint-centre service point) |
| P278 | GD | Data: Weld Shed (reach 2,700), Drone Dock, Patchers (slots 1), Menders (slots 2); name width test; HOW_TO_PLAY Units and Buildings rows (Teach: repair) | data | P277 |
| P279 | ART | Weld Shed and Drone Dock models (body, `dmg2` at 0.75, `anim`), page pins | art | P237 |
| P280 | ART | Patchers and Menders (two figures, 8 directions, walk 4, idle 2), the drone fx, item cards, page pins | art | P237 |
| P281 | TUX | `RepairFx`: sparks, drones out and back, medic glow, from `REPAIRED`, seen-only; ring quotas | 160 | P278, P279, P280 |
| P282 | TUX | The **Repair** button: ground rows a building serves -> one `REPAIR` to the nearest serving building; beside ADR 0036's Home in a mixed selection, each sending its own rows; unarmed rows of an attack get `ATTACK_MOVE`; six sizes | 100 | P278 (2026-11-09: the skill text is accepted and applied, Michael's yes) |
| P283 | AI | `AiProduction` (repair building after the vehicle factory, `medic_per_squads`), `AiArmy` (`REPAIR` under `repair_retreat_percent`, medics in waves with `ATTACK_MOVE`) | 170 | P278 |
| P284 | LEAD | Joins ADR 0036's gate run (P255) and phone check (P256): 18 unit types once the medics are in | docs | P281-P283 |

### Wave 3 (the ground carrier, mines and hold position)
| Row | Owner | What | Size | Depends |
| --- | --- | --- | --- | --- |
| P285 | GD | Defs: `mine_weapon`, `mine_cost`, `mine_aware`, `detect_milli`, `carry_eject_percent`, `WeaponDef.blast_milli`, the mine rules (`mine_cap` 0 by default); type tables; data tests; state-hash-neutral | 100 | P270b, P231 |
| P286 | GD + QA | The ground layout: the mine table, `next_mine_id`, the records, section `mines`, sparse `mine_at`; the `stance` row column; `STATE_FORMAT` stays 7; the sanitizer's format-7 cases regenerated; one re-pin of every golden and `TICK_0_SEED_1` (exception 25) | 190 | P285, P262 |
| P287 | GD | `Mines.gd` 1: `LAY_MINE` 8 (Formation slots, `carry_mode` 2, every order-giving Command zeroes `carry_mode`), lay on the layer's own cell in ECONOMY with every check again at the lay tick, cost and cap, arm; mark, blast (`Strike._land`'s formula) and compact in the FIRE mark; no friendly damage, air passes, rupture clears, a placed building removes; `MINE_CHECKS`, `MINES_REFUSED` | 300 | P286 |
| P288 | GD | `MineMemory.gd` (forget; remember by detectors x mines on the fog turn, counted), sweeping (`carry_mode` 3), `PlayerView.own_mines`/`known_mines`, the snapshot's own and known lists | 250 | P287 |
| P289 | GD | (2026-11-09, merge order 5: after ADR 0036's `Carry.gd`) `Carry` eject: `carry_eject_percent` in `Carry.board`'s place in REMOVE (ring search, hp, `UNLOADED`, no-room deaths and losses); the ground-carrier data checks | 100 | P263b, P285 |
| P290 | GD | Data: Bunk Wagon, Linecar, Shot Truck, Seeder, shot charge and pulse seed weapons, detect on Flarejack and Swift, `hold_types` defaults; name width test; HOW_TO_PLAY Units, Orders, Fog rows (Teach: Board, Unload, Mine, hidden mines) | data | P288, P289 |
| P291 | ART | Bunk Wagon and Linecar (16 directions; P237 and Michael, 2026-11-11), item cards, page pins | art | P237 |
| P292 | ART | Shot Truck and Seeder (as P291), mine marks per faction (own, known), `glyph_mine`, `glyph_hold`, item cards | art | P237 |
| P293 | TUX | `MineLayer` (z 3 after `DecalLayer`, own and known marks, dimmed records, unarmed half alpha, one `_draw`), blast fx and scorch where seen; draw-call guard +1 | 220 | P288, P290, P291, P292 |
| P294 | TUX | The **Mine** button with "n/cap" and `MineAim` (tap, ring, check mark, X, turn cancels); a check that ADR 0036's Board and Unload (P265) take a ground carrier (data only); six sizes | 150 | P293, P265 (2026-11-09: the skill text is accepted and applied, Michael's yes) |
| P295 | AI | `AiMines` in `AiStrikes`' slot: lay on the own-half route, sweep known mines before a wave, scouts ahead on Hard; Easy none | 250 | P290 |
| P295b | AI | Ground rides in `AiArmy` on P267's drop code: load at staging, unload at `ride_unload_tiles` | 150 | P290, P267 |
| P296 | QA | The fairness cases (unknown mine, loaded enemy carrier, enemy mend switch, enemy stance), counted bounds on `perf_bases` with 24 mines and repairers, the replay with every new Command, harness types (26) | tests | P293-P295b, P298 |
| P297 | LEAD | Joins ADR 0036's gate run and phone check (P268): 26 unit types; mines found, swept and blasting; ground load, unload and eject; Hold | docs | P296, P299, P300 |
| P298 | GD | Hold position: `STANCE` 9 (factory, branch), the TARGETING twin (`Targeting.gd`) and kernel (`core/targeting.cpp`, `bind/kernel_targeting.cpp`, `stance` in `world_access.h`'s TARGETING list): weapon-range acquisition and no `CHASE` on `ATTACK_MOVE`, IDLE after a held `ATTACK`; `PlayerView.row_stance`; lockstep cases; no golden moves | 230 (C++ ~120) | P286 |
| P299 | TUX | The **Hold** toggle (shield glyph, lit when all hold) and the chip's shield; HOW_TO_PLAY Orders row; six sizes | 120 | P298, P292 (2026-11-09: the skill text is accepted and applied, Michael's yes) |
| P300 | AI | Normal and Hard set hold on `OpponentDef.hold_types` (each faction's artillery) when they join a wave | 40 | P298, P290 |

### Lanes and order
- **S (GD):** P271 -> P276 -> P277; then P285 -> P286 (after P262) -> P287 -> P288; P298 after
  P286 beside P287; P289 after P263b.
- **D (GD data):** P271b after P271 (2026-11-12, P26bq); P278 after P277; P290 after P288 and
  P289.
- **T (TUX):** P272 -> P282 -> P281; then P293 -> P294 -> P299. (2026-11-12, P26br) P272b
  beside P272 (no shared file); it merges first.
- **A (ART):** P273 at once; P279, P280, P291, P292 after P237, in any order.
- **I (AI):** P274; P283; P295, P295b and P300.
- **Critical paths.** Wave 1: P270b -> P271 -> P272 -> P275 (2026-11-12, P26bq: P271b beside
  P272, before P272's phone step and P275). Wave 2: P276 -> P277 -> P278 ->
  P283 -> P284. Wave 3: P285 -> P286 -> P287 -> P288 -> P290 -> P295 -> P296 -> P297, with P262
  before P286.

### File ownership (no two open rows share a file)
| Lane | Files (production) |
| --- | --- |
| S | `game/sim/{Command,Sim,World,WorldLoad,WorldHash,Buildings,Outcome,Strike,Targeting,PlayerView,Mend,Repair,Mines,MineMemory,Carry}.gd`, `game/sim/defs/*.gd`, `game/core/MatchSnapshot.gd`, `native/sim_kernels/src/core/targeting.cpp`, `native/sim_kernels/src/bind/{kernel_targeting.cpp,world_access.h}` |
| D | `data/units/*`, `data/weapons/*`, `data/factions/*`, `data/rules.tres` |
| T | `game/view/{EffectsLayer,BuildingCollapse,RepairFx,MineLayer,HealthBarLayer,CollapseFx}.gd` (the last two: P272b, 2026-11-12, P26br), the glyph pass file, `scenes/main.tscn` (the `MineLayer` node), `game/ui/CommandBar.gd`, `game/input/{OrderRules,MineAim,PlayerController}.gd`, `data/input_settings.tres` |
| A | `tools/artgen/**`, `assets/art/**`, STYLE.md own sections |
| I | `game/ai/**`, `data/ai/**` |

Shared with ADR 0036's rows: `Carry.gd` (P262-P263b first, then P289), `Removal.gd` (2026-11-12,
P26bq: P271, then P263, then P289), `World.gd` (P232, P262,
then P286), `world_access.h` (P232, then P298), `Targeting.gd` (P238, then P298),
`EffectsLayer.gd` and `BuildingCollapse.gd` (P265 and P272, since 2026-11-12 P272b: the first makes the flag a match),
`CommandBar.gd` (P244, P265, P272, P282, P294, P299), `PlayerView.gd`. The lead keeps one open
row per file. The order is in "Merge order of the shared rows" below (2026-11-09).

## Acceptance per row (short)
- **P271:** ADR 0037 §3 and §4 cases pass; the state hash of the perf arena and `TICK_0_SEED_1`
  unchanged; no allocation in `Mend.run` (the existing guard).
- **P272:** a resting thumb never sells; the second tap after `sell_confirm_ms` re-arms; the last
  producer asks the question card; an enemy's mend switch draws no wrench (P272b, 2026-11-12,
  P26br); six sizes; phone: sell a Turbine Hall at half health, credits rise by about a quarter of
  its price.
- **P276/P277:** the shared contract test passes with ADR 0036's airfield cases; `Air.run` and
  `Repair.run` never serve one row; reach covers every ring point (data test); `REPAIR_CHECKS`
  at most `ceil(R / period) * rows` per tick.
- **P279/P280/P291/P292:** page pins inside the budget P237 set for this plan; if a page passes it,
  stop and report to the lead (ADR 0037 §13's fallbacks).
- **P287/P288:** ADR 0037 §8 cases; `mine_at` equals a full rebuild after every step; two layers
  at 11 of 12 give one mine; `MINE_CHECKS` at most rows per tick plus detectors x mines on fog
  turns; 0 with no mine.
- **P293:** an unknown enemy mine is in no snapshot list and never drawn (a test on a snapshot);
  `MineLayer` is under `GroundFx` in the tree.
- **P295/P295b/P300:** the fairness cases (P296) pass; each new unit type is built in at least half
  of the balance run's matches.
- **P298:** the lockstep cases pass under twin and kernel; with every stance 0 no golden moves.

## Budget (ADR 0037 §13)
| Wave | Sim time per tick (phone) | Draw calls | Page 1 rows (estimate) |
| --- | --- | --- | --- |
| 1 | under 0.02 ms, on period ticks | 0 | 0 |
| 2 | under 0.05 ms | 0 | ~240 |
| 3 | under 0.1 ms with mines; hold position negligible | +1 | ~490 at 16 directions, ~245 at 8 |

## Size estimate (all before launch)
| Wave | Rows | Production lines | C++ | Models |
| --- | --- | --- | --- | --- |
| 1 | 7 (P271-P275, P271b, P272b) | about 850 (as built, 2026-11-12, P26br) | 0 | 0 (3 glyphs) |
| 2 | 9 (P276-P284) | about 840 | 0 | 4 |
| 3 | 17 (P285-P300, P295b) | about 2,100 | about 120 | 4 (+ marks, 2 glyphs) |
| Total | 33 | about 3,790 | about 120 | 8 |

Tests come on top, about 1.5 times the production lines, as in Phases 3 and 4.

**Time at the current pace.** Wave 1 is about 2-3 days of rows plus one balance run. Wave 2 adds
about 4-5 days to ADR 0036's work (two art rounds with Michael). Wave 3 adds about 1.5-2 weeks
(mines are the long pole: memory, AI and tuning; hold position is about 2 days). With ADR 0036's
block before launch, the launch moves later by the two plans together.

## Risks
- **The atlas page.** ADR 0036's buildings and this plan's types compete for page 1; P237
  decides the room. Fallbacks in ADR 0037 §13; Michael chooses if they are not enough.
- **Shared rows and files.** `Carry.gd`, `REPAIR`, the role, P262, `Targeting.gd`, the DIED-flag
  readers and `CommandBar.gd` belong to two plans; the lead merges in ADR 0037 §2's order, made
  one fixed order on 2026-11-09 ("Merge order of the shared rows").
- **The skill text.** P272, P282, P294 and P299 wait for Michael's yes to the `touch-ui-rules`
  text; wave 1's UI cannot merge before it. The draft was written on 2026-11-09 (P230/P270b).
  Closed 2026-11-09: Michael said yes, and the text is applied to the skill.
- **Mines and match length.** Mines could stall pushes; the balance run's "no match over 15
  minutes" and the median length watch it; `mine_cap` and `mine_cost` are the knobs.
- **Hold position's effect.** Idle units already never chase today; hold position changes
  attack-moving units and the attack follow-up only (ADR 0037 §15). The phone check (P297) shows
  Michael what it does.
- **Gate check 4.** Six more unit types (26 in all) must each be built in half the matches; the
  build orders must include them (P283, P295, P295b).
- **Balance runs.** Every merge under `data/**` starts `balance.yml`; data rows are batched (P278,
  P290) so each wave starts few runs.
- **Scope creep.** Ranks, patrol and hold fire stay out until a later update's plan.

## Merge order of the shared rows (both plans; 2026-11-09, P230 and P270b)
The same text stands in `docs/plans/2026-11-09-air-and-tech.md` and
`docs/plans/2026-11-09-ground-support.md`. It replaces every "whichever comes first" of both plans
and of ADR 0037 §2 with one order. The lead keeps one open row per shared file.
1. **Start.** After the Phase 4 gate, P231 (defs), P237 (the page probe) and ADR 0037's wave 1
   (P271, P273, P274) may start at once. Wave 1 needs no air row.
2. **Art.** P237 merges before any art row of either plan: P236, P239b, P245, P245b, P249, P266,
   P279, P280, P291 and P292. (2026-11-12, P26br) P245 also waits for P243's `page_of` re-key, and
   P202 merges before the next of P239b, P245b and P249 (ADR 0036 §15's P236 note).
3. **Layouts and re-pins, in this order:** P232 (format 6, exception 23), then P262 (format 7,
   exception 24), then P286 (format 7, exception 25). No other row re-pins a golden.
4. **The repair role.** P231 declares it on `UnitDef` with `repair_slots` and `repair_seek_milli`
   (ADR 0037 §2), and P232 adds its type tables. P241b builds `REPAIR` (7) with the pads. Then
   P276 (`Repair.gd`) and P277 (the footprint-centre service point) follow. P276 adds no defs or
   type tables, and P277 does not build `REPAIR`.
5. **`Carry.gd`.** P262, P263 and P263b build it; then P289 adds the eject. The transport comes
   first; ADR 0037 §2's option of the ground carrier first is not taken.
6. **The DIED-flag readers.** The first of P272 and P265 to land turns `EffectsLayer._add_death`
   and `BuildingCollapse.cancelled` into a match on the flag; P272 (wave 1) is expected first.
   (2026-11-12, P26br) P272b, P272's view half, does it.
7. **`Targeting.gd` and `world_access.h`.** P232 declares the X-list rows, P238 adds the layer
   test, then P298 adds `stance`.
8. **`CommandBar.gd`.** P272, P244, P282, P265, P294 and P299, one open at a time, in the order
   they become ready. (2026-11-09) Michael said yes to the `touch-ui-rules` text; it is applied
   to the skill, so none of the six waits for it.
9. **Balance runs and the gate.** P275 (after wave 1) and P255 with P284 (part 1 and wave 2, 18
   types) are interim tuning runs. The Phase 4b gate is P268 with P297: 26 types, ADR 0031's gate
   run on held-out seeds, then Michael's phone.

Note (2026-11-12, P26bq, the lead; from the reviews of the first Phase 4b rows):
- **Order** (adds to "Merge order of the shared rows"; its item 1 is unchanged, wave 1 still
  needs no air row): P271 (SELL and MEND) merges before P232. It moves `remove_dead`'s body (now
  `Removal.run`) and `_compact` out of `World.gd` into a new `game/sim/Removal.gd` (World.gd 1000
  -> 960 lines), so P232 starts on that `World.gd`. `Removal.gd` joins lane S's files. P263
  replaces P271's placeholder `Removal.BOARDED` (-2) with `Carry.BOARDED`.
- **Data.** P271 ships the four rule ints inert; row P271b (wave 1 above) writes ADR 0037's
  starting values (ADR 0037: "starting value 50"; "starting 10", "(15)", "(30)") before P272's
  phone step and P275.
- **Lead decision** (2026-11-12; not Michael's, not a reviewer's) on `PlayerView`'s public
  methods. P271 kept it at gdlint's 20 by making the unused `row_harvest_mode` private (ADR 0020
  §1's note). No row of either Phase 4b plan lifts a gdlint limit with a pragma. A row that needs a
  21st public method first does a pure-move split of one group of reads, in its own commit, with
  the callers in `game/ai` coordinated by the lead (as ADR 0030 §4's P198 note asks). A new read
  may be a public field or a `columns()` copy only for data every player may know (the type
  tables, the public columns id, owner, type, pos, hp, build_left); an own-only read stays a
  getter that answers MISSING for other rows (ADR 0020 §1, ADR 0030 §7).
- **Atlas** (as the air plan's note): P237 put every shadow on page 2. The art rows P279, P280,
  P291 and P292 re-pin `TODAY_*` and `TODAY2_*` in `tests/view/test_iso_atlas_budget.gd`. They
  stay at 16 directions, and page 1's budget rises to 3,840 only if a row needs it (Michael,
  2026-11-11, ADR 0036 §15's P237 note).
- **Follow-up.** `GhostMemoryLayer`'s hidden pool sprites keep an old atlas page after a new match
  (pre-existing; P237 fixed the unit rigs). A view row that touches that layer clears them.

Note (2026-11-12, P26br, the lead; from the reviews of P272, P272b and P274):
- **P272 split for size** (CLAUDE.md's ~400 lines).
  - P272 keeps the orders UI: `game/input` (`BuildingOrders`, `SellArm`), `CommandBar`,
    `ConfirmDialog`, `scenes/main.tscn`'s `SellCard`, the timings in `data/input_settings.tres`
    and the HOW_TO_PLAY rows.
  - Row P272b takes the view: the wrench, the DIED-flag readers and the pack-up.
  - Merge order: P271b, P272b, P272. P272's HOW_TO_PLAY rows describe P272b's look.
  - After review, P272 ends at about 450 production lines including comments (about 300 without),
    over the limit because of review asks (hold timing, the card's lifetime, the bar's generic
    order dispatch). The lead accepts it rather than split it a second time.
- **P272b and P265.** Both DIED-flag readers send flag 2 (boarded) down flag 1's path (nothing)
  until P265 decides its look (step 6 of the merge order).
- **P274 as built** (the dated notes in ADR 0037 §4 and ADR 0030 §6, in P274's PR):
  - The AI only switches MEND on, after `AiProduction`.
  - It does so when credits, after the think's spending and the economy's hold, are strictly above
    `mend_floor`, and it switches the Headquarters on at any credits (it mends free, ADR 0037 §4).
  - Easy never mends. Normal is 50 % and 400, Hard 70 % and 250 until P275 tunes them.
  - The frozen `perf_ai` levels stay inert (script defaults 0), so the Perf AI card times the guard
    only. No card times the live path yet; P275's balance run is the first that plays it.

Note (2026-11-13, P26bv, the lead; from merge wave 5):
- **P285 as built (#429).** It shipped the defs together with P263 (#428). `data/rules.tres` sets
  `mine_cap` to 12. That value stays inert while no type has a `mine_weapon`. The test support now
  holds the data rules for mine weapons and for unique weapon ids.
- **P286 waits for P246a.** P246a is a lead-added row in the air-and-tech plan's P26bv note. It
  splits `World.gd`, which is at 994 of gdlint's 1000 lines, so that P286's mine table, records and
  `stance` column fit.
- **The Perf AI trigger is now 11 ms** (Michael, 2026-11-13). The Phase 4 plan's P26bv note has the
  details.
