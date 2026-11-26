# ADR 0048: Tutorial guide v2: a docked card with a step counter, a blinking frame, chained targets and gesture hints

**In short, for Michael:** the help card always stands in the same place: at the top of the
screen, just under the row with the credit pill and the round radar, never over them. It has a
small tab in its top-right corner that shows the step, for example "3/26". Tap the tab to fold the
card away. Only the tab stays. The card opens again by itself at every new step. The frame around
the thing to tap blinks. When a step needs more than one tap (BUILD, then the Infantry tab, then
the squad's card), the blinking frame moves to the next thing to tap as you go. If you close the
drawer, it moves back to BUILD. A drawn hand shows the gesture: a tap, a double tap, a long press,
a drag to pan, a box drag and a two-finger pinch. With Reduced effects on, the frame stops
blinking and the hand stands still. This holds for Basics and for all three drills.

Status: **accepted, 2026-11-24 (Michael: "Ja til alle", yes to every recommendation of the five
questions).** Written by the architect on branch `claude/p58x-guide-v2-plan` (base `main` at
53fabb24) with the plan `docs/plans/2026-11-24-guide-v2.md` (rows P582-P596). Accepted in row
P583 on the same branch (PR #634).

Amends ADR 0044 §2 (the `CoachMark` paragraph: "a ring on the anchor and a prompt card (text, Next
where a beat is read-only, Skip lesson), placed by ADR 0015's rules"). P583 writes a dated status
note in ADR 0044 on acceptance (done, 2026-11-24). No accepted text is rewritten. Retires the
free-place search of plan row P543g (#620), which was a plan row, not an ADR (§8).

## Michael's answers (2026-11-24)
1. **Where the card docks:** at the top, under the pill and the radar, between the group buttons and
   the full map, never over them (§1).
2. **The counter:** "3/26", the form `n/N` (§2).
3. **A target under the open card:** A. The card stays, turns see-through and lets the touch
   through, and the frame and the hand show on top (§3).
4. **Skip lesson:** only on each lesson's first card. After that, "Leave tutorial" in the pause menu
   is the way out (it is on `main`: `PauseMenu`'s Exit reads "LEAVE TUTORIAL" in a lesson) (§2).
5. **The hand with Reduced effects:** a still hand in the gesture's key pose, with arrows (§6).

## Michael's request (2026-11-24, after Basics on his phone, upright; the lead's translation)
1. The help text sits in the same place every time, maybe at the very top, and can be folded away.
   It unfolds itself again after each completed step if you closed it.
2. One corner of the box shows how many steps are left before you are through.
3. At each thing you must tap, the frame around it blinks.
4. When you must tap, for example, the air tab and then build something, the thing you must build
   lights up once you are on the right tab. The highlight follows the current sub-target.
5. This goes for all guides: Basics and every drill.
6. Show on screen where to touch, also for pan and zoom: animated gesture hints.

## Context
- `CoachMark` (P542 #576, P543b #593, P543g #620) puts a pulsing ring on the beat's anchor (a HUD
  control by node name, or a world tile) and a prompt card that `place_card` searches a place for:
  below the ring, then above, right and left, then a grid of the room. The card keeps off every
  visible, enabled HUD button and tries narrower widths before it would stand on one. So the card
  jumps from beat to beat, and within a beat when a button appears. That is what Michael saw on
  his phone.
- The ring pulses (it grows 4 dp and back over 0.8 s each way, a Tween). With `reduced` on there
  is no Tween. Both the rate and the colour are constants and theme reads in code.
- A beat has one anchor. Today the lessons split a multi-tap action into separate beats. For
  example `infantry-tab` (ring on BUILD, ends when the drawer is open on Infantry) is followed by
  `train` (ring on `TabInfantry`, ends when six squads exist). So the ring stays on the tab while
  the player looks for the squad's card. Seven beats are like this: four tab-only lead-ins
  (`open-structures`, `infantry-tab` in Basics, `flight-tab` in Air, `infantry-tab` in Support) and
  the tab-anchored `train`, `fighter`, `wagon`, `medics` and `shot-truck`. `power` and `barracks`
  anchor the item card directly and assume that the drawer is open on Structures.
- `TutorialDirector.progress()` already returns (beats done, beats in the lesson). Basics has 28
  beats, Strikes 10, Air 12 and Support 13. No beat is optional.
- The top of the battle screen (ADR 0025 §2, `HudCorners.place`): the pill at the top left (48 dp
  high, 200-372 wide, with the pause menu button), the radar scope at the top right (56 dp). In
  landscape the attack toast is centred between the two. Upright it stands under them (from y 64,
  48 high). The group column stands under the pill at the left edge, from y 56. The full map
  unfolds under the scope (landscape at most 240 x 120, upright 260 x 130). On short landscape
  screens with a strike button, the map stands left of the right column from the top. **The strike
  button is not at the top.** It stands 8 dp above BUILD in the bottom right corner (ADR 0025 §10).
  The open drawer is a side panel at the right in landscape and a bottom sheet (half the height)
  upright.
- Reduced effects (ADR 0027 §8, status note 2026-11-15) drops the ambient detail and keeps what
  tells the player something. It is read at match start and never changes during a match.
- `data/tutorial/**` is negated in `balance.yml` (P509), so tutorial data starts no balance run.

## Decision

### 1. The dock: one fixed place at the top
- **`GuideDock.place(safe, portrait, dp, hud, settings) -> Rect2`** (`game/ui/tutorial/`, a static
  pure function, no node) gives the open card's rect from the rects `HudCorners.place` returns. The
  rect is computed again only on a change: a resize or turn, the drawer, the full map or the group
  count. It is never searched per frame.
- **Top edge:** under the top row. In landscape that is the scope's foot plus 8 dp (y 64 dp from
  the safe top). Upright it is the toast slot's foot plus 8 dp (y 120 dp). The toast slot is kept
  free whether or not a toast shows, so the card never moves when a toast comes. These are
  `CoachMark.top_row_dp` today.
- **Left edge:** 8 dp right of the group column (8 dp right of its last column when it has more
  than one). Mirrored (left-handed, ADR 0025 §14), everything flips with `HudCorners`.
- **Right edge:** in landscape, 8 dp left of the full map's rect, which is **reserved whether or
  not the map is open**. The card then does not move when the player opens the radar. It is also
  8 dp left of the open side panel's close handle. Upright the right edge is the safe edge.
- **Upright with the full map open,** the map (260 dp wide under the scope) leaves no room beside
  it. Then the dock's top edge moves to 8 dp under the map's foot. This is the one state in which
  the card stands lower, and it goes back up when the map closes.
- **Width:** the room between the edges, at most `card_max_width_dp` (560), centred in the room.
  **Height:** what the text needs, at most `card_max_height_pct` of the safe height (45). Upright
  with the drawer sheet open, it also ends 8 dp above the sheet's top. On the pause menu (the
  `resume` beat) it also ends 16 dp above the ad band (ad policy). The sweep (§10) proves that
  every prompt fits at the six sizes and on the two small web profiles. A prompt that does not fit
  is shortened (P593). It is never scrolled.
- **What it never covers:** the pill, the scope, the toast slot, the group column, the full map,
  the open drawer and its close handle, the command bar, BUILD, the Ready chip, the strike button
  and its aim row, and the enemy sweep's badge and line. It is built from their rects, so this
  holds by construction (the pure function's test at six sizes). The one part it may cover is the
  economy card. That card is transient (any touch closes it, ADR 0025 §2's one-overlay note), and
  no beat asks for it.
- Indicative numbers (dp, safe rect, one group column; the tests pin the real ones):

  | Profile | Dock (x, y, width) | Height cap |
  | --- | --- | --- |
  | 6-inch landscape (safe 890 x 387) | 73, 64, 560 (room 64-642) | 174 |
  | `web_phone` (890 x 331), with strike button | 64, 64, 498 (map left of the column) | 149 |
  | `web_phone_small` (776 x 280), without / with strike button | 64, 64, 428 / 64, 64, 384 | 126 |
  | `web_phone_portrait` (336 x 676) | 64, 120, 272; map open: 64, 250, 272 | 304; map open 298; sheet open 210 |

  The sweep line (landscape) and the sweep badge (upright) are reserved too, which is why two rows
  are lower than they would be without them.
- **No room: the card folds to its tab.** `GuideDock.place` returns an empty rect when no rect of
  at least 48 x 48 dp (the tab's size, §2) fits beside every reserved part, and `GuideDock.has_room`
  says so. The card then folds to its tab (§2) and stays folded until the layout changes. Opening
  the folded tab is the player's explicit choice and may overlay the HUD until it is closed. This
  is rare, and both states are limited to the smallest landscape profile (`web_phone_small`):
  1. Five group buttons, the bar, the Ready chip and the strike aim on together, at either bar
     height, with or without a cutout. With the tall bar (106 dp: while Stop shows or the orders
     wrap) the group row (x up to 312) and the pinned map (from x 320) leave no x range, and moving
     the card below the group row leaves 46 dp of height. With the short 64 dp bar the groups stack
     two high (x 0-184) and meet the pinned map that the aim row pushes left (x 246-486), so
     only 46 dp of width is left.
  2. A cutout (about 710 x 280 dp), the drawer open, the bar and the Ready chip on, and the tall bar
     only: the pill and the open panel leave under 200 dp for the toast, so it stands under the
     top line and spans to the handle's clearance, nothing is left beside it, and the 106 dp bar
     leaves 46 dp under it. With the short bar there is room.

  In both, the card stays reachable through its tab. Folding never happens on the profiles of the
  indicative table (the tests pin that).
- **The folded tab's slot** (P588, `GuideDock.tab_slot`): with no dock there is no corner to stand
  in, so the tab has its own slot. It is a 48 x 48 dp square on the top edge of the safe rect (the
  top row) and the one nearest the scope (top right; mirrored, top left), 8 dp clear of every
  reserved part, the open side panel's close handle (a 48 dp strip left of the panel) included. The
  attack toast's slot is one of the parts. Only where a wide pill leaves no square between it and
  the toast does a second look let the tab stand on the toast's slot (a toast is brief; the tab
  stays) and clear of the rest. A 1 dp scan, run when the layout changes. In both fold states (the
  tests pin the geometry, with the pill at its least width) the slot is free: right of the toast
  and left of the scope in state 1 (x 664 on 776 dp, x 598 on 710 dp), left of the close handle in
  state 2 (x 294 on 710 dp). A tap on the tab opens the card under the top row over the HUD, and a
  new layout folds it again.

### 2. The card and its tab
- **The open card** has two forms, chosen by the dock's width:
  - **Wide** (at least `card_wide_dp`, 440, the usual case in landscape): the prompt and the hint
    line on the left, and a right column with **the tab** on top and Next under it on a read-only
    beat.
  - **Narrow** (upright): a head row of 48 dp with the lesson's short title (muted) and the tab,
    then the prompt and the hint line. A foot row of 48 dp shows only where it has a button: Next
    on a read-only beat.

  In both forms the hint line shows only when the beat has stalled, and Skip shows only on a
  lesson's first beat (answer 4), at the foot, 12 dp from Next. In landscape the head row would
  cost 48 dp of a 280 dp screen, so the wide form has none. The look is the theme's `PauseCard`
  panel, as today.
- **The tab** is one button, at least 48 x 48 dp: the step counter and a fold chevron. It stands at
  the dock's top corner on the scope's side (top right; mirrored, top left). It is the same control
  in both states, so the counter never moves.
- **Folded:** only the tab shows, in its place. The rest of the dock is free for the map.
- **The counter:** `n/N`, for example "3/26" (answer 2). `n` is the number of the beat on show
  (1-based) and `N` is the lesson's beat count. A step is a beat. The sub-targets of a chain (§5)
  are part of their beat and do not count. Read-only beats count: the player taps Next on them. No
  beat is optional. If one becomes optional later, it counts like any other until an ADR says
  otherwise. In a gap between beats (`delay_ticks`, or waiting for the scripted enemy's step), the
  folded tab stays with the next beat's number, so the dock does not flicker. After the merges of
  P593, the lessons have Basics 26, Strikes 10, Air 11 and Support 12 steps.
- **Fold rules:**
  - Every new beat opens the card (Michael's rule). The fold state is not kept from step to step or
    from lesson to lesson, and it is never saved.
  - A tap on the tab folds or unfolds the card. Within a beat, the player's choice stands.
  - A beat that turns `stalled()` opens the card once, because the hint line is new.
  - A turn or a resize keeps the fold state.
  - The radio chirp plays when a new beat shows (ADR 0044 §2), not on a fold.
- **Skip** (answer 4): only on a lesson's first card. After that, the pause menu's
  "Leave tutorial" (P531, ADR 0044 §2; on `main` already) is the way out at any time. Skip next to
  the fold control would invite a slip that ends the lesson. A dock 272 dp wide upright has no room
  for Skip, Next and the tab in one row.

- **Implementation note (P589).** Two deviations, both forced by the 126 dp dock of the smallest
  landscape phone (`web_phone_small`, 384 to 428 dp wide):
  1. The wide form is used for the dock's width at least `card_wide_dp` **or any landscape dock**.
     The narrow form's head row and foot row cost 96 dp of a 126 dp dock and left the prompt no
     height. Only a portrait dock below `card_wide_dp` is narrow.
  2. The tab stands flush in the card's corner and the buttons' column starts one card margin
     (12 dp) below its foot, so the real gap between the tab's rect and Next (or Skip) is that
     margin plus the column's separation, never under 8 dp (measured: 17.6 dp on
     `web_phone_small`). Where the dock's height cannot hold the tab and the buttons in one
     column, Skip and Next sit side by side under the tab, and where even that does not fit,
     beside it. Where the prompt would get under 120 dp beside the column, the buttons stack in a
     column under the tab instead. The 12 dp between Skip and Next stands in every case.
  The hint line no longer names Skip ("Stuck? Try what the card says, or leave from the menu.").
  The tab is a button with the counter over a 14 dp chevron (turned half way when folded), so it
  fits the 48 dp square of `GuideDock.tab_slot`.

### 3. The target is never hidden
- HUD targets cannot lie under the open card (§1).
- Some targets can: a world tile, a control that follows the world (the ghost's check mark and X,
  ADR 0024), and a button of a modal the beat points into (Resume on the pause menu). When the
  active target's ring's own box (no growth, see below), or the gesture hint's bounds meet the open
  card, the card **stays where it is** (answer 3, A) and does three things:
  - Its body turns see-through (the theme's `GuideCardThrough` panel).
  - Its body lets touches through. Only the tab, Next and Skip take a touch.
  - The ring and the hand are drawn above it.
  The target then stays visible and takes its tap, drag or long press through the card. Today's
  rule "a card that could not clear the ring lets touches through" (P542) carries over.
- Over a modal (the `resume` beat on the pause menu) the card's body always lets touches through,
  so no button of the menu, Leave tutorial included, is ever blocked. While a modal is open the
  card's Skip hides (the pause menu has Leave tutorial), and Next shows only if it stands at least
  8 dp clear of every button of the modal.
- **P588 refinements:**
  - The see-through test uses the active ring's own box, with no 8 dp growth. The dock already keeps
    8 dp from every HUD part and the ring stands 6 dp outside its control, so a grown ring would
    meet the card at every HUD neighbour (the pill, the scope, the group column) and turn it
    see-through for a target that is not under it.
  - A control's ring is cut at the safe edge, not shifted off its control; a tile's ring still
    shifts (it is pinned to the nearest edge).
  - The card never grows past its dock. When a prompt is taller than the dock, the card keeps the
    dock's height and the prompt scrolls inside it (a touch drag, no bar); the buttons keep their
    foot row. Where the dock is too narrow for Skip and Next side by side, they stack.
- The card stands down under a modal that does not hold the target (P543b's `_covered()`, kept).

### 4. The blinking frame
- The ring (on a control a rounded frame 6 dp outside it, on a tile the ground ellipse, at least a
  48 dp target) now **blinks**: its opacity eases between `blink_low_alpha_pct` (50; first 25, raised in P591: at 25 the dim
  phase had 1.8:1 against the HUD panel, at 50 it has 3.4:1) and 100 over
  `blink_period_ms` (800). That is 1.25 blinks a second, under the 3-flash-per-second limit
  (WCAG 2.3.1), and it is never fully off. The 4 dp breathing goes. One looping Tween, as today.
- **Colour:** the theme, not code. A new `GuideTokens` type in `game/ui/theme.tres` has `ring` (the
  faction accent's light, as today), `ring_stalled` (the HUD's amber), `hint_fill` and
  `hint_line`. No colour literal (ADR 0025 §13).
- **Stalled:** amber and a second, outer ring, a change of shape as well as colour (as today).
- **Reduced effects:** a steady frame at full opacity, the line 1 dp thicker, and no Tween at all.
  Stalled still doubles the ring.
- Every target blinks: each sub-target of a chain, each tile and each control.

### 5. Chained targets
- **Data.** `TutorialBeatDef` gains `lead_in: Array[TutorialLeadInDef]` (append only, default
  empty: today's single target). The steps run in order before the beat's own anchor, which stays
  the final target. A `TutorialLeadInDef` has `anchor`, `anchor_control` and `anchor_tile` (as on a
  beat), `kind`, `value` and `type_id`: the condition that shows the player has passed the step.
  It also has `gesture` (default TAP). For example, `train`:

  ```
  lead_in = [ {anchor CONTROL "BuildButton", kind UNFOLD_OPEN, value 1 (Unfold.DRAWER)},
              {anchor CONTROL "TabInfantry", kind DRAWER_TAB,  value 1 (Tab.INFANTRY)} ]
  anchor CONTROL "Tile_rifle_squad", kind OWN_AT_LEAST, type_id rifle_squad, count 6
  ```
- **The active target** is `TutorialChain.active(beat, ctx) -> int`, a pure static function (the
  index of a lead-in, or `lead_in.size()` for the beat's anchor). **The furthest step whose
  condition holds now wins:** scanning from the end, the first lead-in whose condition holds gives
  the next step as active. If none holds, the first step is active. It is re-evaluated every frame
  and never latched, so the highlight follows the player both ways:
  - Placement closes the drawer, but `PLACING` (the last lead-in of `barracks`) still holds, so the
    ring stays on the check mark.
  - Closing the drawer by hand sends the ring back to BUILD.
- **"On the right tab"** is the existing `DRAWER_TAB` condition: the drawer is open
  (`HudState.Unfold.DRAWER`) and `BuildSidebar.tab` is the value. The director already fills it into
  `TutorialContext.drawer_tab`.
- Lead-in kinds are the UI-state kinds only: `SELECTED`, `UNFOLD_OPEN`, `UNFOLD_CLOSED`,
  `DRAWER_TAB`, `PLACING`, `STRIKE_AIMED`, `ZOOM_LEVEL` and a new `STRIKE_AIMING` (Kind 18,
  appended: the aim is on, with or without a point). None of them needs ticks, so a chain also
  works on a paused beat. `TutorialLessonDef.problems()` rejects a tick kind, an empty control name
  and a lead-in with no anchor.
- **The director** exposes `active_target() -> TutorialLeadInDef` and emits `target_changed` when
  the index changes. For the final step it returns the beat's own anchor, wrapped once when the
  beat shows, so nothing is allocated per frame. The director never writes the sim and sends no
  Command. The coach mark reads the active target in place of `beat.anchor`.
- **A target in a scrolled list.** When the active target is a drawer card (`ItemTile`) that is not
  fully in view, the mark asks `BuildSidebar.reveal_tile(tile)` once, when that step becomes
  active. `reveal_tile` is P120i's Ready-chip scroll, moved into a shared method; it keeps the card
  clear of the upright foot room. A player who scrolls away is not fought. The ring is clipped to
  the visible part (`_visible_rect`, kept). While the card is out of view entirely, the ring sits on
  the list's edge nearest to it, and the hint is a drag in the scroll direction.
  *Deviation (P591).* The ask is made once per step entry whether or not the card is in view,
  because the foot room under the gesture bar lies inside the scroll rect, so a card standing in it
  counts as "in view" yet is not clear. It is a no-op for a card already clear; a card taller than
  the list scrolls to its top, as the Ready chip does. The ask waits until the card's rect has
  held for 2 looks, since the grid sorts and the drawer slides after a tab change. A list that
  scrolls sideways only (the command bar) gets the strip on its left or right edge.
  *Deviation (P591, Michael's phone test of Basics 21/28).* The tab-anchored training beats ended
  on the tab, so with the tab already open the ring never reached the card. `train` (Basics),
  `medics` and `shot-truck` (Support) and `fighter` and `wagon` (Air) now chain BUILD, then the tab,
  to the item's card (`Tile_*`) as their final target. The rest of the lead-ins stay with P593. The
  chain itself was right: the director takes the furthest satisfied step at the start of a beat.
- **All lessons** (Michael's item 5). A lint in `test_lesson_data.gd` says that every beat whose
  final target is a drawer card or tab (`Tile_*`, `Tab*`) has a lead-in that opens the drawer. One
  whose target is a drawer card also has the tab's lead-in. The sweep (§10) starts every beat in
  the state the beat before leaves, and in the state where the drawer is closed. There the active
  target must be a visible, enabled control or a tile, so no step starts with a ring on nothing.
- **Content:** the four tab-only beats merge into the beat after them as lead-ins (`open-structures`
  into `barracks`, `infantry-tab` into `train` in Basics and into `medics` in Support,
  `flight-tab` into `fighter`). Their `covers` were empty, so coverage is unchanged, and their
  budgets add to the next beat. The tab-anchored beats get the item card as their final target.
  `power` chains BUILD, then the Structures tab, to the power plant's card. `barracks` chains
  BUILD, the Structures tab and the barracks card (passed by `PLACING`) to the check mark
  (`PlaceConfirm`). The scripted enemies' `trigger_beat` ids (`groups`, `home`, `sell-last`) are
  untouched.

### 6. Gesture hints
- **`GestureHint`** (`game/ui/tutorial/`, a Control child of the mark,
  `MOUSE_FILTER_IGNORE`): a hand glyph that plays a gesture in a loop at a screen point. Kinds
  (`TutorialBeatDef.Gesture`, append only): `AUTO`, `NONE`, `TAP`, `DOUBLE_TAP`, `LONG_PRESS`,
  `DRAG`, `BOX`, `PINCH_OUT`, `PINCH_IN`.
  - `AUTO` gives TAP on a control. For a `ZOOM_LEVEL` beat it gives PINCH_OUT or PINCH_IN by
    comparing the camera's level with the beat's value. For `CAMERA_PANNED` it gives DRAG, and
    otherwise NONE.
  - A tile beat names its gesture in data: `box` is BOX, `double` is DOUBLE_TAP, and `move` and
    `across` are TAP.
  - `gesture_vector_dp: Vector2i` sets the drag or box diagonal (the pan default is 160 dp to the
    left).
- **Where:** at the active target's centre (a chain's lead-ins tap their control). A beat with no
  anchor (pan, zoom) plays at the centre of the free field, which `GuideDock.field_point` gives:
  the room below the dock, above the bottom HUD and between the side columns. For a tile off the
  screen, the hint is a DRAG toward the field's centre from the edge where the tile lies. That is
  the pan that brings the tile into view. It is not a tap on the pinned ring.
- **Motion** comes from a pure function, `GestureHint.pose(kind, t_ms, timing) -> Pose`, which gives
  the fingertip offsets in dp, pressed or not, the press ring's progress and the opacity. The
  timing values:
  - From `data/tutorial/guide_settings.tres`: `hint_cycle_ms` 1600 and `hint_rest_ms` 800, with
    drag, pinch and tap lengths.
  - From `data/input_settings.tres`: `long_press_ms` and `double_tap_ms`. The hand holds as long as
    the real gesture needs, plus `hint_hold_extra_ms` (400), so the hint never teaches a timing the
    game would refuse.
  - A box is a long press, then a drag that draws the box outline.
  - A pinch is two fingertips moving apart (zoom in) or together.
- **Never in the way:**
  - The hint takes no input. It reads touches in `_input` without ever marking them handled.
  - While any touch is down, and for `hint_idle_ms` (2000) after the last release, the hint hides.
    A fake finger never moves while a real one does.
  - It loops while the beat is on show, also when stalled, and goes with the beat.
- **Reduced effects** (answer 5): no motion. The hand stands still in its key pose
  (finger on the point; for a drag, an arrow along the path; for a pinch, both fingertips with
  outward or inward arrows). ADR 0027 §8 keeps what tells the player something, and this does.
- **Art:** two hand-written SVGs, `assets/art/svg/ui/guide_hand_point.svg` (one finger) and
  `guide_hand_pinch.svg` (thumb and finger). They are drawn in the HUD glyphs' greys and tinted by
  `GuideTokens`, each with an entry in `assets/CREDITS.md`, © AppCode ApS, all rights reserved (ADR
  0046). They are own work from simple shapes, not traced from an OS emoji set, an icon font or any
  game. The ring of a press and the arrows are drawn in code.

### 7. Data and settings
- `GuideSettingsDef` (`game/ui/tutorial/`) with the one file `data/tutorial/guide_settings.tres`
  holds every number:
  - The card: `card_max_width_dp` 560, `card_wide_dp` 440, `card_max_height_pct` 45.
  - The blink: `blink_period_ms` 800, `blink_low_alpha_pct` 25.
  - The hint: `hint_cycle_ms` 1600, `hint_rest_ms` 800, `hint_idle_ms` 2000, `hint_tap_ms` 180,
    `hint_drag_ms` 900, `hint_pinch_ms` 900, `hint_hold_extra_ms` 400 and
    `hint_size_dp` 72.

  Colours are in `GuideTokens` (§4). Layout constants that are rules of the HUD (8 dp gaps, 48 dp
  targets) stay `HudCorners`' and `CoachMark`'s constants, as today.
- Beat data, append only: `lead_in`, `gesture` and `gesture_vector_dp` on `TutorialBeatDef`, the
  new `TutorialLeadInDef`, and Kind 18 `STRIKE_AIMING`. A lesson file without them plays as today.
- No sim, Command, snapshot or `STATE_FORMAT` change. Nothing in `game/sim`, `game/core` or
  `native/`.

### 8. P543g's search is retired, with no fallback
- What goes from `CoachMark`:
  - `place_card` and its candidate list, grid and costs (`_cost`, `_clear_of`, `_overlap`,
    `WIDTH_SHARES`, `COST_*`, `MAX_COLUMNS`).
  - The per-frame list of blocked buttons (`_collect_blocked` as a placement input).
  - The "a still-clear card stays" logic.
  - Their unit tests in `test_coach_mark_placement.gd`.
- What stays:
  - `_covered()` (P543b).
  - `_visible_rect` (a control scrolled out of view).
  - `_fit_card`'s fix of a wrapped label's height (one width now).
  - The ad band's 16 dp, as a height cap on the pause menu and a sweep assertion.
- **Why no fallback:** the dock is built from the HUD's own layout, so it has nothing to search.
  The only overlaps left are world-anchored targets and a modal's buttons, and §3 handles them
  without moving the card. A search kept as a fallback would bring back the jumping card that
  Michael asked to be rid of, and two layouts would double the test surface.

### 9. Fit
- **Sizes:**
  - The six sizes of ADR 0015 §6 and the profiles `web_phone_small` and `web_phone_portrait`, in
    both orientations and through a turn.
  - Every touch target is at least 48 dp: the tab, Next, Skip, the ring's target.
  - Skip and Next are 12 dp apart where both show.
  - Body text is at least 14 sp, from the theme.
- **Web and Android** use the same code. The hint is one texture and a few `draw_arc` and
  `draw_line` calls. It needs no shader, which suits the Compatibility renderer.
- **Work per frame:**
  - The dock is computed only on a change.
  - The chain is a scan of at most a few lead-ins over the context the director already fills.
  - The blink and the hint are one Tween and one redraw.
  - Nothing is allocated per frame (the pose is written into one reused object).
  - The tutorial is never on screen with 150 units, and the budget stands anyway.
- **Determinism:** view only. The guide sends no Command and never writes the sim. P595 proves it:
  a lesson played by the bot with the guide on, then with Reduced effects, ends in the same command
  log and the same state hash.

### 10. Tests
- **Changed:**
  - `tests/ui/tutorial/test_coach_mark_keeps_off_controls.gd`, the sweep, becomes the dock sweep.
    It covers every beat **and every lead-in step** of every lesson file, at the six sizes and the
    two profiles, in the state the beat before leaves, in its own condition's state, and with the
    drawer closed. It checks:
    - The open card is inside the safe rect, in the dock, and on no `HudCorners` part but the
      economy card.
    - The tab is at least 48 dp and inside.
    - The prompt fits the height cap without clipping.
    - The active target is the expected control or tile. It is visible and enabled, and a pushed
      touch at its centre reaches it, through the card where §3 applies.
    - The card is at least 16 dp from an ad band.
    - See-through occurs only for tile, world-follow and modal targets.

    Its old "covers no button" assertion is replaced by the dock's rule.
  - `test_coach_mark_placement.gd` loses the search's tests. It keeps the 48 dp buttons, the turn,
    the offset parent, Skip by a real touch and the pass-through on the ring.
  - `test_coach_mark.gd`: Skip only on the first beat (answer 4); the reduced test also covers
    the blink and the hint.
  - `test_lesson_data.gd`: the lead-in rules, the drawer lint, gestures that fit their kind (PINCH
    only with `ZOOM_LEVEL`, DRAG with `CAMERA_PANNED` or a vector), and the merged beats' covers and
    budgets.
  - `tests/e2e/test_tutorial_run.gd` (`TutorialBot`): for a lead-in, the bot taps exactly the
    control the ring is on (`mark.target_control()`). That proves the highlight follows the
    sub-target in a real match.
- **Added:**
  - `test_guide_dock.gd`: the pure function at the six sizes and the profiles; mirror; the map's
    reserve in landscape and the drop under the map upright; drawer side panel and sheet; group
    columns.
  - `test_guide_tab.gd`: open on each new beat, fold and unfold by tap, opens on stall, a turn
    keeps the state, the counter at the first and the last beat and in a gap.
  - `test_guide_blink.gd`: the period and low opacity from data, the theme tokens exist, reduced
    gives no Tween and a steady frame.
  - `test_tutorial_chain.gd`: the active index for crafted contexts, both ways, and Kind 18.
  - `test_gesture_hint.gd`: poses at fixed times for each kind, the long-press hold from
    `input_settings`, the static pose with reduced, `MOUSE_FILTER_IGNORE`, hidden while a pushed
    touch is down and back after the idle time, no event marked handled.
  - `test_guide_view_only.gd`: the bot's lesson with the guide on and with reduced effects gives
    the same command log and hash.
  - The art test for the two SVGs (the `svg-art-style` checks as for the HUD glyphs).
- **Unchanged:** `test_how_to_play_coverage.gd`. Merged beats keep the union of the covers, and
  the new help row goes through the existing checks.

### 11. Legal
The card, the tab, the blinking frame and the hand are our own look. A docked hint card, a step
counter, a highlighted target and a hand that shows a gesture are the common pattern of mobile
onboarding, not one game's. The Command & Conquer and Red Alert tutorials are voiced mission
briefings with no coach marks, and none of their text, sounds or art is used. The hand SVGs are
drawn in this repository from simple shapes (ADR 0046's licence). No word on the card comes from
the trademark list of ADR 0023 §13 ("Skip lesson", "Next", the step counter).

### 12. What this amends
- **ADR 0044 §2** (P583's dated note):
  - The card is docked (§1), with a tab and a counter (§2).
  - Skip is on the first card only (answer 4).
  - The ring blinks (§4) and follows a chain (§5), and gesture hints are added (§6).
- **`touch-ui-rules`** (P596, with Michael's yes to its text): a "Tutorial guide" paragraph. The
  dock is under the top row and never covers a corner part. The fold tab is 48 dp. The blink is at
  most 3 Hz and steady with reduced effects. The hint takes no input.
- **`docs/HOW_TO_PLAY.md`:** a new row `menus-tutorial-guide` (not Teach) and its help text. P585
  adds the row with the blinking frame. Later rows extend it: the card at the top (P588), the fold
  tab and the counter (P589), the frame moving on (P591) and the hand (P592). The rows
  `menus-tutorial` and `menus-tutorial-end` change for Skip (P589). `menus-settings` changes for
  the frame and the hand under Reduced effects (P592).

## Consequences
- The card no longer jumps. Its place depends only on the screen, the drawer and the full map.
- A world target under the card is seen and touched through a see-through card. That is less clean
  than a free place. Small landscape screens (280 dp high) show it most.
- One layout and its test replace a search and its fallbacks. The placement code shrinks.
- Lessons describe multi-tap actions as one beat with a chain. The counter falls by four steps
  overall, and the lint keeps future lessons honest.
- A renamed control still breaks a lesson, and the bot's run shows it (as ADR 0044 says).
- New art (two SVGs) and one more settings file.

## Alternatives considered
- **Keep the search, but prefer the top.** This was rejected. The card would still jump whenever
  the top is taken, and the search's cost and test surface stay.
- **Dock at the bottom.** This was rejected (answer 1). The bottom holds BUILD, the strike button,
  the command bar and, upright, the drawer sheet. Those are the controls most beats point at.
- **Fold the card by itself when it covers the target** (question 3, B). This was rejected
  (answer 3). At a new step the player would never see the text Michael wants shown.
- **Move the camera so the target is in view.** This was rejected. It takes the camera from the
  player and breaks the pan beat.
- **Count steps as lead-ins plus beats.** This was rejected. The total would change with the
  player's route (a drawer that is already open skips a step).
- **A latched chain** (a step once passed stays passed). This was rejected. Closing the drawer
  would leave the ring on a hidden tab.

## Questions for Michael (answered 2026-11-24: "Ja til alle", every recommendation)
1. **Where the card docks.** At the top, just under the pill and the radar, between the group
   buttons and the full map, never over them (recommended). Or at the bottom, above BUILD and the
   command bar. **Answer: the top.**
2. **The counter.** "3/26" (recommended: short, shows both numbers, needs no translation). Or "23
   left". Or "Step 3 of 26". **Answer: "3/26".**
3. **When the target lies under the open card** (a spot on the map, mostly on small landscape
   screens). A: the card stays, turns see-through and lets the touch through, and the blinking frame
   and the hand show on top (recommended). B: the card folds itself to the tab for that step.
   **Answer: A.**
4. **Skip lesson.** Only on each lesson's first card, and "Leave tutorial" in the pause menu at any
   time (recommended: the narrow upright card has no room for Skip, Next and the fold tab, and Skip
   beside the fold invites a slip). Or keep Skip on every card, which makes the card taller.
   **Answer: first card only, plus "Leave tutorial".**
5. **The hand with Reduced effects on.** A still hand in the gesture's pose, with arrows
   (recommended: Reduced effects keeps what tells the player something). Or no hand at all.
   **Answer: a still hand with arrows.**
