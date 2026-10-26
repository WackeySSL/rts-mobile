extends GdUnitTestSuite
## The building layers inside the real main scene (plan P84, ADR 0022): with the base match in the
## runner's place, the scene draws player 1's six buildings and no rig for any of them, at every
## screen size of ADR 0015 section 6 held both ways, and the layers ask for no redraw when the
## window turns or changes size (`plan_version` stays: they live in world space and read no screen
## size; the engine itself draws a canvas item again on a resize, which is not counted here). The
## scene's own nodes, wiring and z are in test_building_budget.gd. The window is reset after the
## suite.

const Rig: GDScript = preload("res://tests/view/support/building_rig.gd")
const BaseMatch: GDScript = preload("res://tests/core/support/base_match.gd")
const ScreenSizes: GDScript = preload("res://tests/support/screen_sizes.gd")
const MAIN_SCENE: String = "res://scenes/main.tscn"
const SIZES: Array[Vector2i] = ScreenSizes.ALL

var _window_size_before: Vector2i


func before() -> void:
	_window_size_before = get_window().size


func after() -> void:
	get_window().size = _window_size_before


func test_the_main_scene_draws_the_own_buildings_of_the_base_match_at_every_screen_size() -> void:
	var main: Node2D = auto_free((load(MAIN_SCENE) as PackedScene).instantiate())
	(main.get_node("MatchRunner") as MatchRunner).scenario = BaseMatch.scenario()
	get_window().size = SIZES[0]
	add_child(main)
	await await_idle_frame()
	await await_idle_frame()
	var buildings: BuildingLayer = main.get_node("BuildingLayer")
	var roofs: BuildingRoofLayer = main.get_node("BuildingRoofLayer")
	var units: UnitLayer = main.get_node("UnitLayer")
	assert_int(buildings.building_count()).is_equal(Rig.BUILDINGS)
	assert_int(units.rig_count()).is_equal(10)  # The harvesters and the squads, no building.
	var version: int = buildings.plan_version()
	for size: Vector2i in SIZES:
		get_window().size = size
		await await_idle_frame()
		await await_idle_frame()
		var label: String = str(size)
		for b: int in Rig.BUILDINGS:  # The own six, which stand in sight, and none of the enemy.
			assert_bool(buildings.is_shown(b)).override_failure_message(label).is_equal(
				b < Rig.OWN_BUILDINGS
			)
		assert_int(buildings.drawn_quads()).override_failure_message(label).is_equal(12)
		assert_int(roofs.drawn_quads()).override_failure_message(label).is_equal(13)  # And a head.
		assert_int(buildings.plan_version()).override_failure_message(label).is_equal(version)
