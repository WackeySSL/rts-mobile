extends GdUnitTestSuite
## What happens after the check mark (plan P86b, ADR 0019 section 2), in the main scene on the
## 6-inch phone, with the real sim behind it. The PLACE leaves once and the ghost is held, pending:
## the check mark is dimmed, a second press and a second tap send nothing, the ghost does not move.
## The first snapshot published after the Command's tick holds the answer: a building at the ghost
## ends the mode; none means the sim refused (a tank rolled onto the footprint after the snapshot
## the ghost was judged on) and the ghost is "Blocked": red, with the glyph and the word, the mode
## kept and the check mark dimmed until the ghost is moved, then it may be confirmed again. The X
## ends the mode in every state and a new match too. A turn of the phone while the PLACE is pending
## queues no Command: the state hash of the run, the Commands and the camera are those of a run
## with no turn.

const Rig: GDScript = preload("res://tests/input/support/placement_rig.gd")
const TouchEvents: GDScript = preload("res://tests/support/touch_events.gd")
const UiProfiles: GDScript = preload("res://tests/support/ui_profiles.gd")
const BUILD_TICKS: int = 160  ## The plant takes 150 ticks.
const HOME: Vector2i = Vector2i(11, 7)  ## The tile that holds the middle of a plant that fits.
const ELSEWHERE: Vector2i = Vector2i(11, 10)  ## Another one that fits, three rows south.
const ROSTER: Array = ["power_plant", "barracks", "light_tank"]

var _window_size_before: Vector2i
var _main: Node2D
var _runner: MatchRunner
var _camera: RtsCamera
var _controller: PlayerController
var _placement: PlacementController
var _layer: GhostLayer
var _sent: Array[Command] = []
var _buzzed: Array[int] = []


func before() -> void:
	_window_size_before = get_window().size


func after_test() -> void:
	if is_instance_valid(_main):
		_main.free()
	UiScale.clear_override()
	CommandQueue.clear()
	get_window().size = _window_size_before


func test_a_pending_ghost_is_held_and_nothing_a_player_does_sends_a_second_place() -> void:
	await _open_with_plant()
	_place_at(HOME)
	assert_bool(_placement.confirm()).is_true()
	assert_array([_placement.active, _placement.pending, _placement.blocked]).is_equal(
		[true, true, false]
	)
	assert_bool(_placement.can_confirm()).is_false()
	assert_bool((_hud("PlaceConfirm") as Button).disabled).is_true()
	assert_bool((_hud("PlaceCancel") as Button).disabled).is_false()
	assert_bool((_hud("Items") as Control).visible).is_false()  # The cards wait for the answer.
	# The check mark pressed with a finger, and the call it makes, send nothing.
	await _settle()  # The row has its layout.
	var at: Vector2 = (_hud("PlaceConfirm") as Control).get_global_rect().get_center()
	TouchEvents.press(get_viewport(), 0, at)
	TouchEvents.release(get_viewport(), 0, at)
	assert_bool(_placement.pending).is_true()
	assert_bool(_placement.confirm()).is_false()
	assert_array(_sent).has_size(1)
	# The ghost stays where it was confirmed: a tap on other ground, a drag that starts on it.
	var tap: GestureEvent = GestureEvent.new(GestureEvent.Kind.TAP)
	tap.position = _screen_of(ELSEWHERE)
	_controller.handle_gesture(tap)
	var drag: GestureEvent = GestureEvent.new(GestureEvent.Kind.GHOST_DRAG)
	drag.position = _screen_of(ELSEWHERE)
	_placement.handle_gesture(drag)
	assert_vector(_placement.tile).is_equal(HOME)
	assert_bool(_placement.grabs(_screen_of(HOME))).is_false()
	_placement.edge_pan(Vector2.ZERO, 1.0)  # A finger in the corner: held too.
	assert_vector(_camera.position).is_equal(IsoProjection.cell_centre_px(HOME.x, HOME.y))
	# Frames pass and nothing is answered while no tick does.
	await _settle()
	assert_bool(_placement.pending).is_true()
	assert_array(_sent).has_size(1)


func test_a_building_in_the_snapshot_after_the_commands_tick_ends_the_mode() -> void:
	await _open_with_plant()
	_place_at(HOME)
	assert_bool(_placement.confirm()).is_true()
	var place: Command = _sent[0]
	assert_int(place.tick).is_equal(-1)  # The runner has not taken it.
	var before: int = _runner.snapshot.tick
	_runner.run_ticks(1)
	assert_int(place.tick).is_equal(before)  # Stamped with the tick it was applied at,
	assert_int(_runner.snapshot.tick).is_equal(before + 1)  # and answered by the next snapshot.
	assert_array([_placement.active, _placement.pending, _placement.blocked]).is_equal(
		[false, false, false]
	)
	assert_int(_buildings_at(_runner.snapshot, HOME)).is_equal(1)
	assert_int(_runner.world.dropped_commands).is_equal(0)
	assert_array(_sent).has_size(1)
	await _settle()
	assert_bool((_hud("Items") as Control).visible).is_true()  # The cards are back.
	assert_bool((_hud("Placement") as Control).visible).is_false()


## `refresh` reads the answer only from a snapshot past the Command's tick: not while the Command
## waits in the queue (tick -1), nor from the snapshot of the tick it was applied at.
func test_the_answer_waits_for_a_snapshot_past_the_commands_tick() -> void:
	await _open_with_plant()
	_place_at(HOME)
	assert_bool(_placement.confirm()).is_true()
	var place: Command = _sent[0]
	_placement.refresh()
	assert_bool(_placement.pending).is_true()  # Not taken yet.
	var latest: int = _runner.snapshot.tick
	place.tick = latest  # Taken at the tick of the snapshot already published: no answer in it.
	_placement.refresh()
	assert_bool(_placement.pending).is_true()
	place.tick = latest - 1  # One published tick later: the answer is read, and it has no building.
	_placement.refresh()
	assert_array([_placement.pending, _placement.blocked]).is_equal([false, true])


func test_a_refused_place_blocks_the_ghost_and_keeps_the_mode() -> void:
	await _open_with_plant()
	_place_at(HOME)
	assert_int(_placement.reason).is_equal(Placement.Reason.OK)
	# A tank rolls onto the footprint after the snapshot the ghost was judged on.
	var world: World = _runner.world
	var tank: int = world.add_unit(1, world.type_ids.find(&"light_tank"), 10500, 6500)
	assert_bool(_placement.confirm()).is_true()
	_runner.run_ticks(1)
	assert_array([_placement.active, _placement.pending, _placement.blocked]).is_equal(
		[true, false, true]
	)
	assert_int(_placement.reason).is_equal(Placement.Reason.OCCUPIED)
	assert_bool(_placement.fits()).is_false()
	assert_int(world.dropped_commands).is_equal(1)  # The sim dropped it,
	var queue: int = World.TABS + World.Tab.STRUCTURES
	assert_int(_runner.snapshot.queue_count[queue]).is_equal(1)  # and the plant is still ready.
	assert_int(_buildings_at(_runner.snapshot, HOME)).is_equal(0)
	await _settle()
	assert_bool((_hud("PlaceConfirm") as Button).disabled).is_true()
	assert_bool((_hud("PlaceCancel") as Button).disabled).is_false()
	assert_bool((_hud("Items") as Control).visible).is_false()  # The mode stays.
	_expect_blocked_drawn(Placement.Reason.OCCUPIED)
	# The tank drives off: the verdict is green again, but the ghost stays blocked until it moves.
	var row: int = world.index_of(tank)
	world.pos_x[row] = 2500
	world.goal_x[row] = 2500
	_runner.run_ticks(1)
	assert_int(_placement.reason).is_equal(Placement.Reason.OK)
	assert_bool(_placement.blocked).is_true()
	assert_bool(_placement.confirm()).is_false()
	await _settle()
	_expect_blocked_drawn(Placement.Reason.OCCUPIED)  # Red with the occupied glyph and the word.
	# Moving the ghost clears it; the second PLACE builds.
	_place_at(ELSEWHERE)
	assert_bool(_placement.blocked).is_false()
	await _settle()
	assert_that(_layer.tint()).is_equal(GhostLayer.FITS)
	assert_str(_layer.last_word).is_empty()
	assert_bool((_hud("PlaceConfirm") as Button).disabled).is_false()
	assert_bool(_placement.confirm()).is_true()
	assert_array(_sent).has_size(2)
	_runner.run_ticks(1)
	assert_bool(_placement.active).is_false()
	assert_int(_buildings_at(_runner.snapshot, ELSEWHERE)).is_equal(1)
	assert_int(_buildings_at(_runner.snapshot, HOME)).is_equal(0)


## The refusal the snapshot did not foresee at all: it still calls the tile a fit (here the plant is
## ready in the published snapshot only, so the sim finds nothing to place). The ghost is red with
## the occupied glyph and the word all the same, and a confirm after a move goes out again.
func test_a_refusal_on_a_tile_the_snapshot_calls_a_fit_is_blocked_too() -> void:
	await _open_with_plant(false)
	_place_at(HOME)
	assert_bool(_placement.confirm()).is_true()
	_runner.run_ticks(1)
	assert_array([_placement.active, _placement.blocked]).is_equal([true, true])
	assert_int(_placement.reason).is_equal(Placement.Reason.OK)
	assert_bool(_placement.fits()).is_false()
	await _settle()
	assert_that(_layer.tint()).is_equal(GhostLayer.DANGER)
	_expect_blocked_drawn(Placement.Reason.OCCUPIED)
	_place_at(ELSEWHERE)
	assert_bool(_placement.confirm()).is_true()
	assert_array(_sent).has_size(2)
	_runner.run_ticks(1)
	assert_bool(_placement.blocked).is_true()  # Refused again: blocked again.


## The answer is a building at the ghost's centre, not any of the type: with a plant standing at
## HOME already, a second PLACE that the sim refuses elsewhere is "Blocked", not taken for built.
func test_a_building_of_the_same_type_elsewhere_is_not_the_answer() -> void:
	await _open_with_plant()
	_place_at(HOME)
	assert_bool(_placement.confirm()).is_true()
	_runner.run_ticks(1)
	assert_int(_buildings_at(_runner.snapshot, HOME)).is_equal(1)
	CommandQueue.submit(Command.queue(1, Rig.plant(_runner.snapshot)))
	_runner.run_ticks(BUILD_TICKS)
	assert_bool(_placement.begin(Rig.plant(_runner.snapshot))).is_true()
	_place_at(ELSEWHERE)
	assert_int(_placement.reason).is_equal(Placement.Reason.OK)
	var world: World = _runner.world
	world.add_unit(1, world.type_ids.find(&"light_tank"), 10500, 9500)  # On the footprint.
	assert_bool(_placement.confirm()).is_true()
	_runner.run_ticks(1)
	assert_int(_buildings_at(_runner.snapshot, HOME)).is_equal(1)
	assert_int(_buildings_at(_runner.snapshot, ELSEWHERE)).is_equal(0)
	assert_array([_placement.active, _placement.pending, _placement.blocked]).is_equal(
		[true, false, true]
	)


func test_the_x_a_new_match_and_a_new_begin_end_pending_and_blocked() -> void:
	await _open_with_plant()
	_place_at(HOME)
	assert_bool(_placement.confirm()).is_true()
	_placement.cancel()  # The X while pending; the PLACE in flight is not recalled.
	assert_array([_placement.active, _placement.pending]).is_equal([false, false])
	_runner.run_ticks(1)
	assert_bool(_placement.active).is_false()  # And its answer wakes nothing.
	assert_array(_sent).has_size(1)
	assert_int(_buildings_at(_runner.snapshot, HOME)).is_equal(1)  # It was built all the same.
	# A new match while pending.
	_runner.start()
	_runner.run_ticks(1)
	CommandQueue.submit(Command.queue(1, Rig.plant(_runner.snapshot)))
	_runner.run_ticks(BUILD_TICKS)
	assert_bool(_placement.begin(Rig.plant(_runner.snapshot))).is_true()
	_place_at(HOME)
	assert_bool(_placement.confirm()).is_true()
	_runner.start()
	_runner.run_ticks(1)
	assert_array([_placement.active, _placement.pending, _placement.blocked]).is_equal(
		[false, false, false]
	)
	# A blocked ghost: the X ends it, and a begin on the same structure starts clean.
	CommandQueue.submit(Command.queue(1, Rig.plant(_runner.snapshot)))
	_runner.run_ticks(BUILD_TICKS)
	assert_bool(_placement.begin(Rig.plant(_runner.snapshot))).is_true()
	_place_at(HOME)
	var world: World = _runner.world
	world.add_unit(1, world.type_ids.find(&"light_tank"), 10500, 6500)
	assert_bool(_placement.confirm()).is_true()
	_runner.run_ticks(1)
	assert_bool(_placement.blocked).is_true()
	_placement.cancel()
	assert_array([_placement.active, _placement.blocked]).is_equal([false, false])
	assert_bool(_placement.begin(Rig.plant(_runner.snapshot))).is_true()
	assert_array([_placement.pending, _placement.blocked]).is_equal([false, false])


func test_a_turn_while_the_place_is_pending_queues_no_command_and_changes_no_hash() -> void:
	var idle: Dictionary = await _pending_run(false)
	assert_int(idle["hash"]).is_not_equal(0)
	var turned: Dictionary = await _pending_run(true)
	for key: String in [
		"hash", "commands", "queued", "dropped", "built", "tile", "active", "camera"
	]:
		assert_that(turned[key]).override_failure_message(key).is_equal(idle[key])
	assert_int(turned["commands"]).is_equal(1)  # The one PLACE, no other.
	assert_int(turned["built"]).is_equal(1)
	assert_int(turned["dropped"]).is_equal(0)
	assert_bool(turned["active"]).is_false()
	assert_vector(turned["tile"]).is_equal(HOME)


## A new main scene, the plant built through the queue, the PLACE sent for HOME; with `turn` the
## phone turns to portrait while it is pending. Then 40 ticks.
func _pending_run(turn: bool) -> Dictionary:
	await _open_with_plant()
	_place_at(HOME)
	assert_bool(_placement.confirm()).is_true()
	if turn:
		var portrait: UiMetrics = UiProfiles.by_name(&"android_6in_portrait")
		UiScale.set_override(portrait)
		get_window().size = portrait.window_size
		await await_idle_frame()
		await await_idle_frame()
		assert_bool(_placement.pending).is_true()
		assert_vector(_placement.tile).is_equal(HOME)
	_runner.run_ticks(40)
	await await_idle_frame()
	return {
		"hash": _runner.last_hash,
		"commands": _sent.size(),
		"queued": CommandQueue.pending(),
		"dropped": _runner.world.dropped_commands,
		"built": _buildings_at(_runner.snapshot, HOME),
		"tile": _placement.tile,
		"active": _placement.active,
		"camera": _camera.position,
	}


## The glyph, the hatch and the word of a blocked ghost on the last frame: danger red, the glyph of
## `shown`, the three marks of every cell and "Blocked".
func _expect_blocked_drawn(shown: int) -> void:
	var key: String = String(Placement.Reason.find_key(shown)).to_lower()
	assert_that(_layer.tint()).is_equal(GhostLayer.DANGER)
	assert_str(_layer.last_word).is_equal(GhostLayer.BLOCKED_TEXT)
	var drawn: Texture2D = _layer.last_glyph
	assert_str("" if drawn == null else drawn.resource_path).is_equal(GhostLayer.GLYPH_ART % key)
	assert_int(_layer.last_marks).is_equal(_layer.cells().size() * 3)


## The local player's buildings of the type being placed in `snap` whose centre is on the footprint
## that has `tile` as its centre tile (a 2 x 2 plant's centre is the tile's corner).
func _buildings_at(snap: MatchSnapshot, tile: Vector2i) -> int:
	var type: int = Rig.plant(snap)
	var found: int = 0
	for row: int in snap.unit_count():
		var centre: Vector2i = Vector2i(snap.pos_x[row], snap.pos_y[row])
		if snap.type_index[row] == type and snap.owner[row] == 1 and centre == tile * 1000:
			found += 1
	return found


## A new main scene on the phone in the match of the rig with a light tank in the roster, the
## Commands caught and passed on. With `real` the plant is built through the queue; without, it is
## ready in the published snapshot only. The ground is explored and the mode begun on it.
func _open_with_plant(real: bool = true) -> void:
	if is_instance_valid(_main):
		_main.free()
	var phone: UiMetrics = UiProfiles.by_name(&"android_6in")
	UiScale.set_override(phone)
	get_window().size = phone.window_size
	await await_idle_frame()
	_main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	_runner = _main.get_node("MatchRunner")
	_runner.scenario = Rig.scenario_for(1, "headquarters", [], ROSTER)
	_runner.paused = true  # Only run_ticks() moves time.
	add_child(_main)
	await await_idle_frame()
	_camera = _main.get_node("Camera")
	_controller = _main.get_node("PlayerController")
	_placement = _main.get_node("PlacementController")
	_layer = _main.get_node("GhostLayer")
	_sent.clear()
	_buzzed.clear()
	_controller.vibrate = func(ms: int) -> void: _buzzed.append(ms)
	_controller.command_sink = func(command: Command) -> void:
		_sent.append(command)
		CommandQueue.submit(command)
	_camera.centre_on(IsoProjection.cell_centre_px(HOME.x, HOME.y))
	if real:
		CommandQueue.submit(Command.queue(1, Rig.plant(_runner.snapshot)))
		_runner.run_ticks(BUILD_TICKS)
	else:
		Rig.make_ready(_runner.snapshot)
		Rig.explore(_runner.snapshot)
	var queue: int = World.TABS + World.Tab.STRUCTURES
	assert_int(_runner.snapshot.queue_count[queue]).is_equal(1)
	assert_bool(_placement.begin(Rig.plant(_runner.snapshot))).is_true()


## The ghost on tile `tile` by a tap there.
func _place_at(tile: Vector2i) -> void:
	_camera.centre_on(IsoProjection.cell_centre_px(HOME.x, HOME.y))
	var tap: GestureEvent = GestureEvent.new(GestureEvent.Kind.TAP)
	tap.position = _screen_of(tile)
	_controller.handle_gesture(tap)
	assert_vector(_placement.tile).is_equal(tile)


func _settle() -> void:
	await await_idle_frame()
	await await_idle_frame()


func _hud(node_name: String) -> Node:
	return _main.get_node("Hud").find_child(node_name, true, false)


func _screen_of(tile: Vector2i) -> Vector2:
	return _camera.world_to_screen(IsoProjection.cell_centre_px(tile.x, tile.y))
