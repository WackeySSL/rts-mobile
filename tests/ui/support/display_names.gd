extends RefCounted
## The display names of the shipped units and buildings, for the suites that fit a name into a card
## (the caption of the build card, the sash of a locked one). Not a suite.

const DIR: String = "res://data/units"
## The upgrades (P247): each is a research card's caption once P248 and P249 show it.
const UPGRADES_DIR: String = "res://data/upgrades"


## Every def of the data in sorted file order: type id -> its resource.
static func defs() -> Dictionary[String, Resource]:
	var found: Dictionary[String, Resource] = {}
	var files: PackedStringArray = DirAccess.get_files_at(DIR)
	files.sort()
	for file: String in files:
		if file.ends_with(".tres"):
			var def: Resource = load("%s/%s" % [DIR, file])
			found[str(def.get("type_id"))] = def
	return found


## The display name of every def with one: type id -> name.
static func all() -> Dictionary[String, String]:
	var names: Dictionary[String, String] = {}
	var all_defs: Dictionary[String, Resource] = defs()
	for id: String in all_defs:
		var shown: Variant = all_defs[id].get("display_name")
		if shown is String and not (shown as String).is_empty():
			names[id] = shown as String
	var files: PackedStringArray = DirAccess.get_files_at(UPGRADES_DIR)
	files.sort()
	for file: String in files:
		if file.ends_with(".tres"):
			var up: Resource = load("%s/%s" % [UPGRADES_DIR, file])
			names[str(up.get("id"))] = str(up.get("display_name"))
	return names


## The names a locked card puts on its sash: every `requires` target, and every def that makes a
## tab's items (`produces` of 0 or more), the producer a card names when it has none. Type id ->
## name.
static func requirements() -> Dictionary[String, String]:
	var names: Dictionary[String, String] = all()
	var all_defs: Dictionary[String, Resource] = defs()
	var found: Dictionary[String, String] = {}
	for id: String in all_defs:
		var def: Resource = all_defs[id]
		var needed: Variant = def.get("requires")
		if needed is Resource:
			var needed_id: String = str((needed as Resource).get("type_id"))
			if names.has(needed_id):
				found[needed_id] = names[needed_id]
		var produces: Variant = def.get("produces")
		if produces is int and (produces as int) >= 0 and names.has(id):
			found[id] = names[id]
	return found
