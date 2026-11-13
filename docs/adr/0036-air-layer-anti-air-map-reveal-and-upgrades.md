# ADR 0036: The air layer, anti-air, transports, drone squads, the map reveal and upgrades

**In short, for Michael:** each side gets four new buildings and four new kinds of unit:
- The buildings: an airfield, an anti-air gun, an engineering centre that researches better
  bombers, and a space centre whose satellite lifts the fog over the whole map until the space
  centre is destroyed.
- The units:
  - a fighter;
  - a bomber;
  - a transport aircraft that carries infantry squads over rock and water;
  - a drone squad: soldiers carried by drones at low height.

Aircraft fly straight over everything. Only anti-air, rocket squads and fighters hit them. Rifle
squads and the anti-infantry gun can also hit the low drone squads. A bomber drops its bombs and
flies home to reload, and an aircraft is repaired on its airfield's pad. On the phone you select
and tap a target. A "Home" button sends aircraft home, "Board" puts squads into a transport, and
a loaded transport has an "Unload" button. The satellite has a button like the superweapon's.
The computer plays by the same rules.

Michael chose on 2026-11-09 to build all of it before launch, after the Phase 4 gate, in one block
with the ground design (ADR 0037): ROADMAP Phase 4b. His five answers are at the end.

Status: **accepted, 2026-11-09** (Michael: 1 A, 2 A, 3 B, 4 A, 5 A; accepted in docs row P230 of
`docs/plans/2026-11-09-air-and-tech.md`, together with ADR 0037). Proposed 2026-11-09 (architect,
branch `claude/design-air-and-tech`, base `main` at b6bfe95). The scope addition of the same day
(Michael's transport, drone squads and aircraft repair) is folded in. Revised the same day after the
docs lens (gameplay-dev: 7 must, 7 should, 4 nits): the AIR plane sites, the three `MOVE_CLASSES`
literals, the reveal convention, the boarded marker, selection groups, the SUPERWEAPON order, the
touch buttons in place of taps on own units and buildings, the exception numbers and the sizes.
GDD: the section "Air, anti-air, engineering centre, space centre".

Status note (2026-11-09, P230 docs; acceptance): what changed when it was accepted.
- **§11 is rewritten for answer 3 B.** The sweep has no timer and no recharge. It starts when the
  player fires it and lasts while the space centre that fired it stands. A blackout on it, or low
  power, pauses it; it comes back by itself. The enemy sees the warning once and an indicator
  while the sweep is on or paused. §2, §3, §12 and §14 follow (the strike data, the player's
  `reveal` and `reveal_site`, the indicator, the AI).
- **Answer 2 A.** Where this ADR says "1.1" and "1.2", read the block's first air part (P231-P256)
  and its second (P262-P268). Both come before launch. The two layout rows stay (P232 under
  exception 23, P262 under 24): P232 is already about 380 lines, and format 6 never ships.
- **ADR 0037 (accepted the same day) amends §2** (the repair role is declared on `UnitDef`, with
  `repair_slots` and `repair_seek_milli`), **§8** (`carry_eject_percent`) and **§12** (Board and
  Unload also take a ground carrier). The notes sit in those sections.
- **The `touch-ui-rules` text** for Home, Board and Unload is asked with this acceptance. The draft
  is in the plan's section "touch-ui-rules text for Michael's yes (P230)". P244 and P265 wait for
  Michael's yes; the skill is not edited before it.
- Dated notes were written in ADRs 0007, 0008, 0009, 0010, 0013, 0016, 0017, 0018, 0023, 0027,
  0030 and 0031. ADR 0023 §9 is superseded.

Supersedes, on acceptance: ADR 0023 §9 ("Air units and anti-air: not Phase 3 ... a later ADR
decides them"). Amends, on acceptance, by dated notes the lead writes in P230 (the accepted text of
each stays as it is):
- ADR 0007 §4 (pipeline: `Carry.board` and `Reveal.run` in the REMOVE mark, `Air.run` and
  `Carry.run` in ECONOMY).
- ADR 0007 §5 (Command types 5, 6 and 7).
- ADR 0007 §8 and ADR 0016 (`STATE_FORMAT` 6, and 7 if the carriers come in a later release).
- ADR 0007 §10 (DIED flag 2 and the event UNLOADED).
- ADR 0008 §1-§4 (the AIR move class, separation per layer).
- ADR 0009 §1-§4 (layer bits, the damage formula).
- ADR 0010 §1 (the reveal term).
- ADR 0013 §1 and §5 (§13 here).
- ADR 0017 §3 and ADR 0018 §5 (`TABS` 5, the aircraft cap, research items, passengers in
  `unit_cap`).
- ADR 0023 §2 (z table, atlas page), §10 (strike kind 3) and §13 (legal screen).
- ADR 0027 §7 (STRIKE kind 3).
- ADR 0030 (the managers, §14) and ADR 0031 §6 check 4 (the type count).

## Context
- **Michael's requests.**
  - 2026-11-09, translated: "We should also build an airfield and aircraft, air defence and more
    buildings, an engineering centre that can develop better bomber planes, and a space centre
    that gives a satellite which makes the fog disappear so you can see the whole map." He said
    yes to designing it now. It is built after the Phase 4 gate.
  - The same day, through the lead, he added an aircraft that carries infantry, infantry that fly
    with drones, and the repair of damaged aircraft. A separate ground design (ground repair, a
    medic, an infantry carrier, a minelayer) meets this one at a named interface (§7).
- **What the docs say today.** The GDD says "Not in version 1: ... air and naval units". ADR 0023
  §8/§9 estimated air at about 1,500 lines plus kernels.
- **Today's sim** (`game/sim` at b6bfe95):
  - Three move classes. `move_cost` is `3 x cells` bytes, and `MOVE_CLASSES = 3` is in
    `bind/world_access.h` and `core/fixed_math.cpp`.
  - Four armour classes (`ARMOUR_CLASSES = 4` in `core/targeting.cpp`).
  - `TABS = 3`.
  - Strike kinds 1 (rupture) and 2 (blackout), with `ready_tick`, `offline_until`, SUPERWEAPON and
    STRIKE.
  - Fog `visible` is derived and unhashed (ADR 0016). TARGETING (twin and kernel), `PlayerView`,
    `LastSeen` and the view read it.
  - No splash. Damage is `max(1, damage * percent / 100)`.
  - Rows ascend by id, ids are never reused, and `remove_dead` compacts in REMOVE. Command types
    5-9, 17-19 and 21-29 are free.
- **Kernels.** FLOW, SEPARATION, INTEGRATE, TARGETING and FOG have C++ twins (ADR 0013). Every
  other phase is GDScript only. A rule there costs one edit. A rule in a twinned phase costs two
  edits and a lockstep test.
- **The art page is full.** The cross-faction page is 3,550 of its 3,584-row budget, and ADR 0035
  (proposed) frees about 100 rows.
- **The AI.** It sees only through `PlayerView`, which reads `fog.visible`.

## Decision

### 1. Principle
- **Existing Commands do most of the work.** QUEUE builds aircraft, drone squads and research.
  PLACE places buildings. MOVE, ATTACK_MOVE, ATTACK and STOP move and fight. SUPERWEAPON fires the
  satellite.
- **Three new Command types, shared with the ground design (§7):** `LOAD = 5`, `UNLOAD = 6` and
  `REPAIR = 7`. They sit in the unit-order block, after STOP. The lead reconciles the numbers with
  the ground design before either is accepted.
- **Rules go into GDScript-only phases wherever they can:** COMMANDS, REMOVE, FIRE, PROJECTILES,
  ECONOMY and PRODUCTION. Kernel edits are limited to §13's list.
- **Every number is a starting value in `data/*.tres`.**

### 2. Data contracts (defs)
- **Units and weapons.**
  - `UnitDef.move_class` gains `Air = 3` (`World.MoveClass.AIR`).
  - `UnitDef.low_flying` (bool, AIR only, a data test): the row flies low. Drone squads are the
    first users.
  - `UnitDef.ammo` (0 = no limit; above 0 only for AIR) and `UnitDef.rearm_ticks`.
  - `UnitDef.carry_slots`: squads a carrier holds; 0 = not a carrier.
  - `UnitDef.carry_classes`: a move-class bit mask of who may board. FOOT is bit 1, WHEELED 2,
    TRACKED 4, AIR 8. Transports take 1.
  - `WeaponDef.targets`: a layer bit mask with GROUND 1, AIR 2 and LOW_AIR 4. The default is 1, so
    every shipped weapon keeps its meaning. A data test allows 1..7.
- **Buildings.**
  - `BuildingDef.pads` and `pad_offsets` (`Array[Vector2i]`, inside the footprint): the airfield.
  - The repair role, shared with the ground design (§7): `repair_classes` (a move-class bit mask,
    0 = none), `repair_hp` per `repair_period_ticks`, `repair_cost_percent` (the share of the
    unit's cost a repair from 0 to full hp costs) and `repair_reach_milli`. An airfield has
    `repair_classes` 8 and repairs on its pads only (§6).
  - Note (2026-11-09, P230; ADR 0037 accepted the same day): ADR 0037 §2 amends this bullet. The
    repair role's fields keep their names but are declared on `UnitDef` (`BuildingDef extends
    UnitDef`, so an airfield's data reads the same), so a squad may hold the role. The role gains
    `repair_slots` and `repair_seek_milli`, whose defaults leave the airfield unchanged. `Air.run`
    keeps every type with pads; ADR 0037's `Repair.run` serves the rest.
  - `BuildingDef.strike_kind` gains `Reveal = 3`. For a reveal building, `charge_ticks` is the one
    charge from completion; there is no recharge (§11, answer 3 B). Its `strike_ticks`, radius,
    delay and weapon are 0 or null (a data test).
- **Upgrades.** `UpgradeDef` (new Resource): `id`, `display_name`, `faction`, `cost`,
  `research_ticks`, `requires` (the engineering centre), `stat` (`DAMAGE_DEALT`, `DAMAGE_TAKEN` or
  `AMMO`), `value` (a percent, or an amount for `AMMO`) and `applies_to` (UnitDefs). They are listed
  in `FactionDef.upgrades`. Each upgrade has one level: researched or not.
- **Tabs.** `World.Tab` gains `FLIGHT = 3` and `RESEARCH = 4`, so `TABS = 5`. The airfield produces
  FLIGHT and the engineering centre produces RESEARCH. Drone squads are INFANTRY items from the
  barracks. The labels avoid "Air" (ADR 0023 §13: RA2's sidebar tabs); "Flight" and "Research" are
  recommended.

### 3. State (one layout row per release, one re-pin each)
P232 adds every column the 1.1 rules need at once, under named exception 23 (22 is P189b's):
`STATE_FORMAT` 6. The carriers' state (marked "1.2") comes with P262, the 1.2 layout row, as
`STATE_FORMAT` 7 with one more re-pin under exception 24. If Michael wants everything in one
release, P232 takes both and there is one re-pin. Rule rows after a layout row are hash-neutral for
the frozen arenas.

Note (2026-11-09, P230): Michael chose everything before launch (answer 2 A), but the two layout
rows stay: P232 is already about 380 lines and cannot take the passengers. Format 6 never ships.
ADR 0037's P286 re-pins once more on format 7 (exception 25).

| Kind | Name | Hashed | Meaning |
| --- | --- | --- | --- |
| row | `ammo` | yes | shots left |
| row | `carry_mode` (1.2) | yes | 0 none, 1 unload on arrival |
| type | `type_layer_bit` | rules | 1 ground, 2 air, 4 low air; derived at load from move class and `low_flying` |
| type | `type_ammo`, `type_rearm_ticks`, `type_pads`, `type_upgrade`, the repair role, `type_carry_slots`, `type_carry_classes` (1.2) | rules | as §2; `type_upgrade` -1 except for research items |
| weapon | `weapon_targets` | rules | layer mask |
| player | `reveal_site`, `reveal`, `upgrades` | yes | §11 (the space centre that fired; 0 off, 1 on, 2 paused), §10 |
| upgrade tables | `upgrade_stat`, `upgrade_value`, `upgrade_types` | rules | from `UpgradeDef` |
| passengers (1.2) | `pass_carrier`, `pass_id`, `pass_type`, `pass_hp`, `pass_owner`, scalar `pass_count`, rule `passenger_cap` | yes, section `passengers` | boarded squads (§8) |
| derived | `reveal_stamped`, `mod_dealt`, `mod_taken`, `mod_ammo`, `air_rows` | no | rebuilt by `prepare()` and when their inputs change |
| map | the AIR plane of `move_cost` | map digest | `cells` bytes, all 10 (open) |

- **Return target.** `home` (today a harvester's refinery) is documented as "the building a row
  returns to" and holds an aircraft's airfield.
- **Pads.** An aircraft's pad is derived: its rank by id among the living aircraft with that home.
- **Research items** are queue-only types (tab RESEARCH, speed 0, footprint 0,
  `type_upgrade >= 0`) that WorldLoad makes from each `UpgradeDef`. The queue, the payment, the
  progress, the cancel refund and `requires` are reused.

Note (2026-11-12, P232; named exception 23): the shapes as built. It changes no accepted text.
- **Pad offsets.** Beside `type_pads`, the type table `type_pad_first` indexes the flat rule lists
  `PAD_ARRAYS` (`pad_offset_x`, `pad_offset_y`): entries `type_pad_first[t]` to
  `type_pad_first[t] + type_pads[t] - 1` are the tile offsets of type `t`'s pads from the footprint
  origin.
- **Upgrades.** The tables are `UPGRADE_ARRAYS`: `upgrade_stat`, `upgrade_value`,
  `upgrade_type_first` and `upgrade_type_count` (one entry per upgrade) and the flat `upgrade_types`
  (type indexes), with the id list `upgrade_ids` beside them. WorldLoad reads the listed factions'
  `upgrades` after every type, once per id (the first wins), and skips a null `applies_to` entry
  (it is not counted). At most `World.UPGRADES_MAX` = 30 are kept: `upgrades` holds one bit per
  upgrade in an int32, and 30 (bits 0 to 29) keeps the mask positive. A data test over the shipped
  factions holds the ids non-empty, an id on one def only (the same def in two factions counts once) and at most 30. The lists are rules:
  `defs_hash` takes the pad lists and the upgrade lists after the type tables and before the weapon
  tables, and `upgrade_ids` after the faction ids; none is in the state hash.
- **Other tables.** The repair role is seven type tables (`type_repair_classes`, `_hp`, `_period`,
  `_cost_percent`, `_reach`, `_slots`, `_seek`); a padded type has period 1 (UnitDef's default) and
  the rest 0. The layer bits are `World.Layer` (GROUND 1, AIR 2, LOW_AIR 4); a padded type and a
  hand-built weapon (`weapon_targets` padded) are GROUND.
- **RALLY.** INFANTRY and VEHICLES only; FLIGHT and RESEARCH are dropped and counted; P241 decides FLIGHT.
- **Not added.** The derived row of the table (`reveal_stamped`, `air_rows`, `mod_dealt`,
  `mod_taken`, `mod_ammo`) is left to the rows with the rule that rebuilds each one: P233, P241 and
  P246. Each joins `DERIVED_ARRAYS` and `MatchSnapshot.NOT_COPIED` then. This is hash-neutral,
  because derived arrays are not hashed.
- **Re-pin.** `TICK_0_SEED_1` `a9e33d0d17b232fe` -> `781a749381ea2eb2`; perf arena final
  `17f7a83c4d492c4c` -> `4512f2002ed89f5c`; base arena final `c84764064abfb27c` ->
  `58681a6fcaf74db6`. Twin and kernel agree; no row, rule or run moved.

Note (2026-11-12, P262; named exception 24): the carriers' layout as built. It refines the table
row of the passengers above (`pass_count` is a header scalar, the records are in the section
`passengers`, and `passenger_cap` is in `defs_hash`) and §8's "the derived lists see the change"
(they see it at the next `Buildings.rebuild_lists`, below), and changes no other accepted text.
- **State.** `STATE_FORMAT` 7. The row column `carry_mode` follows `ammo` (0 for every row). The
  passenger table is `World.PASSENGER_ARRAYS` (`pass_carrier`, `pass_id`, `pass_type`, `pass_hp`,
  `pass_owner`), `passenger_cap` entries each, all free at load; the live count `pass_count` is a
  hashed scalar in the header (`HASHED_SCALARS`), and the new last hash section `passengers` feeds
  the live records only (record by record, the five fields in list order), so `HASH_OTHER_SECTIONS`
  is 8. A count outside the table is clamped to 0..the size of its shortest column in the hash.
- **Rules.** `RulesDef.passenger_cap` (default 0, inert; `data/rules.tres` 150, the two players'
  `unit_cap`) is a rule int. `UnitDef.carry_slots` and `carry_classes` fill the type tables
  `type_carry_slots` and `type_carry_classes` (0 for a padded type); a data test holds them to a
  pair (both set or both 0), a mask of 0 to 15, and no building a carrier. `load_reach_milli` and
  `unload_reach_tiles` come with `Carry.gd`.
- **`World.insert_row(id, owner, type_index, hp, x, y)`** (body in `WorldRows.gd`) returns the new
  row, or -1 with no change at `max_rows`, for `hp` below 1, an owner outside 1 to `player_count`,
  an unknown type, an id in use, an id below 1 (0 means "none") or an id not below `next_id` (never
  issued; `add_unit` would issue it again). It writes no event and leaves `next_id`,
  `spawn_refused` and `player_count` alone, bumps `rows_version`, and starts the row as `add_unit`
  does (idle, `fog_cell` -1, `ammo` of its type, `carry_mode` 0). Rows at and above the returned
  row move up by one. The derived lists `building_rows` and `harvester_rows` stay stale until
  `Buildings.rebuild_lists` (`Power.run` calls it at the start of ECONOMY). Its one caller,
  `Carry.run`, runs after `Power.run` and before `Repair.run` and `Mend.run`, which read
  `building_rows`, so `Carry.run` calls `Buildings.rebuild_lists` after its inserts.
- **Data rule.** `passenger_cap` is 0 or at least 2 × `unit_cap` (passengers count toward
  it), so the table cannot overflow.
- **Re-pin.** `TICK_0_SEED_1` `781a749381ea2eb2` -> `dd094805d77cbf7b`; perf arena final
  `4512f2002ed89f5c` -> `8ffe4168214d0fa4`; base arena final `58681a6fcaf74db6` ->
  `57a2fbfa38637bc4`. Twin and kernel agree; no row, rule or run moved.
- **MOVE and `order_target`.** The check of §8 passed: in TARGETING (twin and kernel) only an
  ATTACK row reads or writes `order_target`, so LOAD's MOVE row keeps it and the BOARD fallback is
  not needed. `test_targeting_move_order_target` pins it under both implementations.
- **Kernels.** No kernel reads the new columns, so `world_access.h` is unchanged and the sanitizer
  dump holds no new record; `KNOWN_FORMATS` gains 7.

### 4. The air layer: movement
- **The AIR move class has an open cost plane.** It is structure, not balance: no terrain has an
  air cost. A new constant `World.GROUND_CLASSES = 3` bounds every loop over terrain costs, and
  the AIR plane (class 3) is filled with `World.GRASS_COST` apart from them. P232 changes these
  sites, each of which loops over `World.MoveClass.size()` today:
  - `WorldLoad.gd:141`: `terrain_cost[index * classes + move_class] = def.cost[move_class]` reads
    `TerrainDef.cost`, which has 3 entries. `terrain_cost` stays `terrain * 3 + class`
    (`World.gd:499`, ground classes only), and `MapDef.validate`'s 0..40 range is unchanged.
    The loader fills the AIR plane with `GRASS_COST`, as the no-map path (`WorldLoad.gd:108-111`)
    already fills every plane.
  - `World.set_terrain` (`World.gd:771-779`) loops over `GROUND_CLASSES` and leaves the AIR plane
    alone.
  - `Buildings._write_cost` (`Buildings.gd:219-231`) loops over `GROUND_CLASSES`. Over every
    class it would write 0 into the AIR plane under each footprint, and aircraft would slide off
    buildings.
  - Every other `World.MoveClass.size()` in `game/sim` (`Buildings.gd:106`, `:148`, `:294`,
    `World.gd:728` and `:758`) is checked in P232. It stays 4 where it sizes a plane, the flow
    cache or a passability test, and becomes `GROUND_CLASSES` where it walks terrain costs.
- **What follows.** `line_clear` is always true for AIR: `Movement.run` steers aircraft DIRECT and
  never asks for a flow field, INTEGRATE never slides them, and `Formation.assign` and
  `Buildings.aim` find slots over rock and buildings. The map clamp holds.
- **Kernels.** Only the literal `MOVE_CLASSES` changes, 3 -> 4. It is in three files:
  `bind/world_access.h:54`, `core/fixed_math.cpp:9` and `core/integrate.cpp:14` (its own copy,
  used at `:74`). FLOW is configured with 4 classes and never gets an AIR key.
- **Hovering.** Aircraft and drone squads hover. There is no landing and no fuel.
- **Separation is per layer.** A pair counts in SEPARATION only when both rows have the same
  `type_layer_bit`, so aircraft spread among themselves, drone squads among themselves, and
  neither pushes tanks. This is one comparison per pair, in the twin and the kernel.
- **Altitude is view-only.** Range, sight and pick tests use the ground point. The view draws high
  air `fly_px` up and low air `low_fly_px` up (art data), with shadows (§15).

Note (2026-11-12, P240): as built. It changes no accepted text, but it moves a bound.
- **Skip before the look.** `Separation.run` and its kernel skip a row of another layer before
  `looked += 1`. That row counts toward neither `separation_scan` nor `SEP_PAIRS`, so a stack of
  aircraft cannot use up a tank's scan.
- **The bound.** ADR 0008's "separation is bounded by `separation_scan` x units" and ADR 0011's
  "separation pairs at most `separation_scan` x units" now cover looks only. The walk past rows of
  other layers is bounded by the rows of the 3x3 block and is not counted. `perf_air` (P253)
  measures it, and its counted bound should include the tally probe's `other_layer`. No new
  `World.Stat`.
- **Buildings.** `Buildings._write_cost` writes the ground planes only. That was checked, and the
  crossing case of `tests/sim/native/test_air_movement_lockstep.gd` pins it (a jet flies over a
  footprint with no flow field).
- **Pad spawn is P241's** (section 6: home, pad rank, `air_rows`).

### 5. Target layers
- **The rule.** A weapon may hit a row when `weapon_targets & type_layer_bit[type]` is not 0.
  Buildings are ground.
- **Where it is tested.**
  - TARGETING (twin and kernel): in acquisition, after the damage-percent test, and in the ATTACK
    lock. A lock on a row its weapon cannot hit falls back to ATTACK_MOVE, as an unseen one does.
  - `Sim._apply_attack` keeps only rows that can hit the target's layer.
  - `Combat.fire` re-tests the bit, which costs one read.
  - The rupture skips AIR and LOW_AIR rows (`Strike.run`). The blackout is unchanged.
- **No fifth armour class.** Aircraft use LIGHT or HEAVY, and drone squads use INFANTRY. The layer
  bit decides who may shoot, and the existing percents decide how much damage gets through.
- **Starting masks:**

  | Weapon | Mask | Hits |
  | --- | --- | --- |
  | anti-air buildings (new) | 2 + 4 | high and low air |
  | fighters | 2 | high air only |
  | rocket squads (Wildcatters, Breakers) | 1 + 2 + 4 | everything |
  | rifle squads (Rig Hands, Linemen), the Redoubt (anti-infantry) | 1 + 4 | ground and the low drone squads |
  | every other weapon, bombers, drone squads' own guns | 1 | ground |

  So bombers beat buildings and tanks. Anti-air, rockets and fighters beat bombers. Fighters lose
  to anti-air. Drone squads cross cliffs, but rifles and rockets answer them.

Note (2026-11-12, P238): as built. It changes no accepted text.
- **Unarmed types have no mask.** An ATTACK lock by a type with no weapon index (-1) or one past
  the weapon tables holds on any layer. `Sim._rows_that_can_hit` keeps a row whose weapon index is
  past the tables, and a weapon -1 row never gets ATTACK (`_own_rows` armed).
- **When it is tested.** A held target is re-tested on the row's turn, with its range and percent;
  the ATTACK lock is re-tested every tick.
- **The ATTACK filter** runs before `Buildings.aim`, so an excluded row keeps its goal and its
  order. When no row is left the command is dropped and counted.
- **The fire re-test** in `Combat.fire` comes after the enemy test and before range. A refused
  shot records no SHOT and leaves the cooldown and the held target alone.
- **The rupture skip** is in `Strike._land` (not `Strike.run`) and reads the strike weapon's
  `targets` once: `fossil_rupture.tres` stays at 1, so air and low air rows are skipped.
- **PlayerView** re-exports `World.Layer` as `PlayerView.Layer` (a test pins the pair), so the AI
  names the bits without naming `World`.
- **Requirement for P240.** A ground row can lock a low-air drone squad that hovers over rock; its
  class has no next step there, so it stops (`Movement._refresh_next`) and fires once in range.
  P240's lockstep must include a ground row locking a LOW_AIR drone over rock.

### 6. Airfields: ammo, reloading and repair (`Air.run`, ECONOMY, GDScript only)
- **The aircraft cap.** A FLIGHT QUEUE is valid while living aircraft plus queued FLIGHT items are
  below the sum of `type_pads` of the player's complete airfields. A finished aircraft spawns over
  the producer's first free pad. With no free pad the head waits at 100 %, as at a blocked exit.
  Drone squads are not aircraft for the cap.
- **Home.** The producing airfield. When it dies, `Air.run` re-homes the aircraft to the lowest-id
  own complete airfield with a free pad, or sets home to 0. A homeless aircraft cannot reload or
  be repaired.
- **Ammo.** A shot of a type with `type_ammo > 0` costs 1 (`Combat.fire`). At 0 the row does not
  fire. With a home, `Air.run` gives it MOVE home in the same tick, and on its next TARGETING its
  target is dropped, as for any MOVE row (`Targeting.gd:173`). Without a home it keeps its order
  and holds fire.
- **`Air.run`** walks `air_rows` once, after `Harvest.run`:
  - **Return.** An aircraft with ammo 0 and a home gets MOVE to its pad, through the reset
    `_apply_point` uses.
  - **Pads and separation.** Aircraft that wait on pads are pushed apart by SEPARATION like any
    pair on the same layer. So a data test requires the pads of an airfield to lie at least the
    largest FLIGHT type's `formation_spacing` apart, and `repair_reach_milli` to be at least half
    a tile. Otherwise waiting aircraft drift out of reach.
  - **Reload.** On the pad (within `repair_reach_milli` of it) with its home complete and online,
    it gains 1 ammo every `max(1, type_rearm_ticks / cap)` ticks, with cap `type_ammo + mod_ammo`.
    The tick is stamped in `ready_tick`, which mobile rows leave unused.
  - **Repair.** In the same place, on ticks with `tick % repair_period_ticks == 0`, its hp rises by
    `repair_hp` (not above max). The owner pays `ceil(cost * gained * repair_cost_percent /
    (100 * max_hp))`. There is no repair while the player cannot pay.
  - **Waiting.** A full, healthy aircraft waits over its pad. A bomber does not resume its old
    target in this version.
- **Fighters** have ammo 0 (no limit) and return only when ordered (REPAIR, §7).
- **Cost:** O(air rows) per tick, with no allocation.

Note (2026-11-13, P241): as built. It changes no accepted text except the bullets marked "adds".
- **Where.** `game/sim/Air.gd`: `cap_room` (the QUEUE cap, called from `Production.apply_queue`),
  `free_pad` and `pad_point` (the spawn, called from `ProductionSpawn`), `run` (ECONOMY, after
  `Harvest.run`, before `Mend.run`). `air_rows` is rebuilt in `Buildings.rebuild_lists` with the
  other two derived lists (one `rows_version`), and joins `DERIVED_ARRAYS` and
  `MatchSnapshot.NOT_COPIED`. An aircraft is a row whose type's layer bit is AIR; drone squads
  (LOW_AIR) are not in it.
- **Pad rank** is the rank by row (ids ascend with rows) among the aircraft with that home. When an
  earlier aircraft dies or is re-homed in, the ranks after it shift, and `Air.run` seats (adds):
  an idle aircraft over its airfield's footprint but out of reach of its own pad gets MOVE to it.
  So a reload or repair never stalls on a stale pad. A spawn can share a point with a resident for
  the one tick before that resident leaves.
- **Pad turn (adds).** `pad_point` turns the pad offsets to the airfield's facing for a square
  footprint, as a dock is (P232's note reads them from the origin without a turn). The view rows
  that draw pads (P243 to P245) must use `Air.pad_point`.
- **Spawn (adds).** A finished aircraft takes the first free pad of the producer, and then of the
  other complete own airfields, lowest row first, so that the cap (the pads of every complete
  airfield) and the spawn agree. Its `home` is that airfield and it has no order: a FLIGHT item
  takes no rally point (RALLY on FLIGHT stays dropped and counted), so it hovers over its pad.
- **Re-homing (adds).** `Air.run` also tries a homeless aircraft (home 0) every tick, so an
  airfield that is built or freed takes it. A home counts only while it is a living, complete
  building of the same owner with pads.
- **Return (adds).** An aircraft with ammo 0 and a home, not within `repair_reach_milli` of its pad
  and not already on a MOVE order (a MOVE a player gave is kept until it stops), gets MOVE to the pad (`Formation.assign`, `Movement.reset_nav`). An
  empty aircraft that is on a MOVE keeps its goal and is sent home when it stops.
- **Reload (adds).** The first round is gained at once on arrival, then one each `max(1,
  rearm_ticks / type_ammo)` ticks, the next due tick in `ready_tick` (`tick >= ready_tick`). The cap
  is `type_ammo`; P246 adds `mod_ammo`. The airfield must be complete and not blacked out.
- **Ammo.** `Combat.fire` skips a limited row at 0 ammo before the power and layer tests (no shot,
  no cooldown, target kept) and spends 1 after the shot is made.
- **Cost (adds).** §6's "O(air rows) with no allocation" holds with two additions: a pass over
  `building_rows` clears the per-airfield counts (kept in the scratch columns `push_x` and
  `push_y`, which SEPARATION clears before reading), and a re-home scans `building_rows` (a failed
  scan is not repeated for the owner in the same tick). The one-row array of an order and
  `Formation.assign` allocate at event cadence only.
- **Scratch.** `Air.run` borrows SEPARATION's scratch arrays `push_x` and `push_y`: both implementations
  `fill(0)` them before SEPARATION writes, and nothing reads them between ECONOMY and the next
  SEPARATION.
- **Data rule.** Tab FLIGHT and a high-air type (AIR, not low flying) go together
  (`air_rules.gd`): the cap counts by tab, the spawn keys on the layer. `ready_tick` is a stamp
  (`tick + 1`), as `PlayerView.row_ready_tick` reads it.
- **Not here.** Repair (P241b); the return trigger and reload were not split to P241c.
- **Tests.** `test_airfield.gd`, `test_airfield_return.gd` (the empty-and-return case under both
  implementations) and `test_sweep_layers.gd` (the sweep with the target layers, both
  implementations). No golden moved: no shipped type has ammo or pads.

Note (2026-11-13, P241b): repair and `REPAIR` as built. It changes no accepted text.
- **Where.** `Air._service` (called from `Air.run` for an aircraft within reach of its pad: reload
  as P241 built it, then repair) and `Air.apply_repair`, which `Sim._apply` calls for
  `Command.Type.REPAIR` (7); the factory is `Command.repair(player, unit_ids, building_id)`.
- **Repair** is as §6 says: on ticks with `tick % repair_period_ticks == 0`, `repair_hp` up to the
  maximum, for `ceil(cost * gained * repair_cost_percent / (100 * max_hp))`; no pay, no repair. It
  also needs the airfield's `repair_classes` to carry the AIR bit, and an online airfield (a
  blackout stops it, as it stops the reload). A fighter, with no ammo limit, is repaired too.
- **`REPAIR`**: the valid aircraft are own, living, complete, in the AIR layer, with their move
  class bit in the airfield's `repair_classes`; the lowest ids first. One already homed there keeps
  its pad; another is re-homed while the airfield has a pad left (pads minus aircraft homed there)
  and is skipped otherwise. Each one taken gets MOVE to the pad of its rank, as `Air.run` derives
  it. With none taken, or a target that is not an own complete building with pads and a role, the
  command is dropped and counted. This is the one `REPAIR` entry: P277 adds the branch for a
  building without pads to `apply_repair`, not a second command.
- **Not here.** The `REPAIRED` event (ADR 0037 section 2, Event 8) is P276's: it adds the event for
  the airfield's repair too (at most one per pad per period), together with `Repair.run`. P241b writes
  none, because no view reads it for airfields yet. A defeated owner's aircraft are not repaired.
- **Tests.** `test_airfield_repair.gd` (the repair and its price) and `test_repair_command.gd` (the
  command and the part of the shared contract the airfield owns). No golden moved.

### 7. The interface shared with the ground design
- **`REPAIR = 7`:** unit ids, `target_id` = an own complete building with
  `repair_classes & class_bit(unit) != 0`.
  - Each valid unit goes to the building's service point and is repaired while within
    `repair_reach_milli` (the role's rule of §6). It then goes idle there.
  - For an airfield the service point is a pad. REPAIR re-homes the aircraft when that airfield
    has a free pad, and the row is skipped otherwise. This is also how a player sends aircraft
    home.
  - The ground design's repair building uses the same role with its own classes (vehicles), and
    its own service point (its dock).
- **Recommendation: aircraft are repaired at airfields only.** The ground repair building leaves
  bit 8 (AIR) off. Allowing "both" later is a data change on that building.
- **`LOAD = 5` and `UNLOAD = 6` and the carrier role** (`carry_slots`, `carry_classes`, the
  passenger table, `Carry.gd`): §8. The air transport and the ground infantry carrier are two data
  entries on one module. Whichever release comes first builds `Carry.gd`; the other adds data and
  its own art.
- **Squad-only rules.** The medic and the minelayer belong to the ground design. If the medic
  heals squads through the same repair role, it is a mobile row with the role. The ground design
  decides that. This ADR only requires that `REPAIR` names a building.

### 8. The transport and the carrier rules (`Carry.gd`; release 1.2 recommended)
- **Boarded squads leave the row table.** A boarded squad is not a row. Its id, type, hp and owner
  move into the passenger table. Every kernel, the grids, fog, targeting and separation therefore
  ignore it with no edit.
  - **Unloading** puts it back as a row with the same id, inserted in id order by a new
    `World.insert_row`. This is GDScript, at event cadence, O(rows x columns).
    - It bumps `rows_version`, so the view and the derived lists see the change.
    - It refuses (returns -1) when the table is at `max_rows`; the squad then stays aboard
      (below).
    - The id keys of the view stay valid.
  - **Selection groups.** Today `PlayerController.gd:286` passes every DIED id to
    `selection.remove_ids`, which also strips groups 1-3. P265 makes it skip records with the
    boarded flag (§8, flag 2) for groups 1-3 and drop them only from the live selection. A group
    then counts only the squads on the map and holds the boarded ones again after the unload.
    P265 tests that a group with a squad aboard shows the right count and refills.
  - **Unit cap.** Passengers count toward `unit_cap`.
- **LOAD** (unit ids = the squads, `target_id` = an own carrier). The valid squads are own FOOT
  rows whose class bit is in `carry_classes`, while slots remain.
  - The carrier gets MOVE to G, the position of the lowest-id squad.
  - Every squad gets MOVE to G with `order_target` = the carrier id: "board on arrival".
  - On the phone it comes from the "Board" button (§12).
  - P262 checks that TARGETING (twin and kernel) leaves `order_target` of a MOVE row untouched. If
    it does not, a BOARD order value takes its place with a TARGETING edit, and §13 gains a row.
- **Boarding** (`Carry.board`, in the REMOVE mark after `FogUpdate.begin`, before
  `remove_dead`). A squad boards when its carrier lives, is within `load_reach_milli` and has a
  free slot. The checks run in ascending row order.
  - The squad's record joins the table, and the row is marked for this tick's REMOVE as a
    cancelled site is (`Production.CANCELLED`, `World.gd:894`): `hp` 0 (the one test
    `remove_dead` uses) and `build_left` = `Carry.BOARDED` (-2; a mobile row's `build_left` is
    0 otherwise).
  - `World.remove_dead` writes its DIED record as for any death, with
    `events[at + Production.DIED_CANCEL_FLAG_AT]` (index 6) = 0 died, 1 cancelled or 2 boarded,
    and `events[at + 7]` stays 0. The view draws a flag-2 record as climbing in, not dying.
  - `Outcome.count_losses` skips `Carry.BOARDED` as it skips `Production.CANCELLED`, so boarding
    counts no loss. `LastSeen.forget_dead` keeps records of buildings only, so a squad leaves no
    record to forget.
  - The fog unstamp lands in the dirty list as for any removed row.
- **UNLOAD** (carrier ids, a point). The carrier gets MOVE to the point with `carry_mode` 1.
- **Unloading** (`Carry.run`, ECONOMY). When a `carry_mode` 1 carrier has arrived (order IDLE):
  - Its passengers, in table order, are inserted on free FOOT-passable cells within
    `unload_reach_tiles` of it, by a bounded ring search counted in `stats[EXIT_SCANNED]`.
  - Each gets order IDLE and `fog_cell` -1, and an `UNLOADED` event (kind 6, view only).
  - `carry_mode` goes back to 0. Squads with no free cell, or refused by `insert_row` at
    `max_rows`, stay aboard with their records unchanged. The player tries another spot. (With
    the shipped caps, 2 x 75 units + 2 x 40 buildings = 230 rows, below `max_rows` 256, the
    refusal is a guard.)
- **Carrier death.** When a carrier dies (REMOVE), its passengers die with it. They count as lost
  units, and DIED records carry their ids at the carrier's point.
  - Note (2026-11-09, P230; ADR 0037 §7 accepted the same day): a new type field
    `carry_eject_percent` amends this rule. At 0 (both transports) it is the rule above. Above 0
    (the Bunk Wagon, 50) the passengers are put back round the carrier's point with that share of
    their hp, and only those with no free cell die.
- **Faction takes:**
  - The Derrick League's transport is slow and armoured (HEAVY) and carries 3 squads.
  - The Lumen Accord's is fast and LIGHT and carries 2.
  - Both are unarmed, high air (layer 2) and FLIGHT items, and they count toward pads.

Note (2026-11-13, P263): loading as built. It refines §8 and changes no accepted text.
- **LOAD** is `Command.Type.LOAD` (5), factory `Command.board(player, squads, carrier)`; the rule is
  `Carry.apply_load`. The valid squads are the lowest ids, up to the carrier's free slots
  (`type_carry_slots` less the squads aboard), whose move class bit is in `type_carry_classes`.
  Carrier and squads get MOVE in formation round G (`Formation.assign`), the carrier with
  `carry_mode` 0 and `order_target` 0, each squad with `order_target` = the carrier's id.
- **The mark.** A squad boards when its order is MOVE or IDLE (not ATTACK or ATTACK_MOVE) and its
  `order_target` names an own, living, complete carrier with a free slot within `load_reach_milli`.
  A plain MOVE or ATTACK_MOVE takes the mark off (`Carry.release`, one line in `Sim._apply_point`),
  and only a mark that names an own row: an ATTACK's names an enemy, so no frozen run changes. A
  carrier with no slot free clears the mark of the squad that finds it full.
- **Rules.** `load_reach_milli` is a rule int (`RulesDef`, default 0 = inert, `data/rules.tres`
  3000), in `defs_hash` and out of the state hash. `unload_reach_tiles` comes with P263b.
- **Unit cap.** `ProductionSpawn.mobile_rows` adds the squads aboard (`Carry.passengers_of`).
- **FOOT only.** A squad must be a mobile FOOT type with its bit in the mask (`Carry._boards`), so
  a carrier never boards a carrier and a harvester never boards. A new order to a carrier (MOVE,
  ATTACK_MOVE, STOP) clears the marks that name it.
- **Not in P263.** A ground carrier that cannot reach G in FOOT-only scrub (lens A's S3) goes to
  the ground-carrier row.
- **Pins.** `Carry.BOARDED` replaces `Removal.BOARDED`. No golden moved: the frozen arenas have
  `passenger_cap` 0, so `Carry.board` returns at once.

### 9. Drone squads (release 1.2 recommended)
- **A drone squad is an air unit.** It is not ground infantry that hops. A hop needs a new movement
  mode with terrain checks inside the INTEGRATE kernel. The AIR class with `low_flying` costs no
  kernel rule beyond §4 and §5.
- **It flies low** (layer 4, armour INFANTRY), in the AIR plane over rock and water. It is drawn a
  little above the ground.
- **What hits it:** anti-air, rocket squads, rifle squads and the Redoubt. Tanks, the Rail Battery,
  artillery and fighters do not (§5).
- **Production and weapon.** It is built at the barracks (INFANTRY tab) and requires an airfield.
  It has no ammo and no pad. Its own gun hits ground only.
- **Faction takes:**
  - The Derrick League's squad is three soldiers each hanging under a heavy six-rotor lifting
    drone: slow and sturdy.
  - The Lumen Accord's is three soldiers on light white kite-wing drones: fast and fragile.
  - Neither uses jet packs or rocket packs. Those are other games' looks (§16).

### 10. Engineering centre and upgrades (PRODUCTION and the readers, GDScript only)
- **Research.** A research item is queued on RESEARCH at a complete engineering centre. QUEUE is
  dropped when the upgrade's bit is set or the item is already queued. When it completes,
  `Production.run` sets the bit, rebuilds the player's `mod_*` entries and spawns nothing. Losing
  the engineering centre keeps finished research.
- **Damage.**
  - The formula: `Combat.damage(base, percent, dealt, taken) = max(1, base * percent * dealt *
    taken / 1_000_000)` in int64, and 0 when `percent` is 0.
  - With `dealt = taken = 100` it equals today's formula for every int, so no golden moves.
  - Who calls it: hitscan in `Combat.fire`, impacts in `advance_projectiles`, and the rupture with
    `dealt` 100. A shell stores `proj_owner` and `proj_weapon` already.
  - The range note in `Combat.gd`'s header (`:76-79`: "`damage * percent` ... stays far below
    2^62") is rewritten in P246 for the four-factor product. With `damage` below 2^31, `percent`
    at most 200 and each modifier at most 400 % (a data test), the product stays below 2^56.
- **Ammo.** `Air.run` reads `mod_ammo`.
- **The rule for later upgrades.** An upgrade may change only stats read in GDScript-only phases:
  damage, ammo, reload, repair and build time. Range, speed and sight live in the TARGETING,
  INTEGRATE and FOG kernels and need a plan row with that cost. If FIRE or PROJECTILES is ever
  ported (ADR 0013 §1, P42n), the `mod_*` tables join that kernel's checked list.

### 11. Space centre and the satellite (map reveal)
Rewritten at acceptance (P230, 2026-11-09) for Michael's answer 3 B: the sweep lasts until the
space centre is destroyed. The draft's timed sweep and its recharge are gone; question 3 keeps the
options as they were asked.
- **Kind 3, REVEAL: one charge, no recharge.** The space centre charges like the other strike
  buildings: `charge_ticks` from completion (starting 2,700, 3 minutes). A blackout makes it
  offline, and low power does not pause the charge. A fired sweep lasts while that building
  stands, so there is nothing to recharge.
- **State (player block, hashed; §3).**
  - `reveal_site[p]`: the id of the space centre that fired the sweep, 0 = no sweep.
  - `reveal[p]`: 0 off, 1 on (the fog is lifted), 2 paused.
  - `reveal_stamped[p]` stays derived. Both hashed values replace the draft's `reveal_until`.
- **Firing.** A valid SUPERWEAPON on a REVEAL building (the existing checks: own, complete,
  charged, online; payload empty, point ignored) is taken only while `reveal_site[p]` is 0.
  - It sets `reveal_site[p]` to the building's id and `reveal[p]` to 1.
  - It appends `[STRIKE, building id, 0, 0, 3, owner, 0, 0]`: no landing tick, because the sweep
    has no end.
  - It does not set `ready_tick` again. While `reveal_site[p]` is not 0, every SUPERWEAPON on a
    REVEAL building is dropped. A second space centre is a spare: it can fire only after the first
    is gone.
  - It does not touch `strike_tick`, so it never blocks a rupture. It is also never blocked by
    one, but only because P233 puts the kind-3 branch first:
    - Today `Strike.apply_superweapon` (`Strike.gd:112`) drops every SUPERWEAPON while
      `strike_tick[player]` is not 0.
    - P233 looks up the building first and, for kind REVEAL, skips the pending-rupture test. Kinds
      1 and 2 keep it unchanged.
    - A test fires a sweep while the same player's rupture is pending.
- **The fog contract.**
  - `visible[p]` = the player's row discs + `reveal_stamped[p]` on every cell.
  - `FogGrid.reveal(player, delta)` adds `delta` to the whole block. Where a count rises above 0
    it sets `explored` to 1. It lists the cells that flip, sets `dirty_full` when the list is full
    and bumps `version`. It is GDScript only and allocates nothing.
- **`Reveal.run`** sits in REMOVE, after `FogUpdate.begin` and `remove_dead` and before
  `FogUpdate.run`. It must come after `begin`, so the flips are not cleared on the player's fog
  turn. Per player whose `reveal_site` is not 0, with no pass over the rows:
  - `row` = `world.index_of(reveal_site[p])`, a binary search over the ids.
  - At -1 the space centre is gone (destroyed, or sold under ADR 0037 §3): `reveal_site[p]` and
    `reveal[p]` become 0. The sweep is over. A new space centre charges from its completion.
  - Otherwise `reveal[p]` becomes 1 when the row is online (`offline_until` not above the stamp
    `world.tick + 1`, as in `Strike`) and the player is not on low power, else 2. Low power is
    `Power.is_low` on the totals that `Combat.fire` read in this step, so the sweep and the
    player's defences go dark on the same steps.
  - If `reveal[p] == 1` differs from `reveal_stamped[p]`, call `reveal(p, ±1)`.

  So at every step end `reveal_stamped[p] == (reveal[p] == 1)`. A sweep fired by a command of tick
  c is stamped from the end of step c on, unless it is already paused there. The cost is one
  binary search per player per step while a sweep stands, with no allocation.
- **Blackout and low power pause the sweep.** This was the lead's recommendation, taken at
  acceptance. It matches the GDD: low power puts defences offline, and the Dusk Array's blackout
  silences them.
  - While paused, `visible` falls back to the player's own discs at once. `explored` keeps what the
    sweep showed, and `LastSeen` keeps the ghosts it recorded.
  - The sweep comes back by itself in the first REMOVE after the blackout ends or the power
    returns. It needs no Command and no new charge.
  - Damage that does not destroy the space centre changes nothing.
- **What the enemy sees.**
  - **The warning.** The STRIKE record of kind 3 gives every other player the strike warning
    (the toast and its line), once, as the Deep Bore's warning does.
  - **The indicator.** While an enemy's `reveal` is 1, a satellite badge stays lit on the HUD.
    While it is 2 the badge shows paused (dimmed, with a pause mark: never colour alone). At 0 the
    badge goes. P235 places it in ADR 0025's corners. The owner sees on or paused on its own
    strike button.
  - `PlayerView.reveal_state(player)` (0, 1 or 2) is public for every player. So the pause is
    public too: it tells the enemy that the space centre is blacked out or that its owner is short
    of power. This is accepted. It is the counterplay's feedback ("did my blackout work?"), and
    the AI reads the same value (Pillar 4 both ways).
- **Rebuilding `visible`.** Every rebuild of `visible` from hashed state compares no tick, power
  or offline value: it stamps the reveal for each player whose `reveal` is 1. That is
  `World.prepare()` on a fresh World (it returns at once once `prepared` is set, `World.gd:677`,
  so a running World is never re-stamped) and the rebuild test. The test compares the result with
  the live array after every step of a sweep, across a pause and a resume, and after a replay to a
  checkpoint inside one, on and paused. A snapshot copies `visible` (`FogGrid.copy_into`) and
  needs no rebuild.
- **What follows with no further change:**
  - TARGETING (twin and kernel), `Targeting.sees`, `PlayerView.seen_rows`, `LastSeen` (the sweep
    records every enemy building as a ghost), the radar and the fog view.
  - The FOG kernel is unchanged.
  - `explored` stays all 1 afterwards.
- **Counterplay.** The target sees the warning and the indicator. Destroying (or, for its owner,
  selling) the space centre ends the sweep. A Dusk Array blackout on it, or cutting its owner's
  power, pauses it.
- **The AI.** `PlayerView.reveal_state` is public. The AI's own sweep arrives through
  `seen_rows`. This keeps Pillar 4: vision from its own building, by the human's rule.
- **Duration (answer 3 B).** No timer. A sweep fired at minute 6 lifts the fog for the rest of the
  match unless the enemy answers it. The checks on it are the price (2,000), the 3-minute charge,
  the warning, the indicator and the pause. The balance run watches whether it decides matches.
- Note (2026-11-09, P230 fix 1, after touch-ux-dev's docs lens): a SUPERWEAPON on a REVEAL
  building is also refused while its owner is on low power (`Power.is_low`, as `Reveal.run`
  reads it), so the single charge is never spent into a sweep that would pause at once. The
  strike button dims and shows the reason. The pause rule for a standing sweep is unchanged.

Note (2026-11-12, P233): as built. It changes no accepted rule.
- `PlayerView.reveal_state` is a typed `PackedInt32Array` field, a copy of `World.reveal` indexed by
  player (entry 0 is neutral), not a method: a new per-player fact is a field, and gdlint's limit
  of 20 public methods on `PlayerView` stands. A caller checks the size itself. `Reveal.State` is
  `OFF` 0, `ON` 1, `PAUSED` 2.
- The stamp is GDScript in REMOVE: `Reveal.run` sits inside the REMOVE mark, after `remove_dead` and
  before `FogUpdate.run`. The sweep needs no change to the FOG or TARGETING kernel or to
  `world_access.h`, because the FOG phase only adds and removes discs to the `visible` counts and
  never rebuilds them, so the whole-map +1 survives every stamp, unstamp and kernel call, and
  TARGETING reads `visible` as it stands. (P238 changed the TARGETING kernel for the layer test of
  §5, which reads no sweep state.) A lockstep case and an armed-unit case pin it.
- There is no `reveal_stamped` array in the World and none in `DERIVED_ARRAYS` or
  `MatchSnapshot.NOT_COPIED`. The flag is `FogGrid.revealed`, per player, beside `visible`:
  `FogGrid.reveal` sets and clears it, `configure()` zeroes it, `copy_into` copies it, and
  `WorldLoad.stamp_fog` (called by `prepare()`) sets it from the hashed `reveal` alone.
- A rebuild of a running World must rebuild the power totals as the last step left them (`Power.run`
  at that step's stamp), not only `visible`: the low-power pause and the SUPERWEAPON drop read them
  and write hashed state. `prepare()` of a fresh World leaves both totals 0, which is right there.
  A test pins both the rebuild that matches and the one that does not.
- "After a replay to a checkpoint inside a sweep, on and paused" is met by a twin run compared with
  `hash_parts` after every step, and a rebuild of `visible` from the hashed state compared with the
  live fog after every step across the pause, plus a `prepare()` of a World that holds a standing
  sweep of each player. A replay through a sweep (`Replay.play` to a checkpoint inside one) needs
  P234's space-centre data, because no shipped scenario has a space centre before it; P234 owns
  that case, and it lands with the plan's Determinism replay test.
- Where sections 3 and 11 say `reveal_stamped[p]`, read `fog.revealed[p - 1]` (P233).
- P235 must move `reveal` and `reveal_site` from `MatchSnapshot.NOT_COPIED` to COPIED: the view
  reads only the snapshot, so the badge needs `reveal` and the owner's strike button needs
  `reveal_site`. Done in P235.

Note (2026-11-13, P235): as built. It changes no accepted rule.
- **The warning.** There is no toast: a text line, "Enemy sweep on you", stands beside the badge for
  `reveal_warn_ms` (5000, `data/life_settings.tres`), once per kind-3 STRIKE record of another
  player. Its clock runs only while the badge can be seen, so a drawer, the full map or the pause
  menu over the column holds it. Accepted gap: a pinned full map hides the badge and the line for as
  long as it stays pinned (the column is under the map).
- **The badge.** 48 dp, information only (no touch), a gap above the topmost part of the right
  column (the Ready chip upright, else the strike button, else BUILD), hidden under the drawer, the
  full map and the pause menu. The line stands left of it, 160 to 220 dp, on the `HudPanel` plate,
  and is left out below 160 dp, where the badge shows alone. With several enemies, on beats paused.
- **One strike button (Michael, 2026-11-13).** A space centre whose owner's sweep stands, on or
  paused, never binds (a fired centre keeps its `ready_tick` and the sim drops the spare). A
  construction site never binds. A sweep ignores a pending rupture. A low-power refusal ranks after
  a ready building and before one that still charges. With no other strike building the button
  shows the sweep, "On" or "Paused"; otherwise a satellite mark (and a pause mark) sits on the other
  building's plate. A REVEAL building has no aim: the check mark is lit at once and the point is
  (0, 0). While an aim is open a tie stays with the building it began on, and any other binding ends
  the aim.
- **The fade.** `reveal_fade_ms` (600), the same both ways: the fog fades away when the own sweep
  starts or comes back and fades in when it pauses. It snaps on a gap in the ticks, a new match,
  another player and a new explored alpha.
- **The look.** The sweep's look is the fade plus the HUD; `StrikeFx` plays nothing for kind 3, and
  the models' `launch` emitter is not wired (§16: no rocket launch).

### 12. Commands and touch, per unit (touch-ui-rules: 48 dp, portrait and landscape)
| Unit | Gestures | New HUD |
| --- | --- | --- |
| Fighter, bomber | tap to select: the pick radius is at least 24 dp round the lifted centre (the touch skill's rule); box and double-tap as for units; tap an enemy = ATTACK (a target the weapon cannot hit is not attacked: the tap selects it, as a tap on an own unit does); tap ground = MOVE | a "Home" button (48 dp) in the command bar while aircraft are selected: REPAIR to each aircraft's own airfield (go home, reload, repair) |
| Transport | select as above; a loaded transport shows pips (passengers) on its chip | an "Unload" button (48 dp) while a loaded transport is selected: tap it, then tap ground = UNLOAD at that point (a chevron, with the existing check mark and X beside it, as for a strike aim) |
| Rifle and rocket squads (1.2) | as today | a "Board" button (48 dp) while squads are selected and the player owns a transport: tap it, then tap an own transport = LOAD (the check mark and X as above) |
| Drone squad | as any squad | none |
| Satellite | the strike button: tap the ready button, then the check mark; no map tap | the warning once for every other player, then an indicator badge while the sweep is on or paused (§11); the owner's strike button shows on or paused |

- **Today's tap rule stays.** A tap on an own unit or building selects it, whatever is selected,
  so a tap on an own airfield or transport always selects it. REPAIR and LOAD come only from the
  command-bar buttons above, and Board and Unload take one target tap in the strike aim's pattern.
  A carrier is a unit, so no tap on a building loads anything.
- **Ground units under a hovering aircraft.** The aircraft is picked at its lifted point, so a
  ground unit beneath it stays tappable at its own point. Where the two pick discs overlap (a low
  drone squad's lift is small), the flyer wins the tap, and the ground unit is reached by a box
  select or a double-tap on another of its type.
- **The skill text needs Michael's yes.** The Home, Board and Unload buttons and their aims are new
  `touch-ui-rules` text: the command bar's buttons and the aim modes. That skill edit needs
  Michael's explicit yes. The lead asks for it with the acceptance (P230), and P244 and P265 wait
  for it.
- Note (2026-11-09, P230; ADR 0037 accepted the same day): Board and Unload also serve ADR 0037's
  ground carriers (the Bunk Wagon and the Linecar), with the same aims. ADR 0037 adds the Repair,
  Mend, Sell, Mine and Hold buttons. The draft skill text for all of them is in the plan's section
  "touch-ui-rules text for Michael's yes (P230)".
- Note (2026-11-09, P230 fix 1, after touch-ux-dev's docs lens): "48 dp" in the table above
  reads "at least 48 dp; `CommandBar.ORDER_DP` 56 x 64". The fighter row's "the tap selects it,
  as a tap on an own unit does" is replaced: with units selected, a tap on an enemy that none of
  them can hit does nothing (a short shake, the selection kept), and a mixed selection attacks
  with the rows that can hit. The flyer wins an overlapping pick only within one pick rank, so
  with own units selected an enemy ground unit still beats an own flyer; a lone ground unit
  hidden under a flyer is reached by a box only. Outside an open aim a tap on an own unit or
  building selects it. The aims place their check mark and X by `GhostControls`' column rule
  beside the aimed point, not in the strike aim's row.
- Note (2026-11-09, P230, after fix 1): the `touch-ui-rules` text (Home, Board, Unload and ADR
  0037's buttons, the aims, the picking) is accepted, Michael's "ja til touch-teksten", and
  applied to `.claude/skills/touch-ui-rules/SKILL.md`. P244 and P265 no longer wait for it.
- **HOW_TO_PLAY.** Each row is added in the PR that ships it. Teach: aircraft go home to reload,
  the Home button, Board and Unload, and the satellite.

### 13. Native kernels (ADR 0013): edits, no new port
| Kernel | Edit | Test (row) |
| --- | --- | --- |
| all | `MOVE_CLASSES` 3 -> 4 in `bind/world_access.h:54`, `core/fixed_math.cpp:9` and `core/integrate.cpp:14`; P232 declares the X-list rows of `type_layer_bit` (TARGETING and SEPARATION phase flags) and `weapon_targets` (TARGETING) once in `world_access.h` | the size checks, every lockstep, the sanitizer cases with `KNOWN_FORMATS` in `native/sim_kernels/sanitizer/dump.h` gaining 6 (P262: 7), and `NativeKernels.self_check` (P232) |
| FLOW | none; `classes` 4, never an AIR key | a world with aircraft asks for no AIR key (P232) |
| INTEGRATE | none (the plane is open) | an aircraft straight over rock and a footprint (P240) |
| TARGETING | reads `weapon_targets` and `type_layer_bit` (declared in P232); the layer test in acquisition and the ATTACK lock | mixed layers, rockets on aircraft, rifles on drone squads, an unhittable lock (P238) |
| SEPARATION | the same-layer test, reading `type_layer_bit` (declared in P232) | stacked aircraft over tanks, drone squads over infantry (P240) |
| FOG | none | a reveal while discs move (P233) |

Carriers need no kernel edit, because boarded squads are not rows. If P262's check fails, there is
one TARGETING edit (§8). Reveal, ammo, reload, repair, research, damage modifiers and carrying have
one version each, in GDScript. The port rule (ADR 0013 §1) is read again at the `perf_air` line
(P253).

### 14. AI (ADR 0030's managers; no new manager)
- **What the AI reads.** P232 adds `type_layer_bit` and `weapon_targets` to `PlayerView` (rules,
  which no fog hides) and to `MatchSnapshot`'s field lists (`game/core/MatchSnapshot.gd`, for the
  view and input). P250 makes the counter choices layer-aware: today `AiProduction.gd:302` and
  `AiArmy.gd:701` pick counters by `type_vs_armour` alone, and would field tanks against bombers.
- **Fairness.** Every target comes from `seen_rows` or ghosts. Every act is a Command a human could
  send. Values live in `OpponentDef` and `AiDifficultyDef`. Easy builds no space centre, no
  engineering centre and no transport.
- **Production.**
  - Build-order tiers: the airfield after the radar, then one anti-air building per
    `aa_per_seen_aircraft` seen enemy aircraft, the engineering centre, and the space centre on
    Normal and Hard.
  - The unit mix: fighters weighted by seen enemy aircraft, rockets and rifles weighted up while
    enemy air is seen, and drone squads in the mix when the map's `cliff_share` of the route is
    high.
- **Intel.** Counts seen enemy aircraft, drone squads and anti-air (rows and ghosts). A seen
  airfield is a high-value target.
- **Army.**
  - Bombers raid as a group of `raid_size`. The target is the most valuable seen or ghost
    building with the fewest seen anti-air within `raid_aa_radius`. The next raid waits for full
    ammo.
  - Fighters guard the base zone and escort raids on Hard.
  - Damaged aircraft are sent home with REPAIR below `air_retreat_percent`.
- **Drops (1.2).** On Normal and Hard, a transport loads `drop_squads` squads and unloads beside a
  seen or ghost refinery or harvester path, away from seen anti-air. Drone squads harass harvesters
  across cliffs.
- **Strikes** (amended at acceptance, P230, for answers 3 B and 4 A). Normal and Hard fire the
  sweep as soon as it is charged: it lasts, so waiting gains nothing, and `reveal_blind_ticks` is
  dropped. While an enemy's `reveal_state` is 1, move the staging point by one step, and make a
  seen or ghost enemy space centre the first target of the bomber raids and of the AI's own
  blackout. Easy builds no space centre.
- **Research.** In data order once the engineering centre stands and credits exceed
  `research_floor`.
- **Size and think cost.** Three rows for 1.1 (about 900 lines) and one for 1.2 (about 300). The
  think cost is re-read on `perf_ai`. During a sweep `seen_rows` can hold every enemy row, and the
  counted caps bound the work.

### 15. View, art and the atlas page
- **Layers.**
  - `AirLayer` at z 20 (reserved by ADR 0023 §9), above `WorldSort` (10) and under AirFx (25) and
    the bars (30). High and low air are one layer, sorted by ground y inside it.
  - Shadows on a ground node at z 2.
  - That is +2 draw calls on the forecast.
- **Drawing rules.**
  - An enemy flyer is drawn only where its cell is seen.
  - Flyers bob from `LifeClock` (off with reduced effects).
  - A dying aircraft falls along its heading and bursts on the ground. A boarding squad climbs
    into the transport (DIED flag 2).
- **Frames.** No flyer has damage stages or animation frames.

  | Unit | Directions | Frames | Cell at bake 1.0 (approx.) | Page rows, both factions with shadows |
  | --- | --- | --- | --- | --- |
  | Fighter | 16 | body | 64 x 40 | ~50 |
  | Bomber | 16 | body | 88 x 52 | ~65 |
  | Transport (1.2) | 16 | body (fans as static discs) | 96 x 56 | ~70 |
  | Drone squad (1.2) | 8 (infantry steps) | three figures with their drones | 48 x 52 | ~35 |
  | 4 new buildings per faction | 1 view | whole + 2 damage stages at 0.75 (ADR 0028) | 1x1 to 3x3 | ~900-1,300 |
- **The page rule.** Items of the y-sorted world stay on one page, because two textures
  interleaved in a y-sort break the batch at every switch. Page 2 may hold only unsorted layers:
  AirLayer and its shadows, DecalLayer (craters, building shadows) and effects.
- **The budget.** Flyers come to about 220 rows and go on page 2. The new buildings do not fit on
  page 1 (about 130 rows free after ADR 0035). P237 (art-director) measures before any art row:
  - (a) move DecalLayer and every shadow to page 2;
  - (b) a lower damage-stage scale;
  - (c) no stage-1 picture for the new buildings.

  It reports rows, bake time and texture memory: page 2 is up to 64 MiB of RGBA8 at 4,096 x
  4,096, about 22 MiB at 1,400 rows. Michael chooses if (a) is not enough.

- **P237 note (2026-11-11, art-director; changes no accepted text above).** Measured on the committed
  sheets, cross-faction match, bake 1.0, desktop (the phone read 1,276 ms for the base arena before):

  | Group on page 1 (alone) | Rows | MiB RGBA8 | Bake ms |
  | --- | --- | --- | --- |
  | Building body (hull, head, anim) | 958 | 15.0 | 138 |
  | Building `dmg1` / `dmg2` | 202 / 268 | 3.2 / 4.2 | 31 / 46 |
  | Building shadows | 382 | 6.0 | 21 |
  | Vehicle body / shadows | 1,022 / 628 | 16.0 / 9.8 | 312 / 80 |
  | Infantry body / shadows | 468 / 66 | 7.3 / 1.0 | 476 / 15 |
  | Neutral scars | 44 | 0.7 | 2 |

  Groups packed alone add up to more than the real page. Before: one page of 3,550 rows (55.5 MiB,
  bake about 1.1 s). **Option (a) is chosen** (the lead, 2026-11-11) and built by P237: every cast
  shadow, units' and buildings', is on page 2 (`IsoAtlas.PAGE_UNSORTED`; `page_of`, `texture_for`,
  `texture_at`). Page 1 is now 2,659 rows (41.5 MiB; mirrors 2,542 and 2,650), page 2 is 1,040 rows
  (16.2 MiB; mirrors 566 and 622), 57.8 MiB together. Both pages keep the 3,584 budget (ADR 0027
  section 4). Draw calls: the shadows draw at z 1 and z 2, outside the sort, and were their own calls
  before with the fog drawn; compare `draw_calls_p95` across the split in the perf arena's mode
  "all" only (without fog or rings the shadows may have merged into the sorted batch, +1 call). Option
  (c) is already ADR 0034's rule (P202 drops `dmg1`, 142 rows). Option (b) was skipped:
  `DAMAGE_SCALE` 0.5 saves only about 48 rows.
  Room on page 1 against the 3,584 budget: 925 rows now, about 1,064 after P202. The demand estimate
  of ADR 0036's four buildings (about 610-880 rows without shadows and `dmg1`) plus ADR 0037's
  ground set (about 240 in wave 2 and 245-490 in wave 3) is about 1,095-1,610, so the capacity
  question was put to Michael, with three ways out: (1) 8 directions for the four new ground
  vehicles, (2) a page-1 budget of 3,840 rows, (3) bake scale 0.875.
  **Michael's answer (2026-11-11):** "Ja til 2 kun hvis nødvendigt" ("Yes to 2, only if necessary").
  Read by the lead: (2) the page-1 budget may go from 3,584 to 3,840 rows, only when a later art row
  actually needs it (P237 does not raise it); (1) is not accepted, so the new ground vehicles stay
  at 16 directions; (3) is not accepted, so the bake scale stays at 1.0. If a later row still does
  not fit at 3,840, it returns to the lead for other options, such as moving more parts to page 2 or
  a third page.
  **Re-pin rule.** Every art row with a model and its shadow frames (P236, P239b, P245, P245b, P249,
  P266, P279, P280, P291, P292, the flyers) moves both `TODAY_*` and `TODAY2_*` in
  `tests/view/test_iso_atlas_budget.gd` in its own PR; the polish rows P203 and P204 move `TODAY2_*`
  (and `TODAY_*` only if a model changes); P202 moves `TODAY_*` only.
  **Forecast and check.** Page 2 grows with the flyers (about 220 rows), the new buildings' and
  units' shadows and P204's per-player unit shadows (about +630): about 2,400 rows, 38 MiB. With the
  sorted page that is about 94 MiB of textures at the end; the phone check is P243's (the perf card
  now prints both pages, `atlas_page` and `atlas_page2`).
  **`page_of` is keyed by the part only.** The flyers' `hull` belongs on page 2, which that key
  cannot say; P243 re-keys it (by category or by sheet and part). A sprite's texture follows its
  region (`texture_at(base)`: `WorldSort.show_base`, `GhostLayer`), so a part moved within
  `UNSORTED_PARTS` needs no layer edit. The sites that still pair by `texture_for(part)` with a
  region of that part (`WorldSort.dress`, `BuildingLayer`'s patch, the gallery) are replaced by
  P243's sheet-keyed flyer pages.
- **P236 note (2026-11-12, P26br, the lead; changes no accepted text above).** The space centres
  (P236) cost more than the estimate above. Page 1 grew by 334 rows on the cross-faction page
  (2,659 -> 2,993) and by 336 and 260 on the Derrick and Lumen mirrors (2,878 and 2,910); page 2 grew
  by 76 (1,040 -> 1,116). The estimate allowed about 152-220 rows per building pair. Room on page 1
  against 3,584 is now 591 rows (cross), 706 and 674 (mirrors). On today's sheets P202 frees about
  141, 102 and 128 rows (cross 2,852, mirrors 2,776 and 2,782), so the cross page stays the tightest.
  The forecast depends on what the later art rows really cost:
  - If the three remaining ADR 0036 buildings (P239b, P245b, P249) cost what P236 did (about 334
    rows a pair), page 1 fills at the second or third of them, even at 3,840: with P202,
    2,852 + 3 x 334 = 3,854.
  - At the estimate's high case (about 660 for the three) and without P202, it passes 3,840 around
    P280 (2,993 + 660 + 105 + 135 = 3,893).
  So P202 merges before the next of P239b, P245b and P249, and the lead puts the next lever (more
  parts on page 2, or a third page) to Michael before that row starts, not when a row fails. P245
  merges after P243 has re-keyed `page_of`; before that the fighter and bomber hulls would bake on
  page 1 (about +100 rows).

### 16. Legal screen (ADR 0023 §13 extended)
- **Method.** Names were checked against the games of ADR 0023 §13 and against real military
  aircraft, vehicles and programmes, from the architect's knowledge. "No known hit" is not a
  trademark search: the lead adds the chosen names to Phase 7's search. Names fit ADR 0032's one
  line (at most about 11 characters; the data rows run the width test).
- **Refused names:**
  - airfield, airstrip, helipad: TD, RA, Generals;
  - Tech Center, Battle Lab, Tech Lab: RA, RA2, StarCraft;
  - GPS Satellite: RA;
  - SAM Site, Flak Cannon: TD, RA2;
  - Chinook and Orca: TD transports;
  - Nighthawk: RA2 transport, and a real aircraft;
  - Jumpjet: TS infantry;
  - Rocketeer: RA2 infantry;
  - Reaper: StarCraft II;
  - Dragonfly: a real aircraft;
  - Kestrel: a rocket, and this repo's map;
  - MiG, Yak, Hind, Longbow, Harrier, Hawk, Wildcat, Prism, Stargate, Overwatch;
  - Overcast: an old programme name.
- **Looks refused:**
  - tandem twin-rotor transports (TD and RA's Chinook);
  - jet-pack or rocket-pack infantry (TS, RA2);
  - a satellite dish uplink in RA's GPS look;
  - a "tech" building with RA's dome.

  The drawer tab is not called "Air".
- **Candidates.** Two per item per faction, listed in the GDD section. Michael picks (question 1).
- **Note (2026-11-12, P26br, the lead; changes no accepted text above).** Like every chosen name,
  the space centres' names from the GDD, Skyrig (Derrick League) and Zenith (Lumen Accord), go to
  Phase 7's trademark search (ROADMAP Phase 7). "Zenith" is a common word and a much-registered
  mark, so it is checked first. P236's art review found no RTS building or unit of either name and
  no look from the list above. RA's GPS Satellite (a whole-map reveal launched as a rocket) is the
  known precedent for the Reveal. Its name, dish and dome are refused above, and the Reveal's look
  (P235's sweep) is not a rocket launch either, although both models carry a `launch` emitter.

## Consequences
- **Gains:**
  - Michael's seven items, with three new Commands that the ground design shares. Replays,
    AI-vs-AI and multiplayer stay possible.
  - The reveal is one GDScript stamp that every reader, kernel included, gets for free.
  - Carrying needs no kernel change, because boarded squads leave the table.
  - Upgrades, ammo, reloading and repair have one version each.
  - Aircraft cost no flow fields.
- **Costs:**
  - Two layout rows and re-pins (one if everything ships at once).
  - Three kernel edits with lockstep cases.
  - `TABS` 5.
  - A second atlas page or a smaller damage bake.
  - About 38 rows, about 6,900 production lines (about 5,190 for 1.1 and 1,670 for 1.2) plus
    about 175-250 C++, and 16 generated models (the plan's size estimate; 39 rows with P232c,
    2026-11-12, P26br).
  - 20 unit types for ADR 0031's check 4 instead of 12 (16 after 1.1, 20 after 1.2: per faction
    two aircraft, then a transport and a drone squad), and longer balance runs.
- **Risks:**
  - Air dominance on small maps (rockets have mask 7, anti-air comes after the barracks).
  - A sweep that lasts until the space centre falls ends the fog game for a player who cannot
    answer it (answer 3 B; §11's counters).
  - Page memory on the web preview.
  - The AI's think cost during a sweep.
  - Fighters or transports may fail "built in at least half the matches" (the AI's build order
    must include them).
  - `insert_row` correctness: covered by the replay test and a hash test over load and unload
    cycles.
- **Out of scope:**
  - runways, landing and fuel;
  - naval units;
  - stealth and jamming;
  - paratroopers;
  - an air-to-ground fighter;
  - range, speed or sight upgrades;
  - walls and gates;
  - carrying vehicles;
  - a drone squad that boards.

## Alternatives considered
- **A `layer` column with a branch in every kernel.** Not taken: the AIR plane plus one
  `type_layer_bit` table keeps INTEGRATE and FLOW rule-free.
- **Runways, landing and fuel.** Not taken: more state, hard to read on a phone, more AI steps.
- **Carried rows kept in the table with a flag.** Not taken: every kernel would have to skip them
  (four twin edits).
- **Drone infantry as hopping ground units.** Not taken: a new INTEGRATE movement mode.
- **A fifth armour class.** Not taken.
- **A reveal as huge discs.** Not taken: FOG work on every turn.
- **A RESEARCH Command.** Not taken: it duplicates the queue.
- **Repair of aircraft at the ground repair building too.** Not taken now: it is a data flag later
  (§7).

## Questions for Michael
1. **Names.** The GDD section lists two options per item per faction. A = take every first
   option; otherwise name the ones to swap.
2. **When.**
   - A: everything after the Phase 4 gate, before Phase 5 (launch about 3-4 weeks later).
   - B (recommended): launch without it; update 1.1 (airfield, fighter, bomber, anti-air,
     satellite, research) soon after launch, and 1.2 (transport, drone squads) together with the
     ground design's infantry carrier.
   - C: 1.1 and 1.2 as one update.
3. **How long the satellite lasts.**
   - A (recommended): 45 seconds, then 3 minutes to recharge.
   - B: until the space centre is destroyed.
   - C: the rest of the match.
4. **The computer and the satellite.**
   - A (recommended): Normal and Hard use it by the same rules.
   - B: Hard only.
   - C: never.
5. **Research for the bombers.**
   - A (recommended): heavier bombs (+25 % damage) and armour (-25 % damage taken).
   - B: heavier bombs and one more bomb per trip.
   - C: all three.

Answered by Michael on 2026-11-09 (chat): 1 **A** (every first name), 2 **A** (everything after
the Phase 4 gate, before Phase 5; the launch moves about 3-4 weeks), 3 **B** (the sweep lasts
until the space centre is destroyed), 4 **A** (Normal and Hard use it by the same rules), 5 **A**
(heavier bombs and armour). P230 adapts the reveal rule to answer 3 (no recharge timer; what a
blackout or low power does to a standing sweep), moves "air units" out of the GDD's "Not in
version 1" list and adds the ROADMAP phase. It also asks Michael's yes to the `touch-ui-rules` text
for the Home, Board and Unload buttons.

Applied 2026-11-09 in P230: §11 holds the 3 B rule (pause on blackout and low power, the warning
and the indicator), the GDD and the ROADMAP (Phase 4b) are updated, and the skill text waits in
the plan for Michael's yes.
