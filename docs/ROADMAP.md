# Roadmap

Each phase ends at a gate. The next phase starts only after Michael confirms the gate.
Tick a box in the PR that meets the criterion.

## Phase 0: Foundation (local, Michael with Claude Code CLI)
- [x] Public GitHub repository `rts-mobile` with this kit as the first commit
- [x] Godot 4.7.2 project: Compatibility renderer, base 1280x720, stretch `canvas_items` and `expand`, orientation `sensor_landscape`, touch emulated from mouse
- [x] Folder layout from CLAUDE.md, autoload stubs `DetRng` and `CommandQueue`, a main scene with a 32x32 test map and a camera
- [x] gdUnit4 pinned in `addons/` (version compatible with Godot 4.7), `scripts/run-tests.sh`, one passing test
- [x] `scripts/run-sim-smoke.sh` stub that accepts `--matches N` and `--report PATH` and exits 0 with "no sim yet"
- [x] `scripts/export-web.sh` and a "Web" export preset with thread support off
- [x] `ci.yml`: format check, lint, Godot import, tests, web export, Godot and templates cached, error scan of the logs
- [x] `preview.yml`: web build per PR to `pr-<n>/` on the `gh-pages` branch, link commented on the PR, removed when the PR closes
- [x] `assets/art/STYLE.md` from the svg-art-style skill, one sample unit (light tank hull, turret and team layer) and `scenes/dev/art_gallery.tscn` reachable from a dev menu in the preview
- [x] Gate: CI green on `main`, the preview link works on Michael's phone, `/verify` works in a cloud session

## Phase 1: Controls prototype (go/no-go)
- [x] One 48x48 test map with 30 player tanks and 10 static enemy targets
- [x] Camera: one-finger pan, pinch zoom with 3 levels, two-finger pan, edge clamping
- [x] Selection: tap, double-tap (all of type on screen), long-press box select, "All army" button, groups 1-3
- [x] Move orders are attack-moves with a move marker; units spread around the target point
- [x] Hit areas of at least 48 dp through `UiScale.dp()`; gesture tests in `tests/input/`
- [x] Android debug APK as a CI artifact for testing on a real device
- [x] Gate: on a 6-inch phone Michael selects a single tank with the first tap and moves groups without thinking about it, over 3 days of use

## Phase 2: Simulation core
- [x] ADR for the World data model, Command format and state hash
- [ ] 15 Hz fixed tick, FixedMath, DetRandom, Command queue, state hash and replay test
- [ ] Movement with flow fields and separation; combat with projectiles, armour classes and death
- [ ] Fog of war (visible and explored) and its rendering
- [ ] View interpolation at the display frame rate
- [ ] Performance test: 150 units for 900 ticks, ms per tick reported and the budget enforced
- [ ] Gate: 150 units at 60 fps on a mid-range Android phone, and the same seed gives the same match

## Phase 3: Base building and economy
- [ ] Buildings from the GDD with placement (ghost, valid and invalid tint, confirm and cancel)
- [ ] Build sidebar with tabs, queues, cost and progress; power bar and low-power effects
- [ ] Ore fields, harvester loop, refinery and credits
- [ ] Production of all MVP units with rally points
- [ ] Victory and defeat conditions and a result screen
- [ ] Gate: a full match can be played against a dummy opponent that only builds and defends

## Phase 4: Opponent AI and balance
- [ ] AI with build orders from data, scouting, army grouping, attack waves and retreat
- [ ] Easy, Normal and Hard as parameter sets
- [ ] `run-sim-smoke.sh` runs real headless AI-vs-AI matches with seeds and writes the report JSON
- [ ] `balance-nightly.yml` and an open issue labelled `balance`; first report in `docs/balance/`
- [ ] Gate: Normal wins 40-60% against the mirror AI over 100 matches, no match lasts over 15 minutes, every unit type is used

## Phase 5: Polish and meta
- [ ] Main menu, map select, settings (sound, haptics, privacy options placeholder)
- [ ] Commander rank, XP, unlocks and local save; save and resume when the app goes to the background
- [ ] Sound effects (CC0 or generated) and music volume
- [ ] Interactive tutorial of about 3 minutes that teaches how to play, including every entry marked
  Teach in `docs/HOW_TO_PLAY.md`; it starts on first launch and can be replayed from the menu
- [ ] "How to play" screen in the main menu and the pause menu that explains every entry in
  `docs/HOW_TO_PLAY.md` (controls, units, buildings, economy, how to win)
- [ ] Licences screen in the menu that shows `Engine.get_license_text()`,
  `Engine.get_copyright_info()` and the full texts from `Engine.get_license_info()` (Play builds
  need an in-game notice), plus the LLVM libc++ licence (`docs/licenses/llvm-libc++/`) on Android,
  whose template ships `libc++_shared.so` (ADR 0013 §11), and the game's own boot splash instead
  of Godot's default
- [ ] Second and third map
- [ ] Gate: a new player finishes the tutorial without help, every entry in `docs/HOW_TO_PLAY.md` is
  covered by the tutorial or the How to play screen, and the median match takes 8-10 minutes

## Phase 6: Monetization and Android delivery
- [ ] Poing AdMob plugin for Android, `AdService` with fake mode, caps from data
- [ ] UMP consent flow and privacy options
- [ ] Rewarded offers (double XP, starting credits), post-match interstitial, menu banner
- [ ] Remove ads purchase with restore
- [ ] `android-internal.yml`: signed AAB on every push to `main`, uploaded to Play internal testing
- [ ] Privacy policy text and Play Data safety answers drafted in `docs/store/`
- [ ] Gate: the build is in Play internal testing on Michael's phone, ads show test creatives, and app-ads.txt on appcode.dk covers the app

## Phase 7: Release
- [ ] `release.yml` (workflow_dispatch with a version input) tags `main` and calls the Android and iOS workflows as reusable workflows
- [ ] `ios-testflight.yml` with the iOS AdMob plugin and an App Store Connect API key
- [ ] Trademark search for the name (ADR 0006) and logo; English store texts and screenshots in `docs/store/`
- [ ] Gate: live on Google Play and an approved TestFlight build
