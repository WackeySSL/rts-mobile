# rts-mobile

Original mobile real-time strategy game: base building, harvesting, tank battles.
Android first, iOS later. Free to play, funded by ads. Open source (MIT code).
Owner: AppCode ApS (Michael). Talk to Michael in Danish; write code, comments,
commits and PR text in English.

Source of truth: this file for rules, `docs/GDD.md` for game design,
`docs/ROADMAP.md` for phases and acceptance criteria, `docs/adr/` for decisions.

## Stack (change only via a new ADR)
- Godot **4.7.x** (pinned: 4.7.2), GDScript 2.0 with **static typing everywhere**. C++17 only
  for the sim's hot-phase kernels in `native/sim_kernels/` (GDExtension, godot-cpp pinned, ADR
  0013), each with a GDScript twin in `game/sim/` that stays the reference and the web path.
  No C#.
- Renderer: **Compatibility** (required for web export and low-end Android).
- 2D top-down, landscape and portrait (ADR 0015; the Android build follows the phone's sensor, the
  web preview turns with the phone). Base size 1280x720, stretch mode `canvas_items`, aspect
  `expand`.
- Tests: gdUnit4 in `tests/`, plus a CI-only C++ sanitizer harness in
  `native/sim_kernels/sanitizer/` (ADR 0013 §10). Format/lint: gdtoolkit 4 (`gdformat`,
  `gdlint`). C++: `clang-format` 20.1.8, pinned in `scripts/ci/check-cpp-format.sh`
  (`native/sim_kernels/.clang-format`).
- Ads: Poing Studios godot-admob plugin (Android + iOS) behind `game/ads/AdService.gd`.

## Commands
- `bash scripts/verify.sh` - full check (format, lint, import, tests, sim smoke). Run once per PR head,
  right before the push (see Token budget).
- `bash scripts/build-native.sh` - builds the C++ kernels (scons 4.9.1, g++, binutils; the NDK for Android: CI, or a cloud session after `bash scripts/cloud/install-android.sh`).
  verify.sh runs it first and checks the C++ format with the pinned clang-format.
- `bash scripts/run-tests.sh` - gdUnit4 only.
- `bash scripts/run-sim-smoke.sh --matches N` - headless AI-vs-AI matches with fixed seeds (balance runs: GitHub Actions only).
- `bash scripts/export-web.sh` - web build for the phone preview.
- `bash scripts/export-android.sh` - Android debug APK (CI, or a cloud session after `bash scripts/cloud/install-android.sh`; without the SDK it exits 4).
Phase 0 created `run-tests.sh`, `run-sim-smoke.sh` and `export-web.sh`, Phase 1 `export-android.sh`;
keep their flags stable because CI and skills call them.

## Layout
```
game/sim/    deterministic simulation: pure GDScript, no Node, no rendering, no time
game/core/   Node-side services (autoloads DetRng and CommandQueue, plus MatchRunner); no game rules
game/view/   presentation: sprites, interpolation, effects, camera
game/input/  touch gestures -> Command objects
game/ui/     HUD, build sidebar, menus
game/ai/     opponent AI (issues Commands like a player)
game/ads/    AdService + consent
game/meta/   progression, save data
native/      C++ sim kernels (GDExtension) and their build; godot-cpp is fetched, not committed
data/        unit/building/AI definitions (.tres) - all balance numbers live here
assets/art/svg/, assets/audio/   see assets/CREDITS.md
scenes/dev/  developer scenes (art gallery, sandbox maps)
tests/       gdUnit4 tests mirroring game/
```

## Architecture rules (hard)
1. Simulation and presentation are separate. `game/sim` never references Node, SceneTree,
   Input, rendering, OS time or frame delta. The view reads sim state and interpolates.
   `native/sim_kernels/` follows the same rules, and rules 2, 3 and 5 apply to it: kernels read
   every rule value from the World, never from a C++ literal (ADR 0013 §2, §4, §6).
2. Fixed tick: 15 Hz. Sim state is integers only (fixed point: 1 tile = 1000 units). No floats in sim state.
3. Randomness only via per-match `DetRandom` streams (created through the `DetRng` factory autoload
   outside `game/sim`). Never `randi()`/`randf()` in sim or AI.
4. Humans and AI act only through `Command` objects queued to the sim. This gives replays,
   AI-vs-AI tests and a path to multiplayer.
5. Stats come from `data/*.tres`. No balance numbers hardcoded in code.
6. Budget: 150 units at 60 fps on a mid-range 2021 Android phone. Pool projectiles and effects.
Details and patterns: skill `rts-sim-conventions`.

## Godot 4 only - never Godot 3 API
`@export`, `@onready`, `await` (not `yield`), `signal_name.connect(callable)`, `instantiate()`,
`CharacterBody2D`, `TileMapLayer` (not `TileMap`), `super()`, typed arrays `Array[Unit]`.
When unsure, load the vendored skill `gdscript-patterns` before writing code.

## Mobile UX rules
Touch targets >= 48 dp. Landscape and portrait (ADR 0015; the Android build follows the phone's
sensor, the web preview turns with the phone; UI code never assumes width > height),
respect safe areas. One finger drag = pan, pinch = zoom,
tap = select, tap ground = move (stops an attack), long-press + drag = box select, double-tap = all of that type.
Details: skill `touch-ui-rules`.

## Monetization rules
Never any ad on the battle screen. Rewarded ads only on explicit player choice. Interstitials only
between matches, capped. Banners only in menus. Debug builds use Google test ad IDs; real IDs are
injected only by the release workflow. UMP consent before any ad request. Details: skill `admob-policy`.

## Legal (hard)
- No names, units, factions, art, audio, music or UI look from Command & Conquer, Red Alert or any
  other existing game. Factions, units and lore are original.
- Never copy code from EA's C&C source release or OpenRA. They are GPL and would force the whole
  project to GPL.
- Assets: only SVG authored in this repo, or CC0/CC-BY with an entry in `assets/CREDITS.md`.
  No asset-store packs, no AI images from outside tools, no web images.
- Never read, print or commit secrets: keystores, `.godot/export_credentials.cfg`, `.env`, API keys.

## Workflow
- Multi-system feature: get a plan from the `architect` subagent first (`docs/plans/`),
  record decisions as ADRs in `docs/adr/NNNN-slug.md`.
- Small PRs (under ~400 changed lines of production code; tests and fixtures don't count), one concern each, with tests.
- PR description: what changed, the VERIFY SUMMARY block, how to test it on the phone preview.
- Missing tool, secret or access: say exactly what is missing and stop. Never mock or work around.
- Tick the checkbox in `docs/ROADMAP.md` when an acceptance criterion is met.
- Player-facing feature or control: add or update its entry in `docs/HOW_TO_PLAY.md` in the same PR.
  Phase 5 builds the tutorial and the How to play screen from that list.

## Token budget (Michael, 2026-10-21)
- `scripts/verify.sh` runs once per PR head, right before the push, not after every edit. While
  working, run only the touched suites (`bash scripts/run-tests.sh -a res://tests/<path>.gd`) and
  gdformat/gdlint on the changed files. Read the VERIFY SUMMARY and the failing lines, not whole logs.
- No timing runs in a session: never run `tests/perf/` again to measure or compare times (timings
  here are noise; CI reports them). The perf suites still run inside verify.sh, because their golden
  hashes and bounds are deterministic. No AI-vs-AI balance runs in a session: they run only in
  GitHub Actions. verify.sh's smoke step stays.
- Red CI: read the CI log, run the failing suite alone, fix that failure, then verify.sh once
  before the push. Never rerun the full suite locally to find the failure.
- qa-engineer only when a test fails or a new test is needed.
- Review: at most 2 rounds. Nits go to the lead's follow-up list, not into a new round. Code PRs get
  2 review lenses, docs PRs 1 lens and no rounds. Mutation testing only for PRs that touch
  `game/sim/` or `native/`, at most about 10 chosen mutants. A suite runs 3 times in a row only
  for thread or clock tests.
- Run as many lanes in parallel as the plan's dependencies allow, to keep the pace (Michael,
  2026-10-21; it replaces the one-lane limit of the same day). Each lane is one row, one small,
  well-defined task and one PR. Before PRs that wait for the same merge are merged, verify their
  combined tree once; a read-only interaction review (one agent) only when two of them touch the
  same system.

## Subagents and review
architect, gameplay-dev, ai-dev, touch-ux-dev, art-director, monetization-dev, qa-engineer,
release-engineer (`.claude/agents/`). Review with `/code-review` plus the `godot-code-review` skill
(and `rts-sim-conventions`' "Native kernels" checklist for any PR that touches `native/`).
