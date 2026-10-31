# ADR 0019: Build sidebar, placement mode, building orders, minimap and the result screen

Status: accepted, 2026-10-22 (Michael: 1 B, 2 ja, 3 ja, 4 ja). Proposed 2026-10-22. Docs PR P68
(with `docs/plans/2026-10-22-phase-3.md`), accepted by the lead's row P68b on the same PR (#166).
Builds on ADR 0004 (gestures, `UiScale`), ADR 0015 §5 (layout in both orientations), ADR 0017
(`Placement`) and ADR 0018 (the rules the UI shows). The UI only reads the snapshot and sends
Commands (ADR 0012 §3, CLAUDE.md rule 4).

## Acceptance note (2026-10-22)
Michael answered the questions of ADRs 0017-0021 in chat on 2026-10-22, verbatim "Ja til alle
anbefalinger" (yes to all recommendations), which the lead records for this ADR as "1 B, 2 ja,
3 ja, 4 ja":
1. **B:** in placement mode a one-finger drag that starts on the ghost moves it; any other
   one-finger drag pans as usual (§2). Option A (every drag moves the ghost, two fingers pan) is
   not taken.
2. **ja:** a long-press on a sidebar item cancels the last queued item of that type, with a full
   refund (§1).
3. **ja:** a "Surrender" button at the top left behind a confirm dialog (§6).
4. **ja:** a Phase 3 match starts from Dev → Skirmish; the preview keeps opening on the controls
   test until Phase 5's main menu (§7).

The decision below is unchanged by the acceptance. P68b added one sentence to §6: the Surrender
button narrows the portrait SelectionPanel's line, so its row re-checks that panel's worst case.
Nothing here is applied in code yet: plan rows P84-P90 apply it.

Status note (2026-10-26, P68d docs; ADR 0022 accepted 2026-10-26): §2 and §3 carry dated status
notes on the oblique buildings: the ghost is drawn in ADR 0022's projection and grabbed on its
sprite box plus 24 dp, and a tap anywhere on a building's picture selects it, a unit winning at the
same point. No accepted text changed.

Status note (2026-10-26, P68e docs; ADR 0023 accepted 2026-10-26, Michael's answers 4 A and 7
"ja"): §1-§5 carry dated status notes for the isometric view and the floating panels: in landscape
the build sidebar becomes floating panels, the ghost marks diamonds and is grabbed on its
silhouette, buildings are picked on their silhouettes (units first), the minimap is an isometric
diamond, and low power shows a glyph instead of a dim. No accepted text changed.

Status note (2026-10-26, P26ai docs): §1 and §6 carry dated status notes on the sidebar as P85,
P85c and P85b merged it (the band, the tab names, a fifth tile state) and on the loss stats the
result screen reads. No accepted text changed.

Status note (2026-10-27, P26ak docs): §3 carries a dated status note on building selection as
P115b merged it. No accepted text changed.

Status note (2026-10-30, P26am docs): §3 carries a dated status note that narrows the P26ak note's
attack on an enemy building to the one the sim takes. No accepted text changed.

Status note (2026-10-31, P26an docs): §2 carries a dated status note on placement as P86 merged
it: a tap on the ghost's own silhouette leaves it and the 24 dp ring moves it, the lift and the
grab margin are settings, and placement and the strike aim exclude each other. No accepted text
changed.

## Context
- `touch-ui-rules` already fixes, in its gesture table and its "Building placement" section: tap an
  own building selects it and "a production building opens its build tab"; tap minimap moves the
  camera; long-press minimap with units selected moves them there; the ghost "follows the finger
  64 dp above the touch point"; valid tiles green, invalid red; confirm with a check mark, cancel
  with an X; "Never place a building on touch release alone". "Never use colour alone for meaning."
  "Under attack: edge-of-screen indicator and a minimap ping."
- ADR 0015 §5 fixes the sidebar zone (right edge in landscape, a bottom band in portrait, 20 % and
  at least 200 dp), its contents and budget (three icon-only 48 dp tabs, build icons of at least
  64 dp, a sideways-scrolling icon row in portrait), the minimap's place, and that Phase 3's sidebar
  row sets the portrait zone's height, which P61 reads from one place, so the ArmyBar moves above
  the band; the bottom stack takes at most 40 % of the safe height and the band gives way first.
- ADR 0004 maps a one-finger drag to pan and a 300 ms hold (`long_press_ms`) to the box select on
  the map. A placement ghost needs a drag of its own, which ADR 0004 does not cover.
- The ROADMAP's portrait box asks for a phone check: "build an item with one hand, jump with the
  minimap, rotate during a placement".
- `HOW_TO_PLAY.md`: "Tap 'All army'" selects "every own unit that can move", which would now take
  the harvesters along.

## Decision

### 1. The build sidebar
- One `BuildSidebar` control in the HUD for both orientations, in the zone of ADR 0015 §5. From
  the top (landscape) or left of the minimap (portrait): credits and the power bar, the three tabs,
  the item tiles. It sets the portrait zone's height through P61's one place, so the ArmyBar sits
  directly above the band.
- **Tabs:** Structures, Infantry, Vehicles; icon and name where the zone is wide enough, icon only
  in the portrait band (shapes, not colour alone). Selecting an own production building switches to
  its tab.
- **Item tiles** (at least 64 dp): icon, cost, a progress fill over the icon for the queue's head,
  a count badge for the queued items of that type, and a state shown by a shape as well as a
  colour: available; locked (a lock glyph: a requirement or the tab's producer is missing);
  unaffordable (cost in the warning style with a stripe); ready (structures: a "Ready" banner).
- **Tap** an available tile: `QUEUE` that type, with the light haptic. **Long-press** a tile with
  items queued (`long_press_ms`): `CANCEL` the last queued item of that type (refund), with the
  haptic. Tap a ready structure: enter placement mode. A tap on a locked or unaffordable tile sends
  nothing and shakes the tile.
- The power bar shows made against used; on low power it turns to the warning style with an icon
  and pulses.

Status note (2026-10-26, P68e docs, ADR 0023 accepted 2026-10-26, Michael's answer 4 A; the text
above stays as accepted): from plan row P85d on, `BuildSidebar` in landscape is the canvas's
floating build panel at the bottom right (tabs as line icons above one row of cards of at least
64 dp, each with the item's name always shown), the minimap a floating panel at the top right and
the credits and power bar a pill at the top left (ADR 0023 §12); portrait keeps the band. The
tiles, their states, tap to queue, long-press to cancel, ready structures, the power bar and the
three tabs are unchanged, and the build menu lists only the local player's faction's types
(`type_faction`, ADR 0023 §6).

Status note (2026-10-26, P26ai docs, P85 as merged, #193, P85c, #194, and P85b, #198; the text
and the note above stay as accepted and as dated), on `game/ui/BuildSidebar.gd` and
`ItemTile.gd`:
- **The zone.** The portrait band follows ADR 0015 §5 as that section's note of the same date
  gives it (`HudLayout.band_dp`, 4 dp margins above and below). The tab names show only in
  landscape where all three fit; the band shows icons only.
- **The status line** (P85c): a coin glyph and the credits, then a bolt and the power bar of power
  used against power made, with both numbers where the bar is wide enough; on low power the bar
  is full and amber and the bolt becomes a warning triangle. The pulse and the under-attack cues
  are plan row P89's.
- **A fifth tile state, FULL** (P85b): the item's queue holds `queue_slots` items. It shows the
  stripes of UNAFFORDABLE and differs from it only by the cost's colour (white, against amber for
  money), so it leans on colour alone; touch-ux-dev's follow-up gives it a shape of its own. A tap
  on a READY tile does nothing until plan row P86 enters placement mode there. Selecting an own
  producer opens its tab through `BuildSidebar.set_selected`, wired to
  `PlayerController.selection_changed`; it shows once plan row P115b puts building ids in the
  selection.

### 2. Placement mode
Local input state: no Command until the player confirms.
- Entering puts the ghost at the tile under the view centre. The ghost is the building's sprite
  tinted green with a solid outline (valid) or red with a hatch pattern and the reason's glyph
  (invalid), from `Placement.reason` on the latest snapshot, re-checked when the ghost's tile or
  the snapshot changes.
- **Gestures** (question 1, option B): a one-finger drag that starts on the ghost (its footprint
  plus 24 dp) moves it, the ghost following the finger 64 dp above the touch point and snapping to
  tiles; a one-finger drag that starts elsewhere pans; a tap on the ground moves the ghost to that
  tile; pinch and two-finger pan are unchanged; the long-press box select is off in this mode.
  While the ghost is dragged within 32 dp of the view's edge, the camera pans toward that edge
  (speed in `data/input_settings.tres`).
- **Confirm and cancel:** a check mark and an X, each at least 64 dp, take the place of the item
  row in the sidebar zone while the mode is on, in thumb reach in both orientations. The check mark
  is disabled while the ghost is invalid. Confirm sends `PLACE`; the ghost then waits ("pending")
  until the snapshot shows the building at that origin (the mode ends) or shows the structure still
  ready one published tick after the Command's tick (the ghost turns invalid with "Blocked", and
  the mode stays on). Cancel ends the mode; the structure stays ready.
- **Rotation:** the ghost keeps its tile; the camera keeps its centre (P62); a turn's gesture
  cancel ends a ghost drag without moving the ghost; no Command is sent.

Status note (2026-10-26, P68d docs, ADR 0022 accepted 2026-10-26, Michael's "ja til anbefaling";
the text above stays as accepted): with buildings drawn in an oblique 3/4 view (ADR 0022 §1, §5),
the ghost is the building's whole sprite in that projection, anchored on the footprint's south edge
and faded as one group; the wash, the hatch and the solid frame lie on the footprint rect, and the
reason's glyph at the footprint's centre. The grab area "its footprint plus 24 dp" becomes **the
sprite box plus 24 dp** (the footprint plus the 0.75-tile rise to the north), so a drag that starts
on the roof moves the ghost. The ghost still follows the finger 64 dp above the touch point, with
the footprint's centre as the reference, and snaps to tiles. `GhostLayer` draws at z 145 (plan row
P86). The rest of §2 is unchanged.

Status note (2026-10-26, P68e docs, ADR 0023 accepted 2026-10-26; the text and the note above stay
as accepted and as dated; ADR 0022's oblique ghost does not come): from plan row P86 on, the
footprint's cells are marked as diamonds on the ground (the wash, the hatch and the frame as
diamond tile quads from one texture, per cell, in `GhostLayer` at z 60), with the building's sprite
faded over them; the tile under the reference point is `floor` of `IsoProjection.px_to_ground`;
the grab area is the building's **silhouette plus 24 dp** (ADR 0023 §3). The ghost still follows
the finger 64 dp above the touch point and snaps to tiles. In landscape the check mark and X sit in
the floating build panel in place of the card row (§1's note). The rest of §2 is unchanged.

Status note (2026-10-31, P26an docs, P86 as merged, #246, 8790d2b; the text and the notes above
stay as accepted and as dated):
- **Taps on and near the ghost.** "A tap on the ground moves the ghost to that tile" holds
  everywhere but on the ghost itself: a tap on the ghost's own silhouette (no margin) leaves it
  where it is, and a tap in the 24 dp ring round the silhouette moves it to the tapped tile like
  any other ground tap. A drag that starts on the silhouette or in that ring moves the ghost.
- **The settings.** The lift (64 dp) and the grab margin (24 dp) are `ghost_lift_dp` and
  `ghost_grab_dp` in `data/input_settings.tres`, not constants. The margin is measured across
  each edge of the silhouette, also past the diamond's two lower edges; at the corners of the box
  part it reaches about 1.41 x 24 dp.
- **Placement and the strike aim exclude each other** (P86's choice, in `PlacementController`; ADR
  0023 §10 names only the targeting mode): entering placement ends a
  strike aim, and starting a strike aim ends placement with no Command (the structure stays
  ready), so one mode owns the map's taps.
- **Not yet:** confirm ends the mode at once after its `PLACE`. The pending state, "Blocked" and
  the edge pan are plan row P86b.

### 3. Buildings and harvesters on the map
- Tap an own building: it alone is selected; the selection panel shows it. Buildings never join a
  box selection, a double-tap selection or "All army".
- With an own barracks or vehicle factory selected, a tap on the ground sends `RALLY` and shows the
  tab's rally flag (a flag marker and a line from the building while it is selected). With another
  building selected, a ground tap clears the selection.
- With harvesters selected, a tap on an ore cell sends `HARVEST`; other ground taps move them as
  today.
- "All army" and a box that holds any combat unit leave harvesters out; a box with only harvesters
  selects them.

Status note (2026-10-26, P68d docs, ADR 0022 accepted 2026-10-26, Michael's "ja til anbefaling";
the text above stays as accepted): "Tap an own building" picks on the building's whole picture, the
sprite box (footprint plus the rise, roof included), grown to at least 48 dp a side (ADR 0022 §3).
A unit at the same point wins. The pick order with a selection is enemy unit > own unit > enemy
building > own building; without one, enemies do not count, so own unit > own building; among buildings
of one side the larger footprint south row wins. A building the fog hides and a last-seen ghost are
not pickable. The selection frame goes round the sprite box (ADR 0022 question 2 = A). Plan row P84d
applies it. The rest of §3 is unchanged.

Status note (2026-10-26, P68e docs, ADR 0023 accepted 2026-10-26; the text and the note above stay
as accepted and as dated): "Tap an own building" picks on the building's **silhouette**: the
footprint diamond plus the rectangle between the diamond's left and right corners from the
sprite's top down to the corners' y, at least 48 dp a side at zoom 0.75 (ADR 0023 §3). Units come
first, as the note above says (with a selection enemy unit > own unit > enemy building > own
building; without one own unit > own building); a unit is hit within its pick radius of its lifted
centre; among overlapping buildings the one drawn in front (the larger sort key) wins. The
selection frame is four brackets round the silhouette box. Player-facing harvesters are tankers
and ore is oil and gas (ADR 0018 §3's note). Plan row P115b applies it. The rest of §3 is
unchanged.

Status note (2026-10-27, P26ak docs, P115b as merged, #234; the text and the notes above stay as
accepted and as dated):
- **An enemy building** you see can be tapped with nothing selected: it is selected for its
  information only (an amber frame, its notched bar, its name in the panel) and takes no orders.
  With own units selected, a tap on an enemy building you see attacks it.
- **With a building selected** (own or enemy), only units count as a selection for the pick
  order: own unit > own or seen enemy building, and enemy units do not count. A tap on the ground,
  or on an enemy unit, clears the selection; an empty box clears it too. P87 adds `RALLY` to that
  ground tap for a barracks or a vehicle factory, as the text above says.

Status note (2026-10-30, P26am docs, from the review of P26ak; the notes above stay as dated): the
note above says too much in "With own units selected, a tap on an enemy building you see
attacks it". P115b attacks a shown enemy building only when the sim takes the `ATTACK`
(`PickSnapshot.is_targetable`): the local player sees the cell under the building's position, the
cell `Targeting.sees` asks. One shown only for another cell of its footprint is not attacked: the
tap is a tap on the ground and moves the selected units there. HOW_TO_PLAY's Orders row ("One you
see only at its edge, or the fog hides, is a tap on the ground") already says so.

### 4. Minimap
In the sidebar (top in landscape; at the right end of the portrait band, a square of the band's
inner height, at most 40 % of the safe width). It draws the terrain, the fog (black and dimmed),
own rows, the enemy rows the local player sees, the last-seen ghosts and the camera's frame. It is
one texture, redrawn at fog cadence, not every frame (ADR 0011's draw rules). A tap or a drag on it
moves the camera there; a long-press with units selected sends `MOVE` to that point.

Status note (2026-10-26, P68e docs, ADR 0023 accepted 2026-10-26, Michael's answers 4 A and 7
"ja"; the text above stays as accepted): the minimap is an **isometric diamond** in a 2:1 box (ADR
0023 §4): one cell texture at fog cadence, drawn with the fog's skew, so the camera's frame is a
plain rectangle on it. In landscape it is a floating panel at the top right (§1's note); in
portrait it stays at the right end of the band, at most 40 % of the safe width. What it draws, its
cadence and its gestures are unchanged (plan row P88).

### 5. Low power and under attack
On low power the power-using buildings are drawn dimmed and each defence shows an offline glyph.
When an own row is hit off screen (a `SHOT` or `IMPACT` event on an own target), an arrow of at
least 48 dp at the screen edge points to it for a few seconds and the minimap pings there; one cue
per area and interval (values in `data/input_settings.tres`).

Status note (2026-10-26, P68e docs, ADR 0023 accepted 2026-10-26, Michael's answer 7 "ja"; the
text above stays as accepted): low power no longer dims the power-using buildings; each consuming
building shows a low-power glyph instead (a dim would split the sorted world's one batch, ADR 0023
§2), and the power bar warns as §1 says. Each defence still shows the offline glyph, and a
building a Blackout Array switched off shows it too (ADR 0023 §10). The under-attack cue is
unchanged (plan rows P89, P112b).

### 6. Result screen and surrender
- When the snapshot shows `match_end_tick`, a full-screen overlay shows Victory, Defeat or Draw (a
  word and an emblem shape), the match time and per player: units built, units lost, buildings
  lost, credits harvested. Buttons: "Play again" (the same scenario, a new match) and "Back" (the
  dev menu). No ad, ever, on the battle screen; Phase 6 decides what comes after this screen.
- A "Surrender" button (at least 48 dp) at the top left, beside the Dev button, opens a confirm
  dialog; yes sends `SURRENDER` (question 3). In portrait it is one more top-left control, so the
  SelectionPanel's top line (ADR 0015 §5: from the top-left controls' right edge plus 8 dp) gets
  shorter; the row that adds the button re-checks the panel's worst case at 360 dp (plan row P90).

Status note (2026-10-26, P26ai docs, P76 as merged, #197; the text above stays as accepted): the
loss stats the overlay shows are counted only for a side that has had a producer (ADR 0018 §7's
note of the same date). Every real match has one from its scenario buildings, so the result
screen shows true counts; the perf arena and Worlds of units only show 0.

### 7. Where a match starts in Phase 3
A dev route "Skirmish" loads the battle scene with the skirmish scenario and the dummy opponent as
player 2 (ADR 0020). The preview's main scene keeps the controls-test scenario until Phase 5's main
menu (question 4), so the Phase 1 and 2 scene suites keep their scenario.

## Consequences
- Placement adds a mode to the gesture map; the ghost drag is the only new gesture, and it lives
  only in that mode.
- The sidebar's zone is now real in portrait: the ArmyBar moves up, and the 40 % rule of ADR 0015
  §5 is tested with the real band instead of P61's stand-in.
- Validity is judged twice by the same function (ghost and sim); when they disagree because the
  world moved, the pending ghost shows it.

## Alternatives considered
- **Question 1, option A** (any one-finger drag moves the ghost; pan only with two fingers):
  closer to the skill's "follows the finger", but panning then needs two fingers, which ADR 0015
  §5 found hard in a one-handed portrait grip.
- **Place on release:** forbidden by `touch-ui-rules`.
- **A small X on each queued tile** instead of the long-press: a second target inside a 64 dp tile
  is below 48 dp in the portrait band.
- **Per-building rally points:** ADR 0018 §6 keeps one per tab.

## Questions for Michael
1. While you place a building, how does one finger move the ghost? A: any drag moves it, and you
   pan with two fingers. B: a drag that starts on the ghost moves it, any other drag pans as usual.
   (A/B; recommended: B, so one hand can still pan in portrait)
2. To cancel an item you have queued, you hold its icon in the sidebar (the money comes back). Is
   that the gesture you want? (ja/nej; recommended: ja)
3. Should Phase 3 add a "Surrender" button at the top left, behind a confirm dialog, so a match
   can be ended without being destroyed? (ja/nej; recommended: ja)
4. In Phase 3 you start a match from Dev → Skirmish; the preview still opens on the controls test
   until Phase 5 builds the main menu. Is that fine? (ja/nej; recommended: ja)
