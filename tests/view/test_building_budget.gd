extends GdUnitTestSuite
## The draw budget and the z bands of the buildings (plan P84, ADR 0022 sections 2 and 8, ADR 0012
## section 6): every quad of both parts is a region of the one atlas whatever the mix of types,
## owners, fog states and turret heads, so each part is one call; the forecast of the base arena's
## calls, the offline glyphs' one included, is at most 40 (a headless run has no draw-call monitor,
## so the phone card of P93c judges `draw_calls_max`); and both scenes hold the new and the moved
## layers at their z. On the base match (Rig), with the six mobile types of both players added for
## the forecast.

const Rig: GDScript = preload("res://tests/view/support/building_rig.gd")
const FogRig: GDScript = preload("res://tests/view/support/fog_rig.gd")
const BaseMatch: GDScript = preload("res://tests/core/support/base_match.gd")
const MAIN_SCENE: String = "res://scenes/main.tscn"
const ARENA_SCENE: String = "res://scenes/dev/perf_arena.tscn"
## The mobile types the base match lacks: with its harvester and rifle squad, all six.
const MORE_TYPES: Array[String] = ["light_tank", "heavy_tank", "artillery", "rocket_squad"]
const CALL_CEILING: int = 40  ## ADR 0012 section 6: at this forecast the rigs go to MultiMesh.
## The calls of the layers that are not unit rigs (ADR 0022 section 2): the ground and the ore, the
## selection rings, the base parts, the fog, the roof parts and their heads, the bars, the offline
## glyphs (P89), the projectiles and the effects (up to two).
const OTHER_CALLS: Dictionary[StringName, int] = {
	&"ground": 1,
	&"ore": 1,
	&"rings": 1,
	&"base_parts": 1,
	&"fog": 1,
	&"roof_parts": 1,
	&"bars": 1,
	&"glyphs": 1,
	&"projectiles": 1,
	&"effects": 2,
}

var _runner: MatchRunner
var _units: UnitLayer
var _buildings: BuildingLayer
var _roofs: BuildingRoofLayer


func before_test() -> void:
	_runner = auto_free(Rig.runner(_arena_scenario()))
	_units = auto_free(UnitLayer.new())
	_units.runner = _runner
	add_child(_units)
	_units.set_process(false)
	_buildings = auto_free(BuildingLayer.new())
	_buildings.runner = _runner
	_buildings.unit_layer = _units
	add_child(_buildings)
	_buildings.set_process(false)
	_roofs = auto_free(BuildingRoofLayer.new())
	_roofs.buildings = _buildings
	add_child(_roofs)
	_roofs.set_process(false)


func after_test() -> void:
	CommandQueue.clear()


func test_the_forecast_of_calls_for_a_base_arena_like_snapshot_is_at_most_40() -> void:
	_buildings.reveal_enemies = true  # Every building of both players, the heaviest case.
	_units._process(0.0)
	await _frame()
	# Each unit layer draws at one z per batch group (ADR 0012 section 6): the rig sprites' z.
	var batches: Dictionary[String, bool] = {}
	for rig: Node in _units.get_children():
		for sprite: Node in rig.get_children():
			batches["%s@%d" % [sprite.name, (sprite as Sprite2D).z_index]] = true
	var by_layer: Dictionary[String, int] = {"Hull": 0, "Team": 0, "Turret": 0}
	for key: String in batches:
		by_layer[key.get_slice("@", 0)] += 1
	# Six mobile types, two owners, three types with a turret.
	assert_dict(by_layer).is_equal({"Hull": 6, "Team": 12, "Turret": 3})
	# Both building parts are drawn, each from the one atlas (the next test pins that).
	assert_int(_buildings.drawn_quads()).is_equal(2 * Rig.BUILDINGS)
	assert_int(_roofs.drawn_quads()).is_equal(2 * Rig.BUILDINGS + 2)
	var calls: int = 21
	for name: StringName in OTHER_CALLS:
		calls += OTHER_CALLS[name]
	assert_int(calls).is_equal(32)
	assert_int(calls).is_less_equal(CALL_CEILING)


func test_each_part_draws_from_the_one_atlas_whatever_the_mix_of_types_owners_states_and_heads(
) -> void:
	_buildings.sync()
	var snap: MatchSnapshot = _runner.snapshot
	# The player sees nothing but one cell of the enemy turret and one of its Headquarters: all six
	# own buildings are drawn and dimmed, two enemy ones are drawn and white.
	FogRig.blind(snap, 1)
	FogRig.flip(snap, 1, [Vector2i(30, 5), Vector2i(37, 4)] as Array[Vector2i], true)
	await _frame()
	var list: Array[Dictionary] = Rig.buildings()
	var atlas: RuntimeAtlas = _buildings.atlas()
	var image: Rect2 = Rect2(Vector2.ZERO, Vector2(atlas.image().get_size()))
	var owners: Dictionary[int, bool] = {}
	var dims: Dictionary[bool, bool] = {}
	var heads: int = 0
	for roof: bool in [false, true]:
		for entry: int in _buildings.painted(roof):
			var b: int = entry >> 2
			var layer: int = entry & 3
			var key: StringName = StringName(
				"%s_%s" % [list[b][&"id"], BuildingLayer.LAYER_FILES[layer]]
			)
			var source: Rect2 = (
				_buildings.part_src(b, layer, roof) if layer != 2 else Rect2(atlas.region(key))
			)
			assert_bool(atlas.has_region(key)).override_failure_message(str(key)).is_true()
			(
				assert_bool(Rect2(atlas.region(key)).encloses(source))
				. override_failure_message("%s roof %s" % [key, roof])
				. is_true()
			)
			assert_bool(image.encloses(source)).is_true()
			owners[list[b][&"owner"]] = true
			dims[_buildings.part_color(b, BuildingLayer.HULL, roof) != Color.WHITE] = true
			if layer == BuildingLayer.TURRET:
				heads += 1
	assert_array(owners.keys()).is_equal([1, 2])
	assert_array(dims.keys()).contains_exactly_in_any_order([true, false])  # Dim and white roofs.
	assert_int(heads).is_equal(2)  # The own turret's and the visible enemy one's.
	assert_int(_buildings.drawn_quads()).is_equal(2 * 8)
	assert_int(_roofs.drawn_quads()).is_equal(2 * 8 + 2)


func test_both_scenes_hold_the_new_and_the_moved_layers_at_their_z() -> void:
	for path: String in [MAIN_SCENE, ARENA_SCENE]:
		var scene: PackedScene = load(path)
		var buildings: Dictionary = _properties(scene, "BuildingLayer")
		var roofs: Dictionary = _properties(scene, "BuildingRoofLayer")
		var fog: Dictionary = _properties(scene, "FogLayer")
		var bars: Dictionary = _properties(scene, "HealthBarLayer")
		var units: Dictionary = _properties(scene, "UnitLayer")
		var zs: Array[int] = []
		for layer: Dictionary in [buildings, roofs, fog, bars]:
			assert_bool(layer.get("z_as_relative", true)).override_failure_message(path).is_false()
			zs.append(layer.get("z_index", 0))
		assert_array(zs).override_failure_message(path).is_equal([2, 111, 110, 112])
		# Over the selection rings and under every unit band; the fog over every unit band and
		# under the roofs; the bars over the roofs and under the projectiles.
		assert_int(UnitLayer.Z_RING).is_less(zs[0])
		assert_int(zs[0]).is_less(UnitLayer.Z_FIRST[0])
		assert_int(UnitLayer.Z_LAST[2]).is_less(zs[2])
		assert_int(zs[2]).is_less(zs[1])
		assert_int(zs[1]).is_less(zs[3])
		assert_int(zs[3]).is_less(_properties(scene, "ProjectileLayer").get("z_index", 0))
		# The scripts and the wiring: one runner, the unit layer's palette, the fog layer's
		# explored alpha, and the roofs read the base layer's list.
		assert_str(buildings["script"].resource_path).is_equal("res://game/view/BuildingLayer.gd")
		assert_str(roofs["script"].resource_path).is_equal("res://game/view/BuildingRoofLayer.gd")
		assert_that(buildings["runner"]).is_equal(NodePath("../MatchRunner"))
		assert_that(buildings["unit_layer"]).is_equal(NodePath("../UnitLayer"))
		assert_that(buildings["fog_layer"]).is_equal(NodePath("../FogLayer"))
		assert_that(roofs["buildings"]).is_equal(NodePath("../BuildingLayer"))
		# Only the perf arena shows every enemy, as for the unit layer.
		assert_bool(buildings.get("reveal_enemies", false)).is_equal(
			units.get("reveal_enemies", false)
		)
		assert_bool(buildings.get("reveal_enemies", false)).is_equal(path == ARENA_SCENE)


## The base match with the four mobile types it lacks added for both players, in a row at the
## south of each base (tiles (4, 21), (6, 21), (8, 21) and (10, 21), player 2 mirrored). A type's
## index is the order of its first spawn, and a z band holds ten of them (`UnitLayer.Z_TYPES`)
## while this roster has twelve types, so the mobile types are spawned first: all six get a band
## group of their own, as the real base arena must (see the notes of the P84 PR).
func _arena_scenario() -> ScenarioDef:
	var scenario: ScenarioDef = BaseMatch.scenario()
	for owner: int in [1, 2]:
		for index: int in MORE_TYPES.size():
			var spawn: SpawnDef = SpawnDef.new()
			spawn.owner = owner
			spawn.unit = load("%s%s.tres" % [BaseMatch.UNIT_DIR, MORE_TYPES[index]]) as UnitDef
			spawn.count = 1
			var x: int = 4 + 2 * index
			spawn.origin_tile = Vector2i(x if owner == 1 else BaseMatch.COLS - x - 1, 21)
			scenario.spawns.append(spawn)
	var mobile: Array[SpawnDef] = []
	var fixed: Array[SpawnDef] = []
	for spawn: SpawnDef in scenario.spawns:
		(fixed if spawn.unit is BuildingDef else mobile).append(spawn)
	scenario.spawns.assign(mobile + fixed)
	return scenario


## The properties a scene file sets on its node `node_name`, read from the PackedScene's state, so
## that nothing is instantiated.
func _properties(scene: PackedScene, node_name: String) -> Dictionary:
	var state: SceneState = scene.get_state()
	var found: Dictionary = {}
	for node: int in state.get_node_count():
		if state.get_node_name(node) == node_name:
			for index: int in state.get_node_property_count(node):
				found[state.get_node_property_name(node, index)] = state.get_node_property_value(
					node, index
				)
	return found


## One frame of the three layers, in the scene's order, then the engine's own, which draws.
func _frame() -> void:
	_buildings._process(0.0)
	_roofs._process(0.0)
	await await_idle_frame()
