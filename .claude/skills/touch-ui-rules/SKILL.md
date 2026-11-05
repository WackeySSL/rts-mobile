---
name: touch-ui-rules
description: Touch controls, camera, HUD and layout rules for rts-mobile on phones in landscape and portrait (ADR 0015) - gesture map, thresholds, hit areas in dp, the corner HUD and the build drawer (ADR 0025), safe areas, text sizes and feedback. Use whenever building or reviewing input handling, camera, selection, HUD, the build menu, menus or any on-screen control.
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
| Tap the radar scope | Unfold the full map under it |
| Tap or drag the full map | Move the camera there; with units selected a long-press moves them there |
| Tap a unit card | Queue one (`QUEUE`, paid at once) |
| Long-press a card | Cancel the last one of its type in the queue (`CANCEL`, full refund); nothing if none is queued; further holds do nothing until the queue shows the cancel |
| Any gesture on the map | Also closes the open drawer, full map (unless pinned) or economy card; the gesture still does its work; a touch on a HUD control never closes them |
| Tap BUILD | Open the build drawer |
| Swipe the drawer toward its edge (portrait: from its handle or its tabs) | Close it (`drawer_swipe_dp`) |
| Tap the Ready chip | Open the drawer on the Structures tab, the ready card in view |
| Tap the pill's menu button | Pause the match and open the pause menu |
| Tap the credits or the power in the pill | Show the economy card; the next touch closes it |
| Tap the attack toast | Jump the camera to the attack |
| Tap Deselect at the command bar's start | Clear the selection (no Command); the bar hides, except during placement or a strike aim, when it keeps its place |
| Tap Stop | Stop the selected units (`STOP`) |
| Tap a group / "+" / long-press a group | Select it / save the selection in the lowest free group / overwrite it |

There is no Attack button and no attack-move mode (Michael, 2026-11-02, ADR 0025 answer 4): a tap
on the ground moves, a tap on an enemy attacks.

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
ADR 0019 §2 (Michael's answer 1 B), ADR 0024 §10. Placement mode is local input state; no Command
until confirm.
- Placement begins with a tap on a ready structure's card. The ghost starts at the tile under the
  view centre. A one-finger drag that starts on the ghost (its silhouette plus the grab margin,
  ADR 0023 §3) moves it; it follows the finger 64 dp above the touch point, so the finger never
  hides it, and snaps to tiles. A tap on the ghost's own silhouette leaves it where it is; a tap in
  the grab ring round it, or anywhere else on the ground, moves it to that tile. A one-finger drag
  that starts elsewhere pans as usual; pinch and two-finger pan are unchanged; the long-press box
  select is off. The lift and the grab margin are `ghost_lift_dp` (64) and `ghost_grab_dp` (24) in
  `data/input_settings.tres`.
- Placement and the strike aim exclude each other: entering one ends the other with no Command (the
  structure stays ready), so one mode owns the map's taps.
- Edge pan: while a dragged ghost is within `edge_band_dp` (32) of an edge of the map view, the
  camera pans toward that edge at `edge_pan_dp_per_s` (300) of screen at any zoom, one frame
  scrolling for at most `edge_pan_max_step_ms` (100), all in `data/input_settings.tres`. The top
  band counts from the lifted ghost point, the left, right and bottom bands from the finger. The
  bands lie inside the safe area, and in portrait the bottom band ends at the build menu's real top
  (`HudLayout.menu_top_px`: the strip's top, or the open band's when the menu is pinned; with ADR
  0025's drawer, which placement always closes, the safe bottom).
- Valid tiles are tinted green with a solid outline, invalid red with a hatch and the reason's
  glyph (never colour alone), from `Placement.reason` on the snapshot. Confirm with a check-mark
  button, cancel with an X, each at least 64 dp, beside the ghost: a column right of its
  silhouette, `ghost_grab_dp` + 8 dp out so it never covers the grab ring, flipped left (then
  above) near an edge or a HUD control, inside the safe area and above the build menu; hidden while
  the ghost is dragged, shown again on release. The check mark is dimmed while the ghost does not
  fit, while a PLACE is pending and while it is "Blocked"; the X works in every state. Never place a
  building on touch release alone.
- After confirm the ghost waits ("pending") until the snapshot shows the building; if the
  structure is still ready one published tick after the Command's tick, it turns invalid with
  "Blocked" (the word under the glyph; moving the ghost clears it). Cancel keeps the structure
  ready. A turn keeps the ghost's tile and sends nothing; the check mark and X stay beside the
  ghost.
- Placement closes the build drawer, and it stays closed when a build, the X, a strike aim or the
  match's end ends placement; BUILD brings it back (Michael, 2026-11-05).
- Placement begins with a tap on a "Ready" structure card; ADR 0026's place-first switch (P130)
  is not built (Michael, 2026-11-05).

## Corner HUD and build drawer (ADR 0025)
Plan rows P119-P125 (`docs/plans/2026-11-01-hud-v2.md`) build it; until a row merges, the part it
replaces works as ADR 0024 decided (the open or collapsed menu, the strip and the plate), and the
plan's "Interim places" say where each part stands meanwhile.
- In battle only the corners show: the pill (menu, credits, power) top left, the radar scope top
  right, BUILD bottom right, the strike button (72 dp) above BUILD when owned, the group column on
  the left edge under the pill, and the command bar bottom left while something is selected, ending
  short of BUILD. Upright keeps the same corners (Michael, 2026-11-05): no lift, BUILD stays in its
  corner; the Ready chip stands left of BUILD sideways and above the strike button (or BUILD)
  upright. One function places them (`HudCorners.place`), mirror-ready; ADR 0025 §2's table gives
  the numbers on the short screens. Placement and the strike aim freeze the bar's slot, so nothing
  moves under the thumb while the player places or aims.
- One unfold at a time: the build drawer, the full map, the economy card, the pause menu. A map
  gesture closes it (not a pinned full map, not pause) and still does its work; the game runs on
  behind all but pause, which pauses the match. A match starts with nothing unfolded.
- The drawer: landscape a side panel from the right (40 % of the width, 312 to 420 dp), portrait a
  bottom sheet of half the height; the economy pill stays in its corner (Michael, 2026-11-05); the
  tabs with names (Structures, Infantry, Vehicles) with the close chevron at the row's end, and the
  swipe; the card grid (cards at least 88 x 96 dp, as many columns as fit (two or more on every
  supported screen), stretched so a full row ends at the right edge; it scrolls on short screens).
  No queue row: a long press on a card cancels. It slides over `menu_slide_ms`; no pin. It opens on
  BUILD and on a producer's selection (its tab); never on its own after a placement (Michael,
  2026-11-05).
- The command bar: Deselect (48 x 64 dp) at its start, then the selection chip, then the orders the
  game has (Stop for units; none for a building). Deselect and the orders always fit; the chips take
  what is left, then "+N". No Attack
  button. Later orders join the list with a glyph and a HOW_TO_PLAY line.
- The groups: "All army" on top, the saved groups, "+" while units are selected and a group is free;
  56 dp buttons, more columns where one does not fit.
- The full map closes after `radar_close_ms` without a touch unless pinned; the scope is never
  offline.
- Under attack: a toast at the top (tap to jump), a marker on the scope's rim and a ping on the
  full map; while the full map is open only the ping.

## Layout in both orientations
- Same sizes as landscape on the same phone: a portrait window uses the base size 720x1280 instead
  of 1280x720 (ADR 0015 §2, from P59), so the stretch, every dp and every base-px size match.
  Decide the shape only through `UiScale`'s orientation function (P59; height > width is
  portrait).
- Where each part stands: the section above and ADR 0025 §2's table.
- Upright the battle screen has no bottom stack (the corners as sideways, Michael, 2026-11-05); a
  later bottom stack would take at most 40% of the safe height. The drawer is transient and may take
  half.
- No ads on this screen, except one banner at the foot of the open pause menu where the foot is
  free (`admob-policy`; Michael, 2026-11-05).
- Keep every control inside `DisplayServer.get_display_safe_area()`; safe areas: the same
  `SafeAreaMargin` rule (both sides of an axis get the larger inset).
- A turn keeps the camera centre and the world size per dp (ADR 0015 §4) and cancels gestures in
  flight; it never issues a Command.

## Text and feedback
- At least 14 sp body text and 18 sp HUD numbers. Never use colour alone for meaning; team
  colours also differ by marker shape.
- Fonts: Big Shoulders for buttons and titles (upper case), Chakra Petch for numbers (tabular) and
  body, from `theme.tres` only (ADR 0025 §13).
- Every command gets instant feedback: selection ring, move marker, short sound, optional light
  haptic (`Input.vibrate_handheld(15)`, can be turned off in settings).
- Under attack: a toast with a jump, a marker on the radar scope's rim and a ping on the full map.

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
