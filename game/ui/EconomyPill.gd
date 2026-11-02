class_name EconomyPill
extends PanelContainer
## The economy pill (ADR 0025 section 3, plan P119): the menu button, the credits and the power bar
## in one 48 dp pill at the top left, sideways and upright alike. It replaces `StatusPill` and the
## status line of the build band and strip. It reads the published snapshot only (the local
## player's credits and power) and sends nothing to the sim.
## Credits and power are tap areas of at least 48 dp each (`economy_pressed`; the detail card is
## P119b), the menu button (`menu_pressed`) stays hidden until the pause menu (P124). Numbers keep
## fixed digit slots (`DigitRow`). Low power (`power_used` above `power_made`) is a word, a shape
## and a colour: the pill's border and the bar turn danger red, the bolt becomes the warning
## triangle and the word "LOW POWER" takes the numbers' place in the bar where it fits.
## This node takes the pill's rect from `HudCorners.place` (after what stands at the top left,
## `top_left`: the first visible of the Dev and Surrender buttons), on `_ready`, on every resize and
## when its content changes size.
## The pill is as wide as its content and asks the layout for the room the numbers (on low power the
## word) need in the bar: the bar takes what is left (P85c's fit), the layout gives what the safe
## rect and the scope's corner leave, and what does not fit drops (the numbers, then the word; the
## triangle and the red edge stay). That room is never part of the pill's minimum size: a Control
## does not shrink below it, so the layout's cap would no longer work.

signal menu_pressed
signal economy_pressed  ## The credits or the power was tapped.

const ICON_ART: String = "res://assets/art/svg/icons/%s.svg"
const VARIATION: StringName = &"EconomyPill"
const LOW_VARIATION: StringName = &"EconomyPillLow"
const TOKENS: StringName = &"HudTokens"
const BAR_VARIATION: StringName = &"PowerBar"
const BAR_LOW_VARIATION: StringName = &"PowerBarLow"
const NUMBER_VARIATION: StringName = &"PowerNumber"
const NUMBER_LOW_VARIATION: StringName = &"PowerNumberLow"
const GLYPH_DP: float = 24.0
const MENU_ICON_DP: float = 28.0  ## The menu button's glyph (the button is 48 dp).
const BAR_DP: Vector2 = Vector2(24.0, 28.0)  ## The bar's least size; it takes the rest of the pill.
const TAP_DP: float = 48.0
const GAP_DP: float = 4.0
const TEXT_PAD_DP: float = 2.0  ## Each side of the numbers and the word in the bar.
const TEXT_EDGE_DP: float = 2.0  ## The dark edge of the numbers on the bar.
const SLACK_DP: float = 1.0  ## What the containers' rounding to whole px may take of the bar.
## The credits' slot: 99 999. The rules set no ceiling (a snapshot holds an int32); a bigger bank
## widens the pill by a digit once.
const CREDITS_DIGITS: int = 5

@export var runner: MatchRunner
@export var safe_area: SafeAreaMargin  ## Its gap is the safe rect's (ADR 0025 section 2).
@export var top_left: Control  ## The pill starts after its first visible child (Dev, or Surrender).

var _line: HBoxContainer = HBoxContainer.new()
var _menu: Button = Button.new()
var _divider: VSeparator = VSeparator.new()
var _credits_tap: TapArea = TapArea.new()
var _credits_glyph: TextureRect
var _credits: DigitRow = DigitRow.new()
var _power_tap: TapArea = TapArea.new()
var _power_glyph: TextureRect
var _bar: ProgressBar = ProgressBar.new()
var _numbers: DigitRow = DigitRow.new()
var _word: Label = Label.new()
var _low: bool = false
var _shown: Vector3i = Vector3i(-1, -1, -1)  ## Credits, power made and power used on screen.
var _seen: Vector2i = Vector2i(-1, -1)  ## Serial and tick of the snapshot last read.


## A part of the pill that takes a tap: a press and a release on it, by the same finger.
class TapArea:
	extends HBoxContainer

	signal tapped

	var _finger: int = -1

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP
		add_to_group(TouchInput.CANCEL_GROUP)

	## A modal covers the screen: a finger that went down here is spent (TouchInput.CANCEL_GROUP).
	func cancel_gestures() -> void:
		_finger = -1

	func _gui_input(event: InputEvent) -> void:
		var touch: InputEventScreenTouch = event as InputEventScreenTouch
		if touch == null:
			return
		if touch.pressed:
			_finger = touch.index
		elif touch.index == _finger:
			_finger = -1
			if not touch.canceled and Rect2(Vector2.ZERO, size).has_point(touch.position):
				tapped.emit()


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP  # A touch on the pill is never a gesture on the map.
	theme_type_variation = VARIATION
	_min_dp(self, HudCorners.PILL_DP)
	_line.name = "Line"
	add_child(_line)
	_menu.name = "Menu"
	_menu.icon = load(ICON_ART % "glyph_menu")
	_menu.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_menu.flat = true
	_menu.focus_mode = Control.FOCUS_NONE
	_menu.pressed.connect(menu_pressed.emit)
	_min_dp(_menu, Vector2(TAP_DP, TAP_DP))
	_line.add_child(_menu)
	_divider.name = "Divider"
	_line.add_child(_divider)
	set_menu_shown(false)
	_credits_glyph = _fill_area(_credits_tap, "CreditsTap", "CreditsGlyph", "glyph_credits")
	_credits.name = "Credits"
	_credits.variation = &"NumberLabel"
	_credits.slots = CREDITS_DIGITS
	_credits_tap.add_child(_credits)
	_power_glyph = _fill_area(_power_tap, "PowerTap", "PowerGlyph", "glyph_power")
	_power_tap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_build_bar()
	_credits.set_text("0")
	_numbers.set_text("0/0")
	for tap: TapArea in [_credits_tap, _power_tap]:
		tap.tapped.connect(economy_pressed.emit)
	get_viewport().size_changed.connect(_apply_dp)
	minimum_size_changed.connect(place)
	_apply_dp()


func _notification(what: int) -> void:
	if what == NOTIFICATION_THEME_CHANGED and _power_glyph != null:
		_tint()
		_fit_bar_text()
		place.call_deferred()  # After the labels below have heard of the theme too.


## A frame reads the published snapshot when it is a new one (a tick, or a new match).
func _process(_delta: float) -> void:
	var snap: MatchSnapshot = null if runner == null else runner.snapshot
	if snap != null and Vector2i(snap.match_serial, snap.tick) != _seen:
		refresh()


## Shows the local player's credits and power from the published snapshot.
func refresh() -> void:
	var snap: MatchSnapshot = null if runner == null else runner.snapshot
	if snap == null or runner.scenario == null:
		return
	var player: int = runner.scenario.local_player
	_seen = Vector2i(snap.match_serial, snap.tick)
	var numbers: Vector3i = Vector3i(
		_entry(snap.credits, player),
		_entry(snap.power_made, player),
		_entry(snap.power_used, player)
	)
	if numbers != _shown:
		_shown = numbers
		_show(numbers.x, numbers.y, numbers.z)


## The menu button and its divider show from the pause menu's row (P124) on.
func set_menu_shown(shown: bool) -> void:
	_menu.visible = shown
	_divider.visible = shown


## Whether the pill shows low power: the hook of P89's pulse (kept although nothing reads it yet).
func is_low() -> bool:
	return _low


## Takes the rect `HudCorners.place` gives the pill: after the top-left control, as wide as it asks
## (its content and the room the bar's text needs, at least 200 dp, at most what the layout has),
## inside the safe rect, in both orientations.
func place() -> void:
	if not is_inside_tree():  # A deferred call that outlived the match's scene.
		return
	var dp: float = UiScale.base_px_per_dp()
	var shown: HudCorners.Shown = HudCorners.Shown.new()
	if top_left != null and top_left.visible:
		shown.left_taken = HudLayout.first_visible_width(top_left) / dp
	shown.pill_width = _wanted_dp()
	var margin_dp: float = (
		SafeAreaMargin.DEFAULT_MARGIN_DP if safe_area == null else safe_area.margin_dp
	)
	var safe: Rect2 = SafeAreaMargin.rect_inside(get_viewport().get_visible_rect(), margin_dp)
	var rects: Dictionary[StringName, Rect2] = HudCorners.place(
		safe, HudLayout.is_portrait(), dp, false, shown
	)
	position = rects[HudCorners.PILL].position
	size = rects[HudCorners.PILL].size


## The width the pill asks of the layout, in dp: its content (the bar at its least) and what the
## numbers, or on low power the word, still need beyond that bar. The bar takes all the room the
## pill is given, so this is the width at which the text fits.
func _wanted_dp() -> float:
	var content: float = _line.get_combined_minimum_size().x
	content += get_theme_stylebox(&"panel").get_minimum_size().x
	var text: Control = _word if _low else _numbers
	var more: float = text.get_combined_minimum_size().x + 2.0 * UiScale.dp(TEXT_PAD_DP)
	more += UiScale.dp(SLACK_DP) - UiScale.dp(BAR_DP.x)
	return (content + maxf(more, 0.0)) / UiScale.base_px_per_dp()


static func _entry(values: PackedInt32Array, player: int) -> int:
	return values[player] if player >= 0 and player < values.size() else 0


static func _min_dp(control: Control, size_dp: Vector2) -> void:
	var min_size: DpMinSize = DpMinSize.new()
	min_size.min_dp = size_dp
	control.add_child(min_size)


## One tap area: its name, the glyph in front, at least 48 dp each way.
func _fill_area(tap: TapArea, area_name: String, glyph_name: String, icon: String) -> TextureRect:
	tap.name = area_name
	_min_dp(tap, Vector2(TAP_DP, TAP_DP))
	_line.add_child(tap)
	var glyph: TextureRect = TextureRect.new()
	glyph.name = glyph_name
	glyph.texture = load(ICON_ART % icon)
	glyph.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	glyph.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	glyph.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	glyph.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_min_dp(glyph, Vector2(GLYPH_DP, GLYPH_DP))
	tap.add_child(glyph)
	return glyph


func _build_bar() -> void:
	_bar.name = "PowerBar"
	_bar.theme_type_variation = BAR_VARIATION
	_bar.show_percentage = false
	_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_bar.max_value = 1.0
	_bar.value = 0.0
	_min_dp(_bar, BAR_DP)
	_power_tap.add_child(_bar)
	_numbers.name = "PowerText"
	_numbers.variation = NUMBER_VARIATION
	_numbers.edge_dp = TEXT_EDGE_DP
	_word.name = "PowerWord"
	_word.text = "Low power"
	_word.uppercase = true
	_word.theme_type_variation = &"PillWord"
	_word.visible = false
	_word.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	for overlay: Control in [_numbers, _word]:
		# The full width and the middle of the bar. A line taller than the bar grows up and down
		# alike, never down alone.
		overlay.set_anchors_preset(Control.PRESET_HCENTER_WIDE)
		overlay.grow_vertical = Control.GROW_DIRECTION_BOTH
		overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_bar.add_child(overlay)
	# A theme change reaches a label after its parents: the fit follows the labels' own sizes too.
	_bar.resized.connect(_fit_bar_text)
	_word.minimum_size_changed.connect(_text_changed)
	_numbers.minimum_size_changed.connect(_text_changed)


## The numbers of the pill. The look changes only when the low state does.
func _show(credits: int, made: int, used: int) -> void:
	var low: bool = used > made
	_credits.set_text(str(credits))
	_bar.max_value = maxi(made, 1)
	_bar.value = _bar.max_value if low else used
	_numbers.set_text("%d/%d" % [used, made])
	if low != _low:
		_low = low
		theme_type_variation = LOW_VARIATION if low else VARIATION
		_bar.theme_type_variation = BAR_LOW_VARIATION if low else BAR_VARIATION
		_numbers.variation = NUMBER_LOW_VARIATION if low else NUMBER_VARIATION
		_power_glyph.texture = load(ICON_ART % ("glyph_low_power" if low else "glyph_power"))
		_tint()
		place()  # The text that needs the room is another one.
	_fit_bar_text()


## The glyphs' tints come from the theme's HUD tokens: money for the coin and the bolt, danger for
## the triangle.
func _tint() -> void:
	_credits_glyph.modulate = get_theme_color(&"money", TOKENS)
	_power_glyph.modulate = get_theme_color(&"danger" if _low else &"money", TOKENS)


## The text of the bar changed its size (a number, the theme): the pill asks again, and the text
## shows where it fits.
func _text_changed() -> void:
	place()
	_fit_bar_text()


## The word shows in the bar on low power where it fits, else the numbers where they fit; where
## neither fits the bar, the triangle and the colours speak alone.
func _fit_bar_text() -> void:
	var room: float = _bar.size.x - 2.0 * UiScale.dp(TEXT_PAD_DP)
	_word.visible = _low and _word.get_combined_minimum_size().x <= room
	_numbers.visible = not _word.visible and _numbers.get_combined_minimum_size().x <= room


## Sizes are dp, so they follow a resize.
func _apply_dp() -> void:
	_line.add_theme_constant_override("separation", roundi(UiScale.dp(GAP_DP)))
	for tap: TapArea in [_credits_tap, _power_tap]:
		tap.add_theme_constant_override("separation", roundi(UiScale.dp(GAP_DP)))
	_menu.add_theme_constant_override("icon_max_width", roundi(UiScale.dp(MENU_ICON_DP)))
	_tint()
	_fit_bar_text()
	place()
	place.call_deferred()  # The labels' sizes follow the theme a moment later.
