extends GdUnitTestSuite
## The "Perf AI" route and its card (plan P185, ADR 0030 section 4): the dev menu button beside
## "Perf bases", the route into the perf arena scene on `perf_ai.tres` with a Normal `OpponentAi`
## on each player (`first_opponent` 1, the view stays player 1's), the card's report-only AI keys
## over fixed numbers (no timing is measured here), the card line only on this arena, and no golden
## comparison for it. The other two cards are unchanged: `test_perf_card_pin.gd` pins their text.

const Rig: GDScript = preload("res://tests/ui/support/perf_hud_rig.gd")
const ArenaRig: GDScript = preload("res://tests/ui/support/arena_rig.gd")

var _calls: Array[String] = []
var _arenas: Array[Node2D] = []
var _window_before: Vector2i = Vector2i.ZERO


func before_test() -> void:
	_window_before = get_window().size


func after_test() -> void:
	get_window().size = _window_before
	_arenas.reverse()
	for arena: Node2D in _arenas:
		if is_instance_valid(arena):
			ArenaRig.close(self, arena)
	_arenas.clear()
	_calls.clear()
	CommandQueue.clear()


func test_the_dev_menu_has_the_button_after_perf_bases() -> void:
	assert_bool(ResourceLoader.exists(DevRoutes.PERF_AI_SCENARIO)).is_true()
	var menu: Control = (load(DevRoutes.DEV_MENU_SCENE) as PackedScene).instantiate()
	add_child(menu)
	await await_idle_frame()
	var button: Button = menu.find_child("PerfAiButton", true, false)
	var bases: Button = menu.find_child("PerfBasesButton", true, false)
	assert_str(button.text).is_equal("Perf AI")
	assert_bool(button.disabled).is_false()
	assert_object(button.get_parent()).is_same(bases.get_parent())
	assert_int(button.get_index()).is_equal(bases.get_index() + 1)
	remove_child(menu)
	menu.free()


func test_the_button_opens_the_perf_scene_with_the_ai_arena_and_back_returns() -> void:
	var tree: SceneTree = get_tree()
	var menu: Node = (load(DevRoutes.DEV_MENU_SCENE) as PackedScene).instantiate()
	tree.root.add_child(menu)
	tree.current_scene = menu
	await await_idle_frame()
	var fps_before: int = Engine.max_fps
	menu.find_child("PerfAiButton", true, false).pressed.emit()
	await await_idle_frame()
	var arena: Node = tree.current_scene
	assert_str(arena.scene_file_path).is_equal(DevRoutes.PERF_ARENA_SCENE)
	assert_str(arena.arena_kind).is_equal(PerfHud.ARENA_AI)
	assert_str(arena.hud.arena_kind).is_equal(PerfHud.ARENA_AI)
	assert_str(arena.scenario.resource_path).is_equal(DevRoutes.PERF_AI_SCENARIO)
	arena.find_child("BackButton", true, false).pressed.emit()
	await await_idle_frame()
	assert_str(tree.current_scene.scene_file_path).is_equal(DevRoutes.DEV_MENU_SCENE)
	assert_int(Engine.max_fps).is_equal(fps_before)
	tree.current_scene.free()
	tree.current_scene = null


func test_the_arena_seats_two_normal_opponent_ais_on_players_one_and_two() -> void:
	var arena: Node2D = _open(PerfHud.ARENA_AI)
	var runner: MatchRunner = arena.runner
	assert_int(runner.first_opponent).is_equal(1)
	assert_int(runner.opponents.size()).is_equal(2)
	for def: AiDef in runner.opponents:
		assert_object(def).is_instanceof(OpponentDef)
	var paths: Array = runner.opponents.map(func(def: AiDef) -> String: return def.resource_path)
	assert_array(paths).is_equal([DevRoutes.OPPONENT_FOSSIL, DevRoutes.OPPONENT_RENEW])
	assert_int(runner.opponent_levels.size()).is_equal(2)
	for level: AiDifficultyDef in runner.opponent_levels:
		assert_str(level.resource_path).is_equal(DevRoutes.LEVEL_NORMAL)
	assert_object(runner.scenario).is_same(arena.scenario)
	assert_int(FogLayer.local_player_of(runner)).is_equal(1)
	var players: Array[int] = []
	for controller: AiController in runner._job.controllers:
		assert_object(controller).is_instanceof(OpponentAi)
		players.append(controller.player_id)
	assert_array(players).is_equal([1, 2])


func test_the_other_arenas_seat_no_computer() -> void:
	for kind: String in [PerfHud.ARENA_UNITS, PerfHud.ARENA_BASES]:
		var arena: Node2D = _open(kind)
		assert_int(arena.runner.opponents.size()).is_equal(0)
		assert_int(arena.runner.first_opponent).is_equal(MatchRunner.FIRST_OPPONENT)


func test_the_keys_come_from_the_ticks_on_which_a_computer_thought() -> void:
	var hud: PerfHud = auto_free(Rig.hud())
	hud.arena_kind = PerfHud.ARENA_AI
	Rig.pass_frames(hud)
	# Twenty think ticks of 1 to 20 ms among 880 ticks with none (think_usec 0, not counted).
	for tick: int in range(1, 901):
		var snap: MatchSnapshot = Rig.snapshot(tick)
		if tick <= 20:
			snap.think_usec = tick * 1000
		hud.record_snapshot(snap)
	var s: Dictionary = hud.summary()
	assert_int(s["ai_thinks"]).is_equal(20)
	assert_float(s["ai_think_max_ms"]).is_equal(20.0)
	assert_float(s["ai_think_p95_ms"]).is_between(19.0, 20.0)


func test_a_run_without_thinks_reports_zeros_on_every_arena() -> void:
	for kind: String in [PerfHud.ARENA_UNITS, PerfHud.ARENA_BASES, PerfHud.ARENA_AI]:
		var hud: PerfHud = auto_free(Rig.hud())
		hud.arena_kind = kind
		Rig.run(hud)
		var s: Dictionary = hud.summary()
		assert_int(s["ai_thinks"]).is_equal(0)
		assert_float(s["ai_think_p95_ms"]).is_equal(0.0)
		assert_float(s["ai_think_max_ms"]).is_equal(0.0)


func test_the_card_prints_the_ai_line_for_this_arena_only() -> void:
	var hud: PerfHud = auto_free(Rig.hud())
	hud.arena_kind = PerfHud.ARENA_AI
	Rig.pass_frames(hud)
	for tick: int in range(1, 901):
		var snap: MatchSnapshot = Rig.snapshot(tick)
		snap.think_usec = 500 if tick % 5 == 0 else 0
		if tick == 450:
			snap.think_usec = 2_500
		hud.record_snapshot(snap)
	var line: String = (
		"ai_think_p95_ms 0.50 | ai_think_max_ms 2.50 | ai_thinks 180 | watch p95 at or below "
		+ "1.00 ms (no verdict)"
	)
	assert_array(Array(hud.card_lines())).contains([line])
	for verdict: String in hud.summary()["verdicts"]:
		assert_bool(verdict.begins_with("ai_think")).is_false()
	for kind: String in [PerfHud.ARENA_UNITS, PerfHud.ARENA_BASES]:
		var other: PerfHud = auto_free(Rig.hud())
		other.arena_kind = kind
		Rig.run(other)
		for text: String in other.card_lines():
			assert_bool(text.begins_with("ai_think")).is_false()


func test_no_golden_comparison_and_the_usual_verdicts_with_the_same_thresholds() -> void:
	var gate: PerfGateDef = PerfGateDef.new()  # No bases pair, and the arena's one never matches.
	var ai: PerfHud = auto_free(Rig.hud(gate))
	ai.arena_kind = PerfHud.ARENA_AI
	Rig.pass_frames(ai)
	for tick: int in range(1, 901):
		var snap: MatchSnapshot = Rig.snapshot(tick)
		snap.last_hash += 1  # A hash no golden pair would match.
		ai.record_snapshot(snap)
	var s: Dictionary = ai.summary()
	assert_int(s["golden_checked"]).is_equal(0)
	assert_bool(s["golden_match"]).is_false()  # Nothing was compared: no claim of a match.
	assert_int(s["golden_mismatch_tick"]).is_equal(-1)
	assert_array(s["verdicts"]).contains(["golden_hashes: n/a (this arena has no golden pair)"])
	assert_array(Rig.failed(s)).is_empty()
	assert_bool(s["gate_pass"]).is_true()
	# The verdict rows are the units arena's, name for name, judged against the same gate.
	var units: PerfHud = auto_free(Rig.hud())
	Rig.run(units)
	var names: Callable = func(lines: Array) -> Array:
		return lines.map(func(l: String) -> String: return l.get_slice(":", 0))
	assert_array(names.call(s["verdicts"])).is_equal(names.call(units.summary()["verdicts"]))
	# A slow job still fails its usual verdict on this arena.
	var slow: PerfHud = auto_free(Rig.hud())
	slow.arena_kind = PerfHud.ARENA_AI
	Rig.pass_frames(slow)
	Rig.ticks(slow, slow.run_ticks, 900, 40_000)
	assert_array(Rig.failed(slow.summary())).contains(["sim_p95_ms"])


func test_a_started_ai_match_thinks_and_publishes_its_think_time() -> void:
	var arena: Node2D = _open(PerfHud.ARENA_AI)
	var runner: MatchRunner = arena.runner
	var thinks: int = 0
	for _i: int in 30:
		runner.run_ticks(1)
		var snap: MatchSnapshot = runner.snapshot
		if snap.think_usec > 0:
			thinks += 1
			# No think falls on a checkpoint tick (ADR 0030 section 2).
			assert_int(snap.tick % Replay.CHECKPOINT_PERIOD).is_not_equal(0)
	assert_int(thinks).is_equal(12)  # Two AIs, six think ticks of every 15.


## An arena of `kind` in the tree with its slow seams stubbed; freed with the case.
func _open(kind: String) -> Node2D:
	var arena: Node2D = ArenaRig.make(_calls)
	arena.arena_kind = kind
	add_child(arena)
	_arenas.append(arena)
	return arena
