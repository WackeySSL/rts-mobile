class_name TrophyRules
extends RefCounted
## Pure checks of one `TrophyDef` (ADR 0054 sections 2 and 6). The state kinds (LESSONS, COUNT,
## WIN_GRID) read only saved state, so they can be checked at any time and back-filled. MATCH reads
## the summary of the match being awarded. Every threshold comes from the def. Meta only.


## True when `def` is met by saved state (a MATCH trophy never is).
static func state_met(def: TrophyDef, career: CareerStats, lessons_done: PackedStringArray) -> bool:
	match def.kind:
		TrophyDef.Kind.LESSONS:
			for lesson: StringName in def.lesson_ids:
				if not lessons_done.has(String(lesson)):
					return false
			return not def.lesson_ids.is_empty()
		TrophyDef.Kind.COUNT:
			return career.counter(def.counter, def.key) >= def.count
		TrophyDef.Kind.WIN_GRID:
			return _grid_met(def, career)
	return false


## True when `summary` is a skirmish win that meets every filter of a MATCH `def`.
static func match_met(
	def: TrophyDef, summary: MatchSummary, hq_type_ids: Array[StringName]
) -> bool:
	if def.kind != TrophyDef.Kind.MATCH or summary == null:
		return false
	if summary.lesson_id != &"" or summary.outcome != MatchSummary.OUTCOME_WIN:
		return false
	if not def.levels.is_empty() and not def.levels.has(summary.level):
		return false
	if def.max_ticks > 0 and summary.ticks > def.max_ticks:
		return false
	if def.max_buildings_lost >= 0 and summary.lost_buildings > def.max_buildings_lost:
		return false
	return not def.hq_standing or _hq_stands(summary, hq_type_ids)


## The unearned trophies of `catalog` that the career, the lessons and the optional `summary` now
## meet, in catalog order.
static func newly_earned(
	catalog: TrophyCatalog,
	career: CareerStats,
	lessons_done: PackedStringArray,
	summary: MatchSummary
) -> Array[StringName]:
	var found: Array[StringName] = []
	for def: TrophyDef in catalog.trophies:
		if career.has_earned(def.id):
			continue
		if state_met(def, career, lessons_done) or match_met(def, summary, catalog.hq_type_ids):
			found.append(def.id)
	return found


static func _grid_met(def: TrophyDef, career: CareerStats) -> bool:
	if def.map_ids.is_empty() and def.levels.is_empty():
		return false
	# An empty list means any: one pass with the empty id, which `wins_on` reads as any.
	var maps: Array[StringName] = def.map_ids.duplicate()
	var levels: Array[StringName] = def.levels.duplicate()
	if maps.is_empty():
		maps.append(&"")
	if levels.is_empty():
		levels.append(&"")
	for map_id: StringName in maps:
		for level: StringName in levels:
			if career.wins_on(map_id, level) < 1:
				return false
	return true


static func _hq_stands(summary: MatchSummary, hq_type_ids: Array[StringName]) -> bool:
	for type_id: StringName in hq_type_ids:
		if summary.standing_types.has(type_id):
			return true
	return false
