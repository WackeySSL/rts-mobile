---
name: touch-ui-rules
description: Touch controls, camera, HUD and layout rules for rts-mobile on phones in landscape and portrait (ADR 0015) - gesture map, thresholds, hit areas in dp, sidebar layout, safe areas, text sizes and feedback. Use whenever building or reviewing input handling, camera, selection, HUD, the build sidebar, menus or any on-screen control.
paths:
  - "game/input/**"
  - "game/ui/**"
  - "game/view/camera*"
  - "scenes/ui/**"
---

# Touch UI rules

Target: a 6-inch phone in landscape or portrait (ADR 0015), held with two thumbs in landscape and
often in one hand in portrait. It must also work on tablets and in the desktop web preview, where
the mouse emulates touch. The Android build stays landscape-locked until ADR 0015's flip row (P64)
merges; the web preview already turns with the phone. Until then, and after, no UI code assumes
width > height.

## Gesture map
| Gesture | Result |
| --- | --- |
| Tap own unit | Select it, replacing the selection |
| Tap own building | Select it; a production building opens its build tab |
| Tap ground with units selected | Move there (stops an attack) |
| Tap ground with an own barracks or vehicle factory selected | Set that tab's rally point (`RALLY`) and show its flag |
| Tap ground with another own building selected | Clear the selection |
| Tap ore with harvesters selected | Harvest there (`HARVEST`) |
| Tap enemy with units selected | Attack it |
| Tap enemy with nothing selected | Show its info card |
| Double-tap own unit | Select all own units of that type on screen |
| Long-press 300 ms on ground, then drag | Selection box, selects on release |
| One-finger drag beyond 12 dp | Pan the camera |
| Two-finger pinch | Zoom between 3 levels, smoothly |
| Two-finger drag | Pan, always |
| Tap minimap | Move the camera there |
| Long-press minimap with units selected | Move the units there |
| Tap a build icon | Queue one (`QUEUE`, paid at once) |
| Long-press a build icon with items queued | Cancel the last queued item of that type (`CANCEL`, refunded) |

Thresholds live in `data/input_settings.tres`, never in code.

Buildings never join a box, a double-tap selection or "All army". "All army" and a box that
holds any combat unit leave harvesters out; a box with only harvesters selects them (ADR 0019 §3).

## Sizes in dp, not pixels
- Convert with `game/ui/UiScale.gd` (`dp(value)`), which uses `DisplayServer.screen_get_dpi()`
  and the current canvas scale. Never hardcode pixel sizes for touch targets.
- Every tappable thing has a hit area of at least 48 dp, even when its sprite is smaller
  (infantry in particular).
- When hit areas overlap the touch point, pick the target whose centre is closest; with units
  selected, enemies win over own units.

## Building placement
ADR 0019 §2 (Michael's answer 1 B). Placement mode is local input state; no Command until confirm.
- The ghost starts at the tile under the view centre. A one-finger drag that starts on the ghost
  (its footprint plus a grab margin) moves it; it follows the finger 64 dp above the touch point,
  so the finger never hides it, and snaps to tiles. A one-finger drag that starts elsewhere pans
  as usual; a tap on the ground moves the ghost there; pinch and two-finger pan are unchanged;
  the long-press box select is off. Dragging the ghost near the view's edge pans the camera. The
  grab margin, the edge band and the pan speed live in `data/input_settings.tres`.
- Valid tiles are tinted green with a solid outline, invalid red with a hatch and the reason's
  glyph (never colour alone), from `Placement.reason` on the snapshot. Confirm with a check-mark
  button, cancel with an X, each at least 64 dp, in the sidebar zone in place of the item row;
  the check mark is disabled while the ghost is invalid. Never place a building on touch release
  alone.
- After confirm the ghost waits ("pending") until the snapshot shows the building; if the
  structure is still ready one published tick after the Command's tick, it turns invalid with
  "Blocked". Cancel keeps the structure ready. A turn keeps the ghost's tile and sends nothing.

## Layout in landscape
Today's layout, unchanged by ADR 0015.
- Right sidebar: 20% of the width and at least 200 dp. Minimap at the top, then credits and the
  power bar, then tabs (Buildings, Infantry, Vehicles) with build icons of at least 64 dp that
  show cost and progress.
- Bottom-left: "All army" and groups 1-3 (tap selects, long-press assigns).
- Top-left: pause and menu.
- No ads on this screen, ever.
- Keep every control inside `DisplayServer.get_display_safe_area()`.

## Layout in portrait (ADR 0015 §5)
- Same sizes as landscape on the same phone: a portrait window uses the base size 720x1280 instead
  of 1280x720 (ADR 0015 §2, from P59), so the stretch, every dp and every base-px size match.
  Decide the shape only through `UiScale`'s orientation function (P59; height > width is
  portrait).
- Build sidebar zone: a bottom band, the full safe width, 20% of the height and at least 200 dp.
  Minimap at its right end (square, at most 40% of the safe width); left of it, stacked, credits
  and the power bar, icon-only tabs (48 dp) and one row of build icons (at least 64 dp) that
  scrolls sideways: at least three whole icons on the 6-inch phone, two at 360 dp wide.
- Until Phase 3's sidebar row the portrait zone is not reserved (height 0); that row sets it.
- Bottom-left: "All army" and groups 1-3, on the safe bottom edge while the zone is 0, then
  directly above the band.
- Top line: the read-only selection panel, right of the top-left controls (8 dp gap), one row
  high, never wider than that line. Fit levels, first that fits: names; icon and count; without
  the Total; the first rows that fit and a "+N" chip for the types not shown. Top-left: Dev
  button, pause and menu.
- Taps players make often (army, groups, build, minimap) stay at the bottom; the bottom stack
  (band plus army line) takes at most 40% of the safe height, and the band gives way first.
- No ads on this screen, ever.
- Safe areas: the same `SafeAreaMargin` rule (both sides of an axis get the larger inset).
- A turn keeps the camera centre and the world size per dp (ADR 0015 §4) and cancels gestures in
  flight; it never issues a Command.

## Text and feedback
- At least 14 sp body text and 18 sp HUD numbers. Never use colour alone for meaning; team
  colours also differ by marker shape.
- Every command gets instant feedback: selection ring, move marker, short sound, optional light
  haptic (`Input.vibrate_handheld(15)`, can be turned off in settings).
- Under attack: edge-of-screen indicator and a minimap ping.

## Project settings
- `display/window/handheld/orientation = sensor_landscape` until ADR 0015's flip row (P64), then
  `sensor` (6, Android manifest `fullUser`)
- `input_devices/pointing/emulate_touch_from_mouse = true`, `emulate_mouse_from_touch = false`
- Stretch mode `canvas_items`, aspect `expand`, base size 1280x720.

## Verify on six sizes
Landscape 1280x720, 2400x1080 (20:9) and 2048x1536 (4:3), and portrait 720x1280, 1080x2400 and
1536x2048 (ADR 0015 §6). Attach screenshots of each to PRs that change the layout. UI and layout
tests read the sizes from `tests/support/screen_sizes.gd` (`ScreenSizes.LANDSCAPE`, `PORTRAIT`,
`ALL`) or from a profile of `tests/support/ui_profiles.gd`, never from a literal.
`tests/project/test_screen_sizes_scan.gd` fails on a literal window size and on a suite that runs
only landscape sizes unless its `PORTRAIT_PENDING` entry names the row (P61, P62, P63) that adds
the portrait ones; P64 requires the list to be empty.
