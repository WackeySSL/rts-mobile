# ADR 0019: Build sidebar, placement mode, building orders, minimap and the result screen

Status: proposed, 2026-10-22. Docs PR P68 (with `docs/plans/2026-10-22-phase-3.md`). Builds on ADR
0004 (gestures, `UiScale`), ADR 0015 §5 (layout in both orientations), ADR 0017 (`Placement`) and
ADR 0018 (the rules the UI shows). The UI only reads the snapshot and sends Commands (ADR 0012 §3,
CLAUDE.md rule 4).

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

### 4. Minimap
In the sidebar (top in landscape; at the right end of the portrait band, a square of the band's
inner height, at most 40 % of the safe width). It draws the terrain, the fog (black and dimmed),
own rows, the enemy rows the local player sees, the last-seen ghosts and the camera's frame. It is
one texture, redrawn at fog cadence, not every frame (ADR 0011's draw rules). A tap or a drag on it
moves the camera there; a long-press with units selected sends `MOVE` to that point.

### 5. Low power and under attack
On low power the power-using buildings are drawn dimmed and each defence shows an offline glyph.
When an own row is hit off screen (a `SHOT` or `IMPACT` event on an own target), an arrow of at
least 48 dp at the screen edge points to it for a few seconds and the minimap pings there; one cue
per area and interval (values in `data/input_settings.tres`).

### 6. Result screen and surrender
- When the snapshot shows `match_end_tick`, a full-screen overlay shows Victory, Defeat or Draw (a
  word and an emblem shape), the match time and per player: units built, units lost, buildings
  lost, credits harvested. Buttons: "Play again" (the same scenario, a new match) and "Back" (the
  dev menu). No ad, ever, on the battle screen; Phase 6 decides what comes after this screen.
- A "Surrender" button (at least 48 dp) at the top left, beside the Dev button, opens a confirm
  dialog; yes sends `SURRENDER` (question 3).

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
