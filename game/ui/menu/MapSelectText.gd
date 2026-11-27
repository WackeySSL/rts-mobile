class_name MapSelectText
extends RefCounted
## The English table of the map select (the pattern of `MainMenuText`). Button words are upper
## case.

const TITLE: StringName = &"MAPSEL_TITLE"
const MAP: StringName = &"MAPSEL_MAP"
const CRUMB: StringName = &"MAPSEL_CRUMB"
const HEADLINE: StringName = &"MAPSEL_HEADLINE"
const TAG_PICKED: StringName = &"MAPSEL_TAG_PICKED"
const TAG_OTHER: StringName = &"MAPSEL_TAG_OTHER"
const PITCH_FOSSIL: StringName = &"MAPSEL_PITCH_FOSSIL"
const PITCH_RENEW: StringName = &"MAPSEL_PITCH_RENEW"
const LEVEL: StringName = &"MAPSEL_LEVEL"
const START: StringName = &"MAPSEL_START"
## Shared with the result screen's Play again: shown while the next match is prepared.
## Translator note: keep it about as short as PLAY AGAIN; a longer text is trimmed with "…".
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
	CRUMB: "TREADLINE / SKIRMISH",
	HEADLINE: "CHOOSE YOUR FRONT",
	TAG_PICKED: "SELECTED",
	TAG_OTHER: "ALTERNATIVE",
	PITCH_FOSSIL: "Oil, steel and heavy armour. Slow to move, hard to break.",
	PITCH_RENEW: "Glass, wind and sun. Fast, precise and fragile.",
	LEVEL: "COMPUTER LEVEL",
	START: "START",
	STARTING: "STARTING…",
	LOCKED: "%s  (RANK %d)",
	CHOSEN: "> %s",
	SIDE_FOSSIL: "IRONWARD",
	SIDE_RENEW: "FACET",
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
