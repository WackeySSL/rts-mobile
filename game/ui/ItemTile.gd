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
## type (a name is built to fit, ADR 0032; the ellipsis is only a fallback); `SIZE_DP` is the
## nameless plate it starts as.
## A LOCKED card that knows what it lacks (`set_needs`) is crossed by a sash (ADR 0025 section 5,
## P120j): a light band rising at about 27 degrees across the picture and off both edges of the
## card, with the missing building's name on it in one line, never cut or wrapped (a test pins
## every name of the data against `sash_room_px`), and a padlock seal on a dark disc at the top
## left.
## The price is hidden then, as under a READY banner; the card's own name stays in the caption. The
## band is a shape, so the state does not rest on colour. A LOCKED card with no name known keeps the
## big centred padlock.
## `BuildSidebar` tells it what to show (`show_state`); it tells the sidebar what the finger did:
## `chose` for a tap, `long_pressed` for a hold of `hold_ms`, `dragged` for a drag beyond `slop_dp`,
## which scrolls the row and is then neither. The tile is a Button, so a touch on it never reaches
## the map. The look is the theme's (`ItemTile`, `ItemCost`, `ItemCostLow`, `ItemBanner`,
## `ItemSash`), in dp.

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
## The sash of a locked card (all dp but the angle): the band rises SASH_RISE_RAD (27 degrees)
## about the stage's middle, as low as the name's tilted box goes (its corner on the stage's foot,
## where the count badge above is farthest away), SASH_THICK_DP thick with an edge line of
## SASH_EDGE_DP. The name stands in a box SASH_TEXT_DP high (a line of 14 sp) that keeps SASH_END_DP
## clear of the card's edge at both ends.
## The seal is a SEAL_DP disc SEAL_INSET_DP from the stage's top left corner (the count badge has
## the top right) with a SEAL_GLYPH_DP padlock in it.
const SASH_RISE_RAD: float = 0.4712389
const SASH_THICK_DP: float = 24.0
const SASH_EDGE_DP: float = 1.5
const SASH_TEXT_DP: float = 19.0
const SASH_END_DP: float = 2.5
const SEAL_DP: float = 26.0
const SEAL_INSET_DP: float = 3.0
const SEAL_GLYPH_DP: float = 16.0
const FULL_WORD: String = "FULL"
const STRIPE_DP: Vector2 = Vector2(14.0, 5.0)  ## The step between stripes and their width.
const VARIATION: StringName = &"ItemTile"
const COST_VARIATION: StringName = &"ItemCost"
const COST_LOW_VARIATION: StringName = &"ItemCostLow"
const BANNER_VARIATION: StringName = &"ItemBanner"
const CAPTION_VARIATION: StringName = &"ItemCaption"
const SASH_VARIATION: StringName = &"ItemSash"
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
var _word: Label = Label.new()  ## In the stage: "FULL".
var _sash: Sash = Sash.new()  ## In the stage: the band with the missing name, and the seal's disc.
var _lock_fit: DpMinSize = DpMinSize.new()
var _needs: String = ""  ## The display name of the missing requirement or producer.
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


## The band, its edges and the seal's disc of a locked card, and the name that runs along it. It
## fills the stage; the stage clips the band, so it runs off the card's edges and no further.
class Sash:
	extends Control
	var band: Color
	var edge: Color
	var seal: Color
	var label: Label = Label.new()
	var centre: Vector2 = Vector2.ZERO  ## The middle of the band and of the name's box.

	func _init() -> void:
		label.name = "SashText"
		label.theme_type_variation = ItemTile.SASH_VARIATION
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(label)
		resized.connect(lay_out)

	## The name in a box of the band's room, turned to the band's angle about its middle. The middle
	## is as low as the turned box can go, so that the band keeps clear of the count badge above.
	func lay_out() -> void:
		label.size = Vector2(ItemTile.sash_room_px(size), UiScale.dp(ItemTile.SASH_TEXT_DP))
		label.pivot_offset = label.size / 2.0
		var turned: float = label.size.x * sin(ItemTile.SASH_RISE_RAD)
		turned += label.size.y * cos(ItemTile.SASH_RISE_RAD)
		centre = Vector2(size.x / 2.0, size.y - turned / 2.0)
		label.position = centre - label.size / 2.0
		label.rotation = -ItemTile.SASH_RISE_RAD
		queue_redraw()

	func _draw() -> void:
		var along: Vector2 = Vector2.from_angle(-ItemTile.SASH_RISE_RAD)
		var across: Vector2 = along.orthogonal() * UiScale.dp(ItemTile.SASH_THICK_DP) / 2.0
		var at: Vector2 = centre
		var reach: Vector2 = along * (size.x + size.y)  # Well past both edges of the stage.
		draw_colored_polygon(
			PackedVector2Array(
				[at - reach - across, at + reach - across, at + reach + across, at - reach + across]
			),
			band
		)
		for side: float in [-1.0, 1.0]:
			var line: Vector2 = across * side
			draw_line(
				at - reach + line, at + reach + line, edge, UiScale.dp(ItemTile.SASH_EDGE_DP), true
			)
		var seal_px: float = UiScale.dp(ItemTile.SEAL_DP)
		var inset: float = UiScale.dp(ItemTile.SEAL_INSET_DP)
		draw_circle(
			Vector2(inset, inset) + Vector2(seal_px, seal_px) / 2.0,
			seal_px / 2.0,
			seal,
			true,
			-1.0,
			true
		)


## The longest name, in px, that the sash holds in one line on a card `card_px` wide (base px; only
## the width counts, the stage is as wide as the card): the box of the name, tilted, spans the card
## less `SASH_END_DP` at each end. The drawing and the name-fit test both read this.
static func sash_room_px(card_px: Vector2) -> float:
	var end: float = UiScale.dp(SASH_END_DP)
	var tall: float = UiScale.dp(SASH_TEXT_DP)
	return (card_px.x - 2.0 * end - tall * sin(SASH_RISE_RAD)) / cos(SASH_RISE_RAD)


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
	_word.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_word.set_anchors_preset(Control.PRESET_FULL_RECT)
	_word.text = FULL_WORD
	_word.visible = false
	_sash.set_anchors_preset(Control.PRESET_FULL_RECT)
	_sash.visible = false
	_stage.clip_contents = true  # The band runs off the card's edges and stops there.
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
	_add(_sash, "Sash", _stage)
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
## none); "" when nothing is known. The card then shows that name on its sash.
func set_needs(display_name: String) -> void:
	if display_name == _needs:
		return
	_needs = display_name
	_show_word()


## The word of the state: "FULL" in the middle of the stripes, or the missing name on the sash.
func word() -> String:
	if _sash.visible:
		return _needs
	return _word.text if _word.visible else ""


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


## The words and shapes of the state. A named lock hides the price (the sash stands over the
## picture and the seal takes the padlock's place); else the padlock is the big centred one.
func _show_word() -> void:
	var named: bool = state == State.LOCKED and not _needs.is_empty()
	_cost.visible = state != State.READY and not named
	_word.visible = state == State.FULL
	_sash.visible = named
	if named:
		_sash.label.text = _needs
		_sash.lay_out()  # A label keeps the size a longer name gave it.
	_place_lock(named)


## The padlock: whole and grey in the middle of the stage, or white in the seal's disc at its top
## left.
func _place_lock(named: bool) -> void:
	var glyph: float = SEAL_GLYPH_DP if named else LOCK_DP
	_lock_fit.min_dp = Vector2(glyph, glyph)
	if named:
		var room: float = SEAL_INSET_DP + (SEAL_DP - SEAL_GLYPH_DP) / 2.0
		_lock.set_anchors_and_offsets_preset(
			Control.PRESET_TOP_LEFT, Control.PRESET_MODE_MINSIZE, roundi(UiScale.dp(room))
		)
	else:
		_lock.set_anchors_and_offsets_preset(Control.PRESET_CENTER, Control.PRESET_MODE_MINSIZE)
	var edge: Control.GrowDirection = (
		Control.GROW_DIRECTION_END if named else Control.GROW_DIRECTION_BOTH
	)
	_lock.grow_horizontal = edge
	_lock.grow_vertical = edge
	_lock.modulate = (
		get_theme_color(&"seal_glyph", SASH_VARIATION)
		if named
		else get_theme_color(&"lock", VARIATION)
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
	_sash.band = get_theme_color(&"band", SASH_VARIATION)
	_sash.edge = get_theme_color(&"edge", SASH_VARIATION)
	_sash.seal = get_theme_color(&"seal", SASH_VARIATION)
	_sash.lay_out()
	_place_lock(_sash.visible)
	_stripes.color = get_theme_color(&"stripe", VARIATION)
	_stripes.step = UiScale.dp(STRIPE_DP.x)
	_stripes.width = UiScale.dp(STRIPE_DP.y)
	_stripes.queue_redraw()
	_icon.set_anchors_and_offsets_preset(
		Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, roundi(UiScale.dp(ICON_INSET_DP))
	)


## The icon is dimmed behind the padlock of a locked tile.
func _tint_icon() -> void:
	_icon.modulate = get_theme_color(
		&"icon_locked" if state == State.LOCKED else &"icon", VARIATION
	)
