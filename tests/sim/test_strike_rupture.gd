extends GdUnitTestSuite
## The rupture (plan row P110, ADR 0023 section 10): a pending strike lands in the step whose stamp
## (tick + 1) is its `strike_tick`, not before; every row within the radius of the point by squared
## distance, own and neutral rows included, loses the weapon's damage times its armour percent (at
## least 1, none at a percent of 0) and no row outside does; each player has its own pending strike;
## and a strike in the air is not recalled by the loss of its building or by a defeat. The ticks,
## the fog, the power and the defeat of the landing step are test_strike_tick's. The rig is
## `strike_worlds.gd`; every radius, delay and damage is read from the World's tables.

const Strikes: GDScript = preload("res://tests/sim/support/strike_worlds.gd")
const INFANTRY: int = World.Armour.INFANTRY
const LIGHT: int = World.Armour.LIGHT
const HEAVY: int = World.Armour.HEAVY
const BUILDING: int = World.Armour.BUILDING


## The strike lands on exactly `strike_tick`: every step before it leaves the victim and the pending
## strike alone, the landing step takes the damage and clears the pending tick (the point stays for
## the view's crater), and a step after it changes nothing more.
func test_the_rupture_lands_on_exactly_its_strike_tick_and_not_a_tick_earlier() -> void:
	var world: World = Strikes.world()
	var tick: int = Strikes.fire_tick(world, Strikes.BORE_A)
	Strikes.run_to(world, tick)
	var victim: int = Strikes.add(world, 2, "rifle", Strikes.POINT.x, Strikes.POINT.y)
	var before: int = Strikes.hp_of(world, victim)
	Strikes.step(world, [Strikes.fire(Strikes.BORE_A)])
	var landing: int = world.strike_tick[1]
	assert_int(landing).is_equal(tick + 1 + Strikes.delay_of(world, "bore"))
	assert_int(Strikes.delay_of(world, "bore")).is_greater(1)
	assert_int(Strikes.hp_of(world, victim)).is_equal(before)
	while world.tick < landing - 1:
		Strikes.step(world)
		assert_int(Strikes.hp_of(world, victim)).is_equal(before)
		assert_int(world.strike_tick[1]).is_equal(landing)
	Strikes.step(world)
	assert_int(world.tick).is_equal(landing)
	var lost: int = Strikes.damage_on(world, world.index_of(victim))
	assert_int(lost).is_greater(0)
	assert_int(Strikes.hp_of(world, victim)).is_equal(before - lost)
	assert_array([world.strike_tick[1], world.strike_x[1], world.strike_y[1]]).is_equal(
		[0, Strikes.POINT.x, Strikes.POINT.y]
	)
	Strikes.run_to(world, landing + 5)
	assert_int(Strikes.hp_of(world, victim)).is_equal(before - lost)


## A row is hit when its squared distance from the point is at most the squared radius and not
## otherwise: on the radius along each axis and on a 3-4-5 diagonal it is hit, one milli beyond it
## is not, and the corner of the box around the circle is not. Own rows and neutral ones are hit
## like the enemy's.
@warning_ignore("integer_division")
func test_every_row_within_the_radius_is_hit_and_none_outside_by_squared_distance() -> void:
	var world: World = Strikes.world()
	var radius: int = Strikes.radius_of(world, "bore")
	var offsets: Array[Vector2i] = [Vector2i(0, 0), Vector2i(radius, 0), Vector2i(-radius, 0)]
	offsets.append_array([Vector2i(0, radius), Vector2i(0, -radius)])
	offsets.append_array([Vector2i(radius + 1, 0), Vector2i(0, -(radius + 1))])
	offsets.append_array([Vector2i(-(radius + 1), 0), Vector2i(0, radius + 1)])
	offsets.append(Vector2i(radius * 7 / 10, radius * 7 / 10))
	offsets.append(Vector2i(radius * 8 / 10, radius * 8 / 10))
	offsets.append(Vector2i(radius, radius))
	offsets.append(Vector2i(-radius * 6 / 10, radius * 8 / 10))
	offsets.append(Vector2i(radius * 6 / 10 + 1, -radius * 8 / 10))
	Strikes.run_to(world, Strikes.fire_tick(world, Strikes.BORE_A))
	var ids: Array[int] = []
	var owners: Array[int] = []
	for at: int in offsets.size():
		var x: int = Strikes.POINT.x + offsets[at].x
		var y: int = Strikes.POINT.y + offsets[at].y
		ids.append(Strikes.add(world, at % 3, "rifle", x, y))
		owners.append(at % 3)
	var before: Array[int] = []
	for id: int in ids:
		before.append(Strikes.hp_of(world, id))
	Strikes.step(world, [Strikes.fire(Strikes.BORE_A)])
	Strikes.run_to(world, world.strike_tick[1])
	var hit_owners: Array[int] = []
	var outside: int = 0
	for at: int in ids.size():
		var row: int = world.index_of(ids[at])
		assert_int(world.pos_x[row]).is_equal(Strikes.POINT.x + offsets[at].x)  # Nothing moved.
		var inside: bool = offsets[at].length_squared() <= radius * radius
		var lost: int = Strikes.damage_on(world, row) if inside else 0
		assert_int(world.hp[row]).override_failure_message(str(offsets[at])).is_equal(
			before[at] - lost
		)
		if inside and not hit_owners.has(owners[at]):
			hit_owners.append(owners[at])
		outside += 0 if inside else 1
	assert_array(hit_owners).contains_exactly_in_any_order([0, 1, 2])
	assert_int(outside).is_equal(7)


## The damage is the weapon's damage times its percent against the row's armour class, whichever
## class: the rig's four percents differ, so a class mixed up with another shows. The expected
## damage is taken from the weapon tables here, class by class.
@warning_ignore("integer_division")
func test_the_damage_is_the_weapons_damage_times_the_armour_percent_of_the_class() -> void:
	var world: World = Strikes.world()
	var weapon: int = world.type_strike_weapon[Strikes.type_of(world, "bore")]
	Strikes.run_to(world, Strikes.fire_tick(world, Strikes.BORE_A))
	var at: Vector2i = Strikes.POINT
	var ids: Dictionary[int, int] = {
		INFANTRY: Strikes.add(world, 2, "rifle", at.x - 1000, at.y),
		LIGHT: Strikes.add(world, 2, "jeep", at.x + 1000, at.y),
		HEAVY: Strikes.add(world, 2, "tank", at.x, at.y + 1000),
		BUILDING: world.add_building(2, Strikes.type_of(world, "shed"), 15, 10),
	}
	var before: Dictionary[int, int] = {}
	for armour: int in ids:
		before[armour] = Strikes.hp_of(world, ids[armour])
	Strikes.step(world, [Strikes.fire(Strikes.BORE_A)])
	Strikes.run_to(world, world.strike_tick[1])
	var seen: Array[int] = []
	for armour: int in ids:
		var percent: int = world.weapon_vs_armour[weapon * World.Armour.size() + armour]
		var expected: int = world.weapon_damage[weapon] * percent / 100
		(
			assert_int(before[armour] - Strikes.hp_of(world, ids[armour]))
			. override_failure_message("armour %d" % armour)
			. is_equal(expected)
		)
		assert_int(expected).is_greater(0)
		assert_bool(seen.has(expected)).is_false()
		seen.append(expected)


## A percent of 0 takes nothing, and a hit that the integer division would round to 0 takes 1, the
## rule of a shot (`Combat.fire`): the tables are changed here to make both cases.
func test_a_percent_of_0_hits_nothing_and_a_hit_takes_at_least_1() -> void:
	var world: World = Strikes.world()
	var weapon: int = world.type_strike_weapon[Strikes.type_of(world, "bore")]
	world.weapon_vs_armour[weapon * World.Armour.size() + LIGHT] = 0
	world.weapon_vs_armour[weapon * World.Armour.size() + INFANTRY] = 1
	world.weapon_damage[weapon] = 50  # 50 * 1 / 100 is 0.
	Strikes.run_to(world, Strikes.fire_tick(world, Strikes.BORE_A))
	var jeep: int = Strikes.add(world, 2, "jeep", Strikes.POINT.x, Strikes.POINT.y)
	var rifle: int = Strikes.add(world, 2, "rifle", Strikes.POINT.x + 500, Strikes.POINT.y)
	var before: Array[int] = [Strikes.hp_of(world, jeep), Strikes.hp_of(world, rifle)]
	Strikes.step(world, [Strikes.fire(Strikes.BORE_A)])
	Strikes.run_to(world, world.strike_tick[1])
	assert_int(before[0] - Strikes.hp_of(world, jeep)).is_equal(0)
	assert_int(before[1] - Strikes.hp_of(world, rifle)).is_equal(1)
	assert_array([Strikes.damage_on(world, world.index_of(jeep))]).is_equal([0])


## A warning of 0 ticks lands in the step of the command itself: the strike is pending for no step.
func test_a_warning_of_0_ticks_lands_in_the_step_of_the_command() -> void:
	var world: World = Strikes.world()
	world.type_strike_delay[Strikes.type_of(world, "bore")] = 0
	Strikes.run_to(world, Strikes.fire_tick(world, Strikes.BORE_A))
	var victim: int = Strikes.add(world, 2, "rifle", Strikes.POINT.x, Strikes.POINT.y)
	var before: int = Strikes.hp_of(world, victim)
	Strikes.step(world, [Strikes.fire(Strikes.BORE_A)])
	assert_int(world.dropped_commands).is_equal(0)
	assert_int(world.strike_tick[1]).is_equal(0)
	var lost: int = Strikes.damage_on(world, world.index_of(victim))
	assert_int(Strikes.hp_of(world, victim)).is_equal(before - lost)


## Each player has its own pending strike and lands it on its own tick: player 2 fires a tick after
## player 1 and its rupture lands a tick after, each taking its damage; when both land in one step
## the row takes both.
func test_each_players_rupture_lands_on_its_own_tick_and_two_in_one_step_both_hit() -> void:
	var staggered: World = Strikes.world()
	var bore: int = Strikes.type_of(staggered, "bore")
	var enemy: int = staggered.add_building(2, bore, 20, 2)
	var tick: int = Strikes.fire_tick(staggered, Strikes.BORE_A)
	Strikes.run_to(staggered, tick)
	var victim: int = Strikes.add(staggered, 0, "rifle", Strikes.POINT.x, Strikes.POINT.y)
	var before: int = Strikes.hp_of(staggered, victim)
	var lost: int = Strikes.damage_on(staggered, staggered.index_of(victim))
	Strikes.step(staggered, [Strikes.fire(Strikes.BORE_A)])
	Strikes.step(staggered, [Strikes.fire(enemy, 2)])
	var landing: int = staggered.strike_tick[1]
	assert_int(staggered.strike_tick[2]).is_equal(landing + 1)
	Strikes.run_to(staggered, landing)
	assert_int(Strikes.hp_of(staggered, victim)).is_equal(before - lost)
	assert_array([staggered.strike_tick[1], staggered.strike_tick[2]]).is_equal([0, landing + 1])
	Strikes.step(staggered)
	assert_int(Strikes.hp_of(staggered, victim)).is_equal(before - 2 * lost)
	assert_int(staggered.strike_tick[2]).is_equal(0)
	var together: World = Strikes.world()
	var twin: int = together.add_building(2, bore, 20, 2)
	Strikes.run_to(together, tick)
	var other: int = Strikes.add(together, 0, "rifle", Strikes.POINT.x, Strikes.POINT.y)
	Strikes.step(together, [Strikes.fire(Strikes.BORE_A), Strikes.fire(twin, 2)])
	assert_int(together.dropped_commands).is_equal(0)
	assert_int(together.strike_tick[1]).is_equal(together.strike_tick[2])
	Strikes.run_to(together, together.strike_tick[1])
	assert_int(Strikes.hp_of(together, other)).is_equal(before - 2 * lost)


## A strike in the air is not recalled: the death of the building that fired it and the defeat of
## its player (a surrender, in a match of three that goes on) change nothing, and the rupture lands
## with its point and numbers.
func test_a_rupture_in_the_air_is_not_recalled_by_the_loss_of_its_building_or_a_defeat() -> void:
	var world: World = Strikes.world(true, 3)
	var tick: int = Strikes.fire_tick(world, Strikes.BORE_A)
	Strikes.run_to(world, tick)
	var victim: int = Strikes.add(world, 2, "rifle", Strikes.POINT.x, Strikes.POINT.y)
	var before: int = Strikes.hp_of(world, victim)
	Strikes.step(world, [Strikes.fire(Strikes.BORE_A)])
	world.hp[world.index_of(Strikes.BORE_A)] = 0
	Strikes.step(world, [Command.surrender(1)])
	assert_int(world.index_of(Strikes.BORE_A)).is_equal(-1)
	assert_int(world.defeated_tick[1]).is_not_equal(0)
	assert_int(world.match_end_tick).is_equal(0)
	assert_int(world.strike_tick[1]).is_not_equal(0)
	Strikes.run_to(world, tick + 1 + Strikes.delay_of(world, "bore"))
	assert_int(world.strike_tick[1]).is_equal(0)
	assert_int(Strikes.hp_of(world, victim)).is_equal(
		before - Strikes.damage_on(world, world.index_of(victim))
	)


## The landing reads the radius and the weapon of the first rupture type (the pending strike stores
## no type): with no such type, or with a type that has no weapon, it clears and hits nothing.
func test_a_landing_with_no_rupture_type_or_no_weapon_clears_and_hits_nothing() -> void:
	var world: World = Strikes.world()
	var bore: int = Strikes.type_of(world, "bore")
	assert_int(Strike.rupture_type(world)).is_equal(bore)
	world.type_strike_kind[Strikes.type_of(world, "array")] = Strike.Kind.RUPTURE
	assert_int(Strike.rupture_type(world)).is_equal(bore)  # The lowest index of the kind.
	for label: String in ["no type", "no weapon"]:
		var world_case: World = Strikes.world()
		Strikes.run_to(world_case, Strikes.fire_tick(world_case, Strikes.BORE_A))
		var victim: int = Strikes.add(world_case, 2, "rifle", Strikes.POINT.x, Strikes.POINT.y)
		var before: int = Strikes.hp_of(world_case, victim)
		Strikes.step(world_case, [Strikes.fire(Strikes.BORE_A)])
		if label == "no type":
			world_case.type_strike_kind[bore] = Strike.Kind.NONE
			assert_int(Strike.rupture_type(world_case)).is_equal(-1)
		else:
			world_case.type_strike_weapon[bore] = -1
		Strikes.run_to(world_case, world_case.strike_tick[1])
		assert_int(world_case.strike_tick[1]).override_failure_message(label).is_equal(0)
		assert_int(Strikes.hp_of(world_case, victim)).override_failure_message(label).is_equal(
			before
		)
