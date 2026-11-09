# Plan: air, anti-air, transports, drone squads, engineering centre, space centre

Date: 2026-11-09. Base: `main` at b6bfe95. Decision: `docs/adr/0036-air-layer-anti-air-map-reveal-and-upgrades.md`
(**proposed**). Design: the GDD section "Planned: air, anti-air, engineering centre, space centre".

- **Status.** The design is done now. **Building starts after the Phase 4 gate** (Michael,
  2026-11-09). Michael decides version 1 or an update with ADR 0036's question 2. The
  recommendation is update 1.1 (rows P230-P256), then 1.2 (rows P262-P268) with the ground
  design's infantry carrier.
- **Row ids.** P230-P268, checked free against `git log --all` and the open lanes' plans:
  - the visual polish plan holds P200-P219 and ADRs 0034-0035;
  - ADR 0033 is seat symmetry;
  - P220-P229 stay unused as a buffer for the polish plan;
  - P257-P261 are kept for 1.1 splits and P269 for 1.2's.
- **Named exceptions.** They continue at 22, if still free when P232 starts. The lead confirms.
- **Ground design.** It meets this plan at ADR 0036 §7: Command types `LOAD = 5`, `UNLOAD = 6` and
  `REPAIR = 7`, the repair role and the carrier role. The lead reconciles the numbers before either
  ADR is accepted. Whichever release comes first builds `Carry.gd`.

## Goal
- **1.1:**
  - airfields with a fighter and a bomber per faction (ammo, return, reload, repair on the pad);
  - anti-air buildings per faction, with rockets, rifles and the Redoubt given their air bits;
  - the space centre and its satellite sweep;
  - the engineering centre with two bomber upgrades per faction;
  - the AI using all of it fairly;
  - a 1.1 balance gate on 16 unit types.
- **1.2:** a transport and a drone squad per faction, with LOAD and UNLOAD; the AI's drops.

## Affected modules
- **`game/sim`**
  - Changed: `World`, `WorldLoad`, `WorldHash`, `Sim` (Commands 5-7, `Reveal.run` and
    `Carry.board` in REMOVE), `Strike` (kind 3, rupture skips air), `FogGrid.reveal`, `Targeting`
    (layer bits), `Separation` (same layer), `Combat` (`damage()`, ammo, fire guard),
    `Production` (FLIGHT cap, research completion), `ProductionSpawn` (spawn over a pad),
    `Buildings` (ground planes only), `PlayerView` (`enemy_reveal_active`, own `upgrades`, tabs).
  - New: `Air.gd` (ECONOMY), `Reveal.gd` (REMOVE), `Carry.gd` (1.2).
  - Defs: `UnitDef`, `WeaponDef`, `BuildingDef`, `FactionDef`, new `UpgradeDef`.
- **`native/sim_kernels`:** `MOVE_CLASSES` 4; the TARGETING layer test; the SEPARATION
  same-layer test. There are no new kernels.
- **`data/`:**
  - units, weapons and factions: new `.tres` per faction, and masks on the rocket, rifle and
    Redoubt weapons;
  - `rules.tres`: `passenger_cap`, `load_reach_milli`, `unload_reach_tiles` (1.2);
  - `data/ai/` build orders, `OpponentDef` and difficulty values;
  - `data/dev/arena/` frozen `perf_air` defs.
- **`game/view`:** a new `AirLayer` (z 20) and air shadows (z 2); `IsoAtlas`/`RuntimeAtlas`
  page 2; fog fade on a sweep.
- **`game/input` and `game/ui`:** raised picking, tap-own-building = REPAIR or LOAD, the Unload
  button, the Flight and Research tabs, the reveal button and warning.
- **`game/ai`:** `AiProduction`, `AiIntel`, `AiArmy`, `AiStrikes`, build-order and difficulty
  defs.
- **`tools/artgen/`:** 16 models (8 buildings, 4 aircraft and 2 transports, 2 drone squads, across
  both factions).
- **`docs/`:** HOW_TO_PLAY rows in each player-facing row, the GDD, the ROADMAP (a section per
  update) and dated ADR notes (P230).

## Command and data changes (summary of ADR 0036)
- **Commands.** New: LOAD 5, UNLOAD 6 and REPAIR 7, all shared with the ground design; LOAD and
  UNLOAD in 1.2, REPAIR in 1.1. Everything else uses QUEUE, PLACE, MOVE, ATTACK_MOVE, ATTACK, STOP
  and SUPERWEAPON.
- **State.** `STATE_FORMAT` 6 in P232: `ammo`, `reveal_until`, `upgrades`, the type, weapon and
  upgrade tables, `TABS` 5 and the AIR plane. `STATE_FORMAT` 7 in P262: passengers and
  `carry_mode`. One re-pin each, under one named exception each.
- **Data.**
  - The `targets` mask on every weapon (default 1).
  - The AIR move class with `low_flying`.
  - Ammo and reload.
  - Pads and the repair role on buildings.
  - Strike kind 3.
  - `UpgradeDef`.
  - The carrier fields (1.2).

## Test plan (what is proven headless)
- **Determinism.**
  - The replay test (same seed, same hash) on a scenario with aircraft, a sweep, research and, in
    1.2, load and unload cycles.
  - The hash re-pinned once per layout row.
  - Every lockstep suite under both implementations.
- **Reveal (P233).**
  - `visible` rebuilt from the rows plus the reveal equals the live array after every step of a
    sweep.
  - The sweep ends on time, on the space centre's death and on its blackout.
  - `explored` is all 1 afterwards.
  - The dirty list overflows to `dirty_full` and the view redraws.
  - `World.prepare()` after a snapshot restores the stamp.
  - The TARGETING kernel sees revealed enemies.
  - `PlayerView.seen_rows` grows during the sweep, and `enemy_reveal_active` shows for the other
    player.
- **Layers (P238).**
  - Each mask x layer pair, in acquisition and in the ATTACK lock.
  - `_apply_attack` drops a command with no unit that can hit the target.
  - The fire guard.
  - The rupture spares air.
  - Lockstep cases with mixed layers.
- **Movement (P240).**
  - An aircraft crosses rock and a footprint in a straight line, with no flow key.
  - Separation pairs only within a layer.
  - INTEGRATE, SEPARATION and FLOW lockstep cases.
- **Air (P241, P241b).**
  - The cap at QUEUE, spawn over a free pad, a head waiting with no pad.
  - Ammo: spend, hold fire at 0.
  - Return at 0, the reload cadence, repair and its price, no repair without credits.
  - Re-homing, a homeless aircraft.
  - REPAIR validation.
- **Upgrades (P246).**
  - `Combat.damage` equals the old formula for dealt = taken = 100, on a fixed table of edge ints
    (0, 1, max percent, int32 bounds).
  - Research completion sets the bit, a second QUEUE is dropped, and the `mod_*` tables are
    rebuilt after `prepare()`.
- **Carry (P262-P263b).**
  - `insert_row` keeps ids ascending and every column aligned.
  - Board and unload keep ids, hp and groups.
  - A carrier's death kills and counts its passengers.
  - Passengers count toward `unit_cap`.
  - Unloading over rock finds no cell and stays aboard.
  - The hash is equal after N load and unload cycles under replay.
- **AI.**
  - The fairness suite: no Command targets an unseen row or a point the AI had no record of.
  - The AI-vs-AI smoke with air (three matches).
  - `perf_ai` think bounds during a sweep.
- **View and touch.**
  - Draw-call guards (+2 for air).
  - Page pins for both pages.
  - Pick order (an aircraft over a tank).
  - Tap-own-building rules.
  - The Unload aim.
  - Layouts at ADR 0015's six sizes.
- **Mutation testing** (sim rows only, about 10 chosen mutants each): P233, P238, P240, P241,
  P241b, P246, P262, P263.

## Rows
Owners: GD gameplay-dev, AI ai-dev, ART art-director, TUX touch-ux-dev, QA qa-engineer, LEAD the
lead (docs, gate runs, phone checks). Size = production lines (tests and fixtures do not count).
Every player-facing row adds its HOW_TO_PLAY rows.

### Update 1.1 (recommended order: satellite -> anti-air -> airfield and aircraft -> engineering centre)
| Row | Owner | What | Size | Depends |
| --- | --- | --- | --- | --- |
| P230 | LEAD | Acceptance docs: Michael's answers and names in ADR 0036 and the GDD; dated notes in ADRs 0007, 0008, 0009, 0010, 0013, 0016, 0017, 0018, 0023, 0027, 0030 and 0031; a ROADMAP section per update (or Phase 4b if version 1); the GDD "Not in version 1" line per question 2 | docs | Michael's answers; the Phase 4 gate |
| P231 | GD | Defs: `MoveClass` Air, `low_flying`, `ammo`, `rearm_ticks`, `WeaponDef.targets`, `pads` and `pad_offsets`, the repair role, `strike_kind` 3, `UpgradeDef`, `FactionDef.upgrades`, the Tab enum in exports; data tests (ranges, AIR-only fields). Hash-neutral: World copies nothing yet | 150 | P230 |
| P232 | GD | World v6: the columns and tables of ADR 0036 §3 (1.1 part), `type_layer_bit`, the AIR plane, `TABS` 5 (PlayerView slices, Production indexing; the drawer still lists three tabs), `MOVE_CLASSES` 4 in `world_access.h` and `fixed_math.cpp`, WorldLoad, WorldHash, snapshot classification, `STATE_FORMAT` 6, one re-pin (exception 22) | 380 (C++ ~15) | P231 |
| P233 | GD | Reveal: `FogGrid.reveal`, `Reveal.run` in REMOVE, the `prepare()` stamp, strike kind 3 in `Strike.apply_superweapon`, the STRIKE record of kind 3, `PlayerView.enemy_reveal_active`; a FOG lockstep case | 250 | P232 |
| P234 | GD | Space centre data, both factions (`.tres`, rosters, requires Radar, charge 2,700, sweep 675 or per question 3); name width test; HOW_TO_PLAY Superweapon rows (Teach) | 80 | P233, P230 |
| P235 | TUX | Reveal HUD: the strike button's no-aim variant (tap, check mark), the warning badge and line, the fog fade (`reveal_fade_ms`); six layout sizes | 300 | P234 |
| P236 | ART | Space centre models, both factions (whole + damage stages, a lift part as the anim) | art | P237 |
| P237 | ART | Atlas page probe and split: page 2 for unsorted layers (AirLayer, air shadows, DecalLayer, building shadows); measures rows, bake ms and texture memory; options a/b/c of ADR 0036 §15 to the lead; page pins. Coordinate with polish rows P202-P204 | 250 | P230 (may start at once) |
| P238 | GD | Target layers: TARGETING twin and kernel (`weapon_targets`, `type_layer_bit` in the checked list, acquisition and ATTACK lock), `_apply_attack`, `Combat.fire` guard, rupture skips air; masks on rocket (7), rifle (5) and Redoubt (5) weapons; lockstep cases. Split trigger: the lockstep test as P238b if over ~1,000 changed lines | 200 (C++ ~120) | P232 |
| P239 | GD | Anti-air data, both factions (building, weapon mask 6, requires Barracks); HOW_TO_PLAY Combat rows | 80 | P238, P230 |
| P239b | ART | Anti-air models, both factions (turret head, 16 directions) | art | P237 |
| P240 | GD | Air movement: SEPARATION same-layer test (twin and kernel), INTEGRATE and FLOW lockstep cases with aircraft, `ProductionSpawn` spawn over a pad, `Buildings` ground planes only (checked) | 200 (C++ ~40) | P232 |
| P241 | GD | Airfield rules: the FLIGHT cap at QUEUE, spawn over a pad, home and re-home, `air_rows`, ammo in `Combat.fire`, `Air.run` return and reload | 350 | P238, P240 |
| P241b | GD | REPAIR Command (7) for the airfield role, repair on the pad and its price, the shared repair-role contract test | 180 | P241 |
| P242 | GD | Airfield, fighter and bomber data, both factions (`.tres`, weapons, rosters); HOW_TO_PLAY Units, Orders and Buildings rows (Teach: go home, reload) | 120 | P241b, P230 |
| P243 | GD | View: `AirLayer` z 20, shadows z 2, `fly_px`, bob, death fall, enemy flyers only where seen, page 2; draw-call guard +2 | 350 | P237, P242 |
| P244 | TUX | Touch: raised picking (48 dp), aircraft over ground units in the pick order, tap an own airfield = REPAIR, an unhittable enemy tap selects, box and double-tap, the bomber's attack ring, the Flight tab in the drawer; six sizes | 350 | P243 |
| P245 | ART | Aircraft models: fighter and bomber, both factions (16 directions, body and shadow) | art | P237 |
| P245b | ART | Airfield models, both factions (pads, damage stages) | art | P237 |
| P246 | GD | Upgrades sim: research items from `UpgradeDef`, research completion in `Production`, `mod_*` tables, `Combat.damage` with its readers, `mod_ammo` in `Air.run`, own `upgrades` in PlayerView | 350 | P241 |
| P247 | GD | Engineering centre data and four UpgradeDefs (per question 5); HOW_TO_PLAY Build menu rows | 100 | P246, P230 |
| P248 | TUX | Research tab: cards, the researched mark, a locked card's sash (ADR 0032); six sizes | 200 | P247 |
| P249 | ART | Engineering centre models, both factions | art | P237 |
| P250 | AI | Production and Intel: build-order tiers (airfield, anti-air per seen aircraft, engineering centre, space centre on Normal and Hard), the air mix, research choice; counts of seen air and anti-air | 350 | P242, P247 |
| P251 | AI | Army: bomber raids (`raid_size`, the target by value and anti-air), fighters guard and escort, REPAIR below `air_retreat_percent` | 350 | P250 |
| P252 | AI | Strikes: fire the sweep (`reveal_blind_ticks`, before a wave), react to `enemy_reveal_active`; Easy builds none of the tech | 200 | P234, P250 |
| P253 | GD | `perf_air`: frozen defs in `data/dev/arena/`, a scenario with 16 aircraft among 150 units, golden and counted bounds, the perf card; the lead reads ADR 0013 §1 on its `PERF` line | 200 | P242, P246 |
| P254 | QA | Harness: per-type counts for the new types, `reveals`, `research` and air kills by layer in the report; ADR 0031 check 4 reads the rosters (16 types); the summary | 200 | P242, P247 |
| P255 | LEAD | Balance tuning (data rows, exception 20 style) and the 1.1 gate run: Normal against the mirror 40-60 %, no match over 15 minutes, every one of the 16 types used, the median length 8-10 minutes, aircraft at most 30 % of median army spend | data | P250-P254 |
| P256 | LEAD | Phone check with Michael (below) and the 1.1 wrap-up docs (GDD, ROADMAP ticks) | docs | P255, all art rows |

### Update 1.2
| Row | Owner | What | Size | Depends |
| --- | --- | --- | --- | --- |
| P262 | GD | World v7: the passenger table, `carry_mode`, carrier type tables, `World.insert_row`, `STATE_FORMAT` 7, one re-pin; the check that TARGETING leaves a MOVE row's `order_target` alone (else ADR 0036 §8's BOARD fallback, a TARGETING edit) | 350 | 1.1 shipped; the ground design reconciled |
| P263 | GD | `Carry.gd`: LOAD (5), boarding in REMOVE (DIED flag 2), passengers in `unit_cap` | 300 | P262 |
| P263b | GD | UNLOAD (6), unloading in ECONOMY (ring search, `UNLOADED` event), the carrier's death | 250 | P263 |
| P264 | GD | Transport and drone squad data, both factions (drone squads `low_flying`, INFANTRY tab, requires the airfield); HOW_TO_PLAY rows (Teach: load and unload) | 120 | P263b, P230 |
| P265 | TUX | LOAD taps both ways, the Unload button and its aim (chevron, check mark, X), passenger pips on the chip; six sizes | 350 | P264 |
| P266 | ART | Transport models (16 directions) and drone squads (8 directions), both factions | art | P237 |
| P267 | AI | Drops (Normal and Hard: load `drop_squads`, unload beside a seen or ghost refinery, away from seen anti-air), drone squads harass across cliffs | 300 | P264 |
| P268 | LEAD | 1.2 harness types (20), gate run, phone check, docs | docs | P265-P267 |

### Lanes and order
- **S (GD):** P231 -> P232, then P233 and P238 and P240 in parallel (separate files; P238 and
  P240 touch different kernels). Then P241 -> P241b -> P246.
- **D (GD data):** P234 after P233, P239 after P238, P242 after P241b, P247 after P246.
- **V (GD view):** P243 after P237 and P242.
- **T (TUX):** P235 -> P244 -> P248.
- **A (ART):** P237 first, then P236, P239b, P245, P245b and P249 in any order.
- **I (AI):** P250 -> P251 and P252.
- **Q:** P253 and P254, then the lead's P255 and P256.
- **Critical path for 1.1** (to the last row before the gate): P230 -> P231 -> P232 -> P238 ->
  P241 -> P241b -> P242 -> P250 -> P251 -> P254 -> P255. That is 11 rows plus the tuning rounds.

## Phone checks (Michael's phone, the lead's PerfCard)
1. **Satellite:** the sweep fades out and back in, sideways and upright, and the warning shows on
   the other player's screen in a hot-seat test build. Turning the phone during a sweep keeps it.
2. **Picking:** the first tap picks a single aircraft over a tank. A tap on your airfield sends
   selected aircraft home. A bomber attack on a building shows its ring.
3. **Budget:** `perf_air` (150 units with 16 aircraft) holds 60 fps. `work_p95_ms` stays at most
   5.6 and the draw calls within the forecast +2. The card shows the bake time and texture memory
   with page 2.
4. **1.2:** load two squads, fly over a cliff, unload on the far side; unload over water is
   refused and the squads stay aboard.

## Size estimate
| | Rows | Production lines | C++ | Generated models |
| --- | --- | --- | --- | --- |
| 1.1 | 30 (P230-P256, plus P239b, P241b and P245b; P238b only on its split trigger) | about 5,600 | about 175 | 12 (4 buildings x 2 factions + 2 aircraft x 2) |
| 1.2 | 8 (P262-P268 with P263b) | about 1,900 | 0 (one TARGETING edit if P262's check fails) | 4 |
| Total | 38 | about 7,500 | about 175-250 | 16 |

Tests come on top, about 1.5 times the production lines, as in Phases 3 and 4.

**Time at the current pace** (10-40 merged rows a day on lane-parallel days, 2026-10-26 to
2026-11-07):
- 1.1 takes about 2-3 weeks of calendar time:
  - about 1 week of build rows;
  - about 1 week of art rounds with Michael, as the damage sheets took;
  - about 1 week of balance tuning and the gate run (Phase 4 shows tuning, not code, is the long
    pole).
- 1.2 takes about 1-1.5 weeks.

**Release trade-off.**
- Building 1.1 before launch moves the first ad income about 2-3 weeks later, and Phase 5's
  tutorial must teach air from day one.
- Shipping it as an update keeps the launch date. It also gives the store listing a "new:
  aircraft" update and a reason for lapsed players to come back, which is the point at which
  retention data from the launch can steer the balance.

The recommendation is the update (ADR 0036 question 2 B).

## Risks
- **The atlas page** (ADR 0036 §15): P237 must land before any art row. If option (a) is not
  enough, Michael picks between (b) and (c).
- **Balance:** air could dominate small maps. Rockets with mask 7 and early anti-air are the
  counter, and the 30 % spend check in P255 watches it.
- **The reveal duration** could end the fog game. It is data (question 3).
- **AI think cost during a sweep:** `perf_ai` bounds.
- **Gate check 4 (every type used):** fighters and transports need the AI to build them in most
  matches. P250 and P267 put them in the build orders.
- **`TABS` 5** touches PlayerView, the AI and the drawer at once. P232 keeps the drawer at three
  tabs until P244 and P248.
- **The ground design's Command numbers:** reconcile before either ADR is accepted.
- **Scope creep:** anything in ADR 0036's "Out of scope" needs its own plan row and Michael's yes.
