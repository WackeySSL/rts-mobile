class_name MapSelect
extends MenuScreen
## The map select (ADR 0043 section 5, plan P525; Michael's Figma board and his wish for a guided
## sequence, P666): a breadcrumb and headline, then three numbered steps, each with its current
## choice in its header: 01 the side (two faction cards, the chosen one amber), 02 the map (a row
## per map from `MapCatalog`), 03 the difficulty (three chips). Under them a one-line summary and
## START BATTLE. Wide (landscape): 01 and 03 left, 02 and START right; upright one column in
## order. Every step shows one chosen item (amber edge and tint; START alone is solid amber). A
## map or level above the player's rank (ADR 0045, read through `Progression`) is dimmed with a
## lock and its rank, and cannot be chosen. START builds a `MatchSetup` and awaits
## `MenuFlow.start_match`; a second tap while it runs does nothing, and a refused start
## (ERR_BUSY or another error) is reported with `push_warning` and leaves the button live. The
## computer plays the other side. The banner band is the slot's; the offer slot holds Phase 6's
## `StartCreditsOffer` (P433), which owns every ad call; none lives here. The map's picture
## (P666b) will come back above the map rows. It is a menu: no Command, no sim.

const ProgressionScript: GDScript = preload("res://game/meta/progression_service.gd")
const FlowScript: GDScript = preload("res://game/ui/menu/menu_flow_service.gd")
const EMBLEMS: Dictionary[StringName, Texture2D] = {
	&"fossil": preload("res://assets/art/svg/icons/emblem_fossil.svg"),
	&"renew": preload("res://assets/art/svg/icons/emblem_renew.svg"),
}
const EMBLEM_DP: float = 40.0
const LOCK_ART: Texture2D = preload("res://assets/art/svg/icons/glyph_lock.svg")
const LOCK_DP: float = 16.0
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
var _level_cards: Dictionary[StringName, PanelContainer] = {}
var _names: Dictionary[StringName, Label] = {}  ## The word of each map and level option.
var _notes: Dictionary[StringName, Control] = {}  ## Its lock row (glyph and RANK n), shown locked.
var _choice_labels: Dictionary[StringName, Label] = {}  ## A step header's current choice.
var _summary: Label
var _seen_scroll: int = 0  ## The scroll at the end of the last frame (a turn clamps it first).
var _step_words: Array[Label] = []  ## The numbers and titles of the step headers.
var _tags: Dictionary[StringName, Label] = {}
var _start: Button
var _starting: bool = false
var _wide: bool = false
var _body: BoxContainer
var _left: VBoxContainer
var _right: VBoxContainer
var _side_step: VBoxContainer
var _map_step: VBoxContainer
var _level_step: VBoxContainer
var _start_box: VBoxContainer
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
	_side_step = _step(1, MapSelectText.STEP_SIDE, &"side")
	var cards: HBoxContainer = _spaced_box(HBoxContainer.new()) as HBoxContainer
	_side_step.add_child(cards)
	for id: StringName in SIDES:
		_sides[id] = _side_card(id, cards)
	_map_step = _step(2, MapSelectText.STEP_MAP, &"map")
	var maps: VBoxContainer = _spaced_box(VBoxContainer.new()) as VBoxContainer
	_map_step.add_child(maps)
	for id: StringName in catalog.map_ids():
		_maps[id] = _option(id, catalog.title(id).to_upper(), _pick_map, maps, _map_cards, true)
	_level_step = _step(3, MapSelectText.STEP_LEVEL, &"level")
	var levels: HBoxContainer = _spaced_box(HBoxContainer.new()) as HBoxContainer
	_level_step.add_child(levels)
	for id: StringName in LEVELS:
		_levels[id] = _option(id, tr(LEVEL_TEXT[id]), _pick_level, levels, _level_cards, false)
	_start_box = _spaced_box(VBoxContainer.new()) as VBoxContainer
	_summary = _label(_start_box, "", &"MenuStepTitle")
	_summary.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_start = _button(_start_box, &"MenuPrimary", tr(MapSelectText.START), _on_start, START_DP)
	_apply()
	offer = StartCreditsOffer.new()
	OfferSlot.add_to(_start_box, self).add_child(offer)
	use_footer()  # The back link: the web has no back event (P672a).
	_progression_defaults()
	_progression.xp_changed.connect(_refresh)
	_refresh()


func _process(_delta: float) -> void:
	_seen_scroll = scroll.scroll_vertical


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


## The body: two columns wide (01 and 03 left; 02 and START right), one upright (01, 02 and 03 in
## `_left`, START under them in `_right`). START never changes parent (a move would reset the offer
## in its slot); a turn moves only the map step between the columns, and `_hold_scroll` keeps the
## scroll through it.
func _build_body() -> void:
	_body = _spaced_box(BoxContainer.new()) as BoxContainer
	column.add_child(_body)
	_left = _spaced_box(VBoxContainer.new()) as VBoxContainer
	_right = _spaced_box(VBoxContainer.new()) as VBoxContainer
	_body.add_child(_left)
	_body.add_child(_right)


func _layout() -> void:
	if _body == null or _start_box == null:
		return
	_body.vertical = not _wide
	var left: Array[Control] = [_side_step, _map_step, _level_step]
	var right: Array[Control] = [_start_box]
	if _wide:
		left = [_side_step, _level_step]
		right = [_map_step, _start_box]
	_fill(_left, left)
	_fill(_right, right)


func _fill(target: VBoxContainer, parts: Array[Control]) -> void:
	for index: int in parts.size():
		var part: Control = parts[index]
		if part.get_parent() == null:
			target.add_child(part)
		elif part.get_parent() != target:
			part.reparent(target, false)
		target.move_child(part, index)


## The wide layout asks for the whole safe width inside the gaps; upright keeps the base column.
func _apply() -> void:
	super()
	if scroll == null or column == null:
		return
	var was_wide: bool = _wide
	_wide = not HudLayout.is_portrait()
	if _wide != was_wide and _body != null and _seen_scroll > 0:
		_hold_scroll(_seen_scroll)
	if _wide:
		column.custom_minimum_size.x = column_room_px()
	var gap: int = roundi(UiScale.dp(GAP_DP))
	for box: BoxContainer in _spaced:
		box.add_theme_constant_override("separation", gap)
	_layout()


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
		put_back.call()
	if is_instance_valid(bar):
		bar.changed.disconnect(put_back)


func _spaced_box(box: BoxContainer) -> BoxContainer:
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_spaced.append(box)
	return box


## One numbered step: its header (the number, the title, the current choice at the right in amber)
## and the box the caller fills. `key` names the choice label (`_choice_labels`).
func _step(number: int, title: StringName, key: StringName) -> VBoxContainer:
	var box: VBoxContainer = _spaced_box(VBoxContainer.new()) as VBoxContainer
	var head: HBoxContainer = _spaced_box(HBoxContainer.new()) as HBoxContainer
	box.add_child(head)
	var num: Label = _label(head, tr(MapSelectText.NUMBER) % number, &"MenuEyebrow")
	num.size_flags_horizontal = Control.SIZE_FILL
	num.autowrap_mode = TextServer.AUTOWRAP_OFF
	var heading: Label = _label(head, tr(title), &"MenuStepTitle")
	_step_words.append(num)
	_step_words.append(heading)
	var choice: Label = _label(head, "", &"MenuStepChoice")
	choice.size_flags_horizontal = Control.SIZE_SHRINK_END
	choice.autowrap_mode = TextServer.AUTOWRAP_OFF
	choice.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_choice_labels[key] = choice
	return box


## A faction card: the flat button that takes the touch, under the emblem, the tag, the name and
## the pitch (the content ignores touches). The chosen card is the amber one.
func _side_card(id: StringName, cards: HBoxContainer) -> Button:
	var card: PanelContainer = PanelContainer.new()
	card.name = &"SideCard_%s" % id
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cards.add_child(card)
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


## A map or level option: a PanelContainer card (its look kept in `cards`) holding a flat button
## that takes the touch, over the word and, locked, a lock row (the glyph and RANK n). A map is a
## row (word left, lock right); a level is a chip (word, lock under it): two lines at most.
func _option(
	id: StringName, word: String, pick: Callable, parent: Control, cards: Dictionary, row: bool
) -> Button:
	var card: PanelContainer = PanelContainer.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(card)
	cards[id] = card
	var button: Button = _button(card, &"CapsButton", "", pick.bind(id), BUTTON_DP)
	button.flat = true
	button.autowrap_mode = TextServer.AUTOWRAP_OFF
	var content: BoxContainer = HBoxContainer.new() if row else VBoxContainer.new()
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.alignment = BoxContainer.ALIGNMENT_CENTER
	card.add_child(content)
	var name_label: Label = _label(content, word, &"MenuOptionName")
	name_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	name_label.clip_text = true
	name_label.horizontal_alignment = (
		HORIZONTAL_ALIGNMENT_LEFT if row else HORIZONTAL_ALIGNMENT_CENTER
	)
	_names[id] = name_label
	var note: HBoxContainer = HBoxContainer.new()
	note.mouse_filter = Control.MOUSE_FILTER_IGNORE
	note.size_flags_horizontal = Control.SIZE_SHRINK_END if row else Control.SIZE_SHRINK_CENTER
	content.add_child(note)
	var glyph: TextureRect = TextureRect.new()
	glyph.texture = LOCK_ART
	glyph.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	glyph.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	glyph.custom_minimum_size = Vector2.ONE * UiScale.dp(LOCK_DP)
	note.add_child(glyph)
	var rank: Label = _label(note, "", &"MenuLockNote")
	rank.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	rank.autowrap_mode = TextServer.AUTOWRAP_OFF
	_notes[id] = note
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
		_show(_maps[id], _map_cards[id], id, KIND_MAP, id == map_id)
	for id: StringName in _levels:
		_show(_levels[id], _level_cards[id], id, KIND_LEVEL, id == level)
	for id: StringName in _sides:
		var picked: bool = id == side
		_side_cards[id].theme_type_variation = &"MenuSideCardOn" if picked else SIDE_LOOK[id]
		_tags[id].text = tr(MapSelectText.TAG_PICKED if picked else MapSelectText.TAG_OTHER)
		_tags[id].theme_type_variation = &"MenuEyebrow" if picked else SIDE_TAG_LOOK[id]
	var side_word: String = tr(SIDE_TEXT[side])
	var map_word: String = catalog.title(map_id).to_upper()
	var level_word: String = tr(LEVEL_TEXT[level])
	_choice_labels[&"side"].text = side_word
	_choice_labels[&"map"].text = map_word
	_choice_labels[&"level"].text = level_word
	_summary.text = tr(MapSelectText.SUMMARY) % [side_word, map_word, level_word]
	_start.disabled = _starting or not _can_start()
	UiWait.hold(_start, _starting)
	_start.text = tr(MapSelectText.STARTING if _starting else MapSelectText.START)


## One option of a step: the chosen one is amber, a locked one dim with its lock row (a locked
## choice is disabled), the others plain.
func _show(
	button: Button, card: PanelContainer, id: StringName, kind: StringName, chosen: bool
) -> void:
	var open: bool = is_open(kind, id)
	card.theme_type_variation = (
		&"MenuMapCardLocked" if not open else (&"MenuMapCardOn" if chosen else &"MenuMapCard")
	)
	button.disabled = not open
	_names[id].theme_type_variation = &"MenuOptionName" if open else &"MenuOptionNameLocked"
	_notes[id].visible = not open
	if not open:
		var rank: Label = _notes[id].get_child(1) as Label
		rank.text = tr(MapSelectText.LOCK_NOTE) % _progression.unlock_rank(kind, id)


func _label(parent: Control, text: String, look: StringName) -> Label:
	var label: Label = Label.new()
	label.text = text
	label.theme_type_variation = look
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(label)
	return label
