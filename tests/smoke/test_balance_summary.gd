extends GdUnitTestSuite
## The merge, summary, gate block and markdown of tests/smoke/balance_summary.gd (plan row P187,
## ADR 0031 sections 4 to 6), on hand-written schema 2 reports: no match is played here. The unit
## ids come from the faction rosters (`Summary.rosters_of`), never from literals, so a renamed or
## added unit cannot hide behind a stale id.

const Summary: GDScript = preload("res://tests/smoke/balance_summary.gd")
const Smoke: GDScript = preload("res://tests/smoke/smoke_run.gd")

## The markdown of `_balanced(4)` (match 1001 with one flow-full tick) merged with --gate.
const GOLDEN: String = "res://tests/smoke/fixtures/balance_summary_golden.md"
const FACTIONS: Array[String] = ["fossil", "renew"]

var _roster: Dictionary[String, Array] = {}
var _fossil: Array[String] = []
var _renew: Array[String] = []
## Folders of temp files; freeing a DirAccess removes its folder.
var _folders: Array[DirAccess] = []


func before() -> void:
	_roster = Summary.rosters_of(FACTIONS)
	_fossil.assign(_roster["fossil"])
	_renew.assign(_roster["renew"])


func after_test() -> void:
	_folders.clear()


func test_the_rosters_are_the_twelve_unit_types_and_a_missing_roster_is_refused() -> void:
	assert_int(_fossil.size()).is_equal(6)
	assert_int(_renew.size()).is_equal(6)
	# Every listed id is an Infantry or Vehicles type, never a structure.
	for faction: String in FACTIONS:
		var def: FactionDef = load("res://data/factions/%s.tres" % faction) as FactionDef
		for unit: UnitDef in def.roster:
			var listed: bool = _roster[faction].has(String(unit.type_id))
			var queued: bool = unit.tab in [World.Tab.INFANTRY, World.Tab.VEHICLES]
			assert_bool(listed).is_equal(queued)
	var nobody: Array[String] = ["nobody"]
	assert_int(Summary.rosters_of(nobody)["nobody"].size()).is_equal(0)
	# A faction without a roster file fails the merge with a message, never a silent gap.
	var ghost: Array[Dictionary] = [_match(1, "victory", 1, {"factions": ["nobody", "renew"]})]
	assert_str(_merge([_report(ghost)])["error"]).contains("faction 'nobody' has no roster")
	var shared: Dictionary[String, Array] = {"a": ["x"], "b": ["x"]}
	assert_str(Summary._roster_problem(shared)).contains(
		"type 'x' is in the rosters of 'a' and 'b'"
	)


func test_win_shares_count_a_draw_and_a_timeout_half_to_each_side() -> void:
	# Fossil is player 1 and top in all four: a win, a win, a draw, a loss -> 2+2+1+0 of 8.
	var matches: Array[Dictionary] = [
		_match(1, "victory", 1),
		_match(3, "victory", 1),
		_match(5, "draw", 0),
		_match(7, "victory", 2),
	]
	var summary: Dictionary = _summary(matches)
	assert_int(summary["by_faction"]["fossil"]).is_equal(625)
	assert_int(summary["by_faction"]["renew"]).is_equal(375)
	assert_int(summary["by_seat"]["top"]).is_equal(625)
	assert_int(summary["by_seat"]["bottom"]).is_equal(375)
	assert_int(summary["victories"]).is_equal(3)
	assert_int(summary["draws"]).is_equal(1)
	var timed: Dictionary = _summary([_match(1, "timeout", 0), _match(3, "victory", 1)])
	assert_int(timed["by_faction"]["fossil"]).is_equal(750)
	assert_int(timed["timeouts"]).is_equal(1)
	# A cross run: renew on top in the mirrored scenario, so seats and factions part ways.
	var cross: Dictionary = _summary(
		[_match(1, "victory", 1), _match(2, "victory", 2, {"fossil_top": false})]
	)
	assert_int(cross["by_faction"]["fossil"]).is_equal(1000)
	assert_int(cross["by_seat"]["top"]).is_equal(500)


func test_by_level_reads_each_players_level_so_swapped_pairs_count_both_seats() -> void:
	var first: Dictionary = _match(1, "victory", 1, {"levels": ["easy", "normal"]})
	var second: Dictionary = _match(2, "victory", 2, {"levels": ["normal", "easy"]})
	var summary: Dictionary = _summary([first, second], ["easy", "normal"])
	# Easy won as player 1 in the first match and as player 2 in the second.
	assert_int(summary["by_level"]["easy"]).is_equal(1000)
	assert_int(summary["by_level"]["normal"]).is_equal(0)
	assert_bool(_summary([first, second])["by_faction"].has("fossil")).is_true()
	assert_bool(_summary([_match(1, "victory", 1)]).has("by_level")).is_false()


func test_length_median_p90_and_max() -> void:
	var even: Array[Dictionary] = []
	for index: int in 10:
		even.append(_match(index + 1, "victory", 1, {"ticks": 1000 * (index + 1)}))
	var summary: Dictionary = _summary(even)
	# The mean of the two middle values; the nearest-rank 90th of ten is the ninth.
	assert_int(summary["length_ticks"]["median"]).is_equal(5500)
	assert_int(summary["length_ticks"]["p90"]).is_equal(9000)
	assert_int(summary["length_ticks"]["max"]).is_equal(10000)
	var odd: Dictionary = _summary(
		[
			_match(1, "victory", 1, {"ticks": 9000}),
			_match(3, "victory", 1, {"ticks": 100}),
			_match(5, "victory", 1, {"ticks": 500}),
		]
	)
	assert_int(odd["length_ticks"]["median"]).is_equal(500)
	assert_int(odd["length_ticks"]["p90"]).is_equal(9000)
	var none: Dictionary = _summary([])
	assert_int(none["length_ticks"]["median"]).is_equal(0)
	assert_int(none["matches"]).is_equal(0)


func test_per_type_rows_and_the_roster_fills_in_the_types_that_never_occurred() -> void:
	var tank: String = _fossil[0]
	var other: String = _fossil[1]
	var first: Dictionary = _match(1, "victory", 1)
	_put(first, 0, "produced", {tank: 3, other: 1})
	_put(first, 0, "free", {tank: 1})
	_put(first, 0, "lost", {tank: 2})
	_put(first, 0, "kills", {tank: 5, "a_structure_type": 9})
	_put(first, 0, "spent", {tank: 3000, other: 500})
	# A second match: one more of `tank` built, nothing of `other`.
	var second: Dictionary = _match(3, "victory", 1)
	_put(second, 0, "produced", {tank: 1})
	_put(second, 0, "spent", {tank: 1000})
	# The enemy side's rows are the other faction's, not these.
	_put(second, 1, "produced", {_renew[0]: 4})
	var summary: Dictionary = _summary([first, second])
	var row: Dictionary = summary["types"][tank]
	assert_str(row["faction"]).is_equal("fossil")
	assert_int(row["produced"]).is_equal(4)
	# 4 of the faction's 5 produced units: 800 per-mille; the 5th is `other`'s.
	assert_int(row["share_permille"]).is_equal(800)
	assert_int(summary["types"][other]["share_permille"]).is_equal(200)
	# 5 kills over 4000 credits: 1.25 per 1000 credits, x100 and rounded.
	assert_int(row["kills_per_1000_credits_x100"]).is_equal(125)
	# 5 existed (4 built + 1 free), 2 lost: 600 per-mille survived.
	assert_int(row["survival_permille"]).is_equal(600)
	assert_int(row["matches_built"]).is_equal(2)
	assert_int(summary["types"][other]["matches_built"]).is_equal(1)
	# `other` was never in a kill and survived untouched; a type no map names is all zeros.
	assert_int(summary["types"][other]["kills_per_1000_credits_x100"]).is_equal(0)
	var absent: Dictionary = summary["types"][_fossil[2]]
	assert_int(absent["produced"]).is_equal(0)
	assert_int(absent["share_permille"]).is_equal(0)
	assert_int(absent["survival_permille"]).is_equal(0)
	assert_int(absent["matches_built"]).is_equal(0)
	assert_int(summary["types"].size()).is_equal(12)
	assert_bool(summary["types"].has("a_structure_type")).is_false()
	assert_int(summary["types"][_renew[0]]["share_permille"]).is_equal(1000)
	# Kills per 1000 credits round half up: 1 kill over 6 credits is 16666.67, so 16667.
	var sixths: Dictionary = _match(1, "victory", 1)
	_put(sixths, 0, "kills", {tank: 1})
	_put(sixths, 0, "spent", {tank: 6})
	assert_int(_summary([sixths])["types"][tank]["kills_per_1000_credits_x100"]).is_equal(16667)
	# A mirror match counts a type built in it once, though both players built it, and has no
	# by_faction (it would read 500).
	var mirror: Dictionary = _match(1, "victory", 1, {"factions": ["fossil", "fossil"]})
	_put(mirror, 0, "produced", {tank: 1})
	_put(mirror, 1, "produced", {tank: 1})
	var fossil_only: Dictionary[String, Array] = {"fossil": _roster["fossil"]}
	var mirrored: Dictionary = Summary.summarize(_report([mirror]), fossil_only, false)
	assert_int(mirrored["types"][tank]["matches_built"]).is_equal(1)
	assert_int(mirrored["types"][tank]["produced"]).is_equal(2)
	assert_bool(mirrored.has("by_faction")).is_false()
	assert_bool(mirrored.has("by_seat")).is_true()
	# Kills of structure types change no row.
	var plain: Array[Dictionary] = _balanced(4)
	var with_structures: Array[Dictionary] = _balanced(4)
	_put(with_structures[0], 0, "kills", {"some_structure": 12})
	assert_dict(_summary(with_structures)["types"]).is_equal(_summary(plain)["types"])


func test_distinct_hashes_dropped_commands_and_flow_full_ticks() -> void:
	var a: Dictionary = _match(
		1, "victory", 1, {"hash": "aaaaaaaaaaaaaaaa", "dropped": 2, "flow": 5}
	)
	var b: Dictionary = _match(
		3, "victory", 1, {"hash": "aaaaaaaaaaaaaaaa", "dropped": 1, "flow": 9}
	)
	var c: Dictionary = _match(5, "victory", 1, {"hash": "bbbbbbbbbbbbbbbb"})
	var summary: Dictionary = _summary([a, b, c])
	assert_int(summary["distinct_final_hashes"]).is_equal(2)
	assert_int(summary["dropped_commands"]).is_equal(3)
	assert_array([summary["expired_commands"], summary["stale_commands"]]).is_equal([0, 3])
	# Check 5 counts the matches over ADR 0038 section 6's bound (1 percent of the players'
	# Commands, integer division): 150 + 150 Commands allow 3 drops, a fourth fails the match.
	var within: Dictionary = _match(1, "victory", 1, {"commands": 150, "dropped": 3})
	var over: Dictionary = _match(3, "victory", 1, {"commands": 150, "dropped": 4})
	assert_int(_summary([within])["stale_drop_matches"]).is_equal(0)
	assert_int(_summary([within, over])["stale_drop_matches"]).is_equal(1)
	assert_int(summary["flow_full_ticks"]["total"]).is_equal(14)
	assert_int(summary["flow_full_ticks"]["most_in_one"]).is_equal(9)


func test_a_clean_set_has_no_flags_and_each_flag_names_what_it_found() -> void:
	var clean: Dictionary = _summary(_balanced(4))
	assert_array(clean["flags"]).is_empty()
	var skewed: Array[Dictionary] = _balanced(4)
	for record: Dictionary in skewed:
		record["end"] = "timeout"
		record["winner"] = 0
		record["ticks"] = 13500
		record["state_hash"] = "0000000000000000"
		record["flow_full_ticks"] = 1
	skewed[0]["end"] = "victory"
	skewed[0]["winner"] = 1
	skewed[1]["end"] = "victory"
	skewed[1]["winner"] = 1
	# One type is made far more than the rest: its share is over 400.
	_put(skewed[0], 0, "produced", {_fossil[0]: 100})
	var flags: String = "\n".join(_summary(skewed)["flags"])
	assert_str(flags).contains("by_faction fossil win share 750 per-mille")
	assert_str(flags).contains("by_seat top win share 750")
	assert_str(flags).contains("median length 13500 ticks is outside 7200-9000")
	assert_str(flags).contains("%s (fossil) is" % _fossil[0])
	assert_str(flags).contains("2 matches timed out")
	assert_str(flags).contains("the flow cache was full in 4 ticks")
	assert_str(flags).contains("1 distinct final hashes in 4 matches, under 95 percent")
	var low: Array[Dictionary] = _balanced(4)
	for record: Dictionary in low:
		record["players"][0]["produced"].erase(_fossil[0])
	assert_str("\n".join(_summary(low)["flags"])).contains(
		"%s (fossil) is 0 per-mille" % _fossil[0]
	)
	var fast: Array[Dictionary] = _balanced(4)
	fast[2]["ticks"] = 100
	fast[3]["ticks"] = 100
	assert_str("\n".join(_summary(fast)["flags"])).contains("median length")
	# Exactly on a limit is no flag: shares 400 and 600, medians 7200 and 9000, type shares 50 and
	# 400 per-mille (8, 1, 4, 4, 2, 1 of 20), 95 distinct hashes of 100.
	assert_array(_summary(_split(10, 4))["flags"]).is_empty()
	for edge_ticks: int in [7200, 9000]:
		var edge: Array[Dictionary] = _balanced(4)
		for record: Dictionary in edge:
			record["ticks"] = edge_ticks
		assert_array(_summary(edge)["flags"]).is_empty()
	var shares: Array[Dictionary] = _balanced(4)
	for record: Dictionary in shares:
		var made: Dictionary = {}
		for index: int in 6:
			made[_fossil[index]] = [8, 1, 4, 4, 2, 1][index]
		_put(record, 0, "produced", made)
	assert_array(_summary(shares)["flags"]).is_empty()
	var hashes: Array[Dictionary] = _balanced(100)
	for index: int in range(95, 100):
		hashes[index]["state_hash"] = hashes[0]["state_hash"]
	assert_array(_summary(hashes)["flags"]).is_empty()
	# A type share of 49.5 per-mille rounds to 50 but is under 50: flagged. Others stay in range.
	var under: Array[Dictionary] = _balanced(1)
	var counts: Dictionary = {}
	for index: int in 6:
		counts[_fossil[index]] = [99, 380, 380, 380, 380, 381][index]
	_put(under[0], 0, "produced", counts)
	var under_flags: String = "\n".join(_summary(under)["flags"])
	assert_str(under_flags).contains("%s (fossil) is 50 per-mille" % _fossil[0])
	# The flags of the types come by faction, then id.
	var order: Array[Dictionary] = _balanced(1)
	_put(order[0], 0, "produced", {})
	_put(order[0], 1, "produced", {})
	var flags_text: String = "\n".join(_summary(order)["flags"])
	assert_bool(flags_text.find(_fossil.max()) < flags_text.find(_renew.min())).is_true()
	# By level is flagged too.
	var lopsided: Array[Dictionary] = [
		_match(1, "victory", 1, {"levels": ["easy", "hard"]}),
		_match(3, "victory", 1, {"levels": ["easy", "hard"]}),
	]
	var level_flags: Array = _summary(lopsided, ["easy", "hard"])["flags"]
	assert_str("\n".join(level_flags)).contains("by_level easy win share 1000 per-mille")


func test_the_gate_passes_a_gate_set_and_each_check_fails_alone() -> void:
	var good: Dictionary = _gate(_balanced(100))
	assert_str(good["verdict"]).is_equal("pass")
	assert_int(good["checks"].size()).is_equal(9)
	assert_str(good["checks"][0]["id"]).is_equal("set")
	assert_int(good["matches"]).is_equal(100)
	for check: Dictionary in good["checks"]:
		assert_str(check["verdict"]).is_equal("pass")
	# Exactly the cap is no failure of 3b (a match at the cap is a timeout, which 3a judges).
	var cap: Array[Dictionary] = _balanced(100)
	cap[0]["ticks"] = 13500
	assert_str(_verdict_of(_gate(cap), "3b")).is_equal("pass")
	var failing: Dictionary[String, Callable] = {
		"3a": func(m: Array[Dictionary]) -> void: m[0]["end"] = "timeout",
		"3b": func(m: Array[Dictionary]) -> void: m[0]["ticks"] = 13501,
		"5": func(m: Array[Dictionary]) -> void: m[2]["dropped_commands"] = 1,
		"6": func(m: Array[Dictionary]) -> void: _dupe_hashes(m, 1, 7),
	}
	for id: String in failing:
		var matches: Array[Dictionary] = _balanced(100)
		failing[id].call(matches)
		var gate: Dictionary = _gate(matches)
		assert_str(gate["verdict"]).is_equal("fail")
		assert_str(_verdict_of(gate, id)).is_equal("fail")
		for check: Dictionary in gate["checks"]:
			if not [id, "1", "2", "6"].has(check["id"]):
				assert_str(check["verdict"]).is_equal("pass")
	# Check 4: every match leaves one type out, so it is built in none.
	var unbuilt: Array[Dictionary] = _balanced(100)
	for record: Dictionary in unbuilt:
		record["players"][0]["produced"].erase(_fossil[0])
	assert_str(_verdict_of(_gate(unbuilt), "4")).is_equal("fail")
	var gdscript: Dictionary = _gate(_balanced(100), {"impl": "gdscript"})
	assert_str(_verdict_of(gdscript, "7")).is_equal("fail")
	assert_str(gdscript["verdict"]).is_equal("fail")


## The `set` check: a gate run is exactly 100 matches of seeds 1001-1100 (or 200 of 1001-1200),
## Normal against Normal on `cross`, with twelve unit types; anything else is not judged a pass.
func test_the_gate_set_check_fails_on_anything_that_is_not_a_gate_set() -> void:
	assert_str(_verdict_of(_gate(_balanced(100)), "set")).is_equal("pass")
	assert_str(_verdict_of(_gate(_balanced(200)), "set")).is_equal("pass")
	# A lost shard: 75 or 150 matches.
	var short: Dictionary = _gate(_balanced(75))
	assert_str(_verdict_of(short, "set")).is_equal("fail")
	assert_str(short["verdict"]).is_equal("fail")
	assert_str(_check_of(short, "set")["detail"]).contains("75 matches")
	assert_str(_verdict_of(_gate(_balanced(150)), "set")).is_equal("fail")
	# The right count on the wrong seeds, a gap in the seeds, the wrong levels or scenarios.
	assert_str(_verdict_of(_gate(_split(100, 50, 1)), "set")).is_equal("fail")
	var gap: Array[Dictionary] = _balanced(100)
	gap[50]["seed"] = 5000
	assert_str(_verdict_of(_gate(gap), "set")).is_equal("fail")
	# A gap inside the range (1051 missing, 1053 twice) keeps the count, the lowest and the highest.
	var inside: Array[Dictionary] = _balanced(100)
	inside[50]["seed"] = 1053
	assert_str(_verdict_of(_gate(inside), "set")).is_equal("fail")
	var other_levels: Dictionary = _gate(_balanced(100), {"levels": ["easy", "normal"]})
	assert_str(_check_of(other_levels, "set")["detail"]).contains("levels easy,normal")
	assert_str(other_levels["verdict"]).is_equal("fail")
	var normal_hard: Dictionary = _gate(_balanced(100), {"levels": ["normal", "hard"]})
	assert_str(_verdict_of(normal_hard, "set")).is_equal("fail")
	var mirror: Dictionary = _gate(_balanced(100), {"scenarios": "fossil-mirror"})
	assert_str(_check_of(mirror, "set")["detail"]).contains("scenarios fossil-mirror")
	assert_str(mirror["verdict"]).is_equal("fail")
	# An empty roster: no types, so the set and check 4 fail (it must not pass on nothing).
	var none: Dictionary[String, Array] = {"fossil": [], "renew": []}
	var report: Dictionary = _report(_balanced(100))
	var empty: Dictionary = Summary.summarize(report, none, true)["gate"]
	assert_str(_verdict_of(empty, "set")).is_equal("fail")
	assert_str(_verdict_of(empty, "4")).is_equal("fail")
	assert_str(empty["verdict"]).is_equal("fail")


func test_gate_check_4_wants_half_of_the_matches_and_check_6_95_percent() -> void:
	# 100 matches: 50 built is enough (limit 50), 49 is not.
	var fifty: Array[Dictionary] = _balanced(100)
	for index: int in 100:
		if index >= 50:
			fifty[index]["players"][0]["produced"].erase(_fossil[0])
	var gate: Dictionary = _gate(fifty)
	assert_str(_verdict_of(gate, "4")).is_equal("pass")
	assert_int(_check_of(gate, "4")["min"]).is_equal(50)
	fifty[49]["players"][0]["produced"].erase(_fossil[0])
	assert_str(_verdict_of(_gate(fifty), "4")).is_equal("fail")
	# 200 matches (the rerun set): the limits scale to 100 built and 190 distinct.
	var two_hundred: Dictionary = _gate(_balanced(200))
	assert_int(_check_of(two_hundred, "4")["min"]).is_equal(100)
	assert_int(_check_of(two_hundred, "6")["min"]).is_equal(190)
	# 95 distinct of 100 pass; 94 fail.
	var hashes: Array[Dictionary] = _balanced(100)
	for index: int in range(95, 100):
		hashes[index]["state_hash"] = hashes[0]["state_hash"]
	assert_int(_check_of(_gate(hashes), "6")["value"]).is_equal(95)
	assert_str(_verdict_of(_gate(hashes), "6")).is_equal("pass")
	for index: int in range(90, 95):
		hashes[index]["state_hash"] = hashes[0]["state_hash"]
	assert_int(_check_of(_gate(hashes), "6")["value"]).is_equal(90)
	assert_str(_verdict_of(_gate(hashes), "6")).is_equal("fail")
	var edge: Array[Dictionary] = _balanced(100)
	for index: int in range(94, 100):
		edge[index]["state_hash"] = edge[0]["state_hash"]
	assert_int(_check_of(_gate(edge), "6")["value"]).is_equal(94)
	assert_str(_verdict_of(_gate(edge), "6")).is_equal("fail")


## ADR 0031 section 6: 350-399 or 601-650 per-mille on check 1 or 2 asks for one rerun (so the
## verdict is "rerun", not a pass), outside 350-650 fails, and 200 matches decide against 400-600.
func test_gate_checks_1_and_2_have_the_rerun_band() -> void:
	assert_str(_verdict_of(_gate(_split(100, 50)), "1")).is_equal("pass")
	assert_str(_verdict_of(_gate(_split(100, 60)), "1")).is_equal("pass")
	assert_str(_verdict_of(_gate(_split(100, 61)), "1")).is_equal("rerun")
	assert_str(_verdict_of(_gate(_split(100, 65)), "1")).is_equal("rerun")
	assert_str(_verdict_of(_gate(_split(100, 66)), "1")).is_equal("fail")
	assert_str(_verdict_of(_gate(_split(100, 35)), "1")).is_equal("rerun")
	assert_str(_verdict_of(_gate(_split(100, 34)), "1")).is_equal("fail")
	var rerun: Dictionary = _gate(_split(100, 62))
	assert_str(rerun["verdict"]).is_equal("rerun")
	assert_str(_verdict_of(rerun, "2")).is_equal("rerun")
	assert_int(_check_of(rerun, "1")["value"]).is_equal(620)
	# The 200 together decide: 62 percent is a fail now, 59 percent a pass.
	assert_str(_verdict_of(_gate(_split(200, 124)), "1")).is_equal("fail")
	assert_str(_verdict_of(_gate(_split(200, 118)), "1")).is_equal("pass")
	# The band is for exactly 100 matches: 150 matches with a 620 share are a fail, not a rerun.
	assert_str(_verdict_of(_gate(_split(150, 93)), "1")).is_equal("fail")
	# A fail elsewhere wins over a rerun.
	var both: Array[Dictionary] = _split(100, 62)
	both[0]["end"] = "timeout"
	assert_str(_gate(both)["verdict"]).is_equal("fail")
	# A fail in check 1 (340) before a rerun in check 2 (380) is a fail too.
	var early: Dictionary = _gate(_cross(11, 23))
	assert_int(_check_of(early, "1")["value"]).is_equal(340)
	assert_str(_verdict_of(early, "1")).is_equal("fail")
	assert_int(_check_of(early, "2")["value"]).is_equal(380)
	assert_str(_verdict_of(early, "2")).is_equal("rerun")
	assert_str(early["verdict"]).is_equal("fail")


func test_gate_check_2_reads_the_top_seat_and_check_1_the_faction_farthest_from_half() -> void:
	# Fossil wins every match, as top in the odd ones and bottom in the even ones: its share is
	# 1000 but the top seat holds 500.
	var matches: Array[Dictionary] = []
	for seed_number: int in range(1001, 1005):
		var top: bool = seed_number % 2 == 1
		matches.append(
			_match(
				seed_number,
				"victory",
				1 if top else 2,
				{"fossil_top": top, "hash": str(seed_number)}
			)
		)
	var gate: Dictionary = _gate(matches)
	assert_int(_check_of(gate, "1")["value"]).is_equal(1000)
	assert_str(_check_of(gate, "1")["detail"]).is_equal("fossil 1000, renew 0")
	assert_int(_check_of(gate, "2")["value"]).is_equal(500)
	assert_str(_verdict_of(gate, "2")).is_equal("pass")


func test_merge_sorts_matches_sums_and_takes_the_smallest_seed_start() -> void:
	var first: Dictionary = _report(
		[_match(3, "victory", 1), _match(1, "victory", 2)], {"start": 1, "asked": 2}
	)
	var second: Dictionary = _report(
		[_match(4, "draw", 0), _match(2, "victory", 1)], {"start": 2, "asked": 2}
	)
	var merged: Dictionary = _merge([first, second])["report"]
	var seeds: Array = []
	for record: Dictionary in merged["matches"]:
		seeds.append(record["seed"])
	assert_array(seeds).is_equal([1, 2, 3, 4])
	assert_int(merged["seed_start"]).is_equal(1)
	assert_int(merged["matches_requested"]).is_equal(4)
	assert_str(merged["status"]).is_equal("ok")
	assert_int(merged["summary"]["matches"]).is_equal(4)
	var broken: Dictionary = _report([_match(9, "victory", 1)], {"status": "failed"})
	assert_str(_merge([first, broken])["report"]["status"]).is_equal("failed")


func test_merge_is_order_independent_and_its_text_is_byte_identical() -> void:
	var a: Dictionary = _report(_balanced(4))
	var b: Dictionary = _report(_split(6, 3, 2001), {"start": 2001})
	var ab: String = Smoke.report_text(_merge([a, b], true)["report"])
	var ba: String = Smoke.report_text(_merge([b, a], true)["report"])
	assert_str(ab).is_equal(ba)
	assert_str(ab).is_equal(Smoke.report_text(_merge([a, b], true)["report"]))
	assert_str(Summary.markdown(_merge([a, b], true)["report"])).is_equal(
		Summary.markdown(_merge([b, a], true)["report"])
	)
	# The same ten matches in one shard or two give the same JSON apart from the shard fields.
	var whole: Dictionary = _merge([_report(_balanced(10))])["report"]
	var halves: Dictionary = _merge(
		[_report(_balanced(10).slice(0, 5)), _report(_balanced(10).slice(5, 10))]
	)["report"]
	assert_dict(halves["summary"]).is_equal(whole["summary"])
	assert_array(halves["matches"]).is_equal(whole["matches"])
	assert_bool(ab.ends_with("}\n")).is_true()


func test_merge_levels_accept_a_swapped_pair_and_refuse_a_different_pair() -> void:
	var easy_normal: Dictionary = _report(
		[_match(1, "victory", 1, {"levels": ["easy", "normal"]})], {"levels": ["easy", "normal"]}
	)
	var normal_easy: Dictionary = _report(
		[_match(1, "victory", 2, {"levels": ["normal", "easy"]})], {"levels": ["normal", "easy"]}
	)
	var hard_normal: Dictionary = _report(
		[_match(1, "victory", 1, {"levels": ["hard", "normal"]})], {"levels": ["hard", "normal"]}
	)
	var merged: Dictionary = _merge([easy_normal, normal_easy])
	assert_bool(merged.has("report")).is_true()
	assert_array(merged["report"]["levels"]).is_equal(["easy", "normal"])
	assert_int(merged["report"]["matches"].size()).is_equal(2)
	# The same seed twice is fine when the level order differs (a swapped pair) ...
	var order: String = Smoke.report_text(merged["report"])
	assert_str(order).is_equal(Smoke.report_text(_merge([normal_easy, easy_normal])["report"]))
	# ... and the unchanged order of one shard keeps its `levels`.
	assert_array(_merge([easy_normal])["report"]["levels"]).is_equal(["easy", "normal"])
	var refused: Dictionary = _merge([easy_normal, hard_normal])
	assert_bool(refused.has("error")).is_true()
	assert_str(refused["error"]).contains("field 'levels' differs")
	assert_str(refused["error"]).contains("a.json").contains("b.json")


func test_every_other_refusal_names_its_field() -> void:
	var base: Dictionary = _report(_balanced(2))
	var changes: Dictionary[String, Variant] = {
		"commit": "other",
		"impl": "gdscript",
		"ticks_per_match": 900,
		"scenarios": "derrick",
	}
	for field: String in changes:
		var other: Dictionary = _report(_balanced(2), {field: changes[field]})
		var result: Dictionary = _merge([base, other])
		assert_bool(result.has("error")).is_true()
		assert_str(result["error"]).contains("field '%s' differs" % field)
		assert_str(result["error"]).contains(str(changes[field]))
	var twice: Dictionary = _merge([base, _report(_balanced(2))])
	assert_str(twice["error"]).contains("field 'matches' holds seed 1001")


func test_the_report_survives_json_and_every_number_is_an_int() -> void:
	var merged: Dictionary = _merge([_report(_balanced(4))], true)["report"]
	var text: String = Smoke.report_text(merged)
	# No decimal point anywhere in the JSON.
	assert_bool(RegEx.create_from_string("[0-9]\\.[0-9]").search(text) == null).is_true()
	assert_bool(_has_float(merged)).is_false()
	var path: String = _temp_file(text)
	var loaded: Dictionary = Summary.load_report(path)
	assert_bool(_has_float(loaded)).is_false()
	assert_str(Smoke.report_text(loaded)).is_equal(text)
	assert_str(Summary.load_report(_temp_file("[1]"))["error"]).contains("not a JSON object")
	assert_str(Summary.load_report(_temp_file('{"schema": 1}'))["error"]).contains("'schema'")
	assert_str(Summary.load_report("/nonexistent/r.json")["error"]).contains("cannot be read")
	# A missing key is named, a matches that is no array too, and a fraction is refused.
	var broken: Dictionary = _report(_balanced(2))
	broken.erase("levels")
	assert_str(Summary.load_report(_temp_file(JSON.stringify(broken)))["error"]).contains(
		"field 'levels' is missing"
	)
	broken = _report(_balanced(2))
	broken["matches"] = 5
	assert_str(Summary.load_report(_temp_file(JSON.stringify(broken)))["error"]).contains(
		"field 'matches' is not an array"
	)
	broken = _report(_balanced(2))
	broken["matches"][0]["ticks"] = 1.5
	assert_str(Summary.load_report(_temp_file(JSON.stringify(broken)))["error"]).contains(
		"not a whole number"
	)
	# The markdown goes next to the JSON: .json becomes .md, any other name gets .md added.
	assert_str(Summary.markdown_path("build/x.json")).is_equal("build/x.md")
	assert_str(Summary.markdown_path("build/x")).is_equal("build/x.md")
	assert_str(Summary.markdown_path("a.json.json")).is_equal("a.json.md")


func test_the_markdown_is_a_fixed_template_that_states_the_kill_order() -> void:
	var matches: Array[Dictionary] = _balanced(4)
	matches[0]["flow_full_ticks"] = 1
	var merged: Dictionary = _merge([_report(matches)], true)["report"]
	var text: String = Summary.markdown(merged)
	assert_str(text).is_equal(FileAccess.get_file_as_string(GOLDEN).replace("\r\n", "\n"))
	# The order of the attribution, not only "last shooter".
	var order: String = text.substr(text.find("Kills are an estimate"))
	var shot: int = order.find("a shot at the row in the tick it died")
	var rupture: int = order.find("an enemy rupture landing in that tick")
	var last: int = order.find("the row's last shooter")
	var nobody: int = order.find("else nobody")
	assert_bool(shot > 0 and rupture > shot and last > rupture and nobody > last).is_true()
	assert_str(text).contains("a timeout counts half to each side")
	# Without --gate there is no gate section, and a clean set says so.
	var plain: Dictionary = _merge([_report(_balanced(4))])["report"]
	assert_bool(Summary.markdown(plain).contains("### Gate")).is_false()
	assert_bool(plain["summary"].has("gate")).is_false()
	assert_str(Summary.markdown(plain)).contains("None.")
	# The minutes are ints only, rounded to a tenth.
	assert_str(Summary._minutes(13500)).is_equal("15.0 min")
	assert_str(Summary._minutes(0)).is_equal("0.0 min")
	assert_str(Summary._minutes(1349)).is_equal("1.5 min")
	# The gate table of a rerun set.
	var rerun: Dictionary = _merge([_report(_split(100, 62))], true)["report"]
	var rerun_text: String = Summary.markdown(rerun)
	assert_str(rerun_text).contains("### Gate: RERUN")
	assert_str(rerun_text).contains("| 1 | faction win share | 620 | 400-600 | rerun |")
	assert_bool(rerun_text.find("### Flags") < rerun_text.find("### Gate")).is_true()
	assert_str(rerun_text).contains("| 7 | impl is native | 1 | 1-1 | pass | impl native |")


# --- helpers ---------------------------------------------------------------------------------


## A match record in the shape of smoke_run.gd's `record_of`. `options`: `levels` (two names),
## `fossil_top` (default true: fossil is player 1 and top), `ticks`, `hash`, `dropped`, `flow`.
func _match(match_seed: int, end: String, winner: int, options: Dictionary = {}) -> Dictionary:
	var levels: Array = options.get("levels", ["normal", "normal"])
	var fossil_top: bool = options.get("fossil_top", true)
	var factions: Array = options.get(
		"factions", ["fossil", "renew"] if fossil_top else ["renew", "fossil"]
	)
	var players: Array[Dictionary] = []
	for index: int in 2:
		var is_fossil: bool = factions[index] == "fossil"
		(
			players
			. append(
				{
					"player": index + 1,
					"faction": factions[index],
					"seat": "top" if index == 0 else "bottom",
					"ai": "opponent_fossil" if is_fossil else "opponent_renew",
					"level": levels[index],
					"commands": options.get("commands", 0),
					"produced": {},
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
		"scenario": "res://data/scenarios/skirmish_kestrel_flats.tres",
		"ticks": options.get("ticks", 8000),
		"end": end,
		"winner": winner,
		"match_end_tick": 0 if end == "timeout" else options.get("ticks", 8000),
		"state_hash": options.get("hash", "%016x" % (match_seed * 7919 + 1)),
		"dropped_commands": options.get("dropped", 0),
		"spawn_refused": 0,
		"flow_full_ticks": options.get("flow", 0),
		"players": players,
	}


## Sets the per type map `map` of player index `side` (0 or 1) of `record`.
func _put(record: Dictionary, side: int, map: String, counts: Dictionary) -> void:
	record["players"][side][map] = counts


## `count` matches (seeds 1001..) where every unit type of both rosters is produced once by its
## faction in every match, fossil wins the first half and renew the rest, fossil on top, 8000
## ticks, distinct hashes: the set a gate passes (at 100 matches).
func _balanced(count: int) -> Array[Dictionary]:
	return _split(count, (count + 1) / 2)


## `count` matches from seed `first`, fossil winning the first `fossil_wins`, in the shape of
## `_balanced`.
func _split(count: int, fossil_wins: int, first: int = 1001) -> Array[Dictionary]:
	var matches: Array[Dictionary] = []
	for index: int in count:
		var record: Dictionary = _match(first + index, "victory", 1 if index < fossil_wins else 2)
		_fill(record)
		matches.append(record)
	return matches


## 100 matches of seeds 1001-1100 in the cross layout (fossil on top in the odd seeds), fossil
## winning the first `top_wins` of the odd and the first `bottom_wins` of the even seeds.
func _cross(top_wins: int, bottom_wins: int) -> Array[Dictionary]:
	var matches: Array[Dictionary] = []
	var won: Dictionary[bool, int] = {true: 0, false: 0}
	for seed_number: int in range(1001, 1101):
		var top: bool = seed_number % 2 == 1
		var fossil_wins: bool = won[top] < (top_wins if top else bottom_wins)
		won[top] += 1 if fossil_wins else 0
		var winner: int = 1 if fossil_wins == top else 2
		var record: Dictionary = _match(seed_number, "victory", winner, {"fossil_top": top})
		_fill(record)
		matches.append(record)
	return matches


## Gives each player of `record` one of every unit type of its faction.
func _fill(record: Dictionary) -> void:
	for side: int in 2:
		var made: Dictionary = {}
		for id: String in _roster[record["players"][side]["faction"]]:
			made[id] = 1
		_put(record, side, "produced", made)


## A report holding `matches`. `options`: `start`, `asked`, `status`, `levels`, `commit`, `impl`,
## `ticks_per_match`, `scenarios`.
func _report(matches: Array[Dictionary], options: Dictionary = {}) -> Dictionary:
	var report: Dictionary = {
		"schema": 2,
		"status": "ok",
		"commit": "abc123",
		"impl": "native",
		"ticks_per_match": 13500,
		"seed_start": 1,
		"matches_requested": matches.size(),
		"levels": ["normal", "normal"],
		"scenarios": "cross",
		"matches": matches.duplicate(true),
	}
	var renamed: Dictionary[String, String] = {"start": "seed_start", "asked": "matches_requested"}
	for key: String in options:
		report[renamed.get(key, key)] = options[key]
	return report


func _merge(reports: Array[Dictionary], gate: bool = false) -> Dictionary:
	var names: Array[String] = []
	for index: int in reports.size():
		names.append("%s.json" % char(97 + index))
	return Summary.build(reports, names, gate)


func _summary(matches: Array[Dictionary], levels: Array = ["normal", "normal"]) -> Dictionary:
	var report: Dictionary = _report(matches, {"levels": levels})
	return Summary.summarize(report, _roster, false)


func _gate(matches: Array[Dictionary], options: Dictionary = {}) -> Dictionary:
	var report: Dictionary = _report(matches, options)
	return Summary.summarize(report, _roster, true)["gate"]


## Gives the matches `first` to `last - 1` of `matches` the final hash of the first one.
func _dupe_hashes(matches: Array[Dictionary], first: int, last: int) -> void:
	for index: int in range(first, last):
		matches[index]["state_hash"] = matches[0]["state_hash"]


func _check_of(gate: Dictionary, id: String) -> Dictionary:
	for check: Dictionary in gate["checks"]:
		if check["id"] == id:
			return check
	return {}


func _verdict_of(gate: Dictionary, id: String) -> String:
	return String(_check_of(gate, id).get("verdict", "missing"))


func _temp_file(text: String) -> String:
	var folder: DirAccess = DirAccess.create_temp("balance_summary_")
	_folders.append(folder)
	var path: String = folder.get_current_dir().path_join("r.json")
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	file.store_string(text)
	file.close()
	return path


func _has_float(value: Variant) -> bool:
	if value is float:
		return true
	if value is Array:
		for item: Variant in value:
			if _has_float(item):
				return true
	if value is Dictionary:
		for key: Variant in value:
			if _has_float(value[key]):
				return true
	return false
