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


## The outcome from the snapshot's `winner` and `match_end_tick`; `surrendered` is the local
## player's own Surrender command (the sim cannot tell it from a defeat). A match with no end yet
## is abandoned.
static func from_snapshot(
	snapshot: MatchSnapshot,
	setup_level: StringName,
	setup_map_id: StringName,
	side: int,
	surrendered: bool,
	setup_lesson_id: StringName = &""
) -> MatchSummary:
	var summary: MatchSummary = MatchSummary.new()
	summary.level = setup_level
	summary.map_id = setup_map_id
	summary.ticks = snapshot.tick
	summary.local_side = side
	summary.lesson_id = setup_lesson_id
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
