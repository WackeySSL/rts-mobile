class_name DeployCard
extends CanvasLayer
## The still card that covers the match-start bake (plan P536, Michael's answer 10 of ADR 0043;
## the look is ADR 0052 section 3, P668): the loading picture under the `MenuScrim` shade (the
## `MenuBackdrop` class, built when the card shows and freed when it closes, so the picture does
## not stay in memory), the word DEPLOYING, the map's name and one tip line. The tip is the next in
## `DeployCardText.TIPS`, by a counter in `MenuPrefs` that moves once per card. The text sits on
## the shaded side: the left in the wide crop, the top in the tall one. It shows on
## `MenuFlow.match_loading`;
## MenuFlow then waits two process frames (a start from a tap arrives before its frame is drawn, so
## the first only ends the tap's own), so the card is drawn before the main scene is made. Nothing
## on it moves (no fade, no spinner), so Reduced effects has nothing to switch off, and it carries
## no ad.
##
## It assumes no frame order: it reads `match_loading`, `match_start_finished(error)` and
## `current_runner()`. On an error the card goes away at once; on OK it goes away when a runner
## that did not exist at the signal stands in the tree (the match is ready). The card shows before
## the ads settle (P450), so it waits through it. A time backstop
## (`AdsSettingsDef.deploy_backstop_ms`: ms, not frames, so the refresh rate does not matter) is the
## last word, so it is never left stuck; it never fires while a full-screen ad is open. It sits
## above every scene and takes every touch.

const WIDE_ART: String = "res://assets/art/backdrops/loading_wide.png"
const TALL_ART: String = "res://assets/art/backdrops/loading_tall.png"
const THEME: Theme = preload("res://game/ui/theme.tres")
const LAYER: int = 90
const EDGE_DP: float = 32.0  ## The text's gap to the screen edge.
const TIP_WIDTH_DP: float = 360.0
const GAP_DP: float = 16.0

var catalog: MapCatalog = null  ## Tests inject; null loads the catalog on first use.
## The clock of the backstop (ms); tests replace it.
var now_ms: Callable = Time.get_ticks_msec
var backstop_ms: int = AdsSettingsDef.load_default().deploy_backstop_ms

var _flow: Node = null
var _root: Control = null
var _column: VBoxContainer = null
var _inner: MarginContainer = null
var _backdrop: MenuBackdrop = null
var _map: Label = null
var _tip: Label = null
var _old_runner: MatchRunner = null
var _since_ms: int = 0  ## When the start began, or the last ad closed.
var _ad_open: bool = false
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
	var ads: Object = flow.get("ads")
	if ads != null and ads.has_signal("ad_opened"):
		ads.connect("ad_opened", _on_ad_opened)
		ads.connect("ad_closed", _on_ad_closed)


## Whether the card is on screen.
func is_showing() -> bool:
	return _root != null and _root.visible


## The map name on the card ("" when the setup has none).
func map_name() -> String:
	return _map.text if _map != null else ""


func _on_match_loading(setup: MatchSetup) -> void:
	_old_runner = _flow.current_runner()  # A restart still holds the old match until the new one.
	_since_ms = int(now_ms.call())
	_ad_open = false
	_started = false
	_map.text = _title_of(setup)
	_map.visible = _map.text != ""
	_tip.text = tr(DeployCardText.tip_key(MenuPrefs.take_tip(DeployCardText.TIPS.size())))
	_apply_dp()
	_open_backdrop()
	_apply_dp()  # The crop is known now: it decides the side the text sits on.
	_set_shown(true)


func _on_match_start_finished(error: Error) -> void:
	if not is_showing():
		return
	if error != OK:
		_set_shown(false)  # The start failed: nothing is coming.
	else:
		_started = true


func _on_ad_opened(_placement: StringName) -> void:
	_ad_open = true


func _on_ad_closed(_placement: StringName) -> void:
	_ad_open = false
	_since_ms = int(now_ms.call())


func _process(_delta: float) -> void:
	if not is_showing():
		return
	var runner: MatchRunner = _flow.current_runner()
	var fresh: bool = runner != null and runner != _old_runner
	if _started and fresh and runner.is_inside_tree():
		_set_shown(false)  # The match is ready.
	elif not _ad_open and int(now_ms.call()) - _since_ms >= backstop_ms:
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
		_close_backdrop()


## The picture and shade under the text; dropped when it cannot be drawn (the flat colour stays).
func _open_backdrop() -> void:
	_close_backdrop()
	_backdrop = MenuBackdrop.new()
	_backdrop.wide_path = WIDE_ART
	_backdrop.tall_path = TALL_ART
	_root.add_child(_backdrop)
	_root.move_child(_backdrop, 1)  # Over the flat colour, under the text.
	if not _backdrop.usable:
		_close_backdrop()


func _close_backdrop() -> void:
	if _backdrop != null:
		_backdrop.free()
		_backdrop = null


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
	_inner = MarginContainer.new()
	_inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	safe.add_child(_inner)
	_column = VBoxContainer.new()
	_inner.add_child(_column)
	_label(&"CapsBigTitle", tr(DeployCardText.TITLE))
	_map = _label(&"CapsTitle", "")
	_tip = _label(&"", "")
	_tip.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_apply_dp()


func _label(variation: StringName, text: String) -> Label:
	var label: Label = Label.new()
	label.theme_type_variation = variation
	label.text = text
	_column.add_child(label)
	return label


## The sizes are dp, so a turn of the phone changes them; the theme is the HUD's in base px.
func _apply_dp() -> void:
	_root.theme = HudTheme.scaled(THEME, UiScale.base_px_per_dp())
	_column.add_theme_constant_override("separation", roundi(UiScale.dp(GAP_DP)))
	var view: Vector2 = get_viewport().get_visible_rect().size
	var tall: bool = _backdrop.is_tall if _backdrop != null else view.x < view.y
	var edge: int = roundi(UiScale.dp(EDGE_DP))
	for side: String in ["left", "right", "top", "bottom"]:
		_inner.add_theme_constant_override("margin_" + side, edge)
	_column.size_flags_horizontal = (
		Control.SIZE_SHRINK_CENTER if tall else Control.SIZE_SHRINK_BEGIN
	)
	_column.size_flags_vertical = Control.SIZE_SHRINK_BEGIN if tall else Control.SIZE_SHRINK_CENTER
	var align: HorizontalAlignment = (
		HORIZONTAL_ALIGNMENT_CENTER if tall else HORIZONTAL_ALIGNMENT_LEFT
	)
	for child: Node in _column.get_children():
		(child as Label).horizontal_alignment = align
	var room: float = (
		UiScale.safe_rect_base().size.x
		- 2.0 * (edge + UiScale.dp(SafeAreaMargin.DEFAULT_MARGIN_DP))
	)
	_tip.custom_minimum_size.x = minf(UiScale.dp(TIP_WIDTH_DP), room)
