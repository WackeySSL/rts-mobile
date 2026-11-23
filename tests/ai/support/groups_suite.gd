extends "res://tests/ai/support/wave_suite.gd"
## The base of the grouped-wave suites (plan row P250e): the wave suite's World and numbers with the
## group fields of the level set by the case. Not a test suite.

## The suite's group numbers: the group size, the gather time, the regroup spread (tiles) and cap,
## and the lead percent of the closing push.
const GROUP_MIN: int = 3
const GATHER: int = 300
const SPREAD: int = 5
const CAP: int = 120
const LEAD: int = 200


## The army suite's def with the stall answer off: the hand-built wave stands still and idle, which
## the answer would take for a stall (its own suite, P555b, owns it).
func _def() -> OpponentDef:
	var def: OpponentDef = super()
	def.stall_window_ticks = 0
	return def


## The managers on the suite's level with the group fields given (the default 0 is off).
func _grouped(
	group_min: int = GROUP_MIN, gather: int = GATHER, spread: int = 0, cap: int = CAP, lead: int = 0
) -> void:
	var level: AiDifficultyDef = _level()
	level.group_min_size = group_min
	level.group_gather_ticks = gather
	level.wave_regroup_spread_tiles = spread
	level.wave_regroup_ticks = cap
	level.wave_lead_percent = lead
	_arm_waves(level)


## The first wave launched by strength and the thinks up to the tick before the all-in; returns the
## wave's tank.
func _wave_before_all_in() -> int:
	var tank: int = _launched()
	_until(ALL_IN - 15)
	return tank


## The Commands of `_out` that are an ATTACK_MOVE, the ids of the first one.
func _first_ids() -> PackedInt32Array:
	var sent: Array[Command] = _of(Command.Type.ATTACK_MOVE)
	return sent[0].unit_ids if not sent.is_empty() else PackedInt32Array()
