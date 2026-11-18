class_name MapSelectText
extends RefCounted
## The English table of the map select (the pattern of `MainMenuText`). Button words are upper
## case.

const TITLE: StringName = &"MAPSEL_TITLE"
const MAP: StringName = &"MAPSEL_MAP"
const SIDE: StringName = &"MAPSEL_SIDE"
const LEVEL: StringName = &"MAPSEL_LEVEL"
const START: StringName = &"MAPSEL_START"
## Shared with the result screen's Play again: shown while the next match is prepared.
const STARTING: StringName = &"MAPSEL_STARTING"
const LOCKED: StringName = &"MAPSEL_LOCKED"
const CHOSEN: StringName = &"MAPSEL_CHOSEN"
const SIDE_FOSSIL: StringName = &"MAPSEL_SIDE_FOSSIL"
const SIDE_RENEW: StringName = &"MAPSEL_SIDE_RENEW"
const EASY: StringName = &"MAPSEL_EASY"
const NORMAL: StringName = &"MAPSEL_NORMAL"
const HARD: StringName = &"MAPSEL_HARD"

const ENGLISH: Dictionary[StringName, String] = {
	TITLE: "SKIRMISH",
	MAP: "MAP",
	SIDE: "YOUR SIDE",
	LEVEL: "COMPUTER LEVEL",
	START: "START",
	STARTING: "STARTING…",
	LOCKED: "%s  (RANK %d)",
	CHOSEN: "> %s",
	SIDE_FOSSIL: "DERRICK LEAGUE",
	SIDE_RENEW: "LUMEN ACCORD",
	EASY: "EASY",
	NORMAL: "NORMAL",
	HARD: "HARD",
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
