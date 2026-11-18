# Plan: air, anti-air, transports, drone squads, engineering centre, space centre

Date: 2026-11-09, revised the same day after the docs lens (gameplay-dev: 7 must, 7 should, 4
nits). Base: `main` at b6bfe95. Decision:
`docs/adr/0036-air-layer-anti-air-map-reveal-and-upgrades.md` (**accepted, 2026-11-09**). Design:
the GDD section "Air, anti-air, engineering centre, space centre". ROADMAP: Phase 4b.

Note (2026-11-09, P230 done): ADR 0036 and ADR 0037 are accepted in one docs commit (P230 with
P270b). Michael answered 1 A, 2 A, 3 B, 4 A, 5 A. Everything is built after the Phase 4 gate and
before Phase 5, as ROADMAP Phase 4b, with the ground design. In this plan "1.1" now reads as **part
1** (P231-P256) and "1.2" as **part 2** (P262-P268); neither ships on its own. P233, P234, P235,
P252, P255, P256, P262 and P268 carry dated notes for answers 2 A and 3 B. The `touch-ui-rules`
draft is the last section of this plan; P244 and P265 (and ADR 0037's P272, P282, P294 and P299)
still wait for Michael's yes to it.

Note (2026-11-09, after fix 1): Michael said "ja til touch-teksten". The draft as revised in
1edbf12 is applied to `.claude/skills/touch-ui-rules/SKILL.md`; no row waits for it any more.

- **Status.** Accepted. **Building starts after the Phase 4 gate** (Michael, 2026-11-09), before
  Phase 5 (answer 2 A): part 1 (rows P230-P256), then part 2 (rows P262-P268) with the ground
  design's infantry carrier.
- **Row ids.** P230-P268, checked free against `git log --all` and the open lanes' plans:
  - the visual polish plan holds P200-P219 and ADRs 0034-0035;
  - ADR 0033 is seat symmetry;
  - P220-P229 stay unused as a buffer for the polish plan;
  - P257-P261 are kept for 1.1 splits and P269 for 1.2's.
- **Named exceptions.** 22 is P189b's. P232 takes **23** and P262 takes **24**. The ground plan's
  P286 takes **25** (2026-11-09, P230). (2026-11-13, P26bw) P301 takes **26** (ADR 0038 §8); the
  next free one is 27.
- **Ground design.** It meets this plan at ADR 0036 §7: Command types `LOAD = 5`, `UNLOAD = 6` and
  `REPAIR = 7`, the repair role and the carrier role. The lead reconciles the numbers before either
  ADR is accepted. Whichever release comes first builds `Carry.gd`.
  - Note (2026-11-09, P230): reconciled in ADR 0037 §2 and accepted. This plan's P262-P263b build
    `Carry.gd`; the order of the shared rows is in "Merge order of the shared rows" below, the
    same text as in the ground plan.

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
    `Buildings` (ground planes only), `PlayerView` (`reveal_state`, own `upgrades`, tabs).
  - New: `Air.gd` (ECONOMY), `Reveal.gd` (REMOVE), `Carry.gd` (1.2).
  - Defs: `UnitDef`, `WeaponDef`, `BuildingDef`, `FactionDef`, new `UpgradeDef`.
- **`native/sim_kernels`:**
  - `MOVE_CLASSES` 4, a literal in `bind/world_access.h:54`, `core/fixed_math.cpp:9` and
    `core/integrate.cpp:14`;
  - the X-list rows of `type_layer_bit` and `weapon_targets` in `world_access.h`;
  - the TARGETING layer test and the SEPARATION same-layer test;
  - `KNOWN_FORMATS` in `sanitizer/dump.h` (6, then 7).

  There are no new kernels.
- **`game/core`:** `MatchSnapshot.gd`'s field lists (`ammo`, `type_layer_bit`, `weapon_targets`,
  the tables of ADR 0036 §3, `TABS` 5); `NativeKernels.self_check` for the new sizes.
- **`data/`:**
  - units, weapons and factions: new `.tres` per faction, and masks on the rocket, rifle and
    Redoubt weapons;
  - `rules.tres`: `passenger_cap`, `load_reach_milli`, `unload_reach_tiles` (1.2);
  - `data/ai/` build orders, `OpponentDef` and difficulty values;
  - `data/dev/arena/` frozen `perf_air` defs.
- **`game/view`:** a new `AirLayer` (z 20) and air shadows (z 2); `IsoAtlas`/`RuntimeAtlas`
  page 2; fog fade on a sweep.
- **`game/input` and `game/ui`:**
  - raised picking;
  - the command-bar buttons Home (REPAIR), Board (LOAD, 1.2) and Unload (1.2) with their aims;
  - `PlayerController`'s DIED handling, which keeps boarded squads in their groups (1.2);
  - the Flight and Research tabs, the reveal button and the warning.

  The tap rule (a tap on an own unit or building selects it) is unchanged.
- **`game/ai`:** `AiProduction`, `AiIntel`, `AiArmy` and `AiStrikes` (counter choices made
  layer-aware: `AiProduction.gd:302` and `AiArmy.gd:701` read `type_vs_armour` with no layer
  today), and the build-order and difficulty defs.
- **`tools/artgen/`:** 16 models (8 buildings, 4 aircraft and 2 transports, 2 drone squads, across
  both factions).
- **`docs/`:** HOW_TO_PLAY rows in each player-facing row, the GDD, the ROADMAP (a section per
  update) and dated ADR notes (P230). Note (2026-11-09, P230): the ROADMAP has one section for
  both designs, Phase 4b.

## Command and data changes (summary of ADR 0036)
- **Commands.** New: LOAD 5, UNLOAD 6 and REPAIR 7, all shared with the ground design; LOAD and
  UNLOAD in 1.2, REPAIR in 1.1. Everything else uses QUEUE, PLACE, MOVE, ATTACK_MOVE, ATTACK, STOP
  and SUPERWEAPON.
- **State.** `STATE_FORMAT` 6 in P232: `ammo`, `reveal_site`, `reveal`, `upgrades`, the type,
  weapon and upgrade tables, `TABS` 5 and the AIR plane. `STATE_FORMAT` 7 in P262: passengers and
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
    sweep, across a pause and a resume.
  - (2026-11-09, answer 3 B) The sweep ends on the death or sale of the space centre that fired it,
    and on nothing else. It pauses while that building is blacked out or its owner is on low power,
    and resumes by itself. A second SUPERWEAPON on a REVEAL building is dropped while a sweep
    stands; a second space centre fires only after the first is gone.
  - `explored` is all 1 afterwards.
  - The dirty list overflows to `dirty_full` and the view redraws.
  - `World.prepare()` after a snapshot restores the stamp.
  - The TARGETING kernel sees revealed enemies.
  - `PlayerView.seen_rows` grows during the sweep, and `reveal_state` (0, 1, 2) reads the same for
    every player.
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
  - A tap on an own airfield or transport still selects it; the Home, Board and Unload buttons
    and their aims.
  - The Unload aim.
  - Layouts at ADR 0015's six sizes.
- **Mutation testing** (sim rows only, about 10 chosen mutants each): P233, P238, P240, P241,
  P241b, P246, P262, P263.

## Rows
Owners: GD gameplay-dev, AI ai-dev, ART art-director, TUX touch-ux-dev, QA qa-engineer, LEAD the
lead (docs, gate runs, phone checks). (2026-11-15, P26by) REL release-engineer. Size = production
lines (tests and fixtures do not count).
Every player-facing row adds its HOW_TO_PLAY rows.

### Part 1, was 1.1 (order: satellite -> anti-air -> airfield and aircraft -> engineering centre)
| Row | Owner | What | Size | Depends |
| --- | --- | --- | --- | --- |
| P230 | LEAD | **Done 2026-11-09** (with P270b, one commit on `claude/p230-phase4b-acceptance`): both ADRs accepted, ADR 0036 §11 rewritten for answer 3 B, the dated notes, the GDD sections, ROADMAP Phase 4b, the merge-order section and the skill draft below; the skill itself waits for Michael's yes. Acceptance docs: Michael's answers and names in ADR 0036 and the GDD; dated notes in ADRs 0007, 0008, 0009, 0010, 0013, 0016, 0017, 0018, 0023, 0027, 0030 and 0031; a ROADMAP section per update (or Phase 4b if version 1); the GDD "Not in version 1" line per question 2. The `touch-ui-rules` amendment (ADR 0036 §12: the Home, Board and Unload buttons and their aims) **needs Michael's explicit yes**, asked with the acceptance; the lead edits the skill only after it | docs | Michael's answers; the Phase 4 gate |
| P231 | GD | Defs: `MoveClass` Air, `low_flying`, `ammo`, `rearm_ticks`, `WeaponDef.targets`, `pads` and `pad_offsets`, the repair role, `strike_kind` 3, `UpgradeDef`, `FactionDef.upgrades`, the Tab enum in exports; data tests (ranges, AIR-only fields, pad spacing at least the largest FLIGHT `formation_spacing`, `repair_reach_milli` at least 500, upgrade modifiers at most 400 %). `TerrainDef.cost` keeps 3 entries. Hash-neutral: World copies nothing yet | 150 | P230 |
| P232 | GD + QA | World v6: the columns and tables of ADR 0036 §3 (1.1 part); `type_layer_bit`; the AIR plane with `World.GROUND_CLASSES` at the four sites of ADR 0036 §4 (`WorldLoad.gd:141` and the loader's AIR fill, `World.set_terrain`, `Buildings._write_cost`) plus the check of the other `MoveClass.size()` uses; `TABS` 5 (PlayerView slices, Production indexing; the drawer still lists three tabs); `MOVE_CLASSES` 4 in `world_access.h:54`, `fixed_math.cpp:9` and `integrate.cpp:14`; the X-list rows of `type_layer_bit` (TARGETING and SEPARATION flags) and `weapon_targets` (TARGETING) declared once in `world_access.h`; `type_layer_bit` and `weapon_targets` in `PlayerView` and `MatchSnapshot`'s field lists; WorldLoad, WorldHash, `STATE_FORMAT` 6, one re-pin (exception 23). QA: the sanitizer cases and `KNOWN_FORMATS` in `native/sim_kernels/sanitizer/dump.h` gain 6, and `NativeKernels.self_check` is re-checked for the new sizes and classes. Split trigger (over ~400): P232b takes `TABS` 5 with PlayerView and Production indexing | 380 (C++ ~20) | P231; P271 (2026-11-12, P26bq) |
| P232c | GD | (2026-11-12, P26br) Pure move: the bodies of `add_unit`, `_push_unit_event` and `write_unit_event` from `World.gd` (981 of gdlint's 1000 after P232) into `game/sim/WorldRows.gd`, about 55 lines net. `World` keeps one-line delegates under the names the code and the ADRs call, and P262's `World.insert_row` is such a delegate to `WorldRows`. No rule changes, hash-neutral, no re-pin | 0 (move) | P232 |
| P233 | GD | Reveal (as amended 2026-11-09, P230, answer 3 B): `FogGrid.reveal`, `Reveal.run` in REMOVE (per player with `reveal_site` set: `index_of` the site, 0 when it is gone, else `reveal` 1 when it is online and the player is not low on power, 2 when paused; no row pass), the `prepare()` stamp on `reveal == 1` (ADR 0036 §11), SUPERWEAPON on a REVEAL building dropped while `reveal_site` is set or while its owner is on low power (fix 1, 2026-11-09), strike kind 3 in `Strike.apply_superweapon` with the REVEAL branch before the pending-rupture test (`Strike.gd:112`) and a test that fires a sweep while a rupture is pending, the STRIKE record of kind 3 (`[5, id, 0, 0, 3, owner, 0, 0]`), `PlayerView.reveal_state`; pause and resume cases (blackout, low power), a rebuild test across a pause; a FOG lockstep case | 250 | P232 |
| P234 | GD | Space centre data, both factions (`.tres`, rosters, requires Radar, one charge of 2,700 and no sweep timer: `strike_ticks` 0, answer 3 B, dated 2026-11-09); name width test; HOW_TO_PLAY Superweapon rows (Teach) | 80 | P233, P230 |
| P235 | TUX | Reveal HUD: the strike button's no-aim variant (tap, check mark), the warning badge and line, the fog fade (`reveal_fade_ms`); six layout sizes. (2026-11-09, answer 3 B) The enemy's indicator badge from `reveal_state`: lit while on, dimmed with a pause mark while paused, gone at 0, placed in ADR 0025's corners; the owner's strike button shows on or paused; the fade runs both ways on a pause and a resume. (Fix 1, 2026-11-09) On low power the satellite's strike button dims and shows the reason (the low-power glyph), because the sim refuses the SUPERWEAPON then | 300 | P234 |
| P236 | ART | Space centre models, both factions (whole + damage stages, a lift part as the anim) | art | P237 |
| P237 | ART | Atlas page probe and split: page 2 for unsorted layers (AirLayer, air shadows, DecalLayer, building shadows); measures rows, bake ms and texture memory; options a/b/c of ADR 0036 §15 to the lead; page pins. Coordinate with polish rows P202-P204 | 250 | P230 (may start at once) |
| P238 | GD | Target layers: TARGETING twin and kernel (reading `weapon_targets` and `type_layer_bit` as P232 declared them; acquisition and ATTACK lock), `_apply_attack`, `Combat.fire` guard, rupture skips air; masks on rocket (7), rifle (5) and Redoubt (5) weapons; lockstep cases. Split trigger: the lockstep test as P238b if over ~1,000 changed lines | 200 (C++ ~120) | P232 |
| P239 | GD | Anti-air data, both factions (building, weapon mask 6, requires Barracks); HOW_TO_PLAY Combat rows. (2026-11-13, P26bv) Data only: the rosters, the item cards and the HOW_TO_PLAY Combat rows move to P239b | 80 | P238, P230 |
| P308 | ART | (2026-11-15, P26by; added by the lead) Split `game/view/art_gallery.gd` (1000 lines, the gdlint limit, after P244) before the next art rows: the Icons and Hud pages and the shared row helpers move to the static `art_gallery_icons.gd`, which the gallery calls; the gallery tests repointed and STYLE.md's Gallery text names the new file. The headless node tree is unchanged | 0 (move) | P244 |
| P239b | ART + GD (2026-11-13, P26bv) | Anti-air models, both factions (turret head, 16 directions). (2026-11-13, P26bv) Also the roster entries and item cards, the HOW_TO_PLAY Combat rows, `test_defs_anti_air`'s flipped "not in rosters" assertion and the removed skips. (2026-11-13, P26bw) It may land before or beside the trim rows P305 and P306; if it lands first, P305's regeneration covers its sheets. (2026-11-15, P26by) As built, with its new smoke hashes: the plan's P26by note below | art | P237; P308 (2026-11-15, P26by) |
| P240 | GD | Air movement: SEPARATION same-layer test (twin and kernel, reading P232's `type_layer_bit`), INTEGRATE and FLOW lockstep cases with aircraft, `ProductionSpawn` spawn over a pad, `Buildings` ground planes only (checked) | 200 (C++ ~40) | P232 |
| P241 | GD | Airfield rules: the FLIGHT cap at QUEUE, spawn over a pad, home and re-home, `air_rows`, ammo in `Combat.fire`, `Air.run` return and reload. Split trigger (over ~400): P241c takes `Air.run`'s return and reload | 350 | P238, P240; P232c (2026-11-12, P26br) |
| P241b | GD | REPAIR Command (7) for the airfield role, repair on the pad and its price, the shared repair-role contract test | 180 | P241 |
| P242 | GD | Airfield, fighter and bomber data, both factions (`.tres`, weapons, rosters); HOW_TO_PLAY Units, Orders and Buildings rows (Teach: go home, reload). (2026-11-13, P26bw) Data only, the P239 pattern: the roster entries, the item cards, the HOW_TO_PLAY rows and the rewrite of the rupture row (the P26bt note) move to P245 (fighter, bomber) and P245b (airfield). The bomber's weapon `range` and `acquire_range` are 3.0 tiles, not 2.5 (the lead's fix; the GDD's note of this date) | 120 | P241b, P230 |
| P243 | GD | View: `AirLayer` z 20, shadows z 2, `fly_px`, bob, death fall, enemy flyers only where seen, page 2; draw-call guard +2. Split trigger (over ~400): P243b takes the bob and the death fall | 350 | P237, P242 |
| P307 | TUX | (2026-11-14, P26bx; added by the lead) Split `UnitLayer.gd` (1000 lines, the gdlint limit) before P244: the picking side moves to the static `UnitPick.gd`, `UnitLayer` delegates | 110 | P243 |
| P244 | TUX | Touch: raised picking (a radius of at least 24 dp round the lifted centre), aircraft over ground units in the pick order with the box and double-tap fallback for a unit beneath, an unhittable enemy tap selects (fix 1, 2026-11-09: it does nothing, a short shake, the selection kept; a mixed selection attacks with the rows that can hit; the flyer wins only within one pick rank), the "Home" button (REPAIR) in the command bar, the bomber's attack ring, the Flight tab in the drawer; six sizes. Split trigger (over ~400): P244b takes the Flight tab. (2026-11-14, P26bx) "The bomber's attack ring" is the bomber's own selection ring (ADR 0036 §15); the rest of the as-built rules are in the plan's P26bx note below | 350 | P243 (2026-11-09: the skill text is accepted and applied, Michael's yes); P307 (2026-11-14, P26bx) |
| P245 | ART | Aircraft models: fighter and bomber, both factions (16 directions, body and shadow). (2026-11-13, P26bw) Also, from P242: the fighters' and bombers' roster entries and item cards, the HOW_TO_PLAY Units and Orders rows (Teach: go home, reload), and the rewrite of HOW_TO_PLAY's rupture row (it hits ground rows only). (2026-11-15, P26bz) It merges right after P245b, in the same wave, so the Flight tab is never empty on `main`; its aircraft cost page 2 about 4x their estimate (the plan's P26bz note) | art | P237; P243 (2026-11-12, P26br: its `page_of` re-key first); P242 (2026-11-13, P26bw) |
| P245b | ART | Airfield models, both factions (pads, damage stages). (2026-11-13, P26bw) Also, from P242: the airfields' roster entries and item cards and the HOW_TO_PLAY Buildings rows. It may land before or beside the trim rows P305 and P306. (2026-11-15, P26bz) As built, with its new smoke hashes: the plan's P26bz note below | art | P237; P242 (2026-11-13, P26bw) |
| P246 | GD | Upgrades sim: research items from `UpgradeDef`, research completion in `Production`, `mod_*` tables, `Combat.damage` with its readers and the rewritten range note in `Combat.gd`'s header (`:76-79`), `mod_ammo` in `Air.run`, own `upgrades` in PlayerView. Split trigger (over ~400): P246b takes the readers (`Combat`, `Air.run`) | 350 | P241; P246a (2026-11-13, P26bv) |
| P246a | GD | (2026-11-13, P26bv; added by the lead) `World.gd` split: function bodies move to the `World*` helpers behind one-line delegates; no behaviour, list, hash or name change | 0 (move) | - |
| P247 | GD | Engineering centre data and four UpgradeDefs (per question 5); HOW_TO_PLAY Build menu rows. (2026-11-13, P26bw) Data only, the P239 pattern: the roster entries, the item cards, `FactionDef.upgrades` and the HOW_TO_PLAY Build menu rows move to P249. Starting values (the lead, from P247's review): the GDD's note of this date | 100 | P246, P230; P242 (2026-11-13, P26bw) |
| P248 | TUX | Research tab: cards, the researched mark, a locked card's sash (ADR 0032); six sizes. (2026-11-13, P26bw) The research card must fit the upgrade names: "Heavy Bombs" measures 86.8-90.3 dp and "Focus Bombs" 85.3-88.6 dp at `web_phone`, `web_phone_small` and `android_6in`, over the sidebar caption's 83.4-83.8 dp. P248 owns their width test and gives the card a wider caption or two lines. (2026-11-15, P26bz; Michael) Option A: the close chevron leaves the tabs row; upright it sits at the end of the handle row, sideways it is a handle on the panel's map-side edge. Where even the open tab's name does not fit beside the others' icons, every tab shows its icon only (known case: the 320 dp phone upright with Structures or Research open). P248 itself carries the ADR 0025 §5 note and the skill text | 200 | P247 |
| P249 | ART | Engineering centre models, both factions. (2026-11-13, P26bw) Also, from P247: the roster entries, the item cards, `FactionDef.upgrades` and the HOW_TO_PLAY Build menu rows. `FactionDef.upgrades` is filled only after P248 (the Research tab) has merged, or research tiles would show without their cards | art | P237; P247, P248, P305, P306 (2026-11-13, P26bw) |
| P250 | AI | Production and Intel: build-order tiers (airfield, anti-air per seen aircraft, engineering centre, space centre on Normal and Hard), the air mix, research choice; counts of seen air and anti-air; layer-aware counter choices (`AiProduction.gd:302`, `AiArmy.gd:701`: `weapon_targets` against `type_layer_bit`). Split trigger (over ~400): P250b takes Intel's counts | 350 | P234, P239, P242, P247; P239b (2026-11-13, P26bv); P245, P245b, P249 (2026-11-13, P26bw): the rosters come with the art rows |
| P251 | AI | Army: bomber raids (`raid_size`, the target by value and anti-air), fighters guard and escort, REPAIR below `air_retreat_percent`. Split trigger (over ~400): P251b takes the fighters | 350 | P250; P301, P302, P303 (2026-11-13, P26bw): ADR 0038's AI thread first |
| P252 | AI | Strikes (as amended 2026-11-09, P230, answers 3 B and 4 A): Normal and Hard fire the sweep as soon as it is charged (no `reveal_blind_ticks`); while an enemy's `reveal_state` is 1, move the staging point by one step and make a seen or ghost enemy space centre the first target of bomber raids and of the AI's own blackout; Easy builds none of the tech | 200 | P234, P250 |
| P253 | GD | `perf_air`: frozen defs in `data/dev/arena/`, a scenario with 16 aircraft among 150 units, golden and counted bounds, the perf card; the lead reads ADR 0013 §1 on its `PERF` line. (2026-11-15, P26by) P253b fixed the phone card's heavy window; P309 copies the `PERF air` lines into the CI job summary | 200 | P242, P246 |
| P253b | QA | (2026-11-15, P26by; added by the lead) The phone card gates the air arena: `drawn_rigs` also counts the `AirLayer` flyers in view (`AirLayer.count_in`, as `UnitLayer.count_in`), and the air arena's heavy window uses `PerfGateDef.air_heavy_rigs` 120 (in `data/dev/perf_gate.tres`), because 135 held for only 124 ticks of the run. A headless test plays the real arena 900 ticks (4 frames a tick) and asserts `heavy_frames_min` heavy frames; with the ground rigs alone (the card before P253b) the window holds none. The other arenas keep `heavy_rigs`, and no golden moves. (2026-11-15, P26bz) It works: Michael's Perf air card on `main` 4456e53b has 914 heavy frames (0 before) and passes the gate (the plan's P26bz note) | 30 | P253 |
| P309 | REL | (2026-11-15, P26by; added by the lead) `ci.yml` copies the two `PERF air` lines into the job summary under their own heading and a log group, following P96 (the `PERF bases` block), with the `test_ci_workflow.gd` case that pins it | 10 (CI config) | P253 |
| P310 | TUX | (2026-11-18; added by the lead from Michael's phone test) A building's selection chip shows no name (its card and health only, so Mend and Sell stay on the screen upright), and a tap that selects an own producer no longer opens the build drawer (an open drawer still switches to the tab); ADR 0025 §5 and §9 notes, HOW_TO_PLAY rows | 60 | P122, P120 |
| P254 | QA | Harness: per-type counts for the new types, `reveals`, `research` and air kills by layer in the report; ADR 0031 check 4 reads the rosters (16 types); the summary | 200 | P242, P247; P245, P245b, P249 (2026-11-13, P26bw) |
| P255 | LEAD | (2026-11-09, answer 2 A: this is part 1's interim balance run, not a gate; with ADR 0037's P284 it counts 18 types; the Phase 4b gate is P268 with P297) Balance tuning (data rows, exception 20 style) and the 1.1 gate run: Normal against the mirror 40-60 %, no match over 15 minutes, every one of the 16 types used, the median length 8-10 minutes, aircraft at most 30 % of median army spend. (2026-11-13, P26bw) Open balance item for P255 and P267: against harvester armour the drone squad's gun does about 1 damage a second, so ADR 0036 §14's harvester raid cannot work with today's numbers; no number is changed yet | data | P250-P254; P245, P245b (2026-11-13, P26bw) |
| P256 | LEAD | Phone check with Michael (below) and the 1.1 wrap-up docs (GDD, ROADMAP ticks); (2026-11-09) part 1's interim phone check, ticking the Phase 4b boxes it meets | docs | P255, all art rows; P253b (2026-11-15, P26by): phone check 3 reads its card |

### Part 2, was update 1.2
| Row | Owner | What | Size | Depends |
| --- | --- | --- | --- | --- |
| P262 | GD + QA | World v7: the passenger table, `carry_mode`, carrier type tables, `World.insert_row` (id order, `rows_version` bump, refusal at `max_rows`), `STATE_FORMAT` 7, one re-pin (exception 24); `KNOWN_FORMATS` gains 7 and the sanitizer cases with it; the check that TARGETING leaves a MOVE row's `order_target` alone (else ADR 0036 §8's BOARD fallback, a TARGETING edit). Split trigger (over ~400): P262b takes `insert_row` | 350 | P232 (2026-11-09: "1.1 shipped" no longer applies; the ground design is reconciled; re-pins in the order 23, 24, 25); P232c (2026-11-12, P26br) |
| P263 | GD | `Carry.gd`: LOAD (5), boarding in REMOVE (`hp` 0 with `build_left` = `Carry.BOARDED`, DIED flag 2 at index 6, `count_losses` skips it), passengers in `unit_cap` | 300 | P262 |
| P263b | GD | UNLOAD (6), unloading in ECONOMY (ring search, `insert_row` refusal keeps the squad aboard, `UNLOADED` event), the carrier's death | 250 | P263 |
| P264 | GD | Transport and drone squad data, both factions (drone squads `low_flying`, INFANTRY tab, requires the airfield); HOW_TO_PLAY rows (Teach: load and unload). (2026-11-13, P26bw) Data only, the P239 pattern: the roster entries, the item cards and the HOW_TO_PLAY rows (Teach: load and unload) move to P266 | 120 | P263b, P230; P242 (2026-11-13, P26bw) |
| P265 | TUX | The "Board" button and its aim (tap an own transport = LOAD), the "Unload" button and its aim (chevron, check mark, X), passenger pips on the chip; `PlayerController` skips DIED flag 2 for groups 1-3 and drops it only from the live selection, with a test that a group refills after the unload; six sizes. Split trigger (over ~400): P265b takes the controller change. (2026-11-14, P26bx) P265 and P265b are held for P244 and an integration change (the plan's P26bx note below). (2026-11-15, P26by) They landed after P244 as the integration branches (the plan's P26by note below) | 350 | P264 (2026-11-09: the skill text is accepted and applied, Michael's yes); P244 (2026-11-14, P26bx) |
| P266 | ART | Transport models (16 directions) and drone squads (8 directions), both factions. (2026-11-13, P26bw) Also, from P264: the transports' and drone squads' roster entries and item cards and the HOW_TO_PLAY rows (Teach: load and unload) | art | P237; P264, P243 (2026-11-13, P26bw): the data first, and the transports' hulls go on page 2 by P243's `page_of`; (2026-11-15, P26bz) page 2's per-row allocation first (the plan's P26bz note) |
| P267 | AI | Drops (Normal and Hard: load `drop_squads`, unload beside a seen or ghost refinery, away from seen anti-air), drone squads harass across cliffs | 300 | P264; P266 (2026-11-13, P26bw) |
| P268 | LEAD | 1.2 harness types (20), gate run, phone check, docs. (2026-11-09) It is the **Phase 4b gate** with ADR 0037's P297: harness types 26, the ADR 0031 gate run on held-out seeds, Michael's phone check, the ROADMAP gate box | docs | P265-P267; ADR 0037's P296, P299 and P300 (P297 joins this run) |

### Levers (2026-11-13, P26bw): the AI thread and the atlas trim
Michael chose both levers of the architect's memo on 2026-11-13: the AI thinks on its own thread
and its Commands land at T+1 (ADR 0038, accepted), and the atlas trims the empty margins of the
directional frames (option c1; ADR 0036 §15's P26bw note). Row ids P301-P306 and P304b were checked
free against the plans, `git log --all` and the remote branches. Exception 26 is P301's.

| Row | Owner | What | Size | Depends |
| --- | --- | --- | --- | --- |
| P301 | GD + QA | ADR 0038 §1 in `SYNC`: one pure lagged tick in `AiDriver` (collect the batch made from tick T-1 after the human's Commands, build the due views before the step, think inline, keep the batch for T+1), which `TickJob.run` in `SYNC`, `tests/smoke/smoke_run.gd`, `tests/perf/support/ai_perf_run.gd` and `test_match_runner_ai.gd`'s headless loop call before `MatchLoop.step`; a batch collected after the end is dropped unsent; `MatchRunner.start()` drops a pending batch, with the restart test (ADR 0038 §1); `think_all` stays the lag-0 composition for the `tests/ai` rigs; a pure batch holder in `game/core`. ADR 0038 §6's bound (`dropped_commands > STALE_DROP_PERCENT * C / 100`, one constant in `smoke_run.gd`) in the smoke and the summary's gate check; fixed-seed suites pin their exact drops; the stale drops measured on the smoke seeds and P188's matches, Hard included, go in the PR (above half the bound: stop and report). The stamp comments (`row_ready_tick`, `AiStrikes.gd:128-130`). One re-pin, **exception 26**, closed to ADR 0038 §8's list; `golden_hex`, `bases_golden_hex` and `TICK_0_SEED_1` are asserted unchanged. A `tests/core` case for the order of a human and an AI Command in one step. Then the lead's balance run on `main` (ADR 0038 §8) | 160 | ADR 0038 (this docs PR) |
| P302 | GD | ADR 0038 §4: `PlayerView` holds no World array. Every array is a `duplicate()` made in `PlayerView.of`, including the placement input through a copying builder beside `PlacementInput.of_world` (whose aliases stay for `Production`). The alias test: a write to every source array after `of()` changes no answer of the view. Hash-neutral, no pin moves. `PlayerView` stays within gdlint's 20 public methods (the P26bt note) | 110 | P301 |
| P303 | GD + QA (TUX reviews the card lines) | ADR 0038 §2, §3 and §7: the AI thread in `MatchRunner` (`WORKER` only: `ai_work`/`ai_done`, joined at `stop()` and `PREDELETE` after the sim worker, `wait_idle()` waits for the job, then the batch, and whoever takes `ai_done` first marks the batch done; the thinks inline on a failed start); `MatchSnapshot.ai_wait_usec`; the card's AI line gains `ai_wait_p95_ms`, `ai_wait_max_ms` and `ai_waits` (report-only; the pin test re-made). Tests: `SYNC` = `WORKER` on one seed for at least 900 ticks (equal Command logs and checkpoint hashes), a forced-wait case with a slow test controller, no `WARNING` at stop; a thread test, so 3 runs in a row before the push. Phone: Michael's card after the merge reads `ai_wait`, `work_p95_ms` (main) and `sim_p95_ms`; contention (ADR 0038 §2) shows there | 180 | P301, P302 |
| P304 | QA (TUX reviews the route lines) | ADR 0038 §7: `perf_ai_4b`, the base arena's layout on frozen copies of the Phase 4b unit defs in `data/dev/arena/` (aircraft, airfields, anti-air, the engineering centre and the space centre, transports and drone squads; `perf_air`'s frozen unit defs where both need a type), each side's rows at tick 0; its AI defs are copies of `perf_ai`'s frozen AI defs (P189b's early scout and wave) in their own folder `data/dev/arena/ai_4b/`, with the field-name parity test against the shipped defs (`data/dev/arena/ai/` and `test_frozen_ai_defs.gd` stay as they are); the Perf AI route (`DevRoutes.gd`, `perf_arena.gd`, `tests/ui/test_perf_ai.gd`) and the card's arena choice; a printed hash, no golden pair. From its merge the per-wave Perf AI card runs on `perf_ai_4b`. It need not block P251, a deviation from the memo (ADR 0038 §8): until it merges, P251's cost shows only in `ai_wait`. (2026-11-15, P26by) As built, with the card's new hash and the triggers: the plan's P26by note below. (2026-11-15, P26bz) The 4b baseline and Michael's triggers: the plan's P26bz note and ADR 0038 §7 | 60 (+.tres) | P303, P242, P247, P264, P253 |
| P304b | QA | `perf_ai_4b` gains the ground carriers and the minelayers (frozen copies of P290's defs) | 20 (+.tres) | P304, P290 |
| P305 | ART | Atlas trim, part 1 (ADR 0036 §15's P26bw note): `tools/artgen/` writes, for every directional frame (vehicles, infantry, turret heads), its tight drawn box (the alpha bounds plus 1 px) into the sheet's `IsoSheetDef`, beside the untrimmed cell. The frames and the atlas are unchanged, so no page pin moves. All sheets are regenerated once; the art lanes in flight regenerate once after it merges | 100 (+ sheets) | - (may start now) |
| P306 | ART | Atlas trim, part 2: `IsoAtlas`/`RuntimeAtlas` pack only each directional frame's box from P305 and keep a per-frame offset; every site that places a directional frame by its part's `origin` or writes its region alone uses the frame's offset: `WorldSort.dress` (:174) and `show_base`, `RigLife.Pose.offsets` (`SquadPoses`), the turret heads with `BuildingLayer`'s sweep and kick, `GhostLayer`'s head, and the gallery; `texels_per_px` keeps the untrimmed `frame_size` (`WorldSort.gd:181`, `RigLife.gd:166`). Buildings, their damage cuts and page 2 stay as they are. The headless "no jump" test: for every directional frame of every sheet, the drawn box on screen equals the box the untrimmed frame showed, on a turn, a pose change (hull, walk, idle) and a sweep step. `TODAY_*` in `test_iso_atlas_budget.gd` re-pinned (about -686 / -649 / -715 rows on the cross page and the Derrick and Lumen mirrors); `TODAY2_*` unchanged. Split trigger (over ~400): P306b takes `SquadPoses` and the gallery | 220 | P305 |

**The order of the art rows (the memo, 2026-11-13).**
1. P239b now. It fits as it is (page 1 at 3,040 cross, 2,902 and 3,008 on the mirrors).
2. The trim rows P305 and P306. They run beside P239b and P245b and merge before P249 starts.
3. P245b. It fits even without the trim.
4. P243, then P245 and P266 (page 2).
5. P249, then P279, P280, P291 and P292 (the ground plan).

If P245b or P249 costs more than the space centre did (334 rows a pair), the 3,840 allowance
(ADR 0036 §15's P237 note) is used before any other lever. (2026-11-15, P26by) P239b measured:
page 1 went from 2,167, 2,127 and 2,068 rows (cross, Derrick and Lumen mirrors, after P306) to
2,252, 2,172 and 2,167 (STYLE.md v1.37), the base for P245b and P249. (2026-11-15, P26bz) P245b
moved page 1 to 2,314, 2,258 and 2,238; P245 left it as it was. Page 2: ADR 0036 §15's P26bz note.

### Lanes and order
- **S (GD):** P231 -> P232, then P233 and P238 and P240 in parallel (separate files; P238 and
  P240 touch different kernels). Then P241 -> P241b -> P246. (2026-11-12, P26br) P232c after
  P232 and before P241, alone on `World.gd` while it is open.
- **D (GD data):** P234 after P233, P239 after P238, P242 after P241b, P247 after P246. P247 and
  P264 after P242 (2026-11-13, P26bw).
- **V (GD view):** P243 after P237 and P242.
- **T (TUX):** P235 -> P244 -> P248. (2026-11-14, P26bx) P307 after P243 and before P244.
- **A (ART):** P237 first, then P236, P239b, P245, P245b and P249 in any order. (2026-11-12, P26br)
  P245 after P243; P202 (visual polish) before the next of P239b, P245b and P249. (2026-11-15,
  P26by) P308 after P244 and before P239b.
- **I (AI):** P250 -> P251 and P252.
- **Q:** P253 and P254, then the lead's P255 and P256. (2026-11-15, P26by) P253b (QA) and P309
  (REL) after P253, in parallel.
- **L (2026-11-13, P26bw; ADR 0038):** P301 -> P302 -> P303, all before P251. They touch
  `game/core`, `AiDriver` and `PlayerView`, not the managers, so P250 and P252 do not wait for
  them. P304 once its data rows have merged, P304b after P290.
- **A, the trim (2026-11-13, P26bw):** P305 -> P306, beside P239b and P245b, both before P249. The
  order of all art rows is in "Levers" above.
- **Critical path for 1.1** (to the last row before the gate; 2026-11-12, P26bq: P271 merges
  before P232): P230 -> P231 -> P232 -> P238 ->
  P241, then two branches of equal length, P241b -> P242 and P246 -> P247, then P250 -> P251 ->
  P255. That is 10 rows on the path plus the tuning rounds.
  - P254 runs beside P250 and P251 (it needs P242 and P247; from 2026-11-13, P26bw, also P245,
    P245b and P249).
  - P250 also waits for P234 and P239, which are off the path.
  - (2026-11-13, P26bw) P250 now also waits for P245, P245b and P249 (the rosters). P249 waits for
    P248 and P305 -> P306, and P251 for P301 -> P303. The lead re-reads the path when wave 8
    merges.

## Phone checks (Michael's phone, the lead's PerfCard)
1. **Satellite:** the sweep fades out and back in, sideways and upright, and the warning shows on
   the player's screen when the computer fires its own. Turning the phone during a sweep keeps
   it. (2026-11-09, answer 3 B) The indicator stays lit while the computer's sweep is on; a Dusk
   Array blackout on its space centre dims it to paused and the fog returns, and the sweep comes
   back when the blackout ends; destroying the space centre clears the indicator.
2. **Picking:** the first tap picks a single aircraft over a tank. A tank beneath a hovering
   aircraft is reached by a box or a double-tap. "Home" sends selected aircraft home. A tap on
   your airfield still selects it. A bomber attack on a building shows its ring. (2026-11-14, P26bx)
   The ring is the bomber's own selection ring, under its shadow (the plan's P26bx note below).
3. **Budget:** `perf_air` (150 units with 16 aircraft) holds 60 fps. `work_p95_ms` stays at most
   5.6 and the draw calls within the forecast +2. The card shows the bake time and texture memory
   with page 2.
4. **1.2:** load two squads, fly over a cliff, unload on the far side; unload over water is
   refused and the squads stay aboard.

## Size estimate
| | Rows | Production lines | C++ | Generated models |
| --- | --- | --- | --- | --- |
| 1.1 | 31 (P230-P256, plus P239b, P241b and P245b, and P232c (2026-11-12, P26br); the other b and c parts only on their split triggers) | about 5,190 (the sum of the rows) | about 180 | 12 (4 buildings x 2 factions + 2 aircraft x 2) |
| 1.2 | 8 (P262-P268 with P263b) | about 1,670 (the sum of the rows) | 0 (one TARGETING edit if P262's check fails) | 4 |
| Total | 39 | about 6,900 | about 180-250 | 16 |

Split triggers sit on every row of 350 or more: P232, P241, P243, P244, P246, P250, P251, P262 and
P265. A split adds a row, not lines.

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

The recommendation was the update (ADR 0036 question 2 B). Michael chose 2 A on 2026-11-09:
everything before launch, as ROADMAP Phase 4b, with the ground design.

## Risks
- **The atlas page** (ADR 0036 §15): P237 must land before any art row. If option (a) is not
  enough, Michael picks between (b) and (c).
- **Balance:** air could dominate small maps. Rockets with mask 7 and early anti-air are the
  counter, and the 30 % spend check in P255 watches it.
- **The reveal duration** could end the fog game. Michael chose 3 B (until the space centre is
  destroyed); the counters are the price, the charge, the warning, the indicator and the pause
  (ADR 0036 §11). The balance run watches it.
- **AI think cost during a sweep:** `perf_ai` bounds.
- **Gate check 4 (every type used):** fighters and transports need the AI to build them in most
  matches. P250 and P267 put them in the build orders.
- **`TABS` 5** touches PlayerView, the AI and the drawer at once. P232 keeps the drawer at three
  tabs until P244 and P248.
- **The ground design's Command numbers:** reconcile before either ADR is accepted. Done
  2026-11-09 (ADR 0037 §2).
- **Scope creep:** anything in ADR 0036's "Out of scope" needs its own plan row and Michael's yes.

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

## touch-ui-rules text for Michael's yes (P230): applied to the skill on 2026-11-09 (Michael's yes)
Status (2026-11-09): Michael said "ja til touch-teksten". Parts 1-5 below, as revised in fix 1
(1edbf12), are applied to `.claude/skills/touch-ui-rules/SKILL.md` at the places each part names.
One change on applying: Part 1's Sell row names the window by its section, "Orders and their
aims", in place of "Part 4's window", which means nothing inside the skill. The text below stays
as the record.

Draft, 2026-11-09. `.claude/skills/touch-ui-rules/SKILL.md` is not edited until Michael says yes.
Then the lead pastes the five parts below in one docs commit, unchanged. P244, P265 (ADR 0036) and
P272, P282, P294, P299 (ADR 0037) wait for that commit. The buttons are command-bar orders, so
each is `CommandBar.ORDER_DP` (at least 56 x 64 dp), above the 48 dp floor.

Fix 1 (2026-11-09, after touch-ux-dev's docs lens: 5 must, 4 should, 2 nits; the lead's
decisions): the command bar shows Deselect and Stop always and scrolls the rest (Part 3); the aims
place their check mark and X by `GhostControls`' column rule, with each aim's anchor rect (Part
4); Sell sends only between `sell_arm_min_ms` and `sell_confirm_ms` and keeps a fixed width (Part
4); "always selects" holds outside an open aim (Part 4); an enemy that no selected unit can hit is
not attacked and not selected (Parts 1 and 5); the flyer wins a pick only within one rank (Part
5); Deselect keeps its place during an order aim too (Part 1).

**Part 1. Gesture map: add these rows after "Tap Stop", and replace two rows.**

```markdown
| Tap Home (aircraft selected) | Each selected aircraft flies to its own airfield's pad (`REPAIR`), reloads and is repaired there; no aim |
| Tap Repair (damaged ground units selected) | They drive to the nearest own repair building that serves them (`REPAIR`) and are repaired there; no aim |
| Tap Board, an own carrier, the check mark | The selected squads board it (`LOAD`); the carrier comes to them |
| Tap Unload, the ground, the check mark | The selected loaded carriers go there and unload (`UNLOAD`) |
| Tap Mine, the ground, the check mark | Each selected minelayer lays one mine round that point (`LAY_MINE`) |
| Tap ground on a found enemy mine with minelayers selected | Move there (a plain move); a minelayer standing on it clears it |
| Tap Hold (units selected) | Hold position on or off for all of them (`STANCE`) |
| Tap Mend (an own building selected) | Its paid repair on or off (`MEND`) |
| Tap Sell twice (an own building selected) | Sell it (`SELL`): the first tap arms, the second sends (Part 4's window) |
```

Replace the row "Tap Deselect at the command bar's start" with:

```markdown
| Tap Deselect at the command bar's start | Clear the selection (no Command); the bar hides, except during placement, a strike aim or an order aim (Board, Unload, Mine), when it keeps its place |
```

Replace the row "Tap enemy with units selected" with:

```markdown
| Tap enemy with units selected | Attack it with the selected units that can hit it (a mixed selection attacks with those rows only); if none can hit it, nothing happens: a short shake, and the selection is kept |
```

The row "Tap an enemy unit with nothing selected | Nothing yet (its info card is out of Phase 3
scope)" stays as it is.

**Part 2. "Building placement": replace its second bullet with this one.**

```markdown
- Placement, the strike aim and the order aims (Board, Unload, Mine) exclude each other: entering
  one ends the others with no Command (the structure stays ready), so one mode owns the map's taps.
```

**Part 3. "Corner HUD and build drawer": replace the command-bar bullet with this one.**

```markdown
- The command bar: Deselect (48 x 64 dp) at its start, then the selection chip, then the orders
  the selection has, each at least 56 x 64 dp: for units Stop, Hold, Home (aircraft), Repair
  (damaged ground units that an own repair building serves), Board (squads, while the player has a
  carrier), Unload (a loaded carrier) and Mine (minelayers); for one own building Mend and Sell.
  An order shows only while it can act on part of the selection, and it sends only the rows it
  serves: a mixed selection shows Home and Repair side by side, each for its own rows. Deselect
  and, for units, Stop always show. The other orders follow in the order listed above and scroll
  sideways when they do not fit; a half-cut last button, or a fade at the bar's edge, is the cue.
  The chips take what is left, then "+N". Upright on a 360 dp phone about 264 dp is free for the
  bar: Deselect (48), one chip (40), Stop (56) and two more orders (112) fit before the rest
  scroll. No Attack button. Later orders join the list with a glyph and a HOW_TO_PLAY line.
```

**Part 4. A new section after "Building placement".**

```markdown
## Orders and their aims (ADR 0036 §12, ADR 0037 §9)
- No tap overload. Outside an open aim, a tap on an own unit or building always selects it,
  whatever is selected and whatever it is (an airfield, a carrier, a repair building). Orders
  that name an own target come only from the command bar. During an aim, a tap on an own unit or
  building other than the Board target is refused with a shake and no Command. A hold never
  sells, lays, loads or repairs.
- **Home** (aircraft selected): one tap sends each aircraft to its own airfield's pad (`REPAIR`),
  where it reloads and is repaired for credits. An aircraft whose airfield has no free pad, or
  that has no airfield, is left out. No aim.
- **Repair** (damaged ground units selected that a complete own repair building serves): one tap
  sends one `REPAIR` with those units to the nearest serving building, by straight distance from
  their centre. Units it does not serve are left out. No aim. Aircraft never go to a repair
  building, and medics are never a Repair target.
- **Board** (squads selected and an own carrier on the map, air or ground): tap Board, tap an own
  carrier with a free seat (it gets a ring; any other tap is refused with a shake and no Command),
  then the check mark: one `LOAD`. The carrier comes to the squads.
- **Unload** (a loaded carrier selected): tap Unload, tap the ground (a chevron marks the point;
  another ground tap moves it), then the check mark: one `UNLOAD` for the selected loaded
  carriers. Squads with no room at the point stay aboard.
- **Mine** (minelayers selected): the button shows laid mines over the cap ("7/12") and dims at the
  cap. Tap Mine, tap the ground (a mark and the blast ring show; another ground tap moves them),
  then the check mark: one `LAY_MINE` for the selected minelayers.
- **The aims (Board, Unload, Mine)** follow the strike aim's one-Command, X, turn and exclusion
  rules: the check mark sends exactly one Command and ends the aim; X, a second tap on the same
  button, a turn of the phone, or a selection that no longer holds a row the order serves ends it
  with nothing sent; placement, the strike aim and the order aims exclude each other. The command
  bar's slot stays frozen while an aim is open.
- **Where the aims' check mark and X stand.** Not in the strike aim's row by the strike button
  (`HudCorners.STRIKE_ROW`): beside the aimed point, by `GhostControls`' column rule (right of
  the anchor rect, else left, else above, never below; inside the safe area), each at least
  64 dp. The anchor rect, in place of the ghost's silhouette:
  - Board: the ringed carrier's pick square, its lifted centre plus and minus its pick radius
    (at least 24 dp); no anchor and no check mark until a carrier is ringed;
  - Unload: a 48 dp square round the chevron's ground point;
  - Mine: the bounding box of the blast ring round the mark.
- **Hold** (units selected): a toggle with a shield glyph, lit when every selected unit holds. A tap
  sets all of them to hold, or all to normal when all already hold (one `STANCE`). The selection
  chip shows a small shield on a type whose units hold. No world glyph.
- **Mend** (one own complete building selected): a toggle with a wrench glyph and the word MEND,
  lit while that building mends; a tap sends one `MEND`, on or off. It stops by itself at full
  health. The word differs from the units' Repair. An enemy building never shows its switch.
- **Sell** (one own complete building with a price selected; never the Headquarters or a site):
  the first tap arms it: it turns amber and shows "+N", the refund now. A second tap sends one
  `SELL`, with a buzz, only between `sell_arm_min_ms` (400) and `sell_confirm_ms` (3000) after
  the first. A second tap before `sell_arm_min_ms` is ignored and keeps the arm. Any other touch,
  or the window running out, disarms it with nothing sent. Never a hold: a resting thumb must not
  sell. The Sell button keeps its place and a fixed width, sized for the widest "+N", so the
  refund never shifts it or its neighbours.
  - On the player's last production building the second tap opens the question card that
    Surrender uses: "Selling it loses the match", Keep / Sell. Only Sell sends the Command; Keep,
    a tap outside the card or a turn of the phone closes it with nothing sent.
- `sell_arm_min_ms` and `sell_confirm_ms` live in `data/input_settings.tres`. Each order adds its
  glyph and its HOW_TO_PLAY line in the row that ships it.
```

**Part 5 (ADR 0036 §12's picking, which P244 also needs). "Sizes in dp": add after the
pick-order bullet.**

```markdown
- Aircraft are picked at their lifted point (the ground point raised by the art's `fly_px`, or
  `low_fly_px` for drone squads), with the same least radius of 24 dp. A ground unit beneath stays
  tappable at its own point. Where two pick discs of one pick rank overlap, the flyer wins; the
  rank order above still comes first, so with own units selected an enemy ground unit beats an
  own flyer. A ground unit hidden under a flyer of its rank is reached by a box or a double-tap on
  another of its type; a lone one by a box only. With units selected, a tap on an enemy that none
  of them can hit does nothing: a short shake, and the selection is kept.
```

## Notes

Note (2026-11-12, P26bq, the lead; from the reviews of the first Phase 4b rows):
- **P232.**
  - It starts after P271 (ADR 0037's SELL and MEND) has merged; this adds to "Merge order of the
    shared rows" (the ground-support plan's P26bq note). P271 moves `remove_dead`'s body and
    `_compact` into `game/sim/Removal.gd`, so P232 works on a `World.gd` of 960 lines.
  - Its type tables include one for `pad_offsets` beside `type_pads` (this adds to ADR 0036 §3's
    type row), because P241 spawns over a pad.
  - P231 put the def rules in `tests/sim/support/air_rules.gd` and
    `tests/sim/test_defs_data_air.gd`. The ranges in `test_defs_data.gd` read
    `World.MoveClass.size()`, `World.TABS` and `Strike.Kind`, so they widen when P232 and P233
    grow the enums. P232 points `air_rules.gd`'s placeholders `AIR`, `FLIGHT` and `RESEARCH` at
    `World.MoveClass.AIR` and `World.Tab.*`, and P233 points `REVEAL` at `Strike.Kind.REVEAL`.
- **P262.** It declares the 1.2 carry fields `carry_slots` and `carry_classes` on the defs, with a
  data test. No earlier row does this.
- **P263.** It replaces P271's placeholder `Removal.BOARDED` (-2) with `Carry.BOARDED`.
- **Atlas.** P237 put every shadow on page 2 (ADR 0036 §15's note). Every art row with shadows
  re-pins `TODAY_*` and `TODAY2_*` in `tests/view/test_iso_atlas_budget.gd` (P202 only
  `TODAY_*`), and P243 re-keys `page_of` for the flyers' hulls.
- **`PlayerView`'s public methods.** The lead's rule is the one in the ground-support plan's P26bq
  note: no pragma; a pure-move split comes before a 21st public method; own-only reads stay
  getters.

Note (2026-11-12, P26br, the lead; from the reviews of P232 and P236 and P232's mutation run):
- **P232 as built.** The list shapes (`PAD_ARRAYS`, `UPGRADE_ARRAYS`, `UPGRADES_MAX` 30) are in
  ADR 0036 §3's P232 note.
  - RALLY is bounded at `Tab.VEHICLES`: a RALLY on FLIGHT or RESEARCH is dropped and counted.
    **P241** decides whether an airfield takes a rally point (ADR 0036 §6: aircraft spawn over a
    pad).
  - The derived arrays `reveal_stamped` (P233), `air_rows` (P241) and `mod_dealt`, `mod_taken`,
    `mod_ammo` (P246) join `DERIVED_ARRAYS` and `MatchSnapshot.NOT_COPIED` in the row that writes
    their rebuild. They are unhashed, so no re-pin.
  - `ammo` stays in `MatchSnapshot.NOT_COPIED` until the view needs it (P243 or P244 moves it).
  - The row's split trigger is moot: a P232b taking `TABS` 5 would have needed its own re-pin (the
    per-tab arrays are hashed), which step 3 of the merge order does not allow. P232 shipped
    whole, under the size limit outside its pure moves.
- **`World.gd`'s budget.** 981 of gdlint's 1000 lines after P232, and the pragma is banned
  (`test_world_split`). P233 (about 5), P241 (about 4) and P246 (about 8) fit; P262 (about 50)
  does not. Hence row P232c above, which P241 and P262 now depend on.
- **P238, P240, P250.**
  - `PlayerView` has no mirror of `World.Layer`, and the AI may not name `World`. P238 or P240 adds
    one (P238 first, as the first reader), within the `PlayerView` rule of the P26bq note above.
  - A hand-built AIR type in the test `GridWorld` keeps `type_layer_bit` GROUND, because
    `GridWorld` sets `type_move_class` after `prepare()`. A test that builds an aircraft by hand
    sets the bit itself.
- **P234.** `WorldSort` bakes a sheet only when a scenario type's `type_id` equals its `art_id`.
  - The space centres' BuildingDefs use `type_id` `fossil_space` (Skyrig) and `renew_space`
    (Zenith), footprint 3x3.
  - They join the rosters in `data/factions/{fossil,renew}.tres`, so `test_kestrel_flats_factions`'s
    count moves.
  - Add a test that each one's art footprint equals its data footprint (`test_fossil_buildings`
    covers only its eight).
- **P235.** The Reveal's look is not a rocket launch (ADR 0036 §16's P26br note), although both
  models carry a `launch` emitter. Today a kind-3 strike plays no strike effect at all
  (`StrikeFx._add_strike` returns for any kind but 1 and 2); P235 owns its look.
- **P245** merges after P243 has re-keyed `page_of` (ADR 0036 §15's P236 note; its Depends and step
  2 of "Merge order of the shared rows" say so).
- **Atlas.** P236 cost 334 rows on page 1's cross-faction page, and page 1 has 591 left. If the
  next buildings cost the same, page 1 fills at the second or third of P239b, P245b and P249, even
  at 3,840. So P202 merges before the next of them, and the lead puts the next lever to Michael
  before that row starts (ADR 0036 §15's P236 note).

Note (2026-11-12, P26bt, the lead; from the reviews of P232c, P233 and P238 and their interaction
review):
- **`PlayerView`.** It stays at gdlint's limit of 20 public methods (gdlint does not count the
  static `of`), with no pragma. A new per-player or per-match fact is a typed field, not a method
  (P233's `reveal_state`). P238 added `PlayerView.Layer`, so the P26br point that `PlayerView` has
  no mirror of `World.Layer` is closed.
- **P233 as built.** There is no `reveal_stamped` array: the flag is `FogGrid.revealed` (ADR 0036
  §11's P233 note). So the P26br bullet above that lists `reveal_stamped` (P233) among the derived
  arrays is void; only `air_rows` (P241) and the `mod_*` arrays (P246) join `DERIVED_ARRAYS` and
  `MatchSnapshot.NOT_COPIED`.
- **P234.** It owns the replay-through-a-sweep test (P233's note in ADR 0036 §11): `Replay.play`
  to a checkpoint inside a standing sweep and one inside a pause, equal to the live run. It also
  gives a verb to the clause in `Strike.gd`'s rupture paragraph ("a row on a layer the strike
  weapon cannot hit ... is skipped"), and in `PlayerView.gd` adds "3 sweep" to `type_strike_kind`'s
  comment and `Layer` to the two lists of re-exported enums (the header and the comment on `Tab`).
- **P235.** It moves `reveal` and `reveal_site` from `MatchSnapshot.NOT_COPIED` to the copied list:
  the badge reads `reveal`, and the owner's strike button needs `reveal_site` to show on or paused.
- **P241.** It adds the tests that pin the sweep and the target layers together (the P233 and P238
  interaction review), under both implementations:
  - With the sweep on, a ground gun takes a ground target and never an aircraft; an anti-air
    weapon (mask 6) takes the aircraft and drops it when the sweep pauses.
  - A ground gun's ATTACK on an aircraft that only the sweep shows is dropped and counted (it
    passes `_enemy_target` and fails `_rows_that_can_hit`).
  - A real rupture that destroys the space centre ends the sweep in the same step, and an AIR row
    at the strike point keeps its hp.
- **P242.** `HOW_TO_PLAY`'s rupture row ("everything inside the ring ... takes damage") turns false
  once aircraft ship: the rupture hits ground rows only. P242, the first row with aircraft data,
  rewrites it.
- **The next sim row that edits `Power.gd` or `Harvest.gd`.** Their headers, and `Power.run`'s
  comment (`Power.gd:33`), still call them the first and second "half" of ECONOMY. Since P271,
  `Mend.run` is a third step, so that row changes "half" to "step".

Note (2026-11-13, P26bu, the lead; from the reviews of P234, P235, P240 and P262):
- **The Perf AI card per merge wave.** From Phase 4b's merge wave 4 (#422-#425) on, the card
  runs three times on `main` after a merge wave, not on each row before it merges (Michael,
  2026-11-13; the Phase 4 plan's P26bu note).
- **P240 as built.** P240 did not do its row's "`ProductionSpawn` spawn over a pad"; that work
  moves to P241. A spawn on the first free pad needs three things: an aircraft's `home`, the
  pad's rank among the living aircraft with that home (§3), and `air_rows`. P241 sets the first,
  derives the second and builds the third (ADR 0036 §3 and §6; §4's P240 note). P241's row
  already lists the spawn, so P241 owns it and its test.
- **P263b, from P262's reviews.** `World.insert_row` moves every row at and above the inserted
  row up by one. `building_rows` and `harvester_rows` stay stale until `Buildings.rebuild_lists`.
  `Power.run` calls it at the start of ECONOMY. P263b's unload in `Carry.run` inserts later in
  the same phase, so `Carry.run` calls it again after its inserts (a no-op when nothing was
  inserted), before `Repair.run` and `Mend.run` read `building_rows`. Without that call, Mend
  reads the wrong row's `cargo` as its switch. P263b adds a test of a mend and an unload on the
  same tick, under both implementations.
- **P235 as built.** The space centre and its sweep share the superweapon's one strike button
  (Michael, 2026-11-13: "Én knap"). P234 (#422) and P235 (#425) merge together, so `main` never
  has a space centre that borrows the superweapon's map aim. ADR 0036 §11's P235 note records
  the rest: the warning line in place of a toast, the badge, the binding rules and the fade.
- **The badge in the corner lists.** The row places the badge "in ADR 0025's corners". The
  `touch-ui-rules` skill's Corner HUD bullet and a note at the end of ADR 0025 §2 now name it
  (Michael's yes, 2026-11-13).
- **`rts-sim-conventions`.** Its hashed-state paragraph now covers `STATE_FORMAT` 6 (P232) and 7
  (P262) (Michael's yes, 2026-11-13).

Note (2026-11-13, P26bv, the lead; from merge wave 5 (#428 P263, #429 P285, #430 P241, #431 P239)):
- **The Perf AI trigger is now 11 ms** (Michael, 2026-11-13; the Phase 4 plan's P26bv note). Before
  P250 starts, the lead asks Michael to choose between two AI levers: smaller caps, or the AI's hot
  loops in C++.
- **P239 as built.** P239 ships the anti-air buildings (Burst Stack, Sky Needle) and their mask-6
  guns as data only. They are not in the rosters yet, because a UI test needs an item card for
  every buildable type. **P239b** therefore also does the following:
  - adds the roster entries and the item cards;
  - flips `test_defs_anti_air`'s "not in rosters" assertion;
  - removes the `fossil_aa`/`renew_aa` skips in `_own_files` (`test_defs_roster`,
    `test_defs_roster_renew`) and in `_units` (`test_defs_factions_data`);
  - writes the two HOW_TO_PLAY Combat rows: "the anti-air gun hits aircraft, never the ground"
    and "who hits aircraft".

  **P250 waits for P239b** (the roster entries), not only for P239. The Rows table carries these
  changes as dated notes, with a new P246a row.
- **P241 as built.** `Air.run` borrows SEPARATION's scratch `push_x`/`push_y` (ADR 0036's P241
  note). The `rts-sim-conventions` skill does not say this yet. A skill line needs Michael's yes,
  so it is on the lead's list for the next skill edit.
- **`World.gd` is at 994 of gdlint's 1000 lines.** P246a (a lead-added row, merge wave 6) moves
  function bodies out to the `World*` helpers. It changes no behaviour and keeps the arrays, the
  lists and every hash. P246 and P286 wait for it.
- **Lead follow-ups (NITs, not rows):**
  - `MatchSnapshot.NOT_COPIED`'s comment has one short line, which needs a reflow.
  - `RULE_SCALARS` order is not pinned: the test compares it as a set. The next row that edits the
    list pins the order.
  - The ground carrier cannot follow squads into FOOT-only scrub (P263's note in ADR 0036 §8).
    The ground-carrier rows of ADR 0037 §7 take it.

Note (2026-11-13, P26bw, the lead; from merge wave 7, the wave-8 reviews and Michael's two answers
of the same day):
- **Wave 7 merged:** #438 P289, #441 P203, #439 P246, #440 P276 and #442 P286. `main` is 99e1c6bd,
  and its tree equals the verified combined tree (5,864 tests).
- **The Perf AI cards after wave 7** read `sim_p95_ms` 10.27, 9.93 and 10.16, with
  `job_minus_step_p95_cp_ms` 3.35, 3.36 and 3.85: all under the 11 ms and 5 ms triggers. The
  printed `perf_ai` hash is now `a38d97f2d2fc5b91` (P286's re-pin).
- **New row P287a** (added by the lead): a pure-move split of `World.gd`, 993 -> 678 lines, with
  the shape lists moved to `game/sim/WorldShape.gd`. No behaviour, list, hash or name change. It
  merges before P287 and P298. Its row is in the ground-support plan's wave-3 table.
- **P242, P247 and P264 are data only,** the P239 pattern: a UI test needs an item card for every
  buildable type, so a type joins its roster with its art row. Their roster entries, item cards and
  HOW_TO_PLAY rows move:
  - P242's airfield to **P245b**; its fighters and bombers to **P245**, with the rewrite of
    HOW_TO_PLAY's rupture row (the P26bt note);
  - P247's engineering centre and `FactionDef.upgrades` to **P249**, which fills
    `FactionDef.upgrades` only after P248 (the Research tab) has merged, or research tiles would
    show without their cards;
  - P264's transports and drone squads to **P266**.

  The Rows table carries these as dated notes.
- **Dependencies.**
  - P247 and P264 gain P242: the engineering centre and the carriers require the airfield, and
    the upgrades need the bomber.
  - P250 and P254 gain P245, P245b and P249, and P255 gains P245 and P245b (P249 through P250),
    because a roster now comes with its art row.
  - P266 gains P264 and P243; P267 gains P266.
- **The bomber's range is 3.0 tiles** (the lead's correctness fix; Michael may object): its weapon
  `range` and `acquire_range` go from 2.5 to 3.0 tiles. At 2.5, a bomber that attacks a 3x3
  building from a diagonal stops at the approach ring's corner, 2.83 tiles from the centre, and
  never drops. The data rule's floor is 2.829 tiles. The GDD's bomber row and its dated note say so.
- **P247's starting values** (the lead, from P247's review): the engineering centre has 900 HP, 360
  build ticks and sight 5,000. All four upgrades cost 800 credits and 1,350 ticks of research, since
  the bomb and hull upgrades are a pair of equals. They are in the GDD's tech section as a dated
  note, as starting values for P255 to tune.
- **Open balance item for P255 and P267:** against harvester armour the drone squad's gun does about
  1 damage a second. ADR 0036 §14's harvester raid therefore cannot work with today's numbers. No
  number changes here; P255's run, or P267 when it builds the raid, takes it up.
- **Michael's two decisions (2026-11-13), on the architect's lever memo:**
  - **AI: option 3.** The AI thinks on its own thread, and its Commands land at T+1. ADR 0038
    (accepted) supersedes ADR 0020 §3's "think inside the tick job". Rows P301-P304 and P304b are
    in "Levers" above: P301-P303 merge before P251; they touch `game/core`, `AiDriver` and
    `PlayerView`, not the managers, so P250 and P252 do not wait for them.
  - **Atlas: option c1.** The directional frames lose their empty margins. ADR 0036 §15 has the
    P26bw note, and rows P305 and P306 are in "Levers" above. They merge before P249; P239b and
    P245b may land before or beside them. The art lanes in flight regenerate once after P305.
- **Wording for Michael's yes** (ADR 0038's Consequences): one bullet of `.claude/agents/ai-dev.md`,
  and the AI bullet and the Threading section of `rts-sim-conventions`. The lead asks after P303 has
  merged. CLAUDE.md needs no change.

Note (2026-11-14, P26bx, the lead; from the wave-10 reviews of P307, P288, P306, P253 and P244;
P302 and P303 bring no plan change):
- **P307** (a new row above, added by the lead): `UnitLayer.gd` was at gdlint's 1000 lines, so the
  picking side moved to the static `UnitPick.gd` before P244, with `UnitLayer` delegating.
- **P244 as built.**
  - "The bomber's attack ring" in the row means the bomber's own selection ring (ADR 0036 §15),
    shown while the bomber is selected (so while it attacks). The attack diamond keeps its fixed
    size: P244's widening of it to a building's footprint was reverted, because the row did not
    ask for it and it changed the feedback of tanks and squads.
  - Flyers get the selection ring on the ground under the shadow while selected, and a health bar
    above the lifted hull while selected or after a hit. The fog hides both, as it hides a ground
    unit's.
  - The Flight tab shows when the faction's list holds aircraft, with its cards locked until there
    is an airfield. A faction with no aircraft has three tabs. The names rule for four tabs is in
    the `touch-ui-rules` drawer bullet (Michael's yes, 2026-11-14). The tab shipped in P244 with no
    split, so the id P244b is unused.
  - Home shows only when a selected row can go home, so it is never a button that sends nothing
    (narrower than ADR 0036 §12's "while aircraft are selected").
- **P253 as built.** The arena's frozen anti-air weapons are its own copies. Its Burst Stacks have
  Power Plants and stand under the bomber route. The air fight ends about tick 550 (the last bomb
  at 482, the last aircraft-gun shot at 548). The bounds are the measured counts less P49a's
  margin, with the last bomb and the last gun shot held inside tick windows.
- **P306 as built.** Only page 1 is trimmed. The flyers and the shadows on page 2 stay untrimmed, as
  ADR 0036 §15 says (the trim's "page 2 stay as they are" and the P243 note).
- **P288 as built.** The snapshot stays player-agnostic (ADR 0012). It has one filtering reader,
  `MatchSnapshot.mines_for(player)`, guarded by a purity test (P288's note in ADR 0037 §8).
  **P293's acceptance is read anew** (the ground-support plan, same date): "in no snapshot list"
  means an unknown enemy mine is in no list `MatchSnapshot.mines_for` gives (ADR 0037 §8's P288
  note), so in no list `MineLayer` builds, and is never drawn; view code reads mines only through
  `mines_for`.
- **P265 and P265b are held** (as split, P265b holds `CarryMarkLayer`, the pips and the controller
  groups). They wait for P244's raised picking, because their carry tests pick and ring a transport
  through `UnitLayer`, where P243 left flyers rigless and unpickable. Then they get an integration
  change: the carrier pick goes through raised picking, and `CarryMarkLayer`'s ring follows the
  `AirLayer` rig.
- **Lead follow-ups (not rows yet):**
  - `ci.yml`'s `^PERF air` grep, so the line reaches the job summary, with its
    `test_ci_workflow.gd` case: a release-engineer row, as P96 was for P93.
  - Split `game/view/art_gallery.gd` before the next row that edits it (P244 left it at gdlint's
    limit of 1000 lines).
  - A command-bar overflow cue (a fade at the edge) for TUX: on the 320 dp phone upright, Home sits
    past the edge with no cue.

Note (2026-11-15, P26by, the lead; from the wave-11 reviews of P308, P309, P253b, P304, P239b and
the P265 integration):
- **New rows** (added by the lead, in the Rows table above): P308 (the gallery split, before
  P239b), P253b (the air arena's card gate) and P309 (`PERF air` in the CI job summary). P309 and
  P308 are the first two lead follow-ups of the P26bx note.
- **P239b as built.**
  - The anti-air buildings (Burst Stack, Sky Needle) are now in the rosters, with their item cards
    and the HOW_TO_PLAY Combat rows.
  - The shipped smoke's per-match hashes moved to `9513e873e6195b21`, `fe2669d1878d7d64` and
    `294a65d6349265e4`. The two types join the type list mid-list, so the type and weapon indexes
    that the rows, queues, ghosts and projectiles store shifted (each later Derrick type up 1, each
    Lumen type up 1 or 2), and `WorldHash` hashes those indexes (`type_ids` itself feeds only
    `defs_hash`). Play is identical line for line (ticks, winners, counts). The lead accepted the
    new hashes; the perf goldens did not move.
  - `ArtSheet._boxes` now boxes an unoutlined rod 1 px past its points (`BOX_CLEAR_PX`; a rod has
    no stroke to reach further), where a stroked face keeps 2 px (its stroke's 1 px reach plus the
    clear px).
  - The team share at zoom 1 is 9.4 % (Burst Stack) and 11.0 % (Sky Needle), inside the art
    rule's 8-12 %. KRITISK keeps 0.39 and 0.36 of it (ADR 0029 §5: 20-50 %), both
    inside the bands that `test_anti_air_art.gd` asserts.
- **P304 as built.**
  - From its merge the per-wave Perf AI card runs on `perf_ai_4b`, whose card arena key is
    `ai_4b`. Its printed hash is `75530630f4b19f95` (`SYNC` = `WORKER`), with no golden pair. The
    dev menu's "Perf AI base" runs the old arena, `perf_ai` (key `ai`), hash `025ff6707ff86ba0`.
  - Carriers, mending and air-masked anti-air are live in the arena, and the Space Centres start
    charged. The `ai_4b` difficulty copies take each level's mend pair (ADR 0037 §4), so it is the
    first frozen arena whose AI defs turn mending on (its rules make it work; nothing is mended in
    today's 900 ticks); ADR 0037 §11's "frozen arenas never sell or mend" still holds for the
    pinned arenas. ADR 0038 §7 names "the shipped Normal value" for later fields; here Easy and
    Hard take their own pairs (0/0 and 70/250), Normal 50/400. Its Lumen rifle squad has the
    shipped 70 hp, against 80 in `perf_ai`.
  - **P304b (2026-11-17, main e4be1931):** each side also starts with 2 ground carriers and 2
    minelayers (Bunk Wagon and Shot Truck, Linecar and Seeder; frozen copies of P290's defs and
    mines in `data/dev/arena/arena_4b/units/` and `weapons/`), 4 mobile rows a side taken off the
    rifle squads (18 to 14), so each side stays at 75. The printed hash moves from
    `75530630f4b19f95` to `75019d6b3818eed9` (`full_ticks` 174 to 172); no other golden moves. The
    Perf AI cards compare against the new hash. The AI still does not load, unload or mine.
    - The `AiMemory.class_of` / copied `type_move_class` fix (the ground-support plan's "`class_of`
      gap") moves to P295 (the lead's decision, 2026-11-17). It breaks nothing today: all four new
      units are unarmed and not scouts, so no flow field is keyed for them.
    - The P26bz trigger baseline (`main` 4456e53b, cards on `75530630f4b19f95`) predates P304b. The
      next cards run on a changed arena: 8 fewer armed rifle squads, and 8 unarmed rows that draw as
      `Marker` ellipses until P291 and P292. A trigger hit on them is reported to Michael as a
      finding, not taken for a regression.
  - The AI does not use carriers, mending or the sweep there yet (no LOAD, UNLOAD, MEND or sweep in
    900 ticks). That waits for the AI rows.
  - `test_frozen_ai_defs.gd` (kept as is) still says "the Perf AI route" at :4 and :52. Read that
    as the Perf AI base route.
  - The lead's Perf AI triggers, 11 ms and 5 ms, were set on the old arena. The first `perf_ai_4b`
    cards become the new baseline (this amends ADR 0038 §7's "the 11 ms and 5 ms triggers read
    it"), and Michael decides the triggers after them.
- **P265 and P265b** landed after P244, as the integration branches `claude/p265-board-unload-i`
  and `claude/p265b-carry-view-i`. The carrier pick uses P244's raised picking through
  `PlayerController.fill_pick` and its unit half `fill_unit_pick` (the ground units and the flyers,
  no buildings), which `CarryControls` reads every frame without allocating. `CarryMarkLayer`'s
  ring follows the carrier's `AirLayer.rig_of`.
- **P253.** P253b fixed the phone card's heavy window: Michael's first Perf air card (`main`
  a2204d2f) matched the golden `b56fa7d1c3f91459` on the phone but had no heavy frame, because the
  flyers were not in `drawn_rigs` (at most 134 against 135). Michael reruns Perf air after P253b
  merges, and the lead reads ADR 0013 §1 on the `PERF air` line in the CI summary (P309).
- **Lead follow-ups (not rows yet; they continue the P26bx list):**
  - `view_p95_ms` on the phone rose about 0.8 ms after P303 (wave-10 cards 10.26, 10.48 and 10.53
    against 9.43-9.79 in wave 9), probably from contention with the AI thread. Watch it; a probe
    row if it grows.
  - `BuildSidebar._fit_tabs` measures against `_stack`, a VBox that may grow to the named row;
    measure the parent's room instead.
  - NITs from the reviews:
    - P308: the dead `Gallery`/`GALLERY` preloads in `test_hud_v2_glyphs.gd` and
      `test_low_power_glyphs.gd`; the row helpers move to an `art_gallery_rows.gd` if a third page
      needs them; a header line that `art_gallery_icons.gd` is never instantiated.
    - P309: an over-long `ci.yml` comment line, and the AI comment still says "after the bases
      block".
    - P304: stale "Perf AI plays `perf_ai`" doc lines (`ai_perf_run.gd:19-21`,
      `perf_arena.gd:45-47`, `ci.yml`'s `WATCH ai` comment); the 4b layout test compares only
      building counts; `append_failure_message` in the field-name parity test; the 4b suite header
      should record today's counted facts (no LOAD, UNLOAD, MEND or sweep; the Burst Stack, Sky
      Needle and Redoubt fire 0 shots; `seen_mobile_id` 0, `full_ticks` 174); the frozen rosters
      hold no 4b type, so P250's production passes build nothing there; 3 x 900 ticks per verify;
      the card test's vacuous `begins_with("ai_think")` check; "ADR 0037 section 11" in the
      `ai_4b` headers (§4); the dev menu's 9 dp of room, "Perf AI base" next to "Perf AI", a named
      `open_perf_ai_base`, the layout test's header and an implicit cast in
      `test_frozen_ai_4b_defs.gd`.
    - P239b: STYLE.md's anti-air section needs a results paragraph (team share, 32 px IoU,
      KRITISK), its Gallery bullet (the Icons page lists only `ITEM_ICONS`), the d08 head's flat
      bar and the "taller than the Redoubt" line; the serrated barrel ends at d04/d12; the Sky
      Needle's floating KRITISK rod; its glass needle is faint on sand in greyscale (judge on the
      phone); the Burst Stack's 32 px IoU with the Grid Hub is 0.821, the closest pair; plain
      tracers for the Sky Needle's FX later; "spheres" in the CREDITS row; `_inked_bounds` ignores
      `stroke_px`, and no unit case mixes a rod and a face; the ragged short line "1 clear px
      (`ArtSheet.BOX_CLEAR_PX`). Parts in" in `IsoSheetDef.gd:82`, the "+76" comment in
      `test_iso_atlas_budget.gd`, `test_defs_anti_air`'s three comments and `_share` repeating
      `Support.default_picture`.
    - P265 integration: the Skyhauler/Ferrywing comment and the ninth row in
      `test_command_bar_carry.gd`'s header; `test_carry_mark_layer.gd`'s header (the `AirLayer`
      rig first); `ring_centre` calls `rig_of` twice; `CommandBar.gd:12` wraps early; no Unload
      test taps an own flyer's hull; `_pick_snapshot(_at)` never reads its argument; and, for
      P266's HOW_TO_PLAY line, an Unload tap right under a hovering carrier hits its hull and is
      refused with a shake.
    - P253 (wave 10; the rest is fixed on `main`): the rifle copy's mask cannot hit AIR (all
      ground-to-air fire is rocket squads'), which the comments should say; `AIR_END_PIN` has no
      margin; stale arena lists (`test_golden_hashes.gd`, `perf_arena.gd:38-48`,
      `PerfBases.gd:3-7`), the ragged "P253). When" wrap in `dev_menu.gd`, and in
      `test_dev_menu_layout.gd` the literal dp gaps, the header and a scroll test that checks only
      the safe rect; `test_perf_air` does not check `Engine.max_fps`; the Phase 4b counters read 0
      there; the air card has no draw-call forecast line, which P256's phone check 3 needs; the
      flyers are `Marker` ellipses until the art rows; seven 900-tick runs in the suite. The
      shared `rifle_squad`/`rocket_squad` type_ids are answered: `perf_ai_4b.tres` names
      `perf_air`'s own copies.

Note (2026-11-15, P26bz, the lead; wave 12, the first `perf_ai_4b` cards and the wave-12 reviews of
P245b, P245, P248 and P290):
- **Wave 12, in merge order (the lead):**
  1. Docs first: P400b and P500 (with P500b). They carry the ADRs and plan rows that the code rows
     cite: the Phase 5 rows P501, P507 and P509 depend on P500b, and P400b brings the Phase 6
     notes for the ad and AAB rows.
  2. Phase 5 and Phase 6 code: P509 (Phase 5: the `balance.yml` paths, before the first Phase 5
     data merge); then Phase 6: P401 (the AdService stub), P420 (the ad-ID guard), P410, P410b
     and P410c (the AdMob plugin, the AAB preset, the AAB export; P410c split from P410 at review,
     Phase 6 plan); then Phase 5: P501 (AudioService) and P507 (sfxgen). P501 is about 505
     production lines and stays one PR (the lead's decision): it is one concern with two review
     rounds, and a split would need a stub pool.
  3. Phase 4b: P290, P245b, P245, P248.
  4. This row last.
- **The `perf_ai_4b` baseline and its triggers (Michael, 2026-11-15).** Three cards on `main`
  4456e53b, Pixel 9a, the first on the 4b arena:

  | Card | `job_p95_ms` | `job_p99_ms` | `job_minus_step_p95_cp_ms` | `view_p95_ms` |
  | --- | --- | --- | --- | --- |
  | 1 | 10.61 | 13.13 | 3.39 | 9.43 |
  | 2 | 10.67 | 13.34 | 3.39 | 9.90 |
  | 3 | 10.69 | 14.31 | 3.64 | 9.89 |

  Every card printed the hash `75530630f4b19f95`, `gate_pass` true and 0 hitches. The triggers are
  `job_p95_ms` 11.5 ms (the card's `sim_p95_ms` row), `job_minus_step_p95_cp_ms` 5.0 ms and
  `view_p95_ms` 11.0 ms. When a trigger is exceeded on 2 of the 3 cards of a wave, the lead stops
  and finds the cause before the next wave merges. They replace the old arena's triggers
  (`sim_p95_ms` 11 ms, cp 5 ms; the P26bv and P26by notes) and are recorded in ADR 0038 §7. The
  P26by watch item on `view_p95_ms` now reads against its trigger.
  - **The baseline predates P245.** From wave 12 on, both perf arenas (`perf_air` and
    `perf_ai_4b`) bake and draw the real aircraft, no longer `Marker` ellipses (P245's STYLE.md).
    So the wave-12 cards may move `view_p95_ms`, page-2 rows and bake time by design, and the
    printed `perf_ai_4b` hash may change with the roster growth. The wave-12 cards are the first
    with aircraft: a trigger hit there is reported to Michael as a finding, not taken for a
    regression.
- **Perf air on `main` 4456e53b** (one card): the golden `b56fa7d1c3f91459` matched at all 6
  checkpoints and `gate_pass` is true (false at wave 10). `heavy_frames` is 914 (0 before), so
  P253b works. `drawn_rigs_max` is 150, `job_p95_ms` 8.14, `view_p95_ms` 9.37, 0 hitches.
- **P245b and P245 as built.**
  - Both rosters grew, so the stored type indexes shifted again (as with P239b), and the shipped
    smoke's per-match hashes moved. Play is identical line for line; the lead accepted the new
    hashes.

    | Tree | Match 1 | Match 2 | Match 3 |
    | --- | --- | --- | --- |
    | `main` 4456e53b | `9513e873e6195b21` | `fe2669d1878d7d64` | `294a65d6349265e4` |
    | after P245b (1a3291f5) | `5c59e8e0fc1b8dd9` | `5271041ee81495c0` | `d11d13c040fa4db9` |
    | after P245 (a7b6ee51) | `7bf5ac938a35e1aa` | `943c5cd5adfbd716` | `1f2a4405168f4ffa` |
  - P245 merges right after P245b, in the same wave, so the Flight tab is never empty on `main`
    (the lead's decision).
  - **Watch item: page 2.** P245's aircraft cost page 2 about 4 times their estimate (1,986 of
    3,584 rows on the cross page; the cause and the forecast are in ADR 0036 §15's P26bz note).
    Before P266 starts, the lead sets page 2's per-row allocation within its 3,584 rows.
    - P266 (transports and drone squads, every frame on page 2) waits for the allocation.
    - P204 (per-player unit shadows) and the shadows of P249, P279, P280, P291 and P292 are in
      the forecast. They do not wait; each re-pins `TODAY2_*` and reports its page-2 rows against
      its allocation in its PR.
- **The gate's unit types are 16 after P245.** The rosters now hold the aircraft, and
  `balance_summary.gd`'s set check reads the rosters, not a constant; the gate needs P250's air AI
  before it can pass (ADR 0031 §4's P26bz note).
- **P248.** Michael's two decisions are in its row above. P248 itself carries ADR 0025 §5's note
  and the skill text.
- **P290.** Its starting values are in the GDD's Ground support section (a note of this date;
  recorded now as starting values, the balance rows update them).
- **ROADMAP:** no box is ticked. P256 ticks the Phase 4b boxes it meets after Michael's phone check
  (its row), and the Performance box also needs `perf_bases` with mines and repairers and the draw
  calls within the forecast.
- **Lead follow-ups (NITs, not rows; they continue the P26by list):**
  - P245b, round 2 (line numbers on its branch): the hidden steel beam
    (`assets/art/STYLE.md:1350`); the anchor at `assets/art/STYLE.md:1354` reads 15 and should read
    13; the Flight Yard ruin's dark inside; the Glide Deck's charred lids;
    `assets/art/models/renew/renew_airfield.tres:58` puts two poses on one line; the pad test checks
    only the centres; thin margins (overlap 0.842 against 0.85, team share 8.75 % against 8 %).
  - P245, A-N2: the Sunfall's team share is above 12 % in 9 of its 16 directions.
  - P248, lens A, not folded: the Research tab is empty in the dev arena; the double-tap buzz; the
    unaffordable stripes on an item already paid for; P249 must not repeat P248's "Tap an upgrade"
    HOW_TO_PLAY row.
  - The export presets must exclude `tools/*` (session 2 does it in P411).
  - Open question for Michael: do the Google Mobile Ads SDK terms need an in-game notice
    (`addons/THIRD_PARTY.md`, "To confirm", from P410c)?
