class_name MainMenuText
extends RefCounted
## The English table of the main menu (ADR 0043 question 12; same pattern as `MenuText`). Button
## words are upper case because the theme's buttons have no case property.

const TITLE: StringName = &"MAIN_TITLE"
const TAGLINE: StringName = &"MAIN_TAGLINE"
const SIDE_FOSSIL: StringName = &"MAIN_SIDE_FOSSIL"
const SIDE_RENEW: StringName = &"MAIN_SIDE_RENEW"
const VS: StringName = &"MAIN_VS"
const CONTINUE: StringName = &"MAIN_CONTINUE"
const SKIRMISH: StringName = &"MAIN_SKIRMISH"
const TUTORIAL: StringName = &"MAIN_TUTORIAL"
const HOW_TO_PLAY: StringName = &"MAIN_HOW_TO_PLAY"
const SETTINGS: StringName = &"MAIN_SETTINGS"
const RANK: StringName = &"MAIN_RANK"
const XP: StringName = &"MAIN_XP"
const XP_TOP: StringName = &"MAIN_XP_TOP"
const VERSION: StringName = &"MAIN_VERSION"
const COPYRIGHT: StringName = &"MAIN_COPYRIGHT"
const RESTORING: StringName = &"MAIN_RESTORING"
const RESTORE_CANCEL: StringName = &"MAIN_RESTORE_CANCEL"
const RESTORE_FAILED: StringName = &"MAIN_RESTORE_FAILED"

const ENGLISH: Dictionary[StringName, String] = {
	TITLE: "TREADLINE",
	TAGLINE: "Oil and gas against wind and sun. Choose your side.",
	SIDE_FOSSIL: "IRONWARD",
	SIDE_RENEW: "FACET",
	VS: "vs",
	CONTINUE: "CONTINUE",
	SKIRMISH: "SKIRMISH",
	TUTORIAL: "TUTORIAL",
	HOW_TO_PLAY: "HOW TO PLAY",
	SETTINGS: "SETTINGS",
	RANK: "RANK %d  %s",
	XP: "%d / %d XP",
	XP_TOP: "%d XP",
	VERSION: "v%s · © AppCode ApS",
	COPYRIGHT: "© AppCode ApS",
	RESTORING: "Restoring your match",
	RESTORE_CANCEL: "CANCEL",
	RESTORE_FAILED: "That match could not be restored. It has been discarded.",
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
