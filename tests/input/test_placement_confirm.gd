extends GdUnitTestSuite
## What ends placement mode and what it sends (plan P86, ADR 0019 section 2), in the main scene on
## the 6-inch phone: the check mark (`confirm`) sends exactly one PLACE for the ghost's origin tile
## and holds the ghost pending, and only while the ghost fits (what the sim answers is
## test_placement_pending.gd's); the X (`cancel`) sends nothing; a new match and aiming a strike end
## the mode; each tick judges the ghost again (a tank rolls onto it, a new match). A PLACE from the
## controller runs in the sim and builds a 1x1, a 2x2 and a 3x3 structure of either faction, for
## either player, where the ghost stood. A turn of the phone during a ghost drag keeps the tile and
## makes no Command: the state hash of the run, the tile, the camera's centre and the queue are
## those of a run with no turn.

const MenuRig: GDScript = preload("res://tests/support/menu_rig.gd")
const Rig: GDScript = preload("res://tests/input/support/placement_rig.gd")
const TouchEvents: GDScript = preload("res://tests/support/touch_events.gd")
const UiProfiles: GDScript = preload("res://tests/support/ui_profiles.gd")
const BUILD_TICKS: int = 160  ## The plant takes 150 ticks.
const TARGET: Vector2i = Vector2i(14, 9)  ## A tile that holds the middle of a plant that fits.
## A structure built through the real queue and placed with the ghost on tile (11, 7): [local
## player, its Headquarters, further buildings it needs, the structure, its footprint].
const BUILDS: Array[Array] = [
	[1, "headquarters", [["barracks", 2, 10]], "defence_turret", Vector2i(1, 1)],
	[1, "headquarters", [], "power_plant", Vector2i(2, 2)],
	[1, "headquarters", [["power_plant", 2, 10]], "refinery", Vector2i(3, 3)],
	[2, "renew_hq", [], "renew_power", Vector2i(2, 2)],
]
const HOME: Vector2i = Vector2i(11, 7)

var _window_size_before: Vector2i
var _main: Node2D
var _runner: MatchRunner
var _camera: RtsCamera
var _touch: TouchInput
var _controller: PlayerController
var _placement: PlacementController
var _now_ms: int = 0
var _sent: Array[Command] = []
var _buzzed: Array[int] = []


func before() -> void:
	_window_size_before = get_window().size


func after_test() -> void:
	MenuRig.end()
	if is_instance_valid(_main):
		_main.free()
	UiScale.clear_override()
	CommandQueue.clear()
	get_window().size = _window_size_before


## The menu's slide is off for the test (tests/support/menu_rig.gd).
func before_test() -> void:
	MenuRig.begin()


func test_confirm_sends_exactly_one_place_for_the_origin_tile_and_holds_the_ghost() -> void:
	await _open()
	_place_at(Vector2i(11, 7))
	assert_bool(_placement.confirm()).is_true()
	assert_array(_sent).has_size(1)
	var place: Command = _sent[0]
	assert_array([place.type, place.player_id]).is_equal([Command.Type.PLACE, 1])
	# The origin tile's centre: the sim takes the tile of the point as the footprint's origin.
	assert_array([place.target_x, place.target_y]).is_equal([10500, 6500])
	assert_array(place.payload).is_empty()
	assert_bool(_placement.active).is_true()  # The mode waits for the sim's answer.
	assert_bool(_placement.pending).is_true()
	assert_array(_buzzed).is_equal([_controller.settings.haptic_ms])
	assert_bool(_placement.confirm()).is_false()  # A second press finds a PLACE in flight.
	assert_array(_sent).has_size(1)
	_placement.cancel()  # The X ends the mode; the PLACE already sent is not recalled.
	assert_bool(_placement.active).is_false()
	assert_bool(_placement.pending).is_false()
	assert_array(_sent).has_size(1)


func test_confirm_waits_for_a_ghost_that_fits_and_the_x_sends_nothing() -> void:
	await _open()
	for origin: Vector2i in [Rig.TOO_FAR, Rig.ON_THE_HQ, Rig.OFF_THE_MAP]:
		_place_at(origin + Vector2i.ONE)
		assert_bool(_placement.confirm()).override_failure_message(str(origin)).is_false()
		assert_bool(_placement.active).override_failure_message(str(origin)).is_true()
	assert_array(_sent).is_empty()
	assert_array(_buzzed).is_empty()
	_place_at(Vector2i(11, 7))
	_placement.cancel()
	assert_bool(_placement.active).is_false()
	assert_array(_sent).is_empty()
	assert_array(_buzzed).is_empty()
	var snap: MatchSnapshot = _runner.snapshot  # The structure stays ready, its card comes back.
	assert_int(snap.queue_count[World.TABS + World.Tab.STRUCTURES]).is_equal(1)


## The structure stands on the ghost's tile if its footprint is odd (the middle of the tile), and
## has the tile's top-left corner as its middle if even: worked out here from the tile alone, not
## from the controller's own origin.
func test_the_sim_builds_every_footprint_where_the_confirmed_place_named_the_origin() -> void:
	for entry: Array in BUILDS:
		var local: int = entry[0]
		var foot: Vector2i = entry[4]
		var note: String = "%s for player %s" % [entry[3], local]
		var made: ScenarioDef = Rig.scenario_for(local, entry[1], entry[2], [entry[3]])
		await _open(made, false)
		_controller.command_sink = CommandQueue.submit  # The real way in.
		var type: int = _runner.snapshot.type_ids.find(StringName(entry[3]))
		CommandQueue.submit(Command.queue(local, type))
		_runner.run_ticks(_runner.snapshot.type_build_ticks[type] + 10)
		var queue: int = local * World.TABS + World.Tab.STRUCTURES
		assert_int(_runner.snapshot.queue_count[queue]).override_failure_message(note).is_equal(1)
		assert_bool(_placement.begin(type)).override_failure_message(note).is_true()
		_place_at(HOME)
		assert_int(_placement.reason).override_failure_message(note).is_equal(Placement.Reason.OK)
		assert_bool(_placement.confirm()).override_failure_message(note).is_true()
		_runner.run_ticks(2)
		var snap: MatchSnapshot = _runner.snapshot
		var row: int = -1
		for at: int in snap.unit_count():
			if snap.type_index[at] == type and snap.owner[at] == local:
				row = at
		assert_int(row).override_failure_message(note).is_greater_equal(0)
		var middle: Vector2i = HOME * 1000 + Vector2i(foot.x % 2, foot.y % 2) * 500
		(
			assert_vector(Vector2i(snap.pos_x[row], snap.pos_y[row]))
			. override_failure_message(note)
			. is_equal(middle)
		)
		assert_int(snap.queue_count[queue]).override_failure_message(note).is_equal(0)
		assert_int(_runner.world.dropped_commands).override_failure_message(note).is_equal(0)
		CommandQueue.clear()


## The ghost is judged again on every tick's snapshot, which the sim made: a tank that rolls onto
## its footprint turns it red and the check mark off, it green again when the tank leaves, and a
## new match ends the mode. Nothing here calls `refresh` or touches the snapshot.
func test_each_tick_judges_the_ghost_again_and_a_new_match_ends_the_mode() -> void:
	var scenario: ScenarioDef = Rig.scenario_for(
		1, "headquarters", [], ["power_plant", "barracks", "light_tank"]
	)
	await _open(scenario)
	_place_at(HOME)
	var changes: Array[int] = []
	_placement.changed.connect(func() -> void: changes.append(_placement.reason))
	_runner.run_ticks(2)
	assert_int(_placement.reason).is_equal(Placement.Reason.OK)
	assert_array(changes).is_empty()  # Nothing changed: nothing is told.
	var world: World = _runner.world
	var tank: int = world.add_unit(1, world.type_ids.find(&"light_tank"), 10500, 6500)
	_runner.run_ticks(1)
	assert_int(_placement.reason).is_equal(Placement.Reason.OCCUPIED)
	assert_array(changes).is_equal([Placement.Reason.OCCUPIED])
	assert_bool((_hud("PlaceConfirm") as Button).disabled).is_true()
	assert_bool(_placement.confirm()).is_false()
	var row: int = world.index_of(tank)
	world.pos_x[row] = 2500
	world.goal_x[row] = 2500
	_runner.run_ticks(1)
	assert_int(_placement.reason).is_equal(Placement.Reason.OK)
	assert_array(changes).is_equal([Placement.Reason.OCCUPIED, Placement.Reason.OK])
	assert_bool((_hud("PlaceConfirm") as Button).disabled).is_false()
	_runner.start()
	_runner.run_ticks(1)
	assert_bool(_placement.active).is_false()
	assert_bool((_hud("GhostControls") as Control).visible).is_false()
	assert_array(_sent).is_empty()


func test_aiming_a_strike_and_placing_exclude_each_other() -> void:
	await _open()
	var aim: StrikeAim = _main.get_node("StrikeAim")
	aim.active = true  # As if the strike button had begun the aim.
	assert_bool(_placement.begin(Rig.plant(_runner.snapshot))).is_true()
	assert_bool(aim.active).is_false()
	assert_bool(_placement.active).is_true()
	aim.active = true
	aim.changed.emit()
	assert_bool(_placement.active).is_false()
	assert_bool(aim.active).is_true()
	assert_array(_sent).is_empty()


func test_begin_refuses_a_type_with_no_footprint_and_changes_nothing() -> void:
	await _open()
	_placement.cancel()
	var unit: int = _runner.snapshot.type_ids.find(&"rifle_squad")  # Not in this match: -1.
	for type: int in [unit, -1, 999, Rig.plant(_runner.snapshot) + 100]:
		assert_bool(_placement.begin(type)).override_failure_message(str(type)).is_false()
		assert_bool(_placement.active).override_failure_message(str(type)).is_false()
	_placement.runner = null  # No match to place in.
	assert_bool(_placement.begin(Rig.plant(_runner.snapshot))).is_false()
	assert_bool(_placement.active).is_false()


func test_a_turn_during_a_ghost_drag_keeps_the_tile_and_makes_no_command_or_hash_change() -> void:
	var idle: Dictionary = await _play(false)
	assert_int(idle["hash"]).is_not_equal(0)
	var turned: Dictionary = await _play(true)
	for key: String in ["hash", "commands", "pending", "tile", "active", "reason", "camera"]:
		assert_that(turned[key]).override_failure_message(key).is_equal(idle[key])
	assert_int(turned["commands"]).is_equal(0)
	assert_vector(turned["tile"]).is_equal(TARGET)  # Where the drag had put it before the turn.


## A new main scene on the phone, the plant built (its card is ready) and the Commands caught. The
## ghost is dragged to TARGET with the finger kept down, 30 ticks pass, the phone turns to portrait
## if asked, the finger moves on and lifts (to a place that would be another tile), 30 more ticks.
func _play(turn: bool) -> Dictionary:
	await _open()
	CommandQueue.submit(Command.queue(1, Rig.plant(_runner.snapshot)))
	_runner.run_ticks(BUILD_TICKS)
	_camera.centre_on(IsoProjection.cell_centre_px(11, 7))
	assert_bool(_placement.begin(Rig.plant(_runner.snapshot))).is_true()
	var lift: float = UiScale.dp(_controller.settings.ghost_lift_dp)
	var from: Vector2 = _screen_of(_placement.tile)
	var to: Vector2 = _screen_of(TARGET) + Vector2(0.0, lift)
	TouchEvents.press(get_viewport(), 0, from)
	TouchEvents.drag(get_viewport(), 0, to, to - from)
	assert_int(_touch._recognizer.state()).is_equal(GestureRecognizer.State.GRAB)
	assert_vector(_placement.tile).is_equal(TARGET)
	_runner.run_ticks(30)
	if turn:
		var portrait: UiMetrics = UiProfiles.by_name(&"android_6in_portrait")
		UiScale.set_override(portrait)
		get_window().size = portrait.window_size
		await await_idle_frame()
		await await_idle_frame()
		assert_int(_touch._recognizer.state()).is_equal(GestureRecognizer.State.IDLE)
		var away: Vector2 = to + Vector2(200.0, 100.0)
		TouchEvents.drag(get_viewport(), 0, away, Vector2(200.0, 100.0))  # The finger goes on.
		TouchEvents.release(get_viewport(), 0, away)
	else:
		TouchEvents.release(get_viewport(), 0, to)
	await await_idle_frame()
	_runner.run_ticks(30)
	return {
		"hash": _runner.last_hash,
		"commands": _sent.size(),
		"pending": CommandQueue.pending(),
		"tile": _placement.tile,
		"active": _placement.active,
		"reason": _placement.reason,
		"camera": _camera.position,
	}


## A new main scene on the phone, in the rig's match unless `scenario` is given; the scene of the
## run before, if a test opens more than one, is freed first. With `ready` the plant is made ready
## in the snapshot, the ground explored and the mode begun on it.
func _open(scenario: ScenarioDef = null, ready: bool = true) -> void:
	if is_instance_valid(_main):
		_main.free()
	var phone: UiMetrics = UiProfiles.by_name(&"android_6in")
	UiScale.set_override(phone)
	get_window().size = phone.window_size
	await await_idle_frame()
	_main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	_runner = _main.get_node("MatchRunner")
	_runner.scenario = Rig.scenario() if scenario == null else scenario
	_runner.paused = true  # Only run_ticks() moves time.
	add_child(_main)
	await await_idle_frame()
	_camera = _main.get_node("Camera")
	_touch = _main.get_node("TouchInput")
	_controller = _main.get_node("PlayerController")
	_placement = _main.get_node("PlacementController")
	_now_ms = 0
	_sent.clear()
	_buzzed.clear()
	_touch.clock = func() -> int: return _now_ms
	_controller.vibrate = func(ms: int) -> void: _buzzed.append(ms)
	_controller.command_sink = func(command: Command) -> void:
		_sent.append(command)
		CommandQueue.submit(command)
	_camera.centre_on(IsoProjection.cell_centre_px(HOME.x, HOME.y))
	if ready:
		Rig.make_ready(_runner.snapshot)
		Rig.explore(_runner.snapshot)
		assert_bool(_placement.begin(Rig.plant(_runner.snapshot))).is_true()


## The ghost on tile `tile` by a tap there.
func _place_at(tile: Vector2i) -> void:
	_camera.centre_on(IsoProjection.cell_centre_px(11, 7))
	var tap: GestureEvent = GestureEvent.new(GestureEvent.Kind.TAP)
	tap.position = _screen_of(tile)
	_controller.handle_gesture(tap)
	assert_vector(_placement.tile).is_equal(tile)


func _hud(node_name: String) -> Node:
	return _main.get_node("Hud").find_child(node_name, true, false)


func _screen_of(tile: Vector2i) -> Vector2:
	return _camera.world_to_screen(IsoProjection.cell_centre_px(tile.x, tile.y))
