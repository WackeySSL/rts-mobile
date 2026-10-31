class_name PerfGateDef
extends Resource
## The perf gate's thresholds and golden hashes (ADR 0012 section 4 as ADR 0014 sections 1-4
## change it). The instance will be res://data/dev/perf_gate.tres (P38p); these defaults are the
## ADRs' values. The CPU-time limits are the 2021 limits divided by k = 2.5 for the gate phone;
## the pacing values are not divided. Times are milliseconds.

## The heavy window: frames that draw at least `heavy_rigs` rigs; it must hold `heavy_frames_min`.
@export var heavy_rigs: int = 135
@export var heavy_frames_min: int = 600
## Main-thread frame work p95, normalised (ADR 0014 section 3): all heavy-window frames, and the
## heavy window's publish frames only.
@export var work_p95_ms: float = 5.6
@export var work_tick_p95_ms: float = 5.6
## The worker job (`job_usec`), raw: p95 and p99.
@export var sim_p95_ms: float = 13.3
@export var job_p99_ms: float = 26.7
## Jobs whose post-to-done time exceeds one tick period, over the whole run.
@export var late_ticks_max: int = 0
## The fog patch on the main thread, normalised p95.
@export var fog_update_p95_ms: float = 0.4
## Draw calls p95; a count, not divided.
@export var draw_calls_max: int = 60
## A card from a debug template fails the build verdict.
@export var release_only: bool = true
## Phone time / CI time of the tick, mean and p95, from the release run's worker mode. Printed
## estimates, not thresholds.
@export var ci_ratio_mean: float = 4.4
@export var ci_ratio_p95: float = 5.9
## The same for the native kernels (ADR 0013 section 15): the release worker job over the CI
## native tick, re-derived from the first release perf-arena card by the 10 % rule (plan exception
## 5, gate issue #157): mean 3.070 / 0.277 and p95 5.834 / 0.484 ms (Pixel 9a against CI run 370),
## rounded up to one decimal. Printed estimates of the impl=native PERF line (P38pn), not
## thresholds.
@export var ci_ratio_native_mean: float = 11.1
@export var ci_ratio_native_p95: float = 12.1
## Pacing (ADR 0014 section 1): a frame interval above P + drop_slots x V is dropped; at most
## dropped_pct_max percent dropped and at least cadence_pct_min percent cadence, over the run and
## the heavy window; at most hitches_max intervals of a tick period or more in the heavy window.
@export var drop_slots: float = 0.5
@export var dropped_pct_max: float = 1.0
@export var cadence_pct_min: float = 99.0
@export var hitches_max: int = 0
## The share of intervals up to this length is printed as jitter, a diagnostic without a verdict.
@export var jitter_ms: float = 17.5
## INVALID (ADR 0014 section 2): a median interval below P less this percent (one-sided), and a
## refresh rate that changes by more than this percent or lies this far below max_fps.
@export var median_tolerance_pct: float = 2.0
@export var refresh_tolerance_pct: float = 1.0
## The reference loop (ADR 0014 section 3): iterations per RefLoop run, and the length of the
## burst before every run, whose second half gives ref_peak.
@export var ref_iterations: int = 1000
@export var ref_burst_ms: int = 400
## The golden seed-42 arena checkpoints: ticks and their World.hash_hex() text, index by index.
@export var golden_ticks: PackedInt32Array = PackedInt32Array()
@export var golden_hex: PackedStringArray = PackedStringArray()
## The same for the base arena (plan P93, ADR 0021 section 2): the checkpoints of the seed-42 run of
## data/scenarios/perf_bases.tres, ticks and World.hash_hex() text, index by index. Pinned in
## data/dev/perf_gate.tres by tests/perf/test_golden_hashes.gd; a card of the base arena checks its
## run against them (P93c).
@export var bases_golden_ticks: PackedInt32Array = PackedInt32Array()
@export var bases_golden_hex: PackedStringArray = PackedStringArray()
