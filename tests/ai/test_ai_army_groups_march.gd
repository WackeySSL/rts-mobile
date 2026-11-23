extends "res://tests/ai/support/groups_suite.gd"
## Grouped waves on the move (plan row P250e): tanks come off the line one by one, the AI thinks on
## every 15th tick and the sim runs, so the march is real. With the gather the wave leaves as one
## group and arrives within a few tiles of its own spread; without it the same tanks string out. A
## leader with a clear lead over a small base closes it out.

## One tank every `LINE` ticks at the staging point; `TANKS` of them; the all-in from tick 100.
const LINE: int = 75
const TANKS: int = 4
const ALL_IN_AT: int = 100
## The distance to the target (tiles) at which a wave counts as arrived.
const ARRIVE: int = 14
## The most the grouped wave's members may be apart when the first of them arrives, in tiles.
const GROUPED_SPREAD: int = 4
## The ticks the leader has to take the barracks.
const CLOSE_BOUND: int = 1500


func before_test() -> void:
	super()
	# The suite's tanks only: the two starting rifle squads of the rig walk slower than tanks.
	for id: int in _squads():
		_world.hp[_row_in_world(id)] = 0
	AiRig.step(_world, _loop)


## The level of the suite with the all-in at `ALL_IN_AT`, grouped (a group of `TANKS`) or not.
func _march_level(grouped: bool) -> AiDifficultyDef:
	var level: AiDifficultyDef = _level()
	level.all_in_tick = ALL_IN_AT
	level.wave_first_tick = 100000
	level.group_min_size = TANKS if grouped else 0
	level.group_gather_ticks = 600
	return level


## Plays the march to the tick the first wave member is within `ARRIVE` tiles of the target (at
## most 900 ticks) and returns the most two live wave members are apart then, in tiles.
func _spread_on_arrival(grouped: bool) -> int:
	_arm_waves(_march_level(grouped))
	_target_at()
	var made: int = 0
	for _step: int in 900:
		var tick: int = _world.tick
		if made < TANKS and tick % LINE == 0:
			_tank(11500, 11500)
			made += 1
		var commands: Array = []
		if tick % 15 == 5:
			_think(tick)
			commands = _out
		AiRig.step(_world, _loop, commands)
		var wave: Array[Vector2i] = _wave_places()
		if _nearest_to_target(wave) <= ARRIVE:
			return _widest(wave)
	return -1


func _wave_places() -> Array[Vector2i]:
	var places: Array[Vector2i] = []
	for id: int in _members(AiArmy.WAVE):
		var row: int = _row_in_world(id)
		if row >= 0:
			places.append(Vector2i(_world.pos_x[row], _world.pos_y[row]))
	return places


## The distance of the wave member nearest to the target, in tiles (999 for an empty wave).
func _nearest_to_target(places: Array[Vector2i]) -> int:
	var least: int = 999
	for at: Vector2i in places:
		least = mini(least, FixedMath.isqrt((at - TARGET * 1000).length_squared()) / 1000)
	return least


## The most two of `places` are apart, in tiles.
func _widest(places: Array[Vector2i]) -> int:
	var most: int = 0
	for first: Vector2i in places:
		for second: Vector2i in places:
			most = maxi(most, FixedMath.isqrt((first - second).length_squared()) / 1000)
	return most


func test_a_grouped_wave_arrives_within_a_few_tiles_of_its_own_spread() -> void:
	var spread: int = _spread_on_arrival(true)
	assert_int(spread).is_between(0, GROUPED_SPREAD)


func test_the_same_tanks_without_the_gather_arrive_strung_out() -> void:
	var spread: int = _spread_on_arrival(false)
	assert_int(spread).is_greater(GROUPED_SPREAD)


## The closing push: five tanks leave as a group, three more come later, and the enemy has only its
## Headquarters, its two squads and a barracks near the target. The barracks dies within the bound.
func test_a_leader_with_a_clear_lead_kills_the_producer_within_the_bound() -> void:
	_arm_waves(_march_level(true))
	_target_at()
	var barracks: int = AiRig.give(_world, 2, "barracks", 29, 29)
	_see_all()
	var made: int = 0
	var killed_at: int = -1
	for _step: int in CLOSE_BOUND:
		var tick: int = _world.tick
		if made < 8 and (made == 0 or (made >= 5 and tick % 150 == 0)):
			var batch: int = 5 if made == 0 else 1
			for _unit: int in batch:
				_tank(11500, 11500)
				made += 1
		var commands: Array = []
		if tick % 15 == 5:
			_think(tick)
			commands = _out
		AiRig.step(_world, _loop, commands)
		if _row_in_world(barracks) < 0:
			killed_at = _world.tick
			break
	assert_int(killed_at).is_between(1, CLOSE_BOUND)
