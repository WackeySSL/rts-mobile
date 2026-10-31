# Plan: the collapsible build menu and the placement controls at the ghost

Date: 2026-10-31. Base: `main` at 81c9b61. Decision: `docs/adr/0024-collapsible-build-menu-and-
placement-controls-at-the-ghost.md` (**proposed**; three questions for Michael). Phase: 3 (the
battle-screen HUD of ROADMAP Phase 3, box 3's portrait check). Rows in the style of
`docs/plans/2026-10-22-phase-3.md`; they join its lanes as a new thread, G2.

**Status.** Proposed. No row starts before the lead's docs row P26ao records Michael's answers.
P86b (`claude/p86b-pending-blocked-edge-pan`, head 78d54a9) and P88 (`claude/p88-minimap`,
32ec566) finish and merge as they are first (Michael's answer 4); the rows below build on both.

## Goal
Michael, 2026-10-31: the check mark and the X of placement move to the building being placed, and
the build menu gets out of the way: by default it retracts when the player is not using it, a tap
on a button brings it back, and a pin keeps it open (remembered on the device).

## Out of scope
- The strike aim's check mark and X (they stay in the strike row, ADR 0023 §10).
- A swipe to open, a timer, a "reduce motion" setting (Phase 5 can set `menu_slide_ms` to 0), any
  other saved setting (Phase 5's settings and local save).
- Any change in `game/sim`, `game/core`, a Command, a definition, `rules.tres` or a hash.

## Affected modules
- `game/ui/`: `BuildSidebar.gd` (the two states, the strip and the plate, the slide, the Ready
  badge, the pin, `zone_changed`), `HudLayout.gd` (`STRIP_DP` 96, `PLATE_DP` 56, `BAND_FLOOR_DP`
  172 → 188, `PANEL_MIN_DP` 184 → 232), `ArmyBar.gd` and `StrikeControls.gd` (follow
  `zone_changed`), new `GhostControls.gd` (replaces `PlacementControls.gd`, which is deleted),
  `theme.tres` (the Ready badge's plate).
- `game/input/`: `TouchInput.gd` (signal `map_gesture`; sets `PlacementController.dragging`),
  `PlacementController.gd` (`dragging`, `silhouette_rect()`), `InputSettings.gd` (`menu_slide_ms`).
- `game/meta/` (new): `HudPrefs.gd`, one key in `user://settings.cfg`.
- `scenes/main.tscn`: `Hud/GhostControls` before `SafeArea`; the new exports and connections.
- `data/input_settings.tres`: `menu_slide_ms = 160`.
- `assets/art/svg/icons/`: `glyph_menu_open.svg`, `glyph_pin.svg`, `glyph_pin_off.svg`.
- Docs: `docs/HOW_TO_PLAY.md` (each row's own lines), and on acceptance ADRs 0015, 0019, 0023 and
  `touch-ui-rules` (P26ao).

## Command and data changes
- **Commands:** none. Collapsing, opening, pinning and where the buttons stand are view state; the
  check mark still sends the one `PLACE` of P86b, the Ready badge (question 1 B) calls the same
  `PlacementController.begin` a READY card calls.
- **Data:** `InputSettings.menu_slide_ms: int = 160` and its line in `data/input_settings.tres`
  (`tests/ui/test_input_settings.gd` pins script default = file). The ghost buttons' gap reads the
  existing `ghost_grab_dp`. Layout sizes stay `HudLayout` constants in dp, as today.
- **Save data:** `user://settings.cfg`, section `hud`, key `build_menu_pinned` (bool, default false),
  through `ConfigFile` in `game/meta/HudPrefs.gd`. Not in a replay, not in a hash.

## Test plan (what is proven headless)
All in gdUnit4 at the six sizes of `tests/support/screen_sizes.gd` and the portrait profiles; no
timing run (the perf suites only run inside `verify.sh` as usual).
- **Layout, both states, both orientations:** every visible control inside the safe rect, at least
  48 dp (the ghost buttons 64 dp), no overlap; portrait: the strip 96 dp on the safe bottom edge, the
  ArmyBar 8 dp above the strip or the band, the strike row above the ArmyBar line, the bottom stack
  within 40 % of the safe height (open and collapsed), the minimap visible in both states with the
  same width on the phone profiles; landscape: the plate 56 dp at the bottom right, the pill and
  `MinimapSlot` unchanged, the SelectionPanel's band unchanged by a collapse; the pin at the menu's
  top-right corner in both.
- **The zone is the real top:** at every step of a stepped slide, `HudLayout.bottom_zone_dp` equals
  the menu holder's drawn height, the ArmyBar's bottom is 8 dp above it (within 1 px), and P86b's
  `edge_heading` turns south at the strip's top, not the band's.
- **Triggers** (presses pushed through the viewport, as the scene suites do): a tap, a double-tap, a
  long-press, a pan and a pinch on the map collapse the menu and still do their own work (a move is
  queued, a selection made); a tap on the ArmyBar, the SelectionPanel, the minimap, a tab, a card, a
  long-press on a card and a scroll of the item row do not; entering placement collapses; the end of
  placement restores the state it began in (from a card: open; from the badge: collapsed); the
  events of a turn's `cancel_all()` do not collapse; a turn keeps the state; a new match starts open;
  pinned, nothing collapses (and, per question 2, placement does not either).
- **The producer tap** (question 3 A): one tap on an own vehicle factory ends with the menu open on
  the Vehicles tab and no slide started (heights equal before and after the frame).
- **The slide:** with `menu_slide_ms` 0 the target shows at once; with 160 and stepped deltas the
  height moves monotonically and reaches the target at 160 ms; a reversal mid-slide continues from
  the current height; a press on the Build button mid-slide is taken; a press under the holder's
  clip edge reaches no hidden control (the `clip_contents` picking fact, proven here on 4.7.2).
- **The pin:** a toggle writes `build_menu_pinned` to the test's own `user://` file; a new sidebar
  reads it; no file and an unreadable file mean unpinned; the real `user://settings.cfg` is never
  written by a test (the path is a parameter).
- **Ghost controls:** the static placement function on crafted rects: right; left near the right
  edge; above when neither side fits; the clamped fallback; slid clear of a HUD rect; never inside
  the grab ring (`ghost_grab_dp` + 8 dp from the silhouette box). In the scene: hidden while the
  recognizer is in `GRAB` and through an edge pan, shown on release beside the new tile; the check
  mark dimmed by `can_confirm()` (not fitting, pending, "Blocked"), the X live in all three; one
  press on the check mark sends exactly one `PLACE` and the recognizer sees no `TAP`; a press in the
  grab ring still grabs; a turn keeps the buttons beside the ghost at both orientations' sizes.
- **View only:** a scripted main-scene run with collapses, opens, a pin, slides and a placement ends
  with the same state hash as the run with the same Commands and no menu actions (P62's method).

## Work packages and PRs
Sizes are production lines (tests, fixtures, SVG and `.tres` do not count); a row whose first
commit passes 400 takes its named split.

| Row | Lane | Owner | Title | Size | Depends | Box |
| --- | --- | --- | --- | --- | --- | --- |
| P26ao | - | lead | docs: ADR 0024 on acceptance (answers, status, dated notes on ADRs 0015 §5, 0019 §1, §2, §4 and 0023 §12, the `touch-ui-rules` text of ADR 0024 §11 with Michael's yes, one pointer line in the phase 3 plan) | 0 | ADR 0024's PR, Michael's answers | - |
| P85g | E | art-director | art: the build menu's glyphs `glyph_menu_open`, `glyph_pin`, `glyph_pin_off` (128 x 128 viewBox, white and grey, tinted at run time, like `glyph_check`), gallery entry | SVG | P26ao | - |
| P86c | G2 | touch-ux-dev | input/ui: the check mark and X beside the ghost (`GhostControls`), `PlacementControls` and its card-row place removed | 170 | P86b, P88, P26ao | - |
| P85f | G2 | touch-ux-dev | ui: the collapsible build menu (states, strip and plate, triggers, the slide, the Ready badge, the pin and its save) | 380, split P85f2 | P86c, P85g, P85e, P26ao | box 3's phone check waits for it |
| P85f2 | G2 | touch-ux-dev | ui/meta: the pin and its save (`HudPrefs`), if P85f splits | 100 | P85f | - |

**Lane order.** G2 is touch-ux-dev's new HUD thread: P86c → P85f (→ P85f2). It starts when P86b,
P88 and P26ao have merged. Lane G keeps P88 → P88b → P90; lane E takes P85g at once after P26ao.
P86c comes **before** P85f because P85f collapses the menu during placement, which would hide the
card-row check mark and X; with P86c merged they are at the ghost.

**Critical path.** The phase 3 gate path (P88 → P88b → P90 → P94 → P93b) does not wait for these
rows; G2's chain (P86c → P85f, three slots with P85f2) runs beside it and ends earlier. Box 3's
portrait phone check ("build an item with one hand, jump with the minimap, rotate during a
placement") should run after P85f, so that Michael checks the layout that ships.

### P86c input/ui: the check mark and X beside the ghost (touch-ux-dev)
- Files: new `game/ui/GhostControls.gd` (the two buttons, the static placement function, the
  per-frame follow while placement is on); `game/ui/PlacementControls.gd` deleted; `BuildSidebar.gd`
  loses `_actions`, `set_row_dp` and `_on_placement_changed`; `PlacementController.gd` gains
  `dragging` and `silhouette_rect()` (the `_near` box with no margin, base px); `TouchInput.gd` sets
  `dragging` while the recognizer is in `GRAB`; `scenes/main.tscn` adds `Hud/GhostControls` before
  `SafeArea`. Tests: `tests/ui/test_placement_controls.gd` becomes `tests/ui/test_ghost_controls.gd`;
  the P86/P86b input suites that read the card-row buttons move to the new node.
- Acceptance: ADR 0024 §10 at the six sizes and the portrait profiles: the column right of the
  silhouette at `ghost_grab_dp` + 8 dp, left near the right edge, above when neither side fits,
  inside the safe rect less `bottom_zone_dp`, clear of every visible HUD control or (fallback) under
  it; 64 dp each; hidden during a ghost drag and its edge pan, shown on release; dimmed check mark by
  `can_confirm()`; one press = one `PLACE`, no `TAP`; the card row shows its cards during placement
  (until P85f, the open menu stays open). No allocation in the per-frame follow.
- HOW_TO_PLAY (Build menu): the row "Tap a finished building" says "a check mark and an X appear
  beside the ghost, on its right (on its left near the right edge of the screen, above it when
  neither side has room); they hide while you drag the ghost and come back when you let go"; the
  row "Turn the phone while the ghost shows" says "the check mark and the X stay beside the ghost"
  (not "move with the build menu"); P86b's "Tap the check mark" row says "the cards stay" instead of
  "the cards come back".

### P85f ui: the collapsible build menu (touch-ux-dev)
- Files: `BuildSidebar.gd` (OPEN and COLLAPSED, the strip, the plate, the head line with the pin,
  the clipping holder and the slide, the Ready badge, `open()`, `collapse()`, `state_changed`,
  `zone_changed`, the restore after placement, the producer open), `HudLayout.gd` (the constants of
  ADR 0024 §2-§4), `ArmyBar.gd` and `StrikeControls.gd` (follow `zone_changed`), `TouchInput.gd`
  (`map_gesture` before routing the first event of a map gesture, and on a wheel step),
  `InputSettings.gd` and `data/input_settings.tres` (`menu_slide_ms`), new `game/meta/HudPrefs.gd`,
  `theme.tres` (the badge's plate: the READY banner's look), `scenes/main.tscn` (exports and the
  `map_gesture` connection). Split trigger: P85f2 takes the pin and `HudPrefs` (the pin then shows
  in P85f2, and P85f keeps the default unpinned).
- Acceptance: ADR 0024 §1-§9 by the test plan above (layout, the real top, triggers, the producer
  tap, the slide, the pin, view only); P86b's edge-pan suite passes with the strip; P88's
  `test_minimap_layout` passes in both states; the band's floor is 188 dp and the landscape panel's
  least width 232 dp at every size. On the phone preview (the PR says how): touch the map, the menu
  slides down to the strip; tap Build, it slides up; pin it, reload the page, still pinned.
- HOW_TO_PLAY (Build menu), with Teach on the first three:
  - "Touch the map (drag, pinch, tap, hold) → the build menu slides down out of the way and your
    touch does what it always does. Upright a strip stays at the bottom: your credits and power, the
    Build button, a "Ready" badge when a building is finished, and the minimap. Sideways a small
    plate stays at the bottom right with the Build button and the badge; the credits pill and the
    minimap stay where they are. Touches on the buttons, the army bar, the minimap or the menu itself
    never close it" (yes)
  - "Tap Build → the menu slides back up. It also opens when you tap your Headquarters, barracks or
    vehicle factory (on the tab it builds), and when you finish or cancel a placement you began from
    a card" (yes; the producer clause per question 3)
  - "Tap the pin (lock) at the menu's top right → the menu stays open until you unpin it; the game
    remembers it on this device. Unpinned is the default" (yes)
  - "Tap the "Ready" badge → placement of the finished building begins at once, as a tap on its card
    does" (question 1 B; with A: "→ the menu opens on the Structures tab")
  - The "Look at the screen with the phone sideways/upright" rows add the collapsed forms and say a
    match starts with the menu open; the Army bar section's upright note says the bar rides on the
    menu's top; the placement rows say placement pulls the menu down (unless pinned, question 2).

### P85f2 ui/meta: the pin and its save (touch-ux-dev; P85f's named split)
- The pin toggle in both corners, its glyphs, `game/meta/HudPrefs.gd`, the pinned rule in the
  triggers, the pin's HOW_TO_PLAY row. Acceptance: the pin part of the test plan; the preview check
  of a reload.

### P85g art: the build menu's glyphs (art-director)
- Three hand-written SVG glyphs in `assets/art/svg/icons/` in the style of the existing glyphs
  (`glyph_check`, `glyph_cross`, the tab icons): `glyph_menu_open` (a chevron up over a row of
  cards), `glyph_pin` (a pin pushed in, upright) and `glyph_pin_off` (the same pin tilted and
  lifted), told apart by shape alone. Gallery entry; no `CREDITS.md` line (authored here).
- Acceptance: `tests/art/test_art_assets.gd`'s rules for the icon glyphs pass for the three; Michael
  sees them in the art gallery.

### P26ao docs: ADR 0024 on acceptance (lead)
- ADR 0024's status and answers; the dated notes of ADR 0024 §11 on ADRs 0015 §5, 0019 §1, §2 and
  §4 and 0023 §12; the `touch-ui-rules` text quoted in ADR 0024 §11 (Michael's yes); in the phase 3
  plan one line in the current "Next" text pointing at this plan, and the rows of this plan in its
  work-package table (lane G2). This plan's PR does not edit the phase 3 plan, because the lead's
  open docs row P26an edits the same file.

## Interactions with other rows
- **P88b** (the minimap's long-press `MOVE`, lane G): the minimap is a HUD control, so its tap,
  drag and long-press never collapse the menu; in portrait it rides down with the strip (same width
  on phones), so P88b reads its press point in the minimap's own coordinates at press time, as P88's
  jump does. P88b's six-size cases run in both menu states once P85f has merged (whichever of the two
  merges second adds them).
- **P89** (low-power pulse and under-attack cues, lane I): both P89 and P85f edit `BuildSidebar.gd`;
  whichever starts second branches after the other's merge, and the lead verifies the combined tree
  once. P89's pulse goes on the status line node, so it shows in the pill, the open band and the
  strip; its bottom-edge arrows stay above `HudLayout.bottom_zone_dp` and follow `zone_changed`.
- **P90** (result screen, Surrender, lane G): the result overlay covers the HUD; "Play again" starts
  the new match with the menu open (ADR 0024 §1). The Surrender button is a top-left control and
  does not meet the strip or the plate; P90's re-check of the portrait SelectionPanel line is
  unaffected. P90 and P85f both add nodes to `scenes/main.tscn`: the second rebases.
- **P86b and P88:** merge as they are (answer 4). P86c and P85f change their files afterwards: P86b's
  `PlacementControls` lines go with the file in P86c, and P88's `Body` row gets the strip's layout in
  P85f.

## Risks
- **The slide's frame cost on the phone** (container re-sorts for about ten frames): the content is
  laid out once at the target size, only heights and margins change per frame; if the phone card or
  Michael sees a hitch, `menu_slide_ms` 0 turns it off in data.
- **Two engine facts taken from documentation:** `clip_contents` also stops picking outside the
  rect, and `user://` persists on the web export. P85f's test proves the first headless; the second
  is a preview check (pin, reload). If the web does not keep it, P85f says so and stops (no
  workaround), and the pin is remembered on Android only until it is solved.
- **Muscle memory:** in portrait the ArmyBar rides about 100 dp when the menu opens or closes; it
  never moves without a tap of the player's (ADR 0024, Consequences).
- **The ghost buttons near the HUD:** in a corner where no candidate fits, the fallback lies under a
  HUD control; the edge pan and a pan move the ghost out. The test plan pins the candidates.
- **Short portrait phones** (under about 660 dp): the open band's floor rises to 188 dp, 16 dp over
  the 40 % share while open; collapsed it is far within it.
- **Two touch-ux-dev threads on `BuildSidebar.gd`** (G2's P85f and I's P89): serialised as above.
