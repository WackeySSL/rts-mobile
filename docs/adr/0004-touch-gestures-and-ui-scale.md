# ADR 0004: Touch gestures, UiScale.dp(), selection and the Phase 1 camera

Status: accepted, 2026-10-10

Status note (2026-10-12): §5 partly superseded by ADR 0009 (a tap on an enemy issues `ATTACK`);
§7 partly superseded by ADR 0011 §3 (selection rings are sprites of one ring texture, not drawn
in code).

Status note (2026-10-19, P26v docs; ADR 0015, accepted 2026-10-19): the text below stays as
accepted. Where it assumes landscape it is superseded for the future by ADR 0015 and still true
for every landscape window: the Context's stretch `min(w / 1280, h / 720)` and §3's examples
("held landscape") hold in landscape; from P59 a portrait window uses the base size 720x1280, so
its stretch is `min(w / 720, h / 1280)`, the same number as the same device in landscape (ADR 0015
§2). §3's dp formula, `UiMetrics` and `set_override()` do not change. §3's 180 degree turn rule
for `SafeAreaMargin` ("sensor landscape") holds in both orientations (ADR 0015 §3), and an
orientation change cancels gestures in flight (ADR 0015 §3, P62). §6's camera gains the rotation
rule of ADR 0015 §4 (P62). The Amendment (P21)'s right sidebar zone is the landscape zone; in
portrait the zone is a bottom band (ADR 0015 §5, P61).

## Context
Phase 1 is a go/no-go on controls. `touch-ui-rules` gives the gesture map and the 48 dp rule,
but it leaves several things open: how tap, long-press, drag, pinch and double-tap are told
apart, how the camera and the selection layer share fingers, and how dp becomes pixels. It also
has a conflict: "one-finger drag = pan" against "long-press + drag = box select". ADR 0002 §5
(one-finger pan camera) and §6 (120 base px dev buttons until `UiScale` exists) said Phase 1
replaces them.

Facts checked on Godot 4.7.2:
- Checked headless in a scratch project:
  - `Viewport.get_stretch_transform()` exists. At window sizes 1280x720, 2400x1080 and
    2048x1536 it is a uniform scale of 1.0, 1.5 and 1.6. That is `min(w / 1280, h / 720)` with
    `canvas_items` + `expand`.
  - `push_input()` takes window pixels. `_unhandled_input` receives base (canvas) pixels: a
    push at (1200, 540) on a 2400x1080 window arrives at (800, 360).
  - Headless reports `screen_get_dpi() = 96`, `screen_get_scale() = 1.0` and an empty safe area.
  - `display/window/dpi/allow_hidpi` defaults to true.
  - `InputEventScreenTouch` has `canceled` and `double_tap`. `InputEventScreenDrag` has
    `relative` and `velocity`. `InputEvent` has no timestamp.
  - `input_devices/pointing/android/enable_long_press_as_right_click` and
    `enable_pan_and_scale_gestures` are false by default, so Android does not turn our touches
    into other events.
- From the Godot `4.7.2-stable` source:
  - Web `screen_get_scale()` returns the canvas pixel ratio: `devicePixelRatio` when hidpi is
    on, else 1 (`library_godot_display.js` `getPixelRatio`). `screen_get_dpi()` is
    `round(devicePixelRatio * 96)`.
  - Godot's web shell sets `touch-action: none` and `user-scalable=no`, so a pinch on the canvas
    does not zoom the page.
- Not verified on a device: the Android `screen_get_dpi()` value. It is expected to be the
  density bucket (`DisplayMetrics.densityDpi`, for example 420). The touch probe (decision 3)
  measures it on Michael's phone.

## Decision
1. **Layers.** One finger stream feeds one pure recognizer. Its output goes to two consumers:
   - `game/input/GestureRecognizer.gd` is pure (no Node, no engine time). Time is injected as
     `now_ms: int` on every call, positions are in base px, and thresholds come from
     `InputSettings` (in dp and ms) times a `base_px_per_dp` factor passed in `configure()`. It
     queues `GestureEvent`s.
   - `game/input/TouchInput.gd` (Node) is the only engine adapter. It feeds touches with
     `clock.call()` (default `Time.get_ticks_msec`), calls `advance()` every frame, and
     dispatches each event at once:
     - camera events (`PAN`, `PINCH`, `CAMERA_END`) go to `RtsCamera`;
     - selection events (`TAP`, `DOUBLE_TAP`, `LONG_PRESS`, `BOX_*`) go to `PlayerController`.
   - `PlayerController` turns selection events into `SelectionModel` changes and Commands
     (CommandQueue only), plus feedback.
   - Finger routing keeps the ADR 0002 §5 rule. A press that reaches `_unhandled_input` did not
     start on a GUI control, so it belongs to the recognizer. Its drags and its release are taken
     in `_input` and marked handled, so a pan that crosses a HUD button keeps panning. A touch
     that starts on a HUD button stays with the button.
   - Mouse button and motion events are ignored. Desktop clicks arrive as emulated touches. The
     one exception is the mouse wheel, which steps the zoom level, for the desktop preview only.
   - Losing app focus cancels all gestures.
2. **Disambiguation** (defaults in `data/input_settings.tres`; tests use the same file):
   | Setting | Default | Meaning |
   | --- | --- | --- |
   | `tap_slop_dp` | 12 | Movement beyond this, before the long-press time, is a pan (`touch-ui-rules`) |
   | `long_press_ms` | 300 | Held within the slop this long: long-press, then box select |
   | `double_tap_ms` | 300 | From the first tap's release to the second tap's press |
   | `double_tap_slop_dp` | 32 | Maximum distance between the two taps |
   | `hit_radius_dp` | 24 | Minimum hit radius around a unit centre (48 dp diameter) |
   | `group_assign_ms` | 500 | Hold on a group button to assign it |
   | `zoom_levels` | 0.75, 1.0, 1.5 | Camera zoom levels; start at `zoom_start_index` 1 |
   | `pinch_overshoot` | 0.15 | Pinch may go this fraction beyond the outer levels before the snap |
   | `zoom_snap_ms` | 150 | Snap animation; 0 = immediate (tests) |
   | `marker_ms` | 600 | Move-marker lifetime |
   | `haptic_ms`, `haptics_enabled` | 15, true | Vibration on long-press and group assign |

   States: `IDLE`, `PENDING` (one finger, undecided), `PAN`, `BOX`, `MULTI` (two or more fingers).
   - `PENDING` and the finger leaves the slop: `PAN`. The first `PAN` delta is the full
     distance from the press, so the map stays under the finger.
   - `PENDING`, `now - down >= long_press_ms`: emit `LONG_PRESS`, then `BOX`.
   - `PENDING`, the finger lifts: emit `TAP`, even if the long-press time has passed and
     `advance()` has not run since then. If the press came within `double_tap_ms` of the
     previous tap's release and lies within `double_tap_slop_dp` of it, emit `DOUBLE_TAP`
     instead, and the remembered tap is cleared. **A tap acts at once.** Double-tap's action
     (select all of a type) is a superset of tap's action (select one unit), so no tap waits
     for a possible second tap.
   - `BOX`: each move emits `BOX_UPDATE` with the normalised rect. On release, a rect larger
     than the slop on either axis emits `BOX_END`. Otherwise the press was a slow tap: emit
     `BOX_CANCEL`, then `TAP` at the press point. This forgives a finger that rested on a tank
     for 300 ms.
   - A second finger in any one-finger state goes to `MULTI`. A pending tap is dropped, and a
     box emits `BOX_CANCEL`. `MULTI` tracks the first two fingers by arrival and ignores the
     others. Each move emits `PINCH` with the centroid, the centroid delta (two-finger pan) and
     the distance ratio (zoom).
   - When `MULTI` drops to one finger: emit `CAMERA_END` (zoom snap), then `PAN` with the
     remaining finger. No tap or box starts until every finger is up. A `PAN` release emits
     `CAMERA_END`.
   - A release with `canceled == true` never taps. A press for an index that is already down
     first cancels that index. `cancel_all()` emits `BOX_CANCEL` or `CAMERA_END` as needed and
     returns to `IDLE`.
   - **The conflict is resolved by time.** Moving first is a pan. Holding first is a box. That
     is the `touch-ui-rules` gesture map read literally, and two-finger drag always pans.
3. **`UiScale.dp()`** lives in `game/ui/UiScale.gd` (`class_name UiScale extends RefCounted`,
   static functions only, no autoload), as `touch-ui-rules` names it. It returns **base canvas
   px**, the unit of Control sizes and of input positions under `canvas_items` stretch.
   - `UiMetrics` (`game/ui/UiMetrics.gd`) holds `os_name`, `dpi`, `screen_scale`,
     `stretch_scale`, `window_size` and `safe_area` (window px).
   - Window px per dp:
     - `Android`: `dpi / 160.0`, the Android definition of dp.
     - `iOS`: `screen_scale` (1 pt is about 1 dp).
     - `Web`: `screen_scale` (canvas px per CSS px; a CSS px is about a dp in mobile browsers).
     - Everything else (desktop, headless): `screen_scale`.
     - A result that is not finite or not above 0 falls back to 1.0. The result is clamped to
       [0.75, 4.0].
   - Base px per dp = window px per dp / `stretch_scale`, where `stretch_scale` is
     `get_stretch_transform().get_scale().x` of the root viewport (1.0 when it is not above 0).
   - `dp(v)`, `dp_vec(x, y)`, `base_px_per_dp()` and `safe_rect_base()` read the current
     metrics. `safe_rect_base()` is the safe area in base px, or the visible rect when the
     platform reports an empty safe area.
   - `set_override(m)` and `clear_override()` exist for tests only. They are static state, so
     every suite that sets an override clears it in `after_test`.
   - Values change when the window resizes (rotation, browser toolbar). Users of dp sizes
     recompute on the viewport's `size_changed`: `DpMinSize` and `SafeAreaMargin` do, and
     `TouchInput` re-runs `configure()`. A 180 degree turn (sensor landscape) moves the cutout
     without a resize, so `SafeAreaMargin` gives both sides of an axis the larger inset.
   - Examples (a 6-inch phone, 1080x2400, 420 dpi, held landscape):
     - Native APK: window 2400x1080, stretch 1.5, so `dp(48)` = 48 x 2.625 / 1.5 = 84 base px.
     - Chrome: a 914x355 CSS viewport gives a canvas of 2400x932, stretch 1.294, so
       `dp(48)` = 97 base px.
     - Desktop at 1280x720: `dp(48)` = 48 base px.
   - A dev scene `scenes/dev/touch_probe.tscn` (from the dev menu) shows the metrics, a 48x48 dp
     square (7.6 mm on any phone if the formula is right) and the live gesture events. Michael
     measures the square once on his phone. That replaces ADR 0002 §6's reasoned estimate with
     a measurement.
   - **This supersedes ADR 0002 §6.** The rule "every Button at least 120x120 base px" becomes
     "every tappable thing at least `UiScale.dp(48)` on each axis, at every test profile".
     Dev buttons at 120 base px still pass, because `dp(48)` stays below 120 base px on every
     profile in the test table.

   Status note (2026-10-19, P26x docs, P58 as merged, #107), the text above stays as accepted:
   the HUD Theme's dp step is `game/ui/HudTheme.gd`. `game/ui/theme.tres` holds the HUD's font
   sizes and StyleBox sizes in dp, because a Theme stores fixed numbers. `HudTheme`, a `Node`
   and the first child of the `Hud` `CanvasLayer`, gives each HUD root a copy of its theme with
   every font size and every StyleBox size multiplied by `UiScale.base_px_per_dp()`, at `_ready`
   and on every viewport `size_changed` (before the HUD scripts' own handlers, which may read
   the theme), and to a root added later as it enters the tree. The copy is the root's `theme`,
   never a node override; an entry kept in base px is listed in the theme's `metadata/base_px`
   (today only the Dev button's font size, 40). So the theme is one more user of dp sizes that
   recomputes on `size_changed`, beside `DpMinSize`, `SafeAreaMargin` and `TouchInput` above.
   The Phase 2 plan's section P58 "As merged" has the details.
4. **Hit testing.** A unit's hit radius in screen px is
   `max(dp(hit_radius_dp), ViewScale.milli_to_px(selection_radius) * zoom)`, with
   `selection_radius` in milli-tiles from the unit data. When hit areas
   overlap, the closest centre wins, and ties go to the lower id. With nothing selected, only
   own units are candidates. With units selected, enemies win over own units
   (`touch-ui-rules`).
5. **Actions** (`PlayerController`):
   - Tap own unit: the selection becomes that unit.
   - Tap an enemy with units selected: attack-move to the enemy's position. This is the
     Phase 1 reading of "attack it", and Phase 2 adds a targeted attack.
   - Tap an enemy with nothing selected: nothing for now (an info card comes later).
   - Tap ground with units selected: an attack-move Command plus a move marker. The target is
     `ViewScale.px_to_milli()` of the world point. Tap ground with nothing selected: nothing.
   - `DOUBLE_TAP` on an own unit selects all own units of that type whose screen positions are
     inside the visible viewport, and always the tapped unit. Anywhere else it is handled as a tap.
   - `BOX_END` selects the own units whose screen centres lie in the rect. An empty box clears
     the selection, which is the deliberate way to deselect.
   - "All army" selects every own unit with speed > 0 on the whole map.
   - Group button tap: select that group. Hold for `group_assign_ms`: assign the current
     selection to the group. Sliding off the button first cancels the hold.
   - The selection is a sorted, unique `PackedInt32Array`. Commands carry it as `unit_ids`.

   Status note (2026-10-20, P43c), the text above stays as accepted: since P43c a tap on the
   ground with units selected issues `MOVE` (`Command.move`), not an attack-move, so it stops an
   attack and the units drive to the point without fighting (Michael's decision of 2026-10-20:
   selecting units and telling them to drive to another position must stop the attack). The
   Consequences' double-tap line holds with "move" for "attack-move". No gesture issues
   `ATTACK_MOVE` any more; scenario orders and the Phase 4 AI still may.
6. **Camera** (`game/view/RtsCamera.gd`, replaces `camera_pan.gd`):
   - Pan: `position -= delta / zoom`.
   - Pinch: zoom about the centroid, so the world point under it stays under it. The zoom is
     bounded by the outer levels widened by `pinch_overshoot`.
   - `CAMERA_END` snaps to the nearest level (by ratio, anchored at the last centroid) over
     `zoom_snap_ms`.
   - Edge clamping keeps the ADR 0002 §5 rule: clamp `position` to the map rect inset by half
     the visible size, centre the map on any axis where it is smaller than the view, and
     re-clamp on resize and on every zoom step.
   - The camera owns no input handling. **This supersedes ADR 0002 §5's camera input part.**
7. **Feedback.** Selection rings, the move marker, the long-press anchor and the box are drawn
   procedurally in view code, so they stay crisp at every zoom and can be sized in dp. They
   are not SVG. art-director specifies their shape and colour in `assets/art/STYLE.md`, using
   shape as a second cue besides colour. Haptics use `Input.vibrate_handheld(haptic_ms)`, which
   needs the Android `VIBRATE` permission (ADR 0005). There is no sound in Phase 1.

## Consequences
- Every gesture rule is provable headless with injected time (`tests/input/`), without frames
  or timers. Scene-level tests push window-pixel events through `push_input()` with a fake clock.
- Taps have no added latency. The cost is that a double-tap on ground issues the attack-move
  twice, which is harmless because the second order replaces the first.
- A finger that rests 300 ms before panning starts a box instead of a pan. If the gate shows
  this, `long_press_ms` is tuned in data. No code changes.
- Tapping ground always orders, so deselecting needs an empty box. Michael is asked to confirm.
- `UiScale` returns different base px per platform for the same dp. Tests therefore assert
  against profiles (Android, phone web, tablet web, desktop) through `set_override()`.
- The phone-browser formula rests on Godot source, not on a device. The touch probe and
  Michael's ruler check close that gap. Fixing a wrong factor needs a new ADR, not a silent
  constant change.
- Mouse wheel zoom is the only Mouse event any gesture code reads.

## Amendment (2026-10-11, P8 review)
- Pinch guard: `PINCH.scale` stays 1.0 while either finger distance, before or after the move, is
  below `GestureRecognizer.MIN_PINCH_DP` (8 dp, at least 1 px). The centroid delta still applies.
  This is a numeric guard against dividing by about zero, not a feel threshold, so it stays in code.
- Hand-over: when one of two fingers lifts, the recognizer emits `CAMERA_END` and continues as
  `PAN`; the final release emits `CAMERA_END` again. `RtsCamera.end_gesture()` is idempotent.
- A duplicate down for a finger already down in `MULTI` first ends that finger like a lift, then
  handles the press normally.
- Two fingers moving in the same frame give two `PINCH` events, each with part of the centroid
  delta and a partial scale. The scales multiply, so `TouchInput` (P10) applies every event in order.

## Amendment (2026-10-11, P21)
- Section 1 gives a touch that starts on a HUD button to the button. A read-only HUD panel with
  `mouse_filter` STOP gets the same rule: a tap on it never orders, and a pan, box or pinch finger
  that starts on it is lost. Such panels stay small; the selection panel is the only one so far.
- The right sidebar zone (touch-ui-rules: 20% and at least 200 dp) is reserved for the build
  sidebar. HUD elements stay out of it, except that it gives way on screens too narrow for the
  bottom HUD.
