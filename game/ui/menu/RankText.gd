class_name RankText
extends RefCounted
## The English table of the Rank screen's trophy and progress parts (ADR 0054 section 8; same
## pattern as `MainMenuText`). The trophy names and hints are data (`data/meta/trophies.tres`) and
## go through `tr()` where they are shown. Headings and column heads are upper case because the
## theme's eyebrow has no case property.

# Trophies (P673d).
const TROPHIES: StringName = &"RANK_TROPHIES"
const TROPHIES_COUNT: StringName = &"RANK_TROPHIES_COUNT"
const EARNED: StringName = &"RANK_EARNED"
const PROGRESS: StringName = &"RANK_PROGRESS"
# Progress (P673e).
const PROGRESS_HEAD: StringName = &"RANK_PROGRESS_HEAD"
const WINS_GRID: StringName = &"RANK_WINS_GRID"
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
	TROPHIES: "TROPHIES",
	TROPHIES_COUNT: "TROPHIES  %d / %d",
	EARNED: "EARNED",
	PROGRESS: "%d/%d",
	PROGRESS_HEAD: "PROGRESS",
	WINS_GRID: "WINS BY MAP AND LEVEL",
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
