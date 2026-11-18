class_name MapSelect
extends MenuScreen
## The map select (ADR 0043 section 5, plan P525): the map from `MapCatalog`, the side, the
## computer's level and START. A map or level above the player's rank (ADR 0045, read through
## `Progression`) is dimmed and shows its rank; it cannot be chosen. START builds a `MatchSetup`
## and awaits `MenuFlow.start_match`; a second tap while it runs does nothing, and a refused start
## (ERR_BUSY or another error) is reported with `push_warning` and leaves the button live. The
## computer plays the other side. The banner band is the slot's (empty until P430); no ad call
## lives here. It is a menu: no Command, no sim.

const ProgressionScript: GDScript = preload("res://game/meta/progression_service.gd")
const FlowScript: GDScript = preload("res://game/ui/menu/menu_flow_service.gd")
const SIDE_PLAIN: StringName = &"MenuSideCard"
const OPPONENT_PATH: String = "res://data/ai/opponent_%s.tres"
const LEVEL_PATH: String = "res://data/ai/difficulty/%s.tres"
const KIND_MAP: StringName = &"map"
const KIND_LEVEL: StringName = &"level"
const FOSSIL: StringName = &"fossil"
const RENEW: StringName = &"renew"
const SIDES: Array[StringName] = [FOSSIL, RENEW]
const LEVELS: Array[StringName] = [&"easy", &"normal", &"hard"]
const SIDE_TEXT: Dictionary[StringName, StringName] = {
	FOSSIL: MapSelectText.SIDE_FOSSIL, RENEW: MapSelectText.SIDE_RENEW
}
const SIDE_LOOK: Dictionary[StringName, StringName] = {
	FOSSIL: &"MenuSideCardFossil", RENEW: &"MenuSideCardRenew"
}
const LEVEL_TEXT: Dictionary[StringName, StringName] = {
	&"easy": MapSelectText.EASY, &"normal": MapSelectText.NORMAL, &"hard": MapSelectText.HARD
}

## Tests inject these before the screen is pushed; null means the autoloads and the data file.
var progression: ProgressionScript = null
var flow: FlowScript = null
var catalog: MapCatalog = null

var map_id: StringName = &""
var side: StringName = FOSSIL
var level: StringName = &"normal"

var _progression: ProgressionScript
var _flow: FlowScript
var _maps: Dictionary[StringName, Button] = {}
var _sides: Dictionary[StringName, Button] = {}
var _map_cards: Dictionary[StringName, PanelContainer] = {}
var _side_cards: Dictionary[StringName, PanelContainer] = {}
var _levels: Dictionary[StringName, Button] = {}
var _start: Button
var _starting: bool = false


func _ready() -> void:
	super()
	MapSelectText.register()
	_progression = progression if progression != null else (Progression as ProgressionScript)
	_flow = flow if flow != null else (MenuFlow as FlowScript)
	if catalog == null:
		catalog = load(MapCatalog.DEFAULT_PATH) as MapCatalog
	_label(tr(MapSelectText.TITLE), &"CapsTitle")
	_label(tr(MapSelectText.MAP), &"")
	for id: StringName in catalog.map_ids():
		_maps[id] = _choice(id, _pick_map, _map_cards)
	_label(tr(MapSelectText.SIDE), &"")
	for id: StringName in SIDES:
		_sides[id] = _choice(id, _pick_side, _side_cards)
	_label(tr(MapSelectText.LEVEL), &"")
	for id: StringName in LEVELS:
		_levels[id] = _choice(id, _pick_level, null)
	_start = add_button(tr(MapSelectText.START), _on_start)
	# Phase 6's rewarded offer widget plugs into this slot (P433); it lands empty and calls no ad.
	OfferSlot.add_to(column, self)
	_progression_defaults()
	_progression.xp_changed.connect(_refresh)
	_refresh()


func _exit_tree() -> void:
	if _progression != null and _progression.xp_changed.is_connected(_refresh):
		_progression.xp_changed.disconnect(_refresh)


## The setup START would send, or null when the choice has no scenario or a def is missing.
func build_setup() -> MatchSetup:
	var opponent_side: StringName = RENEW if side == FOSSIL else FOSSIL
	var path: String = catalog.scenario_path(map_id, side, opponent_side)
	var opponent: AiDef = load(OPPONENT_PATH % opponent_side) as AiDef
	var difficulty: AiDifficultyDef = load(LEVEL_PATH % level) as AiDifficultyDef
	if path.is_empty() or opponent == null or difficulty == null:
		return null
	var setup: MatchSetup = MatchSetup.new()
	setup.scenario_path = path
	setup.opponents.append(opponent)
	setup.opponent_levels.append(difficulty)
	setup.map_id = map_id
	return setup


## Whether the player's rank opens `id` of `kind` (ADR 0045); everything but a map or level is open.
func is_open(kind: StringName, id: StringName) -> bool:
	return _progression.is_unlocked(kind, id)


## The first open map (&"" when none is open or the catalog is empty) and Normal, or the first open
## level when Normal is closed.
func _progression_defaults() -> void:
	for id: StringName in catalog.map_ids():
		if is_open(KIND_MAP, id):
			map_id = id
			break
	if not is_open(KIND_LEVEL, level):
		for id: StringName in LEVELS:
			if is_open(KIND_LEVEL, id):
				level = id
				break


func _can_start() -> bool:
	return map_id != &"" and is_open(KIND_MAP, map_id) and is_open(KIND_LEVEL, level)


func _on_start() -> void:
	if _starting or not _can_start():
		return
	var setup: MatchSetup = build_setup()
	if setup == null:
		push_warning("MapSelect: no scenario for %s / %s / %s" % [map_id, side, level])
		return
	_starting = true
	_refresh()
	var error: Error = await _flow.start_match(setup)
	if error != OK:
		push_warning("MapSelect: the match did not start (%s)" % error_string(error))
		_starting = false
		_refresh()


func _pick_map(id: StringName) -> void:
	map_id = id
	_refresh()


func _pick_side(id: StringName) -> void:
	side = id
	_refresh()


func _pick_level(id: StringName) -> void:
	level = id
	_refresh()


## The button for `id`. With `cards` it is a flat CapsButton inside a PanelContainer card (the
## card carries the look, kept in `cards`); without, a plain CapsButton of the column.
func _choice(id: StringName, pick: Callable, cards: Variant) -> Button:
	if cards == null:
		return add_button("", pick.bind(id))
	var card: PanelContainer = PanelContainer.new()
	column.add_child(card)
	var button: Button = Button.new()
	button.theme_type_variation = &"CapsButton"
	button.flat = true
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var floor_dp: DpMinSize = DpMinSize.new()
	floor_dp.min_dp = BUTTON_DP
	button.add_child(floor_dp)
	button.pressed.connect(pick.bind(id))
	card.add_child(button)
	(cards as Dictionary)[id] = card
	return button


func _refresh() -> void:
	if _start == null:
		return
	for id: StringName in _maps:
		var open: bool = is_open(KIND_MAP, id)
		_show(_maps[id], catalog.title(id).to_upper(), id == map_id, KIND_MAP, id)
		_map_cards[id].theme_type_variation = (
			&"MenuMapCardLocked"
			if not open
			else (&"MenuMapCardOn" if id == map_id else &"MenuMapCard")
		)
	for id: StringName in _sides:
		_show(_sides[id], tr(SIDE_TEXT[id]), id == side, &"", id)
		_side_cards[id].theme_type_variation = SIDE_LOOK[id] if id == side else SIDE_PLAIN
	for id: StringName in _levels:
		_show(_levels[id], tr(LEVEL_TEXT[id]), id == level, KIND_LEVEL, id)
		_levels[id].theme_type_variation = &"MenuTabOn" if id == level else &"MenuTab"
	_start.disabled = _starting or not _can_start()
	_start.text = tr(MapSelectText.STARTING if _starting else MapSelectText.START)


## Sets one choice button: the word, `> ` before the chosen one and the rank on a locked one (a
## locked choice is disabled).
func _show(button: Button, word: String, chosen: bool, kind: StringName, id: StringName) -> void:
	var open: bool = kind == &"" or is_open(kind, id)
	if not open:
		word = tr(MapSelectText.LOCKED) % [word, _progression.unlock_rank(kind, id)]
	elif chosen:
		word = tr(MapSelectText.CHOSEN) % word
	button.text = word
	button.disabled = not open


func _label(text: String, variation: StringName) -> Label:
	var label: Label = Label.new()
	label.text = text
	label.theme_type_variation = variation
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(label)
	return label
