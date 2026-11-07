extends Control
## Developer menu: choose the computer's level (Easy, Normal or Hard; Normal at the start, the
## choice shown, plan P183), then jump to a Skirmish (one per side, plan P90), the test map, the
## strike test, the art gallery, the touch probe, the perf arena, the perf bases (the same scene
## with the base arena) or the perf AI (the same scene with two computer players, plan P185). When
## the dev menu is not enabled (a release export without the `dev_menu` feature) it opens the main
## scene instead. Buttons of at least 48 dp in the safe area, in either orientation (ADR 0015
## section 5): one column upright, three sideways, so the nine fit a phone browser held sideways; a
## window too short for them scrolls. The level row is three across in both orientations, its
## choice named in "Level: ..." beside the title. The look is the theme's, sized in dp by
## `HudTheme`; the gap is dp here.

const GAP_DP: float = 12.0
## The level buttons, in the order of the row: name shown and the file of `data/ai/difficulty/`.
const LEVEL_NAMES: Array[String] = ["Easy", "Normal", "Hard"]
const LEVEL_PATHS: Array[String] = [
	DevRoutes.LEVEL_EASY, DevRoutes.LEVEL_NORMAL, DevRoutes.LEVEL_HARD
]
const START_LEVEL: int = 1

## The chosen index of `LEVEL_NAMES` and `LEVEL_PATHS`.
var _level_index: int = START_LEVEL

@onready var _column: VBoxContainer = %Column
@onready var _grid: GridContainer = %Grid
@onready var _level_label: Label = %LevelLabel
@onready var _level_row: HBoxContainer = %LevelRow
@onready var _levels: Array[Button] = [%LevelEasyButton, %LevelNormalButton, %LevelHardButton]
@onready var _derrick_button: Button = %SkirmishDerrickButton
@onready var _lumen_button: Button = %SkirmishLumenButton
@onready var _test_map_button: Button = %TestMapButton
@onready var _strike_test_button: Button = %StrikeTestButton
@onready var _gallery_button: Button = %GalleryButton
@onready var _probe_button: Button = %TouchProbeButton
@onready var _arena_button: Button = %PerfArenaButton
@onready var _bases_button: Button = %PerfBasesButton
@onready var _ai_button: Button = %PerfAiButton


func _ready() -> void:
	if not DevRoutes.is_enabled():
		_open_main.call_deferred()
		return
	# An entry whose scene does not exist yet stays visible but cannot be pressed.
	_gallery_button.disabled = not ResourceLoader.exists(DevRoutes.ART_GALLERY_SCENE)
	_probe_button.disabled = not ResourceLoader.exists(DevRoutes.TOUCH_PROBE_SCENE)
	_arena_button.disabled = not ResourceLoader.exists(DevRoutes.PERF_ARENA_SCENE)
	_bases_button.disabled = (
		not ResourceLoader.exists(DevRoutes.PERF_ARENA_SCENE)
		or not ResourceLoader.exists(DevRoutes.PERF_BASES_SCENARIO)
	)
	_ai_button.disabled = (
		not ResourceLoader.exists(DevRoutes.PERF_ARENA_SCENE)
		or not ResourceLoader.exists(DevRoutes.PERF_AI_SCENARIO)
	)
	var group: ButtonGroup = ButtonGroup.new()
	for index: int in _levels.size():
		var button: Button = _levels[index]
		button.toggle_mode = true
		button.button_group = group
		button.button_pressed = index == _level_index
		button.toggled.connect(_on_level_toggled.bind(index))
	_show_level()
	_derrick_button.pressed.connect(
		_on_skirmish_pressed.bind(DevRoutes.SKIRMISH_DERRICK, DevRoutes.OPPONENT_RENEW)
	)
	_lumen_button.pressed.connect(
		_on_skirmish_pressed.bind(DevRoutes.SKIRMISH_LUMEN, DevRoutes.OPPONENT_FOSSIL)
	)
	_test_map_button.pressed.connect(_on_test_map_pressed)
	_strike_test_button.pressed.connect(_on_strike_test_pressed)
	_gallery_button.pressed.connect(_on_gallery_pressed)
	_probe_button.pressed.connect(_on_probe_pressed)
	_arena_button.pressed.connect(_on_arena_pressed)
	_bases_button.pressed.connect(_on_bases_pressed)
	_ai_button.pressed.connect(_on_ai_pressed)
	get_viewport().size_changed.connect(_apply_dp)
	_apply_dp()


## Sizes are dp, so they follow a resize and a turn.
func _apply_dp() -> void:
	var gap: int = roundi(UiScale.dp(GAP_DP))
	_column.add_theme_constant_override("separation", gap)
	_level_row.add_theme_constant_override("separation", gap)
	_grid.add_theme_constant_override("h_separation", gap)
	_grid.add_theme_constant_override("v_separation", gap)
	_grid.columns = 1 if HudLayout.is_portrait() else 3


func _open_main() -> void:
	DevRoutes.open(get_tree(), DevRoutes.MAIN_SCENE)


func _on_level_toggled(on: bool, index: int) -> void:
	if on:
		_level_index = index
		_show_level()


## The label names the choice in words, so it does not rest on the pressed look alone.
func _show_level() -> void:
	_level_label.text = "Level: %s" % LEVEL_NAMES[_level_index]


func _on_skirmish_pressed(scenario_path: String, opponent_path: String) -> void:
	DevRoutes.open_skirmish(get_tree(), scenario_path, opponent_path, LEVEL_PATHS[_level_index])


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


func _on_bases_pressed() -> void:
	DevRoutes.open_perf_bases(get_tree())


func _on_ai_pressed() -> void:
	DevRoutes.open_perf_ai(get_tree())
