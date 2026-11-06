class_name ItemTile
extends HoldButton
## One build item of the sidebar (plan P85b, ADR 0019 section 1): the icon of a type on a 64 dp
## plate, its cost at the foot, a badge for the items of the type queued, a fill that rises over the
## icon with the head's progress, and a state shown by a shape and not by colour alone: a padlock
## (LOCKED), stripes (UNAFFORDABLE, FULL; the cost amber for money), a "Ready" banner (READY).
## The foot of the tile is the cost's plate, and the shapes of a state (the fill, the stripes, the
## padlock) fill the area above it, so none of them is ever drawn under the plate: the fill's share
## is a share of that area. A READY structure is paid for, so its banner takes the foot in the
## plate's place (the cost is hidden): the count badge, always there on a ready tile, is at the top
## corner and the banner at the bottom, and the two never meet however many digits the count has.
## The card is named (ADR 0025 section 5, plan P120): `set_card(size)` makes it
## `CARD_DP` sideways or
## `CARD_PORTRAIT_DP` upright and shows the type's display name in a line under the plate, in 14 dp
## type, cut with an ellipsis where it does not fit; `SIZE_DP` is the nameless plate it starts as.
## `BuildSidebar` tells it what to show (`show_state`); it tells the sidebar what the finger did:
## `chose` for a tap, `long_pressed` for a hold of `hold_ms`, `dragged` for a drag beyond `slop_dp`,
## which scrolls the row and is then neither. The tile is a Button, so a touch on it never reaches
## the map. The look is the theme's (`ItemTile`, `ItemCost`, `ItemCostLow`, `ItemBanner`), in dp.

signal chose  ## A tap: released before `hold_ms`, within `slop_dp`.
signal long_pressed  ## A hold of `hold_ms`, within `slop_dp`.
signal dragged(relative: Vector2)  ## The finger moved beyond `slop_dp`: the row follows it.

enum State { AVAILABLE, LOCKED, UNAFFORDABLE, FULL, READY }

const SIZE_DP: float = 64.0
## The named card: the drawer's size sideways, and upright (ADR 0025 section 5, at least).
const CARD_DP: Vector2 = Vector2(88.0, 96.0)
const CARD_PORTRAIT_DP: Vector2 = Vector2(92.0, 100.0)
const ICON_INSET_DP: float = 3.0
const LOCK_DP: float = 32.0
## The padlock when the missing building's name stands beside it (ADR 0025 section 5): inline, the
## first thing on the name's first line.
const LOCK_WORDED_DP: float = 14.0
const LOCK_GAP_DP: float = 2.0  ## Between that padlock and the name's first glyph.
## The padlock's room at the start of line one is no-break spaces (NBSP), each followed by a word
## joiner. The joiner is not a space: when the room ends line one (the name's first word starts line
## two), the label's edge-space trim would otherwise cut the NBSPs down to one. The font has no
## glyph for it; the shaper hides it (zero width). Do not "clean it up".
const NBSP: String = "\u00a0"
const JOIN: String = "\u2060"
## After the room and before the name: a break is allowed here and nowhere inside the room, so a
## name too long to share line one with the padlock starts line two whole.
const BREAK_OK: String = "\u200b"
const FULL_WORD: String = "FULL"
const STRIPE_DP: Vector2 = Vector2(14.0, 5.0)  ## The step between stripes and their width.
const VARIATION: StringName = &"ItemTile"
const COST_VARIATION: StringName = &"ItemCost"
const COST_LOW_VARIATION: StringName = &"ItemCostLow"
const BANNER_VARIATION: StringName = &"ItemBanner"
const CAPTION_VARIATION: StringName = &"ItemCaption"
const LOCK_ART: String = "res://assets/art/svg/icons/glyph_lock.svg"
const SHAKE_RAD: float = 0.08
const SHAKE_S: float = 0.05

var type_index: int = -1
var tab: int = -1  ## The `World.Tab` whose queue builds the type.
var faction: int = -1  ## The type's `type_faction` (an index into `faction_ids`), -1 for any.
var state: State = State.AVAILABLE
var queued: int = 0  ## The items of the type in the queue.
var progress: float = 0.0  ## The head's progress when it is of the type (0 to 1).
var slop_dp: float = 12.0  ## `InputSettings.tap_slop_dp`.
var shakes: int = 0  ## How many times the tile has shaken, for the tests.

var _fit: DpMinSize = DpMinSize.new()  ## The tile's least size: `SIZE_DP`, or `CARD_DP` named.
var _icon: TextureRect = TextureRect.new()
var _column: VBoxContainer = VBoxContainer.new()  ## The area above the foot, and the foot.
var _stage: Control = Control.new()  ## The area above the foot (cost or banner): the shapes.
var _fill: ColorRect = ColorRect.new()
var _stripes: Stripes = Stripes.new()
var _lock: TextureRect = TextureRect.new()
var _banner: Label = Label.new()
var _caption: Label = Label.new()
var _word: Label = Label.new()  ## In the stage: "FULL", or the name (after the padlock's room).
var _lock_fit: DpMinSize = DpMinSize.new()
var _needs: String = ""  ## The display name of the missing requirement or producer.
var _word_key: String = ""  ## What the word was last laid out for (state, name, badge).
var _inline: bool = false  ## The padlock stands inline before the name (else in the corner).
var _cost: Label = Label.new()
var _badge: Label = Label.new()
var _offset: Vector2 = Vector2.ZERO  ## The finger's move since the press.
var _scrolling: bool = false
var _shake: Tween = null
var _shown: bool = false  ## `show_state` has been called once.


## The diagonal stripes of a tile that cannot take an item now.
class Stripes:
	extends Control
	var color: Color
	var step: float = 24.0
	var width: float = 6.0

	func _draw() -> void:
		var at: float = -size.y
		while at < size.x:
			draw_line(Vector2(at, size.y), Vector2(at + size.y, 0.0), color, width)
			at += step


func _init() -> void:
	super()  # HoldButton wires its press, hold and release here.
	theme_type_variation = VARIATION
	focus_mode = Control.FOCUS_NONE  # No focus ring left behind after a tap.
	clip_contents = true
	tapped.connect(_on_tapped)
	held.connect(_on_held)
	_fit.min_dp = Vector2(SIZE_DP, SIZE_DP)
	add_child(_fit)
	_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_lock.texture = load(LOCK_ART)
	_lock.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_lock.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_lock.set_anchors_preset(Control.PRESET_CENTER)
	_lock.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_lock.grow_vertical = Control.GROW_DIRECTION_BOTH
	_lock_fit.min_dp = Vector2(LOCK_DP, LOCK_DP)
	_lock.add_child(_lock_fit)
	_word.theme_type_variation = CAPTION_VARIATION
	_word.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_word.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	_word.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_word.max_lines_visible = 2  # The stage holds two lines of 14 sp (a test pins every name).
	_word.text_overrun_behavior = TextServer.OVERRUN_NO_TRIMMING  # A name is never cut.
	_word.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED  # A translation keys on the name.
	_word.set_anchors_preset(Control.PRESET_FULL_RECT)
	_word.visible = false
	_word.resized.connect(_fit_word)
	_banner.text = "Ready"
	_banner.theme_type_variation = BANNER_VARIATION
	_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_caption.theme_type_variation = CAPTION_VARIATION
	_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_caption.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_caption.visible = false
	_cost.theme_type_variation = COST_VARIATION
	_cost.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_badge.theme_type_variation = COST_VARIATION
	_badge.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_badge.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_fill.set_anchors_preset(Control.PRESET_FULL_RECT)
	_stripes.set_anchors_preset(Control.PRESET_FULL_RECT)
	_column.set_anchors_preset(Control.PRESET_FULL_RECT)
	_column.add_theme_constant_override(&"separation", 0)  # The plate sits right under the stage.
	_stage.size_flags_vertical = Control.SIZE_EXPAND_FILL  # The cost keeps its height, this the rest.
	_add(_icon, "Icon")
	_add(_column, "Column")
	_add(_stage, "Stage", _column)
	_add(_cost, "Cost", _column)
	_add(_banner, "Banner", _column)  # The foot of a READY tile, where the cost is not.
	_add(_caption, "Caption", _column)  # Under the foot, in the named card.
	_add(_fill, "Fill", _stage)
	_add(_stripes, "Stripes", _stage)
	_add(_lock, "Lock", _stage)
	_add(_word, "Word", _stage)
	_add(_badge, "Badge")
	show_state(State.AVAILABLE, 0, 0.0)


func _ready() -> void:
	super()
	_look()


func _notification(what: int) -> void:
	if what == NOTIFICATION_THEME_CHANGED:
		_look()


## What the tile is: the type's index and tab, its icon, its cost and its display name.
func setup(index: int, queue_tab: int, art: Texture2D, cost: int, label: String) -> void:
	type_index = index
	tab = queue_tab
	_icon.texture = art
	_cost.text = str(cost)
	_caption.text = label


## The picture of the card (the Ready badge of the collapsed menu shows it too).
func art() -> Texture2D:
	return _icon.texture


## The card of `size_dp` with the name under its foot.
func set_card(size_dp: Vector2) -> void:
	_caption.visible = true
	_fit.min_dp = size_dp


## The display name of what a LOCKED card lacks (its requirement, or its producer when there is
## none); "" when nothing is known. The card then shows that name with a small padlock before it
## (inline when the name and the padlock fit and no count shows, else in the card's corner).
func set_needs(display_name: String) -> void:
	if display_name == _needs:
		return
	_needs = display_name
	_show_word()


## The word of the state: "FULL" in the middle of the stripes, the missing name in up to two
## lines at the stage's foot (the padlock inline before it, or in the stage's top left corner).
func word() -> String:
	if not _word.visible:
		return ""
	return _name() if _worded() else _word.text


## Shows the state, the queued count and the head's progress (a share, 0 to 1).
func show_state(new_state: State, count: int, share: float) -> void:
	if _shown and new_state == state and count == queued and is_equal_approx(share, progress):
		return  # Most tiles do not change from one tick to the next.
	_shown = true
	state = new_state
	queued = count
	progress = share
	var ready: bool = new_state == State.READY
	_tint_icon()
	_lock.visible = new_state == State.LOCKED
	_stripes.visible = new_state == State.UNAFFORDABLE or new_state == State.FULL
	_banner.visible = ready
	_cost.visible = not ready
	_fill.visible = share > 0.0 and not ready
	_fill.anchor_top = 1.0 - share
	_badge.visible = count > 0
	_badge.text = str(count)
	_cost.theme_type_variation = (
		COST_LOW_VARIATION if new_state == State.UNAFFORDABLE else COST_VARIATION
	)
	_show_word()


## A short wiggle: a tap on a tile that cannot take an item.
func shake() -> void:
	shakes += 1
	pivot_offset = size / 2.0
	if _shake != null:
		_shake.kill()
	_shake = create_tween()
	for angle: float in [SHAKE_RAD, -SHAKE_RAD, 0.0]:
		_shake.tween_property(self, "rotation", angle, SHAKE_S)


## A move beyond the slop is a scroll (the first hands over all the finger has moved since the
## press), and then the touch is neither a tap nor a hold.
func _gui_input(event: InputEvent) -> void:
	var touch: InputEventScreenTouch = event as InputEventScreenTouch
	var drag: InputEventScreenDrag = event as InputEventScreenDrag
	if touch != null and touch.pressed:
		_offset = Vector2.ZERO
		_scrolling = false
	elif drag != null and _scrolling:
		dragged.emit(drag.relative)
	elif drag != null:
		_offset += drag.relative
		if _offset.length() > UiScale.dp(slop_dp):
			_scrolling = true
			dragged.emit(_offset)


func _on_tapped() -> void:
	if not _scrolling:
		chose.emit()


func _on_held() -> void:
	if not _scrolling:
		long_pressed.emit()


func _worded() -> bool:
	return state == State.LOCKED and not _needs.is_empty()


## Lays the word out again only when what it is made of changed: the state, the name or whether a
## count shows (the count and the progress as such never move it).
func _show_word() -> void:
	var key: String = "%d|%s|%s" % [state, _needs, queued > 0]
	if key == _word_key:
		return
	_word_key = key
	_fit_word()


## The name as shown: a translation keys on the display name itself.
func _name() -> String:
	return tr(_needs)


## The word, the padlock and their fit. A name with a padlock inline needs: no count badge on the
## card, the padlock and the name's first word together on line one, the whole name in at most two
## lines. Else the card is main's: the bare name and the padlock in the stage's top left corner.
func _fit_word() -> void:
	var needs: bool = _worded()
	_word.visible = needs or state == State.FULL
	_word.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM if needs else VERTICAL_ALIGNMENT_CENTER
	var size_dp: float = LOCK_WORDED_DP if needs else LOCK_DP
	_lock_fit.min_dp = Vector2(size_dp, size_dp)
	_inline = false
	if needs:
		if queued == 0:
			_word.text = _room() + _name()
			_inline = _word.size.x <= 0.0 or _name_fits_inline()  # A size comes with the layout.
		if not _inline:
			_word.text = _name()
	else:
		_word.text = FULL_WORD
	_tint_lock()
	if needs:
		_lock.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT, Control.PRESET_MODE_MINSIZE)
		_lock.grow_horizontal = Control.GROW_DIRECTION_END
		_lock.grow_vertical = Control.GROW_DIRECTION_END
		if _inline:
			_place_lock()
	else:
		_lock.set_anchors_and_offsets_preset(Control.PRESET_CENTER, Control.PRESET_MODE_MINSIZE)
		_lock.grow_horizontal = Control.GROW_DIRECTION_BOTH
		_lock.grow_vertical = Control.GROW_DIRECTION_BOTH


## The padlock's room and the gap: whole no-break spaces at least as wide as both (the padlock is
## placed against the name, so the room's slack stays at its left). A space is measured in the
## label itself, as it lays the text out (a font measure of a lone no-break space is a pixel off).
func _room() -> String:
	_word.text = NBSP + JOIN + "x"
	var space: float = _word.get_character_bounds(0).size.x
	if space <= 0.0:
		return ""
	var wide: float = UiScale.dp(LOCK_WORDED_DP + LOCK_GAP_DP)
	return (NBSP + JOIN).repeat(ceili(wide / space)) + BREAK_OK


## The room's length in the word's text, and the name's.
func _room_length() -> int:
	return _word.text.length() - _name().length()


## Read from the label after its layout: the whole name in the visible lines, and the padlock's
## room and the name's first word on one line.
func _name_fits_inline() -> bool:
	var lines: int = _word.get_line_count()
	if lines > _word.max_lines_visible:
		return false
	var name_text: String = _name()
	var start: int = _room_length()
	var end: int = name_text.find(" ")
	end = name_text.length() if end < 0 else end
	var line_y: float = _word.get_character_bounds(0).position.y
	for index: int in [start, start + end - 1]:
		if absf(_word.get_character_bounds(index).position.y - line_y) > 1.0:
			return false
	return true


## The padlock inline: on line one's box (the label's own layout, with its spacing, margins and
## alignment), with the gap against the name's first glyph.
func _place_lock() -> void:
	var edge: float = UiScale.dp(LOCK_WORDED_DP)
	var line: Rect2 = _word.get_character_bounds(0)
	var first: Rect2 = _word.get_character_bounds(_room_length())
	_lock.position = (
		_word.position
		+ Vector2(
			first.position.x - UiScale.dp(LOCK_GAP_DP) - edge,
			line.position.y + (line.size.y - edge) / 2.0
		)
	)


## A part of the tile that the finger never finds: the tile is what it finds.
func _add(part: Control, part_name: String, parent: Control = self) -> void:
	part.name = part_name
	part.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(part)


## The tints, the fill, the stripes and the inset of the icon, from the theme and the dp scale.
func _look() -> void:
	_tint_icon()
	_fill.color = get_theme_color(&"fill", VARIATION)
	_tint_lock()
	_fit_word.call_deferred()  # The word's own theme items are fresh only after this notification.
	_stripes.color = get_theme_color(&"stripe", VARIATION)
	_stripes.step = UiScale.dp(STRIPE_DP.x)
	_stripes.width = UiScale.dp(STRIPE_DP.y)
	_stripes.queue_redraw()
	_icon.set_anchors_and_offsets_preset(
		Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, roundi(UiScale.dp(ICON_INSET_DP))
	)


## The padlock inline is tinted like the name; in the corner or alone it has the theme's lock
## colour.
func _tint_lock() -> void:
	if _worded() and _inline:
		_lock.modulate = get_theme_color(&"font_color", CAPTION_VARIATION)
	else:
		_lock.modulate = get_theme_color(&"lock", VARIATION)


## The icon is dimmed behind the padlock of a locked tile.
func _tint_icon() -> void:
	_icon.modulate = get_theme_color(
		&"icon_locked" if state == State.LOCKED else &"icon", VARIATION
	)
