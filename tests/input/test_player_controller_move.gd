extends GdUnitTestSuite
## The ground tap of PlayerController (P43c) through the real CommandQueue and sim: it is a MOVE, so
## it takes units out of a fight. Michael, 2026-10-20 (his words, verbatim, are in row P43c of
## docs/plans/2026-10-11-phase-2.md): selecting units and telling them to drive to another position
## must stop the attack and drive them there. The cases in
## test_player_controller.gd and test_controls_flow.gd pin the Command a tap sends; these play it.
## Fingers enter as window-px touch events through the real TouchInput with a fake clock, at
## 1280x720 (desktop), 2400x1080 (android_6in, 20:9 phone) and 2048x1536 (web_tablet, 4:3).
## The fight: blue tanks 1 and 2 stand at milli (8500, 18500) and (10000, 18500); red tank 31 is
## put at (9250, 14500), 4070 from each (the tank cannon's range is 4500, sight 7000), so the pair
## fires at it as soon as it is told to. The retreat point (15000, 12500) is 6088 from the red
## tank: beyond the range of an idle unit (4500) and the acquire range of an attack-moving one
## (5500), but inside the sight of the pair, so the red tank stays pickable and attackable for a
## later tap (the fog authoring rule of P46b and P47p). Every point is inside tiles x 6..37,
## y 8..28, the open rectangle that P48 keeps free of terrain on the controls map. Red tank 31 has
## no AI: it fires only as an idle unit, and drives only when a case orders it.

const MenuRig: GDScript = preload("res://tests/support/menu_rig.gd")
const TouchEvents: GDScript = preload("res://tests/support/touch_events.gd")
const UiProfiles: GDScript = preload("res://tests/support/ui_profiles.gd")
const PROFILES: Array[StringName] = [&"desktop", &"android_6in", &"web_tablet"]
const OPENINGS: Array[StringName] = [&"attack", &"attack_move"]
const PAIR: Array[int] = [1, 2]
const RED: int = 31
const RED_MILLI: Vector2i = Vector2i(9250, 14500)
const RETREAT_MILLI: Vector2i = Vector2i(15000, 12500)
## The retreat point in world px under the 2:1 projection (P117), and the camera centre that shows
## the pair, the red tank and the point.
const RETREAT: Vector2 = Vector2(80, 440)
const CAMERA_AT: Vector2 = Vector2(-100, 420)
const WEAPON_RANGE: int = 4500
const TOL: Vector2 = Vector2(0.05, 0.05)

var _window_size_before: Vector2i
var _runner: MatchRunner
var _layer: UnitLayer
var _camera: RtsCamera
var _touch: TouchInput
var _controller: PlayerController
var _markers: MoveMarkerLayer
var _now_ms: int = 0
var _sent: Array[Command] = []


func before() -> void:
	_window_size_before = get_window().size


func after() -> void:
	get_window().size = _window_size_before


func before_test() -> void:
	MenuRig.begin()
	get_window().size = Vector2i(1280, 720)
	await await_idle_frame()
	var main: Node2D = auto_free((load("res://scenes/main.tscn") as PackedScene).instantiate())
	add_child(main)
	await await_idle_frame()
	_runner = main.get_node("MatchRunner")
	_runner.paused = true  # Only run_ticks() moves time.
	_layer = main.get_node("UnitLayer")
	_camera = main.get_node("Camera")
	_touch = main.get_node("TouchInput")
	_controller = main.get_node("PlayerController")
	_markers = main.get_node("MarkerLayer")
	_now_ms = 0
	_touch.clock = func() -> int: return _now_ms
	_markers.clock = _touch.clock  # One fake clock: a mark of an earlier profile has expired.


## The override is static state: leaving one behind changes every later suite.
func after_test() -> void:
	MenuRig.end()
	UiScale.clear_override()
	CommandQueue.clear()


## The whole story, at all three screen sizes and from both ways a fight starts (a tap on the red
## tank, an ATTACK; and an ATTACK_MOVE, which a scenario or the AI may still give and which holds
## its target for good). The pair fires at the red tank and is about to fire again; a tap on the
## ground makes it stop at once (no SHOT from it in the tick the MOVE is applied or in any tick
## after, and the red tank takes no more damage once the shells in flight have landed), drive to
## the point in formation and stand idle there. A red tank that then drives into the weapon range
## of the idle pair is fired at, and the pair does not move.
func test_a_ground_tap_stops_a_fight_and_the_units_drive_away_then_fire_without_moving() -> void:
	for profile: StringName in PROFILES:
		for opening: StringName in OPENINGS:
			var label: String = "%s, %s" % [profile, opening]
			await _fresh_match(profile)
			var world: World = _runner.world
			_open_fire(opening)
			assert_int(_fight_until_about_to_fire()).override_failure_message(label).is_greater(0)
			assert_bool(_about_to_fire()).is_true()  # Without the tap the next tick would shoot.
			var red_hp: int = world.hp[world.index_of(RED)]
			assert_int(red_hp).is_less(300)  # It was hit, and is alive.
			var sent: int = _sent.size()
			_tap(_camera.world_to_screen(RETREAT))
			assert_array(_sent).has_size(sent + 1)
			if _sent.size() <= sent:
				continue  # No MOVE to look at; the next variant still runs.
			_assert_move(_sent[sent], PAIR, RETREAT_MILLI)
			_assert_one_chevron_mark_at(RETREAT)  # The diamond of the enemy tap has faded.
			var arrived: int = -1
			for tick: int in 400:
				_runner.run_ticks(1)
				(
					assert_array(_shots_by(PAIR))
					. override_failure_message("%s: a shot %d ticks after the tap" % [label, tick])
					. is_empty()
				)
				if tick == 0:  # The tick the MOVE is applied.
					for id: int in PAIR:
						assert_int(world.order[world.index_of(id)]).is_equal(World.Order.MOVE)
						assert_int(world.target[world.index_of(id)]).is_equal(0)
				if tick == 12:  # The longest flight is 8 ticks (4070 at 600 a tick is 7).
					red_hp = world.hp[world.index_of(RED)]
				if _all_idle(PAIR):
					arrived = tick
					break
			assert_int(arrived).override_failure_message(label + ": never arrived").is_greater(12)
			assert_int(world.hp[world.index_of(RED)]).is_equal(red_hp)  # Nothing hit it on the way.
			_assert_idle_pair_fires_on_a_visitor(label)
			assert_int(world.dropped_commands).is_equal(0)


## The lock of an ATTACK is released by the ground tap, and a tap on the enemy afterwards attacks
## again. The ATTACK order keeps its target while the unit lives (P41b); a MOVE drops it in the
## tick it is applied. `order_target` is not asserted: only an ATTACK row reads it.
func test_a_ground_tap_releases_the_attack_lock_and_a_later_enemy_tap_attacks_again() -> void:
	for profile: StringName in PROFILES:
		await _fresh_match(profile)
		var world: World = _runner.world
		_attack_red()
		_runner.run_ticks(2)
		for id: int in PAIR:
			assert_int(world.order[world.index_of(id)]).is_equal(World.Order.ATTACK)
			assert_int(world.order_target[world.index_of(id)]).is_equal(RED)
			assert_int(world.target[world.index_of(id)]).is_equal(RED)
		_tap(_camera.world_to_screen(RETREAT))
		assert_array(_sent).has_size(2)
		if _sent.size() < 2:
			continue
		_assert_move(_sent[1], PAIR, RETREAT_MILLI)
		_runner.run_ticks(1)
		for id: int in PAIR:
			assert_int(world.order[world.index_of(id)]).is_equal(World.Order.MOVE)
			assert_int(world.target[world.index_of(id)]).is_equal(0)
		_runner.run_ticks(10)  # Still driving, a little way along.
		assert_bool(_all_idle(PAIR)).is_false()
		_layer._process(0.0)
		_tap(_off_centre(world.index_of(RED)))
		assert_array(_sent).has_size(3)
		if _sent.size() < 3:
			continue
		_assert_attack(_sent[2])
		_runner.run_ticks(1)
		for id: int in PAIR:
			assert_int(world.order[world.index_of(id)]).is_equal(World.Order.ATTACK)
			assert_int(world.order_target[world.index_of(id)]).is_equal(RED)
		assert_int(world.dropped_commands).is_equal(0)


## A new match at `profile`'s screen size with the red tank put in range of tanks 1 and 2, the pair
## selected, the camera on both, and every Command caught on its way into the real queue.
func _fresh_match(profile: StringName) -> void:
	var metrics: UiMetrics = UiProfiles.by_name(profile)
	UiScale.set_override(metrics)
	get_window().size = metrics.window_size
	_runner.start()
	await await_idle_frame()  # The layer builds the new rigs, TouchInput reads the new dp.
	CommandQueue.clear()
	_sent.clear()
	_controller.command_sink = func(command: Command) -> void:
		_sent.append(command)
		CommandQueue.submit(command)
	var world: World = _runner.world
	var row: int = world.index_of(RED)
	world.pos_x[row] = RED_MILLI.x
	world.pos_y[row] = RED_MILLI.y
	_runner.run_ticks(maxi(world.fog_period_ticks, 2))  # The snapshot and the rig stand there.
	_layer._process(0.0)
	_camera.centre_on(CAMERA_AT)
	_controller.selection.set_ids(PackedInt32Array(PAIR))
	_markers._process(0.0)  # A mark of the last profile is older than its lifetime by now.


## The pair is at its retreat point, idle. A red tank drives to 3200 north of the first tank and the
## idle pair fires as it comes into range: a shot of the pair at the red tank, from within the
## weapon range, with the pair's orders and positions the same in every tick up to it.
func _assert_idle_pair_fires_on_a_visitor(label: String) -> void:
	var world: World = _runner.world
	var spots: Array[Vector2i] = []
	for id: int in PAIR:
		var row: int = world.index_of(id)
		spots.append(Vector2i(world.pos_x[row], world.pos_y[row]))
		assert_float(Vector2(spots.back()).distance_to(Vector2(RETREAT_MILLI))).is_less(1500.0)
	CommandQueue.submit(Command.move(2, PackedInt32Array([RED]), spots[0].x, spots[0].y - 3200))
	var fired: Array[PackedInt32Array] = []
	for tick: int in 200:
		_runner.run_ticks(1)
		for i: int in PAIR.size():
			var row: int = world.index_of(PAIR[i])
			assert_int(world.order[row]).is_equal(World.Order.IDLE)
			assert_vector(Vector2i(world.pos_x[row], world.pos_y[row])).is_equal(spots[i])
		fired = _shots_by(PAIR)
		if not fired.is_empty():
			break
	assert_array(fired).override_failure_message(label + ": no shot at the red tank").is_not_empty()
	if fired.is_empty():
		return
	var shot: PackedInt32Array = fired[0]
	assert_int(shot[4]).is_equal(RED)  # Its target.
	var apart: float = Vector2(shot[2], shot[3]).distance_to(Vector2(shot[6], shot[7]))
	assert_float(apart).is_less_equal(float(WEAPON_RANGE))


## Starts the fight: `attack` taps the red tank (one ATTACK through the sink, the real gesture);
## `attack_move` queues an ATTACK_MOVE onto the red tank's own position, as a scenario would.
func _open_fire(opening: StringName) -> void:
	if opening == &"attack":
		_attack_red()
	else:
		CommandQueue.submit(
			Command.attack_move(1, PackedInt32Array(PAIR), RED_MILLI.x, RED_MILLI.y)
		)


## The tap on the red tank, 20 dp off its centre: one ATTACK, the first Command of the case.
func _attack_red() -> void:
	_tap(_off_centre(_runner.world.index_of(RED)))
	assert_array(_sent).has_size(1)
	if _sent.is_empty():
		return
	_assert_attack(_sent[0])
	_markers._process(0.0)  # The diamond is a second old by now, past its lifetime.


## Plays ticks until the pair has fired and one of its tanks would fire again in the next tick (its
## cooldown is at most 1 and it holds the red tank as its target). Returns the shots seen.
func _fight_until_about_to_fire() -> int:
	var shots: int = 0
	for tick: int in 150:
		_runner.run_ticks(1)
		shots += _shots_by(PAIR).size()
		if shots > 0 and _about_to_fire():
			break
	return shots


func _about_to_fire() -> bool:
	var world: World = _runner.world
	for id: int in PAIR:
		var row: int = world.index_of(id)
		if world.cooldown[row] <= 1 and world.target[row] == RED:
			return true
	return false


func _all_idle(ids: Array[int]) -> bool:
	var world: World = _runner.world
	for id: int in ids:
		if world.order[world.index_of(id)] != World.Order.IDLE:
			return false
	return true


## The SHOT records of the last tick whose shooter is one of `shooters`: [SHOT, shooter id, shooter
## x, y, target id, weapon, target x, y].
func _shots_by(shooters: Array[int]) -> Array[PackedInt32Array]:
	var shots: Array[PackedInt32Array] = []
	var events: PackedInt32Array = _runner.world.events
	for at: int in range(0, events.size(), World.EVENT_STRIDE):
		if events[at] == World.Event.SHOT and shooters.has(events[at + 1]):
			shots.append(events.slice(at, at + World.EVENT_STRIDE))
	return shots


func _assert_move(command: Command, ids: Array[int], at: Vector2i) -> void:
	assert_int(command.type).is_equal(Command.Type.MOVE)
	assert_int(command.player_id).is_equal(1)
	assert_array(command.unit_ids).is_equal(ids)
	assert_int(command.target_x).is_equal(at.x)
	assert_int(command.target_y).is_equal(at.y)


func _assert_attack(command: Command) -> void:
	assert_int(command.type).is_equal(Command.Type.ATTACK)
	assert_int(command.player_id).is_equal(1)
	assert_array(command.unit_ids).is_equal(PAIR)
	assert_int(command.target_id).is_equal(RED)


## Exactly one mark shows, it is the four chevrons (not the diamond), and it stands on `world_px`.
func _assert_one_chevron_mark_at(world_px: Vector2) -> void:
	var shown: Array[MoveMarkerLayer.Mark] = []
	for mark: MoveMarkerLayer.Mark in _markers.get_children():
		if mark.visible:
			shown.append(mark)
	assert_array(shown).has_size(1)
	if shown.is_empty():
		return
	assert_bool(shown[0].diamond).is_false()
	assert_vector(shown[0].position).is_equal_approx(world_px, TOL)


## 20 dp above the centre of row `row`: the tap point is not the unit's own position.
func _off_centre(row: int) -> Vector2:
	return _layer.unit_screen_position(row) - Vector2(0, UiScale.dp(20))


## A finger down and up at `at` (base px), then a pause past the double-tap time.
func _tap(at: Vector2) -> void:
	TouchEvents.press(get_viewport(), 0, at)
	_now_ms += 50
	_touch._process(0.0)  # The frame that sees a hold.
	TouchEvents.release(get_viewport(), 0, at)
	_now_ms += 1000
