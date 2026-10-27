extends GdUnitTestSuite
## `SpawnDef.charge_elapsed_ticks` (plan row P80, ADR 0021 section 2, ADR 0023 sections 10 and 14):
## a scenario's strike building may start part-way through its charge, so that the base arena's
## 900 ticks can fire its strikes. `WorldLoad` takes the ticks off the `ready_tick` that
## `Strike.start_charge` set (not below 0), a block that is no strike building keeps 0, a negative
## value takes nothing, and the first SUPERWEAPON accepted is the one stamped `charge_ticks -
## charge_elapsed_ticks` ticks into the match and not a tick earlier. The numbers are read from the
## Deep Bore's data file, so a retune moves no case.

const BORE_PATH: String = "res://data/units/fossil_strike.tres"
const HQ_PATH: String = "res://data/units/headquarters.tres"
## The first tick the aged bore accepts in the order cases.
const FIRST_TICK: int = 40

@warning_ignore("integer_division")
func test_a_strike_block_starts_that_many_ticks_into_its_charge_and_never_below_zero() -> void:
	var bore: BuildingDef = load(BORE_PATH) as BuildingDef
	var charge: int = bore.charge_ticks
	assert_int(charge).is_greater(FIRST_TICK)
	# elapsed, then the ready_tick it must give (the stamp of tick 0 is 1).
	var cases: Array[Array] = [
		[0, 1 + charge],
		[1000, 1 + charge - 1000],
		[charge - 1, 2],
		[charge, 1],
		[charge + 1, 0],
		[charge * 2, 0],
		[-50, 1 + charge],
	]
	var spawns: Array[SpawnDef] = []
	for index: int in cases.size():
		spawns.append(_spawn(bore, Vector2i(index * 8, 0), cases[index][0], 2))
	var world: World = World.from_scenario(_scenario(spawns, []))
	assert_int(world.unit_count()).is_equal(cases.size() * 2)
	for row: int in world.unit_count():
		var expected: int = cases[row / 2][1]
		(
			assert_int(world.ready_tick[row])
			. override_failure_message("row %d, elapsed %d" % [row, cases[row / 2][0]])
			. is_equal(expected)
		)
	assert_int(world.spawn_refused).is_equal(0)


## A block of buildings with no strike keeps a ready_tick of 0, and so does a unit block: the value
## is read for strike buildings only.
func test_a_block_that_is_no_strike_building_keeps_a_ready_tick_of_zero() -> void:
	var bore: BuildingDef = load(BORE_PATH) as BuildingDef
	var hq: BuildingDef = load(HQ_PATH) as BuildingDef
	assert_int(hq.strike_kind).is_equal(Strike.Kind.NONE)
	var world: World = (
		World
		. from_scenario(
			_scenario(
				[
					_spawn(hq, Vector2i(0, 0), bore.charge_ticks, 1),
					_spawn(bore, Vector2i(4, 0), 100, 1),
				],
				[]
			)
		)
	)
	assert_int(world.unit_count()).is_equal(2)
	assert_int(world.ready_tick[0]).is_equal(0)
	assert_int(world.ready_tick[1]).is_equal(1 + bore.charge_ticks - 100)


## The order is accepted on the tick the aged charge ends and not one before: with the whole charge
## but FIRST_TICK ticks behind it, a SUPERWEAPON at FIRST_TICK - 1 is dropped and counted, one at
## FIRST_TICK writes the pending rupture, and a bore with no ticks behind it drops both.
func test_the_order_is_accepted_on_the_first_tick_the_aged_charge_allows_and_not_one_before(
) -> void:
	var bore: BuildingDef = load(BORE_PATH) as BuildingDef
	for tick: int in [FIRST_TICK - 1, FIRST_TICK]:
		var spawns: Array[SpawnDef] = [
			_spawn(bore, Vector2i(0, 0), bore.charge_ticks - FIRST_TICK, 1)
		]
		var order: OrderDef = OrderDef.new()
		order.tick = tick
		order.player = 1
		order.type = Command.Type.SUPERWEAPON
		order.target_tile = Vector2i(10, 8)
		order.unit = bore
		var scenario: ScenarioDef = _scenario(spawns, [order])
		var world: World = World.from_scenario(scenario, DetRandom.create(1, DetRandom.STREAM_SIM))
		var loop: MatchLoop = MatchLoop.create(scenario, "", 1, world)
		var none: Array[Command] = []
		for _step: int in tick + 1:
			loop.step(world, none)
		var fired: bool = tick >= FIRST_TICK
		assert_int(world.dropped_commands).override_failure_message(str(tick)).is_equal(
			0 if fired else 1
		)
		assert_int(world.strike_tick[1]).override_failure_message(str(tick)).is_equal(
			tick + 1 + bore.strike_delay if fired else 0
		)
	var whole: Array[SpawnDef] = [_spawn(bore, Vector2i(0, 0), 0, 1)]
	var late: OrderDef = OrderDef.new()
	late.tick = FIRST_TICK
	late.player = 1
	late.type = Command.Type.SUPERWEAPON
	late.target_tile = Vector2i(10, 8)
	late.unit = bore
	var untouched: ScenarioDef = _scenario(whole, [late])
	var world: World = World.from_scenario(untouched, DetRandom.create(1, DetRandom.STREAM_SIM))
	var loop: MatchLoop = MatchLoop.create(untouched, "", 1, world)
	var none: Array[Command] = []
	for _step: int in FIRST_TICK + 1:
		loop.step(world, none)
	assert_array([world.dropped_commands, world.strike_tick[1]]).is_equal([1, 0])


func _spawn(unit: UnitDef, origin: Vector2i, elapsed: int, count: int) -> SpawnDef:
	var spawn: SpawnDef = SpawnDef.new()
	spawn.owner = 1
	spawn.unit = unit
	spawn.count = count
	spawn.origin_tile = origin
	spawn.columns = count
	spawn.charge_elapsed_ticks = elapsed
	return spawn


func _scenario(spawns: Array[SpawnDef], orders: Array[OrderDef]) -> ScenarioDef:
	var scenario: ScenarioDef = ScenarioDef.new()
	scenario.map_size_tiles = Vector2i(64, 12)
	scenario.player_count = 2
	scenario.spawns = spawns
	scenario.orders = orders
	return scenario
