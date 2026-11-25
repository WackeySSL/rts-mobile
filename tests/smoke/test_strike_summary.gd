extends GdUnitTestSuite
## The strike block of the balance summary (plan row P571, ADR 0047 section 12): the eleven keys of
## a player entry summed per faction and per level, the mean per fire in hundredths, and an older
## report that has none of the keys.

const Smoke: GDScript = preload("res://tests/smoke/smoke_run.gd")
const Summary: GDScript = preload("res://tests/smoke/balance_summary.gd")
const SmokeCount: GDScript = preload("res://tests/smoke/smoke_count.gd")
const StrikeSummary: GDScript = preload("res://tests/smoke/strike_summary.gd")


func test_the_keys_are_summed_per_faction_and_level_with_the_victims_numbers_per_fire() -> void:
	var matches: Array[Dictionary] = _matches(2, ["normal", "hard"])
	# Match 1: fossil fires the rupture twice; renew blacks out once and fossil is its victim.
	_put(matches[0], 0, "strike_fires_rupture", 2)
	_put(matches[0], 0, "strike_damage_enemy", 1500)
	_put(matches[0], 0, "strike_damage_own", 600)
	_put(matches[0], 0, "strike_kills_buildings", 3)
	_put(matches[0], 0, "strike_kills_units", 1)
	_put(matches[0], 0, "strike_kills_own", 1)
	_put(matches[0], 0, "blackout_building_ticks", 450)
	_put(matches[0], 0, "sight_cut_building_ticks", 300)
	_put(matches[0], 0, "sight_cells_lost", 90)
	_put(matches[0], 0, "radar_dark_ticks", 150)
	_put(matches[0], 1, "strike_fires_blackout", 1)
	_put(matches[0], 1, "strike_damage_enemy", 400)
	_put(matches[0], 1, "strike_kills_buildings", 1)
	# Match 2: the same again for fossil, nothing for renew.
	_put(matches[1], 0, "strike_fires_rupture", 2)
	_put(matches[1], 0, "strike_damage_enemy", 500)
	var strikes: Dictionary = _merge(matches)["summary"]["strikes"]
	var fossil: Dictionary = strikes["by_faction"]["fossil"]
	assert_int(fossil["player_matches"]).is_equal(2)
	assert_int(fossil["fires"]).is_equal(4)
	assert_int(fossil["totals"]["strike_damage_enemy"]).is_equal(2000)
	assert_int(fossil["totals"]["strike_kills_buildings"]).is_equal(3)
	assert_int(fossil["totals"]["blackout_building_ticks"]).is_equal(450)
	# Per fire in hundredths: 2000 over 4 fires is 500.00; the victim keys of fossil's fires are
	# renew's, which are 0.
	assert_int(fossil["per_fire"]["damage_enemy"]).is_equal(50000)
	assert_int(fossil["per_fire"]["damage_own"]).is_equal(15000)
	assert_int(fossil["per_fire"]["kills_buildings"]).is_equal(75)
	assert_int(fossil["per_fire"]["kills_units"]).is_equal(25)
	assert_int(fossil["per_fire"]["kills"]).is_equal(100)
	assert_int(fossil["per_fire"]["kills_own"]).is_equal(25)
	assert_int(fossil["per_fire"]["blackout_building_seconds"]).is_equal(0)
	var renew: Dictionary = strikes["by_faction"]["renew"]
	assert_int(renew["fires"]).is_equal(1)
	assert_int(renew["per_fire"]["damage_enemy"]).is_equal(40000)
	# The victim side of renew's blackout is fossil's: 450 ticks are 30 s of building time.
	assert_int(renew["per_fire"]["blackout_building_seconds"]).is_equal(3000)
	assert_int(renew["per_fire"]["sight_cut_building_seconds"]).is_equal(2000)
	assert_int(renew["per_fire"]["sight_cells_lost"]).is_equal(9000)
	assert_int(renew["per_fire"]["radar_dark_seconds"]).is_equal(1000)
	# The levels differ, so the same numbers come per level.
	assert_array(strikes["by_level"].keys()).contains_exactly_in_any_order(["normal", "hard"])
	assert_dict(strikes["by_level"]["normal"]["totals"]).is_equal(fossil["totals"])
	assert_dict(strikes["by_level"]["hard"]["per_fire"]).is_equal(renew["per_fire"])


func test_the_markdown_has_a_strikes_table_only_when_something_fired() -> void:
	var matches: Array[Dictionary] = _matches(1, ["normal", "hard"])
	_put(matches[0], 1, "strike_fires_blackout", 1)
	_put(matches[0], 1, "strike_damage_enemy", 400)
	_put(matches[0], 0, "blackout_building_ticks", 450)
	var text: String = Summary.markdown(_merge(matches))
	assert_str(text).contains("### Strikes")
	assert_str(text).contains("| faction renew | 1 | 400.00 | 0.00 | 0.00 | 0.00 | 0.00 | 30.00 |")
	assert_str(text).contains("| level hard | 1 |")
	assert_str(Summary.markdown(_merge(_matches(1, ["normal", "hard"])))).not_contains("Strikes")


func test_a_report_without_the_keys_still_summarises() -> void:
	var old: Array[Dictionary] = _matches(2, ["normal", "normal"])
	for record: Dictionary in old:
		for player: Dictionary in record["players"]:
			for key: String in SmokeCount.STRIKE_KEYS:
				assert_bool(player.has(key)).is_false()
	var merged: Dictionary = _merge(old)
	var strikes: Dictionary = merged["summary"]["strikes"]
	assert_array(strikes.keys()).contains_exactly(["by_faction"])  # Same level on both seats.
	for faction: String in ["fossil", "renew"]:
		var group: Dictionary = strikes["by_faction"][faction]
		assert_int(group["fires"]).is_equal(0)
		for key: String in SmokeCount.STRIKE_KEYS:
			assert_int(group["totals"][key]).is_equal(0)
		for name: String in group["per_fire"]:
			assert_int(group["per_fire"][name]).is_equal(0)
	assert_str(Summary.markdown(merged)).not_contains("Strikes")
	assert_str(Summary.markdown(merged)).contains("## Balance summary")


## The numbers of a report file are floats after the JSON round trip; the block reads them as ints.
func test_the_block_survives_a_json_round_trip() -> void:
	var matches: Array[Dictionary] = _matches(1, ["normal", "normal"])
	_put(matches[0], 0, "strike_fires_rupture", 2)
	_put(matches[0], 0, "strike_damage_enemy", 1001)
	var path: String = "user://p571_report.json"
	assert_bool(Smoke.write_report(path, _report(matches, ["normal", "normal"]))).is_true()
	var loaded: Dictionary = Summary.load_report(path)
	assert_bool(loaded.has("error")).is_false()
	var reports: Array[Dictionary] = [loaded]
	var names: Array[String] = ["a.json"]
	var built: Dictionary = Summary.build(reports, names, false)
	var group: Dictionary = built["report"]["summary"]["strikes"]["by_faction"]["fossil"]
	assert_int(group["totals"]["strike_damage_enemy"]).is_equal(1001)
	assert_int(group["per_fire"]["damage_enemy"]).is_equal(50050)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


## The Dusk radar counts (P577c) are summed per faction and listed in the table; a report without
## them counts 0.
func test_the_dusk_radar_counts_are_summed_and_listed() -> void:
	var matches: Array[Dictionary] = _matches(2, ["normal", "normal"])
	_put(matches[0], 1, "strike_fires_blackout", 3)
	_put(matches[0], 1, "dusk_fires_radar_known", 2)
	_put(matches[0], 1, "dusk_fires_radar_coverable", 1)
	_put(matches[0], 1, "dusk_fires_radar_chosen", 1)
	_put(matches[1], 1, "strike_fires_blackout", 1)
	_put(matches[1], 1, "dusk_fires_radar_known", 1)
	var strikes: Dictionary = _merge(matches)["summary"]["strikes"]
	var renew: Dictionary = strikes["by_faction"]["renew"]
	assert_int(renew["radar_fires"]["dusk_fires_radar_known"]).is_equal(3)
	assert_int(renew["radar_fires"]["dusk_fires_radar_coverable"]).is_equal(1)
	assert_int(renew["radar_fires"]["dusk_fires_radar_chosen"]).is_equal(1)
	var fossil: Dictionary = strikes["by_faction"]["fossil"]
	assert_int(fossil["radar_fires"]["dusk_fires_radar_known"]).is_equal(0)
	var lines: PackedStringArray = PackedStringArray()
	StrikeSummary.append_lines(strikes, lines)
	assert_bool("\n".join(lines).contains("| faction renew | 4 | 3 | 1 | 1 |")).is_true()


func _matches(count: int, levels: Array[String]) -> Array[Dictionary]:
	var matches: Array[Dictionary] = []
	for index: int in count:
		var record: Dictionary = {
			"seed": 1001 + index,
			"scenario": Smoke.FLATS,
			"ticks": 8000,
			"end": "victory",
			"winner": 1,
			"match_end_tick": 8000,
			"state_hash": "%016x" % index,
			"dropped_commands": 0,
			"spawn_refused": 0,
			"flow_full_ticks": 0,
			"players": [],
		}
		for side: int in 2:
			(
				record["players"]
				. append(
					{
						"player": side + 1,
						"faction": "fossil" if side == 0 else "renew",
						"seat": "top" if side == 0 else "bottom",
						"level": levels[side],
						"produced": {},
						"free": {},
						"lost": {},
						"kills": {},
						"spent": {},
						"commands": 0,
					}
				)
			)
		matches.append(record)
	return matches


func _put(record: Dictionary, side: int, key: String, value: Variant) -> void:
	record["players"][side][key] = value


func _report(matches: Array[Dictionary], levels: Array[String]) -> Dictionary:
	var names: Array[String] = levels
	return {
		"schema": 2,
		"status": "ok",
		"commit": "abc123",
		"impl": "native",
		"ticks_per_match": 13500,
		"seed_start": 1001,
		"matches_requested": matches.size(),
		"levels": names,
		"scenarios": "cross",
		"matches": matches.duplicate(true),
	}


## The merged report of `matches` (the levels are those of its first match's seats).
func _merge(matches: Array[Dictionary]) -> Dictionary:
	var levels: Array[String] = [
		String(matches[0]["players"][0]["level"]), String(matches[0]["players"][1]["level"])
	]
	var names: Array[String] = ["a.json"]
	var reports: Array[Dictionary] = [_report(matches, levels)]
	var built: Dictionary = Summary.build(reports, names, false)
	assert_bool(built.has("report")).override_failure_message(str(built)).is_true()
	return built.get("report", {})
