class_name PerfBases
extends RefCounted
## The perf card's choice between the seed-42 arena and the base arena (plan P93c, ADR 0021): which
## golden pair the card judges, the comparison itself, the names a mismatch carries and the base
## arena's draw-call forecast. `PerfHud` keeps `arena_kind`; everything else about the choice is
## here so the card stays small.

const ARENA_UNITS: String = "arena"
const ARENA_BASES: String = "bases"
## The gate fields of the base arena's pair, named in a mismatch so a re-pin goes to the right one.
const FIELDS: String = " (bases_golden_ticks, bases_golden_hex)"
## ADR 0023 section 2's draw-call forecast of the base arena, HUD left out: 14 since the craters
## (note of 2026-10-30), and at least 15 while a strike is aimed or in flight (`StrikeMarkerLayer`).
## Printed beside the measured p95 with no verdict; the gate's ceiling is `draw_calls_max`.
const CALLS_FORECAST: int = 14
const CALLS_STRIKE: int = 15
const CALLS_LINE: String = (
	"draw calls p95 %d | forecast %d, %d while a strike is aimed or in flight, plus the HUD "
	+ "(no verdict)"
)


static func ticks(gate: PerfGateDef, kind: String) -> PackedInt32Array:
	return gate.bases_golden_ticks if kind == ARENA_BASES else gate.golden_ticks


static func hexes(gate: PerfGateDef, kind: String) -> PackedStringArray:
	return gate.bases_golden_hex if kind == ARENA_BASES else gate.golden_hex


## What a failed golden row adds: the base arena's gate fields, nothing for the seed-42 arena.
static func fields(kind: String) -> String:
	return FIELDS if kind == ARENA_BASES else ""


## The card's draw-call line of the base arena for the measured p95.
static func calls_line(p95: int) -> String:
	return CALLS_LINE % [p95, CALLS_FORECAST, CALLS_STRIKE]


## The checkpoints of a run (`got_ticks` and `got_hex`, index by index) against the golden `ticks`
## and `hexes`, the golden ticks up to `run_ticks`: `match` is true when at least one was checked
## and every one agrees. `tick` is the first golden tick that differs (-1 for none) with the hash
## text the run `got` there ("none" when a finished run lacks it) and the golden `want`; a tick the
## unfinished run has not reached is skipped.
static func compare(
	ticks_in: PackedInt32Array,
	hexes_in: PackedStringArray,
	got_ticks: PackedInt32Array,
	got_hex: PackedStringArray,
	run_ticks: int,
	finished: bool
) -> Dictionary:
	var out: Dictionary = {"match": false, "checked": 0, "tick": -1, "got": "", "want": ""}
	for i: int in mini(ticks_in.size(), hexes_in.size()):
		var at: int = got_ticks.find(ticks_in[i])
		if ticks_in[i] > run_ticks or (at < 0 and not finished):
			continue
		out["checked"] += 1
		var got: String = got_hex[at] if at >= 0 else "none"
		if got != hexes_in[i]:
			out["tick"] = ticks_in[i]
			out["got"] = got
			out["want"] = hexes_in[i]
			return out
	out["match"] = out["checked"] > 0
	return out
