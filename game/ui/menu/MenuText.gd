class_name MenuText
extends RefCounted
## The English table of the menu frame's strings (ADR 0043 question 12: the new screens use `tr()`
## keys with an English table; other languages come later). The project registers no translation
## file (project.godot is not touched by this row), so the table is registered at runtime, once,
## by `register()`. A screen row adds its keys to `ENGLISH`. Button words are upper case here
## because the theme's buttons have no case property.

const QUIT_TITLE: StringName = &"MENU_QUIT_TITLE"
const QUIT_DETAIL: StringName = &"MENU_QUIT_DETAIL"
const QUIT_YES: StringName = &"MENU_QUIT_YES"
const QUIT_NO: StringName = &"MENU_QUIT_NO"

const ENGLISH: Dictionary[StringName, String] = {
	QUIT_TITLE: "QUIT TREADLINE?",
	QUIT_DETAIL: "Your progress is saved.",
	QUIT_YES: "QUIT",
	QUIT_NO: "STAY",
}

static var _registered: bool = false


## Adds the English table to the TranslationServer; a second call does nothing.
static func register() -> void:
	if _registered:
		return
	_registered = true
	var table: Translation = Translation.new()
	table.locale = "en"
	for key: StringName in ENGLISH:
		table.add_message(key, ENGLISH[key])
	TranslationServer.add_translation(table)
