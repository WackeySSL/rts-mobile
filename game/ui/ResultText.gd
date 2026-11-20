class_name ResultText
extends RefCounted
## The English table of the result screen (the pattern of `MapSelectText`). Button words and
## titles are upper case here. Values come in through `%` placeholders; no number lives here.

const VICTORY: StringName = &"RESULT_VICTORY"
const DEFEAT: StringName = &"RESULT_DEFEAT"
const DRAW: StringName = &"RESULT_DRAW"
const PLAY_AGAIN: StringName = &"RESULT_PLAY_AGAIN"
const BACK: StringName = &"RESULT_BACK"
const RANK_UP: StringName = &"RESULT_RANK_UP"
## Translator note: %d minutes, then %02d seconds (two digits), as in "Match time 3:07".
const MATCH_TIME: StringName = &"RESULT_MATCH_TIME"
const YOU: StringName = &"RESULT_YOU"
const ENEMY: StringName = &"RESULT_ENEMY"
const PLAYER_N: StringName = &"RESULT_PLAYER_N"
const UNITS_BUILT: StringName = &"RESULT_UNITS_BUILT"
const UNITS_LOST: StringName = &"RESULT_UNITS_LOST"
const BUILDINGS_LOST: StringName = &"RESULT_BUILDINGS_LOST"
const CREDITS_HARVESTED: StringName = &"RESULT_CREDITS_HARVESTED"
const XP_GAINED: StringName = &"RESULT_XP_GAINED"
## Translator note: %d the rank number, then %s the rank title (upper-cased in code, from data).
const RANK_LINE: StringName = &"RESULT_RANK_LINE"
const XP_TOTAL: StringName = &"RESULT_XP_TOTAL"
## Translator note: the first %d is the current XP, the second the XP the next rank needs.
const XP_PROGRESS: StringName = &"RESULT_XP_PROGRESS"

const ENGLISH: Dictionary[StringName, String] = {
	VICTORY: "VICTORY",
	DEFEAT: "DEFEAT",
	DRAW: "DRAW",
	PLAY_AGAIN: "PLAY AGAIN",
	BACK: "BACK",
	RANK_UP: "RANK UP!",
	MATCH_TIME: "Match time %d:%02d",
	YOU: "You",
	ENEMY: "Enemy",
	PLAYER_N: "P%d",
	UNITS_BUILT: "Units built",
	UNITS_LOST: "Units lost",
	BUILDINGS_LOST: "Buildings lost",
	CREDITS_HARVESTED: "Credits harvested",
	XP_GAINED: "+%d XP",
	RANK_LINE: "RANK %d  %s",
	XP_TOTAL: "%d XP",
	XP_PROGRESS: "%d / %d XP",
}

## The stat rows, in the order of the snapshot's counters.
const STAT_KEYS: Array[StringName] = [UNITS_BUILT, UNITS_LOST, BUILDINGS_LOST, CREDITS_HARVESTED]

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


## The title key of a result id ("victory", "defeat" or "draw").
static func title_key(result: String) -> StringName:
	match result:
		"victory":
			return VICTORY
		"defeat":
			return DEFEAT
		"draw":
			return DRAW
	push_error("ResultText: unknown result id '%s'" % result)
	return DRAW
