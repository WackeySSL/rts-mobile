extends GdUnitTestSuite
## The match length per map and over all maps in the balance report (P554), on hand-written schema 2
## reports: no match is played here. A new suite, because test_balance_summary.gd holds gdlint's 20
## public methods.

const Summary: GDScript = preload("res://tests/smoke/balance_summary.gd")
const SCENARIOS: String = "res://data/scenarios/%s.tres"
## Seed, scenario and ticks of five matches on the three maps: the median of Heron Fords is 7500,
## of Curlew Crags 12750, of Kestrel Flats 7500, and over all five 9000.
const MATCHES: Array[Array] = [
	[1, "skirmish_heron_fords", 6000],
	[2, "skirmish_heron_fords_mirrored", 9000],
	[3, "skirmish_curlew_crags", 12000],
	[4, "skirmish_curlew_crags_mirrored", 13500],
	[5, "skirmish_kestrel_flats", 7500],
]

const FACTIONS: Array[String] = ["fossil", "renew"]

var _rosters: Dictionary[String, Array] = {}


func before() -> void:
	_rosters = Summary.rosters_of(FACTIONS)


func test_the_median_is_reported_per_map_and_over_all_maps() -> void:
	var merged: Dictionary = _build([_report("all")])["report"]
	assert_str(merged["map"]).is_equal("all")
	var length: Dictionary = merged["summary"]["length_ticks"]
	var by_map: Dictionary = merged["summary"]["length_by_map"]
	assert_int(length["median"]).is_equal(9000)
	assert_array(by_map.keys()).contains_exactly_in_any_order(["kestrel", "heron", "curlew"])
	assert_int(by_map["heron"]["matches"]).is_equal(2)
	assert_int(by_map["heron"]["median"]).is_equal(7500)
	assert_int(by_map["curlew"]["median"]).is_equal(12750)
	assert_int(by_map["curlew"]["p90"]).is_equal(13500)
	assert_int(by_map["kestrel"]["median"]).is_equal(7500)
	var text: String = Summary.markdown(merged)
	assert_str(text).contains("| Map | Matches | Median | 90th percentile |")
	assert_str(text).contains("| heron | 2 | 8.3 min | 10.0 min |")
	assert_str(text).contains("| curlew | 2 | 14.2 min | 15.0 min |")
	assert_str(text).contains("| kestrel | 1 | 8.3 min | 8.3 min |")
	assert_str(text).contains("| all maps | 5 | 10.0 min | 15.0 min |")


## Shards of two maps do not merge; a report from before the field has no map and keeps none.
func test_shards_of_two_maps_do_not_merge_and_an_older_report_has_no_map() -> void:
	var refused: Dictionary = _build([_report("heron"), _report("curlew")])
	assert_str(refused["error"]).contains("field 'map' differs")
	var older: Dictionary = _report("")
	older.erase("map")
	var merged: Dictionary = _build([older])["report"]
	assert_bool(merged.has("map")).is_false()
	assert_bool(merged["summary"]["length_by_map"].has("heron")).is_true()


## The merge of `reports`, named a.json, b.json and so on.
func _build(reports: Array[Dictionary]) -> Dictionary:
	var names: Array[String] = []
	for index: int in reports.size():
		names.append("%s.json" % char(97 + index))
	return Summary.build(reports, names, false)


## A report of the five MATCHES. `map` "" leaves the field at an empty text.
func _report(map: String) -> Dictionary:
	var matches: Array[Dictionary] = []
	for row: Array in MATCHES:
		matches.append(_match(int(row[0]), SCENARIOS % row[1], int(row[2])))
	return {
		"schema": 2,
		"status": "ok",
		"commit": "abc123",
		"impl": "native",
		"ticks_per_match": 13500,
		"seed_start": 1,
		"matches_requested": matches.size(),
		"levels": ["normal", "normal"],
		"scenarios": "cross",
		"map": map,
		"matches": matches,
	}


## A victory of player 1 (fossil, top) in `ticks`, with every unit type produced once.
func _match(match_seed: int, scenario: String, ticks: int) -> Dictionary:
	var players: Array[Dictionary] = []
	for index: int in 2:
		var faction: String = "fossil" if index == 0 else "renew"
		var made: Dictionary = {}
		for id: String in _rosters[faction]:
			made[id] = 1
		(
			players
			. append(
				{
					"player": index + 1,
					"faction": faction,
					"seat": "top" if index == 0 else "bottom",
					"ai": "opponent_" + faction,
					"level": "normal",
					"commands": 0,
					"produced": made,
					"free": {},
					"lost": {},
					"kills": {},
					"spent": {},
					"structures": {},
				}
			)
		)
	return {
		"seed": match_seed,
		"scenario": scenario,
		"ticks": ticks,
		"end": "victory",
		"winner": 1,
		"match_end_tick": ticks,
		"state_hash": "%016x" % (match_seed * 7919 + 1),
		"dropped_commands": 0,
		"spawn_refused": 0,
		"flow_full_ticks": 0,
		"players": players,
	}
