extends GdUnitTestSuite
## The "Perf bases" route and the base arena in the perf arena scene (plan P93c, ADR 0021, ADR 0023
## section 2): the dev menu has the route beside "Perf arena", the scenario switch loads P80's base
## arena on the same card machinery, the card checks its checkpoints against the gate's
## `bases_golden_ticks` and `bases_golden_hex` (and a mismatch names them), the report carries
## `atlas_bake_ms`, the camera holds every sprite inside the diamond and the card prints the
## draw-call forecast. The seed-42 arena's card is unchanged: its fields are `golden_*`.

const Rig: GDScript = preload("res://tests/ui/support/perf_hud_rig.gd")
const ArenaRig: GDScript = preload("res://tests/ui/support/arena_rig.gd")
const ScreenSizes: GDScript = preload("res://tests/support/screen_sizes.gd")
const GATE: String = "res://data/dev/perf_gate.tres"

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


func test_the_route_has_a_scenario_and_the_dev_menu_a_button_beside_perf_arena() -> void:
	assert_bool(ResourceLoader.exists(DevRoutes.PERF_BASES_SCENARIO)).is_true()
	assert_object(load(DevRoutes.PERF_BASES_SCENARIO)).is_instanceof(ScenarioDef)
	var menu: Control = (load(DevRoutes.DEV_MENU_SCENE) as PackedScene).instantiate()
	add_child(menu)
	await await_idle_frame()
	var bases: Button = menu.find_child("PerfBasesButton", true, false)
	var arena: Button = menu.find_child("PerfArenaButton", true, false)
	assert_str(bases.text).is_equal("Perf bases")
	assert_bool(bases.disabled).is_false()
	assert_object(bases.get_parent()).is_same(arena.get_parent())
	assert_int(bases.get_index()).is_equal(arena.get_index() + 1)
	remove_child(menu)
	menu.free()


func test_the_route_opens_the_perf_arena_scene_with_the_base_arena_and_back_returns() -> void:
	var tree: SceneTree = get_tree()
	var menu: Node = (load(DevRoutes.DEV_MENU_SCENE) as PackedScene).instantiate()
	tree.root.add_child(menu)
	tree.current_scene = menu
	await await_idle_frame()
	var fps_before: int = Engine.max_fps
	menu.find_child("PerfBasesButton", true, false).pressed.emit()
	await await_idle_frame()
	var arena: Node = tree.current_scene
	assert_str(arena.scene_file_path).is_equal(DevRoutes.PERF_ARENA_SCENE)
	assert_str(arena.arena_kind).is_equal(PerfHud.ARENA_BASES)
	assert_str(arena.scenario.resource_path).is_equal(DevRoutes.PERF_BASES_SCENARIO)
	assert_str(arena.hud.arena_kind).is_equal(PerfHud.ARENA_BASES)
	arena.find_child("BackButton", true, false).pressed.emit()
	await await_idle_frame()
	assert_str(tree.current_scene.scene_file_path).is_equal(DevRoutes.DEV_MENU_SCENE)
	assert_int(Engine.max_fps).is_equal(fps_before)
	tree.current_scene.free()
	tree.current_scene = null


func test_perf_arena_keeps_its_own_scenario_and_fields() -> void:
	var arena: Node2D = _open(PerfHud.ARENA_UNITS)
	assert_str(arena.scenario.resource_path).is_equal("res://data/scenarios/perf_arena.tres")
	assert_str(arena.hud.arena_kind).is_equal(PerfHud.ARENA_UNITS)
	var gate: PerfGateDef = arena.hud.gate
	assert_array(PerfBases.ticks(gate, arena.hud.arena_kind)).is_equal(gate.golden_ticks)
	assert_array(PerfBases.hexes(gate, arena.hud.arena_kind)).is_equal(gate.golden_hex)
	assert_array(PerfBases.ticks(gate, PerfHud.ARENA_BASES)).is_equal(gate.bases_golden_ticks)
	assert_array(PerfBases.hexes(gate, PerfHud.ARENA_BASES)).is_equal(gate.bases_golden_hex)
	assert_str(arena.hud.summary()["arena"]).is_equal("arena")


func test_the_scenario_switch_loads_the_base_arena_and_starts_its_match() -> void:
	var arena: Node2D = _open(PerfHud.ARENA_BASES)
	var snap: MatchSnapshot = arena.runner.snapshot
	assert_str(arena.scenario.resource_path).is_equal(DevRoutes.PERF_BASES_SCENARIO)
	assert_object(arena.runner.scenario).is_same(arena.scenario)
	assert_object(snap).is_not_null()
	assert_int(snap.map_cols).is_equal(54)
	assert_int(snap.map_rows).is_equal(24)
	assert_int(arena.runner.match_seed).is_equal(42)
	assert_str(arena.hud.summary()["arena"]).is_equal("bases")


func test_the_card_compares_against_the_bases_fields_and_not_the_arena_ones() -> void:
	var gate: PerfGateDef = PerfGateDef.new()
	Rig.pin_golden(gate)  # The arena's pair: what the run would match if the card read it.
	for tick: int in range(150, 901, 150):
		gate.bases_golden_ticks.append(tick)
		gate.bases_golden_hex.append(World.hash_hex(Rig.last_hash(tick) + 1))
	var hud: PerfHud = auto_free(Rig.hud(gate))
	hud.arena_kind = PerfHud.ARENA_BASES
	Rig.pass_frames(hud)
	for tick: int in range(1, 901):
		var snap: MatchSnapshot = Rig.snapshot(tick)
		snap.last_hash += 1  # The base arena's hashes.
		hud.record_snapshot(snap)
	var s: Dictionary = hud.summary()
	assert_bool(s["golden_match"]).is_true()
	assert_int(s["golden_checked"]).is_equal(6)
	assert_array(s["verdicts"]).contains(["golden_hashes: PASS (MATCH, 6 checkpoints)"])
	assert_bool(s["gate_pass"]).is_true()
	hud.arena_kind = PerfHud.ARENA_UNITS  # The same run, judged by the arena's pair, differs.
	assert_int(hud.summary()["golden_mismatch_tick"]).is_equal(150)


func test_a_mismatch_names_the_bases_fields_and_the_tick() -> void:
	var gate: PerfGateDef = PerfGateDef.new()
	for tick: int in range(150, 901, 150):
		gate.bases_golden_ticks.append(tick)
		gate.bases_golden_hex.append(World.hash_hex(Rig.last_hash(tick)))
	gate.bases_golden_hex[2] = "00000000000000ff"  # Tick 450.
	gate.golden_ticks = gate.bases_golden_ticks  # The arena's pair is fine: only the bases differ.
	gate.golden_hex = gate.bases_golden_hex.duplicate()
	gate.golden_hex[2] = World.hash_hex(Rig.last_hash(450))
	var hud: PerfHud = auto_free(Rig.hud(gate))
	hud.arena_kind = PerfHud.ARENA_BASES
	Rig.run(hud)
	var s: Dictionary = hud.summary()
	var got: String = World.hash_hex(Rig.last_hash(450))
	var line: String = (
		"golden_hashes: FAIL (MISMATCH at tick 450, got %s, golden 00000000000000ff "
		+ "(bases_golden_ticks, bases_golden_hex))"
	)
	assert_array(s["verdicts"]).contains([line % got])
	assert_int(s["golden_mismatch_tick"]).is_equal(450)
	assert_array(Rig.failed(s)).is_equal(["golden_hashes"])
	assert_bool(s["gate_pass"]).is_false()


func test_a_gate_without_bases_values_never_passes_and_names_them() -> void:
	var hud: PerfHud = auto_free(Rig.hud())  # The arena's pair only.
	hud.arena_kind = PerfHud.ARENA_BASES
	Rig.run(hud)
	var s: Dictionary = hud.summary()
	assert_bool(s["golden_match"]).is_false()
	assert_int(s["golden_checked"]).is_equal(0)
	assert_array(s["verdicts"]).contains(
		[
			(
				"golden_hashes: FAIL (no golden checkpoint up to tick 900 "
				+ "(bases_golden_ticks, bases_golden_hex))"
			)
		]
	)


func test_the_shipped_base_arena_matches_every_checkpoint_on_the_card() -> void:
	var gate: PerfGateDef = load(GATE)
	assert_int(gate.bases_golden_hex.size()).is_equal(6)
	var runner: MatchRunner = auto_free(MatchRunner.new())
	runner.scenario = load(DevRoutes.PERF_BASES_SCENARIO)
	runner.match_seed = 42
	runner.start()
	var hud: PerfHud = auto_free(Rig.hud(gate))
	hud.runner = runner
	hud.arena_kind = PerfHud.ARENA_BASES
	hud.run_ticks = 900
	add_child(hud)
	hud.restart()
	runner.run_ticks(900)
	var s: Dictionary = hud.summary()
	assert_array(s["checkpoints"]).has_size(6)
	assert_int(s["golden_checked"]).is_equal(6)
	assert_int(s["golden_mismatch_tick"]).is_equal(-1)
	assert_bool(s["golden_match"]).is_true()
	assert_array(s["verdicts"]).contains(["golden_hashes: PASS (MATCH, 6 checkpoints)"])


func test_the_report_carries_the_atlas_bake_and_the_card_the_draw_call_forecast() -> void:
	var arena: Node2D = _open(PerfHud.ARENA_BASES)
	var hud: PerfHud = arena.hud
	assert_bool(hud.summary().has("atlas_bake_ms")).is_true()
	assert_bool(JSON.parse_string(JSON.stringify(hud.summary())).has("atlas_bake_ms")).is_true()
	var lines: PackedStringArray = hud.card_lines()
	var forecast: String = PerfBases.calls_line(0)
	assert_array(Array(lines)).contains([forecast])
	assert_array(Array(lines)).contains(["atlas bake 0.0 ms | page none (no verdict)"])
	var other: Node2D = _open(PerfHud.ARENA_UNITS)
	for line: String in other.hud.card_lines():
		assert_str(line).not_contains("forecast")


func test_the_camera_holds_every_sprite_inside_the_diamond_at_the_six_sizes() -> void:
	for size: Vector2i in ScreenSizes.ALL:
		get_window().size = size
		await await_idle_frame()
		var arena: Node2D = _open(PerfHud.ARENA_BASES)
		var view: Rect2 = arena.camera.visible_world_rect()
		var boxes: Array[Rect2] = arena.sprite_boxes()
		# Buildings and units of both bases: 28 buildings and the rigs of the scenario's spawns.
		assert_int(boxes.size()).override_failure_message(str(size)).is_greater(28)
		for box: Rect2 in boxes:
			(
				assert_bool(view.encloses(box))
				. override_failure_message("%s: %s not in %s" % [size, box, view])
				. is_true()
			)
		assert_float(arena.camera.zoom.x).is_less_equal(arena.start_zoom)


func test_the_union_and_the_diamond_rules() -> void:
	var boxes: Array[Rect2] = [Rect2(0, 0, 10, 10), Rect2(-5, 20, 10, 10)]
	assert_that(ArenaRig.ArenaScript.union_of(boxes)).is_equal(Rect2(-5, 0, 15, 30))
	var none: Array[Rect2] = []
	assert_that(ArenaRig.ArenaScript.union_of(none)).is_equal(Rect2())
	var inside: Vector2 = IsoProjection.cell_centre_px(3, 2)
	assert_bool(ArenaRig.ArenaScript.in_diamond(inside, 54, 24)).is_true()
	assert_bool(ArenaRig.ArenaScript.in_diamond(inside, 4, 3)).is_true()
	assert_bool(ArenaRig.ArenaScript.in_diamond(inside, 4, 2)).is_false()
	assert_bool(ArenaRig.ArenaScript.in_diamond(inside, 3, 3)).is_false()
	assert_bool(ArenaRig.ArenaScript.in_diamond(Vector2(0, -50), 54, 24)).is_false()


## An arena of `kind` in the tree with its slow seams stubbed; freed with the case.
func _open(kind: String) -> Node2D:
	var arena: Node2D = ArenaRig.make(_calls)
	arena.arena_kind = kind
	add_child(arena)
	_arenas.append(arena)
	return arena
