# Draft: the `touch-ui-rules` "Tutorial guide" section (ADR 0048 §12, plan row P596)

Date: 2026-11-27. Author: architect (branch `claude/p596-guide-closeout`, base `main` at
555f6b58).

**This is a draft for Michael's approval.** `.claude/skills/touch-ui-rules/SKILL.md` changes only
after his explicit yes to this text. Until then the skill file is not edited.

- **Where it goes:** a new section after "Corner HUD and build drawer (ADR 0025)" and before
  "Layout in both orientations".
- **Sources:** every number comes from ADR 0048 or a code or data constant on `main` at 555f6b58:
  `GuideDock.GAP_DP`, `MIN_DP`; `GuideRing.RING_GROW_DP`, `MIN_TARGET_DP`;
  `GuideUnitAnchor.THROUGH_BAND_DP`, `MIN_HALF_DP`; `GuideCardFit.BUTTON_GAP_DP`;
  `CoachMark.REDUCED_LINE_DP`; `data/tutorial/guide_settings.tres`; `data/input_settings.tres`.
- **P593b-5 (open on its own branch):** it widens the DRAG start's clearance by the drawn press
  ring's radius. If it merges before Michael's yes, the hand bullet below gets its rule and
  constant from that PR before the text goes in.

## The text to insert

```markdown
## Tutorial guide (ADR 0048)
- The card docks at the top: under the top row (64 dp from the safe top sideways, 120 dp upright,
  the toast slot kept free), 8 dp right of the group column and, sideways, 8 dp left of the full
  map's rect, reserved whether or not the map is open; upright the right edge is the safe edge.
  It is at most `card_max_width_dp` (560) wide and `card_max_height_pct` (45) of the safe height
  high. Upright with the full map open it stands 8 dp under the map. It never covers a corner
  part but the economy card. Every prompt fits without scrolling. With no room for a 48 dp square
  the card folds to its tab.
- The tab: one button, at least 48 x 48 dp, at the dock's corner on the scope's side, with the
  counter `n/N` (a step is a beat) and a fold chevron. A tap folds or opens the card. Every new
  beat opens it, a stall opens it once, and a turn keeps the fold. Skip shows only on a lesson's
  first card, 12 dp from Next; after that the pause menu's Leave tutorial is the way out.
- See-through: where the active ring's own box (no growth) or the hand's bounds meet the open
  card, the card stays where it is. Its body turns see-through (`GuideCardThrough`) and lets
  touches through, and the ring and the hand are drawn above it. For a unit the card turns back
  only once the ring's box grown by 8 dp (`THROUGH_BAND_DP`) and the hand's bounds are clear of
  it. Over a modal the body always lets touches through, Skip hides, and Next shows only 8 dp
  clear of every button of the modal.
- The card's buttons hide the field: Next, Skip and the tab take a touch even while the card is
  see-through. A unit's tap point is off the field once it is inside a visible button's rect, and
  back on only once it is outside that rect grown by 8 dp (`THROUGH_BAND_DP`). A hidden button
  does not count. The `HudCorners` parts, the toast and reveal slots and the ad band hide the
  field too; the economy card does not.
- The ring: on a control 6 dp outside it, cut at the safe edge; on a tile the ground ellipse,
  pinned to the nearest edge off screen. It is at least 48 dp. It blinks between
  `blink_low_alpha_pct` (50) and full opacity over `blink_period_ms` (800): 1.25 a second, under
  3 a second, never fully off. A stall turns it amber and doubles it.
- A unit as target: the ring is round, on the unit's tap point, the point a tap picks it at: a
  ground unit's lifted centre, an aircraft's hull without the bob, never its shadow. Its radius is
  the type's selection ellipse at the zoom, at least 24 dp. The pick (nearest the camera's centre,
  or the newest) is held while the unit stays a candidate. It is made again only when that unit is
  gone, carried or fogged, or when the step or the match changes. Ties go to the lower id. An enemy
  counts only on a cell the player sees. Off screen the ring is pinned to the edge. With no unit
  there is no ring and no hand: the card shows alone.
- The hand: a TAP on a control and on a unit in the field; a DRAG otherwise, the pan that brings
  the unit or the off-screen tile into the field. A beat with no anchor plays at the field's
  centre. The DRAG starts on the nearest free point, never on a visible card button grown by 8 dp
  and never on a HUD control, with its vector unchanged. When no point is free there is no hand.
  The hand is `hint_size_dp` (72) and takes no input: `MOUSE_FILTER_IGNORE`, and it never marks an
  event handled. It hides while any touch is down and for `hint_idle_ms` (2000) after. A long
  press holds `long_press_ms` plus `hint_hold_extra_ms` (400).
- Reduced effects: the frame holds still at full opacity, its line 1 dp thicker, with no Tween; a
  stall still doubles it. The hand stands still in its key pose: the finger on the point, an arrow
  along a drag, both fingertips with arrows for a pinch.
- Touch targets: the tab, Next, Skip and every ring's target are at least 48 dp.
- The numbers live in `data/tutorial/guide_settings.tres` and the colours in the theme's
  `GuideTokens`, never in code.
```
