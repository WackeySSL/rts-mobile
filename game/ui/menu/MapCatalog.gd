class_name MapCatalog
extends Resource
## The maps the map select offers (ADR 0043, plan P525), in data (`data/maps/catalog.tres`).
## Each entry is a Dictionary: `id` (also the unlock id of ADR 0045, kind "map"), `title`, and
## `scenarios`, an Array of Dictionaries with `path`, `player_side` and `opponent_side` (faction
## ids, "fossil" or "renew"): both sides and their mirrors. The mirror rows are listed for a later
## mirror choice and cannot be reached from the screen yet. P550 and P552 add their maps here.

const KEY_ID: StringName = &"id"
const KEY_TITLE: StringName = &"title"
const KEY_SCENARIOS: StringName = &"scenarios"
const KEY_PATH: StringName = &"path"
const KEY_PLAYER: StringName = &"player_side"
const KEY_OPPONENT: StringName = &"opponent_side"
const DEFAULT_PATH: String = "res://data/maps/catalog.tres"

@export var entries: Array[Dictionary] = []


## The ids of the maps, in order.
func map_ids() -> Array[StringName]:
	var ids: Array[StringName] = []
	for entry: Dictionary in entries:
		ids.append(entry[KEY_ID] as StringName)
	return ids


func title(map_id: StringName) -> String:
	return str(_entry(map_id).get(KEY_TITLE, ""))


## The scenario file of `map_id` for the sides, or "" when none is listed.
func scenario_path(
	map_id: StringName, player_side: StringName, opponent_side: StringName
) -> String:
	for row: Dictionary in _entry(map_id).get(KEY_SCENARIOS, []) as Array:
		if row[KEY_PLAYER] == player_side and row[KEY_OPPONENT] == opponent_side:
			return str(row[KEY_PATH])
	return ""


func _entry(map_id: StringName) -> Dictionary:
	for entry: Dictionary in entries:
		if entry[KEY_ID] == map_id:
			return entry
	return {}
