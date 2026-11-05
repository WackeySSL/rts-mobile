class_name AttackToast
extends PanelContainer
## The attack toast (ADR 0025 section 8, plan P123): a 48 dp panel with a danger border, the warning
## glyph, "<NAME> UNDER ATTACK" over "Tap to jump there", for as long as `AttackCues` has a cue.
## A tap (a press and a release by one finger on it) centres the camera on the hit, folds the
## drawer and dismisses the cue; the touch is the toast's own and never reaches the map. It is
## hidden while the full map is open (the attack is a ping there) and while the pause menu is.
## Its rect is `HudCorners.TOAST` (between the pill and the scope, upright under the pill), taken on
## a cue, a change of the unfolds and every resize. Texts are written when the cue changes, never
## per frame.

const ICON_ART: String = "res://assets/art/svg/icons/%s.svg"
const VARIATION: StringName = &"EconomyPillLow"  ## The pill's danger edge.
const TEXT_VARIATION: StringName = &"ItemCaption"
const TITLE_VARIATION: StringName = &"AttackTitle"  ## The caps face, tinted danger.
const TOKENS: StringName = &"HudTokens"
const GLYPH_DP: float = 24.0
const GAP_DP: float = 6.0
const HINT: String = "Tap to jump there"

@export var cues: AttackCues
@export var feed: HudStateFeed
@export var camera: RtsCamera
@export var safe_area: SafeAreaMargin
@export var pill: Control  ## Landscape: the toast stands after it.
## Landscape, where the room beside the pill is short, the toast stands under the top line: right
## of this column, which starts on that line.
@export var group_column: GroupColumn
@export var build_button: BuildButton  ## The column's width upright depends on its Ready chip.

var _row: HBoxContainer = HBoxContainer.new()
var _glyph: TextureRect = TextureRect.new()
var _title: Label = Label.new()
var _hint: Label = Label.new()
var _finger: int = -1


func _ready() -> void:
	add_to_group(TouchInput.CANCEL_GROUP)
	mouse_filter = Control.MOUSE_FILTER_STOP  # A touch on the toast never reaches the map.
	theme_type_variation = VARIATION
	visible = false
	_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_row)
	_glyph.texture = load(ICON_ART % "glyph_alert")
	_glyph.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_glyph.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_glyph.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_row.add_child(_glyph)
	var lines: VBoxContainer = VBoxContainer.new()
	lines.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lines.alignment = BoxContainer.ALIGNMENT_CENTER
	lines.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_row.add_child(lines)
	_title.theme_type_variation = TITLE_VARIATION
	_hint.theme_type_variation = TEXT_VARIATION
	for label: Label in [_title, _hint]:
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		lines.add_child(label)
	_hint.text = HINT
	cues.cue_changed.connect(_sync)
	if pill != null:  # A wider pill (the low-power word, more digits) moves the toast's room.
		pill.item_rect_changed.connect(_replace)
	if group_column != null:  # More or fewer groups move the column's right edge.
		group_column.laid_out.connect(_replace)
	feed.state.changed.connect(_on_unfold_changed)
	get_viewport().size_changed.connect(_apply_dp)
	_apply_dp()


## The rect `HudCorners.place` gives the toast for the screen and the pill in force.
func place() -> void:
	var dp: float = UiScale.base_px_per_dp()
	var shown: HudCorners.Shown = HudCorners.Shown.new()
	feed.state.fill(shown)
	feed.state.fill_bar(shown)
	shown.map = false  # Hidden then; the rect is still the toast's own.
	shown.toast = true
	if pill != null:
		shown.pill_width = pill.size.x / dp
	if group_column != null:
		shown.groups = group_column.item_count()
	shown.ready = build_button != null and build_button.ready_type >= 0
	var margin_dp: float = (
		SafeAreaMargin.DEFAULT_MARGIN_DP if safe_area == null else safe_area.margin_dp
	)
	var safe: Rect2 = SafeAreaMargin.rect_inside(get_viewport().get_visible_rect(), margin_dp)
	var rect: Rect2 = HudCorners.place(safe, HudLayout.is_portrait(), dp, false, shown)[
		HudCorners.TOAST
	]
	position = rect.position
	size = rect.size


## A press on the toast and its release by the same finger, still on it, is a tap.
func _gui_input(event: InputEvent) -> void:
	var touch: InputEventScreenTouch = event as InputEventScreenTouch
	if touch == null:
		return
	if touch.pressed:
		_finger = touch.index
	elif touch.index == _finger:
		_finger = -1
		if not touch.canceled and Rect2(Vector2.ZERO, size).has_point(touch.position):
			jump()


## Centres the camera on the hit, folds the drawer and dismisses the cue.
func jump() -> void:
	if not cues.active:
		return
	if camera != null:
		camera.centre_on(cues.point)
	feed.state.close(HudState.Unfold.DRAWER)
	cues.dismiss()


## A modal covers the screen: a finger that went down here is spent (TouchInput.CANCEL_GROUP).
func cancel_gestures() -> void:
	_finger = -1


func _replace() -> void:
	if visible:
		place()


func _on_unfold_changed(_previous: HudState.Unfold) -> void:
	_sync()


func _sync() -> void:
	var state: HudState = feed.state
	var want: bool = cues.active and not state.is_open(HudState.Unfold.RADAR)
	want = want and not state.is_open(HudState.Unfold.PAUSE)
	if want and _title.text != cues.title:
		_title.text = cues.title
	visible = want
	if want:
		place()
	else:
		_finger = -1


func _apply_dp() -> void:
	var edge: int = roundi(UiScale.dp(GLYPH_DP))
	_glyph.custom_minimum_size = Vector2(edge, edge)
	_glyph.modulate = get_theme_color(&"danger", TOKENS)
	_title.modulate = get_theme_color(&"danger", TOKENS)
	_row.add_theme_constant_override("separation", roundi(UiScale.dp(GAP_DP)))
	if visible:
		place()
