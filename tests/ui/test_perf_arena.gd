extends GdUnitTestSuite
## The perf arena scene (plan P50b, ADR 0011 section 5, ADR 0013 section 3, ADR 0014 section 3),
## headless: what it does on entry and exit (the frame cap and the screen kept on, through an
## injected sink), what the view starts with (every player-1 unit selected for the view and no
## Command), which layers reveal the enemy, the two AUTO modes of both scenes (headless, AUTO is
## SYNC and, with the library loaded, NATIVE, so the Phase 1 scene suites stay synchronous), the
## order of the card's preflight against the runner's start, "Run again" and the layer-mode
## selector. The card's own behaviour is test_perf_hud*.gd's; the layout at three sizes is
## test_perf_arena_layout.gd's. The seams that would run a 0.4 s burst and a 60-tick self-check are
## replaced by the rig's, which log the state of the runner they run in.

const Rig: GDScript = preload("res://tests/ui/support/arena_rig.gd")
const SimImpls: GDScript = preload("res://tests/sim/support/sim_impls.gd")
const AUTO_MODE: int = MatchRunner.TickMode.AUTO
const AUTO_IMPL: int = MatchRunner.SimImpl.AUTO
const OTHER_FPS: int = 144
## The layers a mode shows, in the order fog, bars, projectiles, effects.
const SHOWN: Dictionary[String, Array] = {
	"all": [true, true, true, true],
	"no fog": [false, true, true, true],
	"no bars": [true, false, true, true],
	"no effects": [true, true, false, false],
	"rigs only": [false, false, false, false],
}

var _calls: Array[String] = []
var _max_fps_before: int = 0
var _workers_before: int = 0
var _arenas: Array[Node2D] = []


func before_test() -> void:
	_max_fps_before = Engine.max_fps
	_workers_before = MatchRunner.live_workers()
	CommandQueue.clear()


## Every arena is freed (which restores the frame cap), so no case leaves a cap or a worker behind.
func after_test() -> void:
	_arenas.reverse()  # The last one in is the first out: each restores the cap it found.
	for arena: Node2D in _arenas:
		if is_instance_valid(arena):
			Rig.close(self, arena)
	_arenas.clear()
	_calls.clear()
	assert_int(Engine.max_fps).is_equal(_max_fps_before)
	assert_int(MatchRunner.live_workers()).is_equal(_workers_before)
	CommandQueue.clear()


func test_entering_caps_the_frame_rate_and_keeps_the_screen_on_and_leaving_restores_both() -> void:
	Engine.max_fps = OTHER_FPS
	var kept: Array[bool] = []
	var arena: Node2D = _make()
	arena.keep_on_source = func() -> bool: return true  # The engine's default: the screen is on.
	arena.keep_on_sink = func(on: bool) -> void: kept.append(on)
	assert_int(Engine.max_fps).is_equal(OTHER_FPS)  # Not in the tree yet.
	assert_array(kept).is_empty()
	add_child(arena)
	assert_int(Engine.max_fps).is_equal(60)  # Read back directly, headless too.
	assert_array(kept).is_equal([true])
	remove_child(arena)
	assert_int(Engine.max_fps).is_equal(OTHER_FPS)
	assert_array(kept).is_equal([true, true])  # Put back as found: not switched off.
	arena.free()
	Engine.max_fps = _max_fps_before


func test_leaving_puts_the_keep_screen_on_state_back_as_it_was_found() -> void:
	for before: bool in [true, false]:
		var kept: Array[bool] = []
		var arena: Node2D = _make()
		arena.keep_on_source = func() -> bool: return before
		arena.keep_on_sink = func(on: bool) -> void: kept.append(on)
		add_child(arena)
		assert_array(kept).is_equal([true])  # On while the arena is up, whatever it was.
		remove_child(arena)
		assert_array(kept).override_failure_message("found %s" % before).is_equal([true, before])
		arena.free()


func test_every_player_1_unit_starts_selected_and_no_command_is_submitted() -> void:
	var arena: Node2D = _open()
	# Before any frame: a Command that _ready submitted after the runner's start is still queued.
	assert_int(CommandQueue.pending()).is_equal(0)
	await await_idle_frame()
	await await_idle_frame()
	var runner: MatchRunner = arena.runner
	var units: UnitLayer = arena.unit_layer
	var snap: MatchSnapshot = runner.snapshot
	assert_int(snap.unit_count()).is_equal(150)
	var ringed: int = 0
	for row: int in snap.unit_count():
		var own: bool = snap.owner[row] == 1
		assert_bool(units.is_ringed(row)).override_failure_message("row %d" % row).is_equal(own)
		ringed += int(own)
	assert_int(ringed).is_equal(75)
	# A tick drains the queue into the match, so the queue alone proves little: one more tick makes
	# any Command a frame submitted reach the match, whose replay records every one it stepped.
	runner.run_ticks(1)
	assert_int(CommandQueue.pending()).is_equal(0)
	_assert_the_log_holds_only_the_scenario_orders(runner)
	assert_array(arena.find_children("*", "PlayerController", true, false)).is_empty()
	var touch: TouchInput = arena.get_node("TouchInput")
	assert_object(touch.controller).is_null()  # A finger pans and zooms; it issues nothing.
	assert_object(touch.camera).is_same(arena.camera)


func test_the_arena_runs_the_seed_42_scenario_started_by_its_own_ready() -> void:
	var arena: Node2D = _open()
	var runner: MatchRunner = arena.runner
	assert_str(runner.scenario.resource_path).is_equal("res://data/scenarios/perf_arena.tres")
	assert_int(runner.match_seed).is_equal(42)
	assert_int(runner.match_serial).is_equal(1)  # One start: the arena's, and no other.
	assert_int(runner.snapshot.tick).is_equal(0)
	assert_str(str(arena.hud.get_path_to(runner))).is_equal("../../../../MatchRunner")
	assert_object(arena.hud.runner).is_same(runner)
	assert_str(arena.hud.gate.resource_path).is_equal("res://data/dev/perf_gate.tres")


func test_the_three_layers_with_the_export_reveal_enemies_in_the_arena_and_not_in_the_main(
) -> void:
	var arena: Node2D = auto_free(Rig.make(_calls))
	var main: Node2D = await _open_main()
	assert_bool(arena.unit_layer.reveal_enemies).is_true()
	assert_bool(arena.projectile_layer.reveal_enemies).is_true()
	assert_bool(arena.effects_layer.reveal_enemies).is_true()
	assert_bool((main.get_node("UnitLayer") as UnitLayer).reveal_enemies).is_false()
	assert_bool((main.get_node("ProjectileLayer") as ProjectileLayer).reveal_enemies).is_false()
	assert_bool((main.get_node("EffectsLayer") as EffectsLayer).reveal_enemies).is_false()
	# The bars have no export: they follow the unit layer's is_shown().
	assert_object(arena.bar_layer.unit_layer).is_same(arena.unit_layer)
	var fog: FogLayer = arena.fog_layer
	assert_array([fog.z_index, fog.z_as_relative]).is_equal([4, false])
	assert_object(fog.runner).is_same(arena.runner)
	assert_array([arena.projectile_layer.z_index, arena.effects_layer.z_index]).is_equal([120, 130])
	assert_int(arena.bar_layer.z_index).is_equal(110)


func test_both_scenes_run_auto_modes_which_headless_are_sync_and_native() -> void:
	var arena: Node2D = _open()
	var main: Node2D = await _open_main()
	var runners: Array[MatchRunner] = [arena.runner, main.get_node("MatchRunner")]
	for runner: MatchRunner in runners:
		assert_int(runner.tick_mode).is_equal(AUTO_MODE)
		assert_int(runner.sim_impl).is_equal(AUTO_IMPL)
		assert_bool(runner.worker_active()).is_false()  # AUTO is SYNC headless.
		var world: World = runner.world
		(
			assert_object(world.kernels)
			. override_failure_message("SimKernels is not loaded")
			. is_not_null()
		)
		assert_int(world.native_phases).is_equal(SimImpls.expected_mask())  # AUTO is NATIVE here.
	assert_int(MatchRunner.live_workers()).is_equal(_workers_before)


func test_the_preflight_runs_the_self_check_then_the_burst_then_the_runner_starts_then_the_card(
) -> void:
	var arena: Node2D = _open()
	(
		assert_array(_calls)
		. is_equal(
			[
				"self_check job=false world=null serial=0",
				"burst job=false world=null serial=0",
				"restart serial=1",
			]
		)
	)
	var hud: PerfHud = arena.hud
	var s: Dictionary = hud.summary()
	assert_float(s["ref_peak_us"]).is_equal(25.0)  # The burst's peak reached the run.
	assert_str(s["self_check"]).is_equal(PerfHud.SELF_CHECK_NOT_RUN)
	assert_int(s["runs"]).is_equal(1)
	assert_array(s["invalid_reasons"]).is_empty()
	assert_bool(hud.visible).is_false()  # The card shows when the run ends.


func test_run_again_runs_the_burst_alone_before_the_runner_restarts_on_the_same_seed() -> void:
	var arena: Node2D = _open()
	var runner: MatchRunner = arena.runner
	runner.run_ticks(Replay.CHECKPOINT_PERIOD)
	var first: int = runner.last_hash
	assert_int(first).is_not_equal(0)
	_calls.clear()
	var again: Button = arena.hud.get_node("Column/Buttons/RunAgain")
	again.pressed.emit()
	# The burst once and no self-check, with the old match's World but no job, and the restart of
	# the card after the runner's start.
	assert_array(_calls).is_equal(["burst job=false world=set serial=1", "restart serial=2"])
	assert_int(runner.match_serial).is_equal(2)
	assert_int(runner.match_seed).is_equal(42)
	assert_int(runner.snapshot.tick).is_equal(0)
	runner.run_ticks(Replay.CHECKPOINT_PERIOD)
	assert_int(runner.last_hash).is_equal(first)
	assert_int(arena.hud.summary()["runs"]).is_equal(2)
	await await_idle_frame()
	var units: UnitLayer = arena.unit_layer
	var snap: MatchSnapshot = runner.snapshot
	for row: int in snap.unit_count():  # The new match's rigs are selected again.
		assert_bool(units.is_ringed(row)).is_equal(snap.owner[row] == 1)
	runner.run_ticks(1)  # Whatever a frame of the restarted match queued reaches the match.
	assert_int(CommandQueue.pending()).is_equal(0)
	_assert_the_log_holds_only_the_scenario_orders(runner)  # The restarted match took none either.


func test_the_layer_mode_selector_switches_layers_without_touching_the_hash() -> void:
	var reference: Node2D = _open()
	reference.runner.run_ticks(Replay.CHECKPOINT_PERIOD)
	var want: int = reference.runner.last_hash
	var arena: Node2D = _open()
	var runner: MatchRunner = arena.runner
	var layers: Array[CanvasItem] = [
		arena.fog_layer, arena.bar_layer, arena.projectile_layer, arena.effects_layer
	]
	var modes: Array = SHOWN.keys()
	for mode: String in modes:  # Five modes, three ticks each: the 15th tick is the checkpoint.
		arena.set_layer_mode(mode)
		var shown: Array = SHOWN[mode]
		for at: int in layers.size():
			assert_bool(layers[at].visible).override_failure_message("%s %d" % [mode, at]).is_equal(
				shown[at]
			)
		assert_str(arena.layer_mode).is_equal(mode)
		assert_str(arena.hud.layer_mode).is_equal(mode)  # The card prints it.
		assert_str((arena.layers_button as Button).text).is_equal("Layers: %s" % mode)
		runner.run_ticks(3)
	assert_int(runner.snapshot.tick).is_equal(Replay.CHECKPOINT_PERIOD)
	assert_int(runner.last_hash).is_equal(want)
	arena.set_layer_mode("sideways")  # Unknown: nothing changes.
	assert_str(arena.layer_mode).is_equal("rigs only")


func test_the_layers_button_steps_the_mode_and_every_step_is_a_new_run() -> void:
	var arena: Node2D = _open()
	var button: Button = arena.layers_button
	var hud: PerfHud = arena.hud
	assert_str(button.text).is_equal("Layers: all")
	var order: Array[String] = []
	for press: int in 6:  # Five modes and back to the first.
		button.pressed.emit()
		order.append(arena.layer_mode)
		assert_int(hud.summary()["runs"]).is_equal(press + 2)
		assert_int(arena.runner.match_serial).is_equal(press + 2)
	assert_array(order).is_equal(["no fog", "no bars", "no effects", "rigs only", "all", "no fog"])
	assert_str(hud.summary()["layer_mode"]).is_equal("no fog")
	var order_of_modes: Array[String] = []
	var mode: String = "all"
	for _step: int in 5:
		mode = Rig.ArenaScript.next_mode(mode)
		order_of_modes.append(mode)
	assert_array(order_of_modes).is_equal(["no fog", "no bars", "no effects", "rigs only", "all"])


## The replay of the runner's match holds the scenario's own orders (an attack-move for each
## player at tick 0) and nothing else: a Command that the arena submitted and a tick applied would
## be one more entry.
func _assert_the_log_holds_only_the_scenario_orders(runner: MatchRunner) -> void:
	var data: PackedInt32Array = runner.replay.commands
	var orders: Array[OrderDef] = runner.scenario.orders
	var logged: Array[Command] = []
	var at: int = 0
	while at >= 0 and at < data.size():
		var command: Command = Command.new()
		at = Command.decode(data, at, command)
		logged.append(command)
	assert_int(at).override_failure_message("the log does not decode").is_equal(data.size())
	assert_int(logged.size()).is_equal(orders.size())
	for index: int in mini(logged.size(), orders.size()):
		var seen: Array[int] = [logged[index].tick, logged[index].player_id, logged[index].type]
		var want: Array[int] = [orders[index].tick, orders[index].player, orders[index].type]
		assert_array(seen).override_failure_message("order %d" % index).is_equal(want)


## An arena in the tree with its seams logging into `_calls`; freed with the case.
func _open() -> Node2D:
	var arena: Node2D = Rig.open(self, _calls)
	_arenas.append(arena)
	return arena


## The main scene in the tree for a frame, freed with the case.
func _open_main() -> Node2D:
	var main: Node2D = auto_free((load(Rig.MAIN_SCENE) as PackedScene).instantiate() as Node2D)
	add_child(main)
	await await_idle_frame()
	return main


## An arena outside the tree.
func _make() -> Node2D:
	var arena: Node2D = Rig.make(_calls)
	_arenas.append(arena)
	return arena
