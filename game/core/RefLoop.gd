class_name RefLoop
extends RefCounted
## The reference loop of ADR 0014 section 3 and its normalisation, pure static functions. The perf
## card times run() on the main thread: a burst before every run gives ref_peak, and one sample per
## frame (after a discarded warm-up run) tells how fast the main thread ran in that frame. The
## main-thread work verdicts then use normalised_p95() (the per-frame method, calibration
## 2026-10-13). The worker takes no samples: its job times stay raw.


## The fixed integer loop: `iterations` steps (ref_iterations of PerfGateDef) of a 24-bit
## multiply-add. The result only keeps the work observable; tests pin it, so the loop never
## changes silently.
static func run(iterations: int) -> int:
	var acc: int = 1
	for i: int in iterations:
		acc = (acc * 31 + i) & 0xFFFFFF
	return acc


## The p95 over frames of work_i x min(1, peak / sample_i): each frame's work scaled by its own
## sample against the burst's `peak`, never above the raw value. `work` and `samples` are parallel,
## one entry per frame; `samples` and `peak` share a unit. A frame without a sample (0, or past the
## end of `samples`) and a `peak` of 0 keep the raw value.
static func normalised_p95(
	work: PackedFloat64Array, samples: PackedFloat64Array, peak: float
) -> float:
	var scaled: PackedFloat64Array = PackedFloat64Array()
	scaled.resize(work.size())
	for i: int in work.size():
		var sample: float = samples[i] if i < samples.size() else 0.0
		var factor: float = minf(1.0, peak / sample) if peak > 0.0 and sample > 0.0 else 1.0
		scaled[i] = work[i] * factor
	scaled.sort()
	return PerfStats.percentile(scaled, 95)
