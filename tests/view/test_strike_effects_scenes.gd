extends GdUnitTestSuite
## The strike effects in both scenes (plan P112b, ADR 0023 sections 2 and 10): `EffectsLayer` names
## the `DecalLayer` its craters go to, the decals are at z 1, the bars (and the offline glyphs) at
## z 30 and the effects at z 50. Then each scene is run, on a match of a Deep Bore, a Headquarters
## and an enemy Headquarters, with the match held after its first tick: a rupture lands near the
## Headquarters and the Headquarters and the enemy one are switched off, on all six screens. The
## crater is added every time; the burst and the own Headquarters' glyph are inside the screen; the
## enemy Headquarters' glyph shows in the perf arena (it shows every building) and not in the main
## scene, whose fog the player does not see it through. The sizes are the shared list of
## `ScreenSizes`; a turn of the phone changes the dp, which the layers read again.

const Rig: GDScript = preload("res://tests/view/support/building_rig.gd")
const UiProfiles: GDScript = preload("res://tests/support/ui_profiles.gd")
const ScreenSizes: GDScript = preload("res://tests/support/screen_sizes.gd")
const MAIN: String = "res://scenes/main.tscn"
const ARENA: String = "res://scenes/dev/perf_arena.tscn"
const SCENES: Array[String] = [MAIN, ARENA]
const SPAWNS: Array[Array] = [
	[1, "fossil_strike", 4, 4], [1, "headquarters", 10, 10], [2, "renew_hq", 20, 20]
]
const OWN_HQ: int = 1  ## Rows, in spawn order.
const ENEMY_HQ: int = 2
const AT: Vector2i = Vector2i(14500, 10500)  ## Tile (14, 10), east of the Headquarters.
const GLYPH_DP: int = 32
## The six screens of the shared list (ScreenSizes.ALL, entry by entry), each with its profile.
const SCREEN_PROFILES: Array[StringName] = [
	&"desktop",
	&"android_6in",
	&"web_tablet",
	&"desktop_portrait",
	&"android_6in_portrait",
	&"web_tablet_portrait",
]

var _window_size_before: Vector2i


func before() -> void:
	_window_size_before = get_window().size


func after() -> void:
	get_window().size = _window_size_before


func after_test() -> void:
	UiScale.clear_override()
	CommandQueue.clear()


func test_both_scenes_wire_the_effects_to_the_decals_and_keep_the_z_table() -> void:
	for path: String in SCENES:
		var state: SceneState = (load(path) as PackedScene).get_state()
		var wired: Variant = _value(state, "EffectsLayer", &"decals")
		assert_that(wired).override_failure_message(path).is_equal(NodePath("../DecalLayer"))
		assert_int(int(_value(state, "DecalLayer", &"z_index", 0))).is_equal(1)
		assert_int(int(_value(state, "HealthBarLayer", &"z_index", 0))).is_equal(30)
		assert_int(int(_value(state, "EffectsLayer", &"z_index", 0))).is_equal(50)


func test_a_rupture_and_a_blackout_show_on_all_six_screens_in_both_scenes() -> void:
	for path: String in SCENES:
		var first: UiMetrics = UiProfiles.by_name(SCREEN_PROFILES[0])
		UiScale.set_override(first)  # Before the layers read the dp, which the first size will not tell.
		get_window().size = first.window_size
		await await_idle_frame()
		var scene: Node2D = await _run(path)
		var runner: MatchRunner = scene.get_node("MatchRunner")
		var camera: RtsCamera = scene.get_node("Camera")
		var decals: DecalLayer = scene.get_node("DecalLayer")
		var effects: EffectsLayer = scene.get_node("EffectsLayer")
		var bars: HealthBarLayer = scene.get_node("HealthBarLayer")
		effects.clock = func() -> int: return 0  # Born and planned at once, so alive in any frame.
		var arena: bool = path == ARENA
		var craters: int = 0
		var sizes: Array[Vector2i] = []
		for profile_name: StringName in SCREEN_PROFILES:
			var profile: UiMetrics = UiProfiles.by_name(profile_name)
			sizes.append(profile.window_size)
			UiScale.set_override(profile)
			get_window().size = profile.window_size
			await await_idle_frame()  # size_changed: the layers read the dp again.
			var snap: MatchSnapshot = runner.snapshot
			Rig.see(snap, 1, [Vector2i(14, 10)])
			snap.offline_until.fill(0)
			snap.offline_until[OWN_HQ] = snap.tick + 450
			snap.offline_until[ENEMY_HQ] = snap.tick + 450
			var hall: Vector2 = IsoProjection.ground_to_px(snap.pos_x[OWN_HQ], snap.pos_y[OWN_HQ])
			var burst: Vector2 = IsoProjection.ground_to_px(AT.x, AT.y)
			camera.centre_on((hall + burst) * 0.5)
			_land(runner)
			await await_idle_frame()
			await await_idle_frame()
			craters += 1
			var note: String = "%s %s" % [path, profile_name]
			assert_int(decals.crater_count()).override_failure_message(note).is_equal(craters)
			assert_int(effects.quad_count()).override_failure_message(note).is_greater(0)
			var view: Rect2 = Rect2(Vector2.ZERO, get_viewport().get_visible_rect().size)
			var quad: Rect2 = effects.quad_rect(effects.quad_count() - 1)
			var on_screen: Rect2 = Rect2(
				camera.world_to_screen(quad.position), quad.size * camera.zoom
			)
			assert_bool(view.encloses(on_screen)).override_failure_message(note).is_true()
			assert_int(bars.glyph_count()).override_failure_message(note).is_equal(
				2 if arena else 1
			)
			var glyph: Rect2 = bars.glyph_rect(0)
			var side: float = GLYPH_DP * UiScale.base_px_per_dp()
			(
				assert_float(glyph.size.x * camera.zoom.x)
				. override_failure_message(note)
				. is_equal_approx(side, 0.05)
			)
			var shown: Rect2 = Rect2(
				camera.world_to_screen(glyph.position), glyph.size * camera.zoom
			)
			assert_bool(view.encloses(shown)).override_failure_message(note).is_true()
		assert_array(sizes).is_equal(ScreenSizes.ALL)  # 1280x720, 2400x1080, 2048x1536, both ways.


## Instances `path` on the building match of `SPAWNS`, lets it start, and holds it: nothing more
## ticks, so a snapshot that the test changes stays what the layers read.
func _run(path: String) -> Node2D:
	var spawns: Array[SpawnDef] = []
	for entry: Array in SPAWNS:
		spawns.append(Rig.spawn(entry[0], entry[1], entry[2], entry[3]))
	var scenario: ScenarioDef = Rig.scenario(spawns)
	var scene: Node2D = auto_free((load(path) as PackedScene).instantiate())
	if path == ARENA:
		scene.scenario = scenario
	else:
		scene.get_node("MatchRunner").scenario = scenario
	add_child(scene)
	for _frame: int in 3:
		await await_idle_frame()
	var runner: MatchRunner = scene.get_node("MatchRunner")
	runner.paused = true
	await await_idle_frame()
	assert_object(runner.snapshot).is_not_null()
	return scene


## Player 1's rupture goes up at `AT` and lands: the tick it is in the air, then the one it is not.
func _land(runner: MatchRunner) -> void:
	var snap: MatchSnapshot = runner.snapshot
	snap.strike_x[1] = AT.x
	snap.strike_y[1] = AT.y
	snap.strike_tick[1] = snap.tick + 45
	runner.ticked.emit(snap.tick)
	snap.strike_tick[1] = 0
	runner.ticked.emit(snap.tick)


func _value(
	state: SceneState, node_name: String, prop: StringName, fallback: Variant = null
) -> Variant:
	for index: int in state.get_node_count():
		if state.get_node_name(index) != node_name:
			continue
		for at: int in state.get_node_property_count(index):
			if state.get_node_property_name(index, at) == prop:
				return state.get_node_property_value(index, at)
	return fallback
