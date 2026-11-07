extends "res://tests/ai/support/army_suite.gd"
## The base of the wave suites (plan row P180): the army suite's World with the army made on a copy
## of Normal's level that holds the suite's own wave numbers, so a tuning row of `data/ai/` cannot
## move them. The first ARMY slot is tick 5 and the slots are 15 ticks apart. Not a test suite.

## The suite's wave numbers: first tick, first strength (a heavy tank and the two starting rifle
## squads: 1000 + 100 + 100), growth in percent, all-in tick, and the two retreat tests.
const FIRST_TICK: int = 100
const STRENGTH: int = 1200
const GROWTH: int = 50
const ALL_IN: int = 2000
const RETREAT_PERCENT: int = 50
const RATIO_PERCENT: int = 200
## The ticks a threat must stand before the defence answers.
const REACTION: int = 30
## The first think after `FIRST_TICK` on the slots 5, 20, 35, ...
const LAUNCH: int = 110
## The point mirror of the Headquarters' tile: the target while no enemy producer is known.
const TARGET: Vector2i = Vector2i(32, 32)


func before_test() -> void:
	super()
	_arm_waves()


## A copy of Normal's level with the suite's wave numbers and a start jitter of `jitter` ticks.
func _level(jitter: int = 0) -> AiDifficultyDef:
	var level: AiDifficultyDef = Rig.level_of("normal").duplicate() as AiDifficultyDef
	level.reaction_ticks = REACTION
	level.wave_first_tick = FIRST_TICK
	level.wave_first_strength = STRENGTH
	level.wave_growth_percent = GROWTH
	level.wave_jitter_ticks = jitter
	level.all_in_tick = ALL_IN
	level.retreat_percent = RETREAT_PERCENT
	level.retreat_ratio_percent = RATIO_PERCENT
	return level


## The managers on `level` (the suite's when null) and a fresh memory; `def` as `_arm`.
func _arm_waves(level: AiDifficultyDef = null, def: OpponentDef = null) -> void:
	var own: OpponentDef = def if def != null else _def()
	_make("normal")
	_memory = AiMemory.create(own)
	_army = AiArmy.create(own, level if level != null else _level(), 1)


## The base estimate by hand (the intel slot is not run).
func _target_at(tile: Vector2i = TARGET) -> void:
	_memory.base_x = tile.x
	_memory.base_y = tile.y


## An own heavy tank (beside the squads by default); returns its id.
func _tank(x: int = 9500, y: int = 9500) -> int:
	return AiRig.add_unit_of(_world, 1, "heavy_tank", x, y)


## The INTEL slot then the ARMY slot of one tick, so the base estimate is intel's own.
func _both(tick: int, budget: int = 8) -> void:
	_run(tick, budget)
	_think(tick, budget)


## Think on the slots 5, 20, ... up to and including `last`, keeping the Commands of the last.
func _until(last: int) -> void:
	for tick: int in range(5, last + 1, 15):
		_think(tick)


## The ids of squad `squad`'s members in the memory.
func _members(squad: int) -> PackedInt32Array:
	var found: PackedInt32Array = PackedInt32Array()
	for at: int in _memory.member_id.size():
		if _memory.member_squad[at] == squad:
			found.append(_memory.member_id[at])
	return found


## The squads and a tank, ascending: what a launch sends.
func _all_ids(tank: int) -> PackedInt32Array:
	var ids: PackedInt32Array = _squads()
	ids.append(tank)
	return ids


## Launches the first wave with the squads and one tank at `LAUNCH`; returns the tank's id.
func _launched() -> int:
	_target_at()
	var tank: int = _tank()
	_settle()
	_until(LAUNCH)
	assert_int(_memory.wave_count).is_equal(1)
	return tank


## The memory's squad table, goal keys and counters, copied, to compare before and after a refusal.
func _freeze() -> Array:
	return [
		_memory.member_squad.duplicate(),
		_memory.squad_role.duplicate(),
		_memory.goal_snapshot(),
		_memory.wave_count,
		_army.waves,
		_army.retreats,
	]
