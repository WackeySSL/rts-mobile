extends GdUnitTestSuite
## The building animations in the match view (plan P144, ADR 0027 sections 4 and 5): a shown
## building whose sheet has an `anim` part gets one `Anim` child after its Body, anchored at the
## footprint centre, that loops its frames from a per-id phase. It holds frame 0 while the
## building is a site or offline (own and shown enemy), runs at `low_power_rate` for the local
## player's own buildings while it is short of power and resumes without a jump, never depends on
## an enemy owner's power, stays with `reduced`, writes its region only on a frame change, only for
## a shown building in the view rect grown by a tile, and never steps back after a pause.
## Fixtures: a paused runner whose tick and alpha the test sets (match time = (tick + alpha) x 1000
## / 15 ms), `_process` once for a frame. Player 1 (local): Signal Mast (`fossil_radar`, id 1, 16
## frames of 140 ms), Turbine Hall (`power_plant`, id 2, 4 of 90), a second Turbine Hall (id 3) and
## a Barracks (id 4, no `anim`); player 2: Relay Tower (`renew_radar`, id 5, 16 of 150) and Wind
## Park (`renew_power`, id 6, 6 of 90). They stand along the diagonal so one camera sees them all.

const Rig: GDScript = preload("res://tests/view/support/building_rig.gd")
const Recoil: GDScript = preload("res://tests/view/support/recoil_rig.gd")
const MAST: int = 1
const HALL: int = 2
const HALL_B: int = 3
const BARRACKS: int = 4
const RELAY: int = 5
const WIND: int = 6
const ANIMATED: Array[int] = [MAST, HALL, RELAY, WIND, HALL_B]
const SALT: int = 0x50000000  ## The phase's salt, restated.

var _runner: MatchRunner
var _layer: BuildingLayer
var _camera: RtsCamera
var _life: LifeSettings


func before_test() -> void:
	var spawns: Array[SpawnDef] = [
		Rig.spawn(1, "fossil_radar", 8, 8),
		Rig.spawn(1, "power_plant", 11, 11),
		Rig.spawn(1, "power_plant", 8, 14),
		Rig.spawn(1, "barracks", 14, 6),
		Rig.spawn(2, "renew_radar", 14, 14),
		Rig.spawn(2, "renew_power", 17, 17),
	]
	_runner = auto_free(Rig.runner(Rig.scenario(spawns)))
	for id: int in [MAST, HALL, HALL_B, BARRACKS, RELAY, WIND]:  # The ids the test names.
		assert_int(_runner.snapshot.index_of(id)).is_greater_equal(0)
	assert_int(_runner.snapshot.owner[_runner.snapshot.index_of(RELAY)]).is_equal(2)
	_power(1, 5, 10)
	_power(2, 5, 10)
	_life = Recoil.calmed(null)
	_camera = auto_free(RtsCamera.new())
	add_child(_camera)
	_layer = auto_free(BuildingLayer.new())
	_layer.runner = _runner
	_layer.life = _life
	_layer.camera = _camera
	_layer.reveal_enemies = true
	add_child(_layer)
	_layer.set_process(false)
	Recoil.at(_runner, 0, 0.0)  # Match time 0, whatever tick the start published.
	_layer._process(0.0)
	_camera.position = (_layer.building(MAST).position + _layer.building(WIND).position) * 0.5


func after_test() -> void:
	CommandQueue.clear()


func test_an_animated_building_has_one_anim_child_after_its_body_at_the_footprint_centre() -> void:
	_frame(0, 0.0)
	var bake: float = _layer.world_sort.atlas.bake_scale()
	for id: int in ANIMATED:
		var node: Node2D = _layer.building(id)
		var anims: int = 0
		for child: Node in node.get_children():
			anims += 1 if child.name == "Anim" else 0
		assert_int(anims).is_equal(1)
		var body: Sprite2D = node.get_node("Body")
		var anim: Sprite2D = node.get_node("Anim")
		assert_int(anim.get_index()).is_greater(body.get_index())
		assert_object(anim.get_parent()).is_same(node)  # Freed with the building.
		assert_vector(anim.position).is_equal(Vector2.ZERO)
		assert_int(anim.z_index).is_equal(0)
		assert_bool(anim.centered).is_false()
		var origin: Vector2 = Vector2(_sheet(id).origin(&"anim"))
		assert_vector(anim.offset).is_equal_approx(-origin * bake, Vector2.ONE * 0.001)
		var scale: Vector2 = Vector2.ONE * (WorldSort.ART_SCALE / bake)
		assert_vector(anim.scale).is_equal_approx(scale, Vector2.ONE * 0.0001)
		assert_that(anim.region_rect).is_equal(Rect2(_region(id, _want(id, 0.0))))  # Clock 0.
		assert_bool(anim.visible).is_true()
	# Dressed at frame 0, before any frame of the clock writes (a layer with no camera writes none).
	var bare: BuildingLayer = auto_free(BuildingLayer.new())
	bare.runner = _runner
	bare.life = _life
	bare.reveal_enemies = true
	add_child(bare)
	bare.set_process(false)
	bare._process(0.0)
	for id: int in ANIMATED:
		assert_that(bare.building(id).get_node("Anim").region_rect).is_equal(Rect2(_region(id, 0)))
	# A building with no `anim` part has none.
	assert_object(_layer.building(BARRACKS).get_node_or_null("Anim")).is_null()


func test_the_frame_follows_the_loop_from_the_per_id_phase_at_full_rate() -> void:
	var seen: Dictionary[int, Dictionary] = {MAST: {}, HALL: {}, RELAY: {}, WIND: {}}
	for step: int in 400:  # 6.7 s at 60 fps.
		_frame(step / 4, float(step % 4) * 0.25)
		var ms: float = LifeClock.ms(_runner.snapshot, _runner.alpha())
		for id: int in seen:
			var want: int = _want(id, ms)
			(
				assert_that(_anim(id).region_rect)
				. override_failure_message("id %d step %d want frame %d" % [id, step, want])
				. is_equal(Rect2(_region(id, want)))
			)
			seen[id][want] = true
	for id: int in seen:
		assert_int(seen[id].size()).is_equal(_sheet(id).frame_count(&"anim"))


func test_two_buildings_of_a_kind_turn_out_of_step_and_the_phase_is_the_same_every_run() -> void:
	var apart: int = 0
	for step: int in 60:
		_frame(step / 4, float(step % 4) * 0.25)
		apart += 1 if _anim(HALL).region_rect != _anim(HALL_B).region_rect else 0
	assert_int(apart).is_greater(0)
	var frames: int = _sheet(HALL).frame_count(&"anim")
	assert_int(BuildingAnims.phase_ms(HALL, frames, 90)).is_equal(
		LifeClock.mix(HALL, SALT) % (frames * 90)
	)
	assert_int(BuildingAnims.phase_ms(HALL, frames, 90)).is_not_equal(
		BuildingAnims.phase_ms(HALL_B, frames, 90)
	)
	# A second layer on the same snapshot shows the same frames.
	var other: BuildingLayer = auto_free(BuildingLayer.new())
	other.runner = _runner
	other.life = _life
	other.camera = _camera
	other.reveal_enemies = true
	add_child(other)
	other.set_process(false)
	other._process(0.0)
	_frame(7, 0.5)
	other._process(0.0)
	for id: int in ANIMATED:
		assert_that(other.building(id).get_node("Anim").region_rect).is_equal(_anim(id).region_rect)


func test_a_site_and_an_offline_building_hold_frame_0_and_resume_with_the_clock() -> void:
	var snap: MatchSnapshot = _runner.snapshot
	var base: int = 0  # Ticks: the clock never goes back, so each building has its own stretch.
	for id: int in [MAST, RELAY]:  # Own and shown enemy.
		var row: int = snap.index_of(id)
		var moved: int = 0
		for step: int in 40:  # Playing: not on frame 0 all the time.
			_frame(base + step / 4, float(step % 4) * 0.25)
			moved += 1 if _anim(id).region_rect != Rect2(_region(id, 0)) else 0
		assert_int(moved).is_greater(0)
		snap.build_left[row] = 30
		for step: int in 40:
			_frame(base + 10 + step / 4, float(step % 4) * 0.25)
			assert_that(_anim(id).region_rect).is_equal(Rect2(_region(id, 0)))
		snap.build_left[row] = 0
		_frame(base + 20, 0.0)
		assert_that(_anim(id).region_rect).is_equal(
			Rect2(_region(id, _want(id, LifeClock.tick_ms(base + 20))))
		)
		# Offline until tick base + 60: held through the tick before, playing from it on.
		snap.offline_until[row] = base + 60
		_frame(base + 40, 0.0)
		assert_that(_anim(id).region_rect).is_equal(Rect2(_region(id, 0)))
		_frame(base + 59, 0.75)
		assert_that(_anim(id).region_rect).is_equal(Rect2(_region(id, 0)))
		_frame(base + 60, 0.0)
		assert_that(_anim(id).region_rect).is_equal(
			Rect2(_region(id, _want(id, LifeClock.tick_ms(base + 60))))
		)
		snap.offline_until[row] = 0
		base += 200


func test_an_own_building_slows_to_the_low_power_rate_and_resumes_without_a_jump() -> void:
	var snap: MatchSnapshot = _runner.snapshot
	_life.low_power_rate = 0.5
	var own_ms: float = 0.0
	var last_ms: float = 0.0
	var max_step: int = 0
	var last_frame: int = _want(MAST, 0.0)
	var frames: int = _sheet(MAST).frame_count(&"anim")
	for step: int in 720:  # 12 s: full, low (4 s), full.
		var low: bool = step >= 240 and step < 480
		# Full speed with power to spare (5 of 10) and with exactly enough (10 of 10, the last 2 s).
		_power(1, 20 if low else (10 if step >= 600 else 5), 10)
		_frame(step / 4, float(step % 4) * 0.25)
		var ms: float = LifeClock.ms(snap, _runner.alpha())
		own_ms += (ms - last_ms) * (0.5 if low else 1.0)
		last_ms = ms
		var want: int = _want(MAST, own_ms)
		assert_that(_anim(MAST).region_rect).is_equal(Rect2(_region(MAST, want)))
		# The enemy's Relay Tower follows the match time, whatever the local power does.
		assert_that(_anim(RELAY).region_rect).is_equal(Rect2(_region(RELAY, _want(RELAY, ms))))
		max_step = maxi(max_step, posmod(want - last_frame, frames))
		last_frame = want
	assert_int(max_step).is_less_equal(1)  # Never a jump: a frame at most.
	assert_float(own_ms).is_equal_approx(12000.0 - 0.5 * 4000.0, 70.0)


func test_an_enemy_building_keeps_its_rate_when_its_owner_is_short_of_power() -> void:
	_power(2, 90, 10)
	for step: int in 200:
		_frame(step / 4, float(step % 4) * 0.25)
		var ms: float = LifeClock.ms(_runner.snapshot, _runner.alpha())
		assert_that(_anim(WIND).region_rect).is_equal(Rect2(_region(WIND, _want(WIND, ms))))
	# The local player short of power slows its own and not the enemy's.
	_power(1, 50, 10)
	for step: int in 200:
		_frame(50 + step / 4, float(step % 4) * 0.25)
		var ms: float = LifeClock.ms(_runner.snapshot, _runner.alpha())
		assert_that(_anim(WIND).region_rect).is_equal(Rect2(_region(WIND, _want(WIND, ms))))


func test_reduced_effects_keep_the_animations() -> void:
	_life.reduced = true
	var frames: Dictionary[Rect2, bool] = {}
	for step: int in 80:
		_frame(step / 4, float(step % 4) * 0.25)
		frames[_anim(MAST).region_rect] = true
	assert_int(frames.size()).is_greater(4)


func test_a_region_is_written_only_when_the_frame_changes() -> void:
	var writes: int = _layer.life_writes()
	var changes: int = 0
	var last: Dictionary[int, Rect2] = {}
	for id: int in ANIMATED:
		last[id] = _anim(id).region_rect
	for step: int in 240:
		_frame(step / 4, float(step % 4) * 0.25)
		for id: int in ANIMATED:
			var now: Rect2 = _anim(id).region_rect
			changes += 1 if now != last[id] else 0
			last[id] = now
	assert_int(_layer.life_writes() - writes).is_equal(changes)
	assert_int(changes).is_greater(0)
	assert_int(changes).is_less(ANIMATED.size() * 60)  # Not a write for every frame.
	var before: int = _layer.life_writes()
	_layer._process(0.0)  # The same tick and alpha again: no frame moved.
	assert_int(_layer.life_writes()).is_equal(before)


func test_only_a_shown_building_in_the_view_rect_grown_by_a_tile_is_written() -> void:
	# A hidden enemy (fog): left as it is.
	_layer.reveal_enemies = false
	Rig.see(_runner.snapshot, 1, [])
	_frame(1, 0.0)
	assert_bool(_layer.is_shown(_runner.snapshot.index_of(WIND))).is_false()
	var hidden: Rect2 = _anim(WIND).region_rect
	_frame(60, 0.0)
	assert_that(_anim(WIND).region_rect).is_equal(hidden)
	_layer.reveal_enemies = true
	Rig.see(_runner.snapshot, 1, [])  # A new fog version: the layer reads who is shown again.
	_frame(61, 0.0)
	assert_that(_anim(WIND).region_rect).is_equal(
		Rect2(_region(WIND, _want(WIND, LifeClock.tick_ms(61))))
	)
	# Out of view: not written. 8 px beyond the grown rect, then 8 px inside it.
	var at: Vector2 = _layer.building(MAST).position
	var reach: float = (
		_camera.visible_world_rect().size.x * 0.5 + (float(IsoProjection.HALF_W) * 2.0)
	)  # One tile, restated
	_camera.position = at + Vector2(reach + 8.0, 0.0)
	var stale: Rect2 = _anim(MAST).region_rect
	_frame(100, 0.0)
	assert_that(_anim(MAST).region_rect).is_equal(stale)
	_camera.position = at + Vector2(reach - 8.0, 0.0)
	_frame(101, 0.0)
	assert_that(_anim(MAST).region_rect).is_equal(
		Rect2(_region(MAST, _want(MAST, LifeClock.tick_ms(101))))
	)
	# No camera: nothing is in view.
	var shown: Rect2 = _anim(MAST).region_rect
	_layer.camera = null
	_frame(130, 0.0)
	assert_that(_anim(MAST).region_rect).is_equal(shown)


func test_the_frame_never_steps_back_after_a_pause_or_a_resume() -> void:
	_frame(30, 0.9)
	var shown: Rect2 = _anim(RELAY).region_rect
	_frame(30, 0.0)  # A resume restarts alpha at 0: match time steps back by 0.9 of a tick.
	assert_that(_anim(RELAY).region_rect).is_equal(shown)
	_frame(30, 0.5)
	assert_that(_anim(RELAY).region_rect).is_equal(shown)
	_frame(31, 0.0)  # Caught up: the loop goes on from where it was.
	assert_that(_anim(RELAY).region_rect).is_equal(
		Rect2(_region(RELAY, _want(RELAY, LifeClock.tick_ms(31))))
	)


func test_the_box_covers_the_moving_element_and_the_bar_lift_is_the_sheets() -> void:
	var snap: MatchSnapshot = _runner.snapshot
	for id: int in ANIMATED:
		var row: int = snap.index_of(id)
		var sheet: IsoSheetDef = _sheet(id)
		var body_top: float = float(sheet.origin(&"hull").y) * WorldSort.ART_SCALE
		var anim_top: float = float(sheet.origin(&"anim").y) * WorldSort.ART_SCALE
		var half_h: float = float(IsoProjection.HALF_H * sheet.footprint)
		var box: Rect2 = _layer.frame_box(row)
		var node_y: float = _layer.building(id).position.y
		var want: float = maxf(maxf(body_top, anim_top), half_h)
		assert_float(node_y - box.position.y).is_equal_approx(want, 0.01)
		assert_float(node_y - box.position.y).is_greater_equal(anim_top - 0.01)
		# The bar's lift is the sheet's: the pose three of four stay under, a few px below the
		# highest frame (P143 moved the Signal Mast's to 122 and the Deep Bore's to 143).
		assert_float(_layer.bar_lift_px(row)).is_equal(float(sheet.bar_lift_px))
		assert_float(float(node_y - box.position.y) - _layer.bar_lift_px(row)).is_between(
			-1.0, 12.0
		)


func test_a_new_match_starts_the_loops_afresh() -> void:
	_frame(40, 0.0)
	_runner.start()
	_power(1, 5, 10)
	_frame(0, 0.0)
	assert_that(_anim(MAST).region_rect).is_equal(Rect2(_region(MAST, _want(MAST, 0.0))))


## The frame the rule gives for building `id` at full rate with `ms` on its clock.
func _want(id: int, ms: float) -> int:
	var sheet: IsoSheetDef = _sheet(id)
	var frames: int = sheet.frame_count(&"anim")
	var phase: int = LifeClock.mix(id, SALT) % (frames * sheet.anim_ms)
	return int((float(phase) + ms) / float(sheet.anim_ms)) % frames


func _power(player: int, used: int, made: int) -> void:
	_runner.snapshot.power_used[player] = used
	_runner.snapshot.power_made[player] = made


func _sheet(id: int) -> IsoSheetDef:
	var snap: MatchSnapshot = _runner.snapshot
	return _layer.world_sort.sheet(snap.type_ids[snap.type_index[snap.index_of(id)]])


## The region of frame `frame` of the `anim` part of building `id`, for its owner, read from the
## atlas by key (not by the layer's base).
func _region(id: int, frame: int) -> Rect2i:
	var snap: MatchSnapshot = _runner.snapshot
	var owner_id: int = snap.owner[snap.index_of(id)]
	var sort: WorldSort = _layer.world_sort
	return sort.atlas.region(_sheet(id).art_id, &"anim", -1, sort.slot_of(owner_id), frame)


func _anim(id: int) -> Sprite2D:
	return _layer.building(id).get_node("Anim") as Sprite2D


## One frame at tick `tick` and alpha `alpha`.
func _frame(tick: int, alpha: float) -> void:
	Recoil.at(_runner, tick, alpha)
	_layer._process(0.0)
