class_name StrikeControls
extends HBoxContainer
## The strike controls of the HUD (plan P112, ADR 0023 section 10): the strike button with its
## charge ring while the local player owns a strike building and, while the player aims, the check
## mark and the X before it. A tap on the ready button starts the aim (its foot asks "Tap map" until
## a point is placed) and a tap on the pressed one ends it; the check mark (dimmed until a point is
## placed) sends the one SUPERWEAPON, the X cancels.
## Landscape: the top line, left of the minimap's slot. Portrait: the right edge, a gap above the
## ArmyBar's line, which is a gap above the build band. The parent `MarginContainer` is the band the
## row sits in; this node sets its margins, and it comes after the BuildSidebar in the scene, so the
## band's height is in place. The row is 200 dp wide at most, which every phone's width holds.

const GAP_DP: float = 8.0
const ACTION_DP: float = 56.0  ## The check mark and the X.
const ICON_DP: float = 32.0
const CARD_ART: String = "res://assets/art/iso/icons/item_%s.svg"

@export var aim: StrikeAim
@export var runner: MatchRunner  ## The type ids that name the card.

var _strike: StrikeButton = StrikeButton.new()
var _confirm: Button = Button.new()
var _cancel: Button = Button.new()
var _card: Texture2D = null
var _card_type: int = -1


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE  # The gaps between the buttons belong to the map.
	_strike.toggled.connect(_on_toggled)
	_confirm.pressed.connect(aim.confirm)
	_cancel.pressed.connect(aim.cancel)
	for part: Control in [_confirm, _cancel, _strike]:
		part.size_flags_vertical = Control.SIZE_SHRINK_CENTER  # A plate keeps its shape.
		add_child(part)
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
	visible = aim.owned and snap != null
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


## Sizes are dp, so they follow a resize like DpMinSize does; then the band's margins.
func _apply_dp() -> void:
	var gap: float = UiScale.dp(GAP_DP)
	add_theme_constant_override("separation", roundi(gap))
	for button: Button in [_confirm, _cancel]:
		button.add_theme_constant_override("icon_max_width", roundi(UiScale.dp(ICON_DP)))
	var band: MarginContainer = get_parent() as MarginContainer
	if band == null:
		return
	var portrait: bool = HudLayout.is_portrait()
	var bar: int = (
		ceili(HudLayout.bottom_zone_px() + gap) + ceili(UiScale.dp(ArmyBar.ALL_ARMY_DP.y))
	)
	size_flags_horizontal = Control.SIZE_SHRINK_END
	size_flags_vertical = Control.SIZE_SHRINK_END if portrait else Control.SIZE_SHRINK_BEGIN
	band.add_theme_constant_override("margin_bottom", bar + ceili(gap) if portrait else 0)
	var slot: float = UiScale.dp(HudLayout.SLOT_DP.x) + gap
	band.add_theme_constant_override("margin_right", 0 if portrait else ceili(slot))
