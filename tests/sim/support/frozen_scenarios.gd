extends RefCounted
## The scenarios that play the frozen defs of `data/dev/arena/` (plan rows P171 and P174, ADR
## 0031): their golden hashes, and `perf_ai`'s fixed AI workload (ADR 0031 §8), must never move
## with a tuning change to the shipped defs. Not a test suite; shared
## by `test_frozen_defs_data.gd` and `test_defs_data.gd`, so a new pinned scenario is added once.

const ARENA_DIR: String = "res://data/dev/arena"
const SCENARIOS: Array[String] = [
	"res://data/scenarios/perf_arena.tres",
	"res://data/scenarios/perf_bases.tres",
	"res://data/scenarios/controls_test.tres",
	"res://data/scenarios/perf_ai.tres",
]
