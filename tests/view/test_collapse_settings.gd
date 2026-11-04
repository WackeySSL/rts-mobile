extends GdUnitTestSuite
## The collapse numbers of `data/life_settings.tres` (plan P165, ADR 0029 section 13): their values,
## the order of the times, each `[min, max]`, one collapse's puffs against the ring, and the
## crater's scale of the refineries.

const FileScan: GDScript = preload("res://tests/support/file_scan.gd")
const PATH: String = "res://data/life_settings.tres"


func _file() -> LifeSettings:
	return load(PATH) as LifeSettings


func test_the_data_file_holds_the_documented_values() -> void:
	var file: LifeSettings = _file()
	assert_int(file.collapse_slots).is_equal(40)
	assert_int(file.collapse_max).is_equal(16)
	assert_int(file.collapse_flash_ms).is_equal(250)
	assert_array(file.collapse_fire_puffs).is_equal([2, 3])
	assert_array(file.collapse_sink_ms).is_equal([250, 700])
	assert_int(file.collapse_sink_steps).is_equal(6)
	assert_int(file.collapse_sink_percent).is_equal(60)
	assert_int(file.collapse_hide_ms).is_equal(700)
	assert_array(file.collapse_dust_ms).is_equal([250, 900])
	assert_int(file.collapse_dust_puffs).is_equal(8)
	assert_array(file.collapse_debris).is_equal([6, 8])
	assert_int(file.collapse_end_ms).is_equal(900)
	assert_int(file.collapse_spread_milli).is_equal(700)
	assert_int(file.collapse_fire_spread_milli).is_equal(350)
	var defaults: LifeSettings = LifeSettings.new()  # The script says the same.
	for field: String in ["collapse_slots", "collapse_max", "collapse_hide_ms", "collapse_end_ms"]:
		assert_that(defaults.get(field)).is_equal(file.get(field))
	assert_array(defaults.collapse_debris_fly_px).is_equal(file.collapse_debris_fly_px)
	assert_dict(defaults.crater_scale_milli).is_equal(file.crater_scale_milli)


func test_the_times_are_in_order() -> void:
	var file: LifeSettings = _file()
	assert_int(file.collapse_flash_ms).is_equal(file.collapse_sink_ms[0])  # Flash end = sink start.
	assert_int(file.collapse_sink_ms[1]).is_equal(file.collapse_hide_ms)  # Sink end = hide.
	assert_int(file.collapse_hide_ms).is_less(file.collapse_dust_ms[1])  # Hide < dust end.
	assert_int(file.collapse_dust_ms[1]).is_equal(file.collapse_end_ms)  # Dust end = collapse end.
	for pair: PackedInt32Array in [
		file.collapse_fire_puffs, file.collapse_sink_ms, file.collapse_dust_ms, file.collapse_debris
	]:
		assert_int(pair.size()).is_equal(2)
		assert_int(pair[0]).is_less_equal(pair[1])
	# A dust puff born at the start of the window lives out inside it.
	var window: int = file.collapse_dust_ms[1] - file.collapse_dust_ms[0]
	assert_int(file.collapse_dust_life_ms).is_less_equal(window)
	assert_int(file.collapse_sink_percent).is_between(1, 100)
	assert_int(file.collapse_sink_steps).is_greater(0)


func test_one_collapse_wants_at_most_half_the_ring_and_has_a_direction_for_each_chip() -> void:
	var file: LifeSettings = _file()
	var wanted: int = 1 + file.collapse_fire_puffs[1] + file.collapse_dust_puffs
	wanted += file.collapse_debris[1]
	assert_int(wanted).is_equal(20)
	assert_int(wanted * 2).is_less_equal(file.collapse_slots)
	assert_int(file.collapse_debris_fly_px.size()).is_greater_equal(file.collapse_debris[1])
	assert_int(file.collapse_debris_fly_px.size()).is_less_equal(CollapseFx.MAX_DIRECTIONS)
	assert_int(file.collapse_max * 2).is_less_equal(file.collapse_slots)


func test_every_refinery_leaves_a_crater_one_and_a_half_times_the_default() -> void:
	var file: LifeSettings = _file()
	assert_int(file.crater_scale_milli.get(&"refinery", 1000)).is_equal(1500)
	for path: String in FileScan.list_files("res://data/units", ".tres"):
		var unit: UnitDef = load(path) as UnitDef
		var scale: int = file.crater_scale_milli.get(unit.type_id, 1000)
		var refinery: bool = String(unit.type_id).ends_with("refinery")
		assert_int(scale).override_failure_message(String(unit.type_id)).is_equal(
			1500 if refinery else 1000
		)


func test_every_collapse_puff_dies_by_the_end_of_the_collapse() -> void:
	# CollapseFx counts a puff against the ring only until its collapse ends.
	var file: LifeSettings = _file()
	assert_int(file.collapse_sink_ms[0] + file.collapse_debris_ms).is_less_equal(
		file.collapse_end_ms
	)
	assert_int(file.collapse_flash_ms).is_less_equal(file.collapse_end_ms)  # Flash and fire, at 0.
	assert_int(file.collapse_dust_ms[0] + file.collapse_dust_life_ms).is_less_equal(
		file.collapse_dust_ms[1]
	)  # The first dust puff, and so the latest one (born by dust_ms[1] - life), end inside.
	assert_int(file.collapse_dust_ms[1]).is_less_equal(file.collapse_end_ms)
