---
name: pitfalls-phase2-research
description: Verified Godot 4.7.2 GDScript facts and costs measured while planning Phase 2 (2026-10-11) - int overflow, int32 truncation, shifts, hashing, Dijkstra and tick costs
metadata:
  type: feedback
---

Measured headless in a scratch project on the cloud VM (Xeon 2.1 GHz). **Why:** they decide sim rules and the perf budget. **How to apply:** reuse instead of re-spiking; treat phone numbers as unverified until the perf arena runs.
- int64 add/mul overflow wraps silently (C++ UB); `1 << 64 == 1`; a constant negative `>>` operand is a parse error, runtime `-8 >> 1 == -4`.
- PackedInt32Array silently truncates stores to int32 (2^31 -> -2^31): never store squared distances there.
- HashingContext SHA-256 of ~10 KB state: 0.07-0.10 ms; GDScript FNV loop: 0.3-0.5 ms. var_to_bytes round-trips Dict with PackedInt32/Int64Array.
- FixedMath.isqrt (digit loop) about 2 us per call: 150 calls per tick = 0.3 ms.
- Array literal inside a loop (`[1, -1][k]`) allocates each pass: 64x64 Dijkstra 17-20 ms vs 3-4 ms with const offsets and a padded grid.
- Mock 150-unit tick: separation with 2-tile cells 1.3 ms vs 1-tile 0.23 ms; full-disc fog 0.69 ms vs incremental per-player 0.12 ms; optimised mock tick 0.7 ms mean, 1.25 ms p95.
- (Documented, not spiked) z_index sorts all canvas items of a CanvasLayer before tree order: a relative negative z on a child can draw under the map; use absolute z per world layer.
