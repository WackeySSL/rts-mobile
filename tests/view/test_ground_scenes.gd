extends GdUnitTestSuite
## Both scenes hold the ground (plan P116, ADR 0023 section 2's z table): a `GroundLayer` node of
## type TileMapLayer straight after `MapView` and before the sorted world, at z 0, wired to the
## runner, which `MapView` names as its ground so that it stops drawing its bake under it. The layer
## builds its field layer and props itself, so the scene lists no child of it. The scene files are
## read, not run, for the layout; the perf arena is also run, for its ground to fill.

const MenuRig: GDScript = preload("res://tests/support/menu_rig.gd")
const SCENES: Array[String] = ["res://scenes/main.tscn", "res://scenes/dev/perf_arena.tscn"]
const ARENA: String = "res://scenes/dev/perf_arena.tscn"
const GROUND_SCRIPT: String = "res://game/view/GroundLayer.gd"


## The menu's slide is off for the test (tests/support/menu_rig.gd).
func before_test() -> void:
	MenuRig.begin()


## The slide override is static state: leaving it changes every later suite.
func after_test() -> void:
	MenuRig.end()


func test_both_scenes_hold_a_ground_layer_after_the_map_view_and_before_the_sorted_world() -> void:
	for path: String in SCENES:
		var state: SceneState = (load(path) as PackedScene).get_state()
		var names: Array[String] = _root_children(state)
		var at: int = names.find("GroundLayer")
		assert_int(at).override_failure_message(path).is_greater(0)
		assert_int(at).override_failure_message(path).is_equal(names.find("MapView") + 1)
		assert_int(at).override_failure_message(path).is_less(names.find("WorldSort"))
		assert_str(_type_of(state, "GroundLayer")).is_equal("TileMapLayer")
		var script: Script = _value(state, "GroundLayer", &"script") as Script
		assert_str(script.resource_path).is_equal(GROUND_SCRIPT)
		assert_that(_value(state, "GroundLayer", &"runner")).is_equal(NodePath("../MatchRunner"))
		assert_that(_value(state, "MapView", &"ground")).is_equal(NodePath("../GroundLayer"))
		assert_int(int(_value(state, "GroundLayer", &"z_index", 0))).is_equal(0)
		assert_int(_children_of(state, "GroundLayer")).is_equal(0)  # Its layers are made in code.


func test_the_perf_arena_fills_its_ground_and_its_map_view_stops_drawing() -> void:
	var arena: Node2D = auto_free((load(ARENA) as PackedScene).instantiate())
	add_child(arena)
	for _i: int in 3:
		await await_idle_frame()
	var ground: GroundLayer = arena.get_node("GroundLayer")
	var view: MapView = arena.get_node("MapView")
	var runner: MatchRunner = arena.get_node("MatchRunner")
	var cells: int = runner.snapshot.map_cols * runner.snapshot.map_rows
	assert_int(cells).is_greater(0)
	assert_int(ground.write_count()).is_equal(cells)
	assert_bool(ground.covers_map()).is_true()
	assert_object(view.ground).is_same(ground)
	assert_int(view.draw_count()).is_equal(0)


func _root_children(state: SceneState) -> Array[String]:
	var names: Array[String] = []
	for index: int in state.get_node_count():
		if str(state.get_node_path(index, true)) == ".":  # Its parent is the scene's root.
			names.append(state.get_node_name(index))
	return names


func _children_of(state: SceneState, node_name: String) -> int:
	var count: int = 0
	for index: int in state.get_node_count():
		if str(state.get_node_path(index, true)) == node_name:
			count += 1
	return count


func _type_of(state: SceneState, node_name: String) -> String:
	for index: int in state.get_node_count():
		if state.get_node_name(index) == node_name:
			return state.get_node_type(index)
	return ""


func _value(
	state: SceneState, node_name: String, prop: StringName, fallback: Variant = null
) -> Variant:
	for index: int in state.get_node_count():
		if state.get_node_name(index) != node_name:
			continue
		for at: int in state.get_node_property_count(index):
			if state.get_node_property_name(index, at) == prop:
				return state.get_node_property_value(index, at)
	return fallback
