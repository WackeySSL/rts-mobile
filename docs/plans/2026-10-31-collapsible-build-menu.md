# Plan: the collapsible build menu and the placement controls at the ghost

Date: 2026-10-31. Base: `main` at 81c9b61. Decision: `docs/adr/0024-collapsible-build-menu-and-
placement-controls-at-the-ghost.md` (**accepted** 2026-10-31 on #255; its three questions answered
the same day: 1 A, 2 A, 3 A). Phase: 3 (the battle-screen HUD of ROADMAP Phase 3, box 3's portrait
check). Rows in the style of `docs/plans/2026-10-22-phase-3.md`; they join its lanes as a new
thread, G2.

**Status.** Accepted, 2026-10-31 (Michael, on #255: "ADR 0024 accepted"); the lead's docs row P26ao
recorded it in the same PR, and the rows below are plain rows. Michael answered ADR 0024's questions
on 2026-10-31: the Ready badge opens the menu on the Structures tab (1 A), a pinned menu stays open
during placement (2 A), and a tap on an own producer opens the menu on its tab (3 A); he also said
yes to the `touch-ui-rules` text of ADR 0024 §11 once the ADR is accepted. On the review's two
points he answered: after a build or the X the menu returns to the state placement began in, and a
strike aim that ends placement leaves it collapsed (R1); the 96 dp strip is accepted, to be judged
on the phone, its height in one constant (R2). P86b (#253, 6e845b5) and P88 (#254, 610e513) merged
first, as they were (Michael's L4, ADR 0024's Context), and P85e (#252, 62f76bb) with them; the rows
below build on `main` at 610e513.

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
  check mark still sends the one `PLACE` of P86b; the Ready badge only opens the menu on the
  Structures tab (Q1 A), and placement still begins with `PlacementController.begin` from the
  READY card.
- **Data:** `InputSettings.menu_slide_ms: int = 160` and its line in `data/input_settings.tres`
  (`tests/ui/test_input_settings.gd` pins script default = file). The ghost buttons' gap reads the
  existing `ghost_grab_dp`. Layout sizes stay `HudLayout` constants in dp, as today.
- **Save data:** `user://settings.cfg`, section `hud`, key `build_menu_pinned` (bool, default
  false), through `ConfigFile` in `game/meta/HudPrefs.gd`. Not in a replay, not in a hash.

## Test plan (what is proven headless)
All in gdUnit4 at the six sizes of `tests/support/screen_sizes.gd` and the portrait profiles; no
timing run (the perf suites only run inside `verify.sh` as usual).
- **Layout, both states, both orientations:** every visible control inside the safe rect, at least
  48 dp (the ghost buttons 64 dp), no overlap; portrait: the strip 96 dp on the safe bottom edge,
  the ArmyBar 8 dp above the strip or the band, the strike row above the ArmyBar line, the bottom
  stack within 40 % of the safe height (open and collapsed), the minimap visible in both states with
  the same width on the phone profiles; landscape: the plate 56 dp at the bottom right, the pill and
  `MinimapSlot` unchanged, the SelectionPanel's band unchanged by a collapse; the pin at the menu's
  top-right corner in both.
- **The zone and the real top:** at every step of a stepped slide, `HudLayout.bottom_zone_dp`
  equals the menu holder's drawn height and `HudLayout.menu_top_px` its rect's top on the screen;
  the ArmyBar's bottom is 8 dp above it (within 1 px); P86b's `edge_heading` turns south at the
  strip's top while unpinned and at the open band's top while pinned (Q2 A), also with a portrait
  top cutout (`ui_profiles.with_safe_area`), where the band sits higher than the safe rect's bottom
  less its height. The minimap keeps one size through a slide and has the same size in both states
  on the phone profiles (its room comes from the target state, ADR 0024 §2).
- **No allocation per slide frame:** the lifts read the dp, the orientation and the safe area that
  were cached on the last `size_changed` (as P86b's `read_metrics` does); the test changes the
  `UiScale` override after the cache and steps the slide, and the lifts still use the cached values,
  so no frame calls `UiScale.current()` (which builds a `UiMetrics` without an override).
- **Triggers** (presses pushed through the viewport, as the scene suites do): a tap, a double-tap, a
  long-press, a pan and a pinch on the map collapse the menu and still do their own work (a move is
  queued, a selection made); a tap on the ArmyBar, the SelectionPanel, the minimap, a tab, a card, a
  long-press on a card and a scroll of the item row do not; entering placement collapses; the end of
  placement by a build or the X opens the menu again (placement begins on a card, in the open menu),
  and a strike aim that ends placement leaves it collapsed (R1); a tap on the Ready badge opens the
  menu on the Structures tab with the READY card in view and starts no placement; the events of a
  turn's `cancel_all()` do not collapse; a turn keeps the state; a new match starts open; pinned,
  nothing collapses, placement included (Q2 A): the cards stay shown while the ghost is out.
- **The producer tap** (Q3 A): one tap on an own vehicle factory ends with the menu open on
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
  the grab ring (`ghost_grab_dp` + 8 dp from the silhouette box); with the pinned open band in
  portrait, the buttons stand above the band's real top and clear of it at the six sizes. In the
  scene: hidden while the recognizer is in `GRAB` and through an edge pan, shown on release beside
  the new tile; the check mark dimmed by `can_confirm()` (not fitting, pending, "Blocked"), the X
  live in all three; one press on the check mark sends exactly one `PLACE` and the recognizer sees
  no `TAP`; a press in the grab ring still grabs; a turn keeps the buttons beside the ghost at both
  orientations' sizes.
- **View only:** a scripted main-scene run with collapses, opens, a pin, slides and a placement ends
  with the same state hash as the run with the same Commands and no menu actions (P62's method).

## Work packages and PRs
Sizes are production lines (tests, fixtures, SVG and `.tres` do not count); a row whose first
commit passes 400 takes its named split.

| Row | Lane | Owner | Title | Size | Depends | Box |
| --- | --- | --- | --- | --- | --- | --- |
| P26ao | - | lead | docs: ADR 0024 on acceptance (status, the `touch-ui-rules` text of ADR 0024 §11 with Michael's yes, ADR 0019 §2's note, the rows in the phase 3 plan); folded into #255 | 0 | ADR 0024's PR, Michael's acceptance (2026-10-31) | - |
| P85g | E | art-director | art: the build menu's glyphs `glyph_menu_open`, `glyph_pin`, `glyph_pin_off` (128 x 128 viewBox, white and grey, tinted at run time, like `glyph_check`), gallery entry | SVG | P26ao | - |
| P86c | G2 | touch-ux-dev | input/ui: the check mark and X beside the ghost (`GhostControls`), `PlacementControls` and its card-row place removed | 170 | P86b, P88, P26ao | - |
| P85f | G2 | touch-ux-dev | ui: the collapsible build menu (states, strip and plate, triggers, the slide, the Ready badge, the pin and its save) | 380, split P85f2 | P86c, P85g, P85e, P26ao | box 3's phone check waits for it |
| P85f2 | G2 | touch-ux-dev | ui/meta: the pin and its save (`HudPrefs`), if P85f splits | 100 | P85f | - |

**Lane order.** G2 is touch-ux-dev's new HUD thread: P86c → P85f (→ P85f2). It starts when #255 (ADR
0024 with P26ao) has merged; P86b and P88 already have. Lane G keeps P88 → P88b → P90; lane E takes
P85g at once after P26ao. P86c comes **before** P85f because P85f collapses the menu during
placement, which would hide the card-row check mark and X; with P86c merged they are at the ghost.

**Critical path.** The phase 3 gate path (P88 → P88b → P90 → P94 → P93b) does not wait for these
rows; G2's chain (P86c → P85f, three slots with P85f2) runs beside it and ends earlier. Box 3's
portrait phone check ("build an item with one hand, jump with the minimap, rotate during a
placement") should run after P85f, so that Michael checks the layout that ships.

### P86c input/ui: the check mark and X beside the ghost (touch-ux-dev)
- Files: new `game/ui/GhostControls.gd` (the two buttons, the static placement function, the
  per-frame follow while placement is on); `game/ui/PlacementControls.gd` deleted; `BuildSidebar.gd`
  loses `_actions`, its call to `PlacementControls.set_row_dp` and `_on_placement_changed`, and
  writes `HudLayout.menu_top_px` (new: the menu's rect top on the screen, base px) in `_place`;
  `PlacementController.gd` gains `dragging` and `silhouette_rect()` (the `_near` box with no margin,
  base px), and `edge_heading`'s bottom becomes `HudLayout.menu_top_px` instead of `_safe.end.y -
  bottom_zone_dp` (ADR 0024 §4); `TouchInput.gd` sets `dragging` while the recognizer is in `GRAB`;
  `scenes/main.tscn` adds `Hud/GhostControls` before `SafeArea`, with `theme = theme.tres` as
  `BoxOverlay` has. Tests: `tests/ui/test_placement_controls.gd` becomes
  `tests/ui/test_ghost_controls.gd`; the P86/P86b input suites that read the card-row buttons move
  to the new node.
- Acceptance: ADR 0024 §10 at the six sizes, the portrait profiles and the two short landscape
  profiles `web_phone_small` (800 x 304 dp) and `web_phone` (914 x 355 dp), where the column's 144
  dp is about half the height: the column right of the silhouette at `ghost_grab_dp` + 8 dp, left
  near the right edge, above when neither side fits, inside the safe rect above
  `HudLayout.menu_top_px`, clear of every visible HUD control or (fallback) under it; 64 dp each;
  hidden during a ghost drag and its edge pan, shown on release; dimmed check mark by
  `can_confirm()`; one press = one `PLACE`, no `TAP`; the card row shows its cards during placement
  (until P85f, the open menu stays open, as a pinned menu will after it: the buttons then stand
  above the open band's real top, which is the case P85f's pinned tests keep). With a portrait top
  cutout (`ui_profiles.with_safe_area`) `menu_top_px` is the band's drawn top, and P86b's edge band
  and the buttons end there, not inside the band. No allocation in the per-frame follow.
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
  ADR 0024 §2-§4; `STRIP_DP` is the strip's one height, Michael's R2), `ArmyBar.gd` and
  `StrikeControls.gd` (a lift that follows `zone_changed` with cached metrics; `StrikeControls`'s
  theme overrides stay in `_apply_dp` on `size_changed`), `TouchInput.gd`
  (`map_gesture` before routing the first event of a map gesture, and on a wheel step),
  `InputSettings.gd` and `data/input_settings.tres` (`menu_slide_ms`), new `game/meta/HudPrefs.gd`,
  `theme.tres` (the badge's plate: the READY banner's look), `scenes/main.tscn` (exports and the
  `map_gesture` connection), `tests/support/` (one helper that sets and clears the `HudPrefs` path
  override and the slide override; the scene suites of other owners call it, a cross-owner edit
  P85f lists in its PR). Split trigger: P85f2 takes the pin and `HudPrefs` (the pin then shows in
  P85f2, and P85f keeps the default unpinned); `BAND_FLOOR_DP` 188 and `PANEL_MIN_DP` 232 exist for
  the pin, so they move with it to P85f2 (P85f keeps 172 and 184).
- Acceptance: ADR 0024 §1-§9 by the test plan above (layout, the real top, triggers, the producer
  tap, the slide, the pin, no allocation per slide frame, view only); P86b's edge-pan suite passes
  with the strip, the pinned band and a portrait top cutout; P88's `test_minimap_layout` passes in
  both states, the minimap's room taken from the target state (88 dp in the strip, the band less
  8 + 48 + 8 dp in the open band), so the minimap has one size on the phone profiles in both states
  and through a slide; the Ready badge hides while placement runs; a strike aim that ends placement
  leaves the menu collapsed (R1); the band's floor is 188 dp and the landscape panel's least width
  232 dp at every size (in P85f2 if it splits). No suite reads or writes the real
  `user://settings.cfg` (the helper's override), and no suite mutates the loaded
  `input_settings.tres`. On the phone preview (the PR says how): touch the map, the menu
  slides down to the strip; tap Build, it slides up; pin it, wait a moment, reload the page, still
  pinned. If `OS.is_userfs_persistent()` is false on the preview, the pin lasts for the session on
  the web and the PR says so (Android is the target; ADR 0024 §7).
- HOW_TO_PLAY (Build menu), with Teach on the first three:
  - "Touch the map (drag, pinch, tap, hold) → the build menu slides down out of the way and your
    touch does what it always does. Upright a strip stays at the bottom: your credits and power, the
    Build button, a "Ready" badge when a building is finished, and the minimap. Sideways a small
    plate stays at the bottom right with the Build button and the badge; the credits pill and the
    minimap stay where they are. Touches on the buttons, the army bar, the minimap or the menu
    itself never close it" (yes)
  - "Tap Build → the menu slides back up. It also opens when you tap your Headquarters, barracks or
    vehicle factory (on the tab it builds), and when you finish or cancel a placement you began from
    a card" (yes)
  - "Tap the pin (lock) at the menu's top right → the menu stays open until you unpin it, also while
    you place a building (the check mark and the X stand beside the ghost above it); the game
    remembers it on this device. Unpinned is the default" (yes)
  - "Tap the "Ready" badge → the menu opens on the Structures tab with the finished building's card
    in view; tap that card to place it"
  - The "Look at the screen with the phone sideways/upright" rows add the collapsed forms and say a
    match starts with the menu open; the Army bar section's upright note says the bar rides on the
    menu's top; the placement rows say placement pulls the menu down unless it is pinned, and that
    the menu comes back up when you build or cancel (a strike aim that ends placement leaves it
    down); the Ready badge hides while you place.

### P85f2 ui/meta: the pin and its save (touch-ux-dev; P85f's named split)
- The pin toggle in both corners, its glyphs, `game/meta/HudPrefs.gd`, the pinned rule in the
  triggers, the pin's HOW_TO_PLAY row. Acceptance: the pin part of the test plan; the preview check
  of a reload.

### P85g art: the build menu's glyphs (art-director)
- Three hand-written SVG glyphs in `assets/art/svg/icons/` in the style of the existing glyphs
  (`glyph_check`, `glyph_cross`, the tab icons): `glyph_menu_open` (a chevron up over a row of
  cards), `glyph_pin` (a pin pushed in, upright) and `glyph_pin_off` (the same pin tilted and
  lifted), told apart by shape alone; no `CREDITS.md` line (authored here). The three join
  `HUD_GLYPHS` in `tests/art/test_icon_art.gd`, STYLE.md's tint table and shape table
  (`assets/art/STYLE.md`, beside `glyph_check` and `glyph_cross`) and the HUD glyph page of
  `game/view/art_gallery.gd`.
- Acceptance: `tests/art/test_icon_art.gd` passes with them: the icon folder equals STYLE.md's
  list, every icon a 128 px canvas of greys only, its shape named in one line, ink clear of the
  outer 2 px, the HUD glyphs (`glyph_pin` and `glyph_pin_off` among them) read apart at 32 px in
  greyscale, and STYLE.md names every icon and its tint. Michael sees them in the art gallery.

### P26ao docs: ADR 0024 on acceptance (lead; done, folded into #255)
- Done on 2026-10-31: ADR 0024's status (accepted on #255); the `touch-ui-rules` text quoted in
  ADR 0024 §11 (Michael's yes of 2026-10-31), which also brings the skill's "Building placement"
  section up to P86 and P86b (the tap on the silhouette and in the grab ring, `ghost_lift_dp` and
  `ghost_grab_dp`, placement and the strike aim excluding each other, the edge-pan settings and
  bands) and its layout bullets to the menu's two states; a dated note on ADR 0019 §2 (P86b's
  pending, "Blocked" and edge pan as merged); in the phase 3 plan, wave t as merged, the row P88b,
  the rows of this plan (lane G2) as pointers here, and P26ao's own section.
- Left for the lead's docs row after P86c and P85f: the dated notes of ADR 0024 §11 on ADRs 0015
  §5, 0019 §1 and §4 and 0023 §12, written against the code as merged.

## Interactions with other rows
- **P88b** (the minimap's long-press `MOVE`, lane G): the minimap is a HUD control, so its tap, drag
  and long-press never collapse the menu; in portrait it rides down with the strip (same width on
  phones), so P88b reads its press point in the minimap's own coordinates at press time, as P88's
  jump does. P88b's six-size cases run in both menu states once P85f has merged (whichever of the
  two merges second adds them).
- **P89** (low-power pulse and under-attack cues, lane I): P89, P86c and P85f all edit
  `BuildSidebar.gd`; each starts after the other's merge (P86c before or after P89, then P85f),
  never two at once, and the lead verifies the combined tree once. P89's pulse goes on the status
  line node, so it shows in the pill, the open band and the strip; its bottom-edge arrows stay above
  `HudLayout.menu_top_px` and follow `zone_changed`.
- **P90** (result screen, Surrender, lane G): the result overlay covers the HUD; "Play again" starts
  the new match with the menu open (ADR 0024 §1). The Surrender button is a top-left control and
  does not meet the strip or the plate; P90's re-check of the portrait SelectionPanel line is
  unaffected. P90 and P85f both add nodes to `scenes/main.tscn`: the second rebases.
- **P86b and P88:** merged as they were (L4; #253, #254). P86c and P85f change their files
  afterwards: P86b's `PlacementControls` lines go with the file in P86c, and P88's `Body` row gets
  the strip's layout in P85f.

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
- **Two touch-ux-dev threads on `BuildSidebar.gd`** (G2's P86c and P85f, I's P89): serialised as
  above.
