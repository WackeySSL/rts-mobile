extends GdUnitTestSuite
## The picker and the sim agree on an enemy building whose position is on a tile border (ADR 0033,
## P195d-2 review round 2). A 2x2 building stands on the corner between four tiles on both axes, so
## the cell under its position is `FixedMath.centre_side`'s, not the floor's, whenever it is past the
## middle of the map: the sim reads it so (`Targeting.sees`, the check of an ATTACK), and
## `building_targetable` must give the answer of that check in both fog directions, which a floor
## cell would not. On a 30 x 30 map, player 1's light tank (id 1) and player 2's power plants (2x2) on
## tiles 20-21 by 5-6 (position (21000, 6000): the column is 20, the row 6) and on tiles 20-21 by
## 24-25 (position (21000, 25000): the column is 20 and the row 24, the floor gives 21 and 25).

const Rig: GDScript = preload("res://tests/view/support/building_rig.gd")
## Id, centre-side cell and floor cell of the two power plants.
const PLANTS: Array[Array] = [
	[2, Vector2i(20, 6), Vector2i(21, 6)],
	[3, Vector2i(20, 24), Vector2i(21, 25)],
]

var _runner: MatchRunner
var _camera: RtsCamera
var _layer: BuildingLayer
var _snap: PickSnapshot = PickSnapshot.new()


func before_test() -> void:
	var spawns: Array[SpawnDef] = [
		Rig.spawn(1, "light_tank", 2, 2),
		Rig.spawn(2, "renew_power", 20, 5),
		Rig.spawn(2, "renew_power", 20, 24),
	]
	var scenario: ScenarioDef = Rig.scenario(spawns)
	scenario.map_size_tiles = Vector2i(30, 30)
	_runner = auto_free(Rig.runner(scenario))
	_camera = auto_free(RtsCamera.new())
	add_child(_camera)
	_layer = auto_free(BuildingLayer.new())
	_layer.runner = _runner
	add_child(_layer)
	_layer.set_process(false)
	_layer._process(0.0)


func after_test() -> void:
	CommandQueue.clear()


func test_the_plants_stand_on_borders_past_the_middle_of_the_map() -> void:
	var snap: MatchSnapshot = _runner.snapshot
	for plant: Array in PLANTS:
		var row: int = snap.index_of(plant[0])
		assert_int(snap.pos_x[row] % 1000).is_equal(0)
		assert_int(snap.pos_y[row] % 1000).is_equal(0)
		assert_int(snap.cell_of(snap.pos_x[row], snap.pos_y[row])).is_equal(
			plant[1].y * 30 + plant[1].x
		)


func test_targetable_is_what_the_sim_does_with_an_attack_in_both_fog_directions() -> void:
	for plant: Array in PLANTS:
		var id: int = plant[0]
		for seen: Vector2i in [plant[1], plant[2]]:
			_see([seen])
			_layer.fill_pick_snapshot(_snap, _camera)
			var accepted: bool = Sim._enemy_target(_runner.world, Command.attack(1, [1], id))
			var at: int = _snap.building_ids.find(id)
			assert_int(at).is_greater(-1)  # A cell of its footprint is seen: it is drawn.
			var note: String = "plant %d, seen %s" % [id, seen]
			assert_bool(accepted).override_failure_message(note).is_equal(seen == plant[1])
			assert_int(_snap.building_targetable[at]).override_failure_message(note).is_equal(
				1 if accepted else 0
			)


## Makes exactly `tiles` visible to player 1, in the snapshot the view reads and in the World the
## sim's check reads.
func _see(tiles: Array) -> void:
	Rig.see(_runner.snapshot, 1, tiles)
	_runner.world.fog.visible = _runner.snapshot.fog.visible.duplicate()
