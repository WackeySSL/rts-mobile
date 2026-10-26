# ADR 0015: Portrait and landscape (base size per orientation, layout, camera on rotation)

Status: accepted, 2026-10-19 (Michael's decision of 2026-10-19 and the lead's frame decisions of
the same day, both below as given). Docs PR P26v. The rows that carry it out are in
`docs/plans/2026-10-19-portrait.md` (P59-P64). Until the last of them, P64, merges, the Android
build (APK) stays landscape-locked; the web preview already turns with the phone (§7).

Status note (2026-10-22, P68b docs; ADR 0019 accepted 2026-10-22): §5 carries a dated status
note: Phase 3's sidebar row is P85 of `docs/plans/2026-10-22-phase-3.md`, and the Surrender
button joins the top-left controls. No accepted text changed.

Status note (2026-10-26, P68e docs; ADR 0023 accepted 2026-10-26, Michael's answer 4 A): §5
carries a dated status note: in landscape the right-hand build sidebar zone becomes the canvas's
floating panels (plan row P85d); portrait is unchanged. No accepted text changed.

Status note (2026-10-26, P26ai docs): §5 carries a dated status note on the portrait band as P85
(#193) merged it: its height rule, its 4 dp margins above and below, and the tab names. No
accepted text changed.

## Context
Michael, 2026-10-19, verbatim: **"Tilføj til tema at spillet også skal kunne spilles vertikale og
ikke kun i landscape"**: the game shall be playable in portrait as well as landscape. That changes
two hard rules: `CLAUDE.md`'s Stack line "2D top-down, landscape only" (which changes only through
a new ADR) and its Mobile UX rule "Landscape only".

The lead's frame decisions (2026-10-19), recorded as given (word for word):
1. Both orientations for the whole game: battle screen, HUD, build sidebar, selection, menus, the
   ad and consent screens. The device's sensor picks the orientation and the player may rotate
   during a match. Orientation is view-only: game/sim, Commands, replays and the state hash do
   not change.
2. Touch targets >= 48 dp, safe areas and the gesture set of CLAUDE.md's Mobile UX hold in both
   orientations.
3. The UI must not shrink in portrait: the same phone gives the same dp size in both
   orientations. Today the stretch is base 1280x720, canvas_items, expand, so a 1080x2400 phone
   in portrait would scale by 0.84 instead of 1.5. The ADR picks the mechanism after reading ADR
   0004 and the current code (game/ui/SafeAreaMargin.gd, the TouchInput configure path, the dp
   step and ui_profiles, project.godot's stretch and orientation settings, export_presets.cfg)
   and checks it against the Godot 4.7.2 API.
4. Camera on rotation: the world point at the screen centre stays at the centre and the zoom
   keeps the same world size per dp; the ADR states it exactly, with the camera limits.
5. Portrait layout per screen: the ADR states where each HUD element goes in portrait (build
   sidebar, ArmyBar, SelectionPanel, the Dev button, the minimap if planned) and names the risks
   (a narrower map view, the HUD's larger share of the screen) with how the layout limits them.
6. Sequencing: the build stays landscape-locked (project.godot window/handheld/orientation=4,
   export_presets.cfg progressive_web_app/orientation=0, scripts/export-android.sh's manifest
   check for 11) until the rows that make scale, HUD, menus and camera work in portrait are
   merged; flipping the orientation (with the export and manifest checks and
   tests/project/test_project_settings.gd) is the last row, owned by release-engineer. From this
   PR's merge on, new UI code must not assume width > height.

   Correction to frame decision 6 by this ADR: `progressive_web_app/orientation=0` is `Any` and
   the PWA is off (see "What the code does today"), so it locks nothing. Only `project.godot`'s
   `window/handheld/orientation=4` and the manifest check for 11 lock the build, and they lock
   the Android build (APK) only; the web preview already turns with the phone. This ADR keeps 0
   and pins it in P64 (§7). "This PR" is P26v, the docs PR that accepts this ADR.
7. Tests: UI and layout tests run at landscape and portrait sizes; the ADR names the sizes (at
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
- Under `expand` the engine floors the expanded base axis to whole base px, and the stretch
  transform's `scale.x` (what `UiScale` reads) is the window width over the base width. So a
  window and its transpose give the same scale only when the expanded axis is a whole number:
  2402x1081 shows 1599x720 base px, scale.x 2402 / 1599 = 1.502189, and 1081x2402 gives
  1081 / 720 = 1.501389; 2556x1179 gives 1.638462 and its transpose 1.637500 (ratio 1.000587);
  2992x1344 1.867665 and 1.866667. 2400x1080 and 1080x2400 give exactly 1.5 both ways. The
  difference stays under 0.1 % (review of P26v, headless on 4.7.2).
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
  side / 720)`), up to the engine's rounding of the expanded axis to whole base px (under 0.1 %;
  exactly the same at 2400x1080 and 1080x2400; Context). So:
  - every landscape value of today is unchanged (all profiles, `TARGET_SIZES`, ADR 0004's
    examples);
  - on one phone a dp size, a base-px size and the world px per dp are the same in both
    orientations (within that rounding); only the visible base rect turns (1600x720 to 720x1600
    on the 6-inch phone);
  - the dp formula of ADR 0004 §3, `UiMetrics` and `UiScale`'s existing functions do not
    change (P59 only adds the orientation function);
  - where the window itself changes in the turn (a phone browser whose toolbar takes height in
    landscape: 2400x932 is 1.29450, a portrait window of 1080x2100 is 1.5), the stretch differs
    between the orientations as it does today on any resize; dp sizes stay right through
    `UiScale`, and §4 keeps the world size per dp.
- Every handler of `size_changed` must recompute from the current metrics and be idempotent,
  because a flip runs it twice (Context). P59 adds a flip case that proves it for all eight
  existing handlers as they are today (`DpMinSize`, `SafeAreaMargin`, `TouchInput`, `ArmyBar`,
  `SelectionPanel`, `UnitLayer._resize_rings`, `touch_probe.gd`, `RtsCamera`); a row that
  rewrites a handler extends the case for it (P61 `SelectionPanel` and `ArmyBar`, P62
  `RtsCamera` and `TouchInput`, P63 `touch_probe.gd`), and every later handler joins it.
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
  layout. The recognizer emits `BOX_CANCEL` or `CAMERA_END` as `cancel_all()` does today, and no
  `TAP`. On a turn `TouchInput` routes the `BOX_CANCEL` to the `PlayerController` as usual but
  drops the `CAMERA_END`: it never reaches `RtsCamera.end_gesture()`. That call would snap the
  zoom to a level about `_anchor`, the last pinch or step point in the old view's base px (which
  may lie outside the new view), and so move the centre point and undo §4's rescale. (Review of
  P26v, headless on 4.7.2: a pinch at 2400x1080 to zoom 1.2, a turn, then `end_gesture()` gave
  zoom 1.0 and moved the centre by (-173, +83) world px.) Focus loss keeps today's routing.
- `TouchInput` finds the turn the same way as the camera (§4): it keeps the last orientation it
  saw, through §2's orientation function, and updates it on every `size_changed`. So the result
  does not depend on the order of the handlers: in `scenes/main.tscn` `Camera` comes before
  `TouchInput` and connects first, but whichever runs first, no `CAMERA_END` from a turn's cancel
  reaches the camera.
- `TouchInput.configure()` keeps running on every `size_changed` (ADR 0004 §3).

### 4. Camera on rotation
`RtsCamera` keeps two values from the last `size_changed` it handled: the window's orientation
(§2's function) and `bppd`, `UiScale.base_px_per_dp()`. It updates both at the end of every
`size_changed` handler run, a resize in the same orientation included, so a turn always compares
with the metrics just before it. (A web phone whose toolbar hides first, 2400x932 to 2400x1080,
changes `bppd` from 2.03 to 1.75; a value kept from before that resize would make the next turn
jump the zoom by about 16 %.)

On a `size_changed` where the window's orientation differs from the one `RtsCamera` saw last:
1. A zoom snap in flight is stopped (`_stop_snap()`); the zoom stays where it is.
2. `position`, the world point at the viewport centre, is kept.
3. The zoom keeps the world size per dp: `factor = bppd_new / bppd_old`, where `bppd_old` is the
   kept value and `bppd_new` the current one. If `|factor - 1| < 0.001` the zoom does not change:
   that is the engine's rounding of §2 (exactly 1.0 at 2400x1080 and 1080x2400, under 0.1 % on
   other phones whose window turns to its exact transpose), so a zoom on a level stays on it.
   Otherwise `zoom_new = zoom_old * factor`, clamped to the pinch bounds of `_zoom_about`
   (`zoom_levels[0] * (1 - pinch_overshoot)` to the last level `* (1 + pinch_overshoot)`); this
   is where system bars or a browser toolbar take a different share of the screen in each
   orientation (`web_phone` 2400x932 to a 1080x2100 window: factor 1.75 / 2.028 = 0.863). It
   does not snap to a level; the turn's `CAMERA_END` never reaches the camera (§3), so the zoom
   stays off its level until the player's next gesture end or wheel step snaps it, as today.
4. `_anchor` is set to the new view's centre, so a later snap before any new pinch or step zooms
   about the centre and keeps the centre point.
5. Then `_clamp_to_map()` runs with the new visible size: on each axis `position` is clamped to
   the map rect inset by half the visible world size, or set to the map centre where the map is
   smaller than the view on that axis. So the centre point stays at the centre except where the
   new view would cross a map edge.
6. `limit_*` stays the map rect from `set_map_rect()`; a rotation does not touch it.
7. There is no memory: turning back starts from the clamped position.

Other resizes (a browser toolbar in the same orientation, a desktop window drag) keep today's
behaviour: the zoom stays and the clamp runs; the kept orientation and `bppd` are refreshed.
The autoload of §2 connects before any scene node (autoloads enter the tree first), so in the
double emission of a flip the camera sees the new stretch both times: it rescales on the first
run, where the orientation differs from the one it saw last, and only clamps (and refreshes the
same values) on the second. `TouchInput`'s drop of the turn's `CAMERA_END` (§3) does not depend
on the order of the scene's handlers.

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
  (P21) says for landscape.
- While the build sidebar does not exist (until Phase 3's sidebar row), the landscape zone stays
  reserved but empty, as today, and the portrait zone is not reserved: its height is 0 and the
  ArmyBar sits on the safe bottom edge, in thumb reach, not above an empty 200 dp strip. The HUD
  layout reads the portrait zone's height from one place; Phase 3's sidebar row sets it to the
  band's height, which moves the ArmyBar above the band (ROADMAP Phase 3). P61's tests set a
  stand-in band height of 200 dp to prove "no control in the zone" and the 40 % limit before the
  band exists.
- In portrait, the controls a player taps often (army and groups, build, the minimap) sit in the
  bottom part of the screen; the top line holds only read-only information and the rare top-left
  controls (the Dev button now, pause and menu later).

Portrait layout of the battle screen (the 6-inch phone: 1080x2400 at 420 dpi, 720x1600 base px,
411x914 dp):

| Element | Landscape (today) | Portrait |
| --- | --- | --- |
| Build sidebar (Phase 3) | Right edge, 20 % of the width, at least 200 dp; minimap at the top, then credits and the power bar, then the tabs and the build icons (>= 64 dp) | Bottom band, the full safe width, 20 % of the height and at least 200 dp; the minimap at its right end; left of it, stacked: the credits and power line, the tabs (icon-only, 48x48 dp each), and one row of build icons (>= 64 dp) that scrolls sideways (budget below) |
| Minimap (Phase 3) | Top of the sidebar | Right end of the bottom band: a square of the band's inner height (the band less 8 dp margins), but at most 40 % of the safe inner width |
| ArmyBar | Bottom-left | Bottom-left on the safe bottom edge while the portrait zone is 0 (until Phase 3's sidebar row), then directly above the band (8 dp gap); same sizes (288x56 dp) |
| SelectionPanel | Bottom centre, in the band between the ArmyBar and the sidebar zone | Top edge, right of the top-left controls (8 dp gap), one row high (48 dp plus its padding), with the fit levels below |
| Dev button | Top-left | Top-left |
| Pause and menu (later) | Top-left | Top-left |
| Under-attack indicators (later) | Screen edges and a minimap ping | The same |

The portrait SelectionPanel's fit levels. The panel never grows past its line: the space from
the top-left controls' right edge plus 8 dp to the safe rect's right edge (280 dp on
`web_phone_portrait`, 360 dp wide; 331 dp on the 6-inch phone). An overflow would grow the
`SafeArea` MarginContainer and push the HUD off the screen (`SelectionPanel.gd`'s own warning).
The first level whose line fits is used, for the whole line:
1. every type row with icon, name and count, the Total last;
2. every type row with icon and count only, the Total last;
3. the same without the Total;
4. the first K type rows (in the panel's row order) that fit with a "+N" chip after them, where N
   is the number of types not shown; K is at least 1 (one row and the chip fit in about 150 dp at
   3-digit counts).
For scale (Godot's fallback font, 20 dp numbers, 40 dp icons, 8 dp gaps and padding): icon and
count with the Total take 250 dp for 2 types and 329 dp for 3 at single-digit counts, 285 dp and
375 dp at 2-digit counts, so a 360 dp phone reaches level 3 or 4 with 3 types, and every phone
with all six MVP unit types does.

The portrait build band's budget (Phase 3 builds it; these numbers hold). Inner height: 200 dp
less 8 dp margins = 184 dp; stacked left part: credits and power 32 dp, tabs 48 dp, icons 64 dp,
two 8 dp gaps = 160 dp. Inner width: 387 dp on the 6-inch phone, 336 dp at 360 dp. The minimap
is at most 40 % of it (155 dp, 134 dp), which leaves 224 dp and 194 dp: three icon-only tabs
(3 x 48 + 2 x 8 = 160 dp) fit both, and the icon row shows at least three whole 64 dp icons on
the 6-inch phone and two at 360 dp, with part of the next one visible so the row reads as
scrollable. The tab names show where the band is wide enough (landscape, tablets); in the
portrait band the tabs are icon-only (shapes, not colour alone; `touch-ui-rules`).

Risks and how the layout limits them:
- **A narrower map view.** In portrait the 6-inch phone shows 720 world px across at zoom 1.0
  (11.25 tiles) instead of 1600 (25 tiles), and 960 px (15 tiles) at the widest level 0.75. The
  zoom levels stay the same in both orientations (one list in `data/input_settings.tres`); the
  minimap's tap-to-jump (Phase 3) and the under-attack indicators (when they come) are the remedy
  for what lies beside the view. Double-tap's "all of that type on screen" picks from the
  narrower view, as the rule says.
- **The HUD's larger share of the screen height.** On the 6-inch phone the bottom stack (band
  200 dp + 8 dp + ArmyBar 56 dp = 264 dp) is 29 % of the height, the top line with a selection
  64 dp more (7 %). By area that is about what landscape takes (the sidebar zone alone is 22 % of
  the area in both). Limits: the bottom stack takes at most 40 % of the safe height (every portrait
  profile of §6 stays within it); on a screen where it would not (under about 660 dp tall), the
  build band gives way first, never the ArmyBar, a 48 dp target or the 64 dp build icons; the
  SelectionPanel is one line in portrait with the fit levels above, so a mixed selection grows
  neither a column over the map nor the line past the screen; and nothing but the band and the
  ArmyBar line sits at the bottom. Until Phase 3's band exists the bottom stack is the ArmyBar
  line alone (56 dp plus the margin).
- **Zoom with one hand.** The only zoom gesture is a two-finger pinch (frame decision 2 keeps the
  gesture set), and portrait is often held in one hand, while the narrower view needs zoom-out
  more; the minimap and the indicators that would help arrive after P64. P64's phone check tries
  zooming out with one hand. If Michael finds it too hard, a one-finger zoom is an addition to
  the gesture set and needs its own ADR (with how it differs from double-tap and long-press);
  the wheel step stays desktop only. Michael decides after P64's check.
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

Status note (2026-10-22, P68b docs, ADR 0019 accepted; the text above stays as accepted): "Phase
3's sidebar row" is P85 of `docs/plans/2026-10-22-phase-3.md` (ADR 0019 §1): `BuildSidebar` sets
the portrait zone's height through P61's one place, which moves the ArmyBar above the band, and
turns P61's stand-in band cases into real-band cases; P85b adds the item row, P88 the minimap
(ADR 0019 §4) and P89 the under-attack indicators (ADR 0019 §5), at the places the table above
gives them. During placement the check mark and X (64 dp) take the item row's place in the zone
(ADR 0019 §2, P86). The "Surrender" button (ADR 0019 §6, P90) is one more rare top-left control,
so the SelectionPanel's portrait line starts after it and gets shorter; P90 re-runs P61's worst
case (six types, 3-digit counts, 360 dp) with it. On 757b5f9 P59 (#164) and P60 (#165) are open
PRs and P61-P63 have started.

Status note (2026-10-26, P68e docs, ADR 0023 accepted 2026-10-26, Michael's answer 4 A; the text
and the note above stay as accepted): ADR 0023 §12 changes the landscape column of the table above
from plan row P85d on. The right-hand zone (20 % of the width, at least 200 dp) goes: the build
panel floats at the bottom right (tabs as line icons above one row of named cards of at least
64 dp; during placement the check mark and X take the card row's place), the minimap is a floating
panel at the top right, and the credits and power bar a pill at the top left; the map fills the
rest. The ArmyBar, the SelectionPanel and the top-left controls keep their places, clear of the
panels (P85d checks every control at the six sizes: inside the safe rect, at least 48 dp, no
overlap). The portrait column is unchanged: the bottom band, its budget, the minimap at its right
end (now an isometric diamond, ADR 0023 §4, at most 40 % of the safe inner width) and the ArmyBar
above the band. The general rules of this section hold.

Status note (2026-10-26, P26ai docs, P85 as merged, #193, with P85c, #194, and P85b, #198; the
text and the notes above stay as accepted and as dated):
- **The band's height** is `HudLayout.band_dp` (`game/ui/HudLayout.gd`): 20 % of the safe height
  and at least 200 dp, but no more than keeps the band and the ArmyBar line (the edge margin, the
  8 dp gap and the 56 dp bar) within 40 % of the safe height; it gives way first, down to
  `BAND_FLOOR_DP` 172. `BuildSidebar` writes it to `HudLayout.bottom_zone_dp`, the one place of
  P61, on `_ready` and on every resize, and a scene without a sidebar leaves it at 0.
- **Margins.** The sidebar's backdrop (`game/ui/theme.tres`) has 8 dp at the sides and 4 dp above
  and below, not 8 dp, so a 200 dp band's inner height is 192 dp, not 184. The floor 172 is the
  stacked left part (status line 32, tabs 48, items 64, two 8 dp gaps: 160) plus the two 4 dp
  margins and 4 dp for the gaps' rounding to whole px. The minimap's square (plan row P88) is the
  band's inner height as the theme gives it.
- **Tab names** show beside the icons only in landscape and only where all three tabs fit the
  zone with them (`BuildSidebar._fit_names`); the portrait band shows icons only, however wide.

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
- Camera turn cases (P62): a gesture-free turn at 2400x1080 ↔ 1080x2400 and at 2556x1179 ↔
  1179x2556 (the engine's rounding, §2) keeps the zoom on its level; a turn during a pinch (zoom
  between levels, anchor off-centre in the old view) and during a pan with a factor other than 1
  (`web_phone` 2400x932 to a 1080x2100 window) keeps the centre point and §4's zoom, and no snap
  starts; a resize within landscape (2400x932 to 2400x1080) followed by a turn keeps the world px
  per dp of after the resize within 0.1 % (§4: the resize keeps the zoom and refreshes `bppd`, so
  the value from before the resize is not the one kept).
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
- Because the web export does not lock the orientation (the PWA is off, and the 4.7.x web
  display server does not report the orientation feature, so the project's orientation setting
  is not applied there; review of P26v, from the engine source), each row shows on the phone
  preview in portrait as it merges; the APK stays landscape until P64. P59 changes the sentence
  CI posts with each preview (`scripts/ci/pages-publish.sh`: "Open it on the phone in
  landscape.") to say the preview turns with the phone and that a PR which changes layout says
  which orientation to try.
- P60 also points the touch-ux-dev agent's "Test every screen at" line and `touch-ui-rules`'
  "Verify on three sizes" section at the six sizes of §6 (merged with the portrait section's
  "Verify also" line), so the rows P61-P63 are written against them.
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
- The web preview already turns with the phone and shows portrait at the right scale from P59
  on, so half-done portrait layouts are visible there between P59 and P61; the APK is not
  affected until P64.
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
