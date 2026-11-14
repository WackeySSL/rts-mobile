extends GdUnitTestSuite
## Taps on aircraft (plan P244, ADR 0036 section 12) on a real `AirLayer`, `UnitLayer` and
## `PlayerController`, without the main scene, at the six sizes of ScreenSizes.ALL: an aircraft is
## picked at its lifted centre within at least 24 dp, wins an overlapping tap against a ground unit
## beneath it but only within its pick rank, and a ground unit beneath stays tappable at its own
## point; a tap on an enemy none of the selected units can hit sends nothing, shakes the mark and
## keeps the selection; a mixed selection attacks with the rows that can hit; Home sends one REPAIR
## to each airfield the selected aircraft are homed at.
## Own: light tank 1 and fighter 2 on one tile, transport 5, bomber 6. Enemy: renew tank 3, renew
## fighter 4. A fighter's gun hits air only and a bomber's ground only.

const MenuRig: GDScript = preload("res://tests/support/menu_rig.gd")
const Air: GDScript = preload("res://tests/view/support/air_rig.gd")
const Buildings: GDScript = preload("res://tests/view/support/building_rig.gd")
const Sized: GDScript = preload("res://tests/view/support/sized_camera.gd")
const ScreenSizes: GDScript = preload("res://tests/support/screen_sizes.gd")
const ZOOMS: Array[float] = [0.75, 1.0, 1.5]
const TANK: int = 1
const FIGHTER: int = 2
const ENEMY_TANK: int = 3
const ENEMY_FIGHTER: int = 4
const TRANSPORT: int = 5
const BOMBER: int = 6
const SPAWNS: Array[Array] = [
	[1, "light_tank", 8, 8],
	[1, "fossil_fighter", 8, 8],
	[2, "renew_tank", 14, 8],
	[2, "renew_fighter", 14, 14],
	[1, "fossil_transport", 20, 8],
	[1, "fossil_bomber", 2, 2],
]

var _runner: MatchRunner
var _air: AirLayer
var _units: UnitLayer
var _camera: RtsCamera
var _markers: MoveMarkerLayer
var _controller: PlayerController
var _sent: Array[Command] = []


func before_test() -> void:
	MenuRig.begin()  # The haptic gate reads the prefs file of the suite's own.
	var spawns: Array[SpawnDef] = []
	for entry: Array in SPAWNS:
		spawns.append(Buildings.spawn(entry[0], entry[1], entry[2], entry[3]))
	_runner = auto_free(Buildings.runner(Buildings.scenario(spawns)))
	_camera = auto_free(Sized.new())
	add_child(_camera)
	_air = auto_free(Air.layer(self, _runner))
	_air.reveal_enemies = true
	_units = auto_free(UnitLayer.new())
	_units.runner = _runner
	_units.camera = _camera
	_units.reveal_enemies = true
	add_child(_units)
	_units.set_process(false)
	_markers = auto_free(MoveMarkerLayer.new())
	add_child(_markers)
	_controller = auto_free(PlayerController.new())
	_controller.runner = _runner
	_controller.unit_layer = _units
	_controller.air_layer = _air
	_controller.camera = _camera
	_controller.marker_layer = _markers
	_controller.command_sink = func(command: Command) -> void: _sent.append(command)
	_controller.vibrate = func(_ms: int) -> void: pass
	add_child(_controller)
	_sent.clear()
	_air._process(0.0)


func after_test() -> void:
	MenuRig.end()
	UiScale.clear_override()
	CommandQueue.clear()


func test_a_flyer_is_picked_at_its_lifted_centre_within_24_dp_at_every_size_and_zoom() -> void:
	for size: Vector2i in ScreenSizes.ALL:
		for zoom: float in ZOOMS:
			_zoom(size, zoom)
			_assert_radius("%s at zoom %s" % [size, zoom])


func _assert_radius(why: String) -> void:
	var fighter: Vector2 = _hull(FIGHTER)
	var reach: float = UiScale.dp(24.0)
	var snap: PickSnapshot = _snapshot()
	var row: int = _runner.snapshot.index_of(FIGHTER)
	assert_float(snap.radius_px[row]).override_failure_message(why).is_greater_equal(reach)
	assert_int(snap.pickable[row]).is_equal(1)
	assert_bool(snap.is_flyer(row)).is_true()
	var radius: float = snap.radius_px[row]
	_controller.selection.clear()
	_tap(fighter + Vector2(radius * 0.95, 0.0))
	assert_array(_selected()).override_failure_message(why).is_equal([FIGHTER])
	_controller.selection.clear()
	_tap(fighter + Vector2(0.0, -reach * 0.95))
	assert_array(_selected()).override_failure_message(why).is_equal([FIGHTER])
	_controller.selection.clear()
	_tap(fighter + Vector2(radius * 1.2, 0.0))
	assert_array(_selected()).override_failure_message(why).is_empty()


func test_an_enemy_flyer_the_fog_hides_cannot_be_picked_and_a_falling_one_either() -> void:
	_size(ScreenSizes.ALL[0])
	_air.reveal_enemies = false
	_units.reveal_enemies = false
	var tiles: Array = []
	for y: int in 32:
		for x: int in 32:
			if Vector2i(x, y) != Vector2i(14, 14):  # Everything but the enemy fighter's tile.
				tiles.append(Vector2i(x, y))
	Buildings.see(_runner.snapshot, 1, tiles)
	_air._process(0.0)
	var enemy: int = _runner.snapshot.index_of(ENEMY_FIGHTER)
	var hull: Vector2 = _hull(ENEMY_FIGHTER)
	assert_int(_snapshot().pickable[enemy]).is_equal(0)
	_controller.selection.set_ids(PackedInt32Array([TANK]))
	_sent.clear()
	_tap(hull)  # No enemy there to the player: a ground tap, a MOVE.
	assert_int(_sent[0].type).is_equal(Command.Type.MOVE)
	Buildings.see(_runner.snapshot, 1, [Vector2i(14, 14), Vector2i(8, 8)])  # Seen now.
	_air._process(0.0)
	assert_int(_snapshot().pickable[enemy]).is_equal(1)
	# The own fighter dies in sight: it falls, and a falling flyer takes no tap.
	var snap: MatchSnapshot = _runner.snapshot
	var events: PackedInt32Array = PackedInt32Array()
	events.resize(World.EVENT_STRIDE)
	events[0] = World.Event.DIED
	events[1] = FIGHTER
	events[2] = snap.pos_x[snap.index_of(FIGHTER)]
	events[3] = snap.pos_y[snap.index_of(FIGHTER)]
	snap.events = events
	_air._on_ticked(snap.tick)
	assert_int(_air.falling_count()).is_equal(1)
	assert_int(_snapshot().pickable[snap.index_of(FIGHTER)]).is_equal(0)


func test_the_flyer_wins_where_its_disc_and_the_tank_beneath_overlap_and_the_tank_stays_tappable(
) -> void:
	for size: Vector2i in ScreenSizes.ALL:
		_size(size)
		var why: String = str(size)
		_air.rig_of(FIGHTER).lift = 200.0  # Well clear of the tank's disc, whatever the size.
		var ground: Vector2 = _centre(TANK)
		var hull: Vector2 = _hull(FIGHTER)
		assert_float(ground.distance_to(hull)).override_failure_message(why).is_greater(
			UiScale.dp(24.0) * 1.2
		)
		_controller.selection.clear()
		_tap(ground)  # The tank's own point, outside the hull's disc.
		assert_array(_selected()).override_failure_message(why).is_equal([TANK])
		_controller.selection.clear()
		_tap(hull)
		assert_array(_selected()).override_failure_message(why).is_equal([FIGHTER])


func test_a_tap_where_two_discs_overlap_goes_to_the_flyer_not_the_closer_tank() -> void:
	var snap: PickSnapshot = PickSnapshot.new()
	snap.ids = PackedInt32Array([1, 2])
	snap.owners = PackedInt32Array([1, 1])
	snap.type_index = PackedInt32Array([0, 1])
	snap.screen_pos = PackedVector2Array([Vector2(100, 100), Vector2(100, 70)])
	snap.radius_px = PackedFloat32Array([40.0, 40.0])
	snap.flyer = PackedByteArray([0, 1])
	assert_int(Picker.pick(snap, Vector2(100, 98), 1, false)).is_equal(1)  # Nearer the tank.
	assert_int(Picker.pick(snap, Vector2(100, 130), 1, false)).is_equal(0)  # Only the tank's disc.
	# Within one rank only: an enemy ground unit beats an own flyer when units are selected.
	snap.owners = PackedInt32Array([2, 1])
	assert_int(Picker.pick(snap, Vector2(100, 98), 1, true)).is_equal(0)
	assert_int(Picker.pick(snap, Vector2(100, 98), 1, false)).is_equal(1)  # No enemy without one.


func test_a_box_and_a_double_tap_reach_the_unit_beneath_a_flyer() -> void:
	_size(ScreenSizes.ALL[0])
	var snap: PickSnapshot = _snapshot()
	var found: PackedInt32Array = PackedInt32Array()
	_air.rig_of(FIGHTER).lift = 200.0
	snap = _snapshot()
	var box: Rect2 = Rect2(_centre(TANK) - Vector2(8, 8), Vector2(16, 16))
	Picker.own_in_rect(snap, box, 1, found)
	assert_array(found).is_equal([TANK])  # The flyer's centre is outside, up in the air.
	var wide: Rect2 = Rect2(_hull(FIGHTER) - Vector2(8, 8), Vector2(16, 16))
	Picker.own_in_rect(snap, wide, 1, found)
	assert_array(found).is_equal([FIGHTER])
	_controller.selection.set_ids(PackedInt32Array([BOMBER]))
	_controller.handle_gesture(_gesture(GestureEvent.Kind.DOUBLE_TAP, _hull(FIGHTER)))
	assert_array(_selected()).is_equal([FIGHTER])  # The only fighter of its type.


func test_an_own_transport_is_picked_by_a_tap_on_its_lifted_hull() -> void:
	for size: Vector2i in ScreenSizes.ALL:
		_size(size)
		_controller.selection.set_ids(PackedInt32Array([BOMBER]))
		_tap(_hull(TRANSPORT))
		assert_array(_selected()).override_failure_message(str(size)).is_equal([TRANSPORT])


func test_a_fighter_alone_taps_an_enemy_tank_it_cannot_hit_sends_nothing_and_keeps_the_selection(
) -> void:
	for size: Vector2i in ScreenSizes.ALL:
		_size(size)
		_sent.clear()
		var before: int = _controller.refusals
		for old: MoveMarkerLayer.Mark in _markers.get_children():
			old.visible = false  # Only this tap's mark counts.
		_controller.selection.set_ids(PackedInt32Array([FIGHTER]))
		_tap(_ground(ENEMY_TANK))
		var why: String = str(size)
		assert_array(_sent).override_failure_message(why).is_empty()
		assert_array(_selected()).override_failure_message(why).is_equal([FIGHTER])
		assert_int(_controller.refusals).is_equal(before + 1)
		assert_int(_markers.active_count()).is_greater(0)
		var shaking: int = 0
		for mark: MoveMarkerLayer.Mark in _markers.get_children():
			shaking += 1 if mark.visible and mark.shake else 0
		assert_int(shaking).override_failure_message(why).is_equal(1)  # A shaking diamond.


func test_a_mixed_selection_attacks_with_the_rows_that_can_hit() -> void:
	_size(ScreenSizes.ALL[0])
	_controller.selection.set_ids(PackedInt32Array([TANK, FIGHTER, BOMBER]))
	_tap(_ground(ENEMY_TANK))
	assert_int(_sent.size()).is_equal(1)
	assert_int(_sent[0].type).is_equal(Command.Type.ATTACK)
	assert_array(_sent[0].unit_ids).is_equal([TANK, BOMBER])  # The fighter's gun is air only.
	assert_int(_sent[0].target_id).is_equal(ENEMY_TANK)
	_sent.clear()
	_controller.selection.set_ids(PackedInt32Array([TANK, FIGHTER, BOMBER]))
	_tap(_hull(ENEMY_FIGHTER))
	assert_int(_sent.size()).is_equal(1)
	assert_array(_sent[0].unit_ids).is_equal([FIGHTER])  # Torchjet hits AIR.
	assert_int(_sent[0].target_id).is_equal(ENEMY_FIGHTER)
	assert_array(_selected()).is_equal([TANK, FIGHTER, BOMBER])


func test_home_sends_one_repair_to_each_airfield_the_selected_aircraft_are_homed_at() -> void:
	var snap: MatchSnapshot = _runner.snapshot
	var fighter: int = snap.index_of(FIGHTER)
	var bomber: int = snap.index_of(BOMBER)
	snap.home[fighter] = TANK  # Any own row stands in for an airfield here.
	snap.home[bomber] = TRANSPORT
	_controller.selection.set_ids(PackedInt32Array([TANK, FIGHTER, BOMBER]))
	assert_bool(_controller.home()).is_true()
	assert_int(_sent.size()).is_equal(2)
	assert_int(_sent[0].type).is_equal(Command.Type.REPAIR)
	assert_int(_sent[0].target_id).is_equal(TANK)  # The airfields in ascending id order.
	assert_array(_sent[0].unit_ids).is_equal([FIGHTER])
	assert_int(_sent[1].target_id).is_equal(TRANSPORT)
	assert_array(_sent[1].unit_ids).is_equal([BOMBER])
	snap.home[bomber] = ENEMY_TANK  # An airfield that is not ours is left out.
	_sent.clear()
	assert_bool(_controller.home()).is_true()
	assert_int(_sent.size()).is_equal(1)
	_sent.clear()
	snap.home[fighter] = 0
	snap.home[bomber] = 0
	assert_bool(_controller.home()).is_false()  # No airfield: left out, nothing sent.
	assert_array(_sent).is_empty()


## The size and the camera's zoom.
func _zoom(size: Vector2i, zoom: float) -> void:
	_camera.zoom = Vector2(zoom, zoom)
	_size(size)


## Metrics of the size: a 420 dpi phone, stretched as the engine does in that orientation.
func _size(size: Vector2i) -> void:
	var stretch: float = (
		minf(size.x / 1280.0, size.y / 720.0)
		if size.x >= size.y
		else minf(size.x / 720.0, size.y / 1280.0)
	)
	UiScale.set_override(UiMetrics.create("Android", 420, 1.0, stretch, size, Rect2i()))
	(_camera as Object).set(&"screen", Vector2(size))
	_air._process(0.0)


func _snapshot() -> PickSnapshot:
	var snap: PickSnapshot = PickSnapshot.new()
	_units.fill_pick_snapshot(snap, UiScale.dp(24.0))
	_air.fill_pick_snapshot(snap, _camera, UiScale.dp(24.0))
	return snap


## Where unit `id` stands on the ground, on the screen.
func _ground(id: int) -> Vector2:
	var snap: MatchSnapshot = _runner.snapshot
	var row: int = snap.index_of(id)
	var rig: AirLayer.Rig = _air.rig_of(id)
	var at: Vector2 = rig.global_position if rig != null else _units.rig(row).global_position
	return _camera.world_to_screen(at)


## The pick centre of unit `id` (a ground unit's is raised by half its frame), on the screen.
func _centre(id: int) -> Vector2:
	var snap: PickSnapshot = _snapshot()
	return snap.screen_pos[_runner.snapshot.index_of(id)]


## Where the hull of flyer `id` is drawn (the lifted centre), on the screen.
func _hull(id: int) -> Vector2:
	var rig: AirLayer.Rig = _air.rig_of(id)
	return _camera.world_to_screen(rig.global_position - Vector2(0.0, rig.lift))


func _tap(at: Vector2) -> void:
	_controller.handle_gesture(_gesture(GestureEvent.Kind.TAP, at))


func _gesture(kind: int, at: Vector2) -> GestureEvent:
	var event: GestureEvent = GestureEvent.new(kind)
	event.position = at
	return event


func _selected() -> Array[int]:
	var ids: Array[int] = []
	ids.append_array(_controller.selection.selected)
	return ids
