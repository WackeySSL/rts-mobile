extends GdUnitTestSuite
## The "Strike test" scenario (plan row P112d, ADR 0023 section 10): the data file
## `data/scenarios/dev_strikes.tres`, the one place on `main` where the local player owns a strike
## building, so the phone preview can fire a rupture and a blackout. Player 1 (the Derrick League)
## owns a Headquarters, power, a Deep Bore that is charged at once and a Blackout Array that
## charges for four more seconds. Player 2 (the Lumen Accord) is a small base across 6 tiles of
## open ground, in sight of player 1's six tanks and out of everyone's weapon range, with
## buildings of all three footprints and a few units. Nobody plays player 2 (the main scene sets
## no opponent), so the base stays as it is. What the screen does with it is
## test_dev_strike_route's. The layout numbers are literals (the data are layout); every rule
## number is read from the World.

const PATH: String = "res://data/scenarios/dev_strikes.tres"
const MAP_PATH: String = "res://data/maps/controls_test.tres"
const SEED: int = 1
## The Blackout Array is ready this many ticks into the match (four seconds); the Deep Bore at once.
const ARRAY_READY_TICKS: int = 60
## A quiet stretch of the match: ten seconds with nobody giving an order.
const QUIET_TICKS: int = 150
## The point between the enemy Headquarters and its two batteries, and the middle of its base.
const RUPTURE_POINT: Vector2i = Vector2i(29000, 12000)
const BLACKOUT_POINT: Vector2i = Vector2i(30000, 12500)

var _scenario: ScenarioDef
var _world: World
var _loop: MatchLoop


func before_test() -> void:
	_scenario = load(PATH) as ScenarioDef
	_world = World.from_scenario(_scenario, DetRandom.create(SEED, DetRandom.STREAM_SIM))
	_loop = MatchLoop.create(_scenario, PATH, SEED, _world)


func test_the_scenario_is_two_players_one_in_each_faction_on_the_test_map_with_no_orders() -> void:
	assert_int(_scenario.player_count).is_equal(2)
	assert_int(_scenario.local_player).is_equal(1)
	assert_str(_scenario.map.resource_path).is_equal(MAP_PATH)
	assert_that(_scenario.map_size_tiles).is_equal(_scenario.map.size_tiles())
	assert_array(_scenario.orders).is_empty()
	assert_int(_scenario.factions.size()).is_equal(3)
	assert_array([_scenario.factions[1].id, _scenario.factions[2].id]).is_equal(
		[&"fossil", &"renew"]
	)
	assert_int(_world.spawn_refused).is_equal(0)


func test_player_one_owns_a_headquarters_power_a_deep_bore_and_a_blackout_array() -> void:
	var owned: Dictionary[StringName, int] = _owned(1)
	for id: StringName in [&"headquarters", &"fossil_strike", &"renew_strike"]:
		assert_int(owned.get(id, 0)).override_failure_message(str(id)).is_equal(1)
	assert_int(owned.get(&"power_plant", 0)).is_greater(0)
	# The first row is the Headquarters: the build sidebar takes the player's faction from it.
	assert_str(String(_world.type_ids[_world.type_index[_first_row(1)]])).is_equal("headquarters")
	var made: int = 0
	var used: int = 0
	for row: int in _world.unit_count():
		var power: int = _world.type_power[_world.type_index[row]]
		if _world.owner[row] == 1:
			made += maxi(power, 0)
			used += maxi(-power, 0)
	assert_int(made).is_greater_equal(used)  # No low power to start with.


func test_the_deep_bore_is_ready_at_once_and_the_blackout_array_within_four_seconds() -> void:
	var bore: int = _row_of(&"fossil_strike")
	var array: int = _row_of(&"renew_strike")
	# The first step has the stamp world.tick + 1 = 1.
	assert_int(_world.ready_tick[bore]).is_less_equal(_world.tick + 1)
	assert_int(_world.ready_tick[array] - (_world.tick + 1)).is_equal(ARRAY_READY_TICKS)
	assert_int(ARRAY_READY_TICKS).is_less_equal(5 * Sim.TICK_RATE)


func test_the_enemy_base_shows_all_three_footprints_to_player_one_with_a_few_units() -> void:
	var seen: Dictionary[Vector2i, int] = {}
	var units: int = 0
	for row: int in _world.unit_count():
		if _world.owner[row] != 2:
			continue
		var type: int = _world.type_index[row]
		if _world.type_speed[type] > 0:
			units += 1
		elif _visible_to_player_one(row):
			var size: Vector2i = Vector2i(_world.type_foot_w[type], _world.type_foot_h[type])
			seen[size] = seen.get(size, 0) + 1
	assert_array(seen.keys()).contains_exactly_in_any_order(
		[Vector2i(1, 1), Vector2i(2, 2), Vector2i(3, 3)]
	)
	assert_int(units).is_between(3, 8)


## Nothing is in anyone's weapon reach at the start, so the match is quiet until the player moves:
## ten seconds with no order lose no hit point and no row.
func test_nobody_fights_before_the_player_gives_an_order() -> void:
	var rows: int = _world.unit_count()
	var hit_points: PackedInt32Array = _world.hp.duplicate()
	var none: Array[Command] = []
	for _tick: int in QUIET_TICKS:
		_loop.step(_world, none)
	assert_int(_world.unit_count()).is_equal(rows)
	assert_array(_world.hp).is_equal(hit_points)
	assert_int(_world.defeated_tick[1]).is_equal(0)
	assert_int(_world.defeated_tick[2]).is_equal(0)


func test_a_rupture_from_player_one_is_accepted_and_hits_the_enemy_buildings_around_its_point(
) -> void:
	var before: PackedInt32Array = _world.hp.duplicate()
	var bore_id: int = _world.unit_id[_row_of(&"fossil_strike")]
	_loop.step(_world, [Command.superweapon(1, bore_id, RUPTURE_POINT.x, RUPTURE_POINT.y)])
	assert_int(_world.dropped_commands).is_equal(0)
	assert_int(_world.strike_tick[1]).is_not_equal(0)  # In the air for the warning.
	var delay: int = _world.type_strike_delay[_world.type_index[_row_of(&"fossil_strike")]]
	for _tick: int in delay:
		_loop.step(_world, [])
	assert_int(_world.strike_tick[1]).is_equal(0)
	var hit: Array[StringName] = []
	for row: int in before.size():
		if _world.hp[row] < before[row]:
			assert_int(_world.owner[row]).is_equal(2)  # Player 1's rows are far from the point.
			hit.append(_world.type_ids[_world.type_index[row]])
	assert_array(hit).contains([&"renew_hq", &"renew_defence"])
	assert_int(hit.size()).is_greater_equal(3)


func test_a_blackout_from_player_one_waits_for_its_charge_then_takes_the_enemy_base_offline(
) -> void:
	var array_id: int = _world.unit_id[_row_of(&"renew_strike")]
	var fire: Command = Command.superweapon(1, array_id, BLACKOUT_POINT.x, BLACKOUT_POINT.y)
	_loop.step(_world, [fire])  # Still charging: dropped, and nothing is offline.
	assert_int(_world.dropped_commands).is_equal(1)
	assert_int(_offline_enemy_buildings().size()).is_equal(0)
	while _world.tick < ARRAY_READY_TICKS:
		_loop.step(_world, [])
	_loop.step(_world, [Command.superweapon(1, array_id, BLACKOUT_POINT.x, BLACKOUT_POINT.y)])
	assert_int(_world.dropped_commands).is_equal(1)  # The second one was taken.
	var offline: Array[int] = _offline_enemy_buildings()
	assert_int(offline.size()).is_greater_equal(5)
	var sizes: Dictionary[Vector2i, bool] = {}
	for row: int in offline:
		var type: int = _world.type_index[row]
		sizes[Vector2i(_world.type_foot_w[type], _world.type_foot_h[type])] = true
	assert_array(sizes.keys()).contains_exactly_in_any_order(
		[Vector2i(1, 1), Vector2i(2, 2), Vector2i(3, 3)]
	)


## A rupture holds every strike building of its player until it lands, so the blackout follows the
## rupture: both of the phone steps work one after the other, in that order. The rupture fires at
## the first tick, the earliest a player can; the blackout waits for the landing and its charge.
func test_the_blackout_can_follow_the_rupture_once_it_has_landed() -> void:
	var bore_id: int = _world.unit_id[_row_of(&"fossil_strike")]
	var array_id: int = _world.unit_id[_row_of(&"renew_strike")]
	_loop.step(_world, [Command.superweapon(1, bore_id, RUPTURE_POINT.x, RUPTURE_POINT.y)])
	var delay: int = _world.type_strike_delay[_world.type_index[_row_of(&"fossil_strike")]]
	while _world.strike_tick[1] != 0 or _world.tick < maxi(delay, ARRAY_READY_TICKS):
		_loop.step(_world, [])
	_loop.step(_world, [Command.superweapon(1, array_id, BLACKOUT_POINT.x, BLACKOUT_POINT.y)])
	assert_int(_world.dropped_commands).is_equal(0)
	assert_int(_offline_enemy_buildings().size()).is_greater(0)


## Rows of `player` by type id.
func _owned(player: int) -> Dictionary[StringName, int]:
	var owned: Dictionary[StringName, int] = {}
	for row: int in _world.unit_count():
		if _world.owner[row] == player:
			var id: StringName = _world.type_ids[_world.type_index[row]]
			owned[id] = owned.get(id, 0) + 1
	return owned


func _first_row(player: int) -> int:
	for row: int in _world.unit_count():
		if _world.owner[row] == player:
			return row
	return -1


## The row of the one building of type `id`.
func _row_of(id: StringName) -> int:
	for row: int in _world.unit_count():
		if _world.type_ids[_world.type_index[row]] == id:
			return row
	return -1


## Whether any cell of the building `row` is in sight of player 1 at the start of the match.
func _visible_to_player_one(row: int) -> bool:
	var type: int = _world.type_index[row]
	var origin: Vector2i = _world.footprint_origin(row)
	for dx: int in _world.type_foot_w[type]:
		for dy: int in _world.type_foot_h[type]:
			if _world.fog.is_visible(1, (origin.y + dy) * _world.map_cols + origin.x + dx):
				return true
	return false


## The rows of player 2's buildings that are offline now.
func _offline_enemy_buildings() -> Array[int]:
	var rows: Array[int] = []
	for row: int in _world.unit_count():
		var type: int = _world.type_index[row]
		if _world.owner[row] == 2 and _world.type_foot_w[type] > 0:
			if _world.offline_until[row] > _world.tick:
				rows.append(row)
	return rows
