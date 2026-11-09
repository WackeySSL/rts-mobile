# ADR 0036: The air layer, anti-air, transports, drone squads, the map reveal and upgrades

**In short, for Michael:** each side gets four new buildings and four new kinds of unit:
- The buildings: an airfield, an anti-air gun, an engineering centre that researches better
  bombers, and a space centre whose satellite lifts the fog over the whole map for a while.
- The units:
  - a fighter;
  - a bomber;
  - a transport aircraft that carries infantry squads over rock and water;
  - a drone squad: soldiers carried by drones at low height.

Aircraft fly straight over everything. Only anti-air, rocket squads and fighters hit them. Rifle
squads and the anti-infantry gun can also hit the low drone squads. A bomber drops its bombs and
flies home to reload, and an aircraft is repaired on its airfield's pad. On the phone you select,
tap a target, and tap your own airfield to send aircraft home. A loaded transport has an "Unload"
button. The satellite has a button like the superweapon's. The computer plays by the same rules.

The design is ready now. The work starts after the Phase 4 gate. The recommendation is two updates
after launch:
- 1.1: airfield, fighter, bomber, anti-air, satellite and research.
- 1.2: the transport and the drone squads, together with the ground design's infantry carrier,
  which shares their loading rules.

Five questions are at the end.

Status: **proposed, 2026-11-09** (architect, branch `claude/design-air-and-tech`, base `main` at
b6bfe95). The scope addition of the same day (Michael's transport, drone squads and aircraft repair)
is folded in. Not accepted. The lead accepts it in docs row P230 of
`docs/plans/2026-11-09-air-and-tech.md` once Michael has answered. GDD: the section "Planned: air,
anti-air, engineering centre, space centre".

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
  - `BuildingDef.strike_kind` gains `Reveal = 3`. For a reveal building, `charge_ticks` is the
    recharge and `strike_ticks` the sweep. Its radius, delay and weapon are 0 or null.
- **Upgrades.** `UpgradeDef` (new Resource): `id`, `display_name`, `faction`, `cost`,
  `research_ticks`, `requires` (the engineering centre), `stat` (`DAMAGE_DEALT`, `DAMAGE_TAKEN` or
  `AMMO`), `value` (a percent, or an amount for `AMMO`) and `applies_to` (UnitDefs). They are listed
  in `FactionDef.upgrades`. Each upgrade has one level: researched or not.
- **Tabs.** `World.Tab` gains `FLIGHT = 3` and `RESEARCH = 4`, so `TABS = 5`. The airfield produces
  FLIGHT and the engineering centre produces RESEARCH. Drone squads are INFANTRY items from the
  barracks. The labels avoid "Air" (ADR 0023 §13: RA2's sidebar tabs); "Flight" and "Research" are
  recommended.

### 3. State (one layout row per release, one re-pin each)
P232 adds every column the 1.1 rules need at once, under one named exception (the next free
number, 22 at this writing): `STATE_FORMAT` 6. The carriers' state (marked "1.2") comes with P262,
the 1.2 layout row, as `STATE_FORMAT` 7 with one more re-pin. If Michael wants everything in one
release, P232 takes both and there is one re-pin. Rule rows after a layout row are hash-neutral for
the frozen arenas.

| Kind | Name | Hashed | Meaning |
| --- | --- | --- | --- |
| row | `ammo` | yes | shots left |
| row | `carry_mode` (1.2) | yes | 0 none, 1 unload on arrival |
| type | `type_layer_bit` | rules | 1 ground, 2 air, 4 low air; derived at load from move class and `low_flying` |
| type | `type_ammo`, `type_rearm_ticks`, `type_pads`, `type_upgrade`, the repair role, `type_carry_slots`, `type_carry_classes` (1.2) | rules | as §2; `type_upgrade` -1 except for research items |
| weapon | `weapon_targets` | rules | layer mask |
| player | `reveal_until`, `upgrades` | yes | §11, §10 |
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

### 4. The air layer: movement
- **The AIR move class has an open cost plane.**
  - WorldLoad and `set_terrain` fill the plane with `World.GRASS_COST`. It is structure, not
    balance.
  - `Buildings` writes footprints into the three ground planes only.
  - So `line_clear` is always true for AIR: `Movement.run` steers aircraft DIRECT and never asks
    for a flow field, INTEGRATE never slides them, and `Formation.assign` and `Buildings.aim` find
    slots over rock and buildings. The map clamp holds.
- **Kernels.** Only `MOVE_CLASSES` changes, 3 -> 4. FLOW is configured with 4 classes and never
  gets an AIR key.
- **Hovering.** Aircraft and drone squads hover. There is no landing and no fuel.
- **Separation is per layer.** A pair counts in SEPARATION only when both rows have the same
  `type_layer_bit`, so aircraft spread among themselves, drone squads among themselves, and
  neither pushes tanks. This is one comparison per pair, in the twin and the kernel.
- **Altitude is view-only.** Range, sight and pick tests use the ground point. The view draws high
  air `fly_px` up and low air `low_fly_px` up (art data), with shadows (§15).

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

### 6. Airfields: ammo, reloading and repair (`Air.run`, ECONOMY, GDScript only)
- **The aircraft cap.** A FLIGHT QUEUE is valid while living aircraft plus queued FLIGHT items are
  below the sum of `type_pads` of the player's complete airfields. A finished aircraft spawns over
  the producer's first free pad. With no free pad the head waits at 100 %, as at a blocked exit.
  Drone squads are not aircraft for the cap.
- **Home.** The producing airfield. When it dies, `Air.run` re-homes the aircraft to the lowest-id
  own complete airfield with a free pad, or sets home to 0. A homeless aircraft cannot reload or
  be repaired.
- **Ammo.** A shot of a type with `type_ammo > 0` costs 1 (`Combat.fire`). At 0 the row holds fire
  and keeps its target.
- **`Air.run`** walks `air_rows` once, after `Harvest.run`:
  - **Return.** An aircraft with ammo 0 and a home gets MOVE to its pad, through the reset
    `_apply_point` uses.
  - **Reload.** On the pad (within `repair_reach_milli` of it) with its home complete and online,
    it gains 1 ammo every `max(1, type_rearm_ticks / cap)` ticks, with cap `type_ammo + mod_ammo`.
    The tick is stamped in `ready_tick`, which mobile rows leave unused.
  - **Repair.** In the same place, on ticks with `tick % repair_period_ticks == 0`, its hp rises by
    `repair_hp` (not above max). The owner pays `ceil(cost * gained * repair_cost_percent /
    (100 * max_hp))`. There is no repair while the player cannot pay.
  - **Waiting.** A full, healthy aircraft waits over its pad. A bomber does not resume its old
    target in this version.
- **Fighters** have ammo 0 (no limit) and return only when ordered (REPAIR, §7) or when idle with
  no order.
- **Cost:** O(air rows) per tick, with no allocation.

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
    `World.insert_row`. This is GDScript, at event cadence, O(rows x columns). It keeps selection
    groups and the view's id keys.
  - **Unit cap.** Passengers count toward `unit_cap`.
- **LOAD** (unit ids = the squads, `target_id` = an own carrier). The valid squads are own FOOT
  rows whose class bit is in `carry_classes`, while slots remain.
  - The carrier gets MOVE to G, the position of the lowest-id squad.
  - Every squad gets MOVE to G with `order_target` = the carrier id: "board on arrival".
  - The same Command with the squads selected and the carrier tapped, or the carrier selected and
    a squad tapped, gives the same result.
  - P262 checks that TARGETING (twin and kernel) leaves `order_target` of a MOVE row untouched. If
    it does not, a BOARD order value takes its place with a TARGETING edit, and §13 gains a row.
- **Boarding** (`Carry.board`, in the REMOVE mark after `FogUpdate.begin`, before
  `remove_dead`). A squad boards when its carrier lives, is within `load_reach_milli` and has a
  free slot. The checks run in ascending row order.
  - The squad's record joins the table, and the row is marked for REMOVE with DIED flag 2
    ("boarded"). It counts no loss, and the view draws it climbing in, not dying.
  - The fog unstamp lands in the dirty list as for any removed row.
- **UNLOAD** (carrier ids, a point). The carrier gets MOVE to the point with `carry_mode` 1.
- **Unloading** (`Carry.run`, ECONOMY). When a `carry_mode` 1 carrier has arrived (order IDLE):
  - Its passengers, in table order, are inserted on free FOOT-passable cells within
    `unload_reach_tiles` of it, by a bounded ring search counted in `stats[EXIT_SCANNED]`.
  - Each gets order IDLE and `fog_cell` -1, and an `UNLOADED` event (kind 6, view only).
  - `carry_mode` goes back to 0. Squads with no room stay aboard, and the player tries another
    spot.
- **Carrier death.** When a carrier dies (REMOVE), its passengers die with it. They count as lost
  units, and DIED records carry their ids at the carrier's point.
- **Faction takes:**
  - The Derrick League's transport is slow and armoured (HEAVY) and carries 3 squads.
  - The Lumen Accord's is fast and LIGHT and carries 2.
  - Both are unarmed, high air (layer 2) and FLIGHT items, and they count toward pads.

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
- **Ammo.** `Air.run` reads `mod_ammo`.
- **The rule for later upgrades.** An upgrade may change only stats read in GDScript-only phases:
  damage, ammo, reload, repair and build time. Range, speed and sight live in the TARGETING,
  INTEGRATE and FOG kernels and need a plan row with that cost. If FIRE or PROJECTILES is ever
  ported (ADR 0013 §1, P42n), the `mod_*` tables join that kernel's checked list.

### 11. Space centre and the satellite (map reveal)
- **Kind 3, REVEAL.** It charges like the other strike buildings: from completion, a blackout makes
  it offline, and low power does not pause it.
  - A valid SUPERWEAPON (the existing checks, payload empty, point ignored) sets
    `reveal_until[p] = stamp + strike_ticks` (a longer sweep in progress is kept) and recharges.
  - It appends `[STRIKE, building id, 0, 0, 3, owner, reveal_until, 0]`.
  - It does not touch `strike_tick`, so it never blocks a rupture and is never blocked by one.
- **The fog contract.**
  - `visible[p]` = the player's row discs + `reveal_stamped[p]` on every cell.
  - `FogGrid.reveal(player, delta)` adds `delta` to the whole block. Where a count rises above 0
    it sets `explored` to 1. It lists the cells that flip, sets `dirty_full` when the list is full
    and bumps `version`. It is GDScript only and allocates nothing.
- **`Reveal.run`** sits in REMOVE, after `FogUpdate.begin` and `remove_dead` and before
  `FogUpdate.run`. It must come after `begin`, so the flips are not cleared on the player's fog
  turn. Per player:
  - `want` = `reveal_until > stamp` and the player owns a complete, online REVEAL building. This
    is one pass over the rows, made only while a sweep runs.
  - If `want` is false, `reveal_until` becomes 0.
  - If `want` differs from `reveal_stamped`, call `reveal(p, ±1)`.

  `World.prepare()` stamps the reveal after the discs, so the invariant holds at every step end,
  snapshot and checkpoint. A test rebuilds `visible` and compares it.
- **What follows with no further change:**
  - TARGETING (twin and kernel), `Targeting.sees`, `PlayerView.seen_rows`, `LastSeen` (the sweep
    records every enemy building as a ghost), the radar and the fog view.
  - The FOG kernel is unchanged.
  - `explored` stays all 1 afterwards.
- **Counterplay.** The target sees a warning for the whole sweep. Destroying or blacking out the
  space centre ends it at once.
- **The AI.** `PlayerView.enemy_reveal_active` is public (everyone sees the warning). The AI's own
  sweep arrives through `seen_rows`. This keeps Pillar 4: vision from its own building, by the
  human's rule.
- **Duration.** All three options are data on the same code:
  - A (recommended): a timed sweep, 675 ticks (45 s) every 2,700 (3 min).
  - B: until the space centre falls. `strike_ticks` = int32 max, ended through `want`.
  - C: the rest of the match (B with the building check off).

  A full reveal from minute 6 of an 8-10 minute match would remove the fog play for its last
  third.

### 12. Commands and touch, per unit (touch-ui-rules: 48 dp, portrait and landscape)
| Unit | Gestures | New HUD |
| --- | --- | --- |
| Fighter, bomber | tap the raised sprite to select (hit area at least 48 dp round the drawn point), box and double-tap as for units; tap an enemy = ATTACK (a target the weapon cannot hit is not offered: the tap selects it instead); tap ground = MOVE; tap an own airfield = REPAIR (go home, reload, repair) | none: the command bar already adapts to both orientations |
| Transport | squads selected + tap an own transport = LOAD; transport selected + tap an own squad = LOAD; a loaded transport shows pips (passengers) on its chip | an "Unload" button (48 dp) in the command bar while a loaded transport is selected; tap it, then tap ground = UNLOAD at that point (a chevron and the existing check mark and X beside it, as for a strike aim) |
| Drone squad | as any squad | none |
| Satellite | the strike button: tap the ready button, then the check mark; no map tap | a warning badge and line for the revealed player |

A tap on an own building with units selected currently selects the building. It becomes REPAIR or
LOAD only when that building can serve the selection (repair role, carrier). Otherwise it selects,
as today. HOW_TO_PLAY gets each row in the PR that ships it. Teach: aircraft go home to reload,
loading and unloading, the satellite.

### 13. Native kernels (ADR 0013): edits, no new port
| Kernel | Edit | Test (row) |
| --- | --- | --- |
| all | `MOVE_CLASSES` 3 -> 4 (`world_access.h`, `fixed_math.cpp`) | the size checks and every lockstep (P232) |
| FLOW | none; `classes` 4, never an AIR key | a world with aircraft asks for no AIR key (P232) |
| INTEGRATE | none (the plane is open) | an aircraft straight over rock and a footprint (P240) |
| TARGETING | `weapon_targets` and `type_layer_bit` join the checked list; the layer test in acquisition and the ATTACK lock | mixed layers, rockets on aircraft, rifles on drone squads, an unhittable lock (P238) |
| SEPARATION | the same-layer test; `type_layer_bit` joins its list | stacked aircraft over tanks, drone squads over infantry (P240) |
| FOG | none | a reveal while discs move (P233) |

Carriers need no kernel edit, because boarded squads are not rows. If P262's check fails, there is
one TARGETING edit (§8). Reveal, ammo, reload, repair, research, damage modifiers and carrying have
one version each, in GDScript. The port rule (ADR 0013 §1) is read again at the `perf_air` line
(P253).

### 14. AI (ADR 0030's managers; no new manager)
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
- **Strikes.** Fire the sweep when charged and either a wave is about to leave or no enemy building
  has been seen for `reveal_blind_ticks`. While the enemy's sweep runs, move the staging point by
  one step.
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

## Consequences
- **Gains:**
  - Michael's seven items with three new Commands shared with the ground design. Replays,
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
  - About 38 rows, about 7,500 production lines plus about 175-250 C++, and 16 generated models
    (the plan's size estimate).
  - 20 unit types for ADR 0031's check 4 instead of 12 (16 after 1.1, 20 after 1.2: per faction
    two aircraft, then a transport and a drone squad), and longer balance runs.
- **Risks:**
  - Air dominance on small maps (rockets have mask 7, anti-air comes after the barracks).
  - A reveal duration that ends the fog game (data, question 3).
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
