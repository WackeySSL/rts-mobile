extends RefCounted
## The strike block of the balance summary (ADR 0047 section 12, plan row P571): the eleven strike
## keys of a player entry (`SmokeCount.STRIKE_KEYS`) summed per faction and per level, and the mean
## per fire. A report from before the keys has none of them and counts 0 everywhere.
##
## A group is `{"player_matches", "fires", "totals", "caused", "per_fire"}`:
## - `fires`: the rupture and blackout fires of the group's players;
## - `totals`: each key summed over the group's players, as recorded;
## - `caused`: what those fires did. The firer-side keys (damage, kills) are the group's own; the
##   victim-side keys (`VICTIM_KEYS`: a blackout's building-ticks, sight cut, cells lost and dark
##   radar) are the other players' of the same match, because they are counted on the victim;
## - `per_fire`: `caused` per fire in hundredths, ints only. Building-seconds are ticks over
##   `Sim.TICK_RATE`. `kills` is buildings plus units. 0 fires give 0.

const SmokeCount: GDScript = preload("res://tests/smoke/smoke_count.gd")

## The strike keys that the victim of a fire holds; the others are the firer's.
const VICTIM_KEYS: Array[String] = [
	"blackout_building_ticks",
	"sight_cut_building_ticks",
	"sight_cells_lost",
	"radar_dark_ticks",
]

## The `per_fire` entries the table shows, in column order.
const COLUMNS: Array[String] = [
	"damage_enemy",
	"damage_own",
	"kills_buildings",
	"kills_units",
	"kills_own",
	"blackout_building_seconds",
	"sight_cells_lost",
	"sight_cut_building_seconds",
	"radar_dark_seconds",
]


## `{"by_faction": {id: group}}` of the `matches` and, when `by_level`, `"by_level"` too.
static func build(matches: Array, by_level: bool) -> Dictionary:
	var by_faction: Dictionary = {}
	var by_level_groups: Dictionary = {}
	for record: Dictionary in matches:
		var players: Array = record["players"]
		for player: Dictionary in players:
			var victim: Dictionary = {}
			for other: Dictionary in players:
				if other["player"] != player["player"]:
					for key: String in VICTIM_KEYS:
						victim[key] = int(victim.get(key, 0)) + int(other.get(key, 0))
			_add(by_faction, String(player["faction"]), player, victim)
			if by_level:
				_add(by_level_groups, String(player["level"]), player, victim)
	var result: Dictionary = {"by_faction": _finish(by_faction)}
	if by_level:
		result["by_level"] = _finish(by_level_groups)
	return result


## The "### Strikes" table of `strikes` (a `build` result), one row per faction and per level that
## fired; nothing when no group did.
static func append_lines(strikes: Dictionary, lines: PackedStringArray) -> void:
	var rows: Array[String] = []
	for scope: String in ["by_faction", "by_level"]:
		var groups: Dictionary = strikes.get(scope, {})
		var ids: Array = groups.keys()
		ids.sort()
		for id: String in ids:
			var group: Dictionary = groups[id]
			if int(group["fires"]) == 0:
				continue
			var per: Dictionary = group["per_fire"]
			var cells: Array[String] = [scope.trim_prefix("by_") + " " + id, str(group["fires"])]
			for name: String in COLUMNS:
				cells.append(_hundredths(per[name]))
			rows.append("| %s |" % " | ".join(cells))
	if rows.is_empty():
		return
	lines.append("### Strikes")
	lines.append("")
	lines.append(
		(
			"| Group | Fires | Damage | Own damage | Kills: buildings | units | own "
			+ "| Blackout building-s | Sight cells lost | Sight-cut building-s | Radar-dark s |"
		)
	)
	lines.append("| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |")
	lines.append_array(rows)
	lines.append("")
	lines.append(
		(
			"Per fire, rupture and blackout together. Damage and kills are the firer's; blackout, "
			+ "sight and radar numbers are the victim's. A rupture's kills are an upper bound."
		)
	)
	lines.append("")


static func _add(groups: Dictionary, id: String, player: Dictionary, victim: Dictionary) -> void:
	if not groups.has(id):
		var totals: Dictionary = {}
		var caused: Dictionary = {}
		for key: String in SmokeCount.STRIKE_KEYS:
			totals[key] = 0
			caused[key] = 0
		groups[id] = {"player_matches": 0, "fires": 0, "totals": totals, "caused": caused}
	var group: Dictionary = groups[id]
	group["player_matches"] += 1
	group["fires"] += int(player.get("strike_fires_rupture", 0))
	group["fires"] += int(player.get("strike_fires_blackout", 0))
	for key: String in SmokeCount.STRIKE_KEYS:
		group["totals"][key] += int(player.get(key, 0))
		if VICTIM_KEYS.has(key):
			group["caused"][key] += int(victim.get(key, 0))
		else:
			group["caused"][key] += int(player.get(key, 0))


## `groups` with each group's `per_fire` added.
static func _finish(groups: Dictionary) -> Dictionary:
	for id: String in groups:
		var group: Dictionary = groups[id]
		var caused: Dictionary = group["caused"]
		var fires: int = group["fires"]
		var seconds: int = fires * Sim.TICK_RATE
		group["per_fire"] = {
			"damage_enemy": _per(caused["strike_damage_enemy"], fires),
			"damage_own": _per(caused["strike_damage_own"], fires),
			"kills_buildings": _per(caused["strike_kills_buildings"], fires),
			"kills_units": _per(caused["strike_kills_units"], fires),
			"kills": _per(caused["strike_kills_buildings"] + caused["strike_kills_units"], fires),
			"kills_own": _per(caused["strike_kills_own"], fires),
			"blackout_building_seconds": _per(caused["blackout_building_ticks"], seconds),
			"sight_cells_lost": _per(caused["sight_cells_lost"], fires),
			"sight_cut_building_seconds": _per(caused["sight_cut_building_ticks"], seconds),
			"radar_dark_seconds": _per(caused["radar_dark_ticks"], seconds),
		}
	return groups


## `part` over `whole` in hundredths (integer division), 0 when `whole` is 0.
@warning_ignore("integer_division")
static func _per(part: int, whole: int) -> int:
	return 0 if whole <= 0 else part * 100 / whole


## "N.NN" for a number of hundredths.
@warning_ignore("integer_division")
static func _hundredths(value: int) -> String:
	return "%d.%02d" % [value / 100, value % 100]
