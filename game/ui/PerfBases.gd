class_name PerfBases
extends RefCounted
## The perf card's choice between the seed-42 arena, the base arena (plan P93c, ADR 0021) and the
## AI arena (plan P185, no golden pair, its report-only AI line): which golden pair the card
## judges, the comparison itself, the names a mismatch carries and the base arena's draw-call
## forecast. `PerfHud` keeps `arena_kind`; everything else about the choice is here so the card
## stays small.

const ARENA_UNITS: String = "arena"
const ARENA_BASES: String = "bases"
## The base AI arena (plan P185): `perf_ai.tres` with a computer on each player. No golden pair.
const ARENA_AI: String = "ai"
## The AI arena of Phase 4b (plan P304): `perf_ai_4b.tres`, the per-wave card's. Its own key, so a
## card names which of the two AI arenas it ran. No golden pair either.
const ARENA_AI_4B: String = "ai_4b"
## The air arena (plan P253): `perf_air.tres`, 16 aircraft among 150 units; its pair is the gate's
## `air_golden_*`.
const ARENA_AIR: String = "air"
## The gate fields of the base arena's pair, named in a mismatch so a re-pin goes to the right one.
const FIELDS: String = " (bases_golden_ticks, bases_golden_hex)"
const AIR_FIELDS: String = " (air_golden_ticks, air_golden_hex)"
## ADR 0023 section 2's draw-call forecast of the base arena, HUD left out: 16 (14 + `GroundFx` +
## `AirFx`, note of 2026-11-02, P132) and `MineLayer` (P293: 17), about 23 in the worst moment, and
## one more while a strike is aimed or in the air (`StrikeMarkerLayer`, note of 2026-10-30; the
## 2026-10-31 note adds the ghost, outside this arena).
## Printed beside the measured p95 with no verdict; the gate's ceiling is `draw_calls_max`.
const CALLS_FORECAST: int = 17
const CALLS_STRIKE: int = 18
const CALLS_WORST: int = 23
const CALLS_LINE: String = (
	"draw calls p95 %d | forecast %d, %d while a strike is aimed or in flight, about %d at worst, "
	+ "plus the HUD (no verdict)"
)

## The card's AI line (plan P185, ADR 0030 section 4), report-only: the p95 and the dearest think
## over the ticks on which a computer player thought, and how many ticks that was. 1.0 ms is the
## watch value the p95 is read against, printed so the phone reads it without the ADR.
const AI_WATCH_MS: float = 1.0
const AI_LINE: String = (
	"arena %s | ai_think_p95_ms %.2f | ai_think_max_ms %.2f | ai_thinks %d | watch p95 at or "
	+ "below %.2f ms | ai_wait_p95_ms %.2f | ai_wait_max_ms %.2f | ai_waits %d (no verdict)"
)


## Whether the arena has a golden pair the card compares with (not either AI arena's).
static func has_golden(kind: String) -> bool:
	return not is_ai(kind)


## Whether `kind` is one of the two AI arenas (they share the card's AI line and have no pair).
static func is_ai(kind: String) -> bool:
	return kind == ARENA_AI or kind == ARENA_AI_4B


static func ai_line(
	kind: String,
	p95_ms: float,
	max_ms: float,
	thinks: int,
	wait_p95_ms: float,
	wait_max_ms: float,
	waits: int
) -> String:
	return AI_LINE % [kind, p95_ms, max_ms, thinks, AI_WATCH_MS, wait_p95_ms, wait_max_ms, waits]


static func ticks(gate: PerfGateDef, kind: String) -> PackedInt32Array:
	if kind == ARENA_AIR:
		return gate.air_golden_ticks
	return gate.bases_golden_ticks if kind == ARENA_BASES else gate.golden_ticks


static func hexes(gate: PerfGateDef, kind: String) -> PackedStringArray:
	if kind == ARENA_AIR:
		return gate.air_golden_hex
	return gate.bases_golden_hex if kind == ARENA_BASES else gate.golden_hex


## What a failed golden row adds: the base arena's gate fields, nothing for the seed-42 arena.
static func fields(kind: String) -> String:
	if kind == ARENA_AIR:
		return AIR_FIELDS
	return FIELDS if kind == ARENA_BASES else ""


## The card's draw-call line of the base arena for the measured p95.
static func calls_line(p95: int) -> String:
	return CALLS_LINE % [p95, CALLS_FORECAST, CALLS_STRIKE, CALLS_WORST]


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
