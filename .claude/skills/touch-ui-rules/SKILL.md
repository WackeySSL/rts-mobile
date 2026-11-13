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
| Tap enemy with units selected | Attack it with the selected units that can hit it (a mixed selection attacks with those rows only); if none can hit it, nothing happens: a short shake, and the selection is kept |
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
| Tap Deselect at the command bar's start | Clear the selection (no Command); the bar hides, except during placement, a strike aim or an order aim (Board, Unload, Mine), when it keeps its place |
| Tap Stop | Stop the selected units (`STOP`) |
| Tap Home (aircraft selected) | Each selected aircraft flies to its own airfield's pad (`REPAIR`), reloads and is repaired there; no aim |
| Tap Repair (damaged ground units selected) | They drive to the nearest own repair building that serves them (`REPAIR`) and are repaired there; no aim |
| Tap Board, an own carrier, the check mark | The selected squads board it (`LOAD`); the carrier comes to them |
| Tap Unload, the ground, the check mark | The selected loaded carriers go there and unload (`UNLOAD`) |
| Tap Mine, the ground, the check mark | Each selected minelayer lays one mine round that point (`LAY_MINE`) |
| Tap ground on a found enemy mine with minelayers selected | Move there (a plain move); a minelayer standing on it clears it |
| Tap Hold (units selected) | Hold position on or off for all of them (`STANCE`) |
| Tap Mend (an own building selected) | Its paid repair on or off (`MEND`) |
| Tap Sell twice (an own building selected) | Sell it (`SELL`): the first tap arms, the second sends (the window in "Orders and their aims") |
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
- Aircraft are picked at their lifted point (the ground point raised by the art's `fly_px`, or
  `low_fly_px` for drone squads), with the same least radius of 24 dp. A ground unit beneath stays
  tappable at its own point. Where two pick discs of one pick rank overlap, the flyer wins; the
  rank order above still comes first, so with own units selected an enemy ground unit beats an
  own flyer. A ground unit hidden under a flyer of its rank is reached by a box or a double-tap on
  another of its type; a lone one by a box only. With units selected, a tap on an enemy that none
  of them can hit does nothing: a short shake, and the selection is kept.

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
- Placement, the strike aim and the order aims (Board, Unload, Mine) exclude each other: entering
  one ends the others with no Command (the structure stays ready), so one mode owns the map's taps.
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
- Placement closes the build drawer. It stays closed when placement ends (a build, the X, a strike
  aim, the match's end); BUILD brings it back (Michael, 2026-11-05).
- Placement begins with a tap on a "Ready" structure card; ADR 0026's place-first switch (P130)
  is not built (Michael, 2026-11-05).

## Orders and their aims (ADR 0036 §12, ADR 0037 §9)
- No tap overload. Outside an open aim, a tap on an own unit or building always selects it,
  whatever is selected and whatever it is (an airfield, a carrier, a repair building). Orders
  that name an own target come only from the command bar. During an aim, a tap on an own unit or
  building other than the Board target is refused with a shake and no Command. A hold never
  sells, lays, loads or repairs.
- **Home** (aircraft selected): one tap sends each aircraft to its own airfield's pad (`REPAIR`),
  where it reloads and is repaired for credits. An aircraft whose airfield has no free pad, or
  that has no airfield, is left out. No aim.
- **Repair** (damaged ground units selected that a complete own repair building serves): one tap
  sends one `REPAIR` with those units to the nearest serving building, by straight distance from
  their centre. Units it does not serve are left out. No aim. Aircraft never go to a repair
  building, and medics are never a Repair target.
- **Board** (squads selected and an own carrier on the map, air or ground): tap Board, tap an own
  carrier with a free seat (it gets a ring; any other tap is refused with a shake and no Command),
  then the check mark: one `LOAD`. The carrier comes to the squads.
- **Unload** (a loaded carrier selected): tap Unload, tap the ground (a chevron marks the point;
  another ground tap moves it), then the check mark: one `UNLOAD` for the selected loaded
  carriers. Squads with no room at the point stay aboard.
- **Mine** (minelayers selected): the button shows laid mines over the cap ("7/12") and dims at the
  cap. Tap Mine, tap the ground (a mark and the blast ring show; another ground tap moves them),
  then the check mark: one `LAY_MINE` for the selected minelayers.
- **The aims (Board, Unload, Mine)** follow the strike aim's one-Command, X, turn and exclusion
  rules: the check mark sends exactly one Command and ends the aim; X, a second tap on the same
  button, a turn of the phone, or a selection that no longer holds a row the order serves ends it
  with nothing sent; placement, the strike aim and the order aims exclude each other. The command
  bar's slot stays frozen while an aim is open.
- **Where the aims' check mark and X stand.** Not in the strike aim's row by the strike button
  (`HudCorners.STRIKE_ROW`): beside the aimed point, by `GhostControls`' column rule (right of
  the anchor rect, else left, else above, never below; inside the safe area), each at least
  64 dp. The anchor rect, in place of the ghost's silhouette:
  - Board: the ringed carrier's pick square, its lifted centre plus and minus its pick radius
    (at least 24 dp); no anchor and no check mark until a carrier is ringed;
  - Unload: a 48 dp square round the chevron's ground point;
  - Mine: the bounding box of the blast ring round the mark.
- **Hold** (units selected): a toggle with a shield glyph, lit when every selected unit holds. A tap
  sets all of them to hold, or all to normal when all already hold (one `STANCE`). The selection
  chip shows a small shield on a type whose units hold. No world glyph.
- **Mend** (one own complete building selected): a toggle with a wrench glyph and the word MEND,
  lit while that building mends; a tap sends one `MEND`, on or off. It stops by itself at full
  health. The word differs from the units' Repair. An enemy building never shows its switch.
- **Sell** (one own complete building with a price selected; never the Headquarters or a site):
  the first tap arms it: it turns amber and shows "+N", the refund now. A second tap sends one
  `SELL`, with a buzz, only between `sell_arm_min_ms` (400) and `sell_confirm_ms` (3000) after
  the first. A second tap before `sell_arm_min_ms` is ignored and keeps the arm. Any other touch,
  or the window running out, disarms it with nothing sent. Never a hold: a resting thumb must not
  sell. The Sell button keeps its place and a fixed width, sized for the widest "+N", so the
  refund never shifts it or its neighbours.
  - On the player's last production building the second tap opens the question card that
    Surrender uses: "Selling it loses the match", Keep / Sell. Only Sell sends the Command; Keep,
    a tap outside the card or a turn of the phone closes it with nothing sent.
- `sell_arm_min_ms` and `sell_confirm_ms` live in `data/input_settings.tres`. Each order adds its
  glyph and its HOW_TO_PLAY line in the row that ships it.

## Corner HUD and build drawer (ADR 0025)
Plan rows P119-P125 (`docs/plans/2026-11-01-hud-v2.md`) build it; until a row merges, the part it
replaces works as ADR 0024 decided (the open or collapsed menu, the strip and the plate), and the
plan's "Interim places" say where each part stands meanwhile.
- In battle only the corners show: the pill (menu, credits, power) top left, the radar scope top
  right, BUILD bottom right, the strike button (72 dp) above BUILD when owned, the group column on
  the left edge under the pill, and the command bar bottom left while something is selected, ending
  short of BUILD. Upright keeps the same corners, with no lift (Michael, 2026-11-05); the Ready
  chip stands left of BUILD sideways and above the strike button (or BUILD) upright. The enemy
  sweep's badge (48 dp, no touch, P235) stands at the right edge a gap above the strike button
  (or BUILD; upright the Ready chip when it stands higher), lit while an enemy sweep is on and
  dimmed with a pause mark while it is paused. Its warning line (160 to 220 dp, left out when
  less room is free) stands to its left after the sweep is fired. Both hide under the drawer,
  the full map and the pause menu (Michael's yes, 2026-11-13). One function
  places them (`HudCorners.place`), mirror-ready; ADR 0025 §2's table gives the numbers on the
  short screens. Placement and the strike aim freeze the bar's slot, so nothing moves under the
  thumb while the player places or aims.
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
- The command bar: Deselect (48 x 64 dp) at its start, then the selection chip, then the orders
  the selection has, each at least 56 x 64 dp: for units Stop, Hold, Home (aircraft), Repair
  (damaged ground units that an own repair building serves), Board (squads, while the player has a
  carrier), Unload (a loaded carrier) and Mine (minelayers); for one own building Mend and Sell.
  An order shows only while it can act on part of the selection, and it sends only the rows it
  serves: a mixed selection shows Home and Repair side by side, each for its own rows. Deselect
  and, for units, Stop always show. The other orders follow in the order listed above and scroll
  sideways when they do not fit; a half-cut last button, or a fade at the bar's edge, is the cue.
  The chips take what is left, then "+N". Upright on a 360 dp phone about 264 dp is free for the
  bar: Deselect (48), one chip (40), Stop (56) and two more orders (112) fit before the rest
  scroll. No Attack button. Later orders join the list with a glyph and a HOW_TO_PLAY line.
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
  `SafeAreaMargin` rule (both sides of an axis get the larger inset). The one control that may
  reach past the safe area: upright, the build drawer's card list scrolls on under the gesture bar
  to the screen's bottom edge. Its foot room lets the last row scroll clear, and a tap on the Ready
  chip scrolls that card inside the safe area (Michael, 2026-11-05, P120i).
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
