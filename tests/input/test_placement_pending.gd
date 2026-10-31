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

const MenuRig: GDScript = preload("res://tests/support/menu_rig.gd")
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
	MenuRig.end()
	if is_instance_valid(_main):
		_main.free()
	UiScale.clear_override()
	CommandQueue.clear()
	get_window().size = _window_size_before


## The menu's slide is off for the test (tests/support/menu_rig.gd).
func before_test() -> void:
	MenuRig.begin()


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
	assert_bool((_hud("Items") as Control).is_visible_in_tree()).is_false()  # The menu is down.
	# The check mark pressed with a finger, and the call it makes, send nothing.
	await _settle()  # The buttons are beside the ghost.
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
	assert_bool((_hud("Items") as Control).is_visible_in_tree()).is_true()  # The menu is back.
	assert_bool((_hud("GhostControls") as Control).visible).is_false()  # The buttons are gone.


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
	assert_bool((_hud("GhostControls") as Control).visible).is_true()  # The mode stays.
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


## The refusal the answering snapshot does not show: a tank touches the footprint's east edge when
## the tick starts, so the sim refuses the PLACE, and drives off in that same tick, so the snapshot
## calls the tile a fit again. The ghost is red with the occupied glyph and the word all the same,
## and the structure is still ready.
func test_a_refusal_on_a_tile_the_snapshot_calls_a_fit_is_blocked_too() -> void:
	await _open_with_plant()
	_place_at(HOME)
	var world: World = _runner.world
	var type: int = world.type_ids.find(&"light_tank")
	var tank: int = world.add_unit(1, type, 12000 + world.type_radius[type], 7000)
	CommandQueue.submit(Command.move(1, PackedInt32Array([tank]), 30000, 7000))
	assert_bool(_placement.confirm()).is_true()
	_runner.run_ticks(1)
	assert_int(world.dropped_commands).is_equal(1)
	assert_array([_placement.active, _placement.blocked]).is_equal([true, true])
	assert_int(_placement.reason).is_equal(Placement.Reason.OK)  # The tank has left the footprint.
	assert_bool(_placement.fits()).is_false()
	await _settle()
	assert_that(_layer.tint()).is_equal(GhostLayer.DANGER)
	_expect_blocked_drawn(Placement.Reason.OCCUPIED)
	_place_at(ELSEWHERE)
	assert_bool(_placement.confirm()).is_true()
	_runner.run_ticks(1)
	assert_int(_buildings_at(_runner.snapshot, ELSEWHERE)).is_equal(1)  # Moved and built.
	assert_bool(_placement.active).is_false()


## The X while the PLACE is pending, then a tap on the card, which still says READY, and a second
## confirm before any tick: the first PLACE builds and uses the structure up. The second one is
## refused, and since no ready structure is left the mode ends with the answer instead of
## "Blocked", which no move would cure.
func test_the_x_and_a_new_begin_while_a_place_is_in_flight_end_with_the_second_answer() -> void:
	await _open_with_plant()
	_place_at(HOME)
	assert_bool(_placement.confirm()).is_true()
	_placement.cancel()  # The X.
	assert_bool(_placement.begin(Rig.plant(_runner.snapshot))).is_true()  # The card says READY.
	_place_at(ELSEWHERE)
	assert_bool(_placement.confirm()).is_true()  # The ghost looks fine to the player.
	_runner.run_ticks(1)  # The first PLACE builds at HOME, the second is refused.
	assert_int(_buildings_at(_runner.snapshot, HOME)).is_equal(1)
	assert_array([_placement.active, _placement.pending, _placement.blocked]).is_equal(
		[false, false, false]
	)
	assert_int(_runner.world.dropped_commands).is_equal(1)  # The second one, refused.
	assert_array(_sent).has_size(2)
	assert_int(_buildings_at(_runner.snapshot, ELSEWHERE)).is_equal(0)


## The same, with the second ghost never confirmed: once the first PLACE has used the structure up,
## the next snapshot ends the mode (P86c: it is not ready at the head any more), so the check mark
## has nothing to send and no second PLACE leaves.
func test_a_structure_the_first_place_used_up_ends_a_ghost_that_was_never_confirmed() -> void:
	await _open_with_plant()
	_place_at(HOME)
	assert_bool(_placement.confirm()).is_true()
	_placement.cancel()  # The X.
	assert_bool(_placement.begin(Rig.plant(_runner.snapshot))).is_true()
	_place_at(ELSEWHERE)
	_runner.run_ticks(1)
	assert_int(_buildings_at(_runner.snapshot, HOME)).is_equal(1)
	assert_array([_placement.active, _placement.pending, _placement.blocked]).is_equal(
		[false, false, false]
	)
	assert_bool(_placement.confirm()).is_false()
	assert_int(_runner.world.dropped_commands).is_equal(0)
	assert_array(_sent).has_size(1)


## The Build button brings the cards back with the ghost still out (a HUD touch, ADR 0024 section 6;
## placement had taken the menu down), so the READY card can be tapped with a PLACE in flight: that
## changes nothing. The ghost is held (`begin` would forget the Command in flight and
## wake the check mark, and a second press would send a second PLACE), and no second PLACE leaves.
## Outside pending the same tap puts the ghost back at the view's centre, as it always did.
func test_a_tap_on_the_ready_card_while_the_place_is_pending_changes_nothing() -> void:
	await _open_with_plant()
	await _settle()  # The sidebar reads the finished plant.
	await _bring_the_cards_back()
	assert_int(_card().state).is_equal(ItemTile.State.READY)
	_place_at(ELSEWHERE)
	_tap_card()  # Not pending: the ghost is back where the view's centre is.
	assert_vector(_placement.tile).is_equal(HOME)
	assert_bool(_placement.active).is_true()
	_place_at(ELSEWHERE)
	assert_bool(_placement.confirm()).is_true()
	var place: Command = _sent[0]
	_tap_card()
	assert_array([_placement.active, _placement.pending, _placement.blocked]).is_equal(
		[true, true, false]
	)
	assert_vector(_placement.tile).is_equal(ELSEWHERE)
	assert_bool(_placement.can_confirm()).is_false()
	assert_bool(_placement.begin(Rig.plant(_runner.snapshot))).is_false()
	await _settle()
	assert_bool((_hud("PlaceConfirm") as Button).disabled).is_true()
	var at: Vector2 = (_hud("PlaceConfirm") as Control).get_global_rect().get_center()
	TouchEvents.press(get_viewport(), 0, at)
	TouchEvents.release(get_viewport(), 0, at)
	assert_array(_sent).has_size(1)
	assert_bool(_sent[0] == place).is_true()
	_runner.run_ticks(1)  # The one PLACE builds, and the answer ends the mode.
	assert_int(_buildings_at(_runner.snapshot, ELSEWHERE)).is_equal(1)
	assert_bool(_placement.active).is_false()
	assert_int(_runner.world.dropped_commands).is_equal(0)


## A hold on the READY card cancels the finished structure (CANCEL, paid back) and its ghost has
## nothing left to place: the next snapshot ends the mode, with no Command of its own.
func test_a_hold_on_the_ready_card_cancels_the_structure_and_ends_the_mode() -> void:
	await _open_with_plant()
	await _settle()
	await _bring_the_cards_back()
	_place_at(ELSEWHERE)
	var credits: int = _runner.snapshot.credits[1]
	_hold_card()
	assert_array(_sent).has_size(1)
	assert_int(_sent[0].type).is_equal(Command.Type.CANCEL)
	assert_bool(_placement.active).is_true()  # Until the sim has taken the CANCEL.
	_runner.run_ticks(1)
	assert_int(_runner.snapshot.credits[1]).is_greater(credits)  # Paid back.
	assert_array([_placement.active, _placement.pending, _placement.blocked]).is_equal(
		[false, false, false]
	)
	await _settle()
	assert_bool((_hud("GhostControls") as Control).visible).is_false()
	assert_array(_sent).has_size(1)


## What counts as built: the local player's building of the type being placed exactly at the ghost's
## centre. Another player's building of the type, the player's own of another type, and its own of
## the type a tile off do not; the right one does.
func test_only_the_local_players_building_of_the_type_at_the_ghosts_centre_counts_as_built(
) -> void:
	await _open_with_plant()
	_place_at(HOME)
	var plant: int = Rig.plant(_runner.snapshot)
	var other: int = (plant + 1) % _runner.snapshot.type_ids.size()
	assert_int(other).is_not_equal(plant)
	var at: Vector2i = _placement.centre_ground()
	var rows: Array[Array] = [
		[2, plant, at.x, at.y],  # Another player's, of the type.
		[1, other, at.x, at.y],  # The player's, of another type.
		[1, plant, at.x + 1000, at.y],  # The player's, of the type, a tile east.
		[1, plant, at.x, at.y + 1000],  # And a tile south.
	]
	var snap: MatchSnapshot = MatchSnapshot.new()
	for row: Array in rows:
		assert_bool(_placement._built(_snapshot_of(snap, [row]))).is_false()
	assert_bool(_placement._built(_snapshot_of(snap, rows))).is_false()
	rows.append([1, plant, at.x, at.y])
	assert_bool(_placement._built(_snapshot_of(snap, rows))).is_true()


## The end of the match ends a pending placement: no tick follows, so a PLACE that was never taken
## would leave the ghost pending for good. Here the sink does not pass the Command on, and the
## match ends by a surrender.
func test_the_end_of_the_match_ends_a_pending_placement() -> void:
	await _open_with_plant()
	_controller.command_sink = func(command: Command) -> void: _sent.append(command)
	_place_at(HOME)
	assert_bool(_placement.confirm()).is_true()
	assert_int(_sent[0].tick).is_equal(-1)  # Never taken by the runner.
	CommandQueue.submit(Command.surrender(1))
	_runner.run_ticks(3)
	assert_int(_runner.snapshot.match_end_tick).is_greater(0)
	assert_array([_placement.active, _placement.pending, _placement.blocked]).is_equal(
		[false, false, false]
	)


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
## Commands caught and passed on, the plant built through the queue (it is READY) and the mode
## begun on it.
func _open_with_plant() -> void:
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
	CommandQueue.submit(Command.queue(1, Rig.plant(_runner.snapshot)))
	_runner.run_ticks(BUILD_TICKS)
	var queue: int = World.TABS + World.Tab.STRUCTURES
	assert_int(_runner.snapshot.queue_count[queue]).is_equal(1)
	assert_bool(_placement.begin(Rig.plant(_runner.snapshot))).is_true()


## `snap` with the buildings of `rows`, each [owner, type index, x, y], and nothing else.
func _snapshot_of(snap: MatchSnapshot, rows: Array[Array]) -> MatchSnapshot:
	snap.unit_id = PackedInt32Array()
	snap.owner = PackedInt32Array()
	snap.type_index = PackedInt32Array()
	snap.pos_x = PackedInt32Array()
	snap.pos_y = PackedInt32Array()
	for row: Array in rows:
		snap.unit_id.append(snap.unit_id.size() + 1)
		snap.owner.append(row[0])
		snap.type_index.append(row[1])
		snap.pos_x.append(row[2])
		snap.pos_y.append(row[3])
	return snap


## The ghost on tile `tile` by a tap there.
func _place_at(tile: Vector2i) -> void:
	_camera.centre_on(IsoProjection.cell_centre_px(HOME.x, HOME.y))
	var tap: GestureEvent = GestureEvent.new(GestureEvent.Kind.TAP)
	tap.position = _screen_of(tile)
	_controller.handle_gesture(tap)
	assert_vector(_placement.tile).is_equal(tile)


## Placement took the menu down; a tap on the Build button, with the ghost still out, brings it up.
func _bring_the_cards_back() -> void:
	var sidebar: BuildSidebar = _hud("BuildSidebar") as BuildSidebar
	assert_bool(sidebar.is_open()).is_false()
	var at: Vector2 = (_hud("Build") as Control).get_global_rect().get_center()
	TouchEvents.press(get_viewport(), 0, at)
	TouchEvents.release(get_viewport(), 0, at)
	assert_bool(sidebar.is_open()).is_true()
	assert_bool(_placement.active).is_true()
	await _settle()


func _card() -> ItemTile:
	return _hud("Tile_%s" % Rig.PLANT) as ItemTile


## A tap on the READY card with a finger: pressed and released at once, well before a hold.
func _tap_card() -> void:
	var at: Vector2 = _card().get_global_rect().get_center()
	TouchEvents.press(get_viewport(), 0, at)
	TouchEvents.release(get_viewport(), 0, at)


## A hold on the READY card: the card's clock runs `hold_ms` between the press and the release.
func _hold_card() -> void:
	var card: ItemTile = _card()
	var now: Array[int] = [0]
	card.clock = func() -> int: return now[0]
	var at: Vector2 = card.get_global_rect().get_center()
	TouchEvents.press(get_viewport(), 0, at)
	now[0] += card.hold_ms
	card._process(0.0)
	TouchEvents.release(get_viewport(), 0, at)


func _settle() -> void:
	await await_idle_frame()
	await await_idle_frame()


func _hud(node_name: String) -> Node:
	return _main.get_node("Hud").find_child(node_name, true, false)


func _screen_of(tile: Vector2i) -> Vector2:
	return _camera.world_to_screen(IsoProjection.cell_centre_px(tile.x, tile.y))
