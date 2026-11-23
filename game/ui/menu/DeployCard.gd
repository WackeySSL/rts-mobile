class_name DeployCard
extends CanvasLayer
## The still card that covers the match-start bake (plan P536, Michael's answer 10 of ADR 0043):
## the still app icon, the word DEPLOYING and the map's name. It shows on `MenuFlow.match_loading`;
## MenuFlow then waits two process frames (a start from a tap arrives before its frame is drawn, so
## the first only ends the tap's own), so the card is drawn before the main scene is made. Nothing
## on it moves (no fade, no spinner), so Reduced effects has nothing to switch off, and it carries
## no ad.
##
## It assumes no frame order: it reads `match_loading`, `match_start_finished(error)` and
## `current_runner()`. On an error the card goes away at once; on OK it goes away when a runner
## that did not exist at the signal stands in the tree (the match is ready). `HARD_FRAMES` is the
## last word, so it is never left stuck. It sits above every scene and takes every touch.

const ICON: Texture2D = preload("res://assets/art/svg/icon/app_icon.svg")
const THEME: Theme = preload("res://game/ui/theme.tres")
const LAYER: int = 90
const ICON_DP: float = 160.0
const GAP_DP: float = 16.0
## Frames after which the card goes away whatever happens (a backstop, never the normal way out).
## Above the ads settle bound (P450): the card now shows before that wait.
const HARD_FRAMES: int = 1800

var catalog: MapCatalog = null  ## Tests inject; null loads the catalog on first use.

var _flow: Node = null
var _root: Control = null
var _column: VBoxContainer = null
var _icon: TextureRect = null
var _map: Label = null
var _old_runner: MatchRunner = null
var _frames: int = 0
var _started: bool = false  ## match_start_finished(OK) came: the runner is on its way.


func _ready() -> void:
	DeployCardText.register()
	layer = LAYER
	process_mode = Node.PROCESS_MODE_ALWAYS  # A paused tree must not freeze the backstop.
	_build()
	_set_shown(false)
	get_viewport().size_changed.connect(_on_resized)


## Listens to `flow` (the MenuFlow autoload; a test passes its own instance).
func attach(flow: Node) -> void:
	_flow = flow
	flow.match_loading.connect(_on_match_loading)
	flow.match_start_finished.connect(_on_match_start_finished)


## Whether the card is on screen.
func is_showing() -> bool:
	return _root != null and _root.visible


## The map name on the card ("" when the setup has none).
func map_name() -> String:
	return _map.text if _map != null else ""


func _on_match_loading(setup: MatchSetup) -> void:
	_old_runner = _flow.current_runner()  # A restart still holds the old match until the new one.
	_frames = 0
	_started = false
	_map.text = _title_of(setup)
	_map.visible = _map.text != ""
	_apply_dp()
	_set_shown(true)


func _on_match_start_finished(error: Error) -> void:
	if not is_showing():
		return
	if error != OK:
		_set_shown(false)  # The start failed: nothing is coming.
	else:
		_started = true


func _process(_delta: float) -> void:
	if not is_showing():
		return
	_frames += 1
	var runner: MatchRunner = _flow.current_runner()
	var fresh: bool = runner != null and runner != _old_runner
	if _started and fresh and runner.is_inside_tree():
		_set_shown(false)  # The match is ready.
	elif _frames >= HARD_FRAMES:
		_set_shown(false)


func _title_of(setup: MatchSetup) -> String:
	if setup == null or setup.map_id == &"":
		return ""
	if catalog == null:
		catalog = load(MapCatalog.DEFAULT_PATH) as MapCatalog
	return "" if catalog == null else catalog.title(setup.map_id).to_upper()


func _set_shown(on: bool) -> void:
	_root.visible = on
	set_process(on)
	if not on:
		_old_runner = null


func _on_resized() -> void:
	if is_showing():  # A hidden card is sized when it shows.
		_apply_dp()


func _build() -> void:
	_root = Control.new()
	_root.name = &"Root"
	_root.mouse_filter = Control.MOUSE_FILTER_STOP  # Nothing behind it takes a touch.
	add_child(_root)
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var backdrop: PanelContainer = PanelContainer.new()
	backdrop.theme_type_variation = &"DeployBackdrop"  # The boot splash's colour.
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(backdrop)
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var safe: SafeAreaMargin = SafeAreaMargin.new()
	safe.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(safe)
	safe.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var centre: CenterContainer = CenterContainer.new()
	centre.mouse_filter = Control.MOUSE_FILTER_IGNORE
	safe.add_child(centre)
	_column = VBoxContainer.new()
	_column.alignment = BoxContainer.ALIGNMENT_CENTER
	centre.add_child(_column)
	_icon = TextureRect.new()
	_icon.texture = ICON
	_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_column.add_child(_icon)
	_label(&"CapsBigTitle", tr(DeployCardText.TITLE))
	_map = _label(&"CapsTitle", "")
	_apply_dp()


func _label(variation: StringName, text: String) -> Label:
	var label: Label = Label.new()
	label.theme_type_variation = variation
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_column.add_child(label)
	return label


## The sizes are dp, so a turn of the phone changes them; the theme is the HUD's in base px.
func _apply_dp() -> void:
	_root.theme = HudTheme.scaled(THEME, UiScale.base_px_per_dp())
	_column.add_theme_constant_override("separation", roundi(UiScale.dp(GAP_DP)))
	_icon.custom_minimum_size = Vector2.ONE * UiScale.dp(ICON_DP)
