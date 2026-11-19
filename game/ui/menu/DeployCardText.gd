class_name DeployCardText
extends RefCounted
## The English table of the deploy card (ADR 0043 question 12; same pattern as `MenuText`).

const TITLE: StringName = &"DEPLOY_TITLE"

const ENGLISH: Dictionary[StringName, String] = {TITLE: "DEPLOYING"}

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
