class_name RemoveAdsText
extends RefCounted
## The English table of the Remove ads rows (the pattern of `MapSelectText`). Button words are
## upper case; the price is the store's own text and is never changed.

const REMOVE: StringName = &"PURCHASE_REMOVE"
const RESTORE: StringName = &"PURCHASE_RESTORE"
## Shown on the tapped row while the store works (as `MapSelectText.STARTING`).
const BUSY: StringName = &"PURCHASE_BUSY"

const ENGLISH: Dictionary[StringName, String] = {
	REMOVE: "REMOVE ADS  %s",
	RESTORE: "RESTORE PURCHASES",
	BUSY: "WORKING…",
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
