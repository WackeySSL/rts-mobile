extends GdUnitTestSuite
## The offline rule (plan row P74, ADR 0018 section 4): while a player is on low power its defences
## (building rows with a weapon) keep the target TARGETING gave them and do not shoot, their
## cooldown still counts down, and they fire on the first FIRE after the totals stop being low (the
## totals are built in ECONOMY, after FIRE, so a plant added before step t makes the turret fire in
## step t+1). Units and the other player's defences are not affected, and a player that uses exactly
## what it makes is not low. Combat.fire is GDScript only: no kernel runs it.
##
## The world is a 24 x 12 open map, revealed. A defence turret has a range of 5,500 milli, and the
## target is an unarmed harvester 4,000 milli away, so nothing shoots back and nothing moves.

const Worlds: GDScript = preload("res://tests/sim/support/building_worlds.gd")
const SHOT: int = World.Event.SHOT
const TURRET_AT: Vector2i = Vector2i(10, 5)
const TARGET_AT: Vector2i = Vector2i(14500, 5500)


func _type(world: World, id: String) -> int:
	return Worlds.type_of(world, id)


func _step(world: World, ticks: int = 1) -> void:
	for _tick: int in ticks:
		Sim.step(world, [] as Array[Command])


## Player 1's turret and, with `powered`, a power plant far from it; player 2's harvester in range.
## Returns the world; the ids are found with `_id`.
func _world(powered: bool) -> World:
	var world: World = Worlds.open(24, 12)
	if powered:
		world.add_building(1, _type(world, "power_plant"), 2, 8)
	world.add_building(1, _type(world, "defence_turret"), TURRET_AT.x, TURRET_AT.y)
	world.add_unit(2, _type(world, "harvester"), TARGET_AT.x, TARGET_AT.y)
	return world


## The id of the first row of `owner` of the type `id`.
func _id(world: World, owner: int, id: String) -> int:
	for row: int in world.unit_count():
		if world.owner[row] == owner and world.type_index[row] == _type(world, id):
			return world.unit_id[row]
	return 0


## The shooter ids of the SHOT records of the last step, in order.
func _shooters(world: World) -> Array[int]:
	var found: Array[int] = []
	var at: int = 0
	while at + World.EVENT_STRIDE <= world.events.size():
		if world.events[at] == SHOT:
			found.append(world.events[at + 1])
		at += World.EVENT_STRIDE
	return found


func test_an_offline_turret_keeps_its_target_and_never_fires() -> void:
	var world: World = _world(false)
	var turret: int = world.index_of(_id(world, 1, "defence_turret"))
	var target: int = _id(world, 2, "harvester")
	var hit_points: int = world.hp[world.index_of(target)]
	for tick: int in 60:
		_step(world)
		assert_array(_shooters(world)).override_failure_message("tick %d" % tick).is_empty()
		if tick >= 10:
			assert_int(world.target[turret]).override_failure_message("tick %d" % tick).is_equal(
				target
			)
	assert_bool(Power.is_low(world, 1)).is_true()
	assert_array([world.hp[world.index_of(target)], world.next_projectile_id]).is_equal(
		[hit_points, 1]
	)
	assert_int(world.cooldown[turret]).is_equal(0)


func test_the_same_turret_with_power_fires_from_the_tick_it_has_a_target() -> void:
	var world: World = _world(true)
	var turret_id: int = _id(world, 1, "defence_turret")
	var turret: int = world.index_of(turret_id)
	var first: int = -1
	for tick: int in 60:
		_step(world)
		if first < 0 and not _shooters(world).is_empty():
			first = tick
			assert_array(_shooters(world)).is_equal([turret_id])
			assert_int(world.target[turret]).is_equal(_id(world, 2, "harvester"))
	assert_bool(Power.is_low(world, 1)).is_false()
	assert_int(first).is_greater_equal(0)


func test_a_turret_fires_on_the_first_step_after_power_returns() -> void:
	var world: World = _world(false)
	var turret_id: int = _id(world, 1, "defence_turret")
	_step(world, 30)
	var target: int = _id(world, 2, "harvester")
	assert_int(world.target[world.index_of(turret_id)]).is_equal(target)  # Held, not fired.
	assert_int(world.next_projectile_id).is_equal(1)
	world.add_building(1, _type(world, "power_plant"), 2, 8)
	_step(world)  # FIRE of this step ran before ECONOMY counted the plant.
	assert_array(_shooters(world)).is_empty()
	assert_bool(Power.is_low(world, 1)).is_false()
	_step(world)
	assert_array(_shooters(world)).is_equal([turret_id])
	assert_int(world.target[world.index_of(turret_id)]).is_equal(target)
	assert_int(world.tick).is_equal(32)


## The cooldown counts down while the turret is offline, so it needs no wind-up: powered, it fires
## once (cooldown set); its plant dies and 60 ticks pass, longer than the weapon's cooldown; a new
## plant comes, and the turret fires on the first step after it. A cooldown that stood still while
## offline would delay that shot by what was left of it.
func test_the_cooldown_runs_while_offline_so_the_turret_fires_at_once_when_power_returns() -> void:
	var world: World = _world(true)
	var turret_id: int = _id(world, 1, "defence_turret")
	var plant_id: int = _id(world, 1, "power_plant")
	var cooldown: int = world.weapon_cooldown[world.type_weapon[_type(world, "defence_turret")]]
	var fired: int = 0
	while _shooters(world).is_empty() and fired < 60:
		_step(world)
		fired += 1
	assert_array(_shooters(world)).is_equal([turret_id])
	assert_int(world.cooldown[world.index_of(turret_id)]).is_equal(cooldown)
	world.hp[world.index_of(plant_id)] = 0  # The row leaves, and the rows after it move down.
	for tick: int in 60:
		_step(world)
		assert_array(_shooters(world)).override_failure_message("tick %d" % tick).is_empty()
	assert_bool(Power.is_low(world, 1)).is_true()
	var turret: int = world.index_of(turret_id)
	assert_int(world.cooldown[turret]).is_equal(0)  # Ran out while it waited.
	assert_int(world.target[turret]).is_equal(_id(world, 2, "harvester"))
	world.add_building(1, _type(world, "power_plant"), 2, 8)
	_step(world)
	assert_array(_shooters(world)).is_empty()
	_step(world)
	assert_array(_shooters(world)).is_equal([turret_id])


func test_a_unit_of_a_player_on_low_power_still_fires_and_the_turret_beside_it_does_not() -> void:
	var world: World = _world(false)
	var tank: int = world.add_unit(1, _type(world, "light_tank"), 11500, 7500)
	var turret_id: int = _id(world, 1, "defence_turret")
	var shooters: Dictionary[int, int] = {}
	for _tick: int in 40:
		_step(world)
		for shooter: int in _shooters(world):
			shooters[shooter] = shooters.get(shooter, 0) + 1
	assert_bool(Power.is_low(world, 1)).is_true()
	assert_bool(shooters.has(tank)).is_true()
	assert_bool(shooters.has(turret_id)).is_false()


func test_the_other_players_low_power_does_not_silence_a_powered_turret() -> void:
	var world: World = Worlds.open(24, 12)
	world.add_building(1, _type(world, "power_plant"), 2, 8)
	var mine: int = world.add_building(1, _type(world, "defence_turret"), 4, 5)
	var theirs: int = world.add_building(2, _type(world, "defence_turret"), 18, 5)  # No plant.
	world.add_unit(2, _type(world, "harvester"), 8500, 5500)  # 4,000 from player 1's turret.
	world.add_unit(1, _type(world, "harvester"), 14500, 5500)  # 4,000 from player 2's turret.
	var fired: Dictionary[int, int] = {}
	for _tick: int in 60:
		_step(world)
		for shooter: int in _shooters(world):
			fired[shooter] = fired.get(shooter, 0) + 1
	assert_bool(Power.is_low(world, 1)).is_false()
	assert_bool(Power.is_low(world, 2)).is_true()
	assert_bool(fired.has(mine)).is_true()
	assert_bool(fired.has(theirs)).is_false()
	var held: int = world.target[world.index_of(theirs)]
	assert_int(world.owner[world.index_of(held)]).is_equal(1)  # It kept its target all the same.


func test_a_defence_whose_player_uses_exactly_what_it_makes_fires() -> void:
	var world: World = Worlds.open(24, 12)
	var hq: int = _type(world, "headquarters")
	var turret: int = _type(world, "defence_turret")
	world.add_building(1, hq, 2, 2)
	var turret_id: int = world.add_building(1, turret, TURRET_AT.x, TURRET_AT.y)
	world.add_unit(2, _type(world, "harvester"), TARGET_AT.x, TARGET_AT.y)
	world.type_power[turret] = -world.type_power[hq]  # The turret uses what the Headquarters makes.
	var shot: bool = false
	for _tick: int in 60:
		_step(world)
		shot = shot or _shooters(world).has(turret_id)
	assert_int(world.power_made[1]).is_greater(0)
	assert_int(world.power_used[1]).is_equal(world.power_made[1])
	assert_bool(Power.is_low(world, 1)).is_false()
	assert_bool(shot).is_true()
	world.type_power[turret] -= 1  # One more used than made.
	world._power_version = -1  # The table moved, not the rows: ask for the rebuild.
	_step(world, 2)  # The totals are rebuilt in ECONOMY; the next FIRE finds the turret offline.
	assert_bool(Power.is_low(world, 1)).is_true()
	for _tick: int in 60:
		_step(world)
		assert_array(_shooters(world)).is_empty()
