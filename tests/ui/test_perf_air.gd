extends GdUnitTestSuite
## The dev menu's "Perf air" button (plan row P253): it sits after "Perf AI", is at least 48 dp
## and opens the perf arena scene with the air arena (judged against `air_golden_*`).

const Rig: GDScript = preload("res://tests/ui/support/perf_hud_rig.gd")
const ArenaRig: GDScript = preload("res://tests/ui/support/arena_rig.gd")
const GATE: String = "res://data/dev/perf_gate.tres"
const MIN_DP: float = 48.0

var _calls: Array[String] = []
var _arenas: Array[Node2D] = []


func after_test() -> void:
	_arenas.reverse()
	for arena: Node2D in _arenas:
		if is_instance_valid(arena):
			ArenaRig.close(self, arena)
	_arenas.clear()
	_calls.clear()
	CommandQueue.clear()


func test_the_dev_menu_has_the_button_after_perf_ai_at_48_dp() -> void:
	assert_bool(ResourceLoader.exists(DevRoutes.PERF_AIR_SCENARIO)).is_true()
	var menu: Control = (load(DevRoutes.DEV_MENU_SCENE) as PackedScene).instantiate()
	add_child(menu)
	await await_idle_frame()
	var button: Button = menu.find_child("PerfAirButton", true, false)
	var ai: Button = menu.find_child("PerfAiButton", true, false)
	assert_str(button.text).is_equal("Perf air")
	assert_bool(button.disabled).is_false()
	assert_object(button.get_parent()).is_same(ai.get_parent())
	assert_int(button.get_index()).is_equal(ai.get_index() + 1)
	assert_float(button.get_combined_minimum_size().y).is_greater_equal(UiScale.dp(MIN_DP) - 0.5)
	remove_child(menu)
	menu.free()


func test_the_button_opens_the_perf_scene_with_the_air_arena() -> void:
	var tree: SceneTree = get_tree()
	var menu: Node = (load(DevRoutes.DEV_MENU_SCENE) as PackedScene).instantiate()
	tree.root.add_child(menu)
	tree.current_scene = menu
	await await_idle_frame()
	menu.find_child("PerfAirButton", true, false).pressed.emit()
	await await_idle_frame()
	var arena: Node = tree.current_scene
	assert_str(arena.scene_file_path).is_equal(DevRoutes.PERF_ARENA_SCENE)
	assert_str(arena.arena_kind).is_equal(PerfHud.ARENA_AIR)
	assert_str(arena.hud.arena_kind).is_equal(PerfHud.ARENA_AIR)
	assert_str(arena.scenario.resource_path).is_equal(DevRoutes.PERF_AIR_SCENARIO)
	arena.find_child("BackButton", true, false).pressed.emit()
	await await_idle_frame()
	assert_str(tree.current_scene.scene_file_path).is_equal(DevRoutes.DEV_MENU_SCENE)
	tree.current_scene.free()
	tree.current_scene = null


## The card's pair for the air arena is the gate's `air_golden_*` (not the bases pair or the
## arena's), its mismatch names those fields, and the scenario switch starts the air match.
func test_the_card_reads_the_air_pair_and_names_its_fields() -> void:
	var gate: PerfGateDef = load(GATE)
	assert_bool(PerfBases.has_golden(PerfHud.ARENA_AIR)).is_true()
	assert_array(PerfBases.ticks(gate, PerfHud.ARENA_AIR)).is_equal(gate.air_golden_ticks)
	assert_array(PerfBases.hexes(gate, PerfHud.ARENA_AIR)).is_equal(gate.air_golden_hex)
	assert_array(PerfBases.hexes(gate, PerfHud.ARENA_AIR)).is_not_equal(gate.bases_golden_hex)
	assert_array(PerfBases.hexes(gate, PerfHud.ARENA_AIR)).is_not_equal(gate.golden_hex)
	assert_array(PerfBases.hexes(gate, PerfHud.ARENA_BASES)).is_equal(gate.bases_golden_hex)
	assert_str(PerfBases.fields(PerfHud.ARENA_AIR)).is_equal(" (air_golden_ticks, air_golden_hex)")
	assert_str(PerfBases.fields(PerfHud.ARENA_BASES)).is_not_equal(
		PerfBases.fields(PerfHud.ARENA_AIR)
	)
	var arena: Node2D = _open(PerfHud.ARENA_AIR)
	assert_str(arena.scenario.resource_path).is_equal(DevRoutes.PERF_AIR_SCENARIO)
	assert_str(arena.hud.summary()["arena"]).is_equal("air")
	assert_object(arena.runner.snapshot).is_not_null()


func test_a_run_is_judged_by_the_air_pair_and_a_mismatch_names_its_fields() -> void:
	var gate: PerfGateDef = PerfGateDef.new()
	Rig.pin_golden(gate)  # The arena's pair: what the run would match if the card read it.
	for tick: int in range(150, 901, 150):
		gate.air_golden_ticks.append(tick)
		gate.air_golden_hex.append(World.hash_hex(Rig.last_hash(tick) + 1))
	var hud: PerfHud = auto_free(Rig.hud(gate))
	hud.arena_kind = PerfHud.ARENA_AIR
	Rig.pass_frames(hud)
	for tick: int in range(1, 901):
		var snap: MatchSnapshot = Rig.snapshot(tick)
		snap.last_hash += 1  # The air arena's hashes.
		hud.record_snapshot(snap)
	var s: Dictionary = hud.summary()
	assert_bool(s["golden_match"]).is_true()
	assert_int(s["golden_checked"]).is_equal(6)
	hud.arena_kind = PerfHud.ARENA_UNITS  # The same run, judged by the arena's pair, differs.
	assert_int(hud.summary()["golden_mismatch_tick"]).is_equal(150)
	hud.arena_kind = PerfHud.ARENA_BASES  # And by the bases' (empty here): nothing is checked.
	assert_int(hud.summary()["golden_checked"]).is_equal(0)
	gate.air_golden_hex[2] = "00000000000000ff"  # Tick 450.
	hud.arena_kind = PerfHud.ARENA_AIR
	var line: String = (
		"golden_hashes: FAIL (MISMATCH at tick 450, got %s, golden 00000000000000ff "
		+ "(air_golden_ticks, air_golden_hex))"
	)
	assert_array(hud.summary()["verdicts"]).contains(
		[line % World.hash_hex(Rig.last_hash(450) + 1)]
	)


func test_the_shipped_air_arena_matches_every_checkpoint_on_the_card() -> void:
	var gate: PerfGateDef = load(GATE)
	var runner: MatchRunner = auto_free(MatchRunner.new())
	runner.scenario = load(DevRoutes.PERF_AIR_SCENARIO)
	runner.match_seed = 42
	runner.start()
	var hud: PerfHud = auto_free(Rig.hud(gate))
	hud.runner = runner
	hud.arena_kind = PerfHud.ARENA_AIR
	hud.run_ticks = 900
	add_child(hud)
	hud.restart()
	for _tick: int in 900:
		runner.run_ticks(1)
	var s: Dictionary = hud.summary()
	assert_int(s["golden_checked"]).is_equal(6)
	assert_int(s["golden_mismatch_tick"]).is_equal(-1)
	assert_array(s["verdicts"]).contains(["golden_hashes: PASS (MATCH, 6 checkpoints)"])


## The acceptance of plan P253b: the air arena's run through the real view has a heavy window of
## `heavy_frames_min` frames (4 frames a tick at 60 fps and 15 Hz, as the bases test counts them),
## and the window needs both the flyers in the `rigs` column and `air_heavy_rigs`: with only the
## ground rigs of `UnitLayer` (the card before P253b) it holds no frame. A scripted frame loop: no
## real time is read, the frame's times are constants.
func test_the_air_arena_run_has_a_heavy_window_of_heavy_frames_min() -> void:
	var gate: PerfGateDef = load(GATE)
	var arena: Node2D = _open(PerfHud.ARENA_AIR)
	arena.runner.paused = true  # Only the loop's ticks run: 4 frames each.
	var hud: PerfHud = auto_free(Rig.hud(gate))
	hud.arena_kind = PerfHud.ARENA_AIR
	add_child(hud)
	hud.restart()
	var ground_only: int = 0
	for _tick: int in 900:
		arena.runner.run_ticks(1)
		for frame: int in 4:
			await get_tree().process_frame
			var view: Rect2 = arena.camera.visible_world_rect()
			ground_only += int(arena.unit_layer.count_in(view) >= gate.heavy_rigs)
			hud.record_frame(16667, 1000, 1000, 10, arena.drawn_rigs(), frame == 0, 1000, -1)
	var s: Dictionary = hud.summary()
	assert_int(s["drawn_rigs_max"]).is_greater_equal(gate.heavy_rigs)  # The flyers are counted.
	assert_int(s["heavy_frames"]).is_greater_equal(gate.heavy_frames_min)
	assert_int(s["heavy_publish_frames"]).is_greater(0)
	assert_int(ground_only).is_equal(0)


func _open(kind: String) -> Node2D:
	var arena: Node2D = ArenaRig.make(_calls)
	arena.arena_kind = kind
	add_child(arena)
	_arenas.append(arena)
	return arena
