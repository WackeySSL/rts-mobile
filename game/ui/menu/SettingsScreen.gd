class_name SettingsScreen
extends MenuScreen
## The Settings screen (plan P526, ADR 0043 section 5): Sound and Music steps (saved, and put on
## `AudioService` at once), Vibration (`HudPrefs`), Reduced effects (saved in `MenuPrefs`; a match
## reads it at its start, never during one), Privacy options (only when the consent service says
## they are required; the tap awaits its form), the empty `PurchaseSlot` (Phase 6's Remove ads /
## Restore; a VBoxContainer, not a plain Container, so it takes its child's size, and it is hidden
## and 0 tall while no child shows),
## Replay tutorial, How to play and Licences through `MenuRoutes` (a route nobody registered
## leaves its button present and disabled) and Developer (debug and `dev_menu` builds), which
## changes to the dev menu scene through `DevRoutes` and needs no route.
## In battle (opened from the pause menu) no purchase slot and no privacy row (Michael, 2026-11-17).
## The saved volume reaches `AudioService` from `MenuFlow._ready`; the reduced switch reaches the
## intro, the menu stack and the next match's `LifeSettings` from `MenuFlow` (P526b). No Command,
## no sim. The foot
## banner slot stays empty and 0 tall until Phase 6's band.

const ROW_DP: Vector2 = Vector2(0.0, 48.0)
const TOGGLE_DP: Vector2 = Vector2(88.0, 48.0)
const VALUE_DP: Vector2 = Vector2(32.0, 0.0)
const LABEL_DP: Vector2 = Vector2(96.0, 0.0)
const TITLE: String = "SETTINGS"
const SOUND: String = "SOUND"
const MUSIC: String = "MUSIC"
const VIBRATION: String = "VIBRATION"
const REDUCED: String = "REDUCED EFFECTS"
const PRIVACY: String = "PRIVACY OPTIONS"
const HOW_TO_PLAY: String = "HOW TO PLAY"
const REPLAY: String = "REPLAY TUTORIAL"
const LICENCES_TEXT: String = "LICENCES"
const DEVELOPER_TEXT: String = "DEVELOPER"
const ON: String = "ON"
const OFF: String = "OFF"

## Tests replace these before the screen is pushed; null means the autoloads.
var routes: MenuRoutes = MenuRoutes.shared
var ad_service: Node = null
var audio: Node = null
## Whether the Developer button shows.
var dev_enabled: Callable = DevRoutes.is_enabled
## Opens the dev menu scene; tests replace it.
var open_dev: Callable = _open_dev
## Whether a match is running (opened from the pause menu); tests replace it.
var in_match: Callable = _in_match

var purchase_slot: VBoxContainer
var remove_rows: RemoveAdsRows
var sound_slider: HSlider
var music_slider: HSlider
var vibration_toggle: Button
var reduced_toggle: Button
var privacy_button: Button
var _routed: Dictionary[Button, StringName] = {}
var _asking: bool = false
var _built: bool = false


func _ready() -> void:
	super()
	var tree: SceneTree = get_tree()
	audio = audio if audio != null else tree.root.get_node_or_null("AudioService")
	ad_service = ad_service if ad_service != null else tree.root.get_node_or_null("AdService")
	_heading()
	var top: int = _top_step()
	var sound: int = _initial(&"Sfx", MenuPrefs.sound_step)
	var music: int = _initial(&"Music", MenuPrefs.music_step)
	sound_slider = _slider(
		SOUND, top, sound, _on_sound, _chip_muted(&"Sfx", sound, MenuPrefs.sound_step)
	)
	music_slider = _slider(
		MUSIC, top, music, _on_music, _chip_muted(&"Music", music, MenuPrefs.music_step)
	)
	vibration_toggle = _toggle(VIBRATION, HudPrefs.haptics_enabled(), _on_vibration)
	reduced_toggle = _toggle(REDUCED, MenuPrefs.reduced_effects(), _on_reduced)
	if not in_match.call():  # In battle neither node exists, so no widget can land there.
		privacy_button = add_button(tr(PRIVACY), _ask_privacy)
		purchase_slot = VBoxContainer.new()
		purchase_slot.name = &"PurchaseSlot"
		purchase_slot.visible = false
		purchase_slot.child_entered_tree.connect(_watch_slot_child)
		purchase_slot.child_exiting_tree.connect(_sync_later)
		column.add_child(purchase_slot)
		remove_rows = RemoveAdsRows.new()
		remove_rows.service = ad_service
		purchase_slot.add_child(remove_rows)  # P434: hides itself with no store (or no AdService).
	if not in_match.call():  # A lesson starts a new match: never over the one that is running.
		_route_button(REPLAY, MenuRoutes.TUTORIAL)
	_route_button(HOW_TO_PLAY, MenuRoutes.HOW_TO_PLAY)
	_route_button(LICENCES_TEXT, MenuRoutes.LICENCES)
	if dev_enabled.call():
		add_button(tr(DEVELOPER_TEXT), func() -> void: open_dev.call())
	_built = true
	_listen()
	_refresh()


func _notification(what: int) -> void:
	if what == NOTIFICATION_ENTER_TREE and _built:
		_listen()  # Back from a screen: the routes may have changed.
		_refresh()
	elif what == NOTIFICATION_EXIT_TREE and _built:
		if routes.changed.is_connected(_refresh):
			routes.changed.disconnect(_refresh)


## Back is refused while a purchase or restore call is open: its rows resume on this screen.
func on_back() -> bool:
	return remove_rows != null and remove_rows.is_busy()


func _listen() -> void:
	if not routes.changed.is_connected(_refresh):
		routes.changed.connect(_refresh)


func _refresh() -> void:
	for button: Button in _routed:
		button.disabled = not routes.has(_routed[button])
	if privacy_button != null:
		privacy_button.visible = (
			ad_service != null and ad_service.call("is_privacy_options_required")
		)


func _ask_privacy() -> void:
	if _asking or ad_service == null:
		return  # One form at a time.
	_asking = true
	await ad_service.call("show_privacy_options")
	_asking = false
	if is_inside_tree():
		_refresh()  # The answer may change whether the row is needed.


func _top_step() -> int:
	return int(audio.get("settings").steps) if audio != null else 10


## What the bus plays now, so under a chip mute (the pause menu's, which lasts the session, also on
## the main menu after the match) the slider sits at 0 and its label reads OFF: the save is kept and
## a drag unmutes and saves. The saved step, else the top one, with no audio service.
func _initial(bus: StringName, saved: Callable) -> int:
	var step: int = int(audio.call("get_step", bus)) if audio != null else saved.call(_top_step())
	return clampi(step, 0, _top_step())


## The bus plays 0 while a step above 0 is saved, or none is (the chip then turns on to the default
## step): a chip's session mute, not the player's own 0.
func _chip_muted(bus: StringName, step: int, saved: Callable) -> bool:
	return step == 0 and int(saved.call(_default_step(bus))) > 0


## The step a chip turns a bus on to when nothing is saved (`AudioSettings`, as PauseMenu reads it).
func _default_step(bus: StringName) -> int:
	var settings: AudioSettings = audio.get("settings") as AudioSettings if audio != null else null
	if settings == null:
		return _top_step()
	return settings.default_music_step if bus == &"Music" else settings.default_sfx_step


func _on_sound(value: float) -> void:
	_set_label(sound_slider, value)
	MenuPrefs.set_sound_step(int(value))
	if audio != null:
		audio.call("set_sound_step", int(value))


func _on_music(value: float) -> void:
	_set_label(music_slider, value)
	MenuPrefs.set_music_step(int(value))
	if audio != null:
		audio.call("set_step", &"Music", int(value))


func _on_vibration(on: bool) -> void:
	HudPrefs.set_haptics_enabled(on)
	_show_state(vibration_toggle)


func _on_reduced(on: bool) -> void:
	MenuPrefs.set_reduced_effects(on)
	_show_state(reduced_toggle)
	var stack: MenuStack = get_parent() as MenuStack
	if stack != null:  # The open stack follows at once; a match reads it at its next start.
		stack.reduced = on


func _open(route: StringName) -> void:
	var stack: MenuStack = get_parent() as MenuStack
	if stack != null and routes.has(route):
		stack.push(routes.make(route))


## The slot is hidden, so 0 tall, while no child shows (as the `OfferSlot` is).
func _watch_slot_child(child: Node) -> void:
	var control: Control = child as Control
	if control != null and not control.visibility_changed.is_connected(_sync_later):
		control.visibility_changed.connect(_sync_later)  # The screen re-enters the tree on Back.
	_sync_later()


func _sync_later(_child: Node = null) -> void:
	_sync_slot.call_deferred()  # A child leaving is gone from the list by then.


func _sync_slot() -> void:
	var any: bool = false
	for child: Node in purchase_slot.get_children():
		if child is Control and (child as Control).visible:
			any = true
	purchase_slot.visible = any


func _in_match() -> bool:
	return MenuFlow.current_runner() != null


func _open_dev() -> void:
	DevRoutes.open(get_tree(), DevRoutes.DEV_MENU_SCENE)


func _route_button(text: String, route: StringName) -> void:
	_routed[add_button(tr(text), _open.bind(route))] = route


func _heading() -> void:
	var label: Label = Label.new()
	label.text = tr(TITLE)
	label.theme_type_variation = &"CapsTitle"
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(label)


## A row of 48 dp or more: a name, a slider of whole steps and its value (OFF while `muted`).
func _slider(text: String, top: int, value: int, changed: Callable, muted: bool) -> HSlider:
	var row: HBoxContainer = _row(text)
	var slider: HSlider = HSlider.new()
	slider.theme_type_variation = &"MenuSlider"
	slider.min_value = 0.0
	slider.max_value = float(top)
	slider.step = 1.0
	slider.value = float(value)
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_floor(slider, ROW_DP)
	row.add_child(slider)
	var number: Label = Label.new()
	number.name = &"Value"
	number.text = tr(OFF) if muted else str(value)  # A chip mute reads like the chip: OFF.
	number.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_floor(number, VALUE_DP)
	row.add_child(number)
	slider.value_changed.connect(changed)
	return slider


func _set_label(slider: HSlider, value: float) -> void:
	(slider.get_parent().get_node("Value") as Label).text = str(int(value))


## A row with a name and a button that reads ON or OFF (the words, never colour alone).
func _toggle(text: String, on: bool, changed: Callable) -> Button:
	var row: HBoxContainer = _row(text)
	var button: Button = Button.new()
	button.toggle_mode = true
	button.button_pressed = on
	_floor(button, TOGGLE_DP)
	row.add_child(button)
	_show_state(button)
	button.toggled.connect(changed)
	return button


func _show_state(button: Button) -> void:
	button.text = tr(ON) if button.button_pressed else tr(OFF)
	button.theme_type_variation = &"MenuToggle" if button.button_pressed else &"MenuToggleOff"


func _row(text: String) -> HBoxContainer:
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", roundi(UiScale.dp(GAP_DP)))
	_floor(row, ROW_DP)
	column.add_child(row)
	var label: Label = Label.new()
	label.text = tr(text)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_floor(label, LABEL_DP)
	row.add_child(label)
	return row


func _floor(control: Control, min_dp: Vector2) -> void:
	var floor_dp: DpMinSize = DpMinSize.new()
	floor_dp.min_dp = min_dp
	control.add_child(floor_dp)
