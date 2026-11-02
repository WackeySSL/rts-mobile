extends Control
## Developer menu: jump to a Skirmish (one per side, plan P90), the test map, the strike test, the
## art gallery, the touch probe or the perf arena. When the dev menu is not enabled (a release
## export without the `dev_menu` feature) it opens the main scene instead.
## Buttons of at least 48 dp in the safe area, in either orientation (ADR 0015 section 5): one
## column upright, two sideways, so the seven fit a phone browser held sideways; a window too short
## for them scrolls. The look is the theme's, sized in dp by `HudTheme`; the gap is dp here.

const GAP_DP: float = 12.0

@onready var _column: VBoxContainer = %Column
@onready var _grid: GridContainer = %Grid
@onready var _derrick_button: Button = %SkirmishDerrickButton
@onready var _lumen_button: Button = %SkirmishLumenButton
@onready var _test_map_button: Button = %TestMapButton
@onready var _strike_test_button: Button = %StrikeTestButton
@onready var _gallery_button: Button = %GalleryButton
@onready var _probe_button: Button = %TouchProbeButton
@onready var _arena_button: Button = %PerfArenaButton


func _ready() -> void:
	if not DevRoutes.is_enabled():
		_open_main.call_deferred()
		return
	# An entry whose scene does not exist yet stays visible but cannot be pressed.
	_gallery_button.disabled = not ResourceLoader.exists(DevRoutes.ART_GALLERY_SCENE)
	_probe_button.disabled = not ResourceLoader.exists(DevRoutes.TOUCH_PROBE_SCENE)
	_arena_button.disabled = not ResourceLoader.exists(DevRoutes.PERF_ARENA_SCENE)
	_derrick_button.pressed.connect(
		_on_skirmish_pressed.bind(DevRoutes.SKIRMISH_DERRICK, DevRoutes.DUMMY_RENEW)
	)
	_lumen_button.pressed.connect(
		_on_skirmish_pressed.bind(DevRoutes.SKIRMISH_LUMEN, DevRoutes.DUMMY_FOSSIL)
	)
	_test_map_button.pressed.connect(_on_test_map_pressed)
	_strike_test_button.pressed.connect(_on_strike_test_pressed)
	_gallery_button.pressed.connect(_on_gallery_pressed)
	_probe_button.pressed.connect(_on_probe_pressed)
	_arena_button.pressed.connect(_on_arena_pressed)
	get_viewport().size_changed.connect(_apply_dp)
	_apply_dp()


## Sizes are dp, so they follow a resize and a turn.
func _apply_dp() -> void:
	var gap: int = roundi(UiScale.dp(GAP_DP))
	_column.add_theme_constant_override("separation", gap)
	_grid.add_theme_constant_override("h_separation", gap)
	_grid.add_theme_constant_override("v_separation", gap)
	_grid.columns = 1 if HudLayout.is_portrait() else 2


func _open_main() -> void:
	DevRoutes.open(get_tree(), DevRoutes.MAIN_SCENE)


func _on_skirmish_pressed(scenario_path: String, dummy_path: String) -> void:
	DevRoutes.open_skirmish(get_tree(), scenario_path, dummy_path)


func _on_test_map_pressed() -> void:
	DevRoutes.open(get_tree(), DevRoutes.MAIN_SCENE)


func _on_strike_test_pressed() -> void:
	DevRoutes.open_main_with(get_tree(), DevRoutes.STRIKE_TEST_SCENARIO)


func _on_gallery_pressed() -> void:
	DevRoutes.open(get_tree(), DevRoutes.ART_GALLERY_SCENE)


func _on_probe_pressed() -> void:
	DevRoutes.open(get_tree(), DevRoutes.TOUCH_PROBE_SCENE)


func _on_arena_pressed() -> void:
	DevRoutes.open(get_tree(), DevRoutes.PERF_ARENA_SCENE)
