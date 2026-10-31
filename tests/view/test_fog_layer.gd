extends GdUnitTestSuite
## What FogLayer draws and when (plan P47, P117, ADR 0010 section 2, ADR 0023 section 2,
## assets/art/STYLE.md "Fog and terrain"): one RGBA8 texel of black per tile, drawn as that tile's
## diamond on the ground at z 4, with the alpha 255 (never seen), 140 (seen before) or 0 (seen
## now), read from `FogLayer.image()`, never from the ImageTexture, which reads back
## stale after `update()`; an upload only when the local player's fog version changed; a patch of
## the dirty list for an ordinary tick, a full rebuild for a new match, an overflowed list or a gap
## in the ticks. What the other layers hide by the fog is in test_fog_hiding.gd (gdlint allows 20
## public methods per file).
## On controls_test (Rig): 48 x 48 tiles, blue light tanks at tiles (8, 18) to (13, 23), red ones
## from (34, 10). The runner is not in the tree, so only the calls here move time. Exact cases write
## one update into the published snapshot's fog, as ADR 0012 section 3 lets a SYNC test do, and emit
## `ticked`; the others play the real sim and compare the image with the grids after every tick.

const MenuRig: GDScript = preload("res://tests/support/menu_rig.gd")
const Rig: GDScript = preload("res://tests/view/support/fog_rig.gd")
const EffectsRig: GDScript = preload("res://tests/view/support/effects_rig.gd")
const ScreenSizes: GDScript = preload("res://tests/support/screen_sizes.gd")
const MAIN_SCENE: String = "res://scenes/main.tscn"
const BASE_SIZE: Vector2i = ScreenSizes.LANDSCAPE[0]
## The screens every screen is tested at: base, 20:9 phone and 4:3 tablet, each held both ways.
const TARGET_SIZES: Array[Vector2i] = ScreenSizes.ALL
## ADR 0023 section 2: the z of the layers around the fog, bottom to top. The fog lies on the
## ground, under every unit (the sorted world is 10), bar and effect.
const Z_FOG: int = 4
const Z_BARS: int = 30
const Z_PROJECTILES: int = 40
const Z_EFFECTS: int = 50
const Z_MARKERS: int = 70
const CORNER_TOLERANCE: Vector2 = Vector2(0.001, 0.001)

var _window_size_before: Vector2i
var _runner: MatchRunner
var _fog: FogLayer


func before() -> void:
	_window_size_before = get_window().size


func after() -> void:
	get_window().size = _window_size_before


func before_test() -> void:
	MenuRig.begin()
	get_window().size = BASE_SIZE
	_runner = null
	_fog = null
	_build(Rig.scenario(1))


func after_test() -> void:
	MenuRig.end()
	CommandQueue.clear()


func test_the_image_is_cols_by_rows_in_black_with_the_alpha_of_each_tile_state() -> void:
	var image: Image = _fog.image()
	assert_that(image.get_size()).is_equal(Vector2i(48, 48))
	assert_int(image.get_format()).is_equal(Image.FORMAT_RGBA8)
	assert_array(Rig.mismatches(image, _runner.snapshot.fog, 1)).is_empty()
	# Tick 0: tank 1's own tile is clear, the far corner never seen, and nothing is dimmed yet.
	assert_int(image.get_pixel(8, 18).a8).is_equal(0)
	assert_int(image.get_pixel(47, 47).a8).is_equal(255)
	var start: Vector3i = Rig.tally(image)
	assert_int(start.x).is_greater(0)
	assert_int(start.y).is_equal(0)
	assert_int(start.z).is_greater(0)
	assert_int(start.x + start.y + start.z).is_equal(48 * 48)
	# Driving out leaves a dimmed trail: tiles that were seen and are not any more.
	_drive_blue_east(60)
	var later: Vector3i = Rig.tally(_fog.image())
	assert_int(later.y).is_greater(0)
	assert_int(later.x + later.y + later.z).is_equal(48 * 48)
	assert_array(Rig.mismatches(_fog.image(), _runner.snapshot.fog, 1)).is_empty()
	assert_int(_fog.image().get_pixel(2, 20).a8).is_equal(140)  # The west of the block: left behind.


func test_the_sprite_is_the_map_as_diamonds_one_per_texel_filtered_linearly_from_its_corner(
) -> void:
	assert_bool(_fog.centered).is_false()
	assert_that(_fog.position).is_equal_approx(Vector2.ZERO, CORNER_TOLERANCE)
	assert_int(_fog.texture_filter).is_equal(CanvasItem.TEXTURE_FILTER_LINEAR)
	assert_object(_fog.texture).is_not_null()
	assert_that(_fog.texture.get_size()).is_equal(Vector2(48, 48))
	assert_that(_fog.get_rect()).is_equal(Rect2(0, 0, 48, 48))  # In texels.
	# The axes are (32, 16) and (-32, 16) px per texel: a texel is a tile's diamond.
	var transform: Transform2D = _fog.get_global_transform()
	assert_that(transform.x).is_equal_approx(Vector2(32, 16), CORNER_TOLERANCE)
	assert_that(transform.y).is_equal_approx(Vector2(-32, 16), CORNER_TOLERANCE)
	assert_that(transform.origin).is_equal_approx(Vector2.ZERO, CORNER_TOLERANCE)
	# The four texel corners of the image are the map's diamond corners.
	var diamond: PackedVector2Array = IsoProjection.map_diamond(48, 48)
	var corners: Array[Vector2] = [Vector2(0, 0), Vector2(48, 0), Vector2(48, 48), Vector2(0, 48)]
	for index: int in 4:
		(
			assert_that(transform * corners[index])
			. override_failure_message(str(index))
			. is_equal_approx(diamond[index], CORNER_TOLERANCE)
		)
	# The tile of a point is the sim's: tank 1 stands on tile (8, 18), ground (8500, 18500), and the
	# middle of that texel is where its rig is drawn.
	assert_that(transform * Vector2(8.5, 18.5)).is_equal_approx(
		IsoProjection.ground_to_px(8500, 18500), CORNER_TOLERANCE
	)
	assert_int(_fog.image().get_pixel(8, 18).a8).is_equal(0)


func test_explored_alpha_is_the_export_and_a_change_repaints_at_the_next_frame() -> void:
	_drive_blue_east(60)
	var rebuilds: int = _fog.rebuild_count()
	assert_int(_fog.image().get_pixel(2, 20).a8).is_equal(140)
	_fog.explored_alpha = 90
	_fog._process(0.0)
	assert_int(_fog.rebuild_count()).is_equal(rebuilds + 1)
	assert_int(_fog.image().get_pixel(2, 20).a8).is_equal(90)
	assert_int(_fog.image().get_pixel(47, 47).a8).is_equal(255)  # Never seen stays black.
	assert_array(Rig.mismatches(_fog.image(), _runner.snapshot.fog, 1, 90)).is_empty()
	_fog._process(0.0)  # Nothing else changed: no second rebuild.
	assert_int(_fog.rebuild_count()).is_equal(rebuilds + 1)
	_fog.explored_alpha = 999  # An alpha is a byte.
	_fog._process(0.0)
	assert_int(_fog.image().get_pixel(2, 20).a8).is_equal(255)
	_fog.explored_alpha = -5
	_fog._process(0.0)
	assert_int(_fog.image().get_pixel(2, 20).a8).is_equal(0)
	assert_int(_fog.image().get_pixel(47, 47).a8).is_equal(255)  # Never seen stays black.


func test_uploads_rise_only_when_the_local_players_version_changes() -> void:
	for _tick: int in 12:  # Nothing moves: no flip, no upload.
		_runner.run_ticks(1)
	assert_int(_fog.upload_count()).is_equal(1)  # The first image.
	var fog_version: int = _runner.snapshot.fog.version_of(1)
	CommandQueue.submit(Command.move(1, _all_blue(), 22000, 21500))
	var changed: int = 0
	var quiet: int = 0
	for _tick: int in 45:
		var version: int = _runner.snapshot.fog.version_of(1)
		var uploads: int = _fog.upload_count()
		_runner.run_ticks(1)
		var moved: bool = _runner.snapshot.fog.version_of(1) != version
		assert_int(_fog.upload_count()).is_equal(uploads + (1 if moved else 0))
		changed += int(moved)
		quiet += int(not moved)
	assert_int(_runner.snapshot.fog.version_of(1)).is_not_equal(fog_version)
	assert_int(changed).is_greater(5)  # The player's updates, one tick in three.
	assert_int(quiet).is_greater(5)  # Every other tick uploads nothing.
	assert_int(_fog.rebuild_count()).is_equal(1)  # They were patches.


func test_a_dirty_update_patches_the_listed_cells_and_nothing_else() -> void:
	var snap: MatchSnapshot = _runner.snapshot
	var uploads: int = _fog.upload_count()
	var rebuilds: int = _fog.rebuild_count()
	var texture: Texture2D = _fog.texture
	Rig.flip(snap, 1, [Vector2i(30, 30), Vector2i(31, 30)] as Array[Vector2i], true)
	Rig.set_seen(snap, 1, Vector2i(5, 40), true)  # Changed in the grid and not listed.
	_runner.ticked.emit(snap.tick)
	# A patch updates the texture it has, and makes no new one (`update()` reads back stale, so
	# the pixels are checked on `image()`; that `update()` ran is the texture's `changed` signal,
	# counted in test_fog_layer_update.gd).
	assert_object(_fog.texture).is_same(texture)
	var image: Image = _fog.image()
	assert_int(image.get_pixel(30, 30).a8).is_equal(0)
	assert_int(image.get_pixel(31, 30).a8).is_equal(0)
	assert_int(image.get_pixel(5, 40).a8).is_equal(255)  # A patch writes the list and no more.
	assert_int(_fog.upload_count()).is_equal(uploads + 1)
	assert_int(_fog.rebuild_count()).is_equal(rebuilds)
	# Going dark again dims the tile (it was seen), and the frame's call changes nothing.
	Rig.flip(snap, 1, [Vector2i(30, 30)] as Array[Vector2i], false)
	_runner.ticked.emit(snap.tick)
	assert_int(image.get_pixel(30, 30).a8).is_equal(140)
	assert_int(image.get_pixel(31, 30).a8).is_equal(0)
	_fog._process(0.0)
	assert_int(_fog.upload_count()).is_equal(uploads + 2)


func test_an_overflowed_dirty_list_rebuilds_the_whole_image() -> void:
	var snap: MatchSnapshot = _runner.snapshot
	var rebuilds: int = _fog.rebuild_count()
	Rig.flip(snap, 1, [Vector2i(30, 30)] as Array[Vector2i], true)
	snap.fog.dirty_full[0] = 1  # A flip found the block full: the list is only a prefix.
	Rig.set_seen(snap, 1, Vector2i(5, 40), true)
	_runner.ticked.emit(snap.tick)
	assert_int(_fog.rebuild_count()).is_equal(rebuilds + 1)
	assert_int(_fog.image().get_pixel(5, 40).a8).is_equal(0)  # Not listed, still drawn.
	assert_array(Rig.mismatches(_fog.image(), snap.fog, 1)).is_empty()


func test_a_gap_in_the_ticks_rebuilds_the_whole_image() -> void:
	var snap: MatchSnapshot = _runner.snapshot
	var rebuilds: int = _fog.rebuild_count()
	Rig.flip(snap, 1, [Vector2i(30, 30)] as Array[Vector2i], true, 2)  # A tick was never seen.
	Rig.set_seen(snap, 1, Vector2i(5, 40), true)
	_runner.ticked.emit(snap.tick)
	assert_int(_fog.rebuild_count()).is_equal(rebuilds + 1)
	assert_int(_fog.image().get_pixel(5, 40).a8).is_equal(0)
	assert_array(Rig.mismatches(_fog.image(), snap.fog, 1)).is_empty()


func test_the_image_equals_the_grids_after_every_tick_of_a_march_with_no_rebuild() -> void:
	# Real dirty lists: the blue block drives east and the red one west, so both players' fog
	# moves. Single ticks, then a run of several (each one still emits `ticked`).
	CommandQueue.submit(Command.move(1, _all_blue(), 24000, 21500))
	CommandQueue.submit(Command.move(2, PackedInt32Array(range(31, 41)), 20000, 12000))
	for tick: int in 70:
		_runner.run_ticks(1 if tick < 40 else 5)
		var wrong: Array[int] = Rig.mismatches(_fog.image(), _runner.snapshot.fog, 1)
		assert_array(wrong).override_failure_message("tick %d" % tick).is_empty()
	assert_int(_fog.rebuild_count()).is_equal(1)  # Only the match start drew from the grids.
	assert_int(_fog.upload_count()).is_greater(10)


func test_the_first_update_of_each_player_loses_nothing_of_the_initial_stamp() -> void:
	# Player 1 updates on tick 0 and player 2 on tick 1, and an update empties its player's list,
	# the initial stamp's flips included: the image is built from the grids at the start.
	for player: int in [1, 2]:
		_build(Rig.scenario(player))
		var start: Vector3i = Rig.tally(_fog.image())
		assert_int(start.z).is_greater(0)  # The player's own tanks see their tiles.
		assert_int(_fog.rebuild_count()).is_equal(1)
		for tick: int in 8:
			_runner.run_ticks(1)
			var wrong: Array[int] = Rig.mismatches(_fog.image(), _runner.snapshot.fog, player)
			assert_array(wrong).override_failure_message("p%d tick %d" % [player, tick]).is_empty()
		assert_int(_fog.rebuild_count()).is_equal(1)
		assert_that(Rig.tally(_fog.image())).is_equal(start)  # Nobody moved.


func test_a_new_match_rebuilds_the_image_to_the_tick_0_state_without_a_tick() -> void:
	var tick_0: PackedByteArray = _fog.image().get_data()
	_drive_blue_east(60)
	assert_bool(_fog.image().get_data() == tick_0).is_false()
	var rebuilds: int = _fog.rebuild_count()
	var uploads: int = _fog.upload_count()
	_runner.start()  # Publishes the tick-0 snapshot of a new match and emits no `ticked`.
	_fog._process(0.0)
	assert_int(_fog.rebuild_count()).is_equal(rebuilds + 1)
	assert_int(_fog.upload_count()).is_equal(uploads + 1)
	assert_bool(_fog.image().get_data() == tick_0).is_true()  # After a restart: the tick-0 image.
	assert_array(Rig.mismatches(_fog.image(), _runner.snapshot.fog, 1)).is_empty()
	_runner.run_ticks(4)  # The new match's first updates patch nothing that did not move.
	assert_int(_fog.rebuild_count()).is_equal(rebuilds + 1)
	assert_bool(_fog.image().get_data() == tick_0).is_true()


func test_a_new_match_rebuilds_also_when_its_first_tick_is_the_first_the_layer_hears_of() -> void:
	_drive_blue_east(30)
	var rebuilds: int = _fog.rebuild_count()
	_runner.start()
	_runner.run_ticks(1)  # `ticked` of the new match, before any frame.
	assert_int(_fog.rebuild_count()).is_equal(rebuilds + 1)
	assert_array(Rig.mismatches(_fog.image(), _runner.snapshot.fog, 1)).is_empty()


func test_local_player_2_draws_the_fog_of_player_2_and_a_change_of_player_rebuilds() -> void:
	var of_one: PackedByteArray = _fog.image().get_data()
	_build(Rig.scenario(2))
	assert_array(Rig.mismatches(_fog.image(), _runner.snapshot.fog, 2)).is_empty()
	assert_bool(_fog.image().get_data() == of_one).is_false()
	assert_int(_fog.image().get_pixel(8, 18).a8).is_equal(255)  # The blue block: not red's to see.
	assert_int(_fog.image().get_pixel(34, 10).a8).is_equal(0)  # Red tank 31's own tile.
	var rebuilds: int = _fog.rebuild_count()
	var fog: FogGrid = _runner.snapshot.fog
	fog.version[0] = fog.version[1]  # The change of player is not seen in the version.
	_runner.scenario.local_player = 1  # A copy of the resource, so the shared one is untouched.
	_fog._process(0.0)
	assert_int(_fog.rebuild_count()).is_equal(rebuilds + 1)
	assert_bool(_fog.image().get_data() == of_one).is_true()


func test_a_player_the_fog_has_no_grid_for_gets_no_fog_and_sees_everything() -> void:
	var snap: MatchSnapshot = _runner.snapshot
	assert_bool(FogLayer.covers(snap.fog, 1)).is_true()
	assert_bool(FogLayer.covers(snap.fog, 2)).is_true()
	assert_bool(FogLayer.covers(snap.fog, 0)).is_false()
	assert_bool(FogLayer.covers(snap.fog, 3)).is_false()  # Two players.
	assert_bool(FogLayer.covers(FogGrid.new(), 1)).is_false()  # A snapshot with no map.
	assert_bool(FogLayer.is_seen(snap, 3, 40000, 40000)).is_true()
	assert_bool(FogLayer.is_seen(MatchSnapshot.new(), 1, 0, 0)).is_true()
	assert_int(FogLayer.local_player_of(_runner)).is_equal(1)
	assert_int(FogLayer.local_player_of(auto_free(MatchRunner.new()))).is_equal(1)  # No scenario.
	_runner.scenario.local_player = 3
	_fog._process(0.0)
	assert_object(_fog.texture).is_null()
	assert_that(_fog.image().get_size()).is_equal(Vector2i.ZERO)
	_runner.scenario.local_player = 1  # And back: drawn again from the grids.
	_fog._process(0.0)
	assert_object(_fog.texture).is_not_null()
	assert_array(Rig.mismatches(_fog.image(), snap.fog, 1)).is_empty()


func test_a_new_match_on_another_map_resizes_the_image_and_the_texture() -> void:
	assert_that(_fog.texture.get_size()).is_equal(Vector2(48, 48))
	_runner.scenario = EffectsRig.battle()  # 40 x 24 tiles.
	_runner.start()
	_fog._process(0.0)
	assert_that(_fog.image().get_size()).is_equal(Vector2i(40, 24))
	assert_that(_fog.texture.get_size()).is_equal(Vector2(40, 24))
	assert_array(Rig.mismatches(_fog.image(), _runner.snapshot.fog, 1)).is_empty()
	assert_that(_fog.get_rect()).is_equal(Rect2(0, 0, 40, 24))
	_runner.run_ticks(5)  # Patches on the new size.
	assert_array(Rig.mismatches(_fog.image(), _runner.snapshot.fog, 1)).is_empty()
	_runner.scenario = Rig.scenario(1)  # And back to the first map.
	_runner.start()
	_fog._process(0.0)
	assert_that(_fog.texture.get_size()).is_equal(Vector2(48, 48))
	assert_array(Rig.mismatches(_fog.image(), _runner.snapshot.fog, 1)).is_empty()


func test_a_rebuild_and_a_patch_each_record_their_own_time_and_an_idle_frame_none() -> void:
	assert_int(_fog.last_update_usec()).is_greater(0)  # The first rebuild, on the real clock.
	# A clock that reads 0 and 500 for a rebuild, 1,000 and 1,007 for a patch, and fails past that.
	var times: Array[int] = [0, 500, 1000, 1007]
	var reads: Array[int] = [0]
	_fog.usec_clock = func() -> int:
		reads[0] += 1
		return times[reads[0] - 1]
	_fog.explored_alpha = 90  # Another alpha repaints everything: a rebuild.
	_fog._process(0.0)
	assert_int(_fog.rebuild_count()).is_equal(2)
	assert_int(_fog.last_update_usec()).is_equal(500)
	_fog._process(0.0)  # Nothing changed: no update, no read of the clock, the time is kept.
	assert_int(reads[0]).is_equal(2)
	assert_int(_fog.last_update_usec()).is_equal(500)
	var snap: MatchSnapshot = _runner.snapshot
	Rig.flip(snap, 1, [Vector2i(30, 30)] as Array[Vector2i], true)
	_runner.ticked.emit(snap.tick)
	assert_int(_fog.rebuild_count()).is_equal(2)  # A patch.
	assert_int(_fog.upload_count()).is_equal(3)
	assert_int(_fog.last_update_usec()).is_equal(7)
	assert_int(reads[0]).is_equal(4)


func test_the_main_scene_draws_the_fog_at_z_4_under_every_object_and_covers_the_map_at_every_size(
) -> void:
	var packed: PackedScene = load(MAIN_SCENE)
	var main: Node2D = auto_free(packed.instantiate())
	add_child(main)
	await await_idle_frame()
	var fog: FogLayer = main.get_node("FogLayer")
	var camera: RtsCamera = main.get_node("Camera")
	var order: Array[String] = []
	for child: Node in main.get_children():
		order.append(String(child.name))
	assert_array(order.slice(0, 12)).is_equal(
		[
			"MatchRunner",
			"MapView",
			"GroundLayer",
			"DecalLayer",
			"WorldSort",
			"UnitLayer",
			"BuildingLayer",
			"HealthBarLayer",
			"ProjectileLayer",
			"EffectsLayer",
			"FogLayer",
			"MarkerLayer"
		]
	)
	assert_int(main.get_node("HealthBarLayer").z_index).is_equal(Z_BARS)
	assert_int(main.get_node("ProjectileLayer").z_index).is_equal(Z_PROJECTILES)
	assert_int(main.get_node("EffectsLayer").z_index).is_equal(Z_EFFECTS)
	assert_int(fog.z_index).is_equal(Z_FOG)
	assert_int(Z_FOG).is_less(WorldSort.Z_SORT)  # Under the sorted world: rigs and buildings.
	assert_int(Z_FOG).is_greater(WorldSort.Z_RING)  # Over the map (0), the shadows and the rings.
	assert_int(main.get_node("WorldSort").z_index).is_equal(WorldSort.Z_SORT)
	assert_bool(fog.z_as_relative).is_false()
	assert_int(main.get_node("MarkerLayer").z_index).is_equal(Z_MARKERS)
	assert_object(fog.runner).is_same(main.get_node("MatchRunner"))
	var map_px: Rect2 = IsoProjection.map_bounds(48, 48)  # The diamond's bounding rect.
	var diamond: PackedVector2Array = IsoProjection.map_diamond(48, 48)
	for size: Vector2i in TARGET_SIZES:
		get_window().size = size
		await await_idle_frame()
		# The view turned with the window, so the portrait sizes are run as portrait.
		var view: Vector2 = camera.get_viewport_rect().size
		assert_bool(view.y > view.x).override_failure_message(str(size)).is_equal(
			UiScale.is_portrait_size(size)
		)
		# The sprite is the map, whatever the screen: its bounding rect in world px, and the camera
		# at both ends of its range (its centre clamps into the diamond) stops at a tip of it.
		var rect: Rect2 = fog.get_global_transform() * fog.get_rect()
		assert_that(rect.position).is_equal_approx(map_px.position, CORNER_TOLERANCE)
		assert_that(rect.size).is_equal_approx(map_px.size, CORNER_TOLERANCE)
		for corner: Vector2 in [Vector2(-99999, -99999), Vector2(99999, 99999)]:
			camera.centre_on(corner)
			assert_bool(rect.grow(0.5).has_point(camera.position)).is_true()  # A tip is on its edge.
			assert_bool(diamond.has(camera.position.round())).is_true()
		# Unexplored tiles are black over most of the first screen of the match: the far corner of
		# the map, away from the blue block.
		assert_int(fog.image().get_pixel(47, 0).a8).is_equal(255)
	assert_int(fog.image().get_pixel(8, 18).a8).is_equal(0)


func _build(scenario: ScenarioDef) -> void:
	if is_instance_valid(_fog):
		_fog.free()
	if is_instance_valid(_runner):
		_runner.free()
	_runner = auto_free(MatchRunner.new())
	_runner.scenario = scenario
	_runner.start()
	_fog = auto_free(FogLayer.new())
	_fog.runner = _runner
	add_child(_fog)
	_fog.set_process(false)  # Frames come only from `_fog._process()`.


func _all_blue() -> PackedInt32Array:
	return PackedInt32Array(range(1, 31))


## Orders the blue block to drive east and plays `ticks` ticks.
func _drive_blue_east(ticks: int) -> void:
	CommandQueue.submit(Command.move(1, _all_blue(), 24000, 21500))
	_runner.run_ticks(ticks)
