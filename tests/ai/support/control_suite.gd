extends "res://tests/ai/support/wave_suite.gd"
## The base of the Hard unit-control and recall suites (plan row P180b): the wave suite's World with
## the army made on a copy of Normal's level that holds the suite's own unit-control numbers. Not a
## test suite.

## A heavy tank's hp (data), the step-back percent the suite plays (Hard ships 30) and where the
## staging point is, in milli-tiles.
const TANK_HP: int = 650
const STEP_PERCENT: int = 30
const STAGE_AT: Vector2i = Vector2i(11500, 11500)
## A spot for a wave in the field, and a spot of the base: 8 tiles east of the Headquarters.
const FIELD: Vector2i = Vector2i(20500, 20500)
const NEAR: Vector2i = Vector2i(15500, 7500)


## The suite's level with the step-back percent `hp_percent`, `focus` (0 or 1) and the ratio, on a
## def without the unseen-hit shift (a unit's hp lost here is not a hit the squad answers).
func _control(
	hp_percent: int, focus: int, ratio: int = RATIO_PERCENT, def: OpponentDef = null
) -> void:
	var level: AiDifficultyDef = _level(0, ratio)
	level.unit_retreat_hp_percent = hp_percent
	level.focus_fire = focus
	var own: OpponentDef = def if def != null else _def()
	own.unseen_hit_shift_tiles = 0
	_arm_waves(level, own)


## Sets the hp of the unit `id` (any owner).
func _hp(id: int, hp: int) -> void:
	_world.hp[_row_in_world(id)] = hp


## Launches the first wave with two tanks (a, b ascending) and the squads: value 2200. Returns the
## two tanks' ids.
func _two_tanks() -> PackedInt32Array:
	_target_at()
	var a: int = _tank()
	var b: int = _tank(10500, 9500)
	_settle()
	_until(LAUNCH)
	assert_int(_memory.wave_count).is_equal(1)
	return PackedInt32Array([a, b])


## Puts every unit of the wave on the field's spot and kills the enemy's two starting squads (they
## would count near it).
func _to_field() -> void:
	for id: int in AiRig.ids_of(_world, 2, "rifle_squad"):
		_hp(id, 0)
	AiRig.step(_world, _loop)
	for id: int in _members(AiArmy.WAVE):
		_put(id, FIELD.x, FIELD.y)


## Kills the unit `id` and lets the World drop it.
func _kill(id: int) -> void:
	_hp(id, 0)
	AiRig.step(_world, _loop)
	_see_all()
