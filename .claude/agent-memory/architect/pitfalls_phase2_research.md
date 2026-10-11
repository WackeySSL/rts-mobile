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
- (Plan review 2026-10-11) Godot draw calls under Compatibility: filled draw_rect, draw_line, draw_texture_rect batch; draw_circle/arc/polyline/unfilled rect/polygon cost one call each; Phase 1 Ring = 6 calls. Absolute z: 150 rigs 360 -> 13 calls. viewport_get_measured_render_time_cpu works in Compatibility.
- (Plan review) `"%016x" % negative` prints a minus sign; use encode_s64 + hex_encode. GDScript `+` binds tighter than `<<`. PackedInt32Array has no pop_back and stores 0xFFFFFFFF as -1.
- (Plan review) Real hash state ~86-109 KB costs 0.34-0.38 ms; fog restamp 23-26 us/unit; full 64x64 fog texture rebuild 0.75 ms; 1024-cell Dijkstra slice 1.1-1.5 ms; counting-sort grid rebuild 0.32-0.40 ms vs head/next 0.046 ms; Formation.assign 75 units ~1 ms, 150 units 3.15 ms; aliasing World arrays into locals is 2.7x faster, inline fog lookup 5.6x.
- (Plan review) CI noise: busy runner leaves p50 alone but p95 jumps ~9x (4 ms scheduler slice); enforce min-of-3 and deterministic counters, not single-run p95.
- (Pitfall) Plans that keep Phase 1 tests "unchanged" must check hand-built World.new() helpers in tests (no rules, no player_count, no max_hp) and qa-owned pinned bounds; a typed member referencing a class from a later PR is a parse error.
- (Completeness check) Godot 4.7.2 headless: clipboard_get() logs an ERROR (verify RED), screen_is_kept_on() stays false, ImageTexture.get_image() after update()/set_image() returns the first upload; Engine.max_fps reads back. Plan Callable sinks and CPU-side image() accessors for tests.
- (Completeness check) Size estimates must be counted from listed contents (members, lists, test cases), not asserted; the sqrt-free push d*(R^2-d^2)/2R^2 is 0 at d=0, so coincident-ish pairs need their own rule.
- (Second check) "Phase 1 tests stay green" claims need an audit of every test with run_ticks/Sim.step and 2+ units, including other owners' files (test_player_controller and test_unit_layer repeated test_controls_flow's order); separation proto on controls_test: max centre 3794, min pair 801, all idle tick 155 for the (22250,22250) order. Re-aim view tests to corner tanks rather than weakening them.
- (Second check) A probe/enum consumed across owners needs fixed ids + COUNT + names in the contract, or per-phase numbers drift between PRs.
- (Third check) The Phase 1 test audit must cover view/input/UI tests too: tests pin node names, child order and inner-class properties (Ring.radius/.unit), and fog hiding turns Phase 1 enemy taps into ground taps; hand-built snapshots lack new arrays.
- (Third check) Never let a PR that sets measured bounds (P49) precede a PR that adds the measured work (fog); order them or name the exact constants a later PR may move.
