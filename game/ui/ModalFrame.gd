class_name ModalFrame
extends Control
## The frame of a screen that covers the HUD (plan P90): the result screen, the pause menu and the
## confirm dialog.
## The root takes every touch, so nothing behind it is selected, ordered or panned. The safe area
## and a scroll (for a window too short for the panel) hold the panel; a subclass adds its rows to
## `column` in `_ready`, after `super()`, and shows itself with `visible`. The look is the theme's.

const GAP_DP: float = 12.0
const BUTTON_DP: Vector2 = Vector2(136.0, 64.0)

var column: VBoxContainer


func _ready() -> void:
	visible = false
	mouse_force_pass_scroll_events = false  # The wheel is the modal's too, not the map's.
	column = VBoxContainer.new()
	var scrim: PanelContainer = PanelContainer.new()
	scrim.theme_type_variation = &"Scrim"
	add_child(scrim)
	scrim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var safe: SafeAreaMargin = SafeAreaMargin.new()
	add_child(safe)
	safe.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	safe.add_child(scroll)
	var centre: CenterContainer = CenterContainer.new()
	centre.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	centre.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.add_child(centre)
	var panel: PanelContainer = PanelContainer.new()
	panel.theme_type_variation = &"HudPanel"
	centre.add_child(panel)
	panel.add_child(column)
	get_viewport().size_changed.connect(_apply_dp)
	visibility_changed.connect(_on_visibility_changed)
	_apply_dp()


## A label of type variation `variation` ("Label" for body text) with `text`, added to `parent`.
func add_label(parent: Node, text: String, variation: StringName) -> Label:
	var label: Label = Label.new()
	label.theme_type_variation = variation
	label.text = text
	parent.add_child(label)
	return label


## A CapsButton of at least `BUTTON_DP` calling `action`; `text` is upper case (no case property).
func add_button(parent: Node, text: String, action: Callable) -> Button:
	var button: Button = Button.new()
	button.theme_type_variation = &"CapsButton"
	button.text = text
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var floor_dp: DpMinSize = DpMinSize.new()
	floor_dp.min_dp = BUTTON_DP
	button.add_child(floor_dp)
	button.pressed.connect(action)
	parent.add_child(button)
	return button


## Shows the modal with the keyboard focus on `first`, so a key never reaches the HUD behind it.
## The focus is hidden (no focus ring after a tap, as the rest of the HUD); a key shows it.
func show_over(first: Button) -> void:
	visible = true
	first.grab_focus(true)


## A modal that shows ends every gesture in flight under it (a held finger, a hold, a pan).
func _on_visibility_changed() -> void:
	if is_visible_in_tree():
		get_tree().call_group(TouchInput.CANCEL_GROUP, &"cancel_gestures")


## The gaps are dp: a resize and a turn change them.
func _apply_dp() -> void:
	column.add_theme_constant_override("separation", roundi(UiScale.dp(GAP_DP)))
