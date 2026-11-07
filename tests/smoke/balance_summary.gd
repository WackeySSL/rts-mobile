extends SceneTree
## The merge, the summary, the gate block and the markdown behind scripts/balance-summary.sh (plan
## row P187, ADR 0031 sections 4 to 6). Not a test suite; the entry point is `_initialize` (Godot
## runs this script headless) and `test_balance_summary.gd` calls the same static functions.
##
## Run: godot --headless --path . -s res://tests/smoke/balance_summary.gd -- --out PATH [--gate]
##      REPORT...   (PATH and the reports are absolute file paths; the shell script resolves them)
## Output: lines that start with "balance-summary: ", then "OK, ..." and exit code 0, or "FAILED,
## <what>" and exit code 1 (a refusal names the field). Exit code 2: a bad argument.
##
## Every number is an int (shares in per-mille, ratios as `_x100`), so equal inputs give the same
## bytes. JSON hands numbers back as floats; load_report() turns them into ints again. Per type maps
## of a report hold only the types that occurred (absent = 0), so the unit rows read the faction
## rosters from data/factions/*.tres, units being the roster's types with a queue tab.

const PREFIX: String = "balance-summary: "
const SCHEMA: int = 2
const FACTION_PATH: String = "res://data/factions/%s.tres"
## The skill's and the gate's limits (ADR 0031 sections 4 and 6), per-mille unless named.
const SHARE_MIN: int = 400
const SHARE_MAX: int = 600
const RERUN_MIN: int = 350
const RERUN_MAX: int = 650
const MEDIAN_MIN: int = 7200
const MEDIAN_MAX: int = 9000
const TYPE_MIN: int = 50
const TYPE_MAX: int = 400
const HASH_MIN_PERCENT: int = 95
const GATE_MAX_TICKS: int = 13500
## The gate decides on 100 matches; a rerun (200 matches together) decides against 400-600.
const GATE_RERUN_MATCHES: int = 200
## Ticks per minute (15 Hz).
const TICKS_PER_MINUTE: int = 900
const IMPL_NATIVE: String = "native"
## The fields every shard of one set must share (levels is compared as an unordered pair).
const SAME_FIELDS: Array[String] = ["commit", "impl", "ticks_per_match", "scenarios"]


func _initialize() -> void:
	quit(_run(OS.get_cmdline_user_args()))


## Merges the reports named in `args`, writes the JSON and the markdown, returns the exit code.
func _run(args: PackedStringArray) -> int:
	var out: String = ""
	var gate: bool = false
	var paths: Array[String] = []
	var index: int = 0
	while index < args.size():
		if args[index] == "--out" and index + 1 < args.size() and not args[index + 1].is_empty():
			out = args[index + 1]
			index += 1
		elif args[index] == "--gate":
			gate = true
		elif not args[index].begins_with("--") and not args[index].is_empty():
			paths.append(args[index])
		else:
			printerr("%sbad argument '%s'" % [PREFIX, args[index]])
			return 2
		index += 1
	if out.is_empty() or paths.is_empty():
		printerr("%s--out PATH and at least one REPORT are required" % PREFIX)
		return 2
	var reports: Array[Dictionary] = []
	for path: String in paths:
		var loaded: Dictionary = load_report(path)
		if loaded.has("error"):
			print("%sFAILED, %s" % [PREFIX, loaded["error"]])
			return 1
		reports.append(loaded)
	var result: Dictionary = build(reports, paths, gate)
	if result.has("error"):
		print("%sFAILED, %s" % [PREFIX, result["error"]])
		return 1
	var merged: Dictionary = result["report"]
	if not _write(out, report_text(merged)) or not _write(out + ".md", markdown(merged)):
		print("%sFAILED, cannot write %s or %s.md" % [PREFIX, out, out])
		return 1
	var summary: Dictionary = merged["summary"]
	var verdict: String = ", gate %s" % summary["gate"]["verdict"] if gate else ""
	print(
		(
			"%sOK, %d matches from %d reports, %d flags%s"
			% [PREFIX, summary["matches"], reports.size(), summary["flags"].size(), verdict]
		)
	)
	return 0


## The report in the file `path` with every number an int; `{"error": text}` when it cannot be read.
static func load_report(path: String) -> Dictionary:
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {"error": "%s: cannot be read" % path}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if not parsed is Dictionary:
		return {"error": "%s: not a JSON object" % path}
	var data: Dictionary = _ints(parsed)
	if data.get("schema", 0) != SCHEMA or not data.get("matches", null) is Array:
		return {"error": "%s: field 'schema' is not %d" % [path, SCHEMA]}
	return data


## Merges the `reports` of one set (read from the files `names`) and adds the summary. The result
## is `{"report": merged}` or `{"error": text}`; a refusal names the field that differs. `gate`
## adds the gate block. The order of `reports` does not change the result.
static func build(reports: Array[Dictionary], names: Array[String], gate: bool) -> Dictionary:
	var refused: String = _refusal(reports, names)
	if not refused.is_empty():
		return {"error": refused}
	var matches: Array[Dictionary] = []
	var seen: Dictionary[String, bool] = {}
	var pairs: Dictionary[String, bool] = {}
	var requested: int = 0
	var seed_start: int = int(reports[0]["seed_start"])
	var failed: bool = false
	for report: Dictionary in reports:
		requested += int(report["matches_requested"])
		seed_start = mini(seed_start, int(report["seed_start"]))
		failed = failed or report["status"] != "ok"
		pairs[",".join(_strings(report["levels"]))] = true
		for record: Dictionary in report["matches"]:
			var key: String = "seed %d (levels %s)" % [record["seed"], _order_of(record)]
			if seen.has(key):
				return {"error": "field 'matches' holds %s twice" % key}
			seen[key] = true
			matches.append(record)
	matches.sort_custom(
		func(a: Dictionary, b: Dictionary) -> bool:
			if a["seed"] != b["seed"]:
				return a["seed"] < b["seed"]
			return _order_of(a) < _order_of(b)
	)
	var levels: Array[String] = _strings(reports[0]["levels"])
	if pairs.size() > 1:
		levels.sort()
	var merged: Dictionary = {
		"schema": SCHEMA,
		"status": "failed" if failed else "ok",
		"commit": reports[0]["commit"],
		"impl": reports[0]["impl"],
		"ticks_per_match": reports[0]["ticks_per_match"],
		"seed_start": seed_start,
		"matches_requested": requested,
		"levels": levels,
		"scenarios": reports[0]["scenarios"],
		"matches": matches,
	}
	merged["summary"] = summarize(merged, rosters_of(_factions_of(matches)), gate)
	return {"report": merged}


## The roster of each faction in `factions`: its unit types (the roster entries with a queue tab),
## `{faction id: Array[String]}`.
static func rosters_of(factions: Array) -> Dictionary:
	var rosters: Dictionary = {}
	for faction: String in factions:
		var def: FactionDef = null
		if ResourceLoader.exists(FACTION_PATH % faction):
			def = load(FACTION_PATH % faction) as FactionDef
		var types: Array[String] = []
		if def != null:
			for unit: UnitDef in def.roster:
				if unit.tab >= 1:
					types.append(String(unit.type_id))
		rosters[faction] = types
	return rosters


## The summary of the merged `report` (ADR 0031 section 4). `rosters` is rosters_of() of its
## factions. With `gate` the summary also has the gate block (section 6).
static func summarize(report: Dictionary, rosters: Dictionary, gate: bool) -> Dictionary:
	var matches: Array = report["matches"]
	var ends: Dictionary[String, int] = {"victory": 0, "draw": 0, "timeout": 0}
	var dropped: int = 0
	var flow_total: int = 0
	var flow_most: int = 0
	var lengths: Array[int] = []
	var hashes: Dictionary[String, bool] = {}
	for record: Dictionary in matches:
		ends[record["end"]] = ends.get(record["end"], 0) + 1
		dropped += int(record["dropped_commands"])
		flow_total += int(record["flow_full_ticks"])
		flow_most = maxi(flow_most, int(record["flow_full_ticks"]))
		lengths.append(int(record["ticks"]))
		hashes[String(record["state_hash"])] = true
	lengths.sort()
	var summary: Dictionary = {
		"matches": matches.size(),
		"victories": ends["victory"],
		"draws": ends["draw"],
		"timeouts": ends["timeout"],
		"dropped_commands": dropped,
		"flow_full_ticks": {"total": flow_total, "most_in_one": flow_most},
		"by_faction": _shares(matches, "faction"),
		"by_seat": _shares(matches, "seat"),
		"length_ticks":
		{"median": _median(lengths), "p90": _percentile(lengths, 90), "max": _last(lengths)},
		"types": _types(matches, rosters),
		"distinct_final_hashes": hashes.size(),
	}
	var levels: Array[String] = _strings(report["levels"])
	if levels[0] != levels[1]:
		summary["by_level"] = _shares(matches, "level")
	summary["flags"] = _flags(summary)
	if gate:
		summary["gate"] = _gate(summary, report)
	return summary


## Win shares in per-mille per value of the player field `field`, a draw or timeout counting half
## to each side: the halves a value scored over twice its appearances.
static func _shares(matches: Array, field: String) -> Dictionary:
	var halves: Dictionary[String, int] = {}
	var seats: Dictionary[String, int] = {}
	for record: Dictionary in matches:
		var decided: bool = record["end"] == "victory" and int(record["winner"]) != 0
		for player: Dictionary in record["players"]:
			var key: String = String(player[field])
			var score: int = 1
			if decided:
				score = 2 if int(player["player"]) == int(record["winner"]) else 0
			halves[key] = halves.get(key, 0) + score
			seats[key] = seats.get(key, 0) + 1
	var shares: Dictionary = {}
	for key: String in halves:
		shares[key] = _permille(halves[key], 2 * seats[key])
	return shares


## The per type rows, `{type id: {...}}`, for the units of each faction's roster.
static func _types(matches: Array, rosters: Dictionary) -> Dictionary:
	var rows: Dictionary = {}
	for faction: String in rosters:
		var sums: Dictionary[String, int] = {}
		var total: int = 0
		for record: Dictionary in matches:
			var in_match: Dictionary[String, bool] = {}
			for player: Dictionary in record["players"]:
				if player["faction"] != faction:
					continue
				for type_id: String in rosters[faction]:
					var made: int = int(player["produced"].get(type_id, 0))
					total += made
					in_match[type_id] = in_match.get(type_id, false) or made > 0
					for map: String in ["produced", "kills", "spent", "lost", "free"]:
						var at: String = "%s %s" % [map, type_id]
						sums[at] = sums.get(at, 0) + int(player[map].get(type_id, 0))
			for type_id: String in in_match:
				var at: String = "built %s" % type_id
				sums[at] = sums.get(at, 0) + (1 if in_match[type_id] else 0)
		for type_id: String in rosters[faction]:
			var made: int = sums.get("produced " + type_id, 0)
			var existed: int = made + sums.get("free " + type_id, 0)
			rows[type_id] = {
				"faction": faction,
				"produced": made,
				"share_permille": _permille(made, total),
				"kills_per_1000_credits_x100":
				_ratio(sums.get("kills " + type_id, 0), 100000, sums.get("spent " + type_id, 0)),
				"survival_permille":
				_permille(maxi(existed - sums.get("lost " + type_id, 0), 0), existed),
				"matches_built": sums.get("built " + type_id, 0),
			}
	return rows


## The flags, one text each, in a fixed order: the skill's, then the three of section 4.
static func _flags(summary: Dictionary) -> Array[String]:
	var found: Array[String] = []
	for group: String in ["by_faction", "by_seat", "by_level"]:
		var shares: Dictionary = summary.get(group, {})
		for key: String in _sorted(shares.keys()):
			if shares[key] < SHARE_MIN or shares[key] > SHARE_MAX:
				found.append(
					(
						"%s %s win share %d per-mille is outside %d-%d"
						% [group, key, shares[key], SHARE_MIN, SHARE_MAX]
					)
				)
	var median: int = summary["length_ticks"]["median"]
	if summary["matches"] > 0 and (median < MEDIAN_MIN or median > MEDIAN_MAX):
		found.append("median length %d ticks is outside %d-%d" % [median, MEDIAN_MIN, MEDIAN_MAX])
	var types: Dictionary = summary["types"]
	for type_id: String in _sorted(types.keys()):
		var share: int = types[type_id]["share_permille"]
		if share < TYPE_MIN or share > TYPE_MAX:
			found.append(
				(
					"%s (%s) is %d per-mille of its production, outside %d-%d"
					% [type_id, types[type_id]["faction"], share, TYPE_MIN, TYPE_MAX]
				)
			)
	if summary["timeouts"] > 0:
		found.append("%d matches timed out" % summary["timeouts"])
	if summary["flow_full_ticks"]["total"] > 0:
		found.append("the flow cache was full in %d ticks" % summary["flow_full_ticks"]["total"])
	if summary["distinct_final_hashes"] * 100 < HASH_MIN_PERCENT * summary["matches"]:
		found.append(
			(
				"%d distinct final hashes in %d matches, under %d percent"
				% [summary["distinct_final_hashes"], summary["matches"], HASH_MIN_PERCENT]
			)
		)
	return found


## The gate block (ADR 0031 section 6): `matches` and `verdict` ("pass", "rerun" or "fail") and the
## `checks`, each with `id`, `name`, `value`, `min`, `max` (the limits, ints), `detail` and its own
## verdict. A faction or seat share of 350-399 or 601-650 asks for the one rerun while the set is
## under 200 matches; the 200 together decide against 400-600.
static func _gate(summary: Dictionary, report: Dictionary) -> Dictionary:
	var count: int = summary["matches"]
	var top: Dictionary = {"top": summary["by_seat"].get("top", 0)}
	var checks: Array[Dictionary] = [
		_share_check("1", "faction win share", summary["by_faction"], count),
		_share_check("2", "top seat win share", top, count),
		_check("3a", "timeouts", summary["timeouts"], 0, 0, ""),
		_check(
			"3b", "longest match (ticks)", summary["length_ticks"]["max"], 0, GATE_MAX_TICKS, ""
		),
	]
	var least: int = count
	var least_type: String = ""
	for type_id: String in _sorted(summary["types"].keys()):
		if least_type.is_empty() or summary["types"][type_id]["matches_built"] < least:
			least = summary["types"][type_id]["matches_built"]
			least_type = type_id
	# Built in at least half the matches (50 of 100).
	var detail: String = "%s in %d of %d" % [least_type, least, count]
	checks.append(
		_check("4", "least built unit type (matches)", least, (count + 1) / 2, count, detail)
	)
	checks.append(_check("5", "most dropped commands in a match", _most_dropped(report), 0, 0, ""))
	var hashes: int = summary["distinct_final_hashes"]
	var need: int = (HASH_MIN_PERCENT * count + 99) / 100
	checks.append(_check("6", "distinct final hashes", hashes, need, count, ""))
	var native: int = 1 if report["impl"] == IMPL_NATIVE else 0
	checks.append(_check("7", "impl is native", native, 1, 1, "impl %s" % report["impl"]))
	var verdict: String = "pass"
	for check: Dictionary in checks:
		if check["verdict"] == "fail":
			verdict = "fail"
			break
		if check["verdict"] == "rerun":
			verdict = "rerun"
	return {"matches": count, "verdict": verdict, "checks": checks}


## Check 1 or 2: the share farthest from 500 among `shares`, against 400-600 with the rerun band.
static func _share_check(id: String, name: String, shares: Dictionary, count: int) -> Dictionary:
	var worst: int = 500
	var detail: Array[String] = []
	for key: String in _sorted(shares.keys()):
		detail.append("%s %d" % [key, shares[key]])
		if absi(shares[key] - 500) > absi(worst - 500):
			worst = shares[key]
	var check: Dictionary = _check(id, name, worst, SHARE_MIN, SHARE_MAX, ", ".join(detail))
	var rerun: bool = count < GATE_RERUN_MATCHES and worst >= RERUN_MIN and worst <= RERUN_MAX
	if check["verdict"] == "fail" and rerun:
		check["verdict"] = "rerun"
	return check


static func _check(
	id: String, name: String, value: int, low: int, high: int, detail: String
) -> Dictionary:
	return {
		"id": id,
		"name": name,
		"value": value,
		"min": low,
		"max": high,
		"detail": detail,
		"verdict": "pass" if value >= low and value <= high else "fail",
	}


static func _most_dropped(report: Dictionary) -> int:
	var most: int = 0
	for record: Dictionary in report["matches"]:
		most = maxi(most, int(record["dropped_commands"]))
	return most


## The text of the merged report file: sorted keys, indented, a newline at the end.
static func report_text(report: Dictionary) -> String:
	return JSON.stringify(report, "  ", true) + "\n"


## The markdown of the merged `report`: a fixed template of tables, then the flags, then the gate.
static func markdown(report: Dictionary) -> String:
	var summary: Dictionary = report["summary"]
	var flow: Dictionary = summary["flow_full_ticks"]
	var length: Dictionary = summary["length_ticks"]
	var lines: PackedStringArray = PackedStringArray()
	lines.append("## Balance summary")
	lines.append("")
	(
		lines
		. append(
			(
				"Commit `%s`, impl `%s`, levels `%s`, scenarios `%s`, at most %d ticks a match."
				% [
					report["commit"],
					report["impl"],
					",".join(_strings(report["levels"])),
					report["scenarios"],
					report["ticks_per_match"],
				]
			)
		)
	)
	lines.append("")
	lines.append("| Matches | Victories | Draws | Timeouts | Dropped | Flow full (total, most) |")
	lines.append("| --- | --- | --- | --- | --- | --- |")
	(
		lines
		. append(
			(
				"| %d | %d | %d | %d | %d | %d, %d |"
				% [
					summary["matches"],
					summary["victories"],
					summary["draws"],
					summary["timeouts"],
					summary["dropped_commands"],
					flow["total"],
					flow["most_in_one"],
				]
			)
		)
	)
	lines.append("")
	lines.append("### Win shares (per-mille; a draw or timeout counts half to each side)")
	lines.append("")
	lines.append("| Group | Value | Share |")
	lines.append("| --- | --- | --- |")
	for group: String in ["by_faction", "by_seat", "by_level"]:
		var shares: Dictionary = summary.get(group, {})
		for key: String in _sorted(shares.keys()):
			lines.append("| %s | %s | %d |" % [group.trim_prefix("by_"), key, shares[key]])
	lines.append("")
	lines.append("### Match length")
	lines.append("")
	(
		lines
		. append(
			(
				"Median %s, 90th percentile %s, longest %s (%d, %d and %d ticks)."
				% [
					_minutes(length["median"]),
					_minutes(length["p90"]),
					_minutes(length["max"]),
					length["median"],
					length["p90"],
					length["max"],
				]
			)
		)
	)
	lines.append("")
	lines.append("### Unit types")
	lines.append("")
	lines.append(
		"| Faction | Type | Produced | Share | Kills per 1 000 credits | Survival | Built in |"
	)
	lines.append("| --- | --- | --- | --- | --- | --- | --- |")
	var types: Dictionary = summary["types"]
	var order: Array[String] = _sorted(types.keys())
	order.sort_custom(
		func(a: String, b: String) -> bool:
			if types[a]["faction"] != types[b]["faction"]:
				return types[a]["faction"] < types[b]["faction"]
			return a < b
	)
	for type_id: String in order:
		var row: Dictionary = types[type_id]
		var kills: int = row["kills_per_1000_credits_x100"]
		(
			lines
			. append(
				(
					"| %s | %s | %d | %d | %d.%02d | %d | %d |"
					% [
						row["faction"],
						type_id,
						row["produced"],
						row["share_permille"],
						kills / 100,
						kills % 100,
						row["survival_permille"],
						row["matches_built"],
					]
				)
			)
		)
	lines.append("")
	lines.append("Share and survival are per-mille; a type that never occurred shows 0.")
	(
		lines
		. append(
			(
				"Kills are an estimate, credited in this order: a shot at the unit in the tick it died; "
				+ "else an enemy rupture landing in that tick within its radius (to the strike "
				+ "building's type); else the unit's last shooter; else nobody. Structures and "
				+ "cancelled sites are not in the unit rows."
			)
		)
	)
	lines.append("")
	lines.append("### Flags")
	lines.append("")
	if summary["flags"].is_empty():
		lines.append("None.")
	for flag: String in summary["flags"]:
		lines.append("- %s" % flag)
	lines.append("")
	lines.append("Distinct final hashes: %d." % summary["distinct_final_hashes"])
	if summary.has("gate"):
		var gate: Dictionary = summary["gate"]
		lines.append("")
		lines.append("### Gate: %s" % String(gate["verdict"]).to_upper())
		lines.append("")
		lines.append("| Check | What | Value | Limit | Verdict | Detail |")
		lines.append("| --- | --- | --- | --- | --- | --- |")
		for check: Dictionary in gate["checks"]:
			(
				lines
				. append(
					(
						"| %s | %s | %d | %d-%d | %s | %s |"
						% [
							check["id"],
							check["name"],
							check["value"],
							check["min"],
							check["max"],
							check["verdict"],
							check["detail"],
						]
					)
				)
			)
	return "\n".join(lines) + "\n"


## "N.N min" for a number of ticks, rounded to a tenth with ints only.
static func _minutes(ticks: int) -> String:
	var tenths: int = (ticks * 10 + TICKS_PER_MINUTE / 2) / TICKS_PER_MINUTE
	return "%d.%d min" % [tenths / 10, tenths % 10]


## The text of a refusal naming the field two shards differ in, empty when they merge.
static func _refusal(reports: Array[Dictionary], names: Array[String]) -> String:
	for index: int in range(1, reports.size()):
		for field: String in SAME_FIELDS + ["levels"]:
			if _field_key(reports[index], field) != _field_key(reports[0], field):
				return (
					"field '%s' differs: %s has %s, %s has %s"
					% [
						field,
						names[0],
						str(reports[0].get(field)),
						names[index],
						str(reports[index].get(field)),
					]
				)
	return ""


## A shard's field as the merge compares it: `levels` as a sorted pair.
static func _field_key(report: Dictionary, field: String) -> String:
	if field != "levels":
		return str(report.get(field))
	var levels: Array[String] = _strings(report.get(field, []))
	levels.sort()
	return ",".join(levels)


## The players' levels in seat order, the second key of the sort.
static func _order_of(record: Dictionary) -> String:
	var levels: Array[String] = []
	for player: Dictionary in record["players"]:
		levels.append(String(player["level"]))
	return ",".join(levels)


static func _factions_of(matches: Array[Dictionary]) -> Array[String]:
	var found: Array[String] = []
	for record: Dictionary in matches:
		for player: Dictionary in record["players"]:
			if not found.has(String(player["faction"])):
				found.append(String(player["faction"]))
	found.sort()
	return found


static func _strings(values: Array) -> Array[String]:
	var texts: Array[String] = []
	for value: Variant in values:
		texts.append(String(value))
	return texts


static func _sorted(values: Array) -> Array[String]:
	var texts: Array[String] = _strings(values)
	texts.sort()
	return texts


## `part / whole` in per-mille, rounded half up; 0 when `whole` is 0.
static func _permille(part: int, whole: int) -> int:
	return _ratio(part, 1000, whole)


## `part * scale / whole` rounded half up; 0 when `whole` is 0.
static func _ratio(part: int, scale: int, whole: int) -> int:
	if whole <= 0:
		return 0
	return (part * scale * 2 + whole) / (2 * whole)


## The middle value of the sorted `values` (the mean of the two middle ones, rounded down).
static func _median(values: Array[int]) -> int:
	if values.is_empty():
		return 0
	var size: int = values.size()
	return values[size / 2] if size % 2 == 1 else (values[size / 2 - 1] + values[size / 2]) / 2


## The nearest-rank `percent`th percentile of the sorted `values`.
static func _percentile(values: Array[int], percent: int) -> int:
	if values.is_empty():
		return 0
	return values[(percent * values.size() + 99) / 100 - 1]


static func _last(values: Array[int]) -> int:
	return 0 if values.is_empty() else values[values.size() - 1]


## `value` with every float that holds a whole number turned into an int, deep.
static func _ints(value: Variant) -> Variant:
	if value is float and value == floorf(value):
		return int(value)
	if value is Array:
		var items: Array = []
		for item: Variant in value:
			items.append(_ints(item))
		return items
	if value is Dictionary:
		var map: Dictionary = {}
		for key: Variant in value:
			map[key] = _ints(value[key])
		return map
	return value


static func _write(path: String, text: String) -> bool:
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(text)
	file.close()
	return true
