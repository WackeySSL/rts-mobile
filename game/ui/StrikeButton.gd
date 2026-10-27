class_name StrikeButton
extends Button
## The strike button (plan P112, ADR 0023 section 10): a plate with the strike building's item card
## inside a ring, the charge as a share of a turn from the top, clockwise. While the strike cannot
## fire the foot shows the time left (m:ss); when it can, the ring is full and green and the foot
## says "Ready": a number against a word, never colour alone. A toggle, pressed while the player
## aims; a tap on one that cannot fire only nudges it. `StrikeControls` tells it what to show.

const SIZE_DP: float = 72.0
const RING_DP: float = 6.0
const CARD_DP: float = 40.0
const FOOT_DP: float = 10.0  ## The foot's distance from the plate's edge.
const VARIATION: StringName = &"StrikeButton"
const RING_POINTS: int = 64
const NUDGE_S: float = 0.06

var fires: bool = false  ## The strike can fire.
var charge: float = 0.0  ## The ring's share, 0 to 1.
var nudges: int = 0

var _card: Texture2D = null
var _time: Label = Label.new()
var _banner: Label = Label.new()


func _init() -> void:
	theme_type_variation = VARIATION
	toggle_mode = true
	focus_mode = Control.FOCUS_NONE  # No focus ring left behind after a tap.
	var fit: DpMinSize = DpMinSize.new()
	fit.min_dp = Vector2(SIZE_DP, SIZE_DP)
	add_child(fit)
	_time.theme_type_variation = &"ItemCost"
	_banner.theme_type_variation = &"ItemBanner"
	for label: Label in [_time, _banner]:
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE  # The plate is what the finger finds.
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
		label.grow_horizontal = Control.GROW_DIRECTION_BOTH
		label.grow_vertical = Control.GROW_DIRECTION_BEGIN
		add_child(label)
	_time.name = "StrikeTime"
	_banner.name = "StrikeReady"
	show_state(null, false, 0.0, 0)


func _ready() -> void:
	get_viewport().size_changed.connect(_apply_dp)
	_apply_dp()


## The card and the ring over the plate; the foot's labels are children and come after.
func _draw() -> void:
	var middle: Vector2 = size * 0.5
	var width: float = UiScale.dp(RING_DP)
	var reach: float = minf(size.x, size.y) * 0.5 - width * 0.5
	if _card != null:
		var half: Vector2 = Vector2.ONE * UiScale.dp(CARD_DP) * 0.5
		draw_texture_rect(_card, Rect2(middle - half, half * 2.0), false)
	var track: Color = get_theme_color(&"ring_track", VARIATION)
	draw_arc(middle, reach, 0.0, TAU, RING_POINTS, track, width, true)
	if charge > 0.0:
		var fill: Color = get_theme_color(&"ring_ready" if fires else &"ring_charge", VARIATION)
		draw_arc(middle, reach, -PI * 0.5, -PI * 0.5 + TAU * charge, RING_POINTS, fill, width, true)


func _notification(what: int) -> void:
	if what == NOTIFICATION_THEME_CHANGED:
		queue_redraw()


## What to show: the card, whether the strike can fire, the ring's share, the seconds left and, with
## `hint`, a foot that asks for the point instead of saying "Ready".
@warning_ignore("integer_division")
func show_state(
	card: Texture2D, can_fire: bool, share: float, seconds: int, hint: bool = false
) -> void:
	_card = card
	_banner.text = "Tap map" if hint else "Ready"
	fires = can_fire
	charge = clampf(share, 0.0, 1.0)
	_time.text = "%d:%02d" % [seconds / 60, seconds % 60]
	_time.visible = not can_fire
	_banner.visible = can_fire
	queue_redraw()


## A short press-in: the tap of a strike that is still charging.
func nudge() -> void:
	nudges += 1
	pivot_offset = size * 0.5
	var tween: Tween = create_tween()
	tween.tween_property(self, "scale", Vector2.ONE * 0.9, NUDGE_S)
	tween.tween_property(self, "scale", Vector2.ONE, NUDGE_S)


## The foot sits inside the ring, so its offset is dp.
func _apply_dp() -> void:
	for label: Label in [_time, _banner]:
		label.offset_bottom = -UiScale.dp(FOOT_DP)
	queue_redraw()
