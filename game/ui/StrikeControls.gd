class_name StrikeControls
extends HBoxContainer
## The strike controls of the HUD (plan P112, ADR 0023 section 10): the strike button with its
## charge ring while the local player owns a strike building and, while the player aims, the check
## mark and the X before it. A tap on the ready button starts the aim (its foot asks "Tap map" until
## a point is placed) and a tap on the pressed one ends it; the check mark (dimmed until a point is
## placed) sends the one SUPERWEAPON, the X cancels.
## Placed by `HudCorners.place` (ADR 0025 section 10, plan P120c): the button stands 8 dp above
## BUILD at its 72 dp, the check mark and the X to its left, in both orientations; the parent is
## the Hud, and this node takes the rect that holds the button and, while aiming, the row, on
## `_ready`, on every resize and when the aim starts or ends. It hides with BUILD while the drawer
## or the pause menu is open (the landscape panel covers its column, the portrait sheet the bottom
## stack).

signal reserved_changed  ## The room the aim's row takes changed (`HudLayout.aim_zone_dp`).

const GAP_DP: float = 8.0
const ACTION_DP: float = 64.0  ## The check mark and the X: placement's size (touch-ui-rules).
const ICON_DP: float = 32.0
const CARD_ART: String = "res://assets/art/iso/icons/item_%s.svg"

@export var aim: StrikeAim
@export var runner: MatchRunner  ## The type ids that name the card.
@export var feed: HudStateFeed  ## The unfolds that cover the column.
@export var safe_area: SafeAreaMargin  ## Its gap is the safe rect's (ADR 0025 section 2).

var _strike: StrikeButton = StrikeButton.new()
var _confirm: Button = Button.new()
var _cancel: Button = Button.new()
var _card: Texture2D = null
var _card_type: int = -1
var _dp_px: float = 1.0  ## `UiScale.base_px_per_dp()`, read when the window changes.
var _aiming: bool = false  ## The aim showed when the rect was last taken.


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE  # The gaps between the buttons belong to the map.
	_strike.toggled.connect(_on_toggled)
	_confirm.pressed.connect(aim.confirm)
	_cancel.pressed.connect(aim.cancel)
	for part: Control in [_confirm, _cancel, _strike]:
		part.size_flags_vertical = Control.SIZE_SHRINK_CENTER  # A plate keeps its shape.
		add_child(part)
	_confirm.hide()  # Only the button, until the player aims.
	_cancel.hide()
	_confirm.name = "StrikeConfirm"
	_cancel.name = "StrikeCancel"
	_strike.name = "StrikeButton"
	for action: Array in [[_confirm, "StrikeConfirm", "check"], [_cancel, "StrikeButton", "cross"]]:
		var button: Button = action[0]
		button.theme_type_variation = action[1]
		button.icon = load("res://assets/art/svg/icons/glyph_%s.svg" % action[2])
		button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER  # The icon alone, in the plate.
		button.focus_mode = Control.FOCUS_NONE  # No focus ring left behind after a tap.
		var fit: DpMinSize = DpMinSize.new()
		fit.min_dp = Vector2(ACTION_DP, ACTION_DP)
		button.add_child(fit)
	aim.changed.connect(_show)
	feed.state.changed.connect(_on_unfold)
	get_viewport().size_changed.connect(_apply_dp)
	_apply_dp()
	_show()


## The button's toggle starts or ends the aim; a strike still charging nudges the button.
func _on_toggled(on: bool) -> void:
	if not on:
		aim.cancel()
	elif not aim.begin():
		_strike.set_pressed_no_signal(false)
		_strike.nudge()


## Shows what `aim` says: the button while a strike building is owned, the rest while aiming.
func _show() -> void:
	var snap: MatchSnapshot = null if runner == null else runner.snapshot
	visible = aim.owned and snap != null and not _covered()
	if not visible:
		return
	if aim.type_index != _card_type:
		_card_type = aim.type_index
		var art: String = CARD_ART % snap.type_ids[_card_type]
		_card = load(art) if ResourceLoader.exists(art) else null
	var seconds: int = ceili(float(aim.wait) / Sim.TICK_RATE)
	var hint: bool = aim.active and not aim.has_point
	_strike.show_state(_card, aim.building_id != 0, aim.share, seconds, hint)
	_strike.set_pressed_no_signal(aim.active)
	_confirm.visible = aim.active
	_confirm.disabled = not aim.has_point
	_cancel.visible = aim.active
	if aim.active != _aiming:
		place()


## The drawer or the pause menu opened or closed.
func _on_unfold(_previous: HudState.Unfold) -> void:
	_show()


func _covered() -> bool:
	return feed.state.is_open(HudState.Unfold.DRAWER) or feed.state.is_open(HudState.Unfold.PAUSE)


## Sizes are dp, so they follow a resize like DpMinSize does; then the rect.
func _apply_dp() -> void:
	_dp_px = UiScale.base_px_per_dp()
	add_theme_constant_override("separation", roundi(GAP_DP * _dp_px))
	for button: Button in [_confirm, _cancel]:
		button.add_theme_constant_override("icon_max_width", roundi(ICON_DP * _dp_px))
	place()


## Takes the rect `HudCorners.place` gives the button (and, while aiming, the row to its left).
func place() -> void:
	_aiming = aim.active
	var shown: HudCorners.Shown = HudCorners.Shown.new()
	shown.strike = true
	shown.aim = _aiming
	var margin_dp: float = SafeAreaMargin.DEFAULT_MARGIN_DP
	margin_dp = margin_dp if safe_area == null else safe_area.margin_dp
	var safe: Rect2 = SafeAreaMargin.rect_inside(get_viewport().get_visible_rect(), margin_dp)
	var rects: Dictionary[StringName, Rect2] = HudCorners.place(
		safe, HudLayout.is_portrait(), UiScale.base_px_per_dp(), false, shown
	)
	var span: Rect2 = rects[HudCorners.STRIKE]
	if _aiming:
		span = span.merge(rects[HudCorners.STRIKE_ROW])
	# The plates round their dp up, so the row may be a pixel more than the layout's: it grows
	# toward the screen's inside (left and up), never out of the safe rect.
	size = span.size.max(_least())
	position = span.end - size
	var room: float = 0.0
	if _aiming and not HudLayout.is_portrait():
		room = (safe.end.x - rects[HudCorners.STRIKE_ROW].position.x) / UiScale.base_px_per_dp()
		room += HudCorners.GAP_DP
	if room != HudLayout.aim_zone_dp:
		HudLayout.aim_zone_dp = room
		reserved_changed.emit()


func _exit_tree() -> void:
	HudLayout.aim_zone_dp = 0.0


## What the shown plates ask for, in a row: the container's own cached answer lags a frame behind
## a plate that was just shown or hidden.
func _least() -> Vector2:
	var least: Vector2 = Vector2.ZERO
	for part: Control in [_confirm, _cancel, _strike]:
		if part.visible:
			var ask: Vector2 = part.get_combined_minimum_size()
			least = Vector2(
				least.x + ask.x + (_dp_px * GAP_DP if least.x > 0.0 else 0.0), maxf(least.y, ask.y)
			)
	return least
