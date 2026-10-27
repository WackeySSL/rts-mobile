---
name: touch-ui-rules
description: Touch controls, camera, HUD and layout rules for rts-mobile on phones in landscape and portrait (ADR 0015) - gesture map, thresholds, hit areas in dp, build menu layout (floating panels in landscape, a band in portrait), safe areas, text sizes and feedback. Use whenever building or reviewing input handling, camera, selection, HUD, the build menu, menus or any on-screen control.
paths:
  - "game/input/**"
  - "game/ui/**"
  - "game/view/camera*"
  - "scenes/ui/**"
---

# Touch UI rules

Target: a 6-inch phone in landscape or portrait (ADR 0015), held with two thumbs in landscape and
often in one hand in portrait. It must also work on tablets and in the desktop web preview, where
the mouse emulates touch. The Android build follows the phone's sensor and the web preview turns
with the phone; no UI code assumes width > height.

## Gesture map
| Gesture | Result |
| --- | --- |
| Tap own unit | Select it, replacing the selection |
| Tap own building | Select it; a production building opens its build tab. The hit area is its silhouette, the footprint diamond plus its walls up to the sprite's top (ADR 0023 §3); a unit at the same point wins |
| Tap ground with units selected | Move there (stops an attack) |
| Tap ground with an own barracks or vehicle factory selected | Set that tab's rally point (`RALLY`) and show its flag |
| Tap ground with another own building selected | Clear the selection |
| Tap an oil or gas field with tankers selected | Load there (`HARVEST`) |
| Tap enemy with units selected | Attack it |
| Tap a shown enemy building with nothing selected | Select it for its info only (frame and panel; it takes no order) |
| Tap an enemy unit with nothing selected | Nothing yet (its info card is out of Phase 3 scope) |
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
holds any combat unit leave tankers out; a box with only tankers selects them (ADR 0019 §3).

## Sizes in dp, not pixels
- Convert with `game/ui/UiScale.gd` (`dp(value)`), which uses `DisplayServer.screen_get_dpi()`
  and the current canvas scale. Never hardcode pixel sizes for touch targets.
- Every tappable thing has a hit area of at least 48 dp, even when its sprite is smaller
  (infantry in particular).
- When hit areas overlap the touch point, pick the target whose centre is closest; with units
  selected, enemies win over own units.
- Units and buildings at one point (ADR 0023 §3, units first as in ADR 0022; P115b's
  `Picker.pick` and `Picker.pick_building`): with own units selected, enemy unit > own unit > enemy
  building > own building, an enemy building only when the sim takes the attack
  (`PickSnapshot.is_targetable`, else the tap is a ground tap); with nothing or a building
  selected, enemy units do not count, so own unit > any shown building, own or enemy (an enemy one
  is selected for its info only). A unit is hit within its pick radius of its lifted centre (the
  ground point raised by half the frame's visible height), the radius at least 24 dp. A building's
  hit area is its silhouette (the footprint diamond plus the rectangle between its left and right
  corners from the sprite's top down), at least 48 dp a side at zoom 0.75; between two buildings of
  one rank the one drawn in front (the larger sort key) wins. Ground taps go through the inverse
  projection.

## Building placement
ADR 0019 §2 (Michael's answer 1 B). Placement mode is local input state; no Command until confirm.
- The ghost starts at the tile under the view centre. A one-finger drag that starts on the ghost
  (its silhouette plus a grab margin, ADR 0023 §3) moves it; it follows the finger 64 dp above
  the touch point, so the finger never hides it, and snaps to tiles. A one-finger drag that starts
  elsewhere pans as usual; a tap on the ground moves the ghost there; pinch and two-finger pan are
  unchanged; the long-press box select is off. Dragging the ghost near the view's edge pans the
  camera. The grab margin, the edge band and the pan speed live in `data/input_settings.tres`.
- Valid tiles are tinted green with a solid outline, invalid red with a hatch and the reason's
  glyph (never colour alone), from `Placement.reason` on the snapshot. Confirm with a check-mark
  button, cancel with an X, each at least 64 dp, in place of the card row: in the floating build
  panel in landscape (ADR 0023 §12), in the band in portrait;
  the check mark is disabled while the ghost is invalid. Never place a building on touch release
  alone.
- After confirm the ghost waits ("pending") until the snapshot shows the building; if the
  structure is still ready one published tick after the Command's tick, it turns invalid with
  "Blocked". Cancel keeps the structure ready. A turn keeps the ghost's tile and sends nothing.

## Layout in landscape
The canvas's floating panels (ADR 0023 §12, Michael's answer 4 A; plan row P85d); the map fills
the rest.
- Build panel at the bottom right, as wide as the bottom row leaves after the army line and the
  selection panel's row (`HudLayout.panel_px`, 184 to 372 dp): the tabs (Structures, Infantry,
  Vehicles) as line icons above one row of named cards, 80 x 88 dp (`ItemTile.CARD_DP`), that show
  the item's icon, its cost with the name under it, and progress.
- Minimap: a floating panel at the top right, an isometric diamond (ADR 0023 §4).
- Credits and the power bar: a pill at the top left.
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
  Minimap at its right end (an isometric diamond, at most 40% of the safe width; unchanged by ADR
  0023 §12); left of it, stacked, credits and the power bar, icon-only tabs (48 dp) and one row of
  build icons (at least 64 dp) that scrolls sideways: at least three whole icons on the 6-inch
  phone, two at 360 dp wide.
- The band's height is set by `BuildSidebar` (P85) through `HudLayout.bottom_zone_dp`; a scene
  without the sidebar leaves the zone at 0. The tabs show icons only in the band.
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
- `display/window/handheld/orientation = sensor` (6, Android manifest `fullUser`, ADR 0015)
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
