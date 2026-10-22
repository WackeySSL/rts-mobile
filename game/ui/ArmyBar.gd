class_name ArmyBar
extends HBoxContainer
## The bottom-left army controls (touch-ui-rules): "All army" and groups 1-3. It reports presses and
## shows the counts it is given; PlayerController decides what a press does. A tap on a group asks
## to recall it, a hold of `settings.group_assign_ms` asks to assign the selection.
## It sits on the safe area's bottom edge in both orientations, and in portrait directly above the
## build band once Phase 3 gives the bottom zone a height (`HudLayout`, ADR 0015 section 5).

signal all_army_pressed
signal group_tapped(slot: int)
signal group_assign_requested(slot: int)

const ALL_ARMY_DP: Vector2 = Vector2(96, 56)
const GROUP_DP: Vector2 = Vector2(56, 56)
const GAP_DP: float = 8.0

@export var settings: InputSettings

var _groups: Array[HoldButton] = []  ## Group `slot` is at `slot - 1`.


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE  # The gaps between buttons belong to the map.
	if settings == null:
		settings = InputSettings.new()  # The script defaults are the ADR table.
	var all_army: Button = Button.new()
	_add(all_army, "AllArmy", "All army", ALL_ARMY_DP)
	all_army.pressed.connect(func() -> void: all_army_pressed.emit())
	for slot: int in range(1, SelectionModel.GROUP_COUNT + 1):
		var group: HoldButton = HoldButton.new()
		_add(group, "Group%d" % slot, str(slot), GROUP_DP)
		group.hold_ms = settings.group_assign_ms
		group.tapped.connect(func() -> void: group_tapped.emit(slot))
		group.held.connect(func() -> void: group_assign_requested.emit(slot))
		_groups.append(group)
	get_viewport().size_changed.connect(_apply_dp)
	_apply_dp()


## Shows `count` under the number of group `slot` (1-3). An empty group shows the number only.
func set_group_count(slot: int, count: int) -> void:
	if slot >= 1 and slot <= _groups.size():
		_groups[slot - 1].text = str(slot) if count <= 0 else "%d\n%d" % [slot, count]


func _add(button: Button, node_name: String, label: String, size_dp: Vector2) -> void:
	var min_size: DpMinSize = DpMinSize.new()
	min_size.min_dp = size_dp
	button.add_child(min_size)
	button.name = node_name
	button.text = label
	button.focus_mode = Control.FOCUS_NONE  # No focus ring left behind after a tap.
	add_child(button)


## The gaps are dp, so they follow a resize like DpMinSize does. The buttons' text is the theme's.
func _apply_dp() -> void:
	add_theme_constant_override("separation", roundi(UiScale.dp(GAP_DP)))
	_lift()


## Sets the bottom margin of the band around the bar (`ArmyBand` in main.tscn, a MarginContainer
## that fills the safe area): 0 puts the bar on the safe area's bottom edge, as in landscape, and
## in portrait with a bottom zone (HudLayout) it lifts the bar to a gap above the zone. The bar
## sits at the band's bottom (size flag SHRINK_END), so a call from a stale state is harmless.
func _lift() -> void:
	var band: MarginContainer = get_parent() as MarginContainer
	if band == null:
		return
	var zone: float = HudLayout.bottom_zone_px() if HudLayout.is_portrait() else 0.0
	var lift: int = ceili(zone + UiScale.dp(GAP_DP)) if zone > 0.0 else 0
	band.add_theme_constant_override("margin_bottom", lift)
