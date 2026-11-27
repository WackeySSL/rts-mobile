class_name DeployCardText
extends RefCounted
## The English table of the deploy card (ADR 0043 question 12; same pattern as `MenuText`).

const TITLE: StringName = &"DEPLOY_TITLE"

## The tips, in the order they show (the `MenuPrefs` counter walks them, then starts over).
const TIPS: Array[StringName] = [
	&"DEPLOY_TIP_PAN",
	&"DEPLOY_TIP_TYPE",
	&"DEPLOY_TIP_BOX",
	&"DEPLOY_TIP_MOVE",
	&"DEPLOY_TIP_TANKER",
]

const ENGLISH: Dictionary[StringName, String] = {
	TITLE: "DEPLOYING",
	&"DEPLOY_TIP_PAN": "Drag one finger to pan the map. Pinch to zoom.",
	&"DEPLOY_TIP_TYPE": "Double-tap a unit to select every unit of its type.",
	&"DEPLOY_TIP_BOX": "Press and hold, then drag, to select a group in a box.",
	&"DEPLOY_TIP_MOVE": "Tap the ground to send the selected units there.",
	&"DEPLOY_TIP_TANKER": "A tanker you send away goes back to work by itself.",
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


## The key of tip `index` (wrapped into the list).
static func tip_key(index: int) -> StringName:
	return TIPS[posmod(index, TIPS.size())]
