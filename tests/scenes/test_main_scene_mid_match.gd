extends GdUnitTestSuite
## The main scene entering the tree at tick N (plan P516, ADR 0042 section 6 step 4): a match with a
## fight in its past is restored off the tree by the Restorer and then added, paused. The view has
## only ever met a first snapshot at tick 0; here it meets one at tick N and must start from it
## without an error: the layers hold the same rigs as a view that watched the match tick by tick,
## and nothing of the past is replayed (no shot, impact or collapse effect, no crater). The two
## views then play on and keep the same rigs and the same World hash. Ticks are counted, never
## timed. A script error would end up in the log that scripts/verify.sh scans.

const MenuRig: GDScript = preload("res://tests/support/menu_rig.gd")
const MAIN_SCENE: String = "res://scenes/main.tscn"
const SCENARIO: String = "res://data/scenarios/controls_test.tres"
const BLUE: int = 1
const RED: int = 2
const BLUE_UNITS: int = 30
const FIGHT_LIMIT: int = 900
const AFTER_KILL: int = 20
const MORE: int = 30
const SLICE_TICKS: int = 64
const FRAME_LIMIT: int = 400
const BASE_SIZE: Vector2i = Vector2i(1280, 720)

var _window_size_before: Vector2i
var _clock: int = 0
var _blue: PackedInt32Array = PackedInt32Array()
var _target: Vector2i = Vector2i.ZERO


func before() -> void:
	_window_size_before = get_window().size


func after() -> void:
	get_window().size = _window_size_before


func before_test() -> void:
	MenuRig.begin()
	get_window().size = BASE_SIZE
	_clock = 0
	CommandQueue.clear()


func after_test() -> void:
	ResumeWatcher.restoring = false
	AudioService.clear_mute_reason(AudioService.REASON_RESTORING)
	CommandQueue.clear()
	MenuRig.end()


func _setup() -> MatchSetup:
	var setup: MatchSetup = MatchSetup.new()
	setup.scenario_path = SCENARIO
	setup.match_seed = 77
	return setup


## The one order of the match: the whole blue block drives to the red group at tick 0.
func _order() -> Command:
	return Command.move(BLUE, _blue, _target.x, _target.y)


## Reads the blue ids and the red group's centre from `snap` (tick 0).
func _aim(snap: MatchSnapshot) -> void:
	_blue = PackedInt32Array()
	var sum: Vector2i = Vector2i.ZERO
	var reds: int = 0
	for row: int in snap.unit_count():
		if snap.owner[row] == BLUE:
			_blue.append(snap.unit_id[row])
		elif snap.owner[row] == RED:
			sum += Vector2i(snap.pos_x[row], snap.pos_y[row])
			reds += 1
	assert_int(_blue.size()).is_equal(BLUE_UNITS)
	assert_int(reds).is_greater(0)
	_target = sum / reds


func _died(snap: MatchSnapshot) -> bool:
	for at: int in range(0, snap.events.size(), World.EVENT_STRIDE):
		if snap.events[at] == World.Event.DIED:
			return true
	return false


## Plays a bare runner until a unit has died, then AFTER_KILL ticks more; returns the file's bytes
## and the tick it was written at.
func _fight_file() -> Array:
	var runner: MatchRunner = auto_free(MatchRunner.new())
	var setup: MatchSetup = _setup()
	assert_int(setup.apply(runner)).is_equal(OK)
	runner.start()
	_aim(runner.snapshot)
	CommandQueue.submit(_order())
	var killed: int = -1
	while (
		runner.snapshot.tick < FIGHT_LIMIT
		and (killed < 0 or runner.snapshot.tick < killed + AFTER_KILL)
	):
		runner.run_ticks(1)
		if killed < 0 and _died(runner.snapshot):
			killed = runner.snapshot.tick
	assert_int(killed).override_failure_message("no unit died in the fight").is_greater(0)
	var tick: int = runner.snapshot.tick
	var bytes: PackedByteArray = ResumeStore.encode(
		setup,
		runner.replay,
		tick,
		runner.world.defs_hash(),
		ResumeStore.app_version(),
		runner.world.state_hash()
	)
	CommandQueue.clear()
	return [bytes, tick]


func _packed() -> PackedScene:
	return load(MAIN_SCENE) as PackedScene


## A view that watched the match: the main scene in the tree from tick 0, its runner paused so only
## run_ticks() moves it, played to `tick` with the order. Returns the largest number of live
## effects it showed on the way, in `peak[0]`.
func _watched(tick: int, peak: Array[int]) -> Node:
	var main: Node = auto_free(_packed().instantiate())
	var runner: MatchRunner = main.get_node("MatchRunner")
	assert_int(_setup().apply(runner)).is_equal(OK)
	runner.paused = true
	add_child(main)
	await await_idle_frame()
	var effects: EffectsLayer = main.get_node("EffectsLayer")
	CommandQueue.submit(_order())
	while runner.snapshot.tick < tick:
		runner.run_ticks(1)
		peak[0] = maxi(peak[0], effects.active_count())
	CommandQueue.clear()
	return main


func _restored(bytes: PackedByteArray) -> Node:
	var data: ResumeData = ResumeStore.decode(
		bytes, ResumeStore.app_version(), ResumeStore.ANY_DEFS_HASH
	)
	assert_object(data).is_not_null()
	var main: Node = auto_free(_packed().instantiate())
	var restorer: Restorer = auto_free(Restorer.new())
	restorer.clock = func() -> int:
		_clock += 1
		return _clock
	restorer.slice_usec = SLICE_TICKS
	assert_int(restorer.begin(data, main)).is_equal(OK)
	var done: Array[Error] = []
	restorer.finished.connect(func(result: Error) -> void: done.append(result))
	for _frame: int in FRAME_LIMIT:
		if not done.is_empty():
			break
		restorer._process(0.0)
	assert_array(done).is_equal([OK])
	add_child(main)
	restorer.hand_over(main)
	return main


func _layer_counts(main: Node) -> Array[int]:
	return [
		(main.get_node("UnitLayer") as UnitLayer).rig_count(),
		(main.get_node("BuildingLayer") as BuildingLayer).building_count(),
		(main.get_node("AirLayer") as AirLayer).rig_count(),
	]


func test_the_view_starts_at_tick_n_with_the_watched_views_rigs_and_none_of_the_past() -> void:
	var file: Array = _fight_file()
	var tick: int = file[1]
	var peak: Array[int] = [0]
	var watched: Node = await _watched(tick, peak)
	assert_int(peak[0]).override_failure_message("the fight showed no effect").is_greater(0)
	var main: Node = _restored(file[0])
	await await_idle_frame()
	await await_idle_frame()
	var runner: MatchRunner = main.get_node("MatchRunner")
	var control: MatchRunner = watched.get_node("MatchRunner")
	assert_int(runner.snapshot.tick).is_equal(tick)
	assert_bool(runner.paused).is_true()
	assert_int(runner.world.state_hash()).is_equal(control.world.state_hash())
	assert_array(_layer_counts(main)).is_equal(_layer_counts(watched))
	assert_int((main.get_node("UnitLayer") as UnitLayer).rig_count()).is_greater(0)
	# Nothing of the past is drawn: no effect lives and no crater lies on the ground.
	var effects: EffectsLayer = main.get_node("EffectsLayer")
	assert_int(effects.active_count()).is_equal(0)
	assert_int(effects.line_count()).is_equal(0)
	assert_int(effects.quad_count()).is_equal(0)
	assert_int((main.get_node("DecalLayer") as DecalLayer).crater_count()).is_equal(0)
	assert_bool(AudioService.has_mute_reason(AudioService.REASON_RESTORING)).is_false()
	# Both views play on: the same rigs and the same World.
	for _i: int in MORE:
		runner.run_ticks(1)
		control.run_ticks(1)
	await await_idle_frame()
	assert_int(runner.snapshot.tick).is_equal(tick + MORE)
	assert_int(runner.world.state_hash()).is_equal(control.world.state_hash())
	assert_array(_layer_counts(main)).is_equal(_layer_counts(watched))
