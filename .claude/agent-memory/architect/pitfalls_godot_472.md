---
name: pitfalls-godot-472
description: Verified Godot 4.7.2 / gdUnit4 / export pitfalls that broke earlier plan drafts (camera limits, push_error scan, export dir, version string, pck feature check)
metadata:
  type: feedback
---

Pitfalls a reviewer caught in the Phase 0 plan (2026-10-10); check new plans against them.
**Why:** each one was written into a plan as fact without being run. **How to apply:** before stating engine behaviour in a plan, run it or label it unverified.
- Camera2D `limit_*` clamps only the view, not `position`: clamp position yourself or overscroll leaves a dead zone.
- An asserted `push_error` in gdUnit4 still prints `ERROR:` and fails verify.sh's log scan; needs an allowlist entry or no test of that path.
- `--export-release` fails (exit 1) if the output folder does not exist; mkdir -p first, and delete stale artifacts.
- `godot --version` = `4.7.2.stable.official.<hash>`; template dir is the first FOUR dot fields.
- `grep dev_menu` on a PCK matches paths; use `strings | grep -A1 -x _custom_features | grep -qx dev_menu`.
- 1280x720 canvas_items/expand on a landscape phone browser is ~0.42-0.57 dp per base px; size touch targets accordingly.
- `git diff --quiet` misses untracked `.uid`/`.import`; use `git status --porcelain` for clean-tree checks.
- Purity regexes need fixture tests; the first draft missed randi_range, sqrt, float literals and banned legit `delta` ints.
- Preview jobs must fail when the link is not live, or "green" proves nothing; enable Pages before the first PR.
- (2026-10-13, P31b review) Godot 4.7.2: a `const X: Array[StringName] = A + [..]` (any const built by an expression) is UNTYPED at runtime (is_typed() false); assigning it to a typed var or passing it as a typed param fails only at runtime. Typed const lists must be literals (found in P31b review: World.UNHASHED_SCALARS, FlowField/FlowCache.UNHASHED).
