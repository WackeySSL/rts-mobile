extends GdUnitTestSuite
## The selection ring fits the unit (P651): for every unit art (vehicles, flyers and squads of both
## factions) and each of the 16 headings, the ring's horizontal semi-axis is at least the hull's
## ground half-extent in that heading plus `RingSize.HULL_MARGIN_DP`, at the default zoom 2.0 and
## zoomed out; a selected heavy tank wears a larger ring than a light tank; and the layers and the
## cargo bar take the one size of `RingSize`.

const Rig: GDScript = preload("res://tests/view/support/building_rig.gd")
const Air: GDScript = preload("res://tests/view/support/air_rig.gd")
const UiProfiles: GDScript = preload("res://tests/support/ui_profiles.gd")
const ART_DIRS: Array[String] = ["veh", "inf"]
const ZOOMS: Array[float] = [2.0, 1.0, 0.75, 0.5]

var _runner: MatchRunner
var _camera: RtsCamera
var _layer: UnitLayer


func before_test() -> void:
	UiScale.set_override(UiProfiles.by_name(&"android_6in"))


func after_test() -> void:
	UiScale.clear_override()
	CommandQueue.clear()


func test_every_unit_art_has_a_ring_wider_than_its_hull_plus_the_margin_at_every_heading() -> void:
	var sheets: Array[IsoSheetDef] = _unit_sheets()
	assert_int(sheets.size()).is_greater(20)  # Both factions: vehicles, flyers and squads.
	for sheet: IsoSheetDef in sheets:
		var counts: int = sheet.counts[sheet.parts.find("hull")]
		for zoom: float in ZOOMS:
			var unit: float = UiScale.base_px_per_dp() / zoom
			# The smallest radius in the data, so that only the art can make the ring fit.
			var semi: float = RingSize.semi_px(350, sheet, unit)
			for step: int in 16:
				var dir: int = UnitLayer.frame_of(float(step) * TAU / 16.0, counts)
				var half: float = _hull_half_px(sheet, dir)
				var note: String = "%s heading %d zoom %s" % [sheet.art_id, step, zoom]
				assert_float(semi).override_failure_message(note).is_greater_equal(
					half + RingSize.HULL_MARGIN_DP * unit
				)


func test_the_ring_band_shows_clear_of_the_hull() -> void:
	for sheet: IsoSheetDef in _unit_sheets():
		var unit: float = UiScale.base_px_per_dp() / 2.0
		var semi: float = RingSize.semi_px(350, sheet, unit)
		var inner: float = semi * RingSize.INNER_EDGE_RATIO  # The band's dark inner edge.
		assert_float(inner).override_failure_message(String(sheet.art_id)).is_greater_equal(
			RingSize.footprint_px(sheet) + RingSize.HULL_MARGIN_DP * unit - 0.001
		)


func test_a_selected_heavy_tank_wears_a_visibly_larger_ring_than_a_light_tank() -> void:
	_open([Rig.spawn(1, "light_tank", 4, 4), Rig.spawn(1, "heavy_tank", 4, 10)])
	var snap: MatchSnapshot = _runner.snapshot
	var light: int = _row_of(&"light_tank")
	var heavy: int = _row_of(&"heavy_tank")
	_layer.set_selected(PackedInt32Array([snap.unit_id[light], snap.unit_id[heavy]]))
	_camera.zoom = Vector2(2.0, 2.0)
	_layer._process(0.0)
	var light_ring: UnitLayer.Ring = _layer.rig(light).get_node("Ring")
	var heavy_ring: UnitLayer.Ring = _layer.rig(heavy).get_node("Ring")
	assert_float(heavy_ring.radius).is_greater(light_ring.radius * 1.15)
	# The heavy tank's ring is not the 500 milli one of the data any more: its hull covers that.
	var old: float = IsoProjection.ellipse_px(500 + UnitLayer.RING_PAD_MILLI).x
	assert_float(heavy_ring.radius).is_greater(old * 1.5)
	var unit: float = UiScale.base_px_per_dp() / 2.0
	for row: int in [light, heavy]:
		var sheet: IsoSheetDef = _layer.world_sort.sheet(snap.type_ids[snap.type_index[row]])
		var ring: UnitLayer.Ring = _layer.rig(row).get_node("Ring")
		assert_float(ring.radius).is_equal_approx(
			RingSize.semi_px(snap.type_selection_radius[snap.type_index[row]], sheet, unit), 0.001
		)


func test_the_flyers_ring_and_the_cargo_bar_use_the_size_of_the_ground_layer() -> void:
	var runner: MatchRunner = auto_free(Air.runner())
	var camera: RtsCamera = auto_free(RtsCamera.new())
	add_child(camera)
	camera.zoom = Vector2(2.0, 2.0)
	var air: AirLayer = auto_free(Air.layer(self, runner))
	air.set_selected(PackedInt32Array([Air.FIGHTER_ID]))
	air._process(0.0)
	var snap: MatchSnapshot = runner.snapshot
	var row: int = 2  # The own fighter, see `Air`.
	var type: int = snap.type_index[row]
	var sheet: IsoSheetDef = air.world_sort.sheet(snap.type_ids[type])
	var zoom: float = air.get_canvas_transform().get_scale().x
	var unit: float = UiScale.base_px_per_dp() / zoom
	var ring: UnitLayer.Ring = air.rig_of(Air.FIGHTER_ID).ring
	assert_float(ring.radius).is_equal_approx(
		RingSize.semi_px(snap.type_selection_radius[type], sheet, unit), 0.001
	)
	# The cargo bar of a tanker hangs under the same ring.
	_open([Rig.spawn(1, "harvester", 4, 10)])
	_camera.zoom = Vector2(2.0, 2.0)
	var tanker: int = _row_of(&"harvester")
	var tsnap: MatchSnapshot = _runner.snapshot
	var ttype: int = tsnap.type_index[tanker]
	_layer._process(0.0)
	_layer.set_selected(PackedInt32Array([tsnap.unit_id[tanker]]))
	_layer._process(0.0)
	var tring: UnitLayer.Ring = _layer.rig(tanker).get_node("Ring")
	var low: float = tring.radius * IsoProjection.GROUND_FLATTEN
	var bar: TankerCargo = _layer.rig(tanker).cargo
	assert_float(bar.position.y).is_equal_approx(low + TankerCargo.GAP_DP * tring.unit, 0.001)
	assert_float(tring.radius).is_equal_approx(
		RingSize.semi_px(
			tsnap.type_selection_radius[ttype],
			_layer.world_sort.sheet(tsnap.type_ids[ttype]),
			tring.unit
		),
		0.001
	)


func _open(spawns: Array[SpawnDef]) -> void:
	_runner = auto_free(Rig.runner(Rig.scenario(spawns)))
	_camera = auto_free(RtsCamera.new())
	add_child(_camera)
	_layer = auto_free(UnitLayer.new())
	_layer.runner = _runner
	_layer.camera = _camera
	add_child(_layer)
	_layer.set_process(false)
	_layer._process(0.0)


func _row_of(type_id: StringName) -> int:
	var snap: MatchSnapshot = _runner.snapshot
	for row: int in snap.unit_count():
		if snap.type_ids[snap.type_index[row]] == type_id:
			return row
	return -1


## The half width of the hull's frame facing `dir`, world px at zoom 1, as the ring must clear it.
func _hull_half_px(sheet: IsoSheetDef, dir: int) -> float:
	var box: Rect2i = sheet.frame_box(&"hull", dir)
	var origin: Vector2i = sheet.origin(&"hull")
	var side: int = maxi(origin.x - box.position.x, box.end.x - origin.x)
	return float(side) * WorldSort.ART_SCALE


func _unit_sheets() -> Array[IsoSheetDef]:
	var found: Array[IsoSheetDef] = []
	for faction: String in DirAccess.get_directories_at(IsoSheetDef.ROOT):
		for category: String in ART_DIRS:
			var dir: String = IsoSheetDef.ROOT.path_join(faction).path_join(category)
			if not DirAccess.dir_exists_absolute(dir):
				continue
			for file: String in DirAccess.get_files_at(dir):
				if file.ends_with("_sheet.tres"):
					found.append(load(dir.path_join(file)) as IsoSheetDef)
	return found
