extends GdUnitTestSuite
## The recoil of a defence's Head (plan P136, ADR 0027 sections 1, 3 and 6): a SHOT of a building
## with a head moves the Head back along the aim by the weapon's `recoil_px`, on the same time
## line as a turret's (peak at `recoil_out_ms`, home by `recoil_back_ms`), and nothing else: the
## building's node, its Body, its shadow, its frame box and its pick stay, and a defence has no hull
## to rock. A hidden enemy defence changes nothing drawn. The Redoubt's `redoubt_gun` kicks 2.5 px
## along a straight line on the screen in steps of 0.5 px, so the numbers are exact. Fixtures:
## recoil_rig.gd.

const Rig: GDScript = preload("res://tests/view/support/recoil_rig.gd")
const Buildings: GDScript = preload("res://tests/view/support/building_rig.gd")
const TOL: Vector2 = Vector2(0.001, 0.001)
## The head's distance back from its mount at the fixture's samples with `redoubt_gun` (2.5 px).
const BACK: Array[float] = [1.5, 2.5, 1.5, 1.0, 0.5, 0.5, 0.0, 0.0, 0.0]

var _runner: MatchRunner
var _layer: BuildingLayer


func before_test() -> void:
	_runner = auto_free(Rig.runner())
	_layer = _make_layer(null)


func after_test() -> void:
	CommandQueue.clear()


func test_a_shot_kicks_the_head_back_along_the_aim_and_it_returns_to_its_mount() -> void:
	var head: Sprite2D = Buildings.head(_layer, Rig.REDOUBT)
	var mount: Vector2 = head.position
	_shoot(Rig.REDOUBT, &"redoubt_gun")
	assert_int(_layer.kick_count()).is_equal(1)
	for index: int in Rig.SAMPLES.size():
		_frame(int(Rig.SAMPLES[index].x), Rig.SAMPLES[index].y)
		var note: String = "sample %d" % index
		assert_vector(head.position).override_failure_message(note).is_equal_approx(
			mount + Vector2(-BACK[index], 0.0), TOL
		)
	assert_int(_layer.life_writes()).is_equal(6)  # 150 ms repeats 125's step: no write.
	assert_int(_layer.kick_count()).is_equal(0)
	for _again: int in 5:
		_frame(40, 0.5)
	assert_int(_layer.life_writes()).is_equal(6)


func test_only_the_head_moves_not_the_building_its_body_its_shadow_or_its_pick() -> void:
	var node: Node2D = _layer.building(Rig.REDOUBT)
	var body: Sprite2D = node.get_node("Body")
	var row: int = _runner.snapshot.index_of(Rig.REDOUBT)
	var camera: RtsCamera = _layer_camera()
	var picks_before: PickSnapshot = PickSnapshot.new()
	_layer.fill_pick_snapshot(picks_before, camera)
	var box: Rect2 = _layer.frame_box(row)
	var shadow: Vector2 = Buildings.shadow(_layer, Rig.REDOUBT).position
	var at: Vector2 = node.position
	_shoot(Rig.REDOUBT, &"redoubt_gun")
	_frame(Rig.SHOT_TICK, 0.75)  # The peak.
	assert_int(_layer.life_writes()).is_greater(0)
	var picks_during: PickSnapshot = PickSnapshot.new()
	_layer.fill_pick_snapshot(picks_during, camera)
	assert_vector(node.position).is_equal(at)
	assert_vector(body.position).is_equal(Vector2.ZERO)
	assert_vector(Buildings.shadow(_layer, Rig.REDOUBT).position).is_equal(shadow)
	assert_that(_layer.frame_box(row)).is_equal(box)
	assert_array(picks_during.building_centres).is_equal(picks_before.building_centres)
	assert_array(picks_during.building_rise).is_equal(picks_before.building_rise)
	assert_array(picks_during.building_keys).is_equal(picks_before.building_keys)


func test_a_defence_has_no_hull_to_rock() -> void:
	# A weapon with a rock row rocks a vehicle's hull; a building's body never moves, and the head's
	# kick is its recoil alone.
	var life: LifeSettings = LifeSettings.new()
	life.rock_px[&"redoubt_gun"] = 3.0
	_layer = _make_layer(life)
	var head: Sprite2D = Buildings.head(_layer, Rig.REDOUBT)
	var mount: Vector2 = head.position
	_shoot(Rig.REDOUBT, &"redoubt_gun")
	_frame(Rig.SHOT_TICK, 0.75)
	assert_vector(head.position - mount).is_equal_approx(Vector2(-2.5, 0.0), TOL)
	assert_vector((_layer.building(Rig.REDOUBT).get_node("Body") as Sprite2D).position).is_equal(
		Vector2.ZERO
	)


func test_a_hidden_enemy_defence_kicks_nothing_and_a_seen_one_kicks() -> void:
	var row: int = _runner.snapshot.index_of(Rig.ENEMY_DEFENCE)
	var head: Sprite2D = Buildings.head(_layer, Rig.ENEMY_DEFENCE)
	var mount: Vector2 = head.position
	var from: Vector2i = Rig.position_of(_runner, Rig.ENEMY_DEFENCE)
	assert_bool(_layer.is_shown(row)).is_false()  # The fixture: its footprint is in the dark.
	Rig.deliver(
		_runner,
		Rig.shot(_runner, Rig.ENEMY_DEFENCE, from, Rig.EAST_ON_SCREEN, &"turret_gun"),
		Rig.SHOT_TICK
	)
	assert_int(_layer.kick_count()).is_equal(0)
	_frame(Rig.SHOT_TICK, 0.75)
	assert_int(_layer.life_writes()).is_equal(0)
	assert_vector(head.position).is_equal_approx(mount, TOL)
	Buildings.see(_runner.snapshot, 1, [Rig.DEFENCE_TILE])
	assert_bool(_layer.is_shown(row)).is_true()
	Rig.deliver(
		_runner, Rig.shot(_runner, Rig.ENEMY_DEFENCE, from, Rig.EAST_ON_SCREEN, &"turret_gun"), 40
	)
	assert_int(_layer.kick_count()).is_equal(1)
	_frame(40, 0.75)
	assert_vector(head.position - mount).is_equal_approx(Vector2(-2.5, 0.0), TOL)


func test_a_shot_of_a_vehicle_is_no_business_of_the_building_layer() -> void:
	_shoot(Rig.LIGHT, &"tank_cannon")
	_shoot(Rig.SQUAD, &"rifle")
	assert_int(_layer.kick_count()).is_equal(0)


func test_a_pause_freezes_the_head_and_reduced_keeps_it() -> void:
	var life: LifeSettings = LifeSettings.new()
	life.reduced = true
	_layer = _make_layer(life)
	var head: Sprite2D = Buildings.head(_layer, Rig.REDOUBT)
	var mount: Vector2 = head.position
	_shoot(Rig.REDOUBT, &"redoubt_gun")
	_frame(31, 0.125)  # 75 ms: 1.5 px.
	var writes: int = _layer.life_writes()
	_runner.paused = true
	for _frame_index: int in 20:
		_runner._process(0.5)
		_layer._process(0.05)
	assert_vector(head.position).is_equal_approx(mount + Vector2(-1.5, 0.0), TOL)
	assert_int(_layer.life_writes()).is_equal(writes)
	_runner.paused = false
	_frame(31, 0.5)  # 100 ms: on from where it froze, with `reduced` on.
	assert_vector(head.position).is_equal_approx(mount + Vector2(-1.0, 0.0), TOL)


func test_the_kick_of_a_head_that_is_gone_ends_with_it() -> void:
	_shoot(Rig.REDOUBT, &"redoubt_gun")
	_frame(Rig.SHOT_TICK, 0.75)
	assert_int(_layer.kick_count()).is_equal(1)
	_layer._drop(_layer._entries[Rig.REDOUBT])  # The building left the rows.
	_frame(Rig.SHOT_TICK, 0.9)
	assert_int(_layer.kick_count()).is_equal(0)


func test_the_head_turns_by_regions_while_the_kick_holds_its_position() -> void:
	# The head's frame changes by its region only: a turn in the middle of a kick leaves the offset.
	var head: Sprite2D = Buildings.head(_layer, Rig.REDOUBT)
	var mount: Vector2 = head.position
	var snap: MatchSnapshot = _runner.snapshot
	var row: int = snap.index_of(Rig.REDOUBT)
	var target_row: int = snap.index_of(Rig.ENEMY_TANK)
	_shoot(Rig.REDOUBT, &"redoubt_gun")
	_frame(Rig.SHOT_TICK, 0.75)
	snap.target_row[row] = target_row  # Now it has a target far to the south east.
	Buildings.see(snap, 1, [Rig.FAR_TILE])
	_layer._process(1.0)  # A long frame: the head turns all the way.
	assert_int(Buildings.head_frame(_layer, Rig.REDOUBT)).is_not_equal(6)
	assert_vector(head.position).is_equal_approx(mount + Vector2(-2.5, 0.0), TOL)


## A layer on the fixture runner with the settings `life` (null: the data file's).
func _make_layer(life: LifeSettings) -> BuildingLayer:
	if is_instance_valid(_layer):
		_layer.free()
	var layer: BuildingLayer = auto_free(BuildingLayer.new())
	layer.runner = _runner
	layer.life = Rig.calmed(life)
	add_child(layer)
	layer.set_process(false)
	layer._process(0.0)
	return layer


## A camera for the pick snapshot, in the tree.
func _layer_camera() -> RtsCamera:
	var camera: RtsCamera = auto_free(RtsCamera.new())
	add_child(camera)
	return camera


## Delivers a SHOT of unit `id`, straight east on the screen, at tick `tick`.
func _shoot(id: int, weapon_id: StringName, tick: int = Rig.SHOT_TICK) -> void:
	var from: Vector2i = Rig.position_of(_runner, id)
	var events: PackedInt32Array = Rig.shot(_runner, id, from, Rig.EAST_ON_SCREEN, weapon_id)
	Rig.deliver(_runner, events, tick)


func _frame(tick: int, alpha: float) -> void:
	Rig.at(_runner, tick, alpha)
	_layer._process(0.0)
