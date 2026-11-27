class_name MapSelect
extends MenuScreen
## The map select (ADR 0043 section 5, plan P525; the look of Michael's Figma board, P666): a
## breadcrumb and headline, two faction cards (the chosen one in the amber accent, the other in its
## faction's), the map from `MapCatalog`, the computer's level as chips and START. Wide (landscape)
## the cards and the level stand on the left and the map and START on the right; upright it is one
## column in that order. The map's preview is a marked slot (`MapPreviewSlot`) that names the chosen
## map until a picture can be drawn from the map's data (P666b); the in-match minimap needs a sim.
## A map or level above the player's rank (ADR 0045, read through `Progression`) is dimmed and
## shows its rank; it cannot be chosen. START builds a `MatchSetup`
## and awaits `MenuFlow.start_match`; a second tap while it runs does nothing, and a refused start
## (ERR_BUSY or another error) is reported with `push_warning` and leaves the button live. The
## computer plays the other side. The banner band is the slot's; the offer slot holds Phase 6's
## `StartCreditsOffer` (P433), which owns every ad call; none lives here. It is a menu: no
## Command, no sim.

const ProgressionScript: GDScript = preload("res://game/meta/progression_service.gd")
const FlowScript: GDScript = preload("res://game/ui/menu/menu_flow_service.gd")
const EMBLEMS: Dictionary[StringName, Texture2D] = {
	&"fossil": preload("res://assets/art/svg/icons/emblem_fossil.svg"),
	&"renew": preload("res://assets/art/svg/icons/emblem_renew.svg"),
}
const EMBLEM_DP: float = 40.0
const PREVIEW_DP: float = 112.0  ## The preview slot's least height.
const HOLD_FRAMES: int = 4  ## Frames a turn keeps the scroll position.
const START_DP: Vector2 = Vector2(0.0, 64.0)
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
const SIDE_TAG_LOOK: Dictionary[StringName, StringName] = {
	FOSSIL: &"MenuCardTagFossil", RENEW: &"MenuCardTagRenew"
}
const SIDE_PITCH: Dictionary[StringName, StringName] = {
	FOSSIL: MapSelectText.PITCH_FOSSIL, RENEW: MapSelectText.PITCH_RENEW
}
const LEVEL_TEXT: Dictionary[StringName, StringName] = {
	&"easy": MapSelectText.EASY, &"normal": MapSelectText.NORMAL, &"hard": MapSelectText.HARD
}

## Tests inject these before the screen is pushed; null means the autoloads and the data file.
var progression: ProgressionScript = null
var flow: FlowScript = null
var catalog: MapCatalog = null
## The starting-credits offer in the slot (game/ui/ads/); it owns every ad call, this screen none.
var offer: StartCreditsOffer

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
var _tags: Dictionary[StringName, Label] = {}
var _start: Button
var _starting: bool = false
var _wide: bool = false
var _body: GridContainer
var _cards_row: HBoxContainer
var _map_box: VBoxContainer
var _level_box: VBoxContainer
var _start_box: VBoxContainer
var _preview_name: Label
var _spaced: Array[BoxContainer] = []


func _ready() -> void:
	super()
	MapSelectText.register()
	_progression = progression if progression != null else (Progression as ProgressionScript)
	_flow = flow if flow != null else (MenuFlow as FlowScript)
	if catalog == null:
		catalog = load(MapCatalog.DEFAULT_PATH) as MapCatalog
	_label(column, tr(MapSelectText.CRUMB), &"MenuEyebrow")
	_label(column, tr(MapSelectText.HEADLINE), &"CapsBigTitle")
	_build_body()
	_cards_row = _spaced_box(HBoxContainer.new()) as HBoxContainer
	for id: StringName in SIDES:
		_sides[id] = _side_card(id)
	_map_box = _section(MapSelectText.MAP)
	_build_preview()
	var maps: HBoxContainer = _spaced_box(HBoxContainer.new()) as HBoxContainer
	_map_box.add_child(maps)
	for id: StringName in catalog.map_ids():
		_maps[id] = _choice(id, _pick_map, maps, _map_cards)
	_level_box = _section(MapSelectText.LEVEL)
	var levels: HBoxContainer = _spaced_box(HBoxContainer.new()) as HBoxContainer
	_level_box.add_child(levels)
	for id: StringName in LEVELS:
		_levels[id] = _choice(id, _pick_level, levels, null)
	_start_box = _spaced_box(VBoxContainer.new()) as VBoxContainer
	_start = _button(_start_box, &"MenuPrimary", tr(MapSelectText.START), _on_start, START_DP)
	for part: Control in [_cards_row, _map_box, _level_box, _start_box]:
		_body.add_child(part)  # In the tree: the offer slot's owner must be its ancestor.
	_apply()
	offer = StartCreditsOffer.new()
	OfferSlot.add_to(_start_box, self).add_child(offer)
	use_footer()  # The back link: the web has no back event (P672a).
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


## Back does nothing while the match starts: a pop would leave the flow to start it from the menu.
func on_back() -> bool:
	return _starting


func screen_name() -> String:
	return tr(MapSelectText.TITLE)


func _on_start() -> void:
	if _starting or not _can_start() or offer.is_running():
		return  # Not while the credits ad runs: START could not tell its result yet.
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


## The body: a grid of the four sections in the upright order (cards, map, level, START). Wide it
## has two columns, so the cards and the level stand left of the map and START; upright one column.
## Nothing is moved or rebuilt by a turn, so the scroll and the choice are kept.
func _build_body() -> void:
	_body = GridContainer.new()
	column.add_child(_body)


## The wide layout asks for the whole safe width inside the gaps; upright keeps the base column.
func _apply() -> void:
	super()
	if scroll == null or column == null:
		return
	var was_wide: bool = _wide
	_wide = not HudLayout.is_portrait()
	if _wide != was_wide and _body != null and scroll.scroll_vertical > 0:
		_hold_scroll(scroll.scroll_vertical)
	if _wide:
		column.custom_minimum_size.x = column_room_px()
	var gap: int = roundi(UiScale.dp(GAP_DP))
	for box: BoxContainer in _spaced:
		box.add_theme_constant_override("separation", gap)
	if _body != null:
		_body.columns = 2 if _wide else 1
		_body.add_theme_constant_override("h_separation", gap)
		_body.add_theme_constant_override("v_separation", gap)


## A turn changes the page's shape, which would reset the scroll: for a few frames, each time the
## bar's range changes the old position is put back, cut to the new range.
func _hold_scroll(kept: int) -> void:
	var bar: VScrollBar = scroll.get_v_scroll_bar()
	var put_back: Callable = func() -> void:
		scroll.scroll_vertical = mini(kept, maxi(floori(bar.max_value - bar.page), 0))
	bar.changed.connect(put_back)
	for _frame: int in range(HOLD_FRAMES):
		if not is_inside_tree():
			return  # The screen is gone, and the bar with it.
		await get_tree().process_frame
	if is_instance_valid(bar):
		bar.changed.disconnect(put_back)


func _spaced_box(box: BoxContainer) -> BoxContainer:
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_spaced.append(box)
	return box


## A labelled block of the body: the small caps label, then what the caller adds.
func _section(title: StringName) -> VBoxContainer:
	var box: VBoxContainer = _spaced_box(VBoxContainer.new()) as VBoxContainer
	_label(box, tr(title), &"MenuEyebrow")
	return box


## The slot of the map's picture: for now the chosen map's name on a plate of the card look. P666b
## draws the map into it.
func _build_preview() -> void:
	var slot: PanelContainer = PanelContainer.new()
	slot.name = &"MapPreviewSlot"
	slot.theme_type_variation = &"MenuMapCard"
	slot.custom_minimum_size.y = UiScale.dp(PREVIEW_DP)
	_map_box.add_child(slot)
	_preview_name = _label(slot, "", &"CapsBigTitle")
	_preview_name.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_preview_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER


## A faction card: the flat button that takes the touch, under the emblem, the tag, the name and
## the pitch (the content ignores touches). The chosen card is the amber one.
func _side_card(id: StringName) -> Button:
	var card: PanelContainer = PanelContainer.new()
	card.name = &"SideCard_%s" % id
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_cards_row.add_child(card)
	var button: Button = Button.new()
	button.theme_type_variation = &"CapsButton"
	button.flat = true
	var floor_dp: DpMinSize = DpMinSize.new()
	floor_dp.min_dp = BUTTON_DP
	button.add_child(floor_dp)
	button.pressed.connect(_pick_side.bind(id))
	card.add_child(button)
	var content: VBoxContainer = VBoxContainer.new()
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(content)
	var head: HBoxContainer = HBoxContainer.new()
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(head)
	var emblem: TextureRect = TextureRect.new()
	emblem.texture = EMBLEMS[id]
	emblem.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	emblem.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	emblem.custom_minimum_size = Vector2.ONE * UiScale.dp(EMBLEM_DP)
	head.add_child(emblem)
	var tag: Label = _label(head, "", &"MenuEyebrow")
	tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_tags[id] = tag
	_label(content, tr(SIDE_TEXT[id]), &"CapsBigTitle")
	_label(content, tr(SIDE_PITCH[id]), &"")
	_side_cards[id] = card
	return button


## A choice button for `id` under `parent`. With `cards` it is a flat CapsButton inside a
## PanelContainer card (the card carries the look, kept in `cards`); without, a MenuTab chip.
func _choice(id: StringName, pick: Callable, parent: Control, cards: Variant) -> Button:
	if cards == null:
		return _button(parent, &"MenuTab", "", pick.bind(id), BUTTON_DP)
	var card: PanelContainer = PanelContainer.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(card)
	var button: Button = _button(card, &"CapsButton", "", pick.bind(id), BUTTON_DP)
	button.flat = true
	(cards as Dictionary)[id] = card
	return button


## A button of `look` under `parent`, at least `floor_size` dp, wrapping its words when narrow.
func _button(
	parent: Control, look: StringName, text: String, action: Callable, floor_size: Vector2
) -> Button:
	var button: Button = Button.new()
	button.theme_type_variation = look
	button.text = text
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var floor_dp: DpMinSize = DpMinSize.new()
	floor_dp.min_dp = floor_size
	button.add_child(floor_dp)
	button.pressed.connect(action)
	parent.add_child(button)
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
		var picked: bool = id == side
		_side_cards[id].theme_type_variation = &"MenuSideCardOn" if picked else SIDE_LOOK[id]
		_tags[id].text = tr(MapSelectText.TAG_PICKED if picked else MapSelectText.TAG_OTHER)
		_tags[id].theme_type_variation = &"MenuEyebrow" if picked else SIDE_TAG_LOOK[id]
	_preview_name.text = catalog.title(map_id).to_upper()
	for id: StringName in _levels:
		_show(_levels[id], tr(LEVEL_TEXT[id]), id == level, KIND_LEVEL, id)
		_levels[id].theme_type_variation = &"MenuTabOn" if id == level else &"MenuTab"
	_start.disabled = _starting or not _can_start()
	UiWait.hold(_start, _starting)
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


func _label(parent: Control, text: String, look: StringName) -> Label:
	var label: Label = Label.new()
	label.text = text
	label.theme_type_variation = look
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(label)
	return label
