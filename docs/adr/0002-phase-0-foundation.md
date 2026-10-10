# ADR 0002: Phase 0 foundation (autoloads, test runner, CI and web preview, dev menu)

Status: accepted, 2026-10-10

## Context
Phase 0 of `docs/ROADMAP.md` sets up the project that every later phase builds on. Spikes on
Godot 4.7.2 (macOS arm64) found facts that shape the setup:
- Godot exits 0 after parse errors, autoload compile errors, a runner script that fails to load,
  and export configuration errors. Exit codes alone prove nothing.
- An autoload named `DetRng` makes any `class_name DetRng` a parse error ("hides an autoload
  singleton"), and the failure is silent (exit 0). The roadmap asks for autoload stubs `DetRng`
  and `CommandQueue`, while `rts-sim-conventions` says the RNG is owned by the match, never global,
  and `game/sim` may not reference Node.
- `godot --headless --import` does not report parse errors in scripts. Loading a script does:
  `load()` prints `SCRIPT ERROR: Parse Error` and `can_instantiate()` returns false.
- gdUnit4 v6.2.2 runs headless on 4.7.2 (its README states 4.5-4.7.1). It needs
  `--ignoreHeadlessMode`, and it exits 0 when no tests are found or the class cache is stale.
- In 4.7.2, `BaseButton` handles a native `InputEventScreenTouch` directly, so Buttons press
  exactly once whichever way the two pointer emulation settings are set (engine-side test; not
  yet checked in a real phone browser).
- The 4.7.2 export templates are a 1.28 GB `.tpz`. The web no-threads build needs only
  `version.txt` and the two `web_nothreads_*.zip` files (about 20 MB, fetchable by HTTP range).
  That build runs without COOP/COEP headers, so GitHub Pages can host it.

## Decision
1. **Autoloads are Node-side bridges, never sim state.** Autoload names stay `DetRng` and
   `CommandQueue` (roadmap). Their scripts live in `game/core/` (a new folder for Node-side
   services that connect input, AI and view to the sim; no game rules) as
   `det_rng_service.gd` and `command_queue_service.gd`, with **no `class_name`**.
   - `CommandQueue`: the inbox where input and AI controllers submit Commands. The match runner
     drains it into the sim's ordered per-tick command list. API defined by the Phase 2 ADR.
   - `DetRng`: a stateless factory that the match setup uses to create per-stream generators
     from (match seed, stream id). It holds no generator state. Phase 2 may remove it via ADR.
   - The pure-sim generator class is named **`DetRandom`** (`game/sim/DetRandom.gd`). No
     `class_name` may equal an autoload name. Code in `game/sim` never references an autoload;
     it receives `DetRandom` and command lists as arguments.
2. **File naming.** A script that declares a `class_name` is named like the class in
   PascalCase (as CLAUDE.md does with `AdService.gd`). All other scripts, scenes, resources
   and assets are snake_case. Paths in `preload()` must match case exactly, because Linux CI and
   Android are case-sensitive and macOS is not.
3. **Project settings** (`project.godot`): Compatibility renderer (also for mobile), base
   1280x720, stretch `canvas_items` + `expand`, `window/handheld/orientation=4`
   (sensor_landscape), `import_etc2_astc=true` (needed by the Web preset),
   `gdscript/warnings/untyped_declaration=2` (missing types are parse errors, outside `addons/`),
   and `[gdunit4] report/godot/push_error=true` (a `push_error` in tested code fails the test).
4. **Touch emulation follows `touch-ui-rules` unchanged:** `emulate_touch_from_mouse=true`,
   `emulate_mouse_from_touch=false`. Gesture code handles only `InputEventScreenTouch` and
   `InputEventScreenDrag` from any device (desktop clicks arrive as emulated touches) and
   ignores Mouse events. If dev-menu Buttons do not respond on the phone preview, set
   `emulate_mouse_from_touch=true` in a new ADR. Gesture code must then still ignore Mouse events.
5. **Test map is view-only.** `scenes/main.tscn` draws a 32x32 checkerboard of 64 px tiles in
   `_draw()` (`game/view/TestMapView.gd`, `class_name TestMapView`, size and tile size as
   exported properties set in the scene), with a Camera2D that pans on one-finger drag. Its
   `limit_*` equal the map rect, and after every drag its `position` is clamped to the map rect
   inset by half the visible size (`get_viewport_rect().size * 0.5 / zoom`), because in 4.7.2
   `limit_*` clamps only the rendered view, not `position`, which leaves a dead zone after
   overscrolling. The camera tracks touches by index: a press that did not start on a GUI control
   is a pan touch, its drags are handled before the GUI (so a pan that crosses the Dev button
   keeps panning), and it pans only while exactly one pan touch is active. No TileSet, no sim
   map, no `data/` resource. Phase 1 replaces the camera and adds pinch and two-finger pan.
   Phase 2 replaces the map with sim map data.
6. **Dev menu gating.** `game/ui/DevRoutes.gd` (`class_name DevRoutes`) holds the scene paths
   and `is_enabled() = OS.is_debug_build() or OS.has_feature("dev_menu")`. The Web preset sets
   `custom_features="dev_menu"`, and `scripts/export-web.sh` fails unless the PCK's
   `_custom_features` entry is `dev_menu`. Future store presets must not set it. The menu
   (`scenes/dev/dev_menu.tscn`) disables an entry whose scene does not exist.
   **Dev touch targets are at least 120x120 base px** until `UiScale.dp()` exists in Phase 1.
   This is a temporary, test-enforced exception to `touch-ui-rules` ("never hardcode pixel
   sizes"), because Phase 0 has no `UiScale`. Arithmetic: with `canvas_items` + `expand`, one
   base px is `min(w / 1280, h / 720)` CSS px, and CSS px are roughly dp in Android Chrome. The
   height is the limit on landscape phones: 360 CSS px minus about 56 px of browser toolbar
   gives 304 / 720 = 0.42 dp per base px; a 412 x 915 phone gives 412 / 720 = 0.57. So 120 base
   px is 51-69 dp, which meets the 48 dp rule in the worst case. The earlier 96x64 would have
   been 27-55 dp and failed it. Not yet measured on a phone; Phase 1's `UiScale` replaces this
   reasoned number with a measured one.
7. **gdUnit4 v6.2.2**, tag commit `0127a55f4543dfc24746f6e5c7ba6f94105d51f2`, vendored as the
   upstream AssetLib export (`git archive HEAD addons/gdUnit4`, which has no `test/` and no
   agent files), with its LICENSE and the `.uid`/`.import` files from the first import. Its
   editor plugin is not enabled. Tests use no `class_name`. `scripts/run-tests.sh` imports
   first, runs `GdUnitCmdTool.gd --ignoreHeadlessMode -c -rd reports/gdunit -rc 1`, and fails
   when `results.xml` is missing or reports 0 tests. gdUnit4's exit codes are passed through:
   100 for failures, 101 for orphans, 105 for script errors. Upgrade only through a new ADR.
8. **Silent-failure policy.** Every Godot run in scripts and CI is log-scanned with
   `SCRIPT ERROR|^ERROR:|Parse Error` and `scripts/verify-allowlist.txt`. Parse errors anywhere in
   `game/` and `scenes/` are caught by a test that loads every script. A script must also check
   the artifact it expects (results.xml, export files). CI fails when a run leaves the working
   tree changed (`git status --porcelain` not empty), which catches a forgotten `.uid` or
   `.import` file; `git diff --quiet` alone misses untracked files.
9. **CI and preview hosting.** GitHub Actions on `ubuntu-24.04`. Third-party actions are pinned
   by full SHA with a version comment. gdtoolkit 4.5.0 is installed through pipx.
   `scripts/ci/install-godot.sh` installs the Godot 4.7.2 Linux editor, checked against
   SHA-512, plus only the three web template files, fetched by HTTP range and checked against
   pinned SHA-256s. Both are cached with `actions/cache`, keyed on the Godot version and the
   installer's hash. Previews are no-threads release builds published into `pr-<n>/` on the
   `gh-pages` branch (legacy Pages build from branch root, `.nojekyll`). The push is never
   forced and is retried on races. The PR gets a sticky comment carrying the build SHA. The
   preview job fails when the build is not live within 8 minutes, so a green run means a live
   link. Pages (legacy, `gh-pages` `/`) is enabled once by the repo admin before the first
   preview run. The folder is removed when the PR closes. A PR closed with a merge conflict starts
   no `pull_request` run, and a failed cleanup is not repeated, so `preview-sweep.yml` runs daily
   (also by hand, with a dry-run option), uses only the default branch's code and removes the
   folder of every PR that is not open. A folder whose PR state cannot be read is kept. Fork PRs
   get no preview. The PWA is off. Preview URL: `https://wackeyssl.github.io/rts-mobile/pr-<n>/`.

## Consequences
- Phase 2 must name its sim classes around the autoloads (`DetRandom`, a Command type that is not
  `CommandQueue`), and its World/Command ADR defines the `CommandQueue` API.
- Several docs still call the sim RNG `DetRng` or omit `game/core/`: CLAUDE.md (Layout, rule 3),
  `.claude/skills/rts-sim-conventions/SKILL.md`, `.claude/agents/ai-dev.md` and ROADMAP Phase 2.
  Phase 0 does not edit them. The lead opens an issue listing the exact edits for Michael to
  approve, and the Phase 2 plan does not start until it is closed.
- A wrong autoload or class name, an untyped variable or a parse error turns tests red. It no
  longer passes silently.
- An expected `push_error` still prints `ERROR: <message>` even when a test asserts it with
  `assert_error(...).is_push_error(...)` (verified with `report/godot/push_error=true`), and the
  log scan turns that into a failed verify. A test that exercises an error path therefore needs
  a narrow allowlist entry matching that exact message, with a comment naming the test, or the
  error path stays untested. Phase 0 does not test `DevRoutes.open()` with a missing path and
  adds no allowlist entry. Other expected engine errors also need a narrow entry with evidence.
- Local exports need the three template files under the platform's `export_templates/4.7.2.stable/`.
  `scripts/export-web.sh` stops with exit 4 and names the missing path.
- Each open preview uses about 38 MB of the 1 GB Pages limit, so roughly 25 previews can be
  open at once. The daily sweep keeps closed PRs from using up this budget. The wasm file is
  identical between builds, which keeps git history small.
- The preview job runs PR code with a `contents: write` token. That is acceptable only because
  fork PRs are skipped and no secrets are present. Phase 6 revisits this when signing secrets
  arrive. The deploy would then run in a separate job that holds no build code.
- Running gdUnit4 on Godot 4.7.2 is outside its stated support range. A Godot bump re-runs the
  gdUnit4 spike before the pin changes.
