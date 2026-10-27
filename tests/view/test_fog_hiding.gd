extends GdUnitTestSuite
## What the fog hides in the draw layers (plan P47, ADR 0010 section 2). An enemy rig, a projectile
## and an effect on a tile the local player does not see is not drawn, an own unit always is, and
## `reveal_enemies` shows everything. The tile of a point is `snapshot.cell_of`'s, and a fog flag
## changes per tick: the rig and the projectile read the position of the tick, an effect is judged
## as it is born. Hiding sets only `visible` (a hidden rig keeps its position, tint and screen
## position), and the health bars follow `UnitLayer.is_shown`. The image of the fog layer is in
## test_fog_layer.gd (gdlint allows 20 public methods per file). The fog lies on the ground at z 4,
## under the effects (ADR 0023 section 2), so it does not cover a tracer: one with a single end seen
## is clipped to the seen tiles when it is born (ADR 0022 section 4, from the shelved P84), on the
## ground in steps of a quarter tile, and its two ends are read back through the projection.
## On controls_test (Rig): blue light tanks (ids 1-30, rows 0-29) from tile (8, 18), red ones (ids
## 31-40, rows 30-39), the nearest at tile (34, 10). Exact cases write the published snapshot's fog
## and positions (allowed in SYNC, ADR 0012 section 3); the first one plays the real sim. The
## runner is not in the tree, so only the calls here move time. Pixels cannot be read headless: the
## tests read the rigs' `visible`, the bar plan (`bar_count`, `bar_row`), the projectile plan
## (`active_count`, `quad_slot`) and the effect plan (`active_count`, `line_count`, `quad_count`).

const Frames: GDScript = preload("res://tests/view/support/rig_frames.gd")
const UiProfiles: GDScript = preload("res://tests/support/ui_profiles.gd")
const Rig: GDScript = preload("res://tests/view/support/fog_rig.gd")
const EffectsRig: GDScript = preload("res://tests/view/support/effects_rig.gd")
const ScreenSizes: GDScript = preload("res://tests/support/screen_sizes.gd")
const BASE_SIZE: Vector2i = ScreenSizes.LANDSCAPE[0]
## The screens every screen is tested at: base, 20:9 phone and 4:3 tablet, each held both ways.
const TARGET_SIZES: Array[Vector2i] = ScreenSizes.ALL
## Milli-tile points: a seen tile (tank 1's, tile (8, 18)), an unseen one (tile (40, 40)) and red
## tank 31's own tile (34, 10).
const SEEN: Vector2i = Vector2i(8500, 18500)
const DARK: Vector2i = Vector2i(40500, 40500)
const RED_31: Vector2i = Vector2i(34500, 10500)
## The tolerance of a plan point: the plan keeps its points in 32 bit floats.
const TOLERANCE: Vector2 = Vector2(0.01, 0.01)
## Where a tracer stands above its ground points: the muzzle height of tank_cannon, weapon 0 here
## (ADR 0023 section 2; `SpriteLift`, typed again), and how far a clipped tracer is probed at a
## time (a quarter tile, in milli).
const TANK_LIFT_PX: float = 14.0
const STEP_MILLI: int = 250

var _window_size_before: Vector2i
var _now_ms: int = 0
var _runner: MatchRunner
var _camera: RtsCamera
var _units: UnitLayer
var _bars: HealthBarLayer
var _shells: ProjectileLayer
var _effects: EffectsLayer


func before() -> void:
	_window_size_before = get_window().size


func after() -> void:
	get_window().size = _window_size_before


func before_test() -> void:
	UiScale.set_override(UiProfiles.by_name(&"android_6in"))  # 1 dp is 1.75 px.
	get_window().size = BASE_SIZE
	_build(Rig.scenario(1))


func after_test() -> void:
	UiScale.clear_override()
	CommandQueue.clear()


func test_an_enemy_rig_is_hidden_until_a_blue_tank_drives_within_sight_then_shown() -> void:
	_frame()
	for row: int in 30:
		assert_bool(_rig(row).visible).is_true()
		assert_bool(_units.is_shown(row)).is_true()
	for row: int in range(30, 40):
		assert_bool(_rig(row).visible).is_false()
		assert_bool(_units.is_shown(row)).is_false()
	# Tank 6 drives out of the block towards the red tanks (34.5, 10.5) and nearer.
	CommandQueue.submit(Command.move(1, Rig.BLUE_TANK_6, 30000, 12000))
	var cell: int = _runner.snapshot.cell_of(RED_31.x, RED_31.y)
	var shown_at: int = -1
	for tick: int in range(1, 250):
		_runner.run_ticks(1)
		_frame()
		var seen: bool = _runner.snapshot.fog.is_visible(1, cell)
		assert_bool(_rig(30).visible).override_failure_message("tick %d" % tick).is_equal(seen)
		assert_bool(_units.is_shown(30)).is_equal(seen)
		if seen:
			shown_at = tick
			break
	assert_int(shown_at).is_greater(40)  # Not at once: the tank has some way to drive.
	assert_int(shown_at).is_less(249)  # And it does get there.
	for row: int in 30:  # The own rigs were shown throughout, and are now.
		assert_bool(_rig(row).visible).is_true()
	for row: int in range(37, 40):  # The red tanks near (26, 40) are still outside every sight.
		assert_bool(_rig(row).visible).is_false()


func test_own_rigs_are_shown_even_when_the_player_sees_nothing() -> void:
	Rig.blind(_runner.snapshot, 1)
	_frame()
	for row: int in 30:
		assert_bool(_rig(row).visible).is_true()
		assert_bool(_units.is_shown(row)).is_true()
	for row: int in range(30, 40):
		assert_bool(_rig(row).visible).is_false()
	# One tile in sight brings one rig: the one standing on it.
	Rig.set_seen(_runner.snapshot, 1, Vector2i(34, 10), true)
	_frame()
	assert_bool(_rig(30).visible).is_true()
	assert_bool(_rig(31).visible).is_false()  # Red tank 32 stands at tile (36, 10).
	assert_bool(_units.is_shown(30)).is_true()
	assert_bool(_units.is_shown(31)).is_false()


func test_local_player_2_sees_through_its_own_fog_and_hides_the_blue_tanks() -> void:
	_build(Rig.scenario(2))
	_frame()
	for row: int in 30:
		assert_bool(_rig(row).visible).is_false()
		assert_bool(_units.is_shown(row)).is_false()
	for row: int in range(30, 40):
		assert_bool(_rig(row).visible).is_true()
		assert_bool(_units.is_shown(row)).is_true()
	Rig.set_seen(_runner.snapshot, 2, Vector2i(8, 18), true)  # Tank 1's tile, in red's sight.
	_frame()
	assert_bool(_rig(0).visible).is_true()
	assert_bool(_rig(1).visible).is_false()


func test_hiding_changes_only_visible_a_hidden_rig_keeps_its_place_tint_and_screen_position(
) -> void:
	CommandQueue.submit(Command.move(2, PackedInt32Array([31]), 38000, 10500))  # Red drives east.
	_runner.run_ticks(6)
	_runner._process(1.0 / 60.0)  # A quarter into the next tick.
	_frame()
	var snap: MatchSnapshot = _runner.snapshot
	assert_bool(_rig(30).visible).is_false()
	assert_int(snap.pos_x[30]).is_greater(snap.prev_pos_x[30])  # It is on the move.
	var from: Vector2 = IsoProjection.ground_to_px(snap.prev_pos_x[30], snap.prev_pos_y[30])
	var to: Vector2 = IsoProjection.ground_to_px(snap.pos_x[30], snap.pos_y[30])
	assert_vector(_rig(30).position).is_equal_approx(from.lerp(to, 0.25), Vector2(0.001, 0.001))
	assert_that(_rig(30).get_node("Hull").modulate).is_equal(Color.WHITE)  # No tint, no dimming.
	assert_int(_rig(30).get_child_count()).is_equal(3)  # Nothing was added or taken away.
	assert_int(Frames.dir(_units, 30, &"hull")).is_equal(6)  # Its frame is the one it was made with.
	var pick: PickSnapshot = PickSnapshot.new()
	for size: Vector2i in TARGET_SIZES:
		get_window().size = size
		await await_idle_frame()
		var view: Vector2 = _camera.get_viewport_rect().size
		# The view turned with the window, so the portrait sizes are run as portrait.
		assert_bool(view.y > view.x).override_failure_message(str(size)).is_equal(
			UiScale.is_portrait_size(size)
		)
		var expected: Vector2 = (_rig(30).global_position - _camera.position) * _camera.zoom
		assert_vector(_units.unit_screen_position(30)).is_equal_approx(
			expected + view * 0.5, Vector2(0.01, 0.01)
		)
		assert_vector(_units.unit_screen_position(30)).is_equal(
			_camera.world_to_screen(_rig(30).global_position)
		)
		_units.fill_pick_snapshot(pick, 24.0)  # Every row, hidden or not (P47p marks them).
		assert_int(pick.size()).is_equal(40)
		assert_int(pick.ids[30]).is_equal(31)
		assert_int(pick.owners[30]).is_equal(2)
		# The Picker's centre is the lifted one: the light tank's pick lift above the ground point.
		var lift: float = float((load(IsoIndex.PATH) as IsoIndex).sheet(&"light_tank").pick_lift_px)
		assert_float(pick.lift_of(30)).is_equal_approx(lift * _camera.zoom.x, 0.0001)
		assert_vector(pick.screen_pos[30] + Vector2(0.0, pick.lift_of(30))).is_equal_approx(
			_units.unit_screen_position(30), Vector2(0.001, 0.001)
		)
		assert_bool(_rig(30).visible).is_false()  # And the screen did not unhide it.


func test_reveal_enemies_shows_the_hidden_rigs_and_is_read_when_asked_not_kept() -> void:
	assert_bool(_units.reveal_enemies).is_false()  # Off unless a scene or a test sets it.
	assert_bool(_units.is_shown(30)).is_false()
	_units.reveal_enemies = true
	assert_bool(_units.is_shown(30)).is_true()  # At once, before any frame.
	assert_bool(_rig(30).visible).is_false()  # The rig follows at the next frame.
	_frame()
	for row: int in range(30, 40):
		assert_bool(_rig(row).visible).is_true()
	_units.reveal_enemies = false
	assert_bool(_units.is_shown(30)).is_false()
	_frame()
	assert_bool(_rig(30).visible).is_false()
	# The fog is read at the call too: the same layer, a tile in sight, no frame in between.
	Rig.set_seen(_runner.snapshot, 1, Vector2i(34, 10), true)
	assert_bool(_units.is_shown(30)).is_true()
	assert_bool(_units.is_shown(-1)).is_false()  # A row out of range is not shown.
	assert_bool(_units.is_shown(40)).is_false()


func test_a_units_tile_is_the_snapshots_clamped_cell_at_the_unit_position_of_the_tick() -> void:
	var snap: MatchSnapshot = _runner.snapshot
	# Red tank 31 is placed west of the map: its tile is the edge tile (0, 10).
	snap.pos_x[30] = -5000
	snap.pos_y[30] = 10500
	snap.prev_pos_x[30] = SEEN.x  # The tick before it stood on a tile in sight.
	snap.prev_pos_y[30] = SEEN.y
	_frame()
	assert_bool(_rig(30).visible).is_false()  # It is judged where it is, not where it was.
	assert_bool(_units.is_shown(30)).is_false()
	Rig.set_seen(snap, 1, Vector2i(0, 10), true)
	_frame()
	assert_bool(_rig(30).visible).is_true()
	assert_bool(_units.is_shown(30)).is_true()
	snap.prev_pos_x[30] = DARK.x  # The tick before it stood in the dark: it shows all the same.
	snap.prev_pos_y[30] = DARK.y
	_frame()
	assert_bool(_rig(30).visible).is_true()
	assert_bool(_units.is_shown(30)).is_true()
	snap.pos_x[30] = 20500  # Past the south edge: the edge tile (20, 47).
	snap.pos_y[30] = 99000
	_frame()
	assert_bool(_rig(30).visible).is_false()
	Rig.set_seen(snap, 1, Vector2i(20, 47), true)
	_frame()
	assert_bool(_rig(30).visible).is_true()
	assert_bool(_units.is_shown(30)).is_true()


func test_the_cell_of_a_point_is_the_snapshots_clamped_cell() -> void:
	var snap: MatchSnapshot = _runner.snapshot
	assert_bool(FogLayer.is_seen(snap, 1, 8500, 18500)).is_true()  # Tank 1's tile.
	assert_bool(FogLayer.is_seen(snap, 1, 46500, 46500)).is_false()  # The far corner.
	assert_bool(FogLayer.is_seen(snap, 2, 8500, 18500)).is_false()  # Red does not see the block.
	assert_bool(FogLayer.is_seen(snap, 2, 34500, 10500)).is_true()  # Red tank 31's tile.
	# A point past the map takes the nearest edge cell, and never indexes outside the grid.
	assert_bool(FogLayer.is_seen(snap, 1, -4000, 99000)).is_false()
	Rig.set_seen(snap, 1, Vector2i(0, 47), true)
	assert_bool(FogLayer.is_seen(snap, 1, -4000, 99000)).is_true()
	assert_bool(FogLayer.is_seen(snap, 1, 999, 47999)).is_true()  # Tile (0, 47) itself.
	assert_bool(FogLayer.is_seen(snap, 1, 1000, 47999)).is_false()  # Tile (1, 47).


func test_a_health_bar_is_drawn_only_for_a_unit_the_fog_does_not_hide() -> void:
	assert_bool("reveal_enemies" in _bars).is_false()  # The bars follow the unit layer's answer.
	var snap: MatchSnapshot = _runner.snapshot
	_units.set_selected(PackedInt32Array([2, 31]))  # Own tank 2 and enemy tank 31, in the dark.
	_frame()
	assert_int(_bars.bar_count()).is_equal(1)
	assert_int(_bars.bar_row(0)).is_equal(1)
	_runner.world.hp[30] -= 40  # Hit while hidden: a recent hit gives no bar either.
	_runner.run_ticks(1)
	_units.set_selected(PackedInt32Array([2]))
	_frame()
	assert_int(_units.hit_time_ms(30)).is_equal(_now_ms)
	assert_int(_bars.bar_count()).is_equal(1)
	assert_int(_bars.bar_row(0)).is_equal(1)
	Rig.set_seen(_runner.snapshot, 1, Vector2i(34, 10), true)  # Now in sight.
	_frame()
	assert_int(_bars.bar_count()).is_equal(2)
	assert_int(_bars.bar_row(1)).is_equal(30)
	Rig.set_seen(_runner.snapshot, 1, Vector2i(34, 10), false)
	_units.reveal_enemies = true
	_frame()
	assert_int(_bars.bar_count()).is_equal(2)
	assert_int(snap.owner[30]).is_equal(2)


func test_a_projectile_on_a_tile_the_player_does_not_see_is_not_drawn() -> void:
	_set_slot(0, 11, SEEN, SEEN + Vector2i(100, 0))
	_set_slot(1, 12, DARK, DARK + Vector2i(100, 0))
	_set_slot(2, 13, SEEN, DARK)  # Flies into the dark: judged by the tile it is on now.
	_set_slot(3, 14, DARK, SEEN)  # Flies into sight.
	_set_slot(4, 15, DARK, DARK, 0)  # A neutral one, in the dark.
	_shells._process(0.0)
	assert_int(_shells.active_count()).is_equal(2)
	assert_array(_shell_slots()).is_equal([0, 3])
	_shells.reveal_enemies = true
	_shells._process(0.0)
	assert_array(_shell_slots()).is_equal([0, 1, 2, 3, 4])
	_shells.reveal_enemies = false
	_set_slot(5, 16, SEEN, Vector2i(-3000, 18500))  # West of the map: the edge tile (0, 18).
	_shells._process(0.0)
	assert_array(_shell_slots()).is_equal([0, 3])
	Rig.set_seen(_runner.snapshot, 1, Vector2i(0, 18), true)
	_shells._process(0.0)
	assert_array(_shell_slots()).is_equal([0, 3, 5])
	_runner.scenario.local_player = 2  # Red sees its own corner and not the blue block.
	_set_slot(6, 17, RED_31, RED_31 + Vector2i(100, 0))
	_shells._process(0.0)
	assert_array(_shell_slots()).is_equal([6])


func test_a_shot_shows_its_tracer_when_either_end_is_seen_and_its_flash_when_the_shooter_is(
) -> void:
	_runner.snapshot.weapon_projectile_speed[0] = 0  # tank_cannon as a hitscan weapon.
	_tick_with(EffectsRig.shot(SEEN, DARK, 0))  # A shooter in sight: the tracer and the flash.
	assert_int(_effects.active_count()).is_equal(2)
	assert_int(_effects.line_count()).is_equal(2)  # The outline pass and the colour pass.
	assert_int(_effects.quad_count()).is_equal(1)
	_tick_with(EffectsRig.shot(DARK, SEEN, 0))  # An enemy shoots at an own unit from the dark.
	assert_int(_effects.active_count()).is_equal(3)  # The tracer, which reaches the seen end.
	assert_int(_effects.line_count()).is_equal(4)
	assert_int(_effects.quad_count()).is_equal(1)  # No new flash: its tile is dark.
	_tick_with(EffectsRig.shot(DARK, DARK + Vector2i(2000, 0), 0))
	assert_int(_effects.active_count()).is_equal(3)  # Neither end seen: nothing.
	_tick_with(EffectsRig.shot(SEEN, SEEN + Vector2i(1500, 0), 0))
	assert_int(_effects.active_count()).is_equal(5)
	_effects.reveal_enemies = true
	_tick_with(EffectsRig.shot(DARK, DARK + Vector2i(2000, 0), 0))
	assert_int(_effects.active_count()).is_equal(7)


func test_a_tracer_with_one_end_seen_is_clipped_to_the_seen_tiles_within_a_quarter_tile() -> void:
	_runner.snapshot.weapon_projectile_speed[0] = 0  # tank_cannon as a hitscan weapon.
	var base: Vector2i = Vector2i(18500, 18500)  # Tile (18, 18), the last seen one on each axis.
	for axis: Vector2i in [Vector2i(1, 0), Vector2i(0, 1)]:
		_see_line(axis, 10, 18)  # The dark begins at the tile 19 of the axis: milli 19000.
		var dark_edge: int = 19000
		# A shooter on a dark tile three tiles on, a seen target: the line starts at the last seen
		# point on the way from the target to the muzzle and ends at the target.
		_now_ms += 1000
		_tick_with(EffectsRig.shot(base + axis * 3000, base, 0))
		assert_int(_effects.line_count()).is_equal(2)  # The outline pass and the colour pass.
		for line: int in 2:  # Both passes share the clipped ends.
			assert_vector(_effects.line_to(line)).is_equal_approx(_lifted(base), TOLERANCE)
			var from: Vector2i = _ground_of(_effects.line_from(line))
			assert_bool(_point_seen(from)).is_true()
			assert_bool(_point_seen(from + axis * (STEP_MILLI + 2))).is_false()
			assert_int(_along(from, axis)).is_between(dark_edge - STEP_MILLI - 2, dark_edge - 1)
			assert_int(_along(from, Vector2i(axis.y, axis.x))).is_equal(18500)  # On the line.
		# The ends the other way round: a seen shooter, a dark target six tiles on.
		var shooter: Vector2i = base - axis * 3000
		_now_ms += 1000
		_tick_with(EffectsRig.shot(shooter, base + axis * 3000, 0))
		assert_int(_effects.line_count()).is_equal(2)
		for line: int in 2:
			var muzzle: Vector2 = _effects.line_from(line)
			assert_float(muzzle.distance_to(_lifted(shooter))).is_equal_approx(31.0, 0.01)
			var to: Vector2i = _ground_of(_effects.line_to(line))
			assert_bool(_point_seen(to)).is_true()
			assert_bool(_point_seen(to + axis * (STEP_MILLI + 2))).is_false()
			assert_int(_along(to, axis)).is_between(dark_edge - STEP_MILLI - 2, dark_edge - 1)
		# A target one tile past the last seen tile leaves a line no longer than one step.
		_now_ms += 1000
		_tick_with(EffectsRig.shot(base, base + axis * 1000, 0))
		var short: float = _effects.line_from(0).distance_to(_effects.line_to(0))
		assert_float(short).is_less_equal(IsoProjection.ground_to_px(STEP_MILLI, 0).length())


func test_a_tracer_with_both_ends_seen_is_whole_and_so_is_one_in_the_dark_when_revealed() -> void:
	_runner.snapshot.weapon_projectile_speed[0] = 0
	_see_line(Vector2i(1, 0), 10, 18)
	Rig.set_seen(_runner.snapshot, 1, Vector2i(14, 18), false)  # A dark tile between two seen ends.
	var shooter: Vector2i = Vector2i(10500, 18500)
	var target: Vector2i = Vector2i(18500, 18500)
	_tick_with(EffectsRig.shot(shooter, target, 0))
	assert_int(_effects.line_count()).is_equal(2)
	var from: Vector2 = _lifted(shooter)
	var to: Vector2 = _lifted(target)
	assert_vector(_effects.line_from(1)).is_equal_approx(
		from + (to - from).limit_length(31.0), TOLERANCE
	)
	assert_vector(_effects.line_to(1)).is_equal_approx(to, TOLERANCE)
	# Revealed (the perf arena): every tracer is whole, in the dark too.
	_effects.reveal_enemies = true
	_now_ms += 1000
	_tick_with(EffectsRig.shot(DARK, DARK + Vector2i(3000, 0), 0))
	assert_int(_effects.line_count()).is_equal(2)
	var dark_from: Vector2 = _lifted(DARK)
	var dark_to: Vector2 = _lifted(DARK + Vector2i(3000, 0))
	assert_vector(_effects.line_from(1)).is_equal_approx(
		dark_from + (dark_to - dark_from).limit_length(31.0), TOLERANCE
	)
	assert_vector(_effects.line_to(1)).is_equal_approx(dark_to, TOLERANCE)


func test_a_projectile_shot_from_the_dark_shows_nothing_until_it_lands_in_sight() -> void:
	var speed: int = _runner.snapshot.weapon_projectile_speed[0]
	assert_int(speed).is_greater(0)  # The cannon fires a shell.
	_tick_with(EffectsRig.shot(SEEN, DARK, 0))  # Fired from sight: the flash.
	assert_int(_effects.line_count()).is_equal(0)
	assert_int(_effects.quad_count()).is_equal(1)
	_tick_with(EffectsRig.shot(DARK, SEEN, 0))  # Fired from the dark at an own unit: no flash.
	assert_int(_effects.active_count()).is_equal(1)
	_tick_with(EffectsRig.impact(SEEN, 0))  # The shell comes down in sight: a puff.
	assert_int(_effects.active_count()).is_equal(2)
	_tick_with(EffectsRig.impact(DARK, 0))  # And one in the dark does not.
	assert_int(_effects.active_count()).is_equal(2)
	_runner.scenario.local_player = 2  # Red sees tile (34, 10) and not tank 1's tile.
	_tick_with(EffectsRig.impact(SEEN, 0))
	assert_int(_effects.active_count()).is_equal(2)
	_tick_with(EffectsRig.impact(RED_31, 0))
	assert_int(_effects.active_count()).is_equal(3)


func test_a_death_in_the_dark_shows_no_burst_unless_the_unit_was_the_players_own() -> void:
	_tick_with(EffectsRig.died(DARK, 0, 5, 2))  # Enemy, out of sight.
	assert_int(_effects.active_count()).is_equal(0)
	_tick_with(EffectsRig.died(SEEN, 0, 5, 2))  # Enemy, in sight.
	assert_int(_effects.active_count()).is_equal(1)
	# An own unit's sight ends with it, so the tile it dies on can be dark in that very tick.
	_tick_with(EffectsRig.died(DARK, 0, 6, 1))
	assert_int(_effects.active_count()).is_equal(2)
	_runner.scenario.local_player = 2  # Now owner 2 is own and owner 1 the enemy.
	_tick_with(EffectsRig.died(DARK, 0, 7, 2))
	assert_int(_effects.active_count()).is_equal(3)
	_tick_with(EffectsRig.died(DARK, 0, 8, 1))
	assert_int(_effects.active_count()).is_equal(3)
	_effects.reveal_enemies = true
	_tick_with(EffectsRig.died(DARK, 0, 9, 1))
	assert_int(_effects.active_count()).is_equal(4)


func test_a_fight_in_the_dark_takes_no_slot_of_the_ring() -> void:
	_effects.capacity = 4
	_tick_with(EffectsRig.impact(SEEN, 0) + EffectsRig.impact(SEEN + Vector2i(1000, 0), 0))
	assert_int(_effects.active_count()).is_equal(2)
	for _tick: int in 60:  # An unseen battle that would overwrite a ring of four many times over.
		_tick_with(
			(
				EffectsRig.shot(DARK, DARK + Vector2i(2000, 0), 0)
				+ EffectsRig.impact(DARK, 0)
				+ EffectsRig.died(DARK, 0, 9, 2)
			)
		)
	assert_int(_effects.active_count()).is_equal(2)  # Both puffs in sight are still there.
	assert_int(_effects.quad_count()).is_equal(2)


func _build(scenario: ScenarioDef) -> void:
	_free_if_valid(_effects)  # The nodes of an earlier build, which gdUnit may have freed already.
	_free_if_valid(_shells)
	_free_if_valid(_bars)
	_free_if_valid(_units)
	_free_if_valid(_camera)
	_free_if_valid(_runner)
	_now_ms = 0
	_runner = auto_free(MatchRunner.new())
	_runner.scenario = scenario
	_runner.start()
	_camera = auto_free(RtsCamera.new())
	add_child(_camera)
	_camera.position = Vector2(500, 1100)  # No map rect is set, so nothing clamps it.
	_units = auto_free(UnitLayer.new())
	_units.runner = _runner
	_units.camera = _camera
	_units.clock = func() -> int: return _now_ms
	add_child(_units)
	_units.set_process(false)
	_bars = auto_free(HealthBarLayer.new())
	_bars.runner = _runner
	_bars.unit_layer = _units
	add_child(_bars)
	_bars.set_process(false)
	_shells = auto_free(ProjectileLayer.new())
	_shells.runner = _runner
	add_child(_shells)
	_shells.set_process(false)
	_effects = auto_free(EffectsLayer.new())
	_effects.runner = _runner
	_effects.clock = func() -> int: return _now_ms
	add_child(_effects)
	_effects.set_process(false)


func _free_if_valid(node: Variant) -> void:
	if is_instance_valid(node):
		node.free()


## One frame of the unit layer, then the bars, in the scene's order.
func _frame() -> void:
	_units._process(0.0)
	_bars._process(0.0)


func _rig(row: int) -> Node2D:
	return _units.rig(row)


## Projectile slot `slot` live with id `id`, going from `from` to `to` (milli-tiles), in the
## published snapshot and in the previous tick.
func _set_slot(slot: int, id: int, from: Vector2i, to: Vector2i, owner_id: int = 1) -> void:
	var snap: MatchSnapshot = _runner.snapshot
	snap.proj_id[slot] = id
	snap.prev_proj_id[slot] = id
	snap.proj_owner[slot] = owner_id
	snap.proj_weapon[slot] = 0
	snap.prev_proj_x[slot] = from.x
	snap.prev_proj_y[slot] = from.y
	snap.proj_x[slot] = to.x
	snap.proj_y[slot] = to.y


func _shell_slots() -> Array[int]:
	var slots: Array[int] = []
	for index: int in _shells.active_count():
		slots.append(_shells.quad_slot(index))
	return slots


## Delivers `events` as the events of a tick, the way the runner does, then plans a frame. The
## effects live on the fake clock, which stands still, so nothing expires between calls.
func _tick_with(events: PackedInt32Array) -> void:
	_runner.snapshot.events = events
	_runner.ticked.emit(_runner.snapshot.tick)
	_effects._process(0.0)


## The world px of the ground point `milli`, lifted to the tank cannon's muzzle height.
func _lifted(milli: Vector2i) -> Vector2:
	return IsoProjection.ground_to_px(milli.x, milli.y) - Vector2(0.0, TANK_LIFT_PX)


## The ground point (milli, rounded) under the world px `point` of a tracer at that height.
func _ground_of(point: Vector2) -> Vector2i:
	return IsoProjection.px_to_ground(point + Vector2(0.0, TANK_LIFT_PX))


## Whether the local player sees the tile of the ground point `milli` in the published fog.
func _point_seen(milli: Vector2i) -> bool:
	return FogLayer.is_seen(_runner.snapshot, 1, milli.x, milli.y)


## The coordinate of `point` along `axis`, a unit step of the grid.
func _along(point: Vector2i, axis: Vector2i) -> int:
	return point.x * axis.x + point.y * axis.y


## The player sees the tiles `first` to `last` along `axis` through the tile (18, 18), and nothing
## else: along x these are the tiles (first, 18) to (last, 18), along y (18, first) to (18, last).
func _see_line(axis: Vector2i, first: int, last: int) -> void:
	Rig.blind(_runner.snapshot, 1)
	for at: int in range(first, last + 1):
		Rig.set_seen(_runner.snapshot, 1, Vector2i(18, 18) + axis * (at - 18), true)
