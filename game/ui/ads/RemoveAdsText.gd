class_name RemoveAdsText
extends RefCounted
## The English table of the Remove ads rows (the pattern of `MapSelectText`). Button words are
## upper case; the price is the store's own text and is never changed or trimmed.

const REMOVE: StringName = &"PURCHASE_REMOVE"
## The title and the price on one row: `%s` title, `%s` price.
const PRICED: StringName = &"PURCHASE_PRICED"
const RESTORE: StringName = &"PURCHASE_RESTORE"
## Shown on the tapped row while the store works (as `MapSelectText.STARTING`).
const BUSY: StringName = &"PURCHASE_BUSY"
const RESTORING: StringName = &"PURCHASE_RESTORING"
## What a title shortens to when the price needs the room.
const ELLIPSIS: StringName = &"PURCHASE_ELLIPSIS"

const ENGLISH: Dictionary[StringName, String] = {
	REMOVE: "REMOVE ADS",
	PRICED: "%s  %s",
	RESTORE: "RESTORE PURCHASES",
	BUSY: "WORKING…",
	RESTORING: "RESTORING…",
	ELLIPSIS: "…",
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
