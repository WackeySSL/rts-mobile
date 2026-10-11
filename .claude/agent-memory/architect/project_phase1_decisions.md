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
