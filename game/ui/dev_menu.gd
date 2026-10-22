extends Control
## Developer menu: jump to the test map, the art gallery, the touch probe or the perf arena. When
## the dev menu is not enabled (a release export without the `dev_menu` feature) it opens the main
## scene instead.
## One column of buttons that are at least 56 dp tall, in the safe area, in either orientation
## (ADR 0015 section 5). A window too short for the column (a phone browser held sideways) scrolls
## it. The look is the theme's, sized in dp by the `HudTheme` node; the gap is dp here.

const GAP_DP: float = 12.0

@onready var _column: VBoxContainer = %Column
@onready var _test_map_button: Button = %TestMapButton
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
	_test_map_button.pressed.connect(_on_test_map_pressed)
	_gallery_button.pressed.connect(_on_gallery_pressed)
	_probe_button.pressed.connect(_on_probe_pressed)
	_arena_button.pressed.connect(_on_arena_pressed)
	get_viewport().size_changed.connect(_apply_dp)
	_apply_dp()


## Sizes are dp, so they follow a resize and a turn.
func _apply_dp() -> void:
	_column.add_theme_constant_override("separation", roundi(UiScale.dp(GAP_DP)))


func _open_main() -> void:
	DevRoutes.open(get_tree(), DevRoutes.MAIN_SCENE)


func _on_test_map_pressed() -> void:
	DevRoutes.open(get_tree(), DevRoutes.MAIN_SCENE)


func _on_gallery_pressed() -> void:
	DevRoutes.open(get_tree(), DevRoutes.ART_GALLERY_SCENE)


func _on_probe_pressed() -> void:
	DevRoutes.open(get_tree(), DevRoutes.TOUCH_PROBE_SCENE)


func _on_arena_pressed() -> void:
	DevRoutes.open(get_tree(), DevRoutes.PERF_ARENA_SCENE)
