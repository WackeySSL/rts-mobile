---
name: project-phase1-decisions
description: Phase 1 plan decisions (ADRs 0003-0005, 2026-10-10) - minimal sim pull-forward, gesture/UiScale design, Android debug APK in CI, PR lanes
metadata:
  type: project
---

- ADR 0003: Phase 1 pulls forward only Sim.step at 15 Hz, Command v0 (ATTACK_MOVE, target point in milli-tiles), SoA World v0, FixedMath.isqrt, Formation slots, MatchRunner + CommandQueue API v0. No hash, replay, separation, combat, RNG. **Why:** rules forbid view-only movement; full Phase 2 core is too big. **How to apply:** Phase 2 ADR adopts or supersedes v0; don't re-decide in Phase 1 reviews.
- Selection and control groups are local input state, not Commands (only orders are Commands).
- ADR 0004: recognizer is pure with injected now_ms; move-first = pan, hold-first (300 ms) = box; taps act immediately (double-tap is a superset); UiScale.dp() returns base px: Android dpi/160, web/desktop/iOS screen_get_scale(), divided by stretch scale. Supersedes ADR 0002 §5 camera input and §6 120 px rule.
- ADR 0005: non-Gradle arm64 debug APK in ci.yml job `android-debug-apk` (needs verify, not required); keystore generated per run; optional stable debug keystore secrets only on push to main; `android-dev-latest` pre-release needs Michael's consent.
- Plan uses two lanes (project instructions: max two threads, merge only on Michael's "merge"); touch-ux-dev lane is the critical path (P5-P17). Docs issue #2 does not block Phase 1 (no RNG) but still blocks Phase 2.
- P1 review: World carries its own MILLI_PER_TILE/TILE_CENTRE consts (Sim reads World, so World cannot read Sim). Accepted; P3 pins Sim.MILLI_PER_TILE == World.MILLI_PER_TILE. Types dedupe by UnitDef.type_id, first wins.
- P2 review (2026-10-11): Formation.assign clamps the target itself (inset = min(radius, map/2)), so it is the final clamp; P3 may clamp too (idempotent). Formation does not dedupe rows or set order: P3 filters ids, dedupes, then sets ATTACK_MOVE. A brute-force reference of ADR 0003 §4 matched Formation on 3000 random worlds (narrow/tiny maps, mixed types).
- P3 contract review (2026-10-11, fe545fc): Command/Sim match the plan table verbatim; verify GREEN (140 cases). Accepted extras: speed-0 ids filtered (ADR 0003 §3), attack_move duplicates ids. Sort is unstable, so P4 MatchRunner must stamp tick = world.tick and a unique runner-wide sequence; future-tick commands are dropped, not kept.
- P8 contract review (2026-10-11, 3231a5a): matches the plan table and ADR 0004 §2; verify GREEN (133). Accepted: MIN_PINCH_DP = 8 is a numeric epsilon (fingers cannot touch closer), not an InputSettings threshold; hand-over gives two CAMERA_ENDs (end_gesture idempotent); a second finger after 300 ms with no advance() gives no LONG_PRESS. Pending for the lead: ADR 0004 §2 addendum for these via a new ADR, not an edit.
