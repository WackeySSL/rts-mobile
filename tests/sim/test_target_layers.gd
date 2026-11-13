extends GdUnitTestSuite
## Target layers (plan row P238, ADR 0036 section 5): a weapon may hit a row when `weapon_targets &
## type_layer_bit[type]` is not 0. The rule is in acquisition (a candidate and a held target), in
## the ATTACK lock (a lock on a row the weapon cannot hit falls back to ATTACK_MOVE), in
## `Sim._apply_attack` (only the rows that can hit the target take the order), in the `Combat.fire`
## guard and in the rupture (it skips air and low air). The acquisition and the lock run under both
## implementations (`_both()`); the guard, the command and the rupture are GDScript phases. The
## kernel against the twin on aircraft rows is tests/sim/native/test_targeting_lockstep_layers.gd.
## The worlds are LayerWorlds': 0 gun (mask 1), 1 rocket (7), 2 rifle (5), 3 flak (6), 4 jet (AIR),
## 5 bomber (AIR), 6 drone (low AIR), 7 scout (no weapon).

const Layers: GDScript = preload("res://tests/sim/support/layer_worlds.gd")
const Rig: GDScript = preload("res://tests/sim/support/targeting_rig.gd")
const SimImpls: GDScript = preload("res://tests/sim/support/sim_impls.gd")
const Strikes: GDScript = preload("res://tests/sim/support/strike_worlds.gd")
const TARGETING: int = SimProbe.Phase.TARGETING
const IDLE: int = World.Order.IDLE
const ATTACK_MOVE: int = World.Order.ATTACK_MOVE
const ATTACK: int = World.Order.ATTACK


func _both() -> Array[Array]:
	return SimImpls.CASES.duplicate(true)


## Every shooter against every mark, idle and 2000 milli apart: the shooter takes the mark exactly
## when its mask meets the mark's layer and its damage percent is above 0, for the gun, the
## rocket, the rifle, flak and the jet
## against a tank-like ground row, a jet and a drone.
func test_an_idle_unit_takes_only_a_row_on_a_layer_its_weapon_hits(
	impl: int, _test_parameters := _both()
) -> void:
	var taken: int = 0
	for shooter: int in [Layers.GUN, Layers.ROCKET, Layers.RIFLE, Layers.FLAK, Layers.JET]:
		for mark: int in [Layers.GUN, Layers.JET, Layers.DRONE]:
			var world: World = _in(Layers.duel(shooter, mark), impl)
			var mask: int = world.weapon_targets[world.type_weapon[shooter]]
			var percent: int = world.weapon_vs_armour[
				world.type_weapon[shooter] * World.Armour.size() + world.type_armour[mark]
			]
			var hits: bool = (mask & world.type_layer_bit[mark]) != 0 and percent > 0
			var label: String = "shooter %d (mask %d) at mark %d" % [shooter, mask, mark]
			var found: int = Rig.target_of(world, 1)
			assert_int(found).override_failure_message(label).is_equal(2 if hits else 0)
			taken += int(hits)
	# 5 shooters x 3 marks: gun 1 (ground), rocket 3, rifle 2 (ground, drone), flak 1 (the jet; its
	# percent against the drone's infantry armour is 0), jet 1 (the jet).
	assert_int(taken).is_equal(8)


## The masks the ADR starts with, as the shipped data holds them: the rocket 7, the rifle 5, the
## Redoubt 5, the two anti-air guns 6 and every other weapon file in data/weapons ground (a new
## file fails until it is listed here with its mask).
func test_the_shipped_weapon_masks_are_the_adr_starting_masks() -> void:
	var masks: Dictionary[String, int] = {
		"rocket": 7,
		"breaker_rocket": 7,
		"rifle": 5,
		"redoubt_gun": 5,
		"burst_stack_gun": 6,
		"sky_needle_gun": 6,
		# P242: the fighters hit high air only, the bombers the ground (the default 1).
		"torchjet_gun": 2,
		"glint_gun": 2,
	}
	var files: PackedStringArray = DirAccess.get_files_at("res://data/weapons")
	var seen: int = 0
	for file: String in files:
		if not file.ends_with(".tres"):
			continue
		var id: String = file.get_basename()
		var weapon: WeaponDef = load("res://data/weapons/%s" % file) as WeaponDef
		# Every other weapon is ground only, until its row lists another mask here.
		assert_int(weapon.targets).override_failure_message(id).is_equal(masks.get(id, 1))
		seen += 1
	assert_int(seen).is_greater(9)


## A nearer mark, and one the weapon would hurt more, on a layer it cannot hit does not take the
## target from a farther ground mark: the layer test is part of what makes a candidate.
func test_an_unhittable_row_is_no_candidate_even_when_nearer_and_better(
	impl: int, _test_parameters := _both()
) -> void:
	var world: World = _in(Layers.duel(Layers.GUN, Layers.GUN, 3500), impl)
	world.add_unit(2, Layers.JET, 4500, 6000)  # id 3, nearer than the gun at 7500.
	assert_int(Rig.target_of(world, 1)).override_failure_message("mask 1").is_equal(2)
	var rocket: World = _in(Layers.duel(Layers.ROCKET, Layers.GUN, 3500), impl)
	rocket.add_unit(2, Layers.JET, 4500, 6000)
	assert_int(Rig.target_of(rocket, 1)).override_failure_message("mask 7").is_equal(3)


## A held target that stands on a layer the weapon cannot hit is let go on the unit's turn and
## replaced by a ground row in reach, or by none.
func test_a_held_target_on_an_unhittable_layer_is_not_kept(
	impl: int, _test_parameters := _both()
) -> void:
	var world: World = _in(Layers.duel(Layers.GUN, Layers.JET), impl)
	world.target[0] = 2
	assert_int(Rig.target_of(world, 1)).is_equal(0)
	world.add_unit(2, Layers.GUN, 5000, 6000)  # id 3
	world.target[0] = 2
	assert_int(Rig.target_of(world, 1)).is_equal(3)
	var kept: World = _in(Layers.duel(Layers.ROCKET, Layers.JET), impl)
	kept.target[0] = 2
	kept.add_unit(2, Layers.GUN, 4500, 6000)  # nearer; a held target is kept all the same.
	assert_int(Rig.target_of(kept, 1)).is_equal(2)


## An ATTACK lock on a row the weapon cannot hit falls back to ATTACK_MOVE at once (the target is
## cleared, as for an unseen one), for a ground gun on a jet and on a drone and a jet-only gun on a
## ground row; a weapon that can hit the row keeps the lock. The goal stays where it was.
func test_an_attack_lock_on_an_unhittable_row_falls_back_to_attack_move(
	impl: int, _test_parameters := _both()
) -> void:
	var cases: Array[Array] = [
		[Layers.GUN, Layers.JET, false],
		[Layers.GUN, Layers.DRONE, false],
		[Layers.RIFLE, Layers.JET, false],
		[Layers.RIFLE, Layers.DRONE, true],
		[Layers.ROCKET, Layers.JET, true],
		[Layers.JET, Layers.GUN, false],
		[Layers.JET, Layers.JET, true],
		[Layers.FLAK, Layers.DRONE, true],
	]
	for item: Array in cases:
		var world: World = _in(Layers.duel(item[0], item[1], 6000), impl)
		world.order[0] = ATTACK
		world.order_target[0] = 2
		world.goal_x[0] = 9999
		world.goal_y[0] = 6001
		world.prepare()
		Rig.acquire(world)
		var label: String = str(item)
		assert_int(world.order[0]).override_failure_message(label).is_equal(
			ATTACK if item[2] else ATTACK_MOVE
		)
		assert_int(world.order_target[0]).override_failure_message(label).is_equal(
			2 if item[2] else 0
		)
		assert_int(world.target[0]).override_failure_message(label).is_equal(2 if item[2] else 0)
		if not item[2]:
			assert_array([world.goal_x[0], world.goal_y[0]]).is_equal([9999, 6001])


## An unarmed type has no mask: its ATTACK lock holds on a jet as on any enemy. This is hand-built
## state (no command gives ATTACK to a type with weapon -1; `test_attack_by_a_type_whose_weapon_is_
## past_the_tables...` is the reachable path).
func test_an_unarmed_attack_lock_holds_on_any_layer(impl: int, _test_parameters := _both()) -> void:
	for mark: int in [Layers.GUN, Layers.JET, Layers.DRONE]:
		var world: World = _in(Layers.duel(Layers.SCOUT, mark, 6000), impl)
		world.order[0] = ATTACK
		world.order_target[0] = 2
		world.prepare()
		Rig.acquire(world)
		assert_int(world.order[0]).is_equal(ATTACK)
		assert_int(world.target[0]).is_equal(2)


## ATTACK drops a row whose weapon cannot hit the target's layer, and keeps the others, in both
## directions: a gun (mask 1) and a flak unit (6) sent at a jet leave the flak unit with the order;
## sent at a tank, the gun takes it and the flak unit does not (and keeps its ATTACK on the jet);
## when nobody can hit the target the command is dropped and counted.
func test_attack_keeps_only_the_rows_that_can_hit_the_target() -> void:
	var world: World = _in(Layers.empty(), SimImpls.Impl.GDSCRIPT)
	var gun: int = world.add_unit(1, Layers.GUN, 4000, 6000)
	var flak: int = world.add_unit(1, Layers.FLAK, 4000, 7000)
	var jet: int = world.add_unit(2, Layers.JET, 6000, 6500)
	var tank: int = world.add_unit(2, Layers.GUN, 6000, 5000)
	world.prepare()
	Rig.reveal(world)
	var before: int = world.dropped_commands
	Sim.step(world, [_stamped(Command.attack(1, PackedInt32Array([gun, flak]), jet), world)])
	assert_int(world.order[world.index_of(gun)]).is_not_equal(ATTACK)
	assert_int(world.order[world.index_of(flak)]).is_equal(ATTACK)
	assert_int(world.order_target[world.index_of(flak)]).is_equal(jet)
	assert_int(world.dropped_commands).is_equal(before)
	Sim.step(world, [_stamped(Command.attack(1, PackedInt32Array([gun]), jet), world)])
	assert_int(world.dropped_commands).is_equal(before + 1)
	assert_int(world.order[world.index_of(gun)]).is_not_equal(ATTACK)
	Sim.step(world, [_stamped(Command.attack(1, PackedInt32Array([gun]), tank), world)])
	assert_int(world.order[world.index_of(gun)]).is_equal(ATTACK)
	assert_int(world.dropped_commands).is_equal(before + 1)
	# The flak unit cannot hit the tank: dropped and counted, and its ATTACK on the jet stays.
	Sim.step(world, [_stamped(Command.attack(1, PackedInt32Array([flak]), tank), world)])
	assert_int(world.dropped_commands).is_equal(before + 2)
	assert_int(world.order[world.index_of(flak)]).is_equal(ATTACK)
	assert_int(world.order_target[world.index_of(flak)]).is_equal(jet)
	# A mixed selection at the tank: only the gun takes the order.
	Sim.step(world, [_stamped(Command.stop(1, PackedInt32Array([gun, flak])), world)])
	Sim.step(world, [_stamped(Command.attack(1, PackedInt32Array([gun, flak]), tank), world)])
	assert_int(world.order[world.index_of(gun)]).is_equal(ATTACK)
	assert_int(world.order_target[world.index_of(gun)]).is_equal(tank)
	assert_int(world.order[world.index_of(flak)]).is_not_equal(ATTACK)
	assert_int(world.dropped_commands).is_equal(before + 2)


## The filter runs before `Buildings.aim`: a jet (mask 2) on a MOVE, sent with a gun at a speed-0
## enemy, is left out of the order and keeps its goal and its order (aim writes the goal of every
## row it is given); the gun takes the ATTACK and the command is not dropped.
func test_the_attack_filter_runs_before_aim_so_an_excluded_row_keeps_its_goal() -> void:
	var world: World = _in(Layers.empty(), SimImpls.Impl.GDSCRIPT)
	var gun: int = world.add_unit(1, Layers.GUN, 4000, 6000)
	var jet: int = world.add_unit(1, Layers.JET, 4000, 7000)
	var post: int = world.add_unit(2, Layers.POST, 7000, 6000)
	world.prepare()
	Rig.reveal(world)
	Sim.step(world, [_stamped(Command.move(1, PackedInt32Array([jet]), 2500, 2500), world)])
	var row: int = world.index_of(jet)
	assert_int(world.order[row]).is_equal(World.Order.MOVE)
	var goal: Array[int] = [world.goal_x[row], world.goal_y[row]]
	var before: int = world.dropped_commands
	Sim.step(world, [_stamped(Command.attack(1, PackedInt32Array([gun, jet]), post), world)])
	assert_int(world.order[world.index_of(gun)]).is_equal(ATTACK)
	assert_int(world.order[row]).is_equal(World.Order.MOVE)
	assert_array([world.goal_x[row], world.goal_y[row]]).is_equal(goal)
	assert_int(world.dropped_commands).is_equal(before)


## A type whose weapon index is past the weapon tables is unarmed here as in Targeting (a hand-
## built World may name one): ATTACK accepts it on a jet, which no mask can refuse.
func test_attack_by_a_type_whose_weapon_is_past_the_tables_takes_the_order() -> void:
	var world: World = _in(Layers.empty(), SimImpls.Impl.GDSCRIPT)
	world.type_weapon[Layers.GUN] = world.weapon_range.size()
	var blind: int = world.add_unit(1, Layers.GUN, 4000, 6000)
	var jet: int = world.add_unit(2, Layers.JET, 6000, 6500)
	world.prepare()
	Rig.reveal(world)
	var before: int = world.dropped_commands
	Sim.step(world, [_stamped(Command.attack(1, PackedInt32Array([blind]), jet), world)])
	assert_int(world.order[world.index_of(blind)]).is_equal(ATTACK)
	assert_int(world.dropped_commands).is_equal(before)


## The Combat.fire guard, in both directions and for every layer: a shooter that holds (by hand) a
## row on a layer its weapon cannot hit fires nothing (no SHOT, hit points and cooldown as they
## were), whichever the layer and whichever the shooter's own; the controls hit the layer they can.
## Flak against the drone is not a case (its percent against infantry is 0).
func test_combat_fire_will_not_shoot_a_layer_the_weapon_cannot_hit() -> void:
	var refused: Array[Array] = [
		[Layers.GUN, Layers.JET],
		[Layers.GUN, Layers.DRONE],
		[Layers.FLAK, Layers.GUN],
		[Layers.JET, Layers.GUN],
	]
	var fires: Array[Array] = [
		[Layers.ROCKET, Layers.JET],
		[Layers.RIFLE, Layers.DRONE],
		[Layers.FLAK, Layers.JET],
		[Layers.GUN, Layers.GUN],
	]
	for item: Array in refused + fires:
		var world: World = Layers.duel(item[0], item[1])
		var hp: int = world.hp[1]
		world.events.clear()  # The spawns of the two rows.
		world.target[0] = 2
		Combat.fire(world)
		var label: String = str(item)
		if refused.has(item):
			assert_int(world.hp[1]).override_failure_message(label).is_equal(hp)
			assert_array(world.events).override_failure_message(label).is_empty()
			assert_int(world.cooldown[0]).override_failure_message(label).is_equal(0)
		else:
			assert_int(world.events.size()).override_failure_message(label).is_greater(0)
			assert_int(world.cooldown[0]).override_failure_message(label).is_greater(0)


## The rupture skips a row on the air or the low air layer (here a rifle type moved to each layer)
## and hits the ground row beside it at the same point. A row on the ground layer takes the same
## damage whichever layer the other row is on.
func test_the_rupture_skips_air_and_low_air_rows() -> void:
	var lost: Array[int] = []
	for layer: int in [Layers.AIR, Layers.LOW_AIR, Layers.GROUND]:
		var world: World = Strikes.world()
		world.type_layer_bit[Strikes.type_of(world, "rifle")] = layer
		Strikes.run_to(world, Strikes.fire_tick(world, Strikes.BORE_A))
		var flyer: int = Strikes.add(world, 2, "rifle", Strikes.POINT.x, Strikes.POINT.y)
		var walker: int = Strikes.add(world, 2, "jeep", Strikes.POINT.x, Strikes.POINT.y)
		var flyer_hp: int = Strikes.hp_of(world, flyer)
		var walker_hp: int = Strikes.hp_of(world, walker)
		Strikes.step(world, [Strikes.fire(Strikes.BORE_A)])
		Strikes.run_to(world, world.strike_tick[1])
		var label: String = "layer %d" % layer
		assert_int(Strikes.hp_of(world, walker)).override_failure_message(label).is_less(walker_hp)
		lost.append(walker_hp - Strikes.hp_of(world, walker))
		if layer == Layers.GROUND:
			assert_int(Strikes.hp_of(world, flyer)).override_failure_message(label).is_less(
				flyer_hp
			)
		else:
			assert_int(Strikes.hp_of(world, flyer)).override_failure_message(label).is_equal(
				flyer_hp
			)
	assert_array(lost).is_equal([lost[0], lost[0], lost[0]])


## The rupture reads its own weapon's mask, not a fixed one: with the strike weapon at GROUND | AIR
## (3), an AIR rifle loses hit points and a LOW_AIR one keeps them.
func test_the_rupture_reads_the_mask_of_its_own_weapon() -> void:
	var lost: Dictionary[int, int] = {}
	for layer: int in [Layers.AIR, Layers.LOW_AIR]:
		var world: World = Strikes.world()
		var weapon: int = world.type_strike_weapon[Strikes.type_of(world, "bore")]
		world.weapon_targets[weapon] = Layers.GROUND | Layers.AIR
		world.type_layer_bit[Strikes.type_of(world, "rifle")] = layer
		Strikes.run_to(world, Strikes.fire_tick(world, Strikes.BORE_A))
		var flyer: int = Strikes.add(world, 2, "rifle", Strikes.POINT.x, Strikes.POINT.y)
		var before: int = Strikes.hp_of(world, flyer)
		Strikes.step(world, [Strikes.fire(Strikes.BORE_A)])
		Strikes.run_to(world, world.strike_tick[1])
		lost[layer] = before - Strikes.hp_of(world, flyer)
	assert_int(lost[Layers.AIR]).is_greater(0)
	assert_int(lost[Layers.LOW_AIR]).is_equal(0)


func _in(world: World, impl: int) -> World:
	assert_array(SimImpls.attach(world, impl, TARGETING)).is_empty()
	return world


func _stamped(command: Command, world: World) -> Command:
	command.tick = world.tick
	return command
