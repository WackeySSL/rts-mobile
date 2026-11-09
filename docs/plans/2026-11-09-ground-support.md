# Plan: ground support (sale, building repair, repair buildings, medics, a carrier, mines)

Date: 2026-11-09. Base: `main` at b6bfe95. Author: architect (row P270, branch
`claude/design-ground-support`). Decision:
`docs/adr/0037-ground-support-repair-medics-carriers-mines.md` (**proposed**). Reconciled the same
day with ADR 0036 and its plan `docs/plans/2026-11-09-air-and-tech.md` (branch
`claude/design-air-and-tech`, e01ee4c).

- **Status.** The design is done now. **Building starts after the Phase 4 gate** (Michael,
  2026-11-09). Michael picks the releases with ADR 0037's question 1. The recommendation (B):
  - version 1: sale and building repair (rows P271-P275);
  - update 1.1, with ADR 0036's aircraft: repair buildings and medics (rows P276-P284);
  - update 1.2, with ADR 0036's transport aircraft: the ground carrier and mines (P285-P297).
- **Row ids.** P270-P297. The lead asked for P260 upward, but ADR 0036's plan holds P230-P269
  (P262-P268 used, P269 kept for its 1.2 splits), so this plan starts at P270. Checked free with
  `git grep` on every local and remote branch. P298-P299 stay free for this plan's splits.
- **Named exceptions.** Exception 22 is P189b's. The next free one is 23; the first of the two
  plans (ADR 0036's, this one) to merge a row that needs one takes 23. This plan needs at most one:
  P286's own re-pin, and only if P262 merged before it (ADR 0037 §11).
- **Shared with ADR 0036** (ADR 0037 §2): Commands `LOAD` 5, `UNLOAD` 6, `REPAIR` 7; the repair
  role; `Carry.gd`; `STATE_FORMAT` 6 and 7; the page rule and P237. No second `LOAD` or `REPAIR`.

## Goal
- **Version 1:** a player can sell a finished building for part of its price and switch on a paid
  repair of a damaged building; the AI repairs its buildings on Normal and Hard.
- **1.1:** the Weld Shed and the Drone Dock repair vehicles; Patchers and Menders heal squads; the
  AI builds and uses both; the 1.1 gate counts the four new types.
- **1.2:** the Bunk Wagon and the Linecar carry squads; the Shot Truck and the Seeder lay hidden
  mines that detectors find; the AI rides and mines fairly; the 1.2 gate counts them.
- Every row keeps the 150-unit budget and adds no kernel edit.

## Out of scope (each needs a plan change and Michael's yes)
A repair vehicle; passengers firing (question 2 B); friendly-fire mines (question 3 B and C);
ranks, stances and patrol (question 4); auto-paths round known mines; mines on the radar;
anything in ADR 0037's "Out of scope".

## Affected modules
- **`game/sim`**
  - Changed: `Command` (types 8, 17, 18 and their factories), `Sim` (the branches), `World`
    (events 7 and 8, `SOLD`, the stats, the role and mine type tables, the mine table and records in
    1.2), `WorldLoad`, `WorldHash` (section `mines`, 1.2), `Buildings` (sale, a placed building
    removes a mine), `Outcome` (no loss for flag 3), `Strike` (a rupture clears mines),
    `PlayerView` (`row_mend`, `own_mines`, `known_mines`, type tables), `Carry` (eject, 1.2).
  - New: `Mend.gd` (ECONOMY), `Repair.gd` (ECONOMY, after `Air.run`), `Mines.gd` (FIRE mark and
    ECONOMY), `MineMemory.gd` (MEMORY).
  - Defs: `UnitDef` (the role moved from `BuildingDef`, `repair_slots`, `repair_seek_milli`,
    `mine_weapon`, `mine_cost`, `mine_aware`, `detect_milli`, `carry_eject_percent`), `WeaponDef`
    (`blast_milli`), `RulesDef` (`sell_refund_percent`, `mend_*`, `mine_*`, `sweep_ticks`).
- **`native/sim_kernels`:** none.
- **`game/core`:** `MatchSnapshot` (mend switches of the local player, own mines and its records).
- **`game/view`:** `BuildingCollapse` (flag 3), the glyph pass (wrench), `RepairFx` (new, in the
  GroundFx and AirFx rings), `MineLayer` (new, z 3).
- **`game/input`, `game/ui`:** `CommandBar.ORDERS` (REPAIR, SELL, MINE; building orders),
  `OrderRules` (the serve-tap rule, shared with ADR 0036's P244), `MineAim` (new, on
  `StrikeAim`'s pattern), `data/input_settings.tres` (`sell_confirm_ms`).
- **`game/ai`:** `AiEconomy`, `AiProduction`, `AiArmy`, `AiStrikes` (calls `AiMines`, new),
  `OpponentDef`, `AiDifficultyDef`, the build orders.
- **`data/`:** 8 new types and 2 mine weapons, rosters, `rules.tres`, AI data; frozen arenas
  (`data/dev/arena/`) untouched.
- **`tools/artgen/`, `assets/`:** 8 models, 2 x 3 mine marks, a drone fx, 3 glyphs, 8 item cards.
- **`docs/`:** HOW_TO_PLAY rows in each player-facing row; GDD and ROADMAP in P270b and the
  release wrap-ups.

## Command, state and data changes (summary of ADR 0037)
- **Commands:** `LAY_MINE` 8, `SELL` 17, `MEND` 18 (new); `LOAD` 5, `UNLOAD` 6, `REPAIR` 7
  (ADR 0036's, shared). 9 and 19 reserved for `STANCE` and `PATROL`.
- **Events:** `MINE_BLAST` 7, `REPAIRED` 8; DIED flag 3 = sold.
- **State:** version 1 and 1.1 change no layout (the mend switch is a building's `cargo`); 1.2's
  mine table and records ride ADR 0036's `STATE_FORMAT` 7 (P262). No bump of this plan's own.
- **Data:** every number in `data/*.tres`, starting values in ADR 0037 §3-§8.

## Test plan (what is proven headless)
ADR 0037 §16 lists the cases per feature. In short:
- **Determinism:** the replay test on a scenario that sells, mends, repairs, heals, loads, ejects,
  lays, blasts and sweeps, under both implementations; hashes equal.
- **Hash neutrality:** P271 and P276 move no golden and no `TICK_0_SEED_1` (frozen arenas never
  use them); a test asserts `state_hash` is unchanged on the perf arena.
- **Rules:** one suite per module (`test_sell.gd`, `test_mend.gd`, `test_repair_role.gd`,
  `test_medic.gd`, `test_carry_eject.gd`, `test_mines.gd`, `test_mine_memory.gd`).
- **Fairness:** byte-equal AI Commands for two worlds that differ only in hidden things (an
  unknown mine, a loaded enemy carrier, an enemy's mend switch).
- **Budget:** counted bounds (`REPAIR_CHECKS`, `MINE_CHECKS`) on `perf_bases`; the draw-call guard
  +1 for `MineLayer`; page pins after each art row. No timing runs in a session.
- **Touch:** two-tap sell and its disarm, the serve-tap rule, the mine aim at ADR 0015's six sizes.
- **Mutation testing:** P271, P276, P287, P288 (about 10 chosen mutants each).

## Rows
Owners: GD gameplay-dev, AI ai-dev, ART art-director, TUX touch-ux-dev, QA qa-engineer, LEAD the
lead, ARCH architect. Size = production lines (tests, fixtures and `.tres` do not count). Every
player-facing row adds its HOW_TO_PLAY rows.

### Docs
| Row | Owner | What | Size | Depends |
| --- | --- | --- | --- | --- |
| P270 | ARCH | This plan and ADR 0037 (proposed) | 0 | - |
| P270b | LEAD | Acceptance: Michael's answers and names in ADR 0037; dated notes in ADRs 0007, 0010, 0017, 0018, 0023, 0030, 0031 and 0036 (ADR 0037's list); GDD rows and "Not in version 1" per question 1; a ROADMAP box per release | docs | Michael's answers |

### Version 1 (sale and building repair)
| Row | Owner | What | Size | Depends |
| --- | --- | --- | --- | --- |
| P271 | GD | `SELL` 17 and `MEND` 18: factories, `Sim` branches, `SOLD` and DIED flag 3, `Outcome` skips it, `Mend.gd` (staggered, priced, stops at full), `RulesDef` fields (inert defaults), `PlayerView.row_mend`, snapshot field; hash-neutral test | 200 | P270b, the Phase 4 gate |
| P272 | TUX | Building orders on the command bar: `REPAIR` toggle and two-tap `SELL` with "+N"; wrench glyph (own); the sold pack-up (flag 3: no flash, no crater); `sell_confirm_ms`; HOW_TO_PLAY Buildings rows (Teach) | 270 | P271, P273 |
| P273 | ART | Glyphs `glyph_repair` (wrench) and `glyph_sell` (coin out); STYLE.md glyph rows | SVG | P270b |
| P274 | AI | `AiEconomy` mends below `mend_below_percent` above `mend_floor` (Normal, Hard); data in `AiDifficultyDef` | 80 | P271 |
| P275 | LEAD | Balance run after P274 (data and AI merged), phone check (sell and mend upright and sideways), ROADMAP tick | docs | P272, P274 |

### Update 1.1 (repair buildings and medics; with ADR 0036's 1.1)
| Row | Owner | What | Size | Depends |
| --- | --- | --- | --- | --- |
| P276 | GD | The repair role on `UnitDef` (ADR 0036 §2 names; built here if P231 has not, else moved), `repair_slots`, `repair_seek_milli`; `Repair.gd` after `Air.run` (types without pads, staggered, `target_grid` query, slots order, price, `REPAIRED` event, medic seek); `REPAIR_CHECKS` | 310 | P270b, P231 if merged |
| P277 | GD | `REPAIR` 7 at a building's dock point (`Buildings.aim`); built here if P241b has not, else added to it; the shared contract test's ground cases | 100 | P276, P241b if merged |
| P278 | GD | Data: Weld Shed, Drone Dock, Patchers, Menders (rosters, requires, ADR 0037 starting values); name width test; HOW_TO_PLAY Units and Buildings rows (Teach: repair) | data | P277 |
| P279 | ART | Weld Shed and Drone Dock models (body, `dmg2` at 0.75, `anim`), page pins | art | P237 |
| P280 | ART | Patchers and Menders (two figures, 8 directions, walk 4, idle 2), the Accord drone fx (2 frames), item cards, page pins | art | P237 |
| P281 | TUX | `RepairFx`: sparks (Weld Shed), drones out and back (Drone Dock), medic glow, from `REPAIRED`, seen-only; ring quotas | 160 | P278, P279, P280 |
| P282 | TUX | `REPAIR` order for served selections (nearest serving building) and the serve-tap rule in `OrderRules` (shared with P244: whichever comes first builds it); unarmed rows of an attack get `ATTACK_MOVE`; six sizes | 100 | P278 |
| P283 | AI | `AiProduction` (repair building after the vehicle factory, `medic_per_squads`), `AiArmy` (`REPAIR` under `repair_retreat_percent`, medics in waves with `ATTACK_MOVE`) | 170 | P278 |
| P284 | LEAD | Joins ADR 0036's 1.1 gate (P255) and phone check (P256): 20 types, repair and medics checked on the phone | docs | P281-P283 |

### Update 1.2 (the ground carrier and mines; with ADR 0036's 1.2)
| Row | Owner | What | Size | Depends |
| --- | --- | --- | --- | --- |
| P285 | GD | Defs: `mine_weapon`, `mine_cost`, `mine_aware`, `detect_milli`, `carry_eject_percent`, `WeaponDef.blast_milli`, the mine rules (`mine_cap` 0 by default); type tables; data tests; hash-neutral | 100 | P270b, P231 |
| P286 | GD | The mine table, `next_mine_id`, the records, section `mines`, derived `mine_at`; rides `STATE_FORMAT` 7: inside P262's re-pin if before it, else one re-pin under P262's exception (or 23 if none) | 150 | P285; P262 if merged |
| P287 | GD | `Mines.gd` 1: `LAY_MINE` 8 (Formation slots, `carry_mode` 2, lay in ECONOMY, cost, cap, arm), trigger and blast in the FIRE mark (`MINE_BLAST`, no friendly damage, air passes), rupture clears, a placed building removes; `MINE_CHECKS`, `MINES_REFUSED` | 300 | P286, P262 |
| P288 | GD | `MineMemory.gd` (forget, remember by detectors on the fog turn), sweeping (`carry_mode` 3), `PlayerView.own_mines`/`known_mines`, the snapshot's own and known lists | 250 | P287 |
| P289 | GD | `Carry` eject: `carry_eject_percent` in the carrier-death path (ring search, hp, `UNLOADED`, no-room deaths and losses); the ground-carrier data checks | 100 | P263b, P285 |
| P290 | GD | Data: Bunk Wagon, Linecar, Shot Truck, Seeder, shot charge and pulse seed weapons, detect on Flarejack and Swift; name width test; HOW_TO_PLAY Units, Orders, Fog rows (Teach: load, unload, lay, hidden mines) | data | P288, P289 |
| P291 | ART | Bunk Wagon and Linecar (16 directions, or 8 per P237's page result), item cards, page pins | art | P237 |
| P292 | ART | Shot Truck and Seeder (as P291), mine marks per faction (own, known), `glyph_mine`, item cards | art | P237 |
| P293 | TUX | `MineLayer` (z 3, own and known marks, dimmed records, unarmed half alpha, one `_draw`), blast fx and scorch where seen; draw-call guard +1 | 220 | P288, P290, P291, P292 |
| P294 | TUX | `MINE` order with "n/cap" and `MineAim` (tap, ring, check mark, X, turn cancels); the ground carrier in P265's LOAD taps and `UNLOAD` aim (data only, checked); six sizes | 150 | P293, P265 |
| P295 | AI | `AiMines` in `AiStrikes`' slot: lay on the own-half route, sweep known mines before a wave, scouts ahead on Hard; Easy none | 250 | P290 |
| P295b | AI | Ground rides in `AiArmy` on P267's drop code: load at staging, unload at `ride_unload_tiles` | 150 | P290, P267 |
| P296 | QA | The fairness cases (unknown mine, loaded enemy carrier, enemy mend switch), counted bounds on `perf_bases` with 24 mines and repairers, the replay with every new Command, harness types (24) | tests | P293-P295b |
| P297 | LEAD | Joins ADR 0036's 1.2 gate and phone check (P268): mines found, swept and blasting; ground load, unload and eject | docs | P296 |

### Lanes and order
- **S (GD):** P271 -> P276 -> P277; later P285 -> P286 -> P287 -> P288; P289 beside P287.
- **D (GD data):** P278 after P277; P290 after P288 and P289.
- **T (TUX):** P272 -> P282 -> P281; later P293 -> P294.
- **A (ART):** P273 at once; P279, P280, P291, P292 after P237, in any order.
- **I (AI):** P274; P283; P295 and P295b.
- **Critical paths.** Version 1: P270b -> P271 -> P272 -> P275 (four rows). 1.1: P276 -> P277
  -> P278 -> P283 -> P284. 1.2: P285 -> P286 -> P287 -> P288 -> P290 -> P295 -> P296 -> P297.

### File ownership (no two open rows share a file)
| Lane | Files (production) |
| --- | --- |
| S | `game/sim/{Command,Sim,World,WorldLoad,WorldHash,Buildings,Outcome,Strike,PlayerView,Mend,Repair,Mines,MineMemory,Carry}.gd`, `game/sim/defs/*.gd`, `game/core/MatchSnapshot.gd` |
| D | `data/units/*`, `data/weapons/*`, `data/factions/*`, `data/rules.tres` |
| T | `game/view/{BuildingCollapse,RepairFx,MineLayer}.gd`, the glyph pass file, `game/ui/CommandBar.gd`, `game/input/{OrderRules,MineAim,PlayerController}.gd`, `data/input_settings.tres` |
| A | `tools/artgen/**`, `assets/art/**`, STYLE.md own sections |
| I | `game/ai/**`, `data/ai/**` |

Shared with ADR 0036's rows: `Carry.gd` (P262-P263b first, then P289), `OrderRules.gd` (P244 or
P282 first), `PlayerView.gd`, `World.gd`, `CommandBar.gd`. The lead keeps one open row per file.

## Acceptance per row (short)
- **P271:** ADR 0037 §3 and §4 cases pass; `state_hash` of the perf arena and `TICK_0_SEED_1`
  unchanged; no allocation in `Mend.run` (the existing guard).
- **P272:** a resting thumb never sells; the second tap after `sell_confirm_ms` re-arms; six sizes;
  phone: sell a Turbine Hall at half health, credits rise by about a quarter of its price.
- **P276/P277:** the shared contract test passes with ADR 0036's airfield cases; `Air.run` and
  `Repair.run` never repair one row twice in a period.
- **P279/P280/P291/P292:** page pins inside the budget P237 set for this plan; if a page passes it,
  stop and report to the lead (ADR 0037 §13's fallbacks).
- **P287/P288:** ADR 0037 §8 cases; `MINE_CHECKS` at most mobile rows per tick; 0 with no mine.
- **P293:** an unknown enemy mine is in no snapshot list and never drawn (a test on a snapshot).
- **P295/P295b:** the fairness cases (P296) pass; each new type is built in at least half of the
  balance run's matches.

## Budget (ADR 0037 §13)
| Release | Sim time per tick (phone) | Draw calls | Page 1 rows (estimate) |
| --- | --- | --- | --- |
| Version 1 | under 0.02 ms, on period ticks | 0 | 0 |
| 1.1 | under 0.05 ms | 0 | ~240 |
| 1.2 | under 0.1 ms with mines | +1 | ~490 at 16 directions, ~245 at 8 |

## Size estimate
| Release | Rows | Production lines | C++ | Models |
| --- | --- | --- | --- | --- |
| Version 1 | 5 (P271-P275) | about 550 | 0 | 0 (2 glyphs) |
| 1.1 | 9 (P276-P284) | about 840 | 0 | 4 |
| 1.2 | 14 (P285-P297, P295b) | about 1,670 | 0 | 4 (+ marks) |
| Total | 28 | about 3,060 | 0 | 8 |

Tests come on top, about 1.5 times the production lines, as in Phases 3 and 4.

**Time at the current pace.** Version 1's part is about 2-3 days of rows plus one balance run.
1.1's part adds about 4-5 days to ADR 0036's 1.1 (two art rounds with Michael). 1.2's part adds
about 1-1.5 weeks to ADR 0036's 1.2 (mines are the long pole: memory, AI and tuning).

## Risks
- **The atlas page.** ADR 0036's buildings and this plan's types compete for page 1; P237
  decides the room. Fallbacks in ADR 0037 §13; Michael chooses if they are not enough.
- **Shared rows.** `Carry.gd`, `REPAIR`, the role and P262 belong to two plans; the lead merges in
  ADR 0037 §2's order and keeps one open row per file.
- **Mines and match length.** Mines could stall pushes; the balance run's "no match over 15
  minutes" and the median length watch it; `mine_cap` and `mine_cost` are the knobs.
- **Gate check 4.** Eight more types must each be built in half the matches; the build orders
  must include them (P283, P295, P295b).
- **Balance runs.** Every merge under `data/**` starts `balance.yml`; data rows are batched (P278,
  P290) so each release starts few runs.
- **Scope creep.** Ranks, stances and patrol stay out until Michael answers question 4.

## Questions for Michael
ADR 0037's five questions: 1 when (rec. B), 2 the carrier (rec. A), 3 mines and own units (rec. A),
4 ranks, hold position and patrol (rec. A: later), 5 names (rec. A).
