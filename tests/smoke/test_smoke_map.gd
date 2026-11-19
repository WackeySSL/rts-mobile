extends GdUnitTestSuite
## The `--map` flag of the smoke run (P554), without playing a match: which scenario files a kind
## picks on Heron Fords (map_2) and Curlew Crags (map_3), the rotation of `all`, and the map of a
## scenario file. A new suite, because test_smoke_run.gd holds gdlint's 20 public methods.

const Smoke: GDScript = preload("res://tests/smoke/smoke_run.gd")


## The same four kinds on each map; every file exists and belongs to its map.
func test_the_map_picks_the_scenario_files_of_that_map() -> void:
	var stems: Dictionary[String, String] = {
		"heron": "skirmish_heron_fords",
		"curlew": "skirmish_curlew_crags",
	}
	for map: String in stems:
		var stem: String = "res://data/scenarios/%s" % stems[map]
		assert_str(Smoke.scenario_path("cross", 1, map)).is_equal(stem + ".tres")
		assert_str(Smoke.scenario_path("cross", 2, map)).is_equal(stem + "_mirrored.tres")
		assert_str(Smoke.scenario_path("derrick", 2, map)).is_equal(stem + ".tres")
		assert_str(Smoke.scenario_path("lumen", 1, map)).is_equal(stem + "_mirrored.tres")
		assert_str(Smoke.scenario_path("fossil-mirror", 1, map)).is_equal(
			stem + "_fossil_mirror.tres"
		)
		assert_str(Smoke.scenario_path("renew-mirror", 1, map)).is_equal(
			stem + "_renew_mirror.tres"
		)
		for kind: String in Smoke.KINDS:
			var path: String = Smoke.scenario_path(kind, 1, map)
			assert_bool(ResourceLoader.exists(path)).is_true()
			assert_str(Smoke.map_of_path(path)).is_equal(map)


## The default map is Kestrel Flats; `all` plays six seeds as three maps from both seats.
func test_the_default_map_is_kestrel_and_all_rotates_by_seed() -> void:
	assert_str(Smoke.scenario_path("cross", 1)).is_equal(Smoke.FLATS)
	assert_str(Smoke.scenario_path("cross", 1, "kestrel")).is_equal(Smoke.FLATS)
	assert_str(Smoke.map_of_path(Smoke.FLATS_MIRRORED)).is_equal("kestrel")
	assert_str(Smoke.map_of_path("res://data/scenarios/perf_ai.tres")).is_empty()
	var seen: Dictionary[String, bool] = {}
	var maps: Dictionary[String, bool] = {}
	for match_seed: int in range(1, 7):
		var path: String = Smoke.scenario_path("cross", match_seed, "all")
		seen[path] = true
		maps[Smoke.map_of_path(path)] = true
		assert_bool(ResourceLoader.exists(path)).is_true()
	assert_int(seen.size()).is_equal(6)
	assert_array(maps.keys()).contains_exactly_in_any_order(["kestrel", "heron", "curlew"])
	# The rotation itself: the map of seed n is MAPS[n mod 3], so a changed formula breaks this.
	assert_str(Smoke.map_of_seed("all", 1)).is_equal("heron")
	assert_str(Smoke.map_of_seed("all", 2)).is_equal("curlew")
	assert_str(Smoke.map_of_seed("all", 3)).is_equal("kestrel")
	assert_str(Smoke.map_of_seed("all", 4)).is_equal("heron")
	assert_str(Smoke.map_of_seed("all", 1002)).is_equal("kestrel")
	assert_str(Smoke.map_of_seed("curlew", 1)).is_equal("curlew")
	assert_array(Smoke.MAP_CHOICES).is_equal(["kestrel", "heron", "curlew", "all"])
