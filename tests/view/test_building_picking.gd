extends GdUnitTestSuite
## What BuildingLayer tells the Picker and the bars about a building (plan P115b, ADR 0023 section
## 3): `fill_pick_snapshot` lists the shown buildings with their diamond, the height of their
## picture and their sort key on the screen of a camera; the picture's top comes from the sprite on
## the atlas, so it is as tall as the region says; a shape is at least 48 dp a side at zoom 0.75
## on every screen; the fog keeps an enemy building out; and `set_selected` keeps the buildings
## among the ids, until they die. On a 32 x 32 map: player 1's Headquarters (3x3, row 0, id 1),
## power plant (2x2, id 2) and Redoubt (1x1, id 3), player 2's Headquarters (3x3, id 4) and defence
## (1x1, id 5) and player 1's light tank (id 6, row 5). Enemy buildings are shown unless a case is
## about the fog.

const Rig: GDScript = preload("res://tests/view/support/building_rig.gd")
const UiProfiles: GDScript = preload("res://tests/support/ui_profiles.gd")
const ScreenSizes: GDScript = preload("res://tests/support/screen_sizes.gd")
const SPAWNS: Array[Array] = [
	[1, "headquarters", 4, 4],
	[1, "power_plant", 10, 4],
	[1, "defence_turret", 14, 4],
	[2, "renew_hq", 4, 12],
	[2, "renew_defence", 10, 12],
	[1, "light_tank", 20, 20],
]
const FOOT: Array[int] = [3, 2, 1, 3, 1]
const OWNERS: Array[int] = [1, 1, 1, 2, 2]
const ZOOMS: Array[float] = [0.75, 1.0, 1.5]
## The profile of each of the six screens (ScreenSizes.ALL, entry by entry).
const PROFILES: Array[StringName] = [
	&"desktop",
	&"android_6in",
	&"web_tablet",
	&"desktop_portrait",
	&"android_6in_portrait",
	&"web_tablet_portrait",
]

var _runner: MatchRunner
var _camera: RtsCamera
var _layer: BuildingLayer
var _snap: PickSnapshot = PickSnapshot.new()


func before_test() -> void:
	var spawns: Array[SpawnDef] = []
	for entry: Array in SPAWNS:
		spawns.append(Rig.spawn(entry[0], entry[1], entry[2], entry[3]))
	_runner = auto_free(Rig.runner(Rig.scenario(spawns)))
	_camera = auto_free(RtsCamera.new())
	add_child(_camera)
	_camera.position = Vector2(0, 400)  # No map rect is set, so nothing clamps it.
	_layer = auto_free(BuildingLayer.new())
	_layer.runner = _runner
	_layer.reveal_enemies = true
	add_child(_layer)
	_layer.set_process(false)
	_layer._process(0.0)


func after_test() -> void:
	UiScale.clear_override()
	CommandQueue.clear()


func test_the_pick_snapshot_lists_every_building_with_its_diamond_and_sort_key() -> void:
	for zoom: float in ZOOMS:
		_camera.zoom = Vector2(zoom, zoom)
		_layer.fill_pick_snapshot(_snap, _camera)
		assert_int(_snap.building_count()).is_equal(5)
		for row: int in 5:
			var note: String = "row %d zoom %s" % [row, zoom]
			var node: Node2D = _layer.building(row + 1)
			assert_int(_snap.building_ids[row]).override_failure_message(note).is_equal(row + 1)
			assert_int(_snap.building_owners[row]).override_failure_message(note).is_equal(
				OWNERS[row]
			)
			assert_that(_snap.building_centres[row]).override_failure_message(note).is_equal(
				_camera.world_to_screen(node.position)
			)
			assert_vector(_snap.building_half[row]).override_failure_message(note).is_equal_approx(
				Vector2(32, 16) * (FOOT[row] * zoom), Vector2(0.001, 0.001)
			)
			assert_float(_snap.building_keys[row]).override_failure_message(note).is_equal(
				node.position.y
			)
	assert_int(_snap.size()).is_equal(0)  # The unit arrays are not this layer's to fill.


func test_the_pictures_height_comes_from_the_atlas_region_down_to_the_diamonds_corner() -> void:
	_layer.fill_pick_snapshot(_snap, _camera)  # Zoom 1: base px are world px.
	var snap: MatchSnapshot = _runner.snapshot
	var sort: WorldSort = _layer.world_sort
	for row: int in 5:
		var art_id: StringName = snap.type_ids[snap.type_index[row]]
		var sheet: IsoSheetDef = sort.sheet(art_id)
		var region: Rect2i = sort.atlas.region(art_id, &"hull", BuildingLayer.NO_FRAME, row / 3)
		var note: String = str(art_id)
		assert_bool(region.has_area()).override_failure_message(note).is_true()
		# The picture is the region at 0.5 / bake_scale a texel; its origin is the footprint centre.
		var scale: float = WorldSort.ART_SCALE / sort.atlas.bake_scale()
		var rise: float = _snap.building_rise[row]
		assert_float(rise).override_failure_message(note).is_equal_approx(
			float(sheet.origin(&"hull").y) * WorldSort.ART_SCALE, 0.01
		)
		# So the region's bottom edge is the diamond's bottom corner: the picture fills the shape.
		(
			assert_float(rise + _snap.building_half[row].y)
			. override_failure_message(note)
			. is_equal_approx(region.size.y * scale, 0.5)
		)
		assert_float(rise).is_greater_equal(_snap.building_half[row].y)
	# A taller picture reaches higher: the 3x3 hall over the 1x1 redoubt.
	assert_float(_snap.building_rise[0]).is_greater(_snap.building_rise[2])


func test_a_building_with_no_picture_is_the_flat_footprint_diamond() -> void:
	_layer.world_sort.atlas = IsoAtlas.new()  # An atlas that did not bake: the marker stands in.
	_runner.start()
	_layer._process(0.0)
	_layer.fill_pick_snapshot(_snap, _camera)
	assert_int(_snap.building_count()).is_equal(5)
	for row: int in 5:
		assert_float(_snap.building_rise[row]).is_equal(_snap.building_half[row].y)
		assert_float(_layer.frame_box(row).size.y).is_equal(2.0 * _snap.building_half[row].y)


func test_an_enemy_building_the_fog_hides_is_not_listed_until_a_cell_of_it_is_seen() -> void:
	_layer.reveal_enemies = false
	Rig.see(_runner.snapshot, 1, [])
	_layer._process(0.0)
	_layer.fill_pick_snapshot(_snap, _camera)
	assert_array(_snap.building_ids).is_equal([1, 2, 3])  # Own buildings: always.
	Rig.see(_runner.snapshot, 1, [Vector2i(6, 14)])  # A corner cell of the enemy Headquarters.
	_layer.fill_pick_snapshot(_snap, _camera)
	assert_array(_snap.building_ids).is_equal([1, 2, 3, 4])
	assert_array(_snap.building_owners).is_equal([1, 1, 1, 2])
	Rig.see(_runner.snapshot, 1, [Vector2i(7, 14)])  # Just outside its footprint.
	_layer.fill_pick_snapshot(_snap, _camera)
	assert_array(_snap.building_ids).is_equal([1, 2, 3])


func test_a_refill_replaces_the_rows_of_the_last_fill() -> void:
	_layer.fill_pick_snapshot(_snap, _camera)
	_layer.fill_pick_snapshot(_snap, _camera)
	assert_int(_snap.building_count()).is_equal(5)
	assert_int(_snap.building_centres.size()).is_equal(5)
	assert_int(_snap.building_keys.size()).is_equal(5)
	var idle: BuildingLayer = auto_free(BuildingLayer.new())  # Its runner has no snapshot yet.
	idle.runner = auto_free(MatchRunner.new())
	add_child(idle)
	idle.fill_pick_snapshot(_snap, _camera)
	assert_int(_snap.building_count()).is_equal(0)
	assert_int(_snap.building_half.size()).is_equal(0)


func test_every_shape_is_at_least_48_dp_a_side_at_zoom_075_on_every_screen() -> void:
	_camera.zoom = Vector2(0.75, 0.75)
	var sizes: Array[Vector2i] = []
	for profile_name: StringName in PROFILES:
		var profile: UiMetrics = UiProfiles.by_name(profile_name)
		sizes.append(profile.window_size)
		UiScale.set_override(profile)
		var settings: InputSettings = load("res://data/input_settings.tres")
		var min_half: float = UiScale.dp(settings.hit_radius_dp)
		_layer.fill_pick_snapshot(_snap, _camera)
		for row: int in 5:
			var at: Vector2 = _snap.building_centres[row]
			var one: PickSnapshot = _alone(row)
			var left: float = INF
			var right: float = -INF
			var top: float = INF
			var bottom: float = -INF
			for step: int in range(-400, 401):
				var offset: float = step * 0.5
				if Picker.pick_building(one, at + Vector2(offset, 0), 1, false, min_half) >= 0:
					left = minf(left, offset)
					right = maxf(right, offset)
				if Picker.pick_building(one, at + Vector2(0, offset), 1, false, min_half) >= 0:
					top = minf(top, offset)
					bottom = maxf(bottom, offset)
			var note: String = "%s row %d" % [profile_name, row]
			var wide: float = right - left
			assert_float(wide).override_failure_message(note).is_greater_equal(2.0 * min_half - 0.5)
			assert_float(bottom - top).override_failure_message(note).is_greater_equal(
				2.0 * min_half - 0.5
			)
			# And a shape the art already makes large is not made larger: the footprint's width.
			if 2.0 * _snap.building_half[row].x >= 2.0 * min_half:
				assert_float(wide).override_failure_message(note).is_less_equal(
					2.0 * _snap.building_half[row].x + 0.5
				)
	assert_array(sizes).is_equal(ScreenSizes.ALL)  # 1280x720, 2400x1080, 2048x1536, both ways.


func test_selected_keeps_the_buildings_among_the_ids_and_nothing_else() -> void:
	_layer.set_selected(PackedInt32Array([6, 2, 99]))  # A tank, a power plant and no one.
	assert_array(_layer.selected_ids()).is_equal([2])
	assert_bool(_layer.is_selected(1)).is_true()
	for row: int in [0, 2, 3, 4, 5, -1, 99]:
		assert_bool(_layer.is_selected(row)).override_failure_message(str(row)).is_false()
	_layer.set_selected(PackedInt32Array([4, 1]))  # Replaces the last selection.
	assert_array(_layer.selected_ids()).is_equal([4, 1])
	assert_bool(_layer.is_selected(1)).is_false()
	assert_bool(_layer.is_selected(3)).is_true()
	_layer.set_selected(PackedInt32Array())
	assert_array(_layer.selected_ids()).is_empty()
	assert_bool(_layer.is_selected(0)).is_false()


func test_a_selected_building_that_is_destroyed_leaves_the_selection_and_so_does_a_new_match(
) -> void:
	_layer.set_selected(PackedInt32Array([1, 2]))
	_runner.world.hp[1] = 0  # The power plant dies in the next tick.
	_runner.run_ticks(1)
	_layer._process(0.0)
	assert_array(_layer.selected_ids()).is_equal([1])
	_runner.start()  # Another match: the ids mean other buildings.
	_layer._process(0.0)
	assert_array(_layer.selected_ids()).is_empty()


func test_the_frame_box_is_the_footprints_width_from_the_pictures_top_to_the_bottom_corner(
) -> void:
	_layer.fill_pick_snapshot(_snap, _camera)
	var snap: MatchSnapshot = _runner.snapshot
	for row: int in 5:
		var box: Rect2 = _layer.frame_box(row)
		var at: Vector2 = _layer.building(row + 1).position
		var half: Vector2 = Vector2(32, 16) * FOOT[row]
		var rise: float = _snap.building_rise[row]
		assert_vector(box.position).is_equal_approx(at - Vector2(half.x, rise), Vector2(0.01, 0.01))
		assert_vector(box.size).is_equal_approx(
			Vector2(2.0 * half.x, rise + half.y), Vector2(0.01, 0.01)
		)
		assert_float(box.end.y).is_equal_approx(at.y + half.y, 0.01)
		assert_float(box.get_center().x).is_equal_approx(at.x, 0.01)
	assert_that(_layer.frame_box(5)).is_equal(Rect2())  # A tank is no building.
	assert_that(_layer.frame_box(-1)).is_equal(Rect2())
	assert_that(_layer.frame_box(snap.unit_count())).is_equal(Rect2())


## The snapshot of the one building `row` of `_snap`: the others do not answer for its shape.
func _alone(row: int) -> PickSnapshot:
	var one: PickSnapshot = PickSnapshot.new()
	one.building_ids = _snap.building_ids.slice(row, row + 1)
	one.building_owners = _snap.building_owners.slice(row, row + 1)
	one.building_centres = _snap.building_centres.slice(row, row + 1)
	one.building_half = _snap.building_half.slice(row, row + 1)
	one.building_rise = _snap.building_rise.slice(row, row + 1)
	one.building_keys = _snap.building_keys.slice(row, row + 1)
	return one
