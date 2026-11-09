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
- [x] 15 Hz fixed tick, FixedMath, DetRandom, Command queue, state hash and replay test
- [x] Movement with flow fields and separation; combat with projectiles, armour classes and death
- [x] Fog of war (visible and explored) and its rendering
- [x] View interpolation at the display frame rate
- [x] Performance test: 150 units for 900 ticks, ms per tick reported and the budget enforced
- [x] Gate: 150 units at 60 fps on a mid-range Android phone, and the same seed gives the same match

## Phase 3: Base building and economy
- [x] Buildings from the GDD with placement (ghost, valid and invalid tint, confirm and cancel)
- [x] Build sidebar with tabs, queues, cost and progress; power bar and low-power effects
- [x] Portrait and landscape on the battle screen (ADR 0015): the HUD, selection and build menu keep their dp sizes in both
  orientations and follow ADR 0015 §5's layout as ADR 0025 amends it (the corner HUD and the build drawer; upright the
  same corners as sideways, Michael, 2026-11-05); a turn during a match keeps the camera centre and the world size per
  dp and queues no Command; UI and layout tests run at 1280x720, 2400x1080, 2048x1536, 720x1280, 1080x2400 and
  1536x2048; checked on Michael's phone in portrait: build an item with one hand, jump with the radar's full map,
  rotate during a placement (passed with the Phase 3 gate, Michael, 2026-11-05, issue #340)
- [x] The Android build follows the device's sensor (ADR 0015 §7: `window/handheld/orientation=6`, manifest
  `screenOrientation` 13), as the last row of `docs/plans/2026-10-19-portrait.md`
- [x] Ore fields, harvester loop, refinery and credits
- [x] Production of all MVP units with rally points
- [x] Victory and defeat conditions and a result screen
- [x] Two original factions with their own buildings, units and superweapon (ADR 0023): the Derrick League and the
  Lumen Accord, each with eight buildings, six unit types and one superweapon, both playable; the build menu shows only the
  player's own faction
- [x] Gate: a full match can be played against a dummy opponent that only builds and defends (passed, Michael,
  2026-11-05, issue #340)

## Phase 4: Opponent AI and balance
- [x] AI with build orders from data, scouting, army grouping, attack waves and retreat
- [x] Easy, Normal and Hard as parameter sets
- [x] `run-sim-smoke.sh` runs real headless AI-vs-AI matches with seeds and writes the report JSON
- [ ] `balance.yml` (runs after merges that change AI or balance data and on demand, not on a schedule;
  Michael, 2026-11-06) and an open issue labelled `balance`; first report in `docs/balance/`
- [ ] Gate: Normal wins 40-60% against the mirror AI over 100 matches, no match lasts over 15 minutes, every unit type is used

## Phase 4b: Air and ground support (before launch)
Michael, 2026-11-09: ADR 0036 (air, anti-air, satellite, research, transports, drone squads) and ADR
0037 (sale, mend, repair, medics, ground carrier, mines, hold position), accepted 2026-11-09. It
starts after the Phase 4 gate and ends before Phase 5. Plans:
`docs/plans/2026-11-09-air-and-tech.md` and `docs/plans/2026-11-09-ground-support.md`. The visual
polish rows (P200-P219, ADR 0034 and ADR 0035) run alongside it.
- [ ] Air layer and anti-air: aircraft fly straight over rock, water and buildings; only anti-air,
  rocket squads and fighters hit high air, and rifle squads and the Redoubt also hit the low drone
  squads (ADR 0036 §4-§5)
- [ ] Airfield and aircraft with repair: a fighter and a bomber per faction, the pad cap, ammo, the
  return and reload, repair on the pad for credits, and the Home button
- [ ] Satellite: the space centre's sweep lifts the fog until that space centre is destroyed, pauses
  while it is blacked out or its owner is on low power, and the enemy sees the warning and an
  indicator while it lasts
- [ ] Engineering centre research: heavier bombs and a tougher hull per faction, each once per
  match, from the Research tab
- [ ] Transports and drone squads: Board and Unload, passengers in the unit cap and lost with a
  downed transport; drone squads cross cliffs and water
- [ ] Sale and mend: two-tap Sell with the question card for the last producer; the paid Mend switch
  on a building
- [ ] Repair buildings and medics: the Weld Shed and the Drone Dock repair vehicles through the
  Repair button; Patchers and Menders heal squads
- [ ] Ground carrier: the Bunk Wagon and the Linecar with Board and Unload; the Bunk Wagon's squads
  get out at half health when it dies, the Linecar's are lost
- [ ] Mines with fair detection: the Shot Truck and the Seeder lay hidden mines; a player knows an
  enemy mine only through a minelayer's or scout tank's record; own mines never hurt own units
- [ ] Hold position: the Hold toggle keeps units from chasing (`STANCE` 9, TARGETING twin and kernel
  in lockstep)
- [ ] The AI uses every new unit and building through Commands only, with no target it has not seen,
  on Normal and Hard (satellite included); the fairness suite proves it headless
- [ ] The balance run passes the ADR 0031 gate thresholds with the new units: 26 unit types, each
  built in at least 50 of 100 matches
- [ ] Performance: 150 units at 60 fps on the reference phone with aircraft (`perf_air`) and with
  mines and repairers (`perf_bases`), draw calls within the forecast
- [ ] Gate: the ADR 0031 gate run on held-out seeds passes with all 26 unit types, and on Michael's
  phone, upright and sideways, he flies a raid, drops squads over a cliff, repairs, sells, lays and
  finds mines and holds position

## Phase 5: Polish and meta
- [ ] Main menu, map select, settings (sound, haptics, reduced effects (ADR 0027), privacy options placeholder)
- [ ] Commander rank, XP, unlocks and local save; save and resume when the app goes to the background
- [ ] Sound effects (CC0 or generated) and music volume
- [ ] Interactive tutorial of about 3 minutes that teaches how to play, including every entry marked
  Teach in `docs/HOW_TO_PLAY.md`; it starts on first launch and can be replayed from the menu
- [ ] "How to play" screen in the main menu and the pause menu that explains every entry in
  `docs/HOW_TO_PLAY.md` (controls, units, buildings, economy, how to win)
- [ ] Licences screen in the menu that shows `Engine.get_license_text()`,
  `Engine.get_copyright_info()` and the full texts from `Engine.get_license_info()` (Play builds
  need an in-game notice), plus the LLVM libc++ licence (`docs/licenses/llvm-libc++/`) on Android,
  because Godot's Android template ships `libc++_shared.so` (Phase 2 plan, P26l), and godot-cpp's
  MIT licence (`docs/licenses/godot-cpp-4.5-stable/`) on builds that contain the C++ sim kernels
  (ADR 0013 §11), and the OFL texts of the HUD's two font families, Big Shoulders and Chakra Petch
  (`assets/art/fonts/*/OFL.txt`, SIL Open Font License; ADR 0025 §13, P118b; until this screen exists
  they ship beside every build in `THIRD_PARTY_LICENSES.txt` and in the pack), and the game's own
  boot splash instead of Godot's default
- [ ] Every menu screen (main menu, map select, settings, tutorial, How to play, Licences) works in portrait and landscape
  (ADR 0015 §5) and is tested at the six sizes of ADR 0015 §6
- [ ] Second and third map
- [ ] Gate: a new player finishes the tutorial without help, every entry in `docs/HOW_TO_PLAY.md` is
  covered by the tutorial or the How to play screen, and the median match takes 8-10 minutes

## Phase 6: Monetization and Android delivery
- [ ] Poing AdMob plugin for Android, `AdService` with fake mode, caps from data
- [ ] UMP consent flow and privacy options
- [ ] Rewarded offers (double XP, starting credits), post-match interstitial, menu banner
- [ ] Remove ads purchase with restore
- [ ] The consent and ad screens (UMP form, rewarded offer, post-match interstitial, menu banner) work in portrait and
  landscape and after a turn, checked on Michael's phone (ADR 0015 §5)
- [ ] `android-internal.yml`: signed AAB on every push to `main`, uploaded to Play internal testing
- [ ] Privacy policy text and Play Data safety answers drafted in `docs/store/`
- [ ] Gate: the build is in Play internal testing on Michael's phone, ads show test creatives, and app-ads.txt on appcode.dk covers the app

## Phase 7: Release
- [ ] `release.yml` (workflow_dispatch with a version input) tags `main` and calls the Android and iOS workflows as reusable workflows
- [ ] `ios-testflight.yml` with the iOS AdMob plugin and an App Store Connect API key
- [ ] Trademark search for the name (ADR 0006) and logo; English store texts and screenshots in `docs/store/`
- [ ] Gate: live on Google Play and an approved TestFlight build
