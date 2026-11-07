extends GdUnitTestSuite
## The real entry of scripts/balance-summary.sh (plan row P187): tests/smoke/balance_summary.gd run
## headless on two shard files, as test_smoke_entry.gd runs the smoke entry. It pins what the
## in-process suite cannot reach: that `--gate` arrives, where the JSON and the markdown are
## written (ADR 0031 section 4; `.json` becomes `.md`), the real OK and FAILED lines and the exit
## codes 0, 1 and 2, with no engine error line in the output.

const ENTRY: String = "res://tests/smoke/balance_summary.gd"

var _folders: Array[DirAccess] = []


func after_test() -> void:
	_folders.clear()


func test_the_entry_merges_two_shards_and_writes_the_json_and_the_markdown() -> void:
	var folder: String = _folder()
	var a: String = _shard(folder, "a.json", [1001, 1002], ["normal", "normal"])
	var b: String = _shard(folder, "b.json", [1003, 1004], ["normal", "normal"])
	var out: String = folder.path_join("set.json")
	var result: Dictionary = _entry(["--out", out, "--gate", a, b])
	assert_int(result["code"]).is_equal(0)
	assert_str(result["text"]).contains("balance-summary: OK, 4 matches from 2 reports, ")
	assert_str(result["text"]).contains(", gate fail")
	assert_str(result["text"]).not_contains("SCRIPT ERROR")
	assert_str(result["text"]).not_contains("ERROR:")
	var merged: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(out))
	assert_int(int(merged["summary"]["matches"])).is_equal(4)
	# `--gate` reached the summary, and the .json file's markdown is set.md.
	assert_bool(merged["summary"].has("gate")).is_true()
	var markdown: String = FileAccess.get_file_as_string(folder.path_join("set.md"))
	assert_str(markdown).contains("### Gate: FAIL")
	assert_bool(FileAccess.file_exists(out + ".md")).is_false()
	# Without --gate there is no gate, and a name that is not .json gets .md added.
	var plain: String = folder.path_join("plain")
	var again: Dictionary = _entry(["--out", plain, b, a])
	assert_int(again["code"]).is_equal(0)
	assert_str(again["text"]).not_contains(", gate ")
	assert_bool(FileAccess.get_file_as_string(plain + ".md").contains("### Gate")).is_false()
	(
		assert_bool(JSON.parse_string(FileAccess.get_file_as_string(plain))["summary"].has("gate"))
		. is_false()
	)
	# The order of the shards does not change a byte.
	var swapped: String = folder.path_join("swapped")
	assert_int(_entry(["--out", swapped, a, b])["code"]).is_equal(0)
	assert_str(FileAccess.get_file_as_string(plain)).is_equal(
		FileAccess.get_file_as_string(swapped)
	)


func test_a_refused_pair_exits_1_and_a_bad_argument_exits_2() -> void:
	var folder: String = _folder()
	var a: String = _shard(folder, "a.json", [1001], ["easy", "normal"])
	var b: String = _shard(folder, "b.json", [1002], ["hard", "normal"])
	var out: String = folder.path_join("set.json")
	var refused: Dictionary = _entry(["--out", out, a, b])
	assert_int(refused["code"]).is_equal(1)
	assert_str(refused["text"]).contains("balance-summary: FAILED, field 'levels' differs")
	assert_bool(FileAccess.file_exists(out)).is_false()
	assert_int(_entry(["--out", out, a, folder.path_join("none.json")])["code"]).is_equal(1)
	assert_int(_entry(["--out", out, "--bogus", a])["code"]).is_equal(2)
	assert_int(_entry(["--out", "--gate", a])["code"]).is_equal(2)
	assert_int(_entry([a])["code"]).is_equal(2)
	assert_int(_entry(["--out", folder, a])["code"]).is_equal(2)


## The entry as the shell script starts it, with `args` after the `--`: exit code and output.
func _entry(args: Array[String]) -> Dictionary:
	var launch: PackedStringArray = PackedStringArray(
		["--headless", "--path", ProjectSettings.globalize_path("res://"), "-s", ENTRY, "--"]
	)
	launch.append_array(PackedStringArray(args))
	var output: Array = []
	var code: int = OS.execute(OS.get_executable_path(), launch, output, true)
	return {"code": code, "text": String(output[0])}


func _folder() -> String:
	var folder: DirAccess = DirAccess.create_temp("balance_entry_")
	_folders.append(folder)
	return folder.get_current_dir()


## A schema 2 shard file of one match per seed, fossil against renew at `levels`, no counts.
func _shard(folder: String, name: String, seeds: Array, levels: Array) -> String:
	var matches: Array = []
	for match_seed: int in seeds:
		var players: Array = []
		for index: int in 2:
			(
				players
				. append(
					{
						"player": index + 1,
						"faction": ["fossil", "renew"][index],
						"seat": ["top", "bottom"][index],
						"level": levels[index],
						"produced": {},
						"free": {},
						"lost": {},
						"kills": {},
						"spent": {},
					}
				)
			)
		(
			matches
			. append(
				{
					"seed": match_seed,
					"ticks": 8000,
					"end": "victory",
					"winner": 1 + match_seed % 2,
					"state_hash": "%016x" % match_seed,
					"dropped_commands": 0,
					"flow_full_ticks": 0,
					"players": players,
				}
			)
		)
	var report: Dictionary = {
		"schema": 2,
		"status": "ok",
		"commit": "abc123",
		"impl": "native",
		"ticks_per_match": 13500,
		"seed_start": seeds[0],
		"matches_requested": seeds.size(),
		"levels": levels,
		"scenarios": "cross",
		"matches": matches,
	}
	var path: String = folder.path_join(name)
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify(report))
	file.close()
	return path
