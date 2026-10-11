---
name: pitfalls-phase1-research
description: Verified engine/environment facts from Phase 1 planning (2026-10-10) - DPI on web, push_input coordinates, Android export requirements, cloud network limits
metadata:
  type: feedback
---

**Why:** each was checked headless or in Godot 4.7.2-stable source while planning Phase 1. **How to apply:** reuse instead of re-spiking; label anything not on this list as unverified.
- Cloud session proxy refuses dl.google.com: no Android SDK in cloud sessions, so Android exports are CI-only (runner has JDK 17, ANDROID_HOME, build-tools 34-37).
- `Viewport.push_input()` takes window px; `_unhandled_input` gets base px (2400x1080 window: (1200,540) -> (800,360)). `get_stretch_transform()` = min(w/1280, h/720).
- Headless: screen_get_dpi 96, screen_get_scale 1.0, safe area empty -> UiScale needs fallbacks.
- Web: screen_get_scale = canvas pixel ratio (devicePixelRatio when allow_hidpi, default true); screen_get_dpi = round(DPR*96). Web shell has touch-action:none and user-scalable=no.
- Android export: needs platform-tools/adb + build-tools/*/apksigner (prefers version == target SDK 36), java_sdk_path/android_sdk_path default from JAVA_HOME/ANDROID_HOME; keystore options are secret (export_credentials.cfg) or env GODOT_ANDROID_KEYSTORE_DEBUG_{PATH,USER,PASSWORD}. android_debug.apk template is 127 MB, range-fetchable from the .tpz.
- InputEvent has no timestamp; InputEventScreenTouch has `canceled` and `double_tap`.
- Keep a PR under ~400 changed lines including deletions: a pure module plus its tests often needs two PRs.
- Review P1 (2026-10-10): data-file tests that derive expected values from the same .tres (columns/spacing) are self-referential; pin every contract number literally. Mutation (spawn 2 columns 2->4, spawn 3 spacing 2000->1000) passed all 58 tests.
- P8 review: a guard on min(old, new) tested only with spreading fingers lets the mutation `old >= min` survive (30 -> 7.5 px gives scale 0.25). Test both directions of any two-sided guard.
- P10 (verified headless): Viewport.is_input_handled() stays true after push_input, so "marked handled" needs an _unhandled_input spy; a Button ignores a second touch sequence on the same instance in one test. A stale owned touch index (missed release) followed by a press on a Button leaves the recognizer PENDING and TouchInput eats the Button's release.
