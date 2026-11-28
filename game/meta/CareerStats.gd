class_name CareerStats
extends RefCounted
## The `career` save section (ADR 0054 section 4): skirmish counters and the earned trophy ids.
## Owned by `Progression`; no save version bump, kept apart from `progress` so an older build's
## rewrite of `progress` cannot wipe it. Keys this build does not know are carried through a
## write. An id `SaveService` would refuse as a key never reaches the section, so one bad id
## cannot refuse the whole section and with it the XP award. Meta only, never sim.

const SECTION: StringName = &"career"
const FORMAT: int = 1
const KEYS: Array[String] = [
	"format",
	"finished",
	"wins",
	"play_ticks",
	"best_win_ticks",
	"wins_grid",
	"wins_faction",
	"earned"
]

var format: int = FORMAT
var finished: int = 0
var wins: int = 0
var play_ticks: int = 0
## The shortest win in ticks; 0 = no win yet.
var best_win_ticks: int = 0
var wins_grid: Dictionary = {}  # String map id -> (String level id -> int wins)
var wins_faction: Dictionary = {}  # String faction id -> int wins
var earned: PackedStringArray = PackedStringArray()
## False until the section was saved once: it was then built by the back-fill.
var saved: bool = false

var _extra: Dictionary = {}


## The section as saved, clamped, with a malformed entry dropped through `warn`. With no `format`
## in `raw` it is the back-fill (ADR 0054 section 5): `finished` = `next_award_id - 1`, the rest 0.
static func read(raw: Dictionary, next_award_id: int, warn: Callable) -> CareerStats:
	var stats: CareerStats = CareerStats.new()
	for key: Variant in raw:
		if not KEYS.has(str(key)):
			stats._extra[key] = raw[key]
	if not raw.get("format") is int or int(raw["format"]) < 1:
		stats.finished = clampi(next_award_id - 1, 0, MatchSetup.LIMIT)
		return stats
	stats.saved = true
	stats.format = int(raw["format"])
	stats.finished = _count(raw.get("finished", 0))
	stats.wins = _count(raw.get("wins", 0))
	stats.play_ticks = _count(raw.get("play_ticks", 0))
	stats.best_win_ticks = _count(raw.get("best_win_ticks", 0))
	stats.wins_faction = _read_counts(raw.get("wins_faction", {}), warn)
	var grid: Variant = raw.get("wins_grid", {})
	for map_id: Variant in grid if grid is Dictionary else {}:
		var row: Dictionary = _read_counts((grid as Dictionary)[map_id], warn)
		if valid_id(str(map_id)) and not row.is_empty():
			stats.wins_grid[str(map_id)] = row
		else:
			warn.call("CareerStats: dropped a malformed wins_grid entry")
	var ids: Variant = raw.get("earned", [])
	for id: Variant in ids if ids is Array or ids is PackedStringArray else []:
		if id is String and valid_id(id) and not stats.earned.has(id):
			stats.earned.append(id)
		else:
			warn.call("CareerStats: dropped a malformed earned id")
	return stats


## False for an id `SaveService` would refuse as a key: empty, edge spaces or a forbidden character.
static func valid_id(id: String) -> bool:
	if id == "" or id != id.strip_edges():
		return false
	for character: String in TrophyCatalog.ID_FORBIDDEN:
		if id.contains(character):
			return false
	return true


static func _count(value: Variant) -> int:
	return clampi(value as int, 0, MatchSetup.LIMIT) if value is int else 0


## id -> count, a bad id or count dropped.
static func _read_counts(value: Variant, warn: Callable) -> Dictionary:
	var counts: Dictionary = {}
	for id: Variant in value if value is Dictionary else {}:
		var count: Variant = (value as Dictionary)[id]
		if valid_id(str(id)) and count is int:
			counts[str(id)] = _count(count)
		else:
			warn.call("CareerStats: dropped a malformed count entry")
	return counts


## Counts a finished skirmish. An abandoned, unknown or lesson summary changes nothing; a draw or
## surrender is finished, not won. An empty id (unknown) skips its grid or faction cell silently, a
## refused one with a warning; the counters still count.
func record(summary: MatchSummary, warn: Callable) -> void:
	var counted: Array[StringName] = [
		MatchSummary.OUTCOME_WIN,
		MatchSummary.OUTCOME_LOSS,
		MatchSummary.OUTCOME_DRAW,
		MatchSummary.OUTCOME_SURRENDER
	]
	if summary.lesson_id != &"" or not counted.has(summary.outcome):
		return
	var ticks: int = clampi(summary.ticks, 0, MatchSetup.LIMIT)
	finished = mini(finished + 1, MatchSetup.LIMIT)
	play_ticks = mini(play_ticks + ticks, MatchSetup.LIMIT)
	if summary.outcome != MatchSummary.OUTCOME_WIN:
		return
	wins = mini(wins + 1, MatchSetup.LIMIT)
	var win_ticks: int = maxi(ticks, 1)
	best_win_ticks = win_ticks if best_win_ticks == 0 else mini(best_win_ticks, win_ticks)
	var map_id: String = String(summary.map_id)
	var level: String = String(summary.level)
	var faction: String = String(summary.faction)
	if valid_id(map_id) and valid_id(level):
		var row: Dictionary = wins_grid.get(map_id, {})
		row[level] = mini(int(row.get(level, 0)) + 1, MatchSetup.LIMIT)
		wins_grid[map_id] = row
	elif map_id != "" and level != "":
		warn.call("CareerStats: a win with a refused map or level id left out of wins_grid")
	if valid_id(faction):
		wins_faction[faction] = mini(int(wins_faction.get(faction, 0)) + 1, MatchSetup.LIMIT)
	elif faction != "":
		warn.call("CareerStats: a win with a refused faction id left out of wins_faction")


## Wins on `map_id` at `level`; an empty argument means any.
func wins_on(map_id: StringName, level: StringName) -> int:
	var total: int = 0
	for map_key: String in wins_grid:
		if map_id != &"" and map_key != String(map_id):
			continue
		var row: Dictionary = wins_grid[map_key]
		for level_key: String in row:
			if level == &"" or level_key == String(level):
				total += int(row[level_key])
	return total


func counter(name: StringName, key: StringName) -> int:
	match name:
		&"finished":
			return finished
		&"wins":
			return wins
		&"wins_faction":
			return int(wins_faction.get(String(key), 0))
	return 0


func has_earned(id: StringName) -> bool:
	return earned.has(String(id))


## The section to save: the unknown keys first, then this build's own.
func to_section() -> Dictionary:
	var section: Dictionary = _extra.duplicate(true)
	section["format"] = format
	section["finished"] = finished
	section["wins"] = wins
	section["play_ticks"] = play_ticks
	section["best_win_ticks"] = best_win_ticks
	section["wins_grid"] = wins_grid.duplicate(true)
	section["wins_faction"] = wins_faction.duplicate(true)
	section["earned"] = earned.duplicate()
	return section
