extends GdUnitTestSuite
## Weapons, part 1 (P42a; ADR 0009 section 4, ADR 0007 sections 3, 4 and 10): `Combat.fire` in the
## FIRE phase of `Sim.step`, after PROJECTILES and before REMOVE. Cooldowns count down, a unit with
## a ready weapon and its target in reach fires, the damage lands in the same tick (hitscan: every
## weapon of this suite has no projectile speed; the shells of a weapon with one are
## test_combat_projectiles.gd's), and a `SHOT` record holds both positions. Rows die in REMOVE,
## after every unit has fired. The group fights (the standoffs that end, an `ATTACK` until the
## target dies) are in test_combat_fights.gd.
##
## The worlds are test-built types (Rig.world_of): a shooter (type 0, infantry, 100000 hp) with a
## weapon the case builds, and an unarmed mark (type 1) of the armour class and hp the case names,
## owners 1 and 2 on the open 20 x 12 tile map, sight 7000 and acquire range 5500 (every target
## stands inside the shooter's sight: the authoring rule of the fog PR, P46b). A case that tests
## the phase alone hands the shooter its target (`world.target`) and calls `Sim.step` or
## `Combat.fire`; one that tests the chain lets TARGETING acquire it (id 1 is due at ticks 4, 9,
## ...). The shipped weapon tables are test_defs_data's.

const Rig: GDScript = preload("res://tests/sim/support/targeting_rig.gd")
const FireProbe: GDScript = preload("res://tests/sim/support/fire_view_probe.gd")
const SCENARIO_PATH: String = "res://data/scenarios/controls_test.tres"
const INFANTRY: int = World.Armour.INFANTRY
const LIGHT: int = World.Armour.LIGHT
const HEAVY: int = World.Armour.HEAVY
const BUILDING: int = World.Armour.BUILDING
const SHOT: int = World.Event.SHOT
const DIED: int = World.Event.DIED
const STRIDE: int = World.EVENT_STRIDE
const CHASE: int = World.NavMode.CHASE
const HOLD: int = World.NavMode.HOLD
## The hp of a unit that no case means to kill.
const TOUGH: int = 100000
## The cannon's reach: its range of 4500 milli, squared.
const REACH: int = 4500
## The cases that compare a SHOT record put the mark this far off the shooter's row in y, so that
## the record's two y fields are not the same number (a shooter's y read for the mark's, or the
## other way round, would show).
const SIDE: int = 500
## The shooter's weapon when a case does not name one: damage 30 against (70, 60, 35, 40) percent,
## so 18 against a light target (30 * 60 / 100), a cooldown of 25.
const GUN_VS: Array[int] = [70, 60, 35, 40]


## The shooter fires on the first tick its target is in range, then every `cooldown_ticks`: with a
## cooldown of 1, 7 and 25, in the ticks 0, c, 2c, ... of 60 (the target is handed over, so tick 0
## is the first). Each shot takes 18 hp. The cooldown is a number of the weapon table.
func test_a_unit_fires_on_the_first_tick_in_range_and_then_every_cooldown() -> void:
	for cooldown: int in [1, 7, 25]:
		var world: World = _duel(_weapon(&"gun", 30, cooldown, GUN_VS), LIGHT)
		world.target[0] = 2
		var ticks: Array[int] = []
		for tick: int in 60:
			Sim.step(world, [])
			if not _records(world, SHOT).is_empty():
				ticks.append(tick)
		var label: String = "cooldown %d" % cooldown
		assert_array(ticks).override_failure_message(label).is_equal(range(0, 60, cooldown))
		assert_int(world.hp[1]).override_failure_message(label).is_equal(TOUGH - 18 * ticks.size())


## The same through the whole tick: an idle shooter with an enemy 4000 away takes it as its target
## on its first due tick (4) and fires on that tick, then 25 ticks apart. Nothing is handed over.
func test_an_idle_unit_fires_on_the_tick_it_acquires_a_target_in_range() -> void:
	var world: World = _duel(_weapon(&"gun", 30, 25, GUN_VS), LIGHT)
	var ticks: Array[int] = []
	for tick: int in 60:
		Sim.step(world, [])
		if not _records(world, SHOT).is_empty():
			ticks.append(tick)
	assert_array(ticks).is_equal([4, 29, 54])
	assert_array(Rig.outside_sight(world)).is_empty()


## A unit that chases fires on the first tick it is in range, without waiting for HOLD: the tank
## attack-moves towards an unarmed mark 12000 away (and 500 off its row), acquires it at 5500
## (CHASE), and in the tick its step takes it inside 4500 the shot is fired from the position it
## ended on, still in CHASE. The tick before it was out of range. HOLD follows on the next tick, and
## the next shot 25 ticks later.
func test_a_chasing_unit_fires_in_the_tick_its_step_brings_it_into_range() -> void:
	var world: World = _duel(_weapon(&"gun", 30, 25, GUN_VS), LIGHT, TOUGH, 12000, SIDE)
	var order: Command = Command.attack_move(1, PackedInt32Array([1]), 16000, 6000 + SIDE)
	order.tick = 0
	var commands: Array[Command] = [order]
	var shots: Array[int] = []
	var outside: int = _d2(world, 0, 1)
	var seen: Array[int] = []
	for tick: int in 120:
		Sim.step(world, commands)
		commands.clear()
		var d2: int = _d2(world, 0, 1)
		if not _records(world, SHOT).is_empty():
			shots.append(tick)
			if shots.size() == 1:
				assert_bool(outside > REACH * REACH).is_true()
				assert_bool(d2 <= REACH * REACH).is_true()
				var record: Array = _records(world, SHOT)[0]
				assert_array(record).is_equal(
					[SHOT, 1, world.pos_x[0], world.pos_y[0], 2, 0, world.pos_x[1], world.pos_y[1]]
				)
				seen.append(world.nav_mode[0])
		elif shots.size() == 1 and seen.size() == 1:
			seen.append(world.nav_mode[0])
		outside = d2
	assert_array(seen).is_equal([CHASE, HOLD])
	assert_int(shots.size()).is_greater(2)
	assert_int(shots[1] - shots[0]).is_equal(25)
	assert_array(Rig.outside_sight(world)).is_empty()


## The hit lands in the tick of the shot, and the SHOT record holds both positions as they are in
## FIRE: the mark walks 120 east in INTEGRATE of the same tick (8000 to 8120), so the record has
## 8120 and not the 8000 it started the tick on. It is `[SHOT, shooter id, shooter x, y, target id,
## weapon index, target x, y]` and the only event of the tick; the mark stands 500 off the shooter's
## row, so the two y fields differ. The mark takes 18 hp (30 * 60 / 100).
func test_a_hit_lands_in_the_tick_of_the_shot_and_the_record_holds_both_positions() -> void:
	var world: World = _duel(_weapon(&"gun", 30, 25, GUN_VS), LIGHT, TOUGH, 4000, SIDE)
	world.target[0] = 2
	Sim.step(world, [_walk_east(world)])
	assert_int(world.pos_x[1]).is_equal(8120)
	assert_int(world.hp[1]).is_equal(TOUGH - 18)
	assert_array(world.events).is_equal([SHOT, 1, 4000, 6000, 2, 0, 8120, 6000 + SIDE])
	assert_int(world.cooldown[0]).is_equal(25)


## A hitscan kill: the hit leaves the mark at hp -8 for the rest of FIRE (one hit below 0), REMOVE
## takes the row away in the same tick, and the SHOT record keeps the mark's position, the same as
## the DIED record that follows it. Nothing is rewritten in the shooter's row: its target is the id
## that is gone, which the next tick looks up and does not find, without a shot or an error.
func test_a_kill_shot_still_carries_the_targets_position_after_the_row_is_removed() -> void:
	var direct: World = _duel(_weapon(&"gun", 30, 25, GUN_VS), LIGHT, 10)
	direct.target[0] = 2
	Combat.fire(direct)
	assert_int(direct.hp[1]).is_equal(10 - 18)
	assert_int(direct.unit_count()).is_equal(2)
	var world: World = _duel(_weapon(&"gun", 30, 25, GUN_VS), LIGHT, 10, 4000, SIDE)
	world.target[0] = 2
	Sim.step(world, [_walk_east(world)])
	assert_int(world.unit_count()).is_equal(1)
	assert_int(world.index_of(2)).is_equal(-1)
	var y: int = 6000 + SIDE
	assert_array(world.events).is_equal(
		[SHOT, 1, 4000, 6000, 2, 0, 8120, y, DIED, 2, 8120, y, 1, 2, 0, 0]
	)
	assert_int(world.target[0]).is_equal(2)
	Sim.step(world, [])
	assert_array(world.events).is_empty()
	assert_int(world.cooldown[0]).is_equal(24)


## The percent rule for the four armour classes, with three weapons in one World (the mark is type 0
## and the shooters types 1 to 3, so the SHOT record's weapon index 0 to 2 is not the type index):
## damage * percent / 100 truncated, and at least 1 when the percent is above 0, else 0.
## - 30 against (70, 60, 35, 40): 21, 18, 10 (10.5), 12;
## - 12 against (100, 10, 5, 0): 12, 1 (1.2), 1 (0.6 raised to 1), 0;
## - 12 against (200, 150, 99, 1): 24, 18, 11 (11.88), 1 (0.12 raised to 1).
## The heavy and building marks are test-only types built in code (no shipped unit has them yet).
func test_damage_is_the_percent_of_the_weapon_for_each_of_the_four_armour_classes() -> void:
	var weapons: Array[WeaponDef] = [
		_weapon(&"gun_a", 30, 25, GUN_VS),
		_weapon(&"gun_b", 12, 15, [100, 10, 5, 0]),
		_weapon(&"gun_c", 12, 15, [200, 150, 99, 1]),
	]
	var lost: Array[Array] = [[21, 18, 10, 12], [12, 1, 1, 0], [24, 18, 11, 1]]
	for armour: int in [INFANTRY, LIGHT, HEAVY, BUILDING]:
		var defs: Array[UnitDef] = [_def(&"mark", armour, TOUGH)]
		for weapon: WeaponDef in weapons:
			defs.append(_def(StringName("shooter_" + weapon.id), INFANTRY, TOUGH, weapon))
		var world: World = Rig.world_of(defs)
		for k: int in 3:
			var y: int = 2000 + 4000 * k
			world.add_unit(1, k + 1, 3000, y)
			world.add_unit(2, 0, 7000, y)
			world.target[2 * k] = 2 * k + 2
		Combat.fire(world)
		var label: String = "armour %d" % armour
		for k: int in 3:
			assert_int(TOUGH - world.hp[2 * k + 1]).override_failure_message(label).is_equal(
				lost[k][armour]
			)
		var weapon_of_shot: Array[int] = []
		for record: Array in _records(world, SHOT):
			weapon_of_shot.append(record[5])
		assert_array(weapon_of_shot).override_failure_message(label).is_equal([0, 1, 2])
		for k: int in 3:
			assert_int(world.cooldown[2 * k]).is_equal(weapons[k].cooldown_ticks)


## A unit fires in the tick it dies, whatever its id: two enemies, 10 hp each, hand each other as
## targets and shoot for 21 (30 * 70 / 100 against infantry). Unit 1 fires first and takes unit 2
## to -11; unit 2, already at -11 but still in its row, fires as well; both are removed after.
## Both SHOTs are written before both DIEDs, in row order, and swapping the owners changes nothing.
## The second unit stands 500 off the first one's row, so each record's two y fields differ.
func test_a_unit_fires_in_the_tick_it_dies_whatever_its_id() -> void:
	for swapped: bool in [false, true]:
		var gun: WeaponDef = _weapon(&"gun", 30, 25, GUN_VS)
		var world: World = Rig.world_of([_def(&"duellist", INFANTRY, 10, gun)])
		world.add_unit(2 if swapped else 1, 0, 4000, 6000)
		world.add_unit(1 if swapped else 2, 0, 7000, 6000 + SIDE)
		world.target[0] = 2
		world.target[1] = 1
		Sim.step(world, [])
		var label: String = "owners swapped" if swapped else "owners 1 and 2"
		assert_int(world.unit_count()).override_failure_message(label).is_equal(0)
		assert_array(world.events).override_failure_message(label).is_equal(
			(
				[SHOT, 1, 4000, 6000, 2, 0, 7000, 6500, SHOT, 2, 7000, 6500, 1, 0, 4000, 6000]
				+ [DIED, 1, 4000, 6000, 0, 2 if swapped else 1, 0, 0]
				+ [DIED, 2, 7000, 6500, 0, 1 if swapped else 2, 0, 0]
			)
		)


## A target that one shooter has already brought below 0 is still hit by the shooters after it, and
## those shooters fire (their cooldowns are set): the three shooters of id 1 to 3 take a mark of 30
## hp to 30 - 3 * 18 = -24 in FIRE, so the result does not depend on who comes first. hp goes below
## 0 by the hits of the tick, which is one hit per shooter. REMOVE writes one DIED.
func test_every_shooter_hits_a_target_that_an_earlier_shooter_has_already_killed() -> void:
	var gun: WeaponDef = _weapon(&"gun", 30, 25, GUN_VS)
	var world: World = Rig.world_of([_def(&"gun", INFANTRY, TOUGH, gun), _def(&"mark", LIGHT, 30)])
	for k: int in 3:
		world.add_unit(1, 0, 3000, 3000 + 3000 * k)
	world.add_unit(2, 1, 6000, 6000)
	world.target[0] = 4
	world.target[1] = 4
	world.target[2] = 4
	Combat.fire(world)
	assert_int(world.hp[3]).is_equal(30 - 3 * 18)
	(
		assert_array(_records(world, SHOT).map(func(record: Array) -> int: return record[1]))
		. is_equal([1, 2, 3])
	)
	assert_array(Array(world.cooldown.slice(0, 3))).is_equal([25, 25, 25])
	world.remove_dead()
	(
		assert_array(_records(world, DIED).map(func(record: Array) -> int: return record[1]))
		. is_equal([4])
	)


## Removal keeps id order: shooters 1, 3 and 5 aim at marks 2, 4 and 6 (10, 1000 and 10 hp), and
## the marks 2 and 6 die. The rows left are ids 1, 3, 4, 5 in that order, every column compacted
## with them (`index_of` finds each), the DIED records come in row order and `rows_version` goes up
## by one. The shooters' targets are not rewritten (the dead ids stay in their rows).
func test_removal_after_fire_keeps_the_rows_in_id_order() -> void:
	var gun: WeaponDef = _weapon(&"gun", 30, 25, GUN_VS)
	var defs: Array[UnitDef] = [_def(&"gun", INFANTRY, TOUGH, gun), _def(&"mark", LIGHT, 10)]
	defs.append(_def(&"sturdy", LIGHT, 1000))
	var world: World = Rig.world_of(defs)
	for k: int in 3:
		world.add_unit(1, 0, 3000, 2000 + 4000 * k)
		world.add_unit(2, 2 if k == 1 else 1, 6000, 2000 + 4000 * k)
		world.target[2 * k] = 2 * k + 2
	var version: int = world.rows_version
	Sim.step(world, [])
	assert_array(world.unit_id).is_equal([1, 3, 4, 5])
	for row: int in 4:
		assert_int(world.index_of(world.unit_id[row])).is_equal(row)
	assert_array(world.owner).is_equal([1, 1, 2, 1])
	assert_array(world.type_index).is_equal([0, 0, 2, 0])
	assert_array(world.target).is_equal([2, 4, 0, 6])
	assert_array(world.hp).is_equal([TOUGH, TOUGH, 1000 - 18, TOUGH])
	(
		assert_array(_records(world, DIED).map(func(record: Array) -> int: return record[1]))
		. is_equal([2, 6])
	)
	assert_int(world.rows_version).is_equal(version + 1)


## The reach is inclusive at both ends, in squared distance: a weapon of range 4500 and minimum
## range 2000 fires at 4500 along an axis and along the diagonal (2700, 3600), and at 2000, and not
## at 4501 or at 1999. The minimum range keeps a unit that stands too close from firing; no unit
## backs away. The shooter's weapon is index 1, behind a decoy weapon of index 0 (range 9000, no
## minimum range, damage 5, cooldown 3), so the range, the minimum range, the damage and the
## cooldown are read by the shooter's own weapon index.
func test_the_range_and_the_minimum_range_are_inclusive() -> void:
	var gun: WeaponDef = _weapon(&"gun", 30, 25, GUN_VS, REACH, 2000)
	var decoy: WeaponDef = _weapon(&"decoy", 5, 3, [100, 100, 100, 100], 9000, 0)
	var cases: Dictionary[Vector2i, bool] = {
		Vector2i(4500, 0): true,
		Vector2i(2700, 3600): true,
		Vector2i(2000, 0): true,
		Vector2i(4501, 0): false,
		Vector2i(2700, 3601): false,
		Vector2i(1999, 0): false,
		Vector2i(1200, 1599): false,
	}
	for offset: Vector2i in cases:
		var world: World = _duel_second(decoy, gun, LIGHT)
		world.pos_x[1] = world.pos_x[0] + offset.x
		world.pos_y[1] = world.pos_y[0] + offset.y
		world.target[0] = 2
		Combat.fire(world)
		var label: String = "offset %s" % offset
		var shots: Array[Array] = _records(world, SHOT)
		assert_bool(not shots.is_empty()).override_failure_message(label).is_equal(cases[offset])
		assert_int(world.hp[1]).override_failure_message(label).is_equal(
			TOUGH - (18 if cases[offset] else 0)
		)
		assert_int(world.cooldown[0]).override_failure_message(label).is_equal(
			25 if cases[offset] else 0
		)
		if cases[offset]:
			assert_int(shots[0][5]).override_failure_message(label).is_equal(1)


## Who fires, in the phase alone: a unit with no weapon (type_weapon -1), one whose weapon index is
## past the weapon tables (a hand-built World may name a weapon it has no table for: unarmed, as
## Targeting reads it), one with no target, one whose target is a unit of its own side, a neutral
## unit (owner 0) or an id that is gone, and one at a position out of reach, do not fire and
## write no event. A unit whose target is a real enemy in reach does (the control).
func test_only_an_armed_unit_with_an_enemy_target_in_reach_fires() -> void:
	var gun: WeaponDef = _weapon(&"gun", 30, 25, GUN_VS)
	var cases: Dictionary[String, bool] = {
		"unarmed": false,
		"weapon index past the tables": false,
		"no target": false,
		"friend": false,
		"neutral": false,
		"gone": false,
		"enemy": true,
	}
	for label: String in cases:
		var world: World = _duel(gun, LIGHT)
		world.add_unit(1, 1, 4000, 8000)
		world.add_unit(0, 1, 4000, 9000)
		world.target[0] = 2
		match label:
			"unarmed":
				world.type_weapon[0] = -1
			"weapon index past the tables":
				world.type_weapon[0] = world.weapon_range.size()
			"no target":
				world.target[0] = 0
			"friend":
				world.target[0] = 3
			"neutral":
				world.target[0] = 4
			"gone":
				world.target[0] = 99
		Combat.fire(world)
		assert_bool(not _records(world, SHOT).is_empty()).override_failure_message(label).is_equal(
			cases[label]
		)
		assert_int(world.cooldown[0]).override_failure_message(label).is_equal(
			25 if cases[label] else 0
		)
		assert_int(world.hp[1]).override_failure_message(label).is_equal(
			TOUGH - (18 if cases[label] else 0)
		)


## A target id that is gone is not hit through the row that now stands where the id search ends: the
## shooter (id 1) aims at id 3, which was removed, and the rows left are ids 1, 2 and 4, the two
## others enemies in reach. The search for 3 ends on the row of id 4, whose id is not 3, so nothing
## is hit, no SHOT is written and the cooldown is not set (the shooter waits for its next scan to
## drop the dead id).
func test_a_removed_target_is_not_hit_through_the_row_after_it() -> void:
	var world: World = _duel(_weapon(&"gun", 30, 25, GUN_VS), LIGHT)
	world.add_unit(2, 1, 4000, 8000)
	world.add_unit(2, 1, 4000, 4000)
	world.hp[2] = 0
	world.remove_dead()
	assert_array(world.unit_id).is_equal([1, 2, 4])
	world.target[0] = 3
	Combat.fire(world)
	assert_array(_records(world, SHOT)).is_empty()
	assert_array(world.hp).is_equal([TOUGH, TOUGH, TOUGH])
	assert_int(world.cooldown[0]).is_equal(0)
	world.target[0] = 4
	Combat.fire(world)
	assert_int(_records(world, SHOT).size()).is_equal(1)
	assert_array(world.hp).is_equal([TOUGH, TOUGH, TOUGH - 18])


## The cooldown counts down by 1 a tick whether or not the unit has a target (25 with no target for
## 10 ticks is 15 and then stays at 0), and a pending cooldown of c delays the first shot until tick
## c - 1 (the count reaches 0 in that tick's FIRE, which fires in the same tick, so a shot at tick T
## with cooldown c is followed by one at T + c). The target is handed over from tick 1 on.
func test_the_cooldown_counts_down_without_a_target_and_the_unit_fires_when_it_reaches_0() -> void:
	var idle: World = _duel(_weapon(&"gun", 30, 25, GUN_VS), LIGHT)
	idle.cooldown[0] = 25
	for _tick: int in 10:
		Combat.fire(idle)
	assert_int(idle.cooldown[0]).is_equal(15)
	for _tick: int in 30:
		Combat.fire(idle)
	assert_int(idle.cooldown[0]).is_equal(0)
	for pending: int in [1, 3, 25]:
		var world: World = _duel(_weapon(&"gun", 30, 25, GUN_VS), LIGHT)
		world.cooldown[0] = pending
		var first: int = -1
		for tick: int in 30:
			world.target[0] = 2 if tick >= 1 else 0
			Combat.fire(world)
			if first < 0 and not _records(world, SHOT).is_empty():
				first = tick
		assert_int(first).override_failure_message("pending %d" % pending).is_equal(
			maxi(pending - 1, 1)
		)


## A moving unit does not fire: a MOVE order drops the target every tick (TARGETING), so a unit
## on the way with an enemy 3000 away shoots nothing in 30 ticks; once it has arrived, idle, it
## takes the enemy and fires.
func test_a_unit_on_a_move_order_does_not_fire_until_it_arrives() -> void:
	var world: World = _duel(_weapon(&"gun", 30, 25, GUN_VS), LIGHT, TOUGH, 3000)
	var shots: int = 0
	var first_tick: int = -1
	var order: Command = _order(Command.move(1, PackedInt32Array([1]), 4000, 8000), world)
	var commands: Array[Command] = [order]
	for tick: int in 80:
		Sim.step(world, commands)
		commands.clear()
		if not _records(world, SHOT).is_empty():
			shots += 1
			first_tick = first_tick if first_tick >= 0 else tick
		if tick < 16:
			assert_int(shots).override_failure_message("tick %d" % tick).is_equal(0)
	assert_int(world.order[0]).is_equal(World.Order.IDLE)
	assert_int(first_tick).is_greater(16)
	assert_int(shots).is_greater(0)


## FIRE sits between PROJECTILES (P42b, after INTEGRATE) and REMOVE: at the INTEGRATE and
## PROJECTILES marks the mark (row 1) still has all its hp, at the FIRE mark it has lost 18 and the
## SHOT is written but the row is there, and at the REMOVE mark a mark of 10 hp is gone with its
## DIED record. The shooter's cooldown is set at FIRE. The FOG mark (P46) follows REMOVE and
## changes none of these columns.
func test_damage_is_done_at_the_fire_mark_and_the_row_leaves_at_the_remove_mark() -> void:
	var tough: World = _duel(_weapon(&"gun", 30, 25, GUN_VS), LIGHT)
	var probe: FireProbe = FireProbe.new(tough)
	tough.target[0] = 2
	Sim.step(tough, [], probe)
	var at_integrate: int = probe.phases.find(SimProbe.Phase.INTEGRATE)
	assert_array(probe.phases.slice(at_integrate)).is_equal(
		[
			SimProbe.Phase.INTEGRATE,
			SimProbe.Phase.PROJECTILES,
			SimProbe.Phase.FIRE,
			SimProbe.Phase.REMOVE,
			SimProbe.Phase.FOG
		]
	)
	var after: Array[int] = [TOUGH, TOUGH, TOUGH - 18, TOUGH - 18, TOUGH - 18]
	assert_array(probe.hit_points.slice(at_integrate)).is_equal(after)
	assert_array(probe.event_ints.slice(at_integrate)).is_equal([0, 0, STRIDE, STRIDE, STRIDE])
	assert_array(probe.cooldowns.slice(at_integrate)).is_equal([0, 0, 25, 25, 25])
	var brittle: World = _duel(_weapon(&"gun", 30, 25, GUN_VS), LIGHT, 10)
	var killing: FireProbe = FireProbe.new(brittle)
	brittle.target[0] = 2
	Sim.step(brittle, [], killing)
	var rows: Array[int] = killing.rows.slice(killing.phases.find(SimProbe.Phase.INTEGRATE))
	assert_array(rows).is_equal([2, 2, 2, 1, 1])
	var ints: Array[int] = killing.event_ints.slice(killing.phases.find(SimProbe.Phase.INTEGRATE))
	assert_array(ints).is_equal([0, 0, STRIDE, 2 * STRIDE, 2 * STRIDE])


## The orders of the Phase 1 tests on the controls map produce no SHOT within their tick counts, so
## those tests need no change when units fire: the 450 ticks of test_controls_flow (30 blue tanks
## attack-move to (20016, 21516)), the 165 of test_sim_step's thirty tanks (to (22250, 22250)) and
## its 80-tick command script (two overlapping groups and a red order, then a re-order at tick 25).
## No hit, no death, 40 units at the end. The control: with a red tank stood beside the path, the
## same order draws fire.
func test_the_orders_of_the_phase_1_tests_on_the_controls_map_produce_no_shot() -> void:
	var all_blue: PackedInt32Array = PackedInt32Array(range(1, 31))
	var flow: Array[Command] = [_stamped(Command.attack_move(1, all_blue, 20016, 21516), 0, 0)]
	var thirty: Array[Command] = [_stamped(Command.attack_move(1, all_blue, 22250, 22250), 0, 0)]
	var script: Array[Command] = [
		_stamped(Command.attack_move(1, PackedInt32Array(range(1, 16)), 20000, 20000), 0, 0),
		_stamped(Command.attack_move(1, PackedInt32Array(range(10, 31)), 30000, 30000), 0, 1),
		_stamped(Command.attack_move(2, PackedInt32Array(range(31, 35)), 30000, 12000), 0, 0),
		_stamped(Command.attack_move(1, all_blue, 5000, 5000), 25, 2),
		_stamped(Command.attack_move(2, all_blue, 5000, 5000), 25, 1),
	]
	var runs: Dictionary[String, Array] = {"flow": [flow, 450], "thirty": [thirty, 165]}
	runs["script"] = [script, 80]
	for label: String in runs:
		var world: World = World.from_scenario(load(SCENARIO_PATH) as ScenarioDef)
		var start: PackedInt32Array = world.hp.duplicate()
		var shots: int = _run_counting_shots(world, runs[label][0], runs[label][1])
		assert_int(shots).override_failure_message(label).is_equal(0)
		assert_array(world.hp).override_failure_message(label).is_equal(start)
		assert_int(world.unit_count()).override_failure_message(label).is_equal(40)
	var beside: World = World.from_scenario(load(SCENARIO_PATH) as ScenarioDef)
	beside.pos_x[30] = 21000
	beside.pos_y[30] = 22000
	assert_int(_run_counting_shots(beside, thirty, 165)).is_greater(0)


## A World on the open 20 x 12 tile map with the shooter (type 0, owner 1, id 1) at (4000, 6000) and
## a mark (type 1, owner 2, id 2, of `armour` and `mark_hp`) `gap` milli east and `side` milli south
## of it.
func _duel(
	weapon: WeaponDef, armour: int, mark_hp: int = TOUGH, gap: int = 4000, side: int = 0
) -> World:
	var defs: Array[UnitDef] = [
		_def(&"gun", INFANTRY, TOUGH, weapon), _def(&"mark", armour, mark_hp)
	]
	var world: World = Rig.world_of(defs)
	world.add_unit(1, 0, 4000, 6000)
	world.add_unit(2, 1, 4000 + gap, 6000 + side)
	return world


## `_duel` with a decoy type first in the roster: the decoy's weapon is index 0, the shooter's
## (`weapon`) is index 1 and the mark is type 2, so a column that FIRE reads by the shooter's weapon
## and not by 0 shows. The ids are the same as in `_duel`.
func _duel_second(decoy: WeaponDef, weapon: WeaponDef, armour: int) -> World:
	var defs: Array[UnitDef] = [
		_def(&"decoy", INFANTRY, TOUGH, decoy),
		_def(&"gun", INFANTRY, TOUGH, weapon),
		_def(&"mark", armour, TOUGH)
	]
	var world: World = Rig.world_of(defs)
	world.add_unit(1, 1, 4000, 6000)
	world.add_unit(2, 2, 8000, 6000)
	return world


## A MOVE order, stamped for the World's tick, that walks the mark (id 2, 500 south of the shooter's
## row) east along its row.
func _walk_east(world: World) -> Command:
	var walk: Command = Command.move(2, PackedInt32Array([2]), 12000, 6000 + SIDE)
	return _order(walk, world)


## A weapon of the given numbers (hitscan: no projectile speed), vs the four armour percents.
func _weapon(
	id: StringName,
	damage: int,
	cooldown: int,
	vs: Array,
	range_milli: int = REACH,
	min_range: int = 0
) -> WeaponDef:
	var weapon: WeaponDef = WeaponDef.new()
	weapon.id = id
	weapon.range = range_milli
	weapon.min_range = min_range
	weapon.damage = damage
	weapon.cooldown_ticks = cooldown
	weapon.vs_armour = PackedInt32Array(vs)
	return weapon


## A unit type of `armour` and `hp` that walks 120 a tick, sees 7000 and acquires at 5500.
func _def(id: StringName, armour: int, hp: int, weapon: WeaponDef = null) -> UnitDef:
	var def: UnitDef = UnitDef.new()
	def.type_id = id
	def.speed = 120
	def.radius = 300
	def.selection_radius = 350
	def.formation_spacing = 900
	def.max_hp = hp
	def.armour = armour
	def.sight_range = 7000
	def.acquire_range = 5500
	def.weapon = weapon
	return def


## The records of `kind` in the events of the last tick, each as the 8 ints.
func _records(world: World, kind: int) -> Array[Array]:
	var found: Array[Array] = []
	for at: int in range(0, world.events.size(), STRIDE):
		if world.events[at] == kind:
			found.append(Array(world.events.slice(at, at + STRIDE)))
	return found


## The squared distance between the units in rows `a` and `b`.
func _d2(world: World, a: int, b: int) -> int:
	var dx: int = world.pos_x[a] - world.pos_x[b]
	var dy: int = world.pos_y[a] - world.pos_y[b]
	return dx * dx + dy * dy


func _order(command: Command, world: World) -> Command:
	command.tick = world.tick
	return command


func _stamped(command: Command, tick: int, sequence: int) -> Command:
	command.tick = tick
	command.sequence = sequence
	return command


## Steps `world` for `ticks` ticks with the commands due at each, and returns the SHOT records seen.
func _run_counting_shots(world: World, commands: Array[Command], ticks: int) -> int:
	var shots: int = 0
	for _tick: int in ticks:
		var due: Array[Command] = []
		due.assign(commands.filter(func(c: Command) -> bool: return c.tick == world.tick))
		Sim.step(world, due)
		shots += _records(world, SHOT).size()
	return shots
