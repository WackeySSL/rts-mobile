class_name MatchSummary
extends RefCounted
## What a finished match or lesson tells `Progression` (ADR 0045 section 2). Plain data, built by
## `MenuFlow` from the last published snapshot and the `MatchSetup`. An abandoned match (Exit to
## menu, a failed restore) never gets an award: `Progression.award_match` returns null for it.

const OUTCOME_WIN: StringName = &"win"
const OUTCOME_LOSS: StringName = &"loss"
const OUTCOME_DRAW: StringName = &"draw"
const OUTCOME_SURRENDER: StringName = &"surrender"
const OUTCOME_ABANDONED: StringName = &"abandoned"

var outcome: StringName = OUTCOME_ABANDONED
## The AI difficulty id (`easy`, `normal`, `hard`).
var level: StringName = &"normal"
var map_id: StringName = &""
var ticks: int = 0
var local_side: int = 1
## The lesson id, or empty for a skirmish.
var lesson_id: StringName = &""
## The local player's faction id (`fossil`, `renew`), empty when unknown (ADR 0054 section 3).
var faction: StringName = &""
## The local side's end-of-match counts, copied from the snapshot's `stat_*` (0 when the side is out
## of range). A sold building is no loss (the sim's own rule).
var built: int = 0
var lost_units: int = 0
var lost_buildings: int = 0
var harvested: int = 0
## The distinct type ids of the local side's rows with hit points above 0 at the end.
var standing_types: Array[StringName] = []


## The outcome from the snapshot's `winner` and `match_end_tick`; `surrendered` is the local
## player's own Surrender command (the sim cannot tell it from a defeat). A match with no end yet
## is abandoned.
static func from_snapshot(
	snapshot: MatchSnapshot,
	setup_level: StringName,
	setup_map_id: StringName,
	side: int,
	surrendered: bool,
	setup_lesson_id: StringName = &"",
	setup_faction: StringName = &""
) -> MatchSummary:
	var summary: MatchSummary = MatchSummary.new()
	summary.level = setup_level
	summary.map_id = setup_map_id
	summary.ticks = snapshot.tick
	summary.local_side = side
	summary.lesson_id = setup_lesson_id
	summary.faction = setup_faction
	summary._copy_facts(snapshot)
	# The sim decides first: no end is abandoned even after a Surrender command, and a win stays
	# a win.
	if snapshot.match_end_tick <= 0:
		summary.outcome = OUTCOME_ABANDONED
	elif snapshot.winner == side:
		summary.outcome = OUTCOME_WIN
	elif surrendered:
		summary.outcome = OUTCOME_SURRENDER
	elif snapshot.winner == 0:
		summary.outcome = OUTCOME_DRAW
	else:
		summary.outcome = OUTCOME_LOSS
	return summary


## A lesson played to its last beat: a win for `Progression` (ADR 0045 section 2, a lesson pays
## `lesson_xp` once), since a lesson ends on its beats and not on a match end.
static func for_lesson(
	setup_lesson_id: StringName,
	setup_level: StringName,
	setup_map_id: StringName,
	side: int,
	ticks_played: int,
	setup_faction: StringName = &"",
	snapshot: MatchSnapshot = null
) -> MatchSummary:
	var summary: MatchSummary = MatchSummary.new()
	summary.outcome = OUTCOME_WIN
	summary.level = setup_level
	summary.map_id = setup_map_id
	summary.ticks = ticks_played
	summary.local_side = side
	summary.lesson_id = setup_lesson_id
	summary.faction = setup_faction
	summary._copy_facts(snapshot)
	return summary


## Copies the local side's stats and standing types from `snapshot` (null leaves the defaults).
## One pass over the rows, run once at the end of a match, never per tick.
func _copy_facts(snapshot: MatchSnapshot) -> void:
	if snapshot == null:
		return
	built = _stat(snapshot.stat_built)
	lost_units = _stat(snapshot.stat_lost_units)
	lost_buildings = _stat(snapshot.stat_lost_buildings)
	harvested = _stat(snapshot.stat_harvested)
	standing_types.clear()
	for row: int in snapshot.owner.size():
		if snapshot.owner[row] != local_side or snapshot.hp[row] <= 0:
			continue
		var type_index: int = snapshot.type_index[row]
		if type_index < 0 or type_index >= snapshot.type_ids.size():
			continue
		var type_id: StringName = snapshot.type_ids[type_index]
		if not standing_types.has(type_id):
			standing_types.append(type_id)


func _stat(column: PackedInt32Array) -> int:
	if local_side < 0 or local_side >= column.size():
		return 0
	return column[local_side]
