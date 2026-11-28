class_name RankText
extends RefCounted
## The English table of the Rank screen's trophy part (ADR 0054 section 8; same pattern as
## `MainMenuText`). The trophy names and hints are data (`data/meta/trophies.tres`) and go through
## `tr()` where they are shown.

const TROPHIES: StringName = &"RANK_TROPHIES"
const TROPHIES_COUNT: StringName = &"RANK_TROPHIES_COUNT"
const EARNED: StringName = &"RANK_EARNED"
const PROGRESS: StringName = &"RANK_PROGRESS"

const ENGLISH: Dictionary[StringName, String] = {
	TROPHIES: "TROPHIES",
	TROPHIES_COUNT: "TROPHIES  %d / %d",
	EARNED: "EARNED",
	PROGRESS: "%d/%d",
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
