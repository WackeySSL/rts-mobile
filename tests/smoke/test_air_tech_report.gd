extends GdUnitTestSuite
## The air and tech fields of the AI-vs-AI report (plan row P254, ADR 0031 section 3 note): the
## counter's `kills_by_layer`, `reveals` and `research`, and the summary's `air_tech` block.

const Smoke: GDScript = preload("res://tests/smoke/smoke_run.gd")
const SmokeCount: GDScript = preload("res://tests/smoke/smoke_count.gd")
const Summary: GDScript = preload("res://tests/smoke/balance_summary.gd")


func test_the_counting_reads_reveals_research_and_kills_by_layer() -> void:
	var world: World = Smoke.world_of(1, Smoke.FLATS)
	var counter: SmokeCount = SmokeCount.new(2)
	counter.start(world)
	var rifle: int = world.type_ids.find(&"rifle_squad")
	var fighter: int = world.type_ids.find(&"fossil_fighter")
	var tank: int = world.type_ids.find(&"light_tank")
	assert_bool(fighter >= 0 and world.type_layer_bit[fighter] != World.Layer.GROUND).is_true()
	world.tick = 1
	world.events = _events(
		[
			_spawned(11, fighter, 1),
			_spawned(12, tank, 1),
			_spawned(21, fighter, 2),
			_spawned(22, rifle, 2),
			_spawned(23, rifle, 2),
		]
	)
	counter.after_step(world)
	# Tick 2: the fighter shoots a fighter and a rifle squad; the tank shoots a rifle squad.
	world.tick = 2
	world.events = _events(
		[
			_record(World.Event.SHOT, 11, 0, 0, 21),
			_record(World.Event.SHOT, 11, 0, 0, 22),
			_record(World.Event.SHOT, 12, 0, 0, 23),
			_record(World.Event.DIED, 21, 0, 0, fighter, 2),
			_record(World.Event.DIED, 22, 0, 0, rifle, 2),
			_record(World.Event.DIED, 23, 0, 0, rifle, 2),
			# A sweep of player 2 (kind REVEAL, landing 0) and a blackout of player 1 (not one).
			_record(World.Event.STRIKE, 99, 0, 0, Strike.Kind.REVEAL, 2, 0),
			_record(World.Event.STRIKE, 98, 5, 5, Strike.Kind.BLACKOUT, 1, 0),
		]
	)
	counter.after_step(world)
	assert_dict(counter.kills_by_layer[1]).is_equal({"air": 1, "ground": 2})
	assert_int(_total(counter.kills_by_layer[1])).is_equal(_total(counter.kills[1]))
	assert_array(counter.reveals).is_equal([0, 0, 1])
	# A low flying row's death lands in low_air (the drone squad is not in a roster until P266, so
	# the artillery stands in with the low-air bit), and a death with no shooter is no kill at all.
	var drone: int = world.type_ids.find(&"artillery")
	assert_int(drone).is_greater_equal(0)
	world.type_layer_bit[drone] = World.Layer.LOW_AIR
	world.tick = 3
	world.events = _events(
		[
			_spawned(31, drone, 2),
			_spawned(32, rifle, 2),
			_record(World.Event.SHOT, 12, 0, 0, 31),
			_record(World.Event.DIED, 31, 0, 0, drone, 2),
		]
	)
	counter.after_step(world)
	var before: int = _total(counter.kills[1])
	world.tick = 4
	world.events = _events([_record(World.Event.DIED, 32, 0, 0, rifle, 2)])
	counter.after_step(world)
	assert_dict(counter.kills_by_layer[1]).is_equal({"air": 1, "low_air": 1, "ground": 2})
	assert_int(_total(counter.kills[1])).is_equal(before)
	assert_int(_total(counter.kills_by_layer[1])).is_equal(before)
	assert_int(_total(counter.lost[2])).is_equal(5)
	# Research is read from the owned bits at the end of the run: 0b101 is upgrades 0 and 2.
	assert_int(world.upgrade_ids.size()).is_greater_equal(3)
	world.upgrades[2] = 0b101
	var counts: Dictionary = counter.player_counts(world, 2)
	assert_int(counts["reveals"]).is_equal(1)
	assert_dict(counts["research"]).is_equal(
		{String(world.upgrade_ids[0]): 1, String(world.upgrade_ids[2]): 1}
	)
	assert_dict(counter.player_counts(world, 1)["research"]).is_empty()


func test_the_air_and_tech_block_sums_reveals_research_and_kills_by_layer() -> void:
	var matches: Array[Dictionary] = _matches(4)
	_put(matches[0], 0, "kills_by_layer", {"ground": 3, "air": 2})
	_put(matches[1], 1, "kills_by_layer", {"low_air": 1, "air": 1})
	matches[0]["players"][0]["reveals"] = 2
	matches[1]["players"][1]["reveals"] = 1
	_put(matches[0], 0, "research", {"heavy_bombs": 1, "plated_hull": 1})
	_put(matches[2], 1, "research", {"heavy_bombs": 1})
	var merged: Dictionary = _merge([_report(matches)])["report"]
	var tech: Dictionary = merged["summary"]["air_tech"]
	assert_int(tech["reveals"]).is_equal(3)
	assert_int(tech["reveal_players"]).is_equal(2)
	assert_dict(tech["research"]).is_equal({"heavy_bombs": 2, "plated_hull": 1})
	assert_dict(tech["kills_by_layer"]).is_equal({"ground": 3, "air": 3, "low_air": 1})
	var text: String = Summary.markdown(merged)
	assert_str(text).contains("| 3 | 2 | 3 | 3 | 1 |")
	assert_str(text).contains("heavy_bombs 2, plated_hull 1")
	# A report from before the fields counts 0.
	var old: Dictionary = _merge([_report(_matches(2))])["report"]["summary"]["air_tech"]
	assert_int(old["reveals"]).is_equal(0)
	assert_int(old["reveal_players"]).is_equal(0)
	assert_dict(old["research"]).is_empty()
	assert_dict(old["kills_by_layer"]).is_equal({"ground": 0, "air": 0, "low_air": 0})
	assert_str(Summary.markdown(_merge([_report(_matches(2))])["report"])).contains(
		"(player-matches): none."
	)


## The fields after a JSON round trip (floats in the parsed text) give the same block.
func test_the_air_and_tech_fields_survive_a_json_round_trip() -> void:
	var matches: Array[Dictionary] = _matches(2)
	_put(matches[0], 0, "kills_by_layer", {"ground": 3, "air": 2})
	matches[0]["players"][0]["reveals"] = 2
	_put(matches[1], 1, "research", {"heavy_bombs": 1})
	var parsed: Variant = JSON.parse_string(Smoke.report_text(_report(matches)))
	var tech: Dictionary = Summary._air_tech(parsed["matches"])
	assert_int(tech["reveals"]).is_equal(2)
	assert_int(tech["reveal_players"]).is_equal(1)
	assert_dict(tech["research"]).is_equal({"heavy_bombs": 1})
	assert_dict(tech["kills_by_layer"]).is_equal({"ground": 3, "air": 2, "low_air": 0})


## `count` victories of fossil on top with one player entry each side and no counts.
func _matches(count: int) -> Array[Dictionary]:
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
						"level": "normal",
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


func _report(matches: Array[Dictionary]) -> Dictionary:
	return {
		"schema": 2,
		"status": "ok",
		"commit": "abc123",
		"impl": "native",
		"ticks_per_match": 13500,
		"seed_start": 1001,
		"matches_requested": matches.size(),
		"levels": ["normal", "normal"],
		"scenarios": "cross",
		"matches": matches.duplicate(true),
	}


func _merge(reports: Array[Dictionary]) -> Dictionary:
	var names: Array[String] = ["a.json"]
	return Summary.build(reports, names, false)


func _record(
	kind: int, a: int = 0, b: int = 0, c: int = 0, d: int = 0, e: int = 0, f: int = 0, g: int = 0
) -> PackedInt32Array:
	return PackedInt32Array([kind, a, b, c, d, e, f, g])


func _spawned(id: int, type: int, player: int) -> PackedInt32Array:
	return _record(World.Event.SPAWNED, id, 0, 0, type, player)


func _events(records: Array[PackedInt32Array]) -> PackedInt32Array:
	var events: PackedInt32Array = PackedInt32Array()
	for entry: PackedInt32Array in records:
		events.append_array(entry)
	return events


func _total(counts: Dictionary) -> int:
	var total: int = 0
	for key: String in counts:
		total += int(counts[key])
	return total
