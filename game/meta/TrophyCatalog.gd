class_name TrophyCatalog
extends Resource
## The trophies in display order and the Headquarters type ids (ADR 0054 sections 1-3). The
## instance is `res://data/meta/trophies.tres`. Meta only, never sim.

const DEFAULT_PATH: String = "res://data/meta/trophies.tres"
## The career counters a COUNT trophy may name.
const COUNTERS: Array[StringName] = [&"finished", &"wins", &"wins_faction"]
const MAX_PIPS: int = 3
## What `SaveService` refuses in a key; an id is a save key.
const ID_FORBIDDEN: String = '=[];"\n\r'

@export var trophies: Array[TrophyDef] = []
## The building types of a Headquarters (`unbroken` reads them).
@export var hq_type_ids: Array[StringName] = []


## The shipped catalog, or null when the file is missing.
static func load_default() -> TrophyCatalog:
	return load(DEFAULT_PATH) as TrophyCatalog


## The trophy with `id`, or null.
func find(id: StringName) -> TrophyDef:
	for trophy: TrophyDef in trophies:
		if trophy.id == id:
			return trophy
	return null


func ids() -> Array[StringName]:
	var result: Array[StringName] = []
	for trophy: TrophyDef in trophies:
		result.append(trophy.id)
	return result


## "" when the catalog is sound, else the first problem found.
func problem() -> String:
	if trophies.is_empty() or hq_type_ids.is_empty():
		return "no trophies or no hq_type_ids"
	var seen: Dictionary[StringName, bool] = {}
	for trophy: TrophyDef in trophies:
		if trophy == null:
			return "a null trophy"
		var found: String = _trophy_problem(trophy)
		if found == "" and seen.has(trophy.id):
			found = "duplicate id"
		if found != "":
			return "%s: %s" % [trophy.id, found]
		seen[trophy.id] = true
	return ""


func _trophy_problem(trophy: TrophyDef) -> String:
	var text: String = String(trophy.id)
	if text == "" or text != text.strip_edges():
		return "empty id or edge spaces"
	for character: String in ID_FORBIDDEN:
		if text.contains(character):
			return "refused character in id"
	if trophy.name == "" or trophy.hint == "" or trophy.glyph == &"":
		return "empty name, hint or glyph"
	if trophy.pips < 0 or trophy.pips > MAX_PIPS:
		return "pips out of range"
	return _kind_problem(trophy)


func _kind_problem(trophy: TrophyDef) -> String:
	var found: String = ""
	match trophy.kind:
		TrophyDef.Kind.LESSONS:
			if trophy.lesson_ids.is_empty():
				found = "no lesson_ids"
		TrophyDef.Kind.COUNT:
			if not COUNTERS.has(trophy.counter) or trophy.count < 1:
				found = "unknown counter or count below 1"
			elif (trophy.counter == &"wins_faction") != (trophy.key != &""):
				found = "key is for wins_faction only, and wins_faction needs one"
		TrophyDef.Kind.WIN_GRID:
			if trophy.map_ids.is_empty() and trophy.levels.is_empty():
				found = "no filter"
		TrophyDef.Kind.MATCH:
			pass
		_:
			found = "unknown kind"
	return found
