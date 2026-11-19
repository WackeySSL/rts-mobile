class_name TutorialText
extends RefCounted
## The English table of the tutorial (ADR 0044 section 3, plan row P543; the pattern of
## `MainMenuText`): the title and the prompt of every beat, by the keys of `data/tutorial/*.tres`.
## The words are data (`data/tutorial/text_en.tres`) and name the lessons' faction's cards by
## `{type_id}`, which `register()` replaces with the unit's display name.

const TEXT_PATH: String = "res://data/tutorial/text_en.tres"
## The faction the lessons are played as: its roster gives the card names.
const FACTION_PATH: String = "res://data/factions/fossil.tres"

static var _registered: bool = false


## The words as the file holds them, `{type_id}` unresolved.
static func raw() -> Dictionary[StringName, String]:
	var table: Dictionary[StringName, String] = {}
	var def: TutorialTextDef = load(TEXT_PATH) as TutorialTextDef
	if def == null:
		push_warning("TutorialText: %s did not load" % TEXT_PATH)
		return table
	for index: int in mini(def.keys.size(), def.words.size()):
		table[StringName(def.keys[index])] = def.words[index]
	return table


## The display name of every unit of the lessons' faction, by type id.
static func names() -> Dictionary[String, String]:
	var found: Dictionary[String, String] = {}
	var faction: FactionDef = load(FACTION_PATH) as FactionDef
	if faction == null:
		push_warning("TutorialText: %s did not load" % FACTION_PATH)
		return found
	for unit: UnitDef in faction.roster:
		found[String(unit.type_id)] = unit.display_name
	return found


## The words with every `{type_id}` replaced by its display name.
static func resolved() -> Dictionary[StringName, String]:
	var table: Dictionary[StringName, String] = raw()
	var cards: Dictionary[String, String] = names()
	for key: StringName in table:
		var text: String = table[key]
		for id: String in cards:
			text = text.replace("{%s}" % id, cards[id])
		table[key] = text
	return table


## Adds the English table to the TranslationServer; a second call does nothing.
static func register() -> void:
	if _registered:
		return
	_registered = true
	var table: Translation = Translation.new()
	table.locale = "en"
	var words: Dictionary[StringName, String] = resolved()
	for key: StringName in words:
		table.add_message(key, words[key])
	TranslationServer.add_translation(table)
