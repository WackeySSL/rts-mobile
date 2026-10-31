class_name DevRoutes
extends RefCounted
## Scene paths and gating for the developer-only screens (dev menu, art gallery, touch probe, perf
## arena) and the main scene's scenario for the "Strike test" route.
##
## The dev menu is available in debug builds and in any export that sets the custom feature
## `dev_menu` (the Web preview preset does). Store presets must not set it.

const MAIN_SCENE: String = "res://scenes/main.tscn"
const DEV_MENU_SCENE: String = "res://scenes/dev/dev_menu.tscn"
const ART_GALLERY_SCENE: String = "res://scenes/dev/art_gallery.tscn"
const TOUCH_PROBE_SCENE: String = "res://scenes/dev/touch_probe.tscn"
const PERF_ARENA_SCENE: String = "res://scenes/dev/perf_arena.tscn"
## The "Strike test" scenario (plan P112d): the local player owns a Deep Bore and a Blackout Array
## with a short charge, facing a still enemy base, so the phone preview can fire both strikes.
const STRIKE_TEST_SCENARIO: String = "res://data/scenarios/dev_strikes.tres"


static func is_enabled() -> bool:
	return OS.is_debug_build() or OS.has_feature("dev_menu")


## Changes to `scene_path`. Reports a missing scene with push_error instead of crashing.
static func open(tree: SceneTree, scene_path: String) -> Error:
	if not ResourceLoader.exists(scene_path):
		push_error("DevRoutes: scene not found: %s" % scene_path)
		return ERR_FILE_NOT_FOUND
	return tree.change_scene_to_file(scene_path)


## Changes to the main scene with `scenario_path` in the MatchRunner in place of the scene's own
## scenario (Test map's). The runner starts its match in its own `_ready`, so the scenario is set on
## the new scene before it enters the tree. Reports a missing scenario with push_error instead of
## crashing.
static func open_main_with(tree: SceneTree, scenario_path: String) -> Error:
	var scenario: ScenarioDef = (
		load(scenario_path) as ScenarioDef if ResourceLoader.exists(scenario_path) else null
	)
	if scenario == null:
		push_error("DevRoutes: scenario not found: %s" % scenario_path)
		return ERR_FILE_NOT_FOUND
	var main: Node = (load(MAIN_SCENE) as PackedScene).instantiate()
	(main.get_node("MatchRunner") as MatchRunner).scenario = scenario
	return tree.change_scene_to_node(main)
