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

Amended 2026-11-26 by §13 (unit anchors: the frame and the hand on a unit that moves; plan rows
P593b-0 to P593b-2). §13 extends §3 (see-through for a moving target), §5 (a unit as a target)
and §6 (the hand on a unit); the rest of §1-§12 stands unchanged.

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
  BUILD, then the Structures tab, to the barracks card. The scripted enemies' `trigger_beat` ids
  (`groups`, `home`, `sell-last`) are untouched.
  *Deviation (P593).* A build beat ends on its item card; the placement check is rung by the
  placement beat (basics/placed), so the ring never points at nothing while the structure builds.

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
    `hint_size_dp` 72, `hint_margin_dp` 8 (the see-through test's room round the hand) and
    `hint_drag_max_dp` 240 (the longest drag toward an off-screen tile).

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

### 13. Unit anchors (amendment, 2026-11-26, plan rows P593b-0 to P593b-2)
**In short, for Michael:** where a step asks you to tap a unit (your fighter, the shot truck you
just built, the nearest enemy), the blinking frame now stands on that unit and moves with it, and
the hand taps it. On an aircraft the frame is on the aircraft itself, not on its shadow. If the
unit is off the screen, the frame waits at the screen's edge and the hand drags toward it. If there
is no such unit, the step shows its card alone, as today.

Status: **accepted (lead, 2026-11-26)**, held pick included. Proposed the same day by the architect
(row P593b, branch `claude/p593b-adr`, base `main` at 59efa29b). It changes none of Michael's five answers: it puts the
frame and the hand of §4 and §6 on the thing to tap where that thing is a unit. No sim, Command,
snapshot or `STATE_FORMAT` change (§7 holds).

#### 13.1 Context
After P593 and P594, six beats point at nothing useful, because their target has no fixed tile or
is hidden:

| Beat | Today | What the player must touch |
| --- | --- | --- |
| basics `groups` | ring on `AddGroup`, which is hidden after `rally` (the barracks is selected, so no save) | `AllArmy`, then `AddGroup` |
| basics `attack` | no anchor, no hint (P594's `NO_HINT`) | an enemy unit, which moves |
| air `tap-air` | no anchor, no hint (`NO_HINT`) | the fighter's body, which hovers above its shadow |
| air `home` | ring on `Home`, which shows only with an aircraft selected | the fighter, then `Home` |
| support `select-truck` | no anchor, no hint (`NO_HINT`) | the shot truck built in the lesson |
| support `mine` | ring on `Mine`, which shows only with the truck selected | the shot truck, then `Mine` |

Checked against the code (`main` at 59efa29b):
- `AllArmy` is always in the group column (`GroupColumn._refill`); it is hidden only when the
  column itself has no room (the upright drawer sheet). The plan row's "AllArmy exists only once a
  group does" was wrong. `groups` therefore needs no unit anchor: a `CONTROL` lead-in on
  `AllArmy`, as P593 gave `clear` and `stop` (`Beat_06_select`, `Beat_08b_select`).
- Anchor resolution already lives outside `CoachMark`: `GuideRing.box` (control or tile to the
  ring's rect, the 48 dp floor, the safe-edge pin), `GuideLookup.find` (a control by name,
  throttled) and `GuideHintPlan.resolve` (the hand's point and the off-screen drag). `CoachMark`
  keeps about 50 lines of glue (`_ring_box`, `_sync_aim`, `_resolve_target`, `_draw_ring`,
  `_update_gesture`). It is at 999 lines, one under gdlint's 1000-line cap.
- A tap picks a ground unit at its lifted centre (`UnitPick.fill`: the rig's ground point raised
  by `SpriteLift.centre_lift_px`) and an aircraft at its hull (`AirLayer.fill_pick_snapshot`: the
  rig's ground point raised by `rig.lift`, without the bob). `UnitLayer.unit_screen_position` is
  the ground point and, for an aircraft (no rig in `UnitLayer`), the tick's position, not the
  interpolated one. It cannot serve.
- `MatchSnapshot` has no serial of its own. The runner publishes one new snapshot per tick, so
  `(match_serial, tick)` names a snapshot, and `rows_version` says whether row indices moved.
- `CoachMark._update` lays the card out again (`_layout_card`, so `_fit_card` and its label
  measuring) whenever the ring's box moves. On a tile beat that happens only while the camera
  pans. A ring on a moving unit would refit the card in every frame.

#### 13.2 Decision: the data
- **`TutorialBeatDef.Anchor` gains `UNIT`** (value 3, appended).
- **The selector is a sub-resource**, `TutorialUnitPickDef` (`game/ui/tutorial/`, data only):
  - `side: Whose` (`OWN`, `ENEMY`; append only). The enum is `Whose`, not `Side`, because a class-level `Side` collides with Godot's global `Side` enum and fails to parse. `ENEMY` is any owner other than the local player
    and other than 0.
  - `type_id: StringName`: one type, or any mobile type when empty.
  - `pick: Pick` (`NEAREST_CAMERA`, `NEWEST`; append only).
- **Both `TutorialBeatDef` and `TutorialLeadInDef` gain `unit: TutorialUnitPickDef`** (default
  null). A lead-in needs it, because `home` and `mine` select the unit in a lead-in before their
  `CONTROL` target. `TutorialChain.final_step` copies the reference. The def is read-only and is
  never written at runtime.
- In `.tres` the selector is a `[sub_resource]` like a lead-in, for example `attack`:

  ```
  [sub_resource type="Resource" id="Beat_23_unit"]
  script = ExtResource("10_unit")   # TutorialUnitPickDef
  side = 1                          # ENEMY
  pick = 0                          # NEAREST_CAMERA

  [sub_resource type="Resource" id="Beat_23"]
  ...
  anchor = 3                        # UNIT
  unit = SubResource("Beat_23_unit")
  ```
- The selector does not reuse the beat's `type_id`. That field is the condition's parameter, and
  `ENEMY_LOSSES` ignores it. Two meanings in one field would bind the ring to the condition.
- **`TutorialLessonDef.problems()`** rejects a `UNIT` anchor with no `unit`, and a `unit` on any
  other anchor. A `UNIT` lead-in follows §5's lead-in kinds (`SELECTED`, in `home` and `mine`).
- A lesson file without `UNIT` loads and plays as before.

#### 13.3 Decision: the resolver and the layer accessors
- **`GuideUnitAnchor`** (`game/ui/tutorial/`, a `RefCounted` next to `GuideLookup`, owned by the
  mark). It resolves the active step's selector to one unit and gives its screen point every frame.
  It keeps only ints and the result: the held unit's id, its row, the `(match_serial, tick,
  rows_version)` it last checked, `point` (base px, `Vector2.INF` for none), `half` (the ring's
  half size, px), `flyer` and `in_field`.
- **Two read-only accessors on the layers**, one formula each with their pick fill:
  - `UnitLayer.tap_point(id: int) -> Vector2`
  - `AirLayer.tap_point(id: int) -> Vector2`

  Each returns the world-px point that a tap picks the unit at: the lifted centre of
  `UnitPick.fill`, or the hull of `AirLayer.fill_pick_snapshot`, so an aircraft's body without the
  bob. It is interpolated (the rig's place this frame). It returns `Vector2.INF` when that layer has
  no shown rig for the id: gone, falling, hidden by fog, a building, or the other layer's unit.
  Each syncs as `unit_screen_position` does (cheap when nothing changed) and allocates nothing. They
  take an id, not a row, so a caller never holds a row of an older `rows_version`. The resolver
  calls the layer that `WorldSort.is_flyer(snap, type)` names and projects the point with
  `camera.world_to_screen`.
- **Per frame**, with no allocation:
  1. Read `runner.snapshot`. With none, there is no unit.
  2. Another selector (a new step) or another `match_serial` drops the held unit and scans once
     on this frame, so a new step never waits a tick for its ring.
  3. **Otherwise only on a new snapshot** (another `tick`): check the held unit again. It must still have a
     row (`index_of`, skipped while `rows_version` is unchanged: the row is reused), match the
     selector and, for `ENEMY`, stand on a cell the local player sees (`FogLayer.is_seen` on the
     snapshot's fog). If it fails, the hold drops. With no held unit, scan once (13.4). With none
     found, the next scan waits for the next snapshot. That is the throttle (GuideLookup's
     "a control that is not there" rule at the publish rate, at most 15 a second).
  4. **Every frame:** `point` is the held unit's `tap_point`, projected. `half` is the larger of
     the type's selection ellipse at the camera's zoom (the larger axis of the Vector2
     `IsoProjection.ellipse_px` gives for `type_selection_radius`, the radius the Picker uses) and 24 dp.
- **Never the World.** The resolver reads `runner.snapshot`, the camera, `runner.scenario`'s local
  player (as `FogLayer.local_player_of` does) and the two accessors, nothing else. It never reaches
  into a layer's rigs or pools, and never reads `runner.world`. The test is the one
  `test_unit_layer.gd` uses ("draws from the published snapshot and never reads the world"): swap
  `runner.world` for an empty World, and the resolver still finds its unit.
- **Where it plugs in.** `GuideRing.box` and `GuideHintPlan.resolve` each gain one `UNIT` branch
  and an optional last parameter `unit: GuideUnitAnchor = null`. Both read the resolver's result
  and never resolve it themselves. `CoachMark` gets the glue: it calls `update` once a frame
  before `_ring_box`, and three getters for the bot and the sweep: `target_unit() -> int` (-1 for
  none), `target_point() -> Vector2` and `target_in_field() -> bool`. `TutorialHost` hands the
  mark the runner and the two layers, found by type as it does the others.

#### 13.4 Decision: the pick rule
- **Candidates:** rows of the snapshot whose owner fits `side`, whose type is `type_id` (any when
  empty) and has no footprint (a building has a fixed tile and uses `TILE`). For `ENEMY`, only
  rows on a cell the local player sees. Fog is never leaked, and an enemy the player cannot see
  cannot be tapped.
- **`NEAREST_CAMERA`:** the smallest squared distance in milli-tiles (int) between the row's tick
  position (`pos_x`, `pos_y`, never the interpolated one) and the camera's centre, taken once per
  scan as `IsoProjection.px_to_ground` of the centre. **`NEWEST`:** the highest unit id. Ids rise
  and are never reused, so this is the unit made last.
- **Ties** break by the lower unit id. One scan over the rows, with the snapshot's arrays aliased
  into typed locals before the loop.
- **The hold (a change to the outline).** The outline asked for the lookup on every new snapshot.
  A fresh nearest-pick at 15 Hz would hop the frame between two enemies at almost the same
  distance, and a pan would move it to another unit. That is the jumping §1 was written to end. So
  a unit, once picked, is **held** while it stays a candidate. The pick runs again only when the
  held unit stops being one (dead, carried, fogged, gone) or when the step or the match changes.
  The re-pick happens on the same frame the held unit stops being a candidate; there is no stale
  hold, so the frame never stays on a dead unit or on an enemy the fog has hidden.
  The pick is a pure function of (snapshot, camera centre, selector), with ties by id. Which unit
  is held depends on the snapshots and the camera at the pick: given the same of both, it is the
  same.

#### 13.5 Decision: the ring, the edge, the field and the card
- **The ring** on a unit is the tile's ground ellipse (`_draw_ring`'s non-control branch), centred
  on `point`, of `half` and at least 48 dp. As built the unit ring is circular (radius `half`), not the tile's 2:1 ellipse. It blinks, turns amber and doubles as §4 says.
- **Off the screen:** a unit whose point is outside the safe rect gets its ring pinned to the
  nearest edge (`GuideRing.box`'s existing clamp). The pin slides along the edge as the unit moves.
- **The field:** `in_field` is true when the point is inside the safe rect and under no rect of
  `GuideDock.hud_for_dock` (the `HudCorners.place` parts, the reserved toast and reveal slots and
  `AD_BAND`; the economy card excepted). The loop walks the mark's cached copy of those rects with
  no `keys()` or `values()` call. A unit under the open drawer
  sheet, the command bar or a corner part is not in the field. A real finger there would hit the
  HUD. The card's own visible buttons (Next, Skip, the tab) hide the field too, since they take a
  touch even while the card is see-through (P593b-3): `CoachMark` hands the anchor their global
  rects each frame (hidden ones left out, one reused array). The point counts as under a button once
  it is inside the plain rect and as clear only once it is outside the rect grown by
  `THROUGH_BAND_DP` (8 dp), so a unit along a button's edge does not flip the hand between TAP and
  DRAG. The hand then drags the unit clear by the existing out-of-field path.
  That drag starts on the nearest free field point (P593b-4), never under a visible card button
  grown by the band or a HUD rect (`GuideUnitAnchor.clear_at`), with its vector unchanged; with no
  free point there is no hand, so a finger that follows it pans and never presses Next. The search
  moves the start along one axis only, to a point `START_GAP_DP` past a blocked rect grown by the
  band: where the x move lands in one HUD rect and the y move in another there is no hand (it fails
  safe). It applies to any off-field UNIT drag, not only under a button. The drag's end is not
  checked: a Button fires only when the press began on it, and the vector is unchanged.
  What the hint draws at the start must be clear too (P593b-5): the press ring's square
  (`GestureHint.ring_reach_dp`) and the hand's box may not meet a button grown by the band or a
  HUD rect, so each candidate lies that much further from the blocked rect.
- **The hand** (`GuideHintPlan`): `AUTO` on `UNIT` gives `TAP`, as on a control. A unit not in the
  field gets §6's off-screen `DRAG` from the point (clamped into the safe rect) toward the field's
  point: the pan that brings it out. A tile does that only as the beat's own anchor. A unit gets it
  on a lead-in too, because a tap on a pinned ring selects nothing. An explicit `NONE` still
  suppresses it.
  An explicit `NONE` is read from the active step's own gesture: a lead-in uses its own, and the final step copies the beat's.
- **See-through for a moving target** (§3): the card turns see-through when the unit's ring box or
  the hand's bounds meet it. For a `UNIT` aim it turns back only once the ring's box grown by 8 dp
  and the hand's bounds are clear of it. This is a band of hysteresis, so a unit that walks along
  the card's edge does not flicker the card. Tiles and controls keep §3's rule unchanged.
- **No refit for a moving ring.** In `_update`, a change of the ring's box alone redraws the ring,
  replans the hand and runs the see-through test. On a see-through flip only the card's theme
  variation and mouse filters change. The card's layout (`_fit_card`) runs only on a reshape (§1's
  triggers, a new step, the buttons, a fold). This fixes the per-frame refit of a tile beat during
  a pan as well.
- **§5's target rule** (a step's target must be a visible, enabled control or a tile) gains "or a
  unit the resolver holds". A `UNIT` step with no unit shows the card alone, so no step starts with
  a ring on nothing.
- **No unit, no ring:** with no candidate, or a held unit whose `tap_point` is `INF` this frame,
  the ring box is empty and the hand is `NONE`. This is exactly today's behaviour for these beats:
  the card alone. The card never waits for a unit and never blocks the beat.
- The ring may trail its rig by one frame where the mark's `_process` runs before the layer's. At
  the speeds of the game that is under 2 px. The bot and the tests read after a frame.

#### 13.6 Decision: the six beats (content, P593b-2)
| Beat | Lead-ins | Final target |
| --- | --- | --- |
| basics `groups` | `CONTROL AllArmy`, `SELECTED rifle_squad`; a drawer-closing step before it if the sweep finds the column hidden upright | `CONTROL AddGroup` (kept) |
| basics `attack` | `CONTROL AllArmy`, `SELECTED` (the army type), where the sweep finds the army unselected after `incoming` | `UNIT` `ENEMY`, any type, `NEAREST_CAMERA`, `TAP` |
| air `tap-air` | none | `UNIT` `OWN` `fossil_fighter`, `NEWEST` |
| air `home` | `UNIT` `OWN` `fossil_fighter`, `NEWEST`, `SELECTED fossil_fighter` | `CONTROL Home` (kept) |
| support `select-truck` | none | `UNIT` `OWN` `fossil_shot_truck`, `NEWEST` |
| support `mine` | `UNIT` `OWN` `fossil_shot_truck`, `NEWEST`, `SELECTED fossil_shot_truck` | `CONTROL Mine` (kept) |

Beat ids, conditions, covers, budgets and the scripted enemies' `trigger_beat` ids (`groups`,
`home`) are unchanged. ai-dev may choose another pick or type where the sweep shows a better
target. The table is the default, and the PR says why for any change.

#### 13.7 Decision: the bot and the proof
- **`TutorialBot`** taps a `UNIT` step as a finger would. If `mark.target_in_field()` is false, it
  centres the camera on the unit's tick position (as `_tap_ground` does) and waits one frame. Then
  it sends one `TAP` gesture at `mark.target_point()` through the controller. A step that does not
  pass (a lead-in) or a beat that does not end after the tap is told in `ringless`.
  - For `attack` the army is selected first (by the lead-in, or by the bot's own `select_all_army`
    where the data has none). The tap must send an `ATTACK` whose `target_id` is
    `mark.target_unit()`. That proves the ring is on an enemy the Picker takes.
  - The bot's own `_select` and `_attack` picks stay for beats without a `UNIT` anchor.
- **The proof of the body, not the shadow:** in the chain sweep, a pushed screen touch (viewport
  input, not the controller) at `target_point()` selects the fighter. The test also asserts that
  the point is the hull's (`AirLayer`'s pick point) and stands `rig.lift` times the zoom above the
  shadow's.
- **View only** (§9) still holds: the guide sends nothing. P595's view-only run compares command
  logs, and the bot's `ATTACK` names the unit id, not a pixel, so the log does not depend on
  interpolation.

#### 13.8 The lead's constraints, as built into this decision
1. **Snapshot and accessors only.** The resolver reads the published `MatchSnapshot` and the
   interpolated points through `UnitLayer.tap_point` and `AirLayer.tap_point`, never a layer's
   internals and never the World (13.3; test: the World swap).
2. **No per-frame allocation.** Lookups happen only on a new snapshot, a new selector or a new
   match (one scan each), and the row is reused while `rows_version` holds. Per frame there is one accessor call (the layer
   `WorldSort.is_flyer` names), the projection and arithmetic (13.3; test: `Performance.OBJECT_COUNT` unchanged across 60 frames of a moving
   target, and the scan counter moves at most once per snapshot or new selector).
3. **Deterministic pick.** Int squared distances from tick positions, ties by the lower id; the
   hold is added (13.4; tests: crafted ties, both rules).
4. **Fallback.** No unit gives no ring and no hint, exactly as today. A unit that exists but is off
   the screen gets the edge pin and the drag (13.5).
5. **Size.** P593b-0 (running now) moves the card layout (`_fit_card`, `_layout_card` and the dock
   glue) into `GuideCardFit.gd`, so `CoachMark.gd` is at most 900 lines. P593b-1 stays under about
   250 production lines and adds at most about 40 to `CoachMark.gd`.

#### 13.9 Alternatives considered
- **One `GuideAnchor` with one entry point** (`resolve(aim, target, camera, hud_root, view, safe,
  dp, out)`), folding `GuideRing.box`'s anchor match and `GuideHintPlan`'s tile point into one
  place, with `UNIT` as one more branch. Not now. It moves about 100 lines of reviewed code (P591,
  P592) and costs about 200 changed lines before `UNIT` adds anything. That breaks P593b-1's
  budget, and today there is no second user of the fold. The resolver keeps `UNIT`'s state in one
  class, and the two pure functions each read its result in one branch. If a fourth anchor kind
  comes (a building by selector, say), the fold gets its own refactor row first.
- **Tile anchors refreshed by the lesson** (write the unit's tile into the beat at runtime). This
  was rejected. It writes a shared Resource, the ring would jump tile by tile, and an aircraft's
  body is not on its tile.
- **Ring the selection instead of a unit** (wait until the player has selected something). This
  was rejected. The beats exist to teach the selection.
- **Read the `PickSnapshot`** the Picker fills. This was rejected. It is filled per tap for the
  controller, not per frame, and a second filler would touch every row in every frame (150 rows,
  rule 6).
- **Re-pick on every snapshot** (the outline as written). This was rejected for the hop described
  in 13.4.
- **Nearest to the own army** for `attack`. This was rejected for now. The camera's centre is what
  the player looks at, and it needs no second scan. A `Pick` value can be appended later.

#### 13.10 Consequences
- Every beat that asks for a map action has a frame and a hand. P594's `NO_HINT` list goes
  (P593b-2).
- The guide reads two more view nodes (`UnitLayer`, `AirLayer`) through one method each. A change
  to the pick point (a new lift rule) must keep `tap_point` equal to the pick fill. A test pins
  both layers against their `fill_pick_snapshot` for every row.
- A moving ring no longer refits the card. Tile beats gain this during a pan too.
- `CoachMark` keeps its glue role. New anchor logic lives in `GuideUnitAnchor`, `GuideRing` and
  `GuideHintPlan`.
- The held unit can differ from the one nearest now (after a pan). That is accepted: the frame
  stays on one unit until it is gone.
- HOW_TO_PLAY: `menus-tutorial-guide` gains one sentence (P593b-1): the frame can stand on a unit
  and follow it; on an aircraft it is on the aircraft, not its shadow.

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
