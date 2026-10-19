# ADR 0015: Portrait and landscape (base size per orientation, layout, camera on rotation)

Status: accepted, 2026-10-19 (Michael's decision of 2026-10-19 and the lead's frame decisions of
the same day, both below as given). Docs PR P26v. The rows that carry it out are in
`docs/plans/2026-10-19-portrait.md` (P59-P64). Until the last of them, P64, merges, the build
stays landscape-locked (§7).

## Context
Michael, 2026-10-19, verbatim: **"Tilføj til tema at spillet også skal kunne spilles vertikale og
ikke kun i landscape"**: the game shall be playable in portrait as well as landscape. That changes
two hard rules: `CLAUDE.md`'s Stack line "2D top-down, landscape only" (which changes only through
a new ADR) and its Mobile UX rule "Landscape only".

The lead's frame decisions (2026-10-19), recorded as given:
1. Both orientations for the whole game: battle screen, HUD, build sidebar, selection, menus, the
   ad and consent screens. The device's sensor picks the orientation and the player may rotate
   during a match. Orientation is view-only: `game/sim`, Commands, replays and the state hash do
   not change.
2. Touch targets >= 48 dp, safe areas and the gesture set of `CLAUDE.md`'s Mobile UX hold in both
   orientations.
3. The UI must not shrink in portrait: the same phone gives the same dp size in both
   orientations. This ADR picks the mechanism after reading ADR 0004 and the current code.
4. Camera on rotation: the world point at the screen centre stays at the centre and the zoom
   keeps the same world size per dp; this ADR states it exactly, with the camera limits.
5. Portrait layout per screen: this ADR states where each HUD element goes in portrait and names
   the risks (a narrower map view, the HUD's larger share of the screen) with how the layout
   limits them.
6. Sequencing: the build stays landscape-locked until the rows that make scale, HUD, menus and
   camera work in portrait are merged; flipping the orientation (with the export and manifest
   checks and `tests/project/test_project_settings.gd`) is the last row, owned by
   release-engineer. From this ADR's merge on, new UI code must not assume width > height.
7. Tests: UI and layout tests run at landscape and portrait sizes; this ADR names the sizes (at
   least 2400x1080 and 1080x2400 next to the existing 1280x720 and 2048x1536).

### What the code does today (`main` at 32bfb89)
- `project.godot`: `window/size/viewport_width=1280`, `window/size/viewport_height=720`,
  `window/stretch/mode="canvas_items"`, `window/stretch/aspect="expand"`,
  `window/handheld/orientation=4`. `tests/project/test_project_settings.gd` (`test_display`) pins
  all five; its comment reads `# 4 = sensor landscape`.
- Android: `scripts/export-android.sh` checks the APK manifest with
  `grep -Eq 'screenOrientation\(0x0101001e\)=11$'` ("the manifest screenOrientation is not 11
  (userLandscape)"), and the offline stub in `scripts/ci/test-export-notices.sh` prints that line.
- Web: `export_presets.cfg` has `progressive_web_app/enabled=false` and
  `progressive_web_app/orientation=0`, and `html/custom_html_shell=""`. The 4.7.2 editor binary
  holds the hint string `Any,Landscape,Portrait` next to the `progressive_web_app/*` option
  names, so 0 is `Any`, and the PWA is off anyway. Nothing in the web export locks the
  orientation, so the phone preview already turns with the phone today and shows the landscape
  layout in a portrait window. (From the editor binary's strings and the preset; not checked on
  the phone by this ADR.)
- `UiScale` (`game/ui/UiScale.gd`, ADR 0004 §3) returns base px:
  `base_px_per_dp_for(m)` = `window_px_per_dp(m) / m.stretch_scale`, with `stretch_scale` read
  from `tree.root.get_stretch_transform().get_scale().x`. So every size given in dp is
  density-correct at any stretch, portrait included.
- Users of dp sizes recompute on the root viewport's `size_changed`: `DpMinSize._apply`,
  `SafeAreaMargin.apply`, `TouchInput.configure` (which calls
  `_recognizer.configure(settings, UiScale.base_px_per_dp())`), `ArmyBar._apply_dp`,
  `SelectionPanel._apply_dp`, `UnitLayer._resize_rings`, `touch_probe.gd`'s `_refresh`, and
  `RtsCamera._clamp_to_map`. P58 (central UI Theme, in flight) adds one dp step for the theme on
  the same signal.
- `SafeAreaMargin.apply()` gives both sides of an axis the larger inset, because "turning a
  sensor-landscape phone 180 degrees moves the cutout to the other side without a resize".
- `SelectionPanel._fit_band()` reserves the build sidebar zone on the right:
  `maxf(width * SIDEBAR_SHARE, UiScale.dp(SIDEBAR_MIN_DP))` with `SIDEBAR_SHARE` 0.2 and
  `SIDEBAR_MIN_DP` 200, where `width` is `get_viewport().get_visible_rect().size.x` (ADR 0004,
  Amendment P21).
- `scenes/main.tscn`: `Hud` (CanvasLayer) holds `BoxOverlay` and `SafeArea`
  (`SafeAreaMargin`); in `SafeArea` the `DevButton` sits top-left (size flags 0, 0;
  `theme_override_font_sizes/font_size = 40`, base px), the `ArmyBar` bottom-left (size flags
  0, 8; "All army" 96x56 dp, groups 1-3 56x56 dp, 8 dp gaps: 288 dp wide), and `SelectionBand`
  with `SelectionPanel` at the bottom centre.
- `RtsCamera` (`game/view/RtsCamera.gd`, ADR 0004 §6): `position` is the world point at the
  viewport centre (Camera2D's default `ANCHOR_MODE_DRAG_CENTER`), the zoom levels come from
  `InputSettings.zoom_levels` (0.75, 1.0, 1.5 in `data/input_settings.tres`), `limit_*` is the
  map rect, and on `size_changed` `_clamp_to_map()` clamps `position` to the map rect inset by
  half the visible world size (the map centre on an axis where the map is smaller than the view).
- Sizes in base px, not dp: the Dev button's font (40), the dev menu
  (`scenes/dev/dev_menu.tscn`: 360x120 buttons, fonts 48 and 40), `art_gallery.gd`'s
  `PX_PER_DP` 1.75 ("on the 6-inch phone profile"), and the camera: one base px is one world px
  at zoom 1.0.
- Test sizes: `tests/scenes/test_main_scene.gd` `TARGET_SIZES` (1280x720, 2400x1080,
  2048x1536), `tests/view/test_rts_camera.gd` (2400x1080, 2048x1536), and the profiles of
  `tests/support/ui_profiles.gd` (`android_6in` 2400x1080, `web_phone` 2400x932,
  `web_phone_small` 2400x912, `web_tablet` 2048x1536, `desktop` 1280x720), all landscape.

### Facts checked headless on Godot 4.7.2 (scratch project, 2026-10-19)
- With base 1280x720, `canvas_items` and `expand`, the stretch is `min(w / 1280, h / 720)`: at
  1080x2400 it is 0.84375 and the visible rect is 1280x2844 base px; at 1536x2048 1.2
  (1280x1706); at 720x1280 0.5625 (1280x2275). The same phone gives 1.5 in landscape
  (2400x1080, 1600x720 base px).
- So at 1080x2400 everything sized in base px is 0.84375 / 1.5 = 56 % of its landscape size on
  the same phone: the Dev button and dev menu, and the map (one dp shows 1.75 world px in
  landscape and 3.11 in portrait at zoom 1.0). dp sizes keep their physical size, because
  `UiScale` divides by the stretch, but they take 149 base px for `dp(48)` instead of 84.
- `Window.content_scale_size` (Vector2i) exists and can be set at run time. With it set to
  720x1280, the stretch is `min(w / 720, h / 1280)`: 1.5 at 1080x2400 (visible 720x1600), 1.6 at
  1536x2048 (960x1280), 1.0 at 720x1280, 1.50139 at 1081x2402. Set back to 1280x720 in a
  landscape window it gives the old values (1.5 at 2400x1080, 1.6 at 2048x1536, 1.29450 at
  2400x932).
- Setting `content_scale_size` emits the root viewport's `size_changed` once, synchronously.
  From inside a `size_changed` handler that emission is nested: every handler runs in it with the
  new stretch, and then the outer emission goes on with the handlers after the one that set it.
  So on a flip every handler runs twice, both times with the new values when the setter is
  connected first; a handler connected before it runs once with the old values first. The final
  state is right if every handler recomputes from the current metrics (idempotent). The handlers
  listed above read the current metrics on each call; P59 proves the double run for them (§2).
- `DisplayServer.SCREEN_SENSOR` is 6 and `SCREEN_SENSOR_LANDSCAPE` 4. In the 4.7.2 source
  (`platform/android/export/gradle_export_util.cpp`, `_get_android_orientation_value`) 4 maps to
  manifest value 11 and 6 (`SCREEN_SENSOR`) to 13 (`fullUser`); the app template's
  `AndroidManifest.xml` declares `configChanges` with `orientation` and `screenSize`, so a
  rotation resizes the window and does not restart the activity. (Source read, not run on a
  device.)

## Decision

### 1. Scope
Both orientations for the whole game, as frame decision 1 says: the battle screen with its HUD,
the build sidebar (Phase 3), selection, every menu (Phase 5) and the ad and consent screens
(Phase 6). The device's sensor picks the orientation; with P64's setting 6 Godot writes
`fullUser` (13), so a phone with auto-rotate off keeps its current orientation, as the Android
setting asks. The player may rotate during a match.

Orientation is view-only. `game/sim`, `native/sim_kernels/`, Commands, replays and the state hash
do not change and never read it. A rotation issues no Command: a gesture in flight is cancelled
(§3), never turned into a tap or an order.

### 2. Mechanism: the base size turns with the window
- A portrait window is one with height > width; any other window (a square one too) is
  landscape. One pure function holds that rule (`UiScale.is_portrait_size(size: Vector2i)` or a
  name P59 picks and shows), and no other code compares width and height to find the
  orientation.
- The landscape base size stays `project.godot`'s 1280x720 (`viewport_width`,
  `viewport_height`; unchanged, so `test_display` stays as it is). The portrait base size is the
  same size transposed, 720x1280, computed from the project settings, not a second literal.
- A new autoload (P59; working name `UiOrientation`, script
  `res://game/ui/ui_orientation_service.gd`, no `class_name`, as `tests/project/test_autoloads.gd`
  requires of autoload scripts) sets `get_tree().root.content_scale_size` to the base size of the
  window's orientation in `_ready()` and in its handler of the root viewport's `size_changed`,
  and only when the value differs. It holds no game rule and no state beyond that.
- Stretch mode `canvas_items` and aspect `expand` stay. With the swap the stretch is
  `min(w / 1280, h / 720)` in landscape and `min(w / 720, h / 1280)` in portrait, which is the
  same number for the same device in both orientations (both are `min(long side / 1280, short
  side / 720)`). So:
  - every landscape value of today is unchanged (all profiles, `TARGET_SIZES`, ADR 0004's
    examples);
  - on one phone a dp size, a base-px size and the world px per dp are the same in both
    orientations; only the visible base rect turns (1600x720 to 720x1600 on the 6-inch phone);
  - the dp formula of ADR 0004 §3, `UiMetrics` and `UiScale`'s existing functions do not
    change (P59 only adds the orientation function);
  - where the window itself changes in the turn (a phone browser whose toolbar takes height in
    landscape: 2400x932 is 1.29450, a portrait window of 1080x2100 is 1.5), the stretch differs
    between the orientations as it does today on any resize; dp sizes stay right through
    `UiScale`, and §4 keeps the world size per dp.
- Every handler of `size_changed` must recompute from the current metrics and be idempotent,
  because a flip runs it twice (Context). P59 adds a case that proves it for the existing ones.
- The autoload covers every scene (the battle screen, dev scenes, the future menus and the ad and
  consent screens) without a per-scene step.

### 3. Touch targets, safe areas and gestures in both orientations
- The 48 dp rule, the gesture map and the thresholds of ADR 0004 §2 (`data/input_settings.tres`)
  hold unchanged in both orientations; no setting has a portrait value.
- `SafeAreaMargin` keeps its rule (both sides of an axis get the larger inset). In portrait the
  cutout is at the top and the gesture bar at the bottom, so top and bottom get the larger of the
  two; a 180 degree turn (reverse portrait, where Android allows it) moves the cutout without a
  resize, the same case as reverse landscape. Its doc comment drops "sensor-landscape" (P59).
- An orientation change cancels every gesture in flight (`TouchInput` calls
  `_recognizer.cancel_all()`, as on focus loss), because the finger positions belong to the old
  layout. It emits `BOX_CANCEL` or `CAMERA_END` as `cancel_all()` does today, and no `TAP`.
- `TouchInput.configure()` keeps running on every `size_changed` (ADR 0004 §3).

### 4. Camera on rotation
On a `size_changed` where the window's orientation (§2) differs from the one `RtsCamera` saw last:
1. A zoom snap in flight is stopped (`_stop_snap()`); the zoom stays where it is.
2. `position`, the world point at the viewport centre, is kept.
3. The zoom keeps the world size per dp: `zoom_new = zoom_old * bppd_new / bppd_old`, where
   `bppd` is `UiScale.base_px_per_dp()` after and before the turn (the camera keeps the last
   value it saw), clamped to the pinch bounds of `_zoom_about`
   (`zoom_levels[0] * (1 - pinch_overshoot)` to the last level `* (1 + pinch_overshoot)`). It
   does not snap to a level; the next `CAMERA_END` or wheel step snaps as today. Where the
   window after the turn is the exact transpose of the one before, §2 makes the factor exactly
   1.0, so the zoom does not change; where system bars or a browser toolbar take a different
   share of the screen in each orientation, the factor corrects for it.
4. Then `_clamp_to_map()` runs with the new visible size: on each axis `position` is clamped to
   the map rect inset by half the visible world size, or set to the map centre where the map is
   smaller than the view on that axis. So the centre point stays at the centre except where the
   new view would cross a map edge.
5. `limit_*` stays the map rect from `set_map_rect()`; a rotation does not touch it.
6. There is no memory: turning back starts from the clamped position.

Other resizes (a browser toolbar in the same orientation, a desktop window drag) keep today's
behaviour: the zoom stays and the clamp runs. The autoload of §2 connects before any scene node
(autoloads enter the tree first), so in the double emission of a flip the camera sees the new
stretch both times: it rescales on the first run, where the orientation differs from the one it
saw last, and only clamps on the second.

### 5. Layout
General rules (both orientations, from this ADR's merge on):
- No UI code assumes width > height. A layout decision that depends on the shape goes through
  the one orientation function of §2; sizes come from the safe rect and dp, never from 1280 or
  720.
- One HUD scene for both orientations; the layout code places its parts per orientation. No
  second scene per orientation.
- The landscape layout stays as `touch-ui-rules` gives it today.
- The build sidebar zone is at the end of the long axis: the right edge in landscape (20 % of the
  width and at least 200 dp, today's rule), the bottom edge in portrait (20 % of the height and at
  least 200 dp, the full safe width). HUD elements stay out of the zone, as ADR 0004's Amendment
  (P21) says for landscape; while the sidebar does not exist (until Phase 3) the zone is reserved
  but empty.
- In portrait, the controls a player taps often (army and groups, build, the minimap) sit in the
  bottom part of the screen; the top line holds only read-only information and the rare top-left
  controls (the Dev button now, pause and menu later).

Portrait layout of the battle screen (the 6-inch phone: 1080x2400 at 420 dpi, 720x1600 base px,
411x914 dp):

| Element | Landscape (today) | Portrait |
| --- | --- | --- |
| Build sidebar (Phase 3) | Right edge, 20 % of the width, at least 200 dp; minimap at the top, then credits and the power bar, then the tabs and the build icons (>= 64 dp) | Bottom band, the full safe width, 20 % of the height and at least 200 dp; the minimap at its right end (square, the band's height less the margins), and left of it the credits and power line, the tabs and one row of build icons (>= 64 dp) that scrolls sideways |
| Minimap (Phase 3) | Top of the sidebar | Right end of the bottom band |
| ArmyBar | Bottom-left | Bottom-left, directly above the build band (on the safe bottom edge while the band does not exist); same sizes (288x56 dp) |
| SelectionPanel | Bottom centre, in the band between the ArmyBar and the sidebar zone | Top edge, right of the top-left controls, one line: the type rows side by side, the total last; the names show only when the whole line fits with them, else every row shows icon and count only; one row high (48 dp plus its padding) |
| Dev button | Top-left | Top-left |
| Pause and menu (later) | Top-left | Top-left |
| Under-attack indicators (later) | Screen edges and a minimap ping | The same |

Risks and how the layout limits them:
- **A narrower map view.** In portrait the 6-inch phone shows 720 world px across at zoom 1.0
  (11.25 tiles) instead of 1600 (25 tiles), and 960 px (15 tiles) at the widest level 0.75. The
  zoom levels stay the same in both orientations (one list in `data/input_settings.tres`); the
  minimap's tap-to-jump (Phase 3) and the under-attack indicators (when they come) are the remedy
  for what lies beside the view. Double-tap's "all of that type on screen" picks from the narrower view, as the
  rule says.
- **The HUD's larger share of the screen height.** On the 6-inch phone the bottom stack (band
  200 dp + 8 dp + ArmyBar 56 dp = 264 dp) is 29 % of the height, the top line with a selection
  64 dp more (7 %). By area that is about what landscape takes (the sidebar zone alone is 22 % of
  the area in both). Limits: the bottom stack takes at most 40 % of the safe height (every portrait
  profile of §6 stays within it); on a screen where it would not (under about 660 dp tall), the
  build band gives way first, never the ArmyBar, a 48 dp target or the 64 dp build icons; the
  SelectionPanel is one line in portrait, so a mixed selection does not grow a column over the
  map; and nothing but the band and the ArmyBar line sits at the bottom.
- **Thumb reach at the top.** The SelectionPanel is read-only (it keeps its touches, ADR 0004's
  Amendment P21), so reach does not matter for it; tappable controls stay at the bottom, except
  the rare top-left ones.

Other screens:
- Dev scenes: the dev menu and the touch probe work in both orientations (P63). The art gallery
  is art-director's developer tool: in portrait it opens and its way back works; its layout may
  stay landscape-shaped unless art-director changes it.
- Menus (Phase 5): every menu scene (main menu, map select, settings, How to play, the tutorial's
  overlays, Licences) works in both orientations and joins §6's sizes; a single column that fits
  the short side is the default.
- Ad and consent screens (Phase 6): the UMP consent form and the full-screen ads are drawn by
  Google's SDKs in the current orientation; our screens around them (the rewarded offer, the
  post-match screen before an interstitial, the menu with its banner) follow the menu rule.
  Phase 6 checks on the phone, in both orientations, that each SDK screen shows and closes, and
  whether the menu banner must be reloaded after a rotation (an adaptive banner is sized for the
  width it was loaded at; not checked here).

### 6. Tests
- Window sizes for UI and layout tests: landscape 1280x720, 2400x1080 and 2048x1536 (today's),
  and portrait 720x1280, 1080x2400 and 1536x2048 (their transposes). P60 (qa-engineer) puts the
  six in one shared list (`tests/support/screen_sizes.gd`, with `LANDSCAPE`, `PORTRAIT` and
  `ALL`) that the suites read instead of their own literals.
- Profiles: `tests/support/ui_profiles.gd` gains portrait twins (P59, behind a new `portrait()`
  so the suites that loop over `all()` join them in their own row): `android_6in_portrait`
  (Android, 420 dpi, 1080x2400, stretch 1.5, `dp(48)` 84 base px), `web_tablet_portrait`
  (1536x2048, 1.6, 60), `desktop_portrait` (720x1280, 1.0, 48), and `web_phone_portrait`, a phone
  browser in portrait (Web, 288 dpi, screen scale 3.0, a 360x700 CSS px viewport: 1080x2100,
  stretch 1.5, `dp(48)` 96). `test_ui_scale`'s case that matches each profile's stretch with the
  engine covers them, so the base-size swap is proven against the engine, not assumed.
- A project scan (P60) fails on a suite under `tests/ui`, `tests/scenes` or `tests/view` that sets
  the window size from a literal instead of the shared list or a profile, and on a suite that runs
  only landscape sizes without an entry in the scan's pending list; each entry names the row that
  removes it (P61, P62, P63), and P64 requires the list to be empty.
- View-only proof (P62): the main scene run for a fixed number of ticks with a rotation in the
  middle of a pan, a box and a pinch queues no Command and ends with the same state hash as the
  run without the rotation.
- Headless runs use the dummy renderer, so layout is asserted on Control rects (inside the safe
  rect, >= 48 dp, no overlap, outside the reserved zone); PRs that change the layout attach
  screenshots at the six sizes (`touch-ui-rules`).

### 7. Sequencing
- Until P64 merges, `project.godot` keeps `window/handheld/orientation=4`,
  `scripts/export-android.sh` keeps its check for 11, and `tests/project/test_project_settings.gd`
  keeps 4. `export_presets.cfg`'s `progressive_web_app/orientation=0` is `Any` (Context) and stays
  0; P64 pins it and `progressive_web_app/enabled=false` in `tests/project/test_export_presets.gd`.
- Because the web export does not lock the orientation, each row shows on the phone preview in
  portrait as it merges; the APK stays landscape until P64.
- Order: P59 (base size and safe area) → P60 (test sizes) → P61 (HUD; also after P58, the central
  Theme), P62 (camera and gestures) and P63 (dev scenes) in any order → P64 (the flip,
  release-engineer). Each row is one concern and under about 400 production lines; the plan gives
  owners, dependencies and acceptance criteria.
- P64 sets `window/handheld/orientation=6`, changes the manifest check to 13 (`fullUser`) in
  `scripts/export-android.sh` and its stub in `scripts/ci/test-export-notices.sh`, updates
  `test_project_settings.gd`, adds the How to play entry, and removes the "landscape-locked until
  P64" clause from `CLAUDE.md`, `touch-ui-rules` and `touch-ux-dev`.
- From this ADR's merge on, new UI code must not assume width > height (§5), whichever row it
  belongs to; reviewers check it (`touch-ui-rules`).
- ROADMAP: Phase 3 holds the battle-screen criteria (scale, HUD, build sidebar, camera, test
  sizes, the flip), because Phase 3 builds the sidebar and its portrait band; Phase 5 holds the
  menu criterion and Phase 6 the ad and consent screens. The rows P59-P64 do not wait for
  Phase 3; a box is ticked when its criterion is met. The Phase 0 criterion that names
  `sensor_landscape` stays as it is (it was true then).

### 8. What this changes in earlier ADRs and docs (P26v)
- ADR 0004 §3 (the stretch formula and the examples "held landscape", the 180 degree turn) and
  its Amendment (P21) (the right sidebar zone): dated status note; landscape values stay true,
  portrait follows §2, §3 and §5 here.
- ADR 0002 §3 and ADR 0005 §1 and its Amendment (P18) (`sensor_landscape`, manifest 11): dated
  status notes; superseded for the future by this ADR, still true until P64.
- `CLAUDE.md` (Stack line, Mobile UX rule), `docs/GDD.md` ("Landscape only."), `touch-ui-rules`
  and `touch-ux-dev`: the rule points here; `docs/ROADMAP.md`: unchecked criteria (§7).

## Consequences
- Landscape behaviour does not change at all: every landscape stretch, dp value, layout and test
  stays as it is. Portrait gets the same physical sizes as landscape on the same device.
- One new autoload; `tests/project/test_autoloads.gd` lists it (P59). It lives in `game/ui`, not
  `game/core`, because it is a screen concern.
- Every `size_changed` handler, present and future, must be idempotent (a flip runs it twice).
- The HUD gets orientation-aware layout code in `SafeArea`'s children (P61), and the Phase 3
  sidebar is built for both shapes from the start, which costs that row some lines.
- The web preview turns with the phone from P59 on, so half-done portrait layouts are visible
  there between P59 and P61; the APK is not affected until P64.
- A phone with auto-rotate off stays in the orientation it is in (`fullUser`); the game cannot
  force a turn, and the player cannot lock one orientation inside the game (no setting is planned).
- iOS (later) reads the same project setting; its orientation list is checked when the iOS export
  is built (Phase 7).

## Alternatives considered
1. **A square base size (720x720) with `expand`.** The stretch would be `min(w, h) / 720` in both
   orientations, so a turn would not change it either. Rejected: it changes every landscape value
   that is not 16:9 or wider (2048x1536 would go from 1.6 to 2.13, and its visible rect from
   1280x960 to 960x720 base px), the desktop window would open at 720x720 without an override, and
   `test_display` and ADR 0004's tables would all change.
2. **Keep 1280x720 and scale each consumer by a factor in portrait** (fonts, base-px sizes, the
   camera zoom). Rejected: every screen and every later control would carry the factor, the dev
   scenes and menus would each need it, and a missed one shrinks to 56 %.
3. **Stretch mode `disabled` with a computed `content_scale_factor`, or `viewport` mode.**
   Rejected: `disabled` puts the scale logic in our code with the same effect as option 1 or the
   chosen swap but more code; `viewport` renders at the base resolution and scales the image,
   which blurs text and art on phones.
4. **Swap the base size in each scene's root script.** Rejected: every scene, dev scenes and future
   menus included, would need the step, and a scene without it shrinks; one autoload covers all.
5. **A second HUD scene for portrait.** Rejected: two scenes to keep in step, and a rotation in a
   match would swap scenes with live state; one scene with per-orientation layout code instead.
6. **React to `DisplayServer.orientation_changed`** (the signal exists in 4.7.2). Not used: the
   window's `size_changed` arrives on every turn and also on desktop and web resizes, and the
   window's shape, not the device's orientation, is what the layout needs.
7. **Stay landscape-only.** Rejected by Michael's decision.
