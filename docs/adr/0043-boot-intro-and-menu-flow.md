# ADR 0043: Boot splash, the intro out of the app icon, and the menu flow

**In short, for Michael:** the game opens on its own icon instead of Godot's logo. While the game
loads, the icon's tank drives (its tracks roll, dirt and sparks fly), and when loading is done the
icon opens out into the main menu. The animation never makes you wait: it lasts as long as loading
does, at least 0.6 s so it does not flicker, and after 3 s the tank stops and a thin line shows the
loading. A tap skips the motion; with reduced effects it is a plain fade. The menus are a stack of
screens: Android's back button closes the top one, and on the main menu it asks whether to quit.
One service, `MenuFlow`, starts matches and brings you back, with Phase 6's ad steps in between.

Status: **accepted, 2026-11-15 (Michael: "Ja til anbefaling", yes to every recommendation of
the plan's questions).** Written by the architect on branch
`claude/p500-phase5-plan` (base `main` at a2204d2f) with the plan
`docs/plans/2026-11-15-phase-5.md` (rows P519-P536). Michael's intro direction of 2026-11-15
replaces the earlier "3-5 s animated title". Questions 6, 10, 14 and 16 of the plan are this ADR's.
The Phase 6 parts (consent at boot, the banner band, the offers, the post-match interstitial) are
agreed with Phase 6 (2026-11-15; the plan's "Interfaces with Phase 6").

Amends by dated notes (written in P500b): ADR 0019 §7 (the preview opens on the boot scene, not
the controls test, from P533), ADR 0025 §11 (Exit to menu goes to the main menu) and §12 (the start
page as §5 builds it).

## Michael's answers (2026-11-15)
- **Question 6, splash:** the app icon alone on its background colour, no AppCode ApS mark;
  `min_ms` 600, `max_ms` 3,000; a tap skips the motion (§1, §2).
  Note (Michael, 2026-11-15, later the same day): the splash shows AppCode ApS's brand, which
  replaces "no AppCode ApS mark". Michael supplied the brand SVGs (wordmark and mark, white); they
  go in `assets/art/brand/` (plan row P520a). They carry a C2PA manifest (made with Claude at
  Michael's request); Michael approved them unmodified as the company's trademark, © AppCode ApS,
  all rights reserved (ADR 0046 item 5: reserved assets, kept unmodified; the CLAUDE.md exception
  sentence comes with the main lead's P26ca). Layout: the wordmark small under the app icon (about
  30 % of the icon's width); where that is too tall, the mark to the left of the wordmark at the
  same height. It adds no time to the intro (§1, §2).
- **Question 10, the match-start wait:** a still "deploying" card before the bake (P536, in scope).
- **Question 11, left-handed mode:** after launch (not in Settings, §5).
- **Question 12, translations:** the new screens use `tr()` keys with an English table; the HUD
  is converted in a later row.
- **Question 14, back on the main menu:** "Quit Treadline?" (§4).
- **Question 16, the tagline:** "Oil and gas against wind and sun. Choose your side." (§5).

## Context
- `project.godot`: `run/main_scene` is `scenes/main.tscn` (a match on the test map); no
  `boot_splash` key, so Godot's default splash and the web loading image show the Godot logo
  (`assets/CREDITS.md`'s first row); `config/icon` is `assets/art/svg/icon/app_icon.svg`, with its
  adaptive layers `icon_background.svg` and `icon_foreground.svg` (one tank rolling out at the
  viewer, clods and sparks from its tracks, a radar ring).
- `tools/artgen/ArtIcon.gd` draws the item cards; the icon itself was emitted by a script kept
  outside the repository, and the committed SVG is its source (CREDITS).
- The atlas bake (1.0-1.4 s on the Pixel 9a, `atlas_bake_ms`) runs per match on the main thread
  (`WorldSort.bake`, keyed by the scenario's types and triads); the defs load with the scenario.
  At boot neither is needed: the boot loads the menu scene, the theme, the fonts, the menu music and
  the save.
- The HUD's look is `game/ui/theme.tres` only (P58; `tests/project/test_ui_theme_scan.gd` bans
  colour and modulate literals in `game/ui`). ADR 0015 §5: every menu scene works in both
  orientations at §6's six sizes; a single column on the short side is the default. ADR 0025 §12
  specifies the start page.
- Phase 4b's open UI rows (P248, P281, P282, P293, P294, P299, the polish rows) work in
  `CommandBar`, `BuildSidebar`, `game/view` layers, `theme.tres` and `main.tscn`.
- Godot's Android build gets an Android 12+ system splash (the launcher icon) before the engine's
  boot splash (unverified on 4.7.2's template; checked on the phone in P533).

## Decision
### 1. The boot splash
`application/boot_splash/*` (image, background colour, show image, stretch, minimum display time;
the exact 4.7.2 key names are checked in P533) shows a PNG rendered from `app_icon.svg`, centred on
the icon's own background colour, with no Godot logo. The same image is the web build's loading
image. Art-director renders it in P520 (own work, a CREDITS row); the Godot logo row of CREDITS
goes once nothing shows it. No AppCode ApS mark (Michael, question 6).

Note (Michael, 2026-11-15; replaces "No AppCode ApS mark" above): the splash PNG also carries
AppCode ApS's white wordmark from `assets/art/brand/` (P520a), small under the icon at about 30 %
of the icon's width; where that is too tall, the mark to the left of the wordmark at the same
height. One PNG serves every size, so P520 picks the lockup that fits the shortest of ADR 0015
§6's six sizes at the splash's scale, and the intro's still frame (§2) uses the same lockup, so
the hand-over stays invisible. The brand stays still for the whole intro and leaves with the
open-out; it adds no time. Its CREDITS rows, and the splash PNG's, say "All rights reserved
(AppCode ApS)" (ADR 0046 item 7).

### 2. The intro: the tank drives while loading
- `scenes/boot.tscn` (the main scene from P533) with `IntroPlayer` (`game/view/intro/`, outside the
  theme scan because it animates modulate; its numbers in `data/intro_settings.tres`). Its first
  frame shows the splash's picture at the splash's place (a layout test headless; the look on the
  phone), so the hand-over is invisible.
- **Layers** (P520): the foreground split into hull, two tracks with cleats, turret and gun, clods,
  sparks and radar ring, compositing to today's icon pixel for pixel; the background stays one
  layer. **Motion:** cleats scroll, the hull rocks on its suspension, clods and sparks fly in short
  loops, the ring sweeps.
- **Loading during it:** `ResourceLoader.load_threaded_request` for `scenes/menu/menu.tscn` and its
  resources, `SaveService` load (ADR 0042), `AudioService.apply_prefs`, and
  `await AdService.ensure_consent()` (always finishes, agreed with Phase 6; the UMP form, when it
  shows, covers the intro, which holds still under it). No ad is requested before it returns.
- **Timing:** the open-out starts when every load and the consent are done **and** at least
  `min_ms` (600) has passed since the first frame. After `max_ms` (3,000) of motion the tank settles
  into a still idle and a thin progress line shows until loading ends; the intro never ends before
  loading does and never adds a wait beyond `min_ms`.
- **Open-out** (`open_ms` 400): the icon's rounded square grows to fill the screen and becomes the
  main menu's backdrop; the tank rolls down and out; the menu fades in on top.
- **Skip:** a tap ends the motion at once: the open-out if loading is done, else the still frame and
  the line. **Reduced effects** (the saved switch): a plain `fade_ms` (250) cross-fade from the
  still icon to the menu.
- Both orientations at the six sizes (the icon centred on the short side). A `boot_ms` console line
  (first frame to menu ready) for the phone and the web console; no timing run in a session.
- The match-start bake is a separate wait: a still "deploying" card shows before it (P536;
  Michael, question 10).

### 3. Screens and the stack
- `scenes/menu/menu.tscn`: a root Control with a `HudTheme` node and the theme, the backdrop, and
  `MenuStack` (`game/ui/menu/`). Screens are code-built Controls (as `PauseMenu` is), each a
  `MenuScreen`: one column on the short side, a scroll when too short, the safe area, buttons of at
  least 48 dp, and the foot `AdBannerSlot` (§8).
- `push(screen)`, `pop()`, `replace(screen)`; a slide of `slide_ms` (200), a cut with reduced
  effects. A turn keeps the stack, each screen's scroll and its focus.
- Screens: **MainMenu**, **MapSelect**, **Settings**, **HowToPlay**, **Licences**, **Tutorial**
  (ADR 0044), **Restore** (ADR 0042 §6). The dev menu stays as it is, reached from Settings ->
  Developer and from the pause menu, in debug and `dev_menu` builds only.

### 4. Back on Android
`application/config/quit_on_go_back` = false; `NOTIFICATION_WM_GO_BACK_REQUEST`:
| Where | Back does |
| --- | --- |
| a question card is open | closes it (its cancel) |
| a menu screen above the root | pops it |
| the main menu | asks "Quit Treadline?" (question 14); yes quits |
| the intro | skips the motion (as a tap) |
| a match | opens the pause menu; in the pause menu it resumes |
| the tutorial | opens the pause menu with "Leave tutorial" |
The web has no back event; the browser's back leaves the page.

### 5. The main menu (ADR 0025 §12)
TREADLINE; the two sides with their emblems, each name in its accent; the tagline (question 16);
**Continue** (only while a valid resume file exists, ADR 0042 §6); **Skirmish** (-> MapSelect);
**Tutorial**; **How to play**; **Settings**; the rank badge and XP bar (ADR 0045); the version line
"v<version> · © AppCode ApS"; the banner band with 48 dp of air (ADR 0025 §12; 16 dp is the floor
elsewhere). Campaign and Multiplayer are not shown.
- **MapSelect:** map cards from `data/maps/catalog.tres` (name, picture, size, a lock and its rank,
  ADR 0045), side (Derrick League or Lumen Accord), level (Easy, Normal, Hard; locked per ADR 0045),
  Start; the map-select `OfferSlot` (§8).
- **Settings:** Sound, Music (steps 0-10), Vibration, Reduced effects (applied at the next match
  start: nobody writes `LifeSettings.reduced` during a match, ADR 0027 §8), Privacy ("Privacy
  options" when `AdService.is_privacy_options_required()`, tap awaits `show_privacy_options()`),
  the Remove ads / Restore slot, Replay tutorial, How to play, Licences, Developer (debug builds).

### 6. MenuFlow
Autoload **`MenuFlow`** (`game/ui/menu/menu_flow_service.gd`): the one owner of scene changes.
- `start_match(setup: MatchSetup)`: picks the seed (from `Crypto.generate_random_bytes`, outside
  the sim; the tutorial's is fixed in data), writes `AdService.take_start_credits_bonus()` into
  `setup.bonus_starting_credits`, builds the main scene with `setup.apply(runner)` and changes to
  it; keeps a reference to it for ADR 0042 §5-§6.
- The match end: builds the `MatchSummary`, `Progression.award_match(summary)`; the result screen
  shows the award (P532). Leaving it: `AdService.note_match_completed(ticks / Sim.TICK_RATE)` for
  an ended match only, then `await AdService.maybe_show_interstitial(&"post_match")`, then the main
  menu (or the next lesson). Exit to menu from the pause menu: straight to the menu, no XP, no
  `note_match_completed`.
- **Tutorial lessons are not ad matches.** A lesson (a setup with a lesson id, ADR 0044 §1) never
  calls `AdService.take_start_credits_bonus()` (the grant stays for the next skirmish), never calls
  `note_match_completed` and never awaits `maybe_show_interstitial`; its end goes straight to the
  next lesson or the menu. So lessons do not count toward Phase 6's new-player ad grace or its caps.
  Its XP is the one-time lesson award (ADR 0045 §2).
- `continue_match()`: the restore of ADR 0042 §6. `return_to_menu(screen)`.

### 7. The Licences screen
Exactly ROADMAP's list, plus what Phase 6 and CC-BY add: `Engine.get_license_text()`,
`Engine.get_copyright_info()`, the full texts from `Engine.get_license_info()`; the LLVM libc++
licence on Android (`docs/licenses/llvm-libc++/`); godot-cpp's MIT licence on every build that
contains the C++ kernels (`docs/licenses/godot-cpp-4.5-stable/`; ADR 0013 §11), whether or not the
library loads: a build-time fact, the export feature tag `sim_kernels` that exactly the presets
packing `native/` set (both Android presets today; Web excludes `native/*`), and the editor;
`test_export_presets.gd` pins "tag set = `native/` packed"; the OFL texts of Big Shoulders and Chakra
Petch (`assets/art/fonts/*/OFL.txt`); the Poing AdMob and GodotGooglePlayBilling plugin licences
(texts from Phase 6's P410/P411); the credit lines of every CC-BY asset (question 9). Texts outside
`assets/` are copied into `assets/licenses/` by P529 so the pack holds them (a test keeps the copies
equal to `docs/licenses/`).
Note (2026-11-15): ADR 0046 adds `assets/LICENSE.md` (the game's own art and audio, all rights
reserved) to ROADMAP's list, so the screen shows it too.

### 8. Phase 6's slots (agreed 2026-11-15)
- `AdBannerSlot`: the one bottom container at the foot of MainMenu, MapSelect and Settings; its
  height is `AdService.banner_height_dp()` plus the gap, re-laid out on `banner_changed`, 0 when
  there is no banner. It hosts Phase 6's `AdBannerBand` (P430) as its only child, so no screen
  builds a second band; the band shows on enter_tree and hides on exit_tree, and Phase 5 calls
  nothing on it. The menu rows land with the slot empty and 0 tall; P430 fills it later.
- `OfferSlot`: a plain Container on the result screen and on MapSelect that takes the widget's size
  and is empty when the widget hides. The widgets are Phase 6's (P432, P433).
  Note (2026-11-15, P500c; from Phase 6's P431, the `RewardedOffer` widget): "a plain Container"
  is replaced. The slot is a `VBoxContainer` or a `CenterContainer` (its size comes from the
  child; 0 when the child hides), never a plain `Container`. The widget's `on_reward` binds to an
  autoload or service (e.g. `Progression.apply_bonus.bind(award_id, mult)`), never to the screen
  node, so a grant survives the screen being freed while the ad shows. The host has
  `game/ui/theme.tres` in scope (the CapsButton variation). One offer per screen, claimed through
  `slot.owner`.
- Note (2026-11-15, P500c; from Phase 6's P430, the `AdBannerBand`): the `AdBannerSlot` sits at the
  very bottom of the safe area with no control below it, because the real AdMob banner is drawn at
  the screen's bottom; the menu tests call P430's shared `assert_lines_up`
  (`tests/ui/support/ad_band_asserts.gd`; `is_at_safe_bottom()` until 2026-11-16).
- Note (2026-11-16, P500d; superseded by Phase 6): the first item's sizing is replaced.
  `AdBannerBand` owns its whole height (the gap from Phase 6's ads data, the caption, the banner);
  `AdBannerSlot` has no gap of its own, is as tall as the band's combined minimum size (0 when
  empty), puts the band's bottom on the safe bottom and re-lays out on the band's
  `minimum_size_changed`. `MenuStack` takes covered screens out of the tree, so a covered band
  hides.
- The pause menu's foot banner (old P127) is Phase 6's P435; P531 keeps the foot free.

### 9. Isolation from Phase 4b
Waves 1-7 of the plan add only new files (`game/ui/menu/`, `game/view/intro/`, `scenes/boot.tscn`,
`scenes/menu/`) and read `ModalFrame`, `SafeAreaMargin`, `ConfirmDialog`, `HudTheme`, `UiScale` and
the pause menu's theme looks without editing them. The touches of shared files wait for the 4b gate:
`PauseMenu.gd` (P531), `ResultScreen.gd` (P532), `project.godot`'s main scene and splash (P533; it
also changes what Michael's preview opens on, so not during the 4b phone checks), `main.tscn`
(P535). Menu-only theme variations are one art-director row (P519) in `theme.tres` when the file is
free.

## Consequences
- Godot's logo leaves the boot and the web loading screen; CREDITS loses that row when nothing shows
  it.
- The preview opens on the intro and the main menu from P533; the dev menu stays one tap deeper.
- Every scene change goes through `MenuFlow`, which is where Phase 6 hooks its post-match steps.
- The intro cannot mask the match-start bake (a per-match cost); P536's still card covers that wait.

## Alternatives considered
- **A fixed 3-5 s animated title** (the first direction). Replaced by Michael on 2026-11-15: never
  add to loading.
- **Bake the atlas at boot for the last setup.** Rejected: the bake is per match, blocks the main
  thread (the intro could not animate), and the next setup may differ.
- **One scene per menu screen with `change_scene`.** Rejected: loses the stack, the back order and
  the transitions; the battle stays its own scene.
- **A separate menu Theme.** Rejected: P58's rule that the look lives in `theme.tres` only.
