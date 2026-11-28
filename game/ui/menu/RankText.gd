class_name RankText
extends RefCounted
## The English table of the Rank screen's sections (ADR 0054 section 8, plan P673). Same pattern
## as `MainMenuText`. Headings and column heads are upper case because the theme's eyebrow has no
## case property.

const PROGRESS: StringName = &"RANK_PROGRESS"
const WINS_GRID: StringName = &"RANK_WINS_GRID"
const MAP_HEAD: StringName = &"RANK_MAP_HEAD"
const CELL_LOCKED: StringName = &"RANK_CELL_LOCKED"
const LESSONS: StringName = &"RANK_LESSONS"
const MATCHES: StringName = &"RANK_MATCHES"
const WINS: StringName = &"RANK_WINS"
const TIME_PLAYED: StringName = &"RANK_TIME_PLAYED"
const FASTEST_WIN: StringName = &"RANK_FASTEST_WIN"
const OF: StringName = &"RANK_OF"
const TIME_SHORT: StringName = &"RANK_TIME_SHORT"
const TIME_LONG: StringName = &"RANK_TIME_LONG"
const FASTEST: StringName = &"RANK_FASTEST"
const NO_WIN: StringName = &"RANK_NO_WIN"

const ENGLISH: Dictionary[StringName, String] = {
	PROGRESS: "PROGRESS",
	WINS_GRID: "WINS BY MAP AND LEVEL",
	MAP_HEAD: "MAP",
	CELL_LOCKED: "RANK\n%d",  # Two lines: the cell is narrow.
	LESSONS: "Lessons done",
	MATCHES: "Matches played",
	WINS: "Wins",
	TIME_PLAYED: "Time played",
	FASTEST_WIN: "Fastest win",
	OF: "%d / %d",
	TIME_SHORT: "%d min %02d s",
	TIME_LONG: "%d h %02d min",
	FASTEST: "%d:%02d",
	NO_WIN: "None yet",
}

static var _registered: bool = false


static func register() -> void:
	if _registered:
		return
	_registered = true
	var table: Translation = Translation.new()
	table.locale = "en"
	for key: StringName in ENGLISH:
		table.add_message(key, ENGLISH[key])
	TranslationServer.add_translation(table)
