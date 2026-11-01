extends GdUnitTestSuite
## Phase 2 combat end to end (plan P52): the main scene on a 6-inch Android phone (2400x1080), real
## touches pushed into the viewport (TouchInput, GestureRecognizer, PlayerController, the HUD
## buttons through the GUI), the real CommandQueue, the sim and every layer. Time is a fake clock
## and only run_ticks() moves the sim, one tick at a time, so each tick is looked at before the
## next. Blue tanks are ids 1-30 (rows 0-29), red ones 31-40 (rows 30-39); at tick 0 no red tank
## is in sight (the nearest is about 20 tiles from the block and a light tank sees 7), so a red rig
## is hidden and not pickable, a tap on it is a ground tap (P47p), and an ATTACK on an enemy the
## side does not see would be dropped (P46b). The cases therefore drive the whole block to the red
## group with a ground tap first and tap a red tank only once it is in sight. The fight case then
## plays tick by tick until that tank is dead and a blue tank is lost, at most 900 ticks.

const MenuRig: GDScript = preload("res://tests/support/menu_rig.gd")
const TouchEvents: GDScript = preload("res://tests/support/touch_events.gd")
const UiProfiles: GDScript = preload("res://tests/support/ui_profiles.gd")
const Lifts: GDScript = preload("res://tests/view/support/lifts.gd")
const PROFILE: StringName = &"android_6in"
const MAIN_SCENE: String = "res://scenes/main.tscn"
const BLUE: int = 1
const BLUE_TANKS: int = 30
const RED_FIRST_ROW: int = 30
const RED_ROWS: int = 10
## The plan's bound on the fight, and a bound on the drive that brings a red tank into sight (about
## 100 ticks at 120 milli-tiles a tick).
const FIGHT_TICKS: int = 900
const APPROACH_TICKS: int = 300
## The drive is not instant: a light tank covers 120 milli-tiles a tick and the block starts about
## 20 tiles from the red group.
const MIN_DRIVE_TICKS: int = 40
## The blue tanks nearest the target brought down to 1 hp before the tap: at the shipped numbers 30
## tanks kill four without losing one, so the fight needs a loss to prove the selection and the
## badge follow it.
const WOUNDED: int = 4
const BAND: String = "Hud/SafeArea/SelectionBand/SelectionPanel"

var _window_size_before: Vector2i
var _now_ms: int = 0
var _main: Node2D
var _runner: MatchRunner
var _layer: UnitLayer
var _camera: RtsCamera
var _touch: TouchInput
var _controller: PlayerController
var _effects: EffectsLayer
var _panel: SelectionPanel
var _scan: LogScan
var _sent: Array[Command] = []


## The errors the engine logs while a case plays, the lines scripts/verify.sh scans for (SCRIPT
## ERROR, ERROR:, Parse Error). Warnings are not in that scan.
class LogScan:
	extends Logger

	var hits: PackedStringArray = PackedStringArray()

	func _log_error(
		_function: String,
		file: String,
		line: int,
		code: String,
		rationale: String,
		_editor_notify: bool,
		error_type: int,
		_script_backtraces: Array[ScriptBacktrace]
	) -> void:
		if error_type != Logger.ERROR_TYPE_WARNING:
			hits.append("%s:%d %s %s" % [file, line, code, rationale])


func before() -> void:
	_window_size_before = get_window().size


func before_test() -> void:
	MenuRig.begin()
	_scan = LogScan.new()
	OS.add_logger(_scan)


## Nothing in the log matches the error scan. The override, queue, window size and logger are global
## and must not outlive the case. The scene goes first, so no live HUD sees the resize.
func after_test() -> void:
	MenuRig.end()
	assert_array(_scan.hits).is_empty()
	OS.remove_logger(_scan)
	if is_instance_valid(_main):
		_main.free()
	UiScale.clear_override()
	CommandQueue.clear()
	get_window().size = _window_size_before


func test_a_red_rig_in_the_fog_is_hidden_and_not_pickable_and_a_tap_on_it_moves_the_block() -> void:
	await _open()
	var pick: PickSnapshot = PickSnapshot.new()
	_layer.fill_pick_snapshot(pick, UiScale.dp(24.0))
	assert_int(pick.size()).is_equal(BLUE_TANKS + RED_ROWS)
	for row: int in range(RED_FIRST_ROW, RED_FIRST_ROW + RED_ROWS):
		assert_bool(_rig(row).visible).override_failure_message("rig %d" % row).is_false()
		assert_int(pick.pickable[row]).override_failure_message("pickable %d" % row).is_equal(0)
	for row: int in BLUE_TANKS:
		assert_bool(_rig(row).visible).is_true()
		assert_int(pick.pickable[row]).is_equal(1)
	_press_hud("AllArmy")
	assert_array(_controller.selection.selected).is_equal(range(1, BLUE_TANKS + 1))
	# The tap lands on the hidden tank's own screen position: it is the ground under it.
	_centre_on_rig(RED_FIRST_ROW)
	var at: Vector2 = _layer.unit_screen_position(RED_FIRST_ROW)
	await _tap(at)
	assert_array(_sent).has_size(1)
	assert_int(_sent[0].type).is_equal(Command.Type.MOVE)
	assert_array(_sent[0].unit_ids).is_equal(range(1, BLUE_TANKS + 1))
	var ground: Vector2i = IsoProjection.px_to_ground(_camera.screen_to_world(at))
	assert_int(_sent[0].target_x).is_equal(ground.x)
	assert_int(_sent[0].target_y).is_equal(ground.y)


func test_select_all_tap_a_visible_red_tank_and_fight_until_it_dies() -> void:
	await _open()
	_press_hud("AllArmy")
	_press_hud("Group1", _touch.settings.group_assign_ms)  # A hold assigns the 30.
	_assert_blue_left(range(1, BLUE_TANKS + 1))
	# The approach: a tap on the hidden red tank's ground drives the whole block there.
	_centre_on_rig(RED_FIRST_ROW)
	await _tap(_layer.unit_screen_position(RED_FIRST_ROW))
	var seen: int = _drive_until_a_red_rig_shows()
	assert_int(seen).override_failure_message("no red rig shown").is_greater_equal(RED_FIRST_ROW)
	var snap: MatchSnapshot = _runner.snapshot
	assert_int(snap.tick).override_failure_message("not at once").is_greater(MIN_DRIVE_TICKS)
	var target: int = snap.unit_id[seen]
	assert_bool(FogLayer.is_seen(snap, BLUE, snap.pos_x[seen], snap.pos_y[seen])).is_true()
	assert_bool(_layer.is_shown(seen)).is_true()
	var pick: PickSnapshot = PickSnapshot.new()
	_layer.fill_pick_snapshot(pick, UiScale.dp(24.0))
	assert_int(pick.pickable[seen]).is_equal(1)
	_wound_nearest_blue(snap, seen, WOUNDED)
	# The tap on the tank in sight is one ATTACK from the whole selection.
	_centre_on_rig(seen)
	await _tap(_layer.unit_screen_position(seen))
	assert_array(_sent).has_size(2)
	assert_int(_sent[0].type).is_equal(Command.Type.MOVE)
	var attack: Command = _sent[1]
	assert_int(attack.type).is_equal(Command.Type.ATTACK)
	assert_int(attack.player_id).is_equal(BLUE)
	assert_array(attack.unit_ids).is_equal(range(1, BLUE_TANKS + 1))
	assert_int(attack.target_id).is_equal(target)
	var lost: Array[int] = []
	var died_at: int = -1
	var fought: int = 0
	while fought < FIGHT_TICKS and (died_at < 0 or lost.is_empty()):
		fought += 1
		for record: PackedInt32Array in _tick():
			if record[1] == target:
				died_at = fought
				_assert_death_shown(record)
			elif record[5] == BLUE:
				lost.append(record[1])
		if fought == 1:
			_assert_ordered_to_attack(attack.unit_ids, target)
	assert_int(died_at).override_failure_message("the target lived").is_greater(0)
	assert_array(lost).override_failure_message("no blue tank died").is_not_empty()
	assert_int(_runner.world.dropped_commands).is_equal(0)
	var left: Array[int] = []
	for id: int in range(1, BLUE_TANKS + 1):
		if not lost.has(id):
			left.append(id)
	_assert_blue_left(left)


func _assert_panel(count: String) -> void:
	assert_bool(_panel.visible).is_true()
	assert_str((_panel.get_node("Rows/Row0/Name") as Label).text).is_equal("Flarejack")
	assert_str((_panel.get_node("Rows/Row0/Count") as Label).text).is_equal(count)


## The blue tanks `ids` are what is selected and what group 1 holds, and the panel and the badge
## show their number.
func _assert_blue_left(ids: Array) -> void:
	assert_array(_controller.selection.selected).is_equal(ids)
	assert_array(_controller.selection.group(1)).is_equal(ids)
	_assert_panel("×%d" % ids.size())
	assert_str((_hud("Group1") as Button).text).is_equal("1\n%d" % ids.size())


## Every unit of `ids` has the ATTACK order on `target` in the World, the tick after the tap.
func _assert_ordered_to_attack(ids: PackedInt32Array, target: int) -> void:
	var world: World = _runner.world
	for id: int in ids:
		var row: int = world.index_of(id)
		assert_int(world.order[row]).override_failure_message("unit %d" % id).is_equal(
			World.Order.ATTACK
		)
		assert_int(world.order_target[row]).is_equal(target)


## The tick that destroyed a tank: its rig is gone and the layer holds one rig per unit left, and
## a burst of the effects layer is planned on the place of its death, at the middle of a light
## tank's frame (ADR 0023 section 2: the sheet's `pick_lift_px` above its ground point).
func _assert_death_shown(record: PackedInt32Array) -> void:
	assert_object(_layer.get_node_or_null("Unit%d" % record[1])).is_null()
	assert_int(_layer.rig_count()).is_equal(_runner.snapshot.unit_id.size())
	var lift: float = Lifts.pick(&"light_tank")
	var place: Vector2 = IsoProjection.ground_to_px(record[2], record[3]) - Vector2(0.0, lift)
	var bursts: int = 0
	for index: int in _effects.quad_count():
		var at: Vector2 = _effects.quad_rect(index).get_center()
		if _effects.quad_region(index) == EffectsLayer.BURST and at.distance_to(place) < 0.01:
			bursts += 1
	assert_int(bursts).override_failure_message("burst of unit %d" % record[1]).is_equal(1)


func _hud(node_name: String) -> Control:
	return _main.get_node("Hud").find_child(node_name, true, false)


## The rig of unit row `row`, a child of the unit layer in row order.
func _rig(row: int) -> Node2D:
	return _layer.rig(row)


func _centre_on_rig(row: int) -> void:
	_camera.centre_on(_rig(row).position)


## One tick of the sim and the frame after it: the rigs and the effects follow the snapshot.
## Returns the DIED records of the tick, [DIED, unit id, x, y, type index, owner, 0, 0] each.
func _tick() -> Array[PackedInt32Array]:
	_runner.run_ticks(1)
	_layer._process(0.0)
	_effects._process(0.0)
	var found: Array[PackedInt32Array] = []
	var events: PackedInt32Array = _runner.snapshot.events
	for at: int in range(0, events.size(), World.EVENT_STRIDE):
		if events[at] == World.Event.DIED:
			found.append(events.slice(at, at + World.EVENT_STRIDE))
	return found


## Plays ticks until a red rig shows (at most APPROACH_TICKS) and returns its row, or -1.
func _drive_until_a_red_rig_shows() -> int:
	for _step: int in APPROACH_TICKS:
		_tick()
		for row: int in range(RED_FIRST_ROW, RED_FIRST_ROW + RED_ROWS):
			if _rig(row).visible:
				return row
	return -1


## Sets the `count` blue tanks nearest to unit row `row` of `snap` to 1 hp, as the World holds them.
func _wound_nearest_blue(snap: MatchSnapshot, row: int, count: int) -> void:
	var gap: Dictionary[int, int] = {}
	for blue: int in BLUE_TANKS:
		var dx: int = snap.pos_x[blue] - snap.pos_x[row]
		var dy: int = snap.pos_y[blue] - snap.pos_y[row]
		gap[blue] = dx * dx + dy * dy
	var rows: Array[int] = gap.keys()
	rows.sort_custom(
		func(a: int, b: int) -> bool: return gap[a] < gap[b] or (gap[a] == gap[b] and a < b)
	)
	for near: int in rows.slice(0, count):
		_runner.world.hp[near] = 1


## A new main scene on the phone profile with the fake clock; Commands are caught on their way to
## the real queue.
func _open() -> void:
	var metrics: UiMetrics = UiProfiles.by_name(PROFILE)
	UiScale.set_override(metrics)
	get_window().size = metrics.window_size
	await await_idle_frame()
	_main = auto_free((load(MAIN_SCENE) as PackedScene).instantiate())
	_runner = _main.get_node("MatchRunner")
	_runner.paused = true  # Only run_ticks() moves time.
	add_child(_main)
	await await_idle_frame()
	_layer = _main.get_node("UnitLayer")
	_camera = _main.get_node("Camera")
	_touch = _main.get_node("TouchInput")
	_controller = _main.get_node("PlayerController")
	_effects = _main.get_node("EffectsLayer")
	_panel = _main.get_node(BAND)
	_now_ms = 0
	_sent.clear()
	_touch.clock = func() -> int: return _now_ms
	_effects.clock = _touch.clock
	for slot: int in range(1, 4):
		(_hud("Group%d" % slot) as HoldButton).clock = _touch.clock
	assert_bool(_controller.command_sink == CommandQueue.submit).is_true()  # What the game ships.
	_controller.command_sink = func(command: Command) -> void:
		_sent.append(command)
		CommandQueue.submit(command)


## Fails when a map touch would start off screen or on a HUD Control. The HUD lays out on a frame,
## as on a phone.
func _assert_off_hud(at: Vector2) -> void:
	await await_idle_frame()
	var screen: Rect2 = get_viewport().get_visible_rect()
	assert_bool(screen.has_point(at)).override_failure_message("%s is off screen" % at).is_true()
	for node_name: String in ["SelectionPanel", "ArmyBar", "DevButton"]:
		var hud: Control = _hud(node_name)
		var why: String = "%s is on %s %s" % [at, node_name, hud.get_global_rect()]
		var under: bool = hud.is_visible_in_tree() and hud.get_global_rect().has_point(at)
		assert_bool(under).override_failure_message(why).is_false()


## A finger down and up at `at` (base px), then a pause past the double-tap time.
func _tap(at: Vector2) -> void:
	await _assert_off_hud(at)
	TouchEvents.press(get_viewport(), 0, at)
	_now_ms += 50
	TouchEvents.release(get_viewport(), 0, at)
	_now_ms += 1000


## A finger on a HUD button through the real GUI for `held_ms`. A HoldButton sees the hold on a
## frame while the finger rests, which `_process` stands in for.
func _press_hud(node_name: String, held_ms: int = 50) -> void:
	var control: Control = _hud(node_name)
	var at: Vector2 = control.get_global_rect().get_center()
	TouchEvents.press(get_viewport(), 0, at)
	_now_ms += held_ms
	if control is HoldButton:
		(control as HoldButton)._process(0.0)
	TouchEvents.release(get_viewport(), 0, at)
	_now_ms += 1000
