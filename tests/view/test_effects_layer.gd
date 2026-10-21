extends GdUnitTestSuite
## What EffectsLayer makes of the events of a tick (plan P44b, assets/art/STYLE.md "Combat
## effects"): a tracer and a flash for a hitscan SHOT, a flash for a projectile SHOT, a puff for an
## IMPACT, a burst for the DIED of a vehicle and a fade for the DIED of infantry; the fixed ring,
## the expiry on the frame clock and the new match. The look in time (alphas, growth, dp widths)
## is in test_effects_layer_curves.gd and the frame, the tick delivery and the scene are in
## test_effects_layer_frames.gd (gdlint allows 20 public methods per file). Pixels cannot be read
## headless, so the tests read the layer's plan (`line_*`, `quad_*`), which `_draw` paints one for
## one. Events are set on the published snapshot and delivered by `runner.ticked`, as the runner
## does it; the SHOT and the DIED of a target that is gone in the same tick come from the real sim.
## On Rig.battle(): types light_tank (armour LIGHT), rifle_squad and rocket_squad (INFANTRY),
## weapons tank_cannon, rifle (hitscan) and rocket; indexes are looked up by id. The runner is not
## in the tree, so only the calls here move time.

const UiProfiles: GDScript = preload("res://tests/support/ui_profiles.gd")
const Rig: GDScript = preload("res://tests/view/support/effects_rig.gd")
const SCRIPT_PATH: String = "res://game/view/EffectsLayer.gd"
## STYLE.md: the atlas regions and the tracer colours.
const FLASH: Rect2 = Rect2(144, 0, 32, 32)
const PUFF: Rect2 = Rect2(84, 0, 56, 56)
const BURST: Rect2 = Rect2(0, 0, 80, 80)
const TRACER: Color = Color("FFD84D")
const EDGE: Color = Color("1C2127")
const TOL: Vector2 = Vector2(0.001, 0.001)

var _now_ms: int = 0
var _runner: MatchRunner
var _layer: EffectsLayer


func before_test() -> void:
	UiScale.set_override(UiProfiles.by_name(&"android_6in"))  # 1 dp is 1.75 px.
	_runner = null
	_layer = null
	_build(Rig.battle())


func after_test() -> void:
	UiScale.clear_override()
	CommandQueue.clear()


func test_a_rifle_shot_draws_a_tracer_from_the_muzzle_point_to_the_targets_position() -> void:
	var shooter: Vector2i = Vector2i(10000, 20000)
	var target: Vector2i = Vector2i(14000, 23000)  # 4 tiles east and 3 south: 5 tiles away.
	_tick_with(Rig.shot(shooter, target, _weapon(&"rifle")))
	var from_px: Vector2 = ViewScale.milli_to_px_vec(shooter.x, shooter.y)
	var to_px: Vector2 = ViewScale.milli_to_px_vec(target.x, target.y)
	assert_int(_layer.line_count()).is_equal(2)  # The outline pass, then the colour pass.
	for index: int in 2:
		var muzzle: Vector2 = _layer.line_from(index)
		# 13 world px from the shooter, on the segment to the target, which the line ends at.
		assert_float(muzzle.distance_to(from_px)).is_equal_approx(13.0, 0.001)
		assert_float((to_px - from_px).cross(muzzle - from_px)).is_equal_approx(0.0, 0.01)
		assert_float((to_px - from_px).dot(muzzle - from_px)).is_greater(0.0)
		assert_vector(muzzle).is_equal_approx(from_px + (to_px - from_px).normalized() * 13.0, TOL)
		assert_vector(_layer.line_to(index)).is_equal(to_px)
	assert_that(_layer.line_color(0)).is_equal(EDGE)
	assert_that(_layer.line_color(1)).is_equal(TRACER)
	assert_float(_layer.line_width(0)).is_equal_approx(3.5 * 1.75, 0.001)
	assert_float(_layer.line_width(1)).is_equal_approx(1.5 * 1.75, 0.001)


func test_a_tracer_ends_at_the_events_target_position_when_the_target_died_in_that_tick() -> void:
	# Two rifle squads of 1 hp each, three tiles apart: a shot kills its target, which is gone
	# from the rows of the snapshot that holds the SHOT and the DIED.
	_build(Rig.duel())
	_runner.world.hp[0] = 1
	_runner.world.hp[1] = 1
	var events: PackedInt32Array = PackedInt32Array()
	for _i: int in 60:
		_runner.run_ticks(1)
		events = _runner.snapshot.events
		if not events.is_empty():
			break
	_layer._process(0.0)
	var killed_shots: int = 0
	for at: int in range(0, events.size(), World.EVENT_STRIDE):
		if events[at] != World.Event.SHOT or _runner.snapshot.index_of(events[at + 4]) >= 0:
			continue
		killed_shots += 1
		assert_array(_died_ids(events)).contains([events[at + 4]])
		var target_px: Vector2 = ViewScale.milli_to_px_vec(events[at + 6], events[at + 7])
		var shooter_px: Vector2 = ViewScale.milli_to_px_vec(events[at + 2], events[at + 3])
		var drawn: bool = false
		for index: int in _layer.line_count():
			if _layer.line_to(index) == target_px:
				drawn = true
				assert_float(_layer.line_from(index).distance_to(shooter_px)).is_less(14.0)
		assert_bool(drawn).is_true()
	assert_int(killed_shots).is_greater(0)  # The case is the one it says.
	assert_int(_layer.line_count()).is_equal(2 * killed_shots)


func test_a_shot_of_a_projectile_weapon_draws_only_a_flash_out_at_its_muzzle() -> void:
	var shooter: Vector2i = Vector2i(10000, 20000)
	var target: Vector2i = Vector2i(10000, 24000)  # 4 tiles south.
	var from_px: Vector2 = ViewScale.milli_to_px_vec(shooter.x, shooter.y)
	# STYLE.md: the flash is 32, 24 and 16 px wide, and it sits 31 (tank_cannon) or 13 px out.
	var cases: Dictionary[StringName, Vector2] = {
		&"tank_cannon": Vector2(32.0, 31.0),
		&"rocket": Vector2(24.0, 13.0),
		&"rifle": Vector2(16.0, 13.0),
	}
	for weapon_id: StringName in cases:
		_now_ms += 1000  # The effects before are gone.
		_tick_with(Rig.shot(shooter, target, _weapon(weapon_id)))
		assert_int(_layer.line_count()).is_equal(2 if weapon_id == &"rifle" else 0)  # Rifle only.
		assert_int(_layer.quad_count()).is_equal(1)
		assert_that(_layer.quad_region(0)).is_equal(FLASH)
		assert_float(_layer.quad_alpha(0)).is_equal(1.0)
		assert_float(_layer.quad_rect(0).size.x).is_equal_approx(cases[weapon_id].x, 0.001)
		assert_float(_layer.quad_rect(0).size.y).is_equal_approx(cases[weapon_id].x, 0.001)
		var centre: Vector2 = _layer.quad_rect(0).get_center()
		assert_vector(centre).is_equal_approx(from_px + Vector2(0.0, cases[weapon_id].y), TOL)


func test_a_shot_has_a_tracer_when_its_weapons_projectile_speed_is_0_whatever_it_is_named() -> void:
	# STYLE.md keys the hitscan rule on the weapon_projectile_speed column, as it keys the infantry
	# rule on the armour column: swap the speeds of the rifle and the cannon and the tracer follows.
	var rifle: int = _weapon(&"rifle")
	var cannon: int = _weapon(&"tank_cannon")
	_runner.snapshot.weapon_projectile_speed[rifle] = 600
	_runner.snapshot.weapon_projectile_speed[cannon] = 0
	_tick_with(Rig.shot(Vector2i(10000, 20000), Vector2i(14000, 20000), rifle))
	assert_int(_layer.line_count()).is_equal(0)
	assert_int(_layer.quad_count()).is_equal(1)  # Its flash only, with the rifle's size.
	_now_ms += 1000
	_tick_with(Rig.shot(Vector2i(10000, 20000), Vector2i(14000, 20000), cannon))
	assert_int(_layer.line_count()).is_equal(2)
	assert_int(_layer.quad_count()).is_equal(1)
	assert_float(_layer.quad_rect(0).size.x).is_equal_approx(32.0, 0.001)  # The cannon's flash.


func test_a_target_nearer_than_the_muzzle_leaves_the_muzzle_on_the_target() -> void:
	var shooter: Vector2i = Vector2i(10000, 20000)
	var target: Vector2i = Vector2i(10100, 20000)  # 6.4 px away, and the muzzle is 13 px out.
	_tick_with(Rig.shot(shooter, target, _weapon(&"rifle")))
	var to_px: Vector2 = ViewScale.milli_to_px_vec(target.x, target.y)
	assert_vector(_layer.line_from(1)).is_equal_approx(to_px, TOL)
	assert_vector(_layer.line_to(1)).is_equal(to_px)
	_now_ms += 1000
	_tick_with(Rig.shot(shooter, shooter, _weapon(&"tank_cannon")))  # On top of each other.
	var on_shooter: Vector2 = ViewScale.milli_to_px_vec(shooter.x, shooter.y)
	assert_vector(_layer.quad_rect(0).get_center()).is_equal_approx(on_shooter, TOL)


func test_an_impact_draws_a_puff_where_the_shell_came_down() -> void:
	var landing: Vector2i = Vector2i(12500, 9500)
	var landing_px: Vector2 = ViewScale.milli_to_px_vec(landing.x, landing.y)
	# STYLE.md: 40 px for a tank shell and 56 for a rocket, from 0.6 of that on the first frame.
	# The first shell hit a unit (7), the second came down on nothing (0): both show a puff.
	for case: Array in [[&"tank_cannon", 40.0, 7], [&"rocket", 56.0, 0]]:
		_now_ms += 1000
		_tick_with(Rig.impact(landing, _weapon(case[0]), 3, case[2]))
		assert_int(_layer.line_count()).is_equal(0)
		assert_int(_layer.quad_count()).is_equal(1)
		assert_that(_layer.quad_region(0)).is_equal(PUFF)
		assert_vector(_layer.quad_rect(0).get_center()).is_equal_approx(landing_px, TOL)
		assert_float(_layer.quad_rect(0).size.x).is_equal_approx(case[1] * 0.6, 0.001)
		_now_ms += 200  # Grown by now.
		_layer._process(0.0)
		assert_float(_layer.quad_rect(0).size.x).is_equal_approx(case[1], 0.001)


func test_a_vehicle_death_bursts_and_an_infantry_death_fades() -> void:
	var place: Vector2i = Vector2i(15000, 8000)
	var place_px: Vector2 = ViewScale.milli_to_px_vec(place.x, place.y)
	var tank: int = _type(&"light_tank")
	var squad: int = _type(&"rifle_squad")
	_tick_with(Rig.died(place, tank))
	assert_int(_layer.quad_count()).is_equal(1)
	assert_that(_layer.quad_region(0)).is_equal(BURST)  # A burst, 80 px, from half of that.
	assert_vector(_layer.quad_rect(0).get_center()).is_equal_approx(place_px, TOL)
	assert_float(_layer.quad_rect(0).size.x).is_equal_approx(40.0, 0.001)
	_now_ms += 1000
	_tick_with(Rig.died(place, squad))
	assert_int(_layer.quad_count()).is_equal(1)
	assert_that(_layer.quad_region(0)).is_equal(PUFF)  # A fade: the puff, 24 px, at 0.7.
	assert_float(_layer.quad_rect(0).size.x).is_equal_approx(24.0, 0.001)
	assert_float(_layer.quad_alpha(0)).is_equal_approx(0.7, 0.0001)
	# The class is the armour column of the type and nothing else, whatever the type is named:
	# the tank made INFANTRY fades, the squad made HEAVY bursts, and so does a building.
	_runner.snapshot.type_armour[tank] = World.Armour.INFANTRY
	_runner.snapshot.type_armour[squad] = World.Armour.HEAVY
	_now_ms += 1000
	_tick_with(Rig.died(place, tank))
	assert_that(_layer.quad_region(0)).is_equal(PUFF)
	_now_ms += 1000
	_tick_with(Rig.died(place, squad))
	assert_that(_layer.quad_region(0)).is_equal(BURST)
	_runner.snapshot.type_armour[squad] = World.Armour.BUILDING
	_now_ms += 1000
	_tick_with(Rig.died(place, squad))
	assert_that(_layer.quad_region(0)).is_equal(BURST)


func test_a_neutral_unit_shoots_and_dies_like_any_other() -> void:
	# The owner-0 design note of rows P44a and P44b: an armed neutral acquires every player's
	# units, so its shots and its death reach the layer, which reads no owner and no fog. Owner 0
	# against player 1, from the real sim: the first shot is the neutral's or the player's.
	_build(Rig.duel(Vector2i(0, 1)))
	_runner.world.hp[0] = 1
	_runner.world.hp[1] = 1
	var shots: int = 0
	for _i: int in 60:
		_runner.run_ticks(1)
		for at: int in range(0, _runner.snapshot.events.size(), World.EVENT_STRIDE):
			shots += int(_runner.snapshot.events[at] == World.Event.SHOT)
		if shots > 0:
			break
	assert_int(shots).is_greater(0)
	_layer._process(0.0)
	assert_int(_layer.line_count()).is_equal(2 * shots)  # Rifle squads: a tracer for each.
	_now_ms += 1000
	_tick_with(Rig.died(Vector2i(8000, 5000), _type(&"light_tank"), 4, 0))  # Owner 0.
	assert_int(_layer.quad_count()).is_equal(1)
	assert_that(_layer.quad_region(0)).is_equal(BURST)


func test_a_shell_that_overflowed_the_pool_has_a_shot_and_no_impact_and_shows_a_flash() -> void:
	# P42b: with no slot free the damage lands at once and the SHOT has no IMPACT. The snapshot has
	# no overflow count, so the layer shows what any projectile SHOT gets, the flash, and no puff.
	var scenario: ScenarioDef = Rig.battle()
	scenario.rules = scenario.rules.duplicate()  # Never the shared, cached resource.
	scenario.rules.max_projectiles = 1
	_build(scenario)
	var overflowed: bool = false
	for _i: int in 300:
		var before: int = _runner.world.projectile_overflow
		_now_ms += 1000  # The effects of the ticks before are gone.
		_runner.run_ticks(1)
		_layer._process(0.0)
		if _runner.world.projectile_overflow > before:
			overflowed = true
			break
	assert_bool(overflowed).is_true()
	var snap: MatchSnapshot = _runner.snapshot
	var events: PackedInt32Array = snap.events
	var cannon: int = _weapon(&"tank_cannon")
	var shots: int = 0
	var cannon_shots: int = 0
	var impacts: int = 0
	var infantry_deaths: int = 0
	for at: int in range(0, events.size(), World.EVENT_STRIDE):
		shots += int(events[at] == World.Event.SHOT)
		cannon_shots += int(events[at] == World.Event.SHOT and events[at + 5] == cannon)
		impacts += int(events[at] == World.Event.IMPACT)
		if events[at] == World.Event.DIED:
			infantry_deaths += int(snap.type_armour[events[at + 4]] == World.Armour.INFANTRY)
	# The one slot is taken (by this tick's shell or one in flight) and a tank shot found no slot.
	assert_int(snap.proj_id.size()).is_equal(1)
	assert_int(snap.proj_id[0]).is_not_equal(0)
	assert_int(cannon_shots).is_greater(0)
	assert_int(_count_regions(FLASH)).is_equal(shots)  # A flash for every shot, overflowed or not.
	assert_int(_count_regions(PUFF)).is_equal(impacts + infantry_deaths)  # And a puff per IMPACT.
	assert_int(_layer.line_count()).is_equal(2 * (shots - cannon_shots))  # Tracers: rifles only.


func test_the_ring_never_grows_past_its_capacity_and_the_oldest_effect_is_overwritten() -> void:
	_layer.capacity = 4
	assert_int(_layer.active_count()).is_equal(0)
	var cannon: int = _weapon(&"tank_cannon")
	for index: int in 6:  # Six flashes, 2 tiles apart in x: the first two are overwritten.
		_tick_with(Rig.shot(Vector2i(2000 * index, 1000), Vector2i(2000 * index, 9000), cannon))
		assert_int(_layer.active_count()).is_equal(mini(index + 1, 4))
	assert_int(_layer.quad_count()).is_equal(4)
	# Planned oldest first, so the newest is painted on top: shots 2 to 5 at x 4000 to 10000.
	for index: int in 4:
		var expected_x: float = ViewScale.milli_to_px(2000 * (index + 2))
		assert_float(_layer.quad_rect(index).get_center().x).is_equal_approx(expected_x, 0.001)
	# A tick with more events than the ring holds keeps the newest ones.
	_now_ms += 1000
	var many: PackedInt32Array = PackedInt32Array()
	for index: int in 9:
		many.append_array(
			Rig.shot(Vector2i(1000 * index, 1000), Vector2i(1000 * index, 9000), cannon)
		)
	_tick_with(many)
	assert_int(_layer.active_count()).is_equal(4)
	var first_x: float = _layer.quad_rect(0).get_center().x
	var last_x: float = _layer.quad_rect(3).get_center().x
	assert_float(first_x).is_equal_approx(ViewScale.milli_to_px(5000), 0.001)
	assert_float(last_x).is_equal_approx(ViewScale.milli_to_px(8000), 0.001)
	_layer.capacity = 0  # A ring has a slot at least, and a new ring is empty.
	assert_int(_layer.capacity).is_equal(1)
	assert_int(_layer.active_count()).is_equal(0)


func test_effects_expire_after_their_lifetime_on_the_frame_clock() -> void:
	# STYLE.md lifetimes in ms: flash 100, tracer 120, puff 350, burst 600, infantry fade 700. A
	# case is the events of the tick and the ms after which nothing of them is alive.
	var rifle: int = _weapon(&"rifle")
	var cases: Array = [
		[Rig.shot(Vector2i(1000, 1000), Vector2i(1000, 9000), _weapon(&"tank_cannon")), 100],
		[Rig.shot(Vector2i(1000, 1000), Vector2i(1000, 9000), rifle), 120],  # Flash 100, tracer 120.
		[Rig.impact(Vector2i(3000, 3000), _weapon(&"tank_cannon")), 350],
		[Rig.died(Vector2i(3000, 3000), _type(&"light_tank")), 600],
		[Rig.died(Vector2i(3000, 3000), _type(&"rifle_squad")), 700],
	]
	for case: Array in cases:
		_now_ms = 5000  # Not 0: a lifetime is an age and not a time.
		_tick_with(case[0])
		assert_int(_layer.active_count()).is_greater(0)
		_now_ms = 5000 + case[1] - 1
		_layer._process(0.0)
		assert_int(_layer.active_count()).is_greater(0)
		assert_int(_layer.line_count() + _layer.quad_count()).is_greater(0)
		_now_ms = 5000 + case[1]
		_layer._process(0.0)
		assert_int(_layer.active_count()).is_equal(0)
		assert_int(_layer.line_count() + _layer.quad_count()).is_equal(0)
	# The rifle's flash goes at 100 ms and its tracer stays to 120.
	_now_ms = 9000
	_tick_with(Rig.shot(Vector2i(1000, 1000), Vector2i(1000, 9000), rifle))
	assert_int(_layer.active_count()).is_equal(2)
	_now_ms = 9100
	_layer._process(0.0)
	assert_int(_layer.active_count()).is_equal(1)
	assert_int(_layer.line_count()).is_equal(2)
	assert_int(_layer.quad_count()).is_equal(0)


func test_only_lines_and_atlas_quads_are_drawn() -> void:
	# ADR 0011 section 3: one _draw(), per-item drawing with straight lines and quads of one
	# atlas only. Pixels cannot be read headless, so the script is: every draw call it makes is
	# draw_line or draw_texture_rect_region, the quads take the atlas, and there is one _draw().
	var source: String = ""
	for line: String in FileAccess.get_file_as_string(SCRIPT_PATH).split("\n"):
		source += line.get_slice("#", 0) + "\n"
	var calls: Array[String] = []
	var at: int = source.find("draw_")
	while at >= 0:
		var open: int = source.find("(", at)
		var call_name: String = source.substr(at, open - at)
		if not calls.has(call_name):
			calls.append(call_name)
		at = source.find("draw_", open)
	assert_array(calls).is_equal(["draw_line", "draw_texture_rect_region"])
	assert_int(source.count("func _draw()")).is_equal(1)
	assert_int(source.count("draw_texture_rect_region(ATLAS, ")).is_equal(1)
	assert_str(source).contains('preload("res://assets/art/svg/fx/effects_atlas.svg")')
	# And what it painted is its plan: the lines and the quads that were planned.
	_tick_with(Rig.shot(Vector2i(1000, 1000), Vector2i(1000, 9000), _weapon(&"rifle")))
	_tick_with(Rig.impact(Vector2i(3000, 3000), _weapon(&"rocket")))
	await await_idle_frame()
	assert_int(_layer.drawn_lines()).is_equal(2)
	assert_int(_layer.drawn_quads()).is_equal(2)  # The flash and the puff.
	assert_int(_layer.line_count()).is_equal(2)
	assert_int(_layer.quad_count()).is_equal(2)


func test_a_new_match_empties_the_ring() -> void:
	_tick_with(Rig.shot(Vector2i(1000, 1000), Vector2i(1000, 9000), _weapon(&"rifle")))
	_tick_with(Rig.died(Vector2i(3000, 3000), _type(&"light_tank")))
	assert_int(_layer.active_count()).is_equal(3)  # Flash, tracer and burst; the clock is at 0.
	_runner.start()  # A new match_serial; a start emits no ticked.
	_layer._process(0.0)
	assert_int(_layer.active_count()).is_equal(0)
	assert_int(_layer.line_count() + _layer.quad_count()).is_equal(0)
	_tick_with(Rig.impact(Vector2i(3000, 3000), _weapon(&"rocket")))  # The new match fills it.
	assert_int(_layer.active_count()).is_equal(1)
	# When the first thing the new match sends is a tick, the old match goes before its events.
	_runner.start()
	_runner.snapshot.events = Rig.impact(Vector2i(4000, 4000), _weapon(&"rocket"))
	_runner.ticked.emit(_runner.snapshot.tick)
	assert_int(_layer.active_count()).is_equal(1)


## Frees the runner and the layer and makes them anew for `scenario`: the runner started, the
## layer on the fake clock and out of the frame loop. The dp is the one in force now.
func _build(scenario: ScenarioDef) -> void:
	if is_instance_valid(_layer):
		_layer.free()
	if is_instance_valid(_runner):
		_runner.free()
	_now_ms = 0
	_runner = auto_free(MatchRunner.new())
	_runner.scenario = scenario
	_runner.start()
	_layer = auto_free(EffectsLayer.new())
	_layer.runner = _runner
	_layer.reveal_enemies = true  # The effects are the subject, not the fog (test_fog_hiding.gd).
	_layer.clock = func() -> int: return _now_ms
	add_child(_layer)
	_layer.set_process(false)


## Delivers `events` as the events of a tick, the way the runner does, then plans a frame.
func _tick_with(events: PackedInt32Array) -> void:
	_runner.snapshot.events = events
	_runner.ticked.emit(_runner.snapshot.tick)
	_layer._process(0.0)


func _weapon(weapon_id: StringName) -> int:
	return _runner.snapshot.weapon_ids.find(weapon_id)


func _type(type_id: StringName) -> int:
	return _runner.snapshot.type_ids.find(type_id)


## The unit ids of the DIED records of `events`.
func _died_ids(events: PackedInt32Array) -> Array[int]:
	var ids: Array[int] = []
	for at: int in range(0, events.size(), World.EVENT_STRIDE):
		if events[at] == World.Event.DIED:
			ids.append(events[at + 1])
	return ids


## Quads of the plan that show the region `region`.
func _count_regions(region: Rect2) -> int:
	var found: int = 0
	for index: int in _layer.quad_count():
		found += int(_layer.quad_region(index) == region)
	return found
