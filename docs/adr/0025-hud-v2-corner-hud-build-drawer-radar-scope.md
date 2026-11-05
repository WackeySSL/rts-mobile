# ADR 0025: HUD v2: the corner HUD, the build drawer, the radar scope, the command bar and the pause menu

Status: accepted, 2026-11-02 (Michael, on #259: "Ja til anbefalinger undtagen attack. Punkt 4 behold
som det er i dag men lav en knap så man kan fjerne sin markering af en enhed"; his answers below).
Proposed 2026-11-01 on `main` at 5203ce0 (ADR 0024 accepted, P85g #256, P86c #257 and P85f #258
merged); revised 2026-11-02 after the lead's one-lens review (the layout numbers of §2, the freeze
of §1, the swipe, the screen of HUD words, eight questions); accepted the same day with the lead's
docs row P26ap folded into #259. Plan:
`docs/plans/2026-11-01-hud-v2.md`. Companion: ADR 0026 (place first, build afterwards; a sim rule
whose player-facing row lands after this ADR's drawer). Amends ADR 0015 §5, ADR 0019
§1, §3, §4, §5 and §6, ADR 0023 §5, §12 and §13 and ADR 0024 (§18); accepted, so the lead's P26ap wrote the dated notes (the skill text waits for its own yes). No
sim rule, Command, definition, data column or hash changes here: everything is view, input and UI
state, plus one settings key, new `input_settings` keys and font files.

Status note (2026-11-02, acceptance): the text below is written to Michael's answers. Question 4
was answered with neither option: a ground tap keeps moving and an enemy tap keeps attacking, there
is **no Attack button and no attack-move mode**, and the command bar gets a **Deselect** button
instead (§9). The `touch-ui-rules` text of §18 is applied by its own commit, after Michael's yes to
the skill change.

Status note (2026-11-03, the docs row after wave y; P119-P123 as merged): §1, §2, §4-§6, §8 and
§18 carry dated status notes: a pinned full map stays through placement and the aim; the tabs are
56 dp, so §5's budget leaves 76 dp; the toast's least width and its fallback place; the economy
card is the one overlay; a lead decision on the group column during a strike aim in portrait; the
interim portrait zone of 64 dp; the ring of a READY head and the placement restart; a strike on
own buildings out of view raises no cue (an open question). No accepted text changed.

Status note (2026-11-03, P26ar docs; P120d #293, P120c #295 and P122b #296 as merged, main
1a6209c): §2, §4, §5 and §7 carry dated status notes from wave z's lead decisions: the drawer
head's economy line takes no touch, drops the "POWER" caption and is 54 dp upright; the toast's
top-left check; what "stalled" means on low power; a pinned full map on very short screens during
the aim (§7); a hold on a group with nothing selected; the group column under the portrait sheet.
No accepted text changed.

Status note (2026-11-04, P26aw docs; P120b #320 and P122 #321 as merged, main f40e2a4): §5 and §9
carry dated notes: Michael's decision on the locked card (the padlock and the full name, no
"Needs"), the `web_phone_small` grid budget of about 53 dp, the queue row's cancel wait, the final
hold; and for the command bar, Stop during placement and the strike aim, the chip's label cap, no
health for a fogged enemy building, the bar's plain Control, and the chip's fit rule and the amber
frame and notch left for P122c. Two accepted phrases are replaced, each where its note says so:
§5's "Needs <display_name>" (with §19's P120 row's "("Needs <name>")"), by Michael's decision, and
§5's "until the next published snapshot shows the queue again", by the queue row's wait. No other
accepted text changed.

Status note (2026-11-05, P26ax docs; Michael's decisions of 2026-11-05 on his phone check of P124
and of the build drawer; rows P124b and P120e): dated notes at the end of §5, §11, §15, §16 and
§19 record them. They replace accepted text where each note says so. For the pill: "under the
drawer" in §2's table, §3's "Hidden while the drawer is open" bullet, row 3 of "Decisions in
short" ("hidden while the drawer is open (the drawer's head shows the economy)") and §5's "the pill
hides" (twice). For the drawer: §5's head ("From the top: the head (48 dp) ..."), the swipe's
"a drag that starts on the sheet's head with its handle", the long-press's "as many `QUEUE`s ...
at most `queue_hold_count`", the "Queue row" bullet, "never fewer than two" as a coded floor, and
row 5's "economy head" and "a queue row (tap an item = cancel, full refund)"; answer 2 A is
superseded and the P26ar notes on the head's economy line lapse. The P26aw notes on the queue
row's wait and the final hold stay, for the hold's CANCEL, except that a tab change no longer ends
the wait (§5's note). For the pause menu: §11's "64 dp high" and "No ad, ever", row 11's "no
ad", and §15's pause-menu banner row. CLAUDE.md and `admob-policy` take the banner rule with
Michael's yes of 2026-11-05 (`touch-ui-rules` points to it); the drawer rules follow his decisions
of 2026-11-05.

## Michael's answers (2026-11-02, on #259)
"Ja til anbefalinger undtagen attack" (yes to the recommendations except attack):
1. **A:** the build menu's pin is dropped (P85f2 withdrawn); its glyphs serve the radar pin.
2. **A:** a hold on a unit card queues up to `queue_hold_count`; the queue row's tap cancels.
3. **A:** "All army" stays at the top of the group column, always shown.
4. **Neither A nor B:** "Punkt 4 behold som det er i dag men lav en knap så man kan fjerne sin
   markering af en enhed" (keep point 4 as it is today, but make a button to remove your selection
   of a unit). No Attack button or mode; a Deselect button in the command bar (§9).
5. **No:** the radar is never offline.
6. **No:** items are paid when queued; "stalled" shows a queue that cannot go on.
7. **Ja:** in a skirmish the local player's units take its side's colour (Lumen Accord cyan,
   Derrick League orange); the GDD's team-colour line changes (P26ap).
8. **Ja:** a match starts with everything folded away, the drawer closed.

## Context
**Michael's design (2026-11-01).** A new page "HUD & startside" in his Claude Design canvas
("Iron Meridian - grafisk udkast", Version B): two system boards ("HUD · System og regler", "HUD ·
Komponenter og tilstande", notes in Danish), five landscape boards (L1-L5, 932 x 430), five
portrait boards (P1-P5, 430 x 932) and two start pages. The PNG exports are reference only and never
enter the repository (as ADR 0023's canvas). The design in one line: in battle only four corner
anchors show (about 4 % of the screen): a pill top left (menu button, credits, power), a round
radar scope top right, a round BUILD button bottom right, and the bottom left kept for a command bar
that shows only while something is selected. Everything else unfolds on demand (the build drawer,
the full radar map, an economy detail card, the pause menu), one at a time, and a tap on the map
closes it while the game runs on.

**Michael's decisions (2026-11-01, his answers to the lead), cited M1-M4:**
1. **M1:** build on wave u as merged (ADR 0024, P85g, P86c, P85f); reuse what fits (P85f's holder,
   slide, `map_gesture` collapse, `zone_changed`, the Build button; P85g's pin glyphs for the radar
   pin).
2. **M2:** the placement check mark and X stay beside the ghost (P86c's `GhostControls`), not in the
   BUILD corner as the design draws them; the design's price on the confirm ("PLACE 600") may move
   to the ghost controls if it fits.
3. **M3:** place first, build afterwards: yes, as its own ADR (0026), implemented after the HUD
   rows. Units keep a queue.
4. **M4:** SIL OFL fonts are allowed (Big Shoulders, Chakra Petch). The lead adds the CLAUDE.md
   line (Legal, Assets: "Fonts may also be under SIL OFL 1.1, shipped with their license and listed
   in `assets/CREDITS.md`") in this ADR's PR with Michael's yes.

**What the code has today** (`main` at 5203ce0):
- `BuildSidebar` (954 lines): OPEN or COLLAPSED (ADR 0024), the portrait band and strip, the
  landscape panel and plate, the Build button (`glyph_menu_open`), the Ready badge, the slide
  (`menu_slide_ms`), `map_gesture` collapse, `zone_changed`, `HudLayout.bottom_zone_dp` and
  `menu_top_px`. The pin and `game/meta/HudPrefs.gd` are P85f2, not merged; `game/meta/` is empty.
- `StatusPill` (landscape credits and power), `MinimapSlot` with `Minimap` (P88; the long-press
  `MOVE` is P88b, not merged), `SelectionPanel` (read-only, fit levels), `ArmyBar` ("All army" and
  groups 1-3: tap recalls, a hold of `group_assign_ms` assigns), `StrikeButton` and
  `StrikeControls`, `GhostControls` (P86c), the Dev button, one Theme (`game/ui/theme.tres`,
  dp-scaled by `HudTheme`).
- Commands the sim takes: `MOVE`, `ATTACK`, `ATTACK_MOVE`, `STOP`, `PLACE`, `QUEUE`, `CANCEL`,
  `RALLY`, `HARVEST`, `SUPERWEAPON`, `SURRENDER`. The UI sends `MOVE`, `ATTACK`, `QUEUE`, `CANCEL`,
  `PLACE` and `SUPERWEAPON`; `RALLY` and `HARVEST` input is P87, `SURRENDER` is P90 (both not
  merged). Only the dummy AI sends `ATTACK_MOVE`; nothing sends `STOP`.
- `MatchRunner.paused` stops the ticks (no Command, no sim state). There is no audio. Haptics exist
  (`haptic_ms`) with no switch. No result screen yet (P90).
- Not merged and touched here: P87 (rally, harvest, army filter), P88b, P89 (low power and
  under-attack cues), P90 (result screen, Surrender, Skirmish route), P85f2.

## Decisions in short
| # | Topic | Decision |
| --- | --- | --- |
| 1 | States | One unfolded panel at a time: none (battle), the build drawer, the full radar map, the economy card or pause; placement and the strike aim are modes. The command bar follows the selection and is not an unfold. A map gesture closes the unfold and still does its work (ADR 0024 §5 kept) |
| 2 | Corners | Pill top left, scope top right, BUILD bottom right, command bar bottom left (only with a selection), group column on the left edge, the 72 dp strike button above BUILD; every target at least 48 dp; layout is one pure function of (safe rect, orientation, dp, mirror, what shows), pinned with one table of numbers for the short screens; placement and the strike aim freeze the bottom layout |
| 3 | Economy pill | Menu button, credits, power bar in one 48 dp pill; spend and income flashes; low-power look with the word; a tap on the numbers shows a detail card, closed by the next touch; hidden while the drawer is open (the drawer's head shows the economy) |
| 4 | BUILD | Round, 64 dp, `glyph_menu_open` and the word; a ring with the first-finishing item's progress, a count badge, a "stalled" look (grey ring, "!") for a queue that cannot advance; a "Ready" chip until ADR 0026's UI row |
| 5 | Drawer | Landscape: a side panel from the right; portrait: a bottom sheet of half the height; economy head, close button and swipe to close, tabs Structures / Infantry / Vehicles with names, a card grid, a queue row (tap an item = cancel, full refund); replaces the band, strip, plate and floating panel |
| 6 | From ADR 0024 | Kept: holder and slide, `map_gesture`, `zone_changed` and `menu_top_px`, the return after placement (R1), the producer tap (Q3 A), `GhostControls`. Dropped: strip, plate, Ready badge (after ADR 0026), the build menu pin (P85f2; question 1) |
| 7 | Radar | A 56 dp round scope of the area round the camera (a crop of P88's minimap texture); a tap unfolds P88's full map under it with a pin and a collapse button; closes after `radar_close_ms` without touch unless pinned; never "offline" (question 5) |
| 8 | Attack cues | A 4 s toast at the top middle ("<name> under attack", tap = jump), a red marker on the scope's rim, a ping on the full map (no toast while the full map is open); they replace P89's planned edge arrows |
| 9 | Command bar | A Deselect button (48 dp, at the bar's start), the selection chip (picture, x N, health; "+N" for more types) and the orders that exist: Stop; a building shows Deselect, its chip and its orders (none today; Cancel with ADR 0026); later orders slot in; no Attack button (question 4); portrait BUILD lifts above it |
| 10 | Groups | A column on the left edge: "All army" on top (question 3), saved groups, "+" to save the selection; tap selects, long-press overwrites |
| 11 | Pause | The menu button pauses the match (`MatchRunner.paused`): objective card, Resume, Restart, Surrender, Exit to menu, Vibration; no ad; Settings, Sound and Music come with Phase 5 |
| 12 | Start page | Specified here, built with ROADMAP Phase 5's main menu: Treadline, the two sides, Skirmish, Settings, the version line, a banner slot only when Phase 6's `AdService` exists |
| 13 | Look | The design's tokens in `theme.tres`; panel without blur; Big Shoulders 800 and Chakra Petch 500-700 under `assets/art/fonts/` with their OFL texts; accent per side (Lumen Accord cyan, Derrick League orange) |
| 14 | Left-handed | Later (Phase 5 settings); the layout function takes a mirror flag from the first row and is tested mirrored |

## Decision

### 1. One unfold at a time
- A new view object, `HudState` (`game/ui/`, `RefCounted`, no Node), holds which panel is
  unfolded: `NONE`, `DRAWER`, `RADAR`, `ECONOMY` or `PAUSE`. Opening one closes the open one (the
  last request in a frame wins, ADR 0024 §5). The command bar is not an unfold: it shows while the
  selection is not empty, in battle, `RADAR` and `ECONOMY`, and in landscape beside the open drawer
  (the portrait sheet covers it); never in `PAUSE`. Placement and the strike aim stay the input
  modes of P86 and P112; starting either closes the unfold (as ADR 0024 §5 collapses the menu).
- **Placement and the strike aim freeze the bottom layout.** While either mode runs, the command
  bar keeps the slot it had when the mode began (shown or not), so BUILD's portrait lift (§9) and
  the strike button and its check mark and X above it never move under the thumb: a group tap
  during the aim (the groups still select, HOW_TO_PLAY's Superweapon row) changes the bar's chip,
  not its slot; a selection that empties leaves an empty plate until the mode ends. This keeps
  Michael's R1 (ADR 0024: "the strike row's check mark and X do not move under the player's
  thumb"). The layout follows the selection again when the mode ends.
- **A gesture on the map closes the unfold** (`TouchInput.map_gesture`, ADR 0024 §5: tap,
  double-tap, long-press, pan, pinch, ghost drag, wheel), except a pinned full map (§7) and `PAUSE`
  (a modal panel that takes every touch). The gesture still does its own work: the tap that closes
  the drawer also moves the selected units (ADR 0024 §5, Michael's "pan, select, order" of
  2026-10-31). A touch on a HUD control closes nothing by itself (only opening another unfold
  does), except the economy card, which any next touch closes (§3).
- **The game runs on** behind every unfold but `PAUSE`. The state is view state: no Command,
  nothing in the sim, the replay or the hash. A turn keeps it; a new match starts at `NONE` with the
  drawer closed. This drops ADR 0024 §1's accepted "a match starts OPEN" (the drawer covers 40-50 %
  of the screen, and the design's battle state is the empty field), so Michael confirms it
  (question 8).

Status note (2026-11-03, the docs row after wave y; P119c #271 and P121 #278 as merged; the text
above stays as accepted): "starting either closes the unfold" has the same exceptions as a map
gesture: **a pinned full map stays open** through the start of placement and of a strike aim
(`HudState.mode_started` folds the drawer, the economy card and an unpinned full map), as the
`GhostControls.clear_of` list in `scenes/main.tscn` (which names `RadarMap`) implies.

### 2. The corners
Sizes in dp, inside the safe rect (`SafeAreaMargin`: the OS insets plus 12 dp, the larger inset on
both ends of an axis, ADR 0015 §3). The design's safe zones (landscape 59 pt sides and 21 pt bottom,
portrait 59 pt top and 34 pt bottom) are an iPhone's; the OS insets govern, and the plan adds a
test profile with the design's insets (`ui_profiles.notch_design`). Gaps 8 dp.

| Part | Landscape | Portrait | Shows |
| --- | --- | --- | --- |
| Pill (§3) | Top left (until P124 after the Dev button, as P85d's pill), 48 high, width to content: the power bar takes what is left (P85c's fit), least about 200 dp | Same | Always but under the drawer and pause |
| Radar scope (§7) | Top right, 56 round | Same | Always but under the landscape drawer and pause |
| Toast (§8) | Centred in the room between the pill (or the safe left edge while the pill hides) and the scope (or the open drawer), 48 high, at most 280 wide | Under the pill (8 dp gap), the safe width, at most 360 | 4 s per cue; never while the full map is open (§8) |
| BUILD (§4) | Bottom right, 64 round | Bottom right; 8 dp above the command bar while it shows (§1's freeze) | Always but under the drawer and pause |
| Ready chip (§4) | Left of BUILD, 8 dp gap, 48 high, at most 112 wide | Same | While a structure is ready (until P130) |
| Strike button (§10) | 8 dp above BUILD, 72 round (`StrikeButton.SIZE_DP`, kept); its check mark and X to its left | Same | While the player owns a strike building |
| Command bar (§9) | Bottom left, 64 high, width to content, at most the safe width less BUILD's column (72), the Ready chip (120) while shown, the open drawer and their 8 dp gaps | Bottom, the full safe width | While something is selected (§1) |
| Group column (§9) | Left edge, in the room from the pill's bottom + 8 to the command bar's top - 8 (or the safe bottom), 56 x 56 buttons, as many per column as fit, further columns to the right | Left edge, above the command bar; its room ends at the 40 % line (below) | Always (question 3) |
| Full map (§7) | Under the scope when the room down to the right column's next part (the strike button, else BUILD) less 8 dp holds the 48 dp head and a 2:1 box at least 96 dp high; else left of the right column, its top at the safe top. The box is at most 240 x 120 | Under the scope, the box at most 260 x 130 | On a tap of the scope |
| Economy card (§3) | Under the pill, 280 wide | Same, the safe width at most | On a tap of the pill's numbers |

- **Touch targets** (CLAUDE.md, `touch-ui-rules`; the design's 44 pt is overruled, §15): the pill
  is 48 high and each of its three tap areas (menu, credits, power) at least 48 wide; group buttons
  56 (today's `ArmyBar.GROUP_DP`), the full map's pin and collapse 48, the drawer's close 48, the
  toast 48 high, queue items 56, tabs 48, order buttons 64 high and at least 56 wide.
- **One layout function.** `HudCorners.place(safe_rect, portrait, dp, mirror, shown) -> rects`, a
  static pure function in `game/ui/HudCorners.gd`, gives every part's rect; the scene applies them.
  `shown` says which optional parts are visible (command bar, Ready chip, strike button, full map,
  toast, open drawer, the group count). No part overlaps another, every rect is inside the safe
  rect. The share of the screen in battle (pill, scope, BUILD) is about 5 % on the 6-inch phone,
  landscape and portrait.
- **The numbers on the short screens** (the safe rect is the screen less 12 dp a side,
  `SafeAreaMargin`; one set of numbers, which the plan's tests pin):

  | Profile (screen dp) | Safe rect | Right column, from the bottom | Full map | Group column room | Items per column |
  | --- | --- | --- | --- | --- | --- |
  | `web_phone_small` (800 x 304) | 776 x 280 | BUILD y 216-280, strike 136-208 | with the strike button: left of the column, y 0-168 (head 48, box 240 x 120); without: under the scope, y 64-208 (head 48, box 192 x 96) | 152 with the bar (y 56-208), 224 without | 2 with the bar, 3 without |
  | `web_phone` (914 x 355) | 890 x 331 | BUILD y 267-331, strike 187-259 | with the strike button: left of the column; without: under the scope, y 64-232 (box 240 x 120) | 203 with the bar, 275 without | 3, 4 without |
  | 6-inch landscape (914 x 411) | 890 x 387 | BUILD y 323-387, strike 243-315 | under the scope, y 64-232 | 259 with the bar | 4 |
  | `web_phone_portrait` (360 x 700) | 336 x 676 | BUILD 8 dp above the bar: y 540-604, strike 460-532 | under the scope, y 64-242 (box 260 x 130) | to the 40 % line: 270 - 72 = 198 above the bar | 3 |

- **The 40 % rule in portrait** (ADR 0015 §5) holds for the bottom stack in battle: the command bar
  (64 + 8) and the group column (at most `floor((room + 8) / 64)` buttons per column, further
  columns to the right) stay within 40 % of the safe height (270 dp at 360 x 700); BUILD and the
  strike button stand in the right column (the bar 64, BUILD 8 + 64 and the strike button 8 + 72:
  216 dp from the safe bottom).
  Five group items at 360 x 700 take two columns (120 dp wide), which leave the Ready chip and BUILD
  their 184 dp on the right (336 dp safe width).
- **What leaves:** the portrait band and strip, the landscape floating panel and plate, `StatusPill`,
  `MinimapSlot`, `SelectionPanel`, `ArmyBar` and the Dev button on the battle screen (the dev menu
  moves into the pause menu, §11). Their logic is reused where the table names it.

Status note (2026-11-03, the docs row after wave y; P119 #268, P119b #276, P120 #285 and P123 #284
as merged; the text above stays as accepted):
- **Tabs are 56 dp high** (`BuildSidebar.TAB_DP`), not 48: an icon over a 14 sp name needs 53 dp.
  §5's budget changes with it (§5's note).
- **The toast's least width** is `HudCorners.TOAST_LEAST_DP`, 200 dp. Where the landscape room
  between the pill and the scope (or the open drawer) is narrower, the toast stands under the top
  line instead: from the pill's start, 8 dp below the lower of the scope's foot and the top-left
  stack (Dev over Surrender until P124, `Shown.left_height`), no further right than the open drawer
  or the safe edge (the P120 x P123 interaction fix). In portrait it stands 8 dp below the lower of
  the scope's foot (56) and that stack, so at y 64 at least, not under the pill's 48 dp line.
- **One overlay** (a lead decision, 2026-11-02): "No part overlaps another" holds for every part
  but the economy card. The card is transient (any next touch closes it) and may cover the toast,
  the group column and, on the short landscape screens, the command bar; it touches the scope's
  foot with no gap.
- **Until P120d** the pill stays beside the open drawer (`Shown.pill_over_drawer`), so the economy
  shows once.
- **The 8 dp gaps** are tested on the pure function (`test_hud_corners.gd`), with one exemption
  beside the card's: at 360 x 700 dp with five group items the strike aim's check mark and X touch
  the group column's second column with no gap (the numbers above: a 120 dp column, the 136 dp
  row, 8 dp and the 72 dp button make 336 dp). **Lead decision (2026-11-03):** in portrait, while
  a strike aim is shown, the group column holds at most three items in one column and the rest
  scroll. The strike row (check mark and X, 136 dp) is not moved or squeezed. P122b implements
  it, and the test's exemption goes with it.

Status note (2026-11-03, P26ar docs; P122b #296 as merged; the text and the note above stand):
- **The group column's "Always"** in the table: but hidden under the portrait drawer sheet, which
  covers its place (P119's rule on main since #268; `GroupColumn` keeps it).
- **A hold on a group with no units selected does nothing** (a lead decision, 2026-11-03), the same
  rule as "+" (§9): a resting finger never empties a group.
- The portrait strike-aim rule above (three items in one column, the rest scroll) is as merged.

### 3. The economy pill and its detail card
- **Content:** the menu button (48 x 48, `glyph_menu`, opens `PAUSE`), a divider, the coin and the
  credits (tabular figures, `CREDITS_DIGITS` wide as today), the bolt and the power bar (P85c's
  rule: used against made, the numbers where they fit). It replaces `StatusPill` and the band's and
  strip's `Status` line: one node, in both orientations.
- **Spend and income flashes** (view only, from two published snapshots): a fall in credits shows
  a red chip "-600" for `economy_flash_ms` (`data/input_settings.tres`, 1000) while the shown
  number counts down to the new value; a rise shows a green chip "+180" (a tanker's delivery and a
  refund alike). The number and the chip change text only when the shown integer changes, at most
  once per frame, never a string per frame at rest.
- **Low power** (`power_used > power_made`): the pill's border and the bar turn danger red, the bolt
  becomes the warning triangle (P85c) and the word "LOW POWER" shows: a word, a shape and a colour.
  P89's pulse goes on this node. GDD: low power slows production (`low_power_percent`) and takes
  defences offline; the card's text says that, nothing about the radar (§7).
- **Detail card:** a tap on the credits or the power opens a card under the pill (`ECONOMY`):
  credits with "+N/min" (the view's difference of the snapshot's `stat_harvested` over the last 60 s
  of match ticks, from a ring of 60 one-second samples allocated once), the number of the player's
  tankers; power used / made and the consumers (each own building type that uses power, its display
  name and the sum it uses, as chips). Any next touch closes it (on the card too), and that touch
  then does its own work. All values come from the snapshot; nothing new is asked of the sim.
- **Hidden while the drawer is open:** the drawer's head shows the economy (§5), so it never shows
  twice (the design's rule 4).

### 4. The BUILD button
- 64 dp round, the accent plate, `glyph_menu_open` (P85g, drawn for "open the build menu") over the
  word "BUILD" (Big Shoulders, upper case). A tap opens `DRAWER`. It replaces ADR 0024's Build
  button (M1) and stays in place of the plate and the strip.
- **Ring:** a 4 dp arc round the button, the progress of the item that finishes first among the
  player's queue heads (the least work left at the current rate), clockwise from the top. After
  ADR 0026 a construction counts as an item. Redrawn when a snapshot is published (15 Hz), not per
  frame.
- **Count badge:** the number of items in all the player's queues (plus the construction after
  ADR 0026), on a white disc at the top right; hidden at 0.
- **Stalled** (the design's "waiting", re-meant): when no queue head advanced between the last two
  published snapshots while some queue is not empty (no producer, the producer blacked out, the unit
  cap or no free exit; a finished structure waiting to be placed does not count, it shows the Ready
  chip), the ring turns grey and stops and an "!" badge shows (a shape, not colour alone). The design's reason, "no credits", cannot happen: items are paid when queued (ADR 0018
  §5, question 2 A of 2026-10-22); a pay-later queue is question 6, not this ADR. Low power slows
  the ring and is not "stalled".
- **Ready chip** (interim, until ADR 0026's UI row P130): while a finished structure waits at the
  head of the Structures queue, a "Ready" chip (the card's picture and the word, ADR 0024 §9's
  badge, 48 dp high, at most 112 wide, an entry of `HudCorners`' `shown`) shows left of BUILD; a
  tap opens the drawer on the Structures tab with the READY card in view (ADR 0024 Q1 A kept).
  ADR 0026 removes the READY state and the chip with it.

Status note (2026-11-03, the docs row after wave y; P120 #285 as merged; the text above stays as
accepted): a finished structure waiting at the Structures head has no work left, so it is the item
that "finishes first" and **the ring shows full** until it is placed (until P130).

Status note (2026-11-03, P26ar docs; lead decisions on P120c #295, as merged; the text and the note
above stand):
- **Stalled** means that no queue head advanced between two published snapshots. Low power is no
  exception and needs none: on low power alone, every head still advances, at
  `low_power_percent` (a unit head at the cap or with no free exit does not). So a producer that is
  blacked out (or destroyed) on low power is a stall like any other.
- A pinned full map on very short screens during the strike aim: see §7's note.

### 5. The build drawer
- **Container:** ADR 0024's clipping holder and slide (M1): `menu_slide_ms` (160) drives the
  drawer in from the right edge in landscape (the width slides) and up from the bottom in portrait
  (the height slides); input never waits; a turn ends the slide at its target. `BuildSidebar`
  keeps its class name, its tests and its wiring; P120 rewrites its layout (a rename is not worth
  the churn).
- **Landscape: a side panel** at the right edge, the full safe height, 40 % of the screen width,
  clamped to [312, 420] dp (three 88 dp cards, two gaps and 16 dp padding each side is 312); its
  backdrop runs to the screen's right edge, its content stays in the safe rect. It covers the scope
  and the right column; the pill hides (§3). On a short screen the card grid scrolls: on
  `web_phone_small` (280 dp safe height) the head (48), the tabs (48), the queue row (56 and its
  20 dp label) and three 8 dp gaps leave 84 dp, less than one 96 dp card row, so the grid is a
  vertical scroll there (a test pins it).
- **Portrait: a bottom sheet** of the full width and half the screen height, at least the head,
  the tabs, one row of cards and the queue row (about 312 dp); taller content scrolls inside the
  sheet. The command bar and BUILD hide under it; the pill hides; the scope stays.
- **Swipe to close** (the design's rule; a lead decision of 2026-11-01): a drag toward the edge the
  drawer came from, past `drawer_swipe_dp` (`data/input_settings.tres`, 48), closes it. In
  landscape any horizontal drag on the panel counts (the grid scrolls vertically); in portrait only
  a drag that starts on the sheet's head with its handle counts, because the grid's own scroll is
  vertical. ADR 0024's "Alternatives" left a swipe for later; this takes it, for closing only.
- **From the top:** the head (48 dp): the economy (credits with "+N/min", the power bar with
  "used/made POWER") and the close button (48 dp, a chevron towards the edge it leaves by); the tabs
  (48 dp, an icon and the name: Structures, Infantry, Vehicles; never "Base", §16); the card grid;
  the queue row.
- **Cards:** 88 x 96 dp (landscape) and 92 x 100 dp (portrait) at least; the columns are as many as
  fit (three in the landscape panel; upright three on the 6-inch phone and at 360 dp, four on a
  screen about 450 dp wide or wider), never fewer than two. A card shows the item card picture
  (P85e), the name and the price (tabular). States, each
  with a shape as well as a colour (ADR 0019 §1's tile states kept and named as the design names
  them): **ready to buy** (available); **in production** (the head: the picture fills with the
  percent, "xN" badge); **queued** ("xN" badge, no fill); **selected** (the structure that started
  placement, accent border); **too expensive** (red price and stripes; a tap shakes it, as today;
  see question 6); **queue full** (P85b's FULL, stripes and a "FULL" word, the shape the review
  asked for); **locked** (padlock, dimmed, and the words "Needs <display_name>" of the missing
  requirement or producer); **ready** (structures, until P130: "Ready" banner; a tap starts
  placement).
- **Taps:** a unit card: +1 (`QUEUE`). A long-press on a unit card (`long_press_ms`): as many
  `QUEUE`s as the queue has room for and the credits pay, at most `queue_hold_count`
  (`data/input_settings.tres`, 5) (answer 2 A; before it the long-press cancelled the last one of
  the type, ADR 0019 Q2). A structure card: as today until P130
  (queue it, or start placement when it is ready), then ADR 0026's tap-to-place.
- **Queue row** (the open tab's queue): the producer's display name and "N IN QUEUE" (after
  ADR 0026, on Structures: "CONSTRUCTION" and the building's name and percent, or "NOTHING
  BUILDING" with the hint "Tap a building, then place it on the map"), then one 56 dp thumb per item,
  the head with a progress bar, empty slots dashed. **A tap on an item cancels it** (`CANCEL [tab,
  slot]`, full refund, ADR 0018 §5) with the haptic. After a cancel the row ignores taps until the
  next published snapshot shows the queue again, so a quick second tap never sends a slot index the
  first cancel has shifted. The design's repeat button is dropped: no repeat production exists.
- **Opens** on BUILD, on the Ready chip (Structures tab) and on a tap that selects an own producer
  (its tab; ADR 0024 Q3 A kept); after a placement that began in the drawer ends by a build or the
  X (ADR 0024 R1 kept; a strike aim leaves it closed). **Closes** on its close button, a map gesture
  (§1), a swipe, the start of placement or of a strike aim, `PAUSE`. No pin (§6).

Status note (2026-11-03, the docs row after wave y; P120 #285 as merged; the text above stays as
accepted):
- **Budget:** with the 56 dp tabs (§2's note), `web_phone_small`'s head (48), tabs (56), queue row
  (56 and its 20 dp label) and three 8 dp gaps leave **76 dp**, not 84; the grid still scrolls
  there. P120b re-checks the budget with its queue row.
- **The restart:** whether the drawer returns after a placement (R1) is decided when the placement
  first begins. READY tapped again in a drawer the player opened with BUILD during the placement
  restarts the ghost and closes the drawer, but does not set the return: the drawer comes back at
  the end only if it was open at the first start.

Status note (2026-11-03, P26ar docs; lead decisions on P120d #293, as merged; the text and the note
above stand):
- **The head's economy line takes no touch:** the economy card (§3) opens only from the pill, which
  is folded while the drawer is open (§1: one unfold at a time).
- **No "POWER" caption** in the head: the bolt, the numbers and LOW POWER carry it.
- **The head's height:** upright 54 dp (the handle's 4 dp and a 2 dp gap above the 48 dp line);
  sideways it stays 48 dp.
- **The toast** beside the open drawer, with the pill folded, is checked against the top-left stack
  for plain no-overlap, not for §2's 8 dp gap.

Notes (2026-11-04, P26aw docs; P120b #320 as merged; the text and the notes above stand, except
where a note below says what it replaces):
- **The locked card** (Michael's decision, 2026-11-04): it shows the padlock and the missing
  building's full display name, with no "Needs" prefix and no ellipsis; this replaces the words
  "Needs <display_name>" above and "("Needs <name>")" in §19's P120 row. The name takes at most 2
  lines at 14 sp inside the stage, so a long name ("Cracking Plant", "Synthesis Works") is never
  cut. The padlock is then 14 dp, at the top left of the stage, clear of the count badge.
- **The budget on `web_phone_small`** is about **53 dp** for the grid, not the 76 dp of the note of
  2026-11-03 above: the drawer's padding counts too (sideways, the panel's 8 dp top and bottom and
  the pad's 8 dp at the foot). The grid's least height is 48 dp (`BuildSidebar.FIT_LEAST_DP`) and it
  scrolls. A whole 96 dp card row would need about 43 dp more; the 56 dp queue thumbs can give at
  most 8 dp before the 48 dp touch floor, so the grid scrolls instead.
- **The queue row's wait after a cancel** ends when a snapshot is past the tick the runner stamped
  on the CANCEL, when the tab changes, or when a match restarts. This replaces "until the next
  published snapshot shows the queue again" above, which is not enough: on Android (WORKER mode)
  the first snapshot after a tap is published before the Command is drained into a tick, so it
  still shows the old queue, and this wait is what stops a second tap from hitting a shifted
  slot.
- **A hold on a unit card is final** once it fires at `long_press_ms` (the tile's `hold_ms`; as a
  group hold in ADR 0004 §5): a drag after that does not take back its QUEUEs.

Notes (2026-11-05, P26ax docs; Michael's decisions on the build drawer, row P120e; they replace the
text and the notes above where they say so):
- **The pill stays in its corner** while the drawer is open, in both orientations (sideways it ends
  a gap short of the side panel; upright the sheet is below it). This replaces "under the drawer"
  in §2's table for the pill, §3's "Hidden while the drawer is open" bullet and "the pill hides"
  twice above: P120d's economy line in the head goes, and the P26ar notes on it lapse. A tap on
  the pill's credits or power with the drawer open opens the economy card and closes the drawer
  (§1's one unfold).
- **The close chevron sits at the right end of the tabs row** (at least 48 dp wide, as high as the
  tabs). The head row goes ("From the top: the head (48 dp) ..." above); upright the grab handle
  stays above the tabs, and the swipe to close starts on the handle or the tabs, replacing "a drag
  that starts on the sheet's head with its handle".
- **The cards fill the drawer's width:** as many columns as fit, every tab the same count (two or
  more on every supported screen; the code keeps no floor, so "never fewer than two" above is no
  longer a coded rule), the cards stretched so a full row ends at the right edge with the left
  margin; a shorter row keeps the column width and leaves the rest empty.
- **No queue row** (P120b's goes; Michael found it did not fit). **A long press on a card cancels
  the last one of its type in the queue** (`CANCEL`, full refund, the haptic; infantry, vehicles
  and structures alike); on a card with none queued it does nothing. A tap queues one. This
  replaces the "Queue row" bullet and the long-press's "as many `QUEUE`s ... at most
  `queue_hold_count`" above (`queue_hold_count` goes); the hold cancels again, as before answer
  2 A. The P26aw notes stay for the hold: it is final once it fires (a drag after it does not take
  back its CANCEL), and after it every hold does nothing until a snapshot is past the tick the
  runner stamped on that CANCEL, or a new match starts; a tab change no longer ends the wait.
- **What else lapses:** the sheet's least content "at least the head, the tabs, one row of cards
  and the queue row (about 312 dp)" (the least height stays 312 dp, `HudCorners.SHEET_LEAST_DP`),
  the grid budgets on `web_phone_small` above (84, 76 and about 53 dp; the grid still scrolls
  there), §2's "queue items 56" and the toast's "(or the safe left edge while the pill hides)".

### 6. What this does to ADR 0024's parts
| Part (ADR 0024) | Here | Why |
| --- | --- | --- |
| OPEN / COLLAPSED and the match starting OPEN | Drawer open or closed; a match starts closed | The battle state is the empty field (§1) |
| The portrait strip (96 dp) and the landscape plate (56 dp) | Dropped | BUILD, the pill and the scope carry what they held; 96 dp more map in portrait |
| The Build button | Kept as the round BUILD (§4) | M1 |
| The Ready badge | Kept as the Ready chip beside BUILD until P130, then dropped | ADR 0026 has no READY state |
| The pin (P85f2, not merged) | Dropped for the drawer (question 1); the glyphs serve the radar pin | A pinned side panel in landscape is a permanent right-hand column with the economy and a build grid, the Command & Conquer sidebar look that ADR 0023 §12 moved away from (§16); a pinned half sheet in portrait halves the field for the whole match; the design gives the drawer no pin |
| The holder and the slide (`menu_slide_ms`) | Kept for the drawer, sideways in landscape | M1 |
| `map_gesture`, "never a touch on a HUD control" | Kept; closes any unfold (§1) | M1 |
| `zone_changed`, `bottom_zone_dp`, `menu_top_px` | Kept: the drawer's height and real top in portrait (0 and INF while closed); in landscape 0 and INF (the panel is at the side) | Placement and the strike aim close the drawer, so the edge pan and `GhostControls` see a closed drawer; the command bar and BUILD are islands that `GhostControls.clear_of` lists |
| The return after placement (R1) and the producer tap (Q3 A) | Kept | Michael's answers stand |
| `GhostControls` (P86c) | Kept beside the ghost (M2); after ADR 0026 the check mark shows the price under its glyph ("600", tabular, 18 sp as `touch-ui-rules` asks of HUD numbers and as the theme's `ItemCost` is), which fits its 64 dp (32 dp glyph, a 22 dp line) | M2 |
| `HudPrefs` and `user://settings.cfg` | Kept as the settings file; first key `[hud] haptics` (§11) | P85f2's file without its key |

Status note (2026-11-03, the docs row after wave y; P120 #285 as merged; the table above stays as
accepted):
- **`bottom_zone_dp` in portrait while closed** is BUILD's 64 dp (`HudLayout.BUILD_ZONE_DP`), not
  0, until P122b replaces the ArmyBar; the ArmyBar adds its own 8 dp gap above it. Open, it is the
  larger of the drawer's height and 64. In landscape it stays 0 and INF.
- **`map_gesture`'s row:** "closes any unfold" means §1's rule: not a pinned full map, not `PAUSE`;
  a touch on a HUD control closes only the economy card (§1, §3).

### 7. The radar scope and the full map
- **Scope:** a 56 dp disc at the top right showing the ground round the camera: a crop of P88's
  `MinimapImage` texture (one texel per cell, the fog's cadence), drawn under the same iso skew as
  the full map (`IsoProjection.cell_to_px`), so up on the scope is up on the screen and the frame,
  the pings and the rim wedges point as the screen does; centred on the camera's ground centre, `scope_radius_tiles` (`data/input_settings.tres`, 16) to the rim, drawn as one textured
  polygon of 32 points (the Compatibility renderer, no shader), with the camera's frame as a white
  rectangle clipped to the disc. It redraws when the camera moves or the picture changes, not per
  frame at rest. A tap opens `RADAR`. It replaces `MinimapSlot`, and in portrait the minimap leaves
  the band's right end (ADR 0024 §2) for the top right.
- **Full map:** P88's `Minimap` node (the iso diamond, the fog, own and seen enemy rows in team
  colours, last-seen ghosts, the camera frame; its tap and drag jump the camera; P88b's long-press
  with units selected sends `MOVE`) unfolds under the scope, right-aligned, with a 48 dp head:
  "RADAR", the pin (P85g's `glyph_pin` and `glyph_pin_off`) and the collapse button (48 dp each).
  The head says no "ONLINE": the radar is never offline here.
- **Closing:** the collapse button, a map gesture (unless pinned), opening another unfold, or
  `radar_close_ms` (`data/input_settings.tres`, 4000) without a touch on it unless pinned, counted
  in frame time in `game/ui` (a test steps it). The pin is view state for the match, not saved.
- **Never offline.** The design's "offline" (noise, no blips) without a radar building or on low
  power is a new gameplay rule: the GDD says a radar unlocks artillery and the superweapon and low
  power slows production and silences defences, nothing about the minimap; and a radar building
  that switches the minimap on, or low power that switches it off, is Command & Conquer's
  (Communications Center, Radar Dome), which ADR 0023 §13 rejected ("radar is a tech gate, the
  minimap is always on"). It is question 5, recommended no.
- **What P88 and P88b keep:** the picture, its cadence, the frame, the jump, the long-press `MOVE`;
  P88b lands on the `Minimap` node as planned, and P121 moves the node.

Status note (2026-11-03, P26ar docs; a lead decision on P120c #295, as merged; the text above stays
as accepted): on very short screens (a safe width under about 680 dp; the test rig's
`tiny_short_landscape` is 680 dp wide with 656 dp safe, while 728 dp with 704 dp safe keeps the
map open), a pinned full map cannot stand beside the pill and the strike aim's row (§10) even at
its least width. It folds when the aim begins (the pin stays), and a tap on the scope opens it
again after the aim. A follow-up row will let `HudCorners` leave MAP out instead.

### 8. Attack cues
- **Detection** (P89's rule, moved): a `SHOT` or `IMPACT` event on an own row whose point is
  outside the camera's visible world rect raises one cue per area (`attack_cue_area_tiles`) and
  interval (`attack_cue_ms`), both in `data/input_settings.tres` (ADR 0019 §5). The cue reads the
  published events only.
- **Toast:** a 48 dp panel at the top (§2's place), danger border and the
  warning glyph, "<display_name> UNDER ATTACK" (the hit row's own `display_name`, "UNITS UNDER
  ATTACK" for a unit) over "Tap to jump there", for `attack_toast_ms` (4000); a newer cue replaces
  it. A tap jumps the camera to the point and closes the unfold. The design's place words ("Oil
  field, south") need map region names, which do not exist; not shown. **While the full map is
  open no toast shows** (the design's rule: an attack is then a ping on the map); in portrait both
  would stand at the top right.
- **Scope rim:** a red wedge on the scope's rim in the direction of the attack (from the camera's
  ground centre) for the same time, with the shape of a wedge, not colour alone; an attack inside the
  scope's radius pings inside it instead. **Full map:** a ping at the point.
- **Replaces** P89's screen-edge arrows (ADR 0019 §5's "arrow of at least 48 dp at the screen
  edge"): the rim marker is the direction cue, the toast the jump. touch-ui-rules' "edge-of-screen
  indicator" becomes the rim marker on acceptance (§18). P89 keeps the
  low-power part: the glyph on each consuming building and the pill's pulse.

Status note (2026-11-03, the docs row after wave y; P123 #284 as merged; the text above stays as
accepted):
- **Detection** also counts the `DIED` record of an own row (a lethal hit leaves no row to read a
  `SHOT` or `IMPACT` target from), except a cancelled site's (ADR 0026 §6's flag).
- **The numbers:** `attack_cue_area_tiles` 12 and `attack_cue_ms` 4000 were placeholders with no
  planned values (the plan's "P89's planned values" never existed); Michael's phone test of
  64f0402 accepted them as they are (2026-11-03).
- **Open question (a later row; not decided here):** a superweapon strike on the local player's
  buildings out of view raises no cue: `Strike._land` writes no `SHOT` or `IMPACT`, and a blackout
  writes neither, so only a row the rupture kills raises one (by its `DIED`). This section
  is silent on strikes. Whether a strike should raise its own cue (perhaps from P133's `STRIKE`
  event) is for a later row, with Michael if it changes what the player is told.

### 9. The command bar, the groups and the portrait BUILD lift
- **Shows** as §1 says (and keeps its slot through placement and the strike aim). It holds, from
  the bar's start:
  - **Deselect** (Michael's answer 4): a 48 x 64 dp button (the bar's height) at the bar's start,
    before the chip; `glyph_deselect` (P118g: the oval selection ring the game draws under a
    selected unit, broken by a diagonal stroke; not the padlock, which means "a requirement is
    missing", and not `glyph_cross`, which is placement's and the strike's X and ADR 0026's Cancel)
    over the word "CLEAR". A tap clears the whole selection (`SelectionModel`, as an empty box does
    today): units or a building, own or an enemy building selected for its info; the rings and the
    frame go and, outside placement and the strike aim, the bar hides. It is view and input state
    only: no Command, nothing in the sim, the replay or the hash. **Why the start:** it acts on the
    selection the chip shows, so it sits beside the chip, apart from the orders that send Commands;
    its neighbours are the screen edge and the read-only chip, so a miss never sends an order and
    an order's miss never clears; in landscape the bar's start is the bottom-left corner under the
    left thumb, in portrait the left end (left-handed mode mirrors it). **During placement and the
    strike aim** it still clears, and §1's freeze holds: the bar keeps its slot as an empty plate,
    so BUILD, the strike button and its check mark and X do not move until the mode ends. A tap on
    the chip itself stays read-only; making it narrow the selection to that type is a possible later
    order, not planned. Screened (§16): "Deselect" and "Clear" are plain words and no RTS this ADR
    screens has such a button.
  - **The selection chip** (64 dp): the first type's item card picture, "xN" and the health of the
    selection (a bar of the summed hp against the summed max). More types show a "+N" chip;
    a building shows its picture, name and health, an enemy building its amber frame and notch
    (P115b). It replaces `SelectionPanel` and keeps its fit rule (the chips that fit, then "+N").
    The design's "x2" badge is the count.
  - **Orders, only those the game has** (the lead's rule; checked in `game/sim/Command.gd` and
    `game/input/PlayerController.gd`): **Stop** (`STOP`, which the sim takes and nothing sends
    today): one tap, one Command, for units. **No Attack button and no attack-move mode**
    (Michael's answer 4): a ground tap stays a `MOVE` that stops an attack and a tap on an enemy an
    `ATTACK`, as CLAUDE.md's Mobile UX line says; the design's ATTACK button is not taken.
  - **Later orders slot in:** the bar is a row of 64 dp buttons from a list (an order id, a glyph, a
    label, a visibility predicate on the selection); a row that adds an order adds a list entry, its
    glyph and its HOW_TO_PLAY line. Guard, Patrol and Scatter (units) and Repair, Sell, Rally and
    Primary (buildings) are not in the game (ADR 0023 §8); the bar shows none of them. Rally stays
    the ground tap with a producer selected (P87). A building's orders today: none (its chip only);
    ADR 0026 adds Cancel for one under construction.
  - **Overflow:** more orders than fit scroll sideways inside the bar; a button never shrinks below
    56 dp.
- **Portrait BUILD lift:** while the bar shows, BUILD (and the strike button above it) stands 8 dp
  above the bar's top (the design's y 744 against 818); they move without a slide when the bar
  appears, as the selection changes under the player's tap, and never during placement or the
  strike aim (§1's freeze).
- **Groups** (replacing `ArmyBar`): a column on the left edge (landscape: below the pill; portrait:
  above the bar; §2 gives its room and the columns). On top **"All army"** (56 dp, an icon and
  "ALL", question 3), then each saved
  group (1-3, `SelectionModel.GROUP_COUNT`) with its number and count, then **"+"** while units are
  selected and a group is free. Tap a group: select it. Tap "+": save the selection into the lowest
  free group, with the haptic. Long-press a group (`group_assign_ms`): overwrite it with the
  selection, with the haptic. An empty group is not shown. This changes today's "hold 1-3 to
  assign" into "+" to save and a hold to overwrite (the design's rule); the group numbers and
  `SelectionModel` stay.

Notes (2026-11-04, P26aw docs; P122 #321 as merged; the text above stays as accepted):
- **Stop also works during placement and the strike aim** (a lead decision): it is a tap on the
  HUD, not on the map, and this section names no exception.
- **The chip's label** asks for its text's width, capped at 140 dp (`CommandBar.LABEL_MAX_DP`), and
  the bar grows with it, so a building's name is not cut to the health bar's width.
- **A fogged enemy building** selected in the chip shows no health, as `HealthBarLayer` hides its
  bar.
- **The bar is a plain Control.** Only the chip uses the theme variation `SelectionPanel`, which
  keeps its name although the `SelectionPanel` node is gone.
- **Not in P122:** the chip's fit rule (above: "keeps its fit rule (the chips that fit, then
  "+N")"; P122 shows the first type's chip and "+N") and an enemy building's amber frame and notch
  (above: "an enemy building its amber frame and notch (P115b)"). Both go into P122c's row of
  `docs/plans/2026-11-01-hud-v2.md`.

### 10. The strike button
- The strike button (P112, 72 dp: `StrikeButton.SIZE_DP` with its 40 dp card, 6 dp ring and foot
  label, kept) moves from the top line (landscape) and the right edge (portrait) to 8 dp above
  BUILD, in the thumb zone with the other actions; its row (the check mark and X, 64 dp,
  ADR 0024 §10's last bullet) stands to its left. It rides with BUILD's portrait lift. Nothing else
  of P112 changes. The design has no superweapon; the game has, so the HUD shows it (the lead's
  rule).

### 11. The pause menu
- **Opens** on the pill's menu button; **pauses the match** (`MatchRunner.paused = true`; the sim
  only stops ticking, no Command, so replays and hashes do not see it); closes every other unfold;
  a modal panel over a dimmed field. **Resume** unpauses; a turn keeps the menu open and the match
  paused.
- **Card:** "SKIRMISH" and the map's display name; the objective "Destroy the enemy Headquarters and
  every production building" (GDD victory rule); the time and "Units lost" (P76's stats). No mission,
  no difficulty (no campaign in version 1; difficulty is Phase 4).
- **Buttons** (64 dp high, the full column width): **Resume**; **Restart** (P90's "Play again": the
  same scenario, a new match; confirm); **Surrender** (P90's `SURRENDER`, its confirm dialog; the
  top-left button P90 adds moves here); **Exit to menu** (confirm; the dev menu until Phase 5's
  start page, through `DevRoutes`); in debug and `dev_menu` builds a **Developer menu** entry (the
  battle screen's Dev button goes). Confirms only for Restart, Surrender and Exit (the design: "only
  for Surrender and Exit"; Restart loses the match as well).
- **Toggles:** **Vibration** (the only one whose feature exists: it gates every `vibrate` call
  through one setting, saved as `[hud] haptics` in `user://settings.cfg` by `game/meta/HudPrefs.gd`,
  default on; `touch-ui-rules` already says the haptic "can be turned off in settings"). Sound and
  Music come with Phase 5's audio, Settings with Phase 5's settings screen; until then they are not
  shown.
- **No ad**, ever (admob-policy: "Battle, including pause: never"); the design's banner is dropped
  (§15).

Notes (2026-11-05, P26ax docs; Michael's design for the pause menu, row P124b, and his decision on
its banner; they replace the text above where they say so):
- **The look** follows Michael's design: "PAUSED" at the top left over the dimmed field (the HUD's
  controls are hidden under the menu); a card with the side's emblem, "SKIRMISH", the map's name,
  the objective as an open check line, and Time and Units lost; one column of buttons, full width
  under the card upright and right of it sideways: Resume (56 dp, filled with the side's accent),
  Restart, Surrender (word and glyph in danger red), Exit to menu and, in debug and `dev_menu`
  builds, Developer menu (48 dp each, replacing "64 dp high"; the confirm dialogs keep 64 dp); the
  Vibration chip below them. Settings, Sound and Music stay hidden until their features exist
  (Michael).
- **A banner at the menu's foot** (Michael, 2026-11-05): this replaces "No ad, ever ... the design's
  banner is dropped" above and row 11's "no ad" in the decisions table. It shows only while the
  menu is open, below the last control and at least 16 dp from any button, never beside, between
  or over controls. It applies where the foot is free: upright, below the Vibration chip. Sideways
  the column reaches the safe bottom (P124b), and on short screens the menu scrolls: there it shows
  no banner until P127's row decides. It is built with the menu banners (P127's row), not in
  P124b; CLAUDE.md and `admob-policy` say so.

### 12. The start page (Phase 5)
- Built by ROADMAP Phase 5's "Main menu" box, not in this wave (a decision from the roadmap, not a
  question: ADR 0019 §7 Q4 keeps
  the preview opening on the controls test until then, and a start page with one working button is
  a menu screen to maintain twice.
- **Content when built:** the title "TREADLINE" (ADR 0006); the two sides with their emblems and
  names, "DERRICK LEAGUE vs LUMEN ACCORD" (ADR 0023 §6), each name in its side's accent; a tagline
  in the energy-bloc framing (the design's "Oil runs along the border. Two blocs want it." is the
  border framing ADR 0023 dropped; proposed "Oil and gas against wind and sun. Choose your side.",
  which Michael confirms or rewrites in P126's PR, where it first shows); **Skirmish** (the route P90 makes per faction); a settings button (the Phase 5
  settings screen); the version line ("v<version> · © AppCode ApS"). Continue (save and resume,
  Phase 5's local save) shows only once a save exists; Campaign and Multiplayer are not in version 1
  (GDD) and are not shown.
- **Ads:** a banner only when Phase 6's `AdService` exists, at the bottom, with "Advertisement" over
  it and 48 dp of air to the nearest button (the design's gap; stricter than admob-policy's floor
  of 16 dp, so it is kept); the "+500 starting credits"
  rewarded offer is Phase 6's. Both orientations as the boards show.

### 13. Look: theme, fonts and the accent
- **Tokens** (the design's, art-director owns them in STYLE.md and `theme.tres` is the value of
  record, as for the backdrop): panel rgba(10,14,17,0.84) with no blur (a flat StyleBoxFlat:
  cheap on weak phones); border #2C383E; money and power #F2C14E; danger #FF5A3C; ok and income
  #6EDC5F; text on the dark panel white. The design's fixed "enemy" #FF9446 is not a HUD token:
  rows on the radar keep their team colours (P88), and #FF9446 is almost the Derrick League accent.
- **Accent per side** (the design's rule 6 mapped to our factions): **Lumen Accord: cyan**
  #1FA6C8, light #62D6EE, text on accent #05202A (the design's values); **Derrick League:
  orange**, the natural fit to its flare stacks and amber lamps; art-director picks the pair in P118
  with two checks: a hue at least 15° from danger (#FF5A3C, about 9°) and from money (#F2C14E,
  about 42°), and text on accent at contrast 4.5:1 or more (a starting point: #E07B2A, light
  #FFAE5C, text #2A1405). The local player's side is the faction of its own rows (P85d's rule).
  Accent never carries meaning alone. The team colours stay per player (GDD), so a Lumen Accord
  player 1 sees orange units under a cyan HUD unless the routes give the local player its side's
  colour (answer 7 ja: the routes do, and the GDD's team-colour line says so, P26ap).
- **Fonts (M4):** **Big Shoulders** (weight 800) for buttons and titles, upper case, tracking +6 to
  +14 %; **Chakra Petch** (500 to 700) for numbers and body text, tabular figures (OpenType `tnum`)
  for every number that changes. Home: **`assets/art/fonts/<family>/`**, the folder `STYLE.md`
  ("Reskin", item 3) and `theme.tres`'s header already name for a new font (the lead's brief said
  `assets/fonts/`; the existing rule wins unless Michael says otherwise). Each family's folder holds
  the unmodified upstream font files and its `OFL.txt` (the SIL Open Font License 1.1 with the
  family's copyright line), one `assets/CREDITS.md` row per family (file, author, source URL,
  licence "SIL OFL 1.1", notes), and the OFL texts ship in every export beside
  `THIRD_PARTY_LICENSES.txt` (P118b). `STYLE.md` ("Reskin", item 3) and the `theme.tres` header also
  ask for the licence text "in the Licences screen", which does not exist yet: P118 amends both
  lines to "beside every build (P118b) and, from Phase 5's settings screen on, in its Licences
  screen", and the Phase 5 plan gets that screen. The fonts are referenced only from `theme.tres`
  (as `FontVariation`s: the `tnum` feature and the tracking), never from code:
  `tests/project/test_ui_theme_scan.gd` already flags a font class or `set_font` in a `game/ui`
  script, and P118 widens its font rule to every script under `game/` and `scenes/` instead of adding
  a scan. **The tracking needs no code:** one `FontVariation` per size class (button, title, big
  title) in `theme.tres` with its `spacing_glyph` in base px, listed in the file's
  `metadata/base_px` (the existing way to keep an entry out of `HudTheme`'s dp step); across the
  phones' dp-to-px ratios the tracking then stays inside the design's 6-14 % band. P118 checks three facts
  before committing: the families' Reserved Font Names (if any, the files stay unmodified: no
  subsetting under the same name), the glyph coverage of Danish and German letters (æ ø å ä ö ü ß;
  the GDD's later languages), and whether Chakra Petch has `tnum` (if not, the numbers use
  fixed-width digit slots in code, a named fallback). Their size in the web build is reported in the
  PR.
- **Sizes stay `touch-ui-rules`'**: body at least 14 sp, HUD numbers at least 18 sp.

### 14. Left-handed mode
- Later: the switch comes with Phase 5's settings (a scope decision from the roadmap, not a
  question). From P119 on, `HudCorners.place`
  takes `mirror` and swaps left and right for every part (the pill and the scope, BUILD and the
  command bar, the group column, the drawer's side in landscape); its tests run both. No other row
  reads the flag until the switch exists.

### 15. Where the design is overruled (constraints, each with its source)
| Design | Here | Source |
| --- | --- | --- |
| "Iron Meridian", "Taiga Union", "Concordia", the tagline, Warden, Trebuchet, Kestrel, Sentry, Caravan, Radome, Academy, Wellhead, Refinery, "Blackout · Mission 6" | Treadline; Derrick League and Lumen Accord; every label is our data's `display_name` (the design's Wind Park, Motor Works, Swift and Fuel Runner are Lumen Accord names of ours and show as data says) | ADR 0006; ADR 0023 §6, §13; lead's rule |
| Accent cyan for Concordia, orange for Taiga Union | Lumen Accord cyan, Derrick League orange (§13) | ADR 0023 §6 |
| Banner on the pause menu and the end screen | None in battle, pause or the match result; banners only in menus | admob-policy placement matrix; CLAUDE.md Monetization |
| Interstitial at most one per 3 min | One per 4 min, none in a new player's first 2 matches, one per completed match | admob-policy caps |
| Rewarded "double reward" on the end screen | The existing "Double XP" offer (Phase 6) | GDD Meta; admob-policy |
| 44 pt least touch target | 48 dp least, 56 for groups, 64 for BUILD, orders and placement's confirm | CLAUDE.md Mobile UX; touch-ui-rules |
| Guard, Patrol, Scatter; Repair, Sell, Rally button, Primary; repeat production; Campaign, Continue, Multiplayer; Sound and Music toggles; mission objectives | Not shown until the feature exists | GDD "Not in version 1"; ADR 0023 §8; lead's rule |
| Radar offline without a radar building or on low power | Never offline (question 5) | GDD; ADR 0023 §13 |
| "Too expensive" items still queue; BUILD "waiting for credits" | Pay at queue stays; "stalled" means a queue that cannot advance (question 6) | ADR 0018 §5 (question 2 A) |
| ATTACK as the default for a ground tap, and the ATTACK button | A ground tap moves (stops an attack), an enemy tap attacks; no Attack button or mode; a Deselect button instead (question 4) | CLAUDE.md Mobile UX; Michael's answer 4 |
| "BYG" | "BUILD"; every player-facing string English | CLAUDE.md; the design's own rule |
| The check mark and X in the BUILD corner | Beside the ghost | M2 |
| Tabs "Base, Infantry, Vehicles" | "Structures, Infantry, Vehicles" | ADR 0023 §13 (RA2's sidebar tabs) |
| Confirms only for Surrender and Exit | Restart confirms too: it throws the match away like Surrender (a lead decision, 2026-11-01) | lead |
| Start page: Continue, Campaign, Multiplayer | Skirmish and Settings; Continue once a save exists; the page itself in Phase 5 | GDD "Not in version 1"; ROADMAP Phase 5; ADR 0019 §7 Q4 |

The design's swipe to close the drawer and its 48 dp gap round a menu banner are taken as drawn
(§5, §12), not overruled.

Note (2026-11-05, P26ax docs): the row "Banner on the pause menu and the end screen" now holds for
the end screen only. Michael allows the pause menu's banner (§11's note of 2026-11-05), so its
"Here" cell's "pause" no longer holds.

### 16. Legal
- **The layout is not Command & Conquer's.** C&C's and Red Alert's sidebar is a permanent column at
  the right edge that stacks the radar, the credits, the power bar and a grid of build icons, always
  on screen. This HUD keeps the field clear: four small corner anchors in battle, the build drawer
  only on demand (closed by any map touch, never pinned, without the radar inside it, three or four
  columns of named cards with prices, tabs with words, a queue row with cancel), the radar a round
  scope with a fold-out map, the economy a pill. Corner HUDs with a round action button and a
  bottom sheet are the common mobile pattern, not one game's. The drawer's pin is dropped partly for
  this reason (§6).
- **Labels:** "Base" as a tab, "PRIMARY", "SCATTER", "GUARD" and the repair and sell buttons are
  Red Alert 2 sidebar or command labels (ADR 0023 §12, §13). None is used now; a later row that adds
  such an order screens its label against ADR 0023 §13's list first, and the lead adds it to the
  trademark list.
- **Generic HUD words, screened** (ADR 0023 §13 asks for the screen to be written down): "RADAR"
  (C&C calls its minimap the radar, and its announcer says "radar online" and "radar offline"),
  "LOW POWER" (the announcer's "low power"), "UNDER ATTACK" ("our base is under attack"),
  "BUILDING" and "CONSTRUCTION" ("building", "construction complete"); "CLEAR" on the Deselect
  button (§9; no screened game has such a button, and the glyph is a broken selection ring). Each is a plain English word
  for what it labels and stays as a word; what is not taken is the announcer's phrasing as a
  line: no "ONLINE"/"OFFLINE" status beside "RADAR" (the radar is never offline, §7), no "Base
  under attack", "Construction complete" or "Unit ready" text or voice. The toast names the hit
  building by its `display_name` instead.
- **Names and look:** no design name is used (§15); every glyph is drawn in this repository
  (P118g); the fonts are OFL and credited (§13). The design's note that place-first is "one step
  fewer than Red Alert's build, ready, place" names a game, not an asset: placing a foundation first
  is the common RTS pattern (StarCraft, Age of Empires, Warcraft), a mechanic, which the legal rules
  do not cover (ADR 0026).

Note (2026-11-05, P26ax docs): the drawer has no queue row any more (§5's note of 2026-11-05), so
§16's "a queue row with cancel" no longer applies; the rest of the list carries the point.

### 17. Performance and headless proof
- **Per frame at rest:** no work beyond today's: the HUD reads each published snapshot (15 Hz),
  the scope redraws only when the camera or the picture moves, the ring redraws per snapshot, texts
  change only with their integers. The slide's frame cost is ADR 0024 §8's (cached metrics, no
  `UiScale` call per frame). No per-frame allocation (the income ring, the cue table and the order
  list are allocated once).
- **Draw calls:** the battle state shows fewer HUD controls than today (the pill, the scope, BUILD
  against the band or panel, the minimap slot, the selection panel and the army bar); the open
  drawer about today's open panel. Each font is its own glyph texture, so a panel with both fonts
  takes a call per font change; the plan's phone card check (Michael's phone, not a session timing
  run) watches it.
- **Headless proof** (the plan's test plan): the layout function at the six sizes, the portrait
  profiles, the short landscape profiles and the design's notch profile, mirrored and not: inside the
  safe rect, no overlap, every target at least 48 dp, §2's table of numbers row by row; the freeze
  (a group tap during the strike aim moves nothing at the bottom); the unfold rules (one at a time, map gesture
  closes, pinned map stays, the economy card's next touch, the radar's timer stepped); BUILD's ring,
  badge, stalled look and Ready chip from crafted snapshots; the pill's flashes from two crafted
  snapshots; the cues from crafted events; the command bar's Stop and its Command, Deselect clearing the selection with no Command; pause sets
  `paused` and a scripted run with HUD actions ends with the same state hash as without them
  (P62's method); no ad node in the battle scene; the font files, OFL texts and CREDITS rows exist,
  `theme.tres` is the only reference to them.

### 18. What this amends, and the proposed `touch-ui-rules` text
Nothing is superseded whole; on acceptance the lead's docs row P26ap adds dated status notes (the
accepted texts stay):
- **ADR 0015 §5:** the battle-screen layout is the corner HUD (§2): no bottom band or strip; the
  portrait bottom stack is the command bar with BUILD lifted above it and the group column (at most
  40 % of the safe height, as before); the transient drawer may take half the height; the portrait
  top line holds the pill and the scope, the SelectionPanel's line and its fit levels move into the
  command bar's chips. The minimap is no longer at the bottom in portrait: the scope and its full
  map are at the top right (the often-tapped action, BUILD, stays at the bottom).
- **ADR 0019 §1:** the sidebar is the drawer (§5); the long-press cancel becomes the hold that
  queues up to `queue_hold_count` (answer 2 A). **§3:** a Deselect button clears the selection
  (§9), beside the empty box. **§4:** the minimap is the radar's full map (§7). **§5:** the
  under-attack arrows become the
  toast and the rim marker (§8). **§6:** Surrender moves into the pause menu (§11).
- **ADR 0023 §5:** "new fonts" are no longer out of scope (M4). **§12:** the floating panels become
  the corner HUD; of the canvas's command buttons only Stop is shown (the sim has it; attack-move
  stays out by Michael's answer 4), and a Deselect button is added; guard, patrol, formation, sell,
  repair, the Air tab and PRIMARY stay out.
  **§13:** the fonts row's decision becomes "used (SIL OFL allowed, M4, 2026-11-01)".
- **ADR 0024:** §6 above; `touch-ui-rules`' "Collapsible build menu" section is replaced.
- **CLAUDE.md:** the Legal line of M4 (the lead, a5b945e in this PR). **`docs/GDD.md`:** the
  team-colour line ("player 1 orange and player 2 cyan by default"), answer 7 ja (P26ap); nothing
  else. **`docs/ROADMAP.md`:** box 3's wording ("the sidebar row sets the portrait bottom zone, so
  the ArmyBar moves above the band"; "jump with the minimap") becomes "the build drawer and the
  corner HUD keep their dp sizes ... jump with the radar's full map"; P26ap writes it, no box is
  ticked.
- **`assets/art/STYLE.md` and the `theme.tres` header:** the "Licences screen" line (§13, P118).
- **`.claude/skills/touch-ui-rules/SKILL.md`** (applied by P26ap only on Michael's yes at
  acceptance, with the answers to questions 1-4 and 8 written in):

> **Line 3 (frontmatter `description`):** "... hit areas in dp, the corner HUD and the build drawer
> (ADR 0025), safe areas, ..." (the rest unchanged).
>
> **Gesture table:** the rows "Tap minimap" and "Long-press minimap with units selected" become "Tap
> the radar scope | Unfold the full map under it" and "Tap or drag the full map | Move the camera
> there; with units selected a long-press moves them there". The rows "Tap a build icon" and
> "Long-press a build icon with items queued" become "Tap a unit card | Queue one (`QUEUE`, paid at
> once)", "Long-press a unit card | Queue up to five, as room and credits allow" and "Tap an item
> in the queue row | Cancel it (`CANCEL`, full refund)". The ADR 0024 rows (any map gesture, the
> Build button, the Ready badge, the pin) become (with the hold count named `queue_hold_count`):
> | Any gesture on the map | Also closes the open drawer, full map (unless pinned) or economy card; the gesture still does its work; a touch on a HUD control never closes them |
> | Tap BUILD | Open the build drawer |
> | Swipe the drawer toward its edge (portrait: from its head) | Close it (`drawer_swipe_dp`) |
> | Tap the pill's menu button | Pause the match and open the pause menu |
> | Tap the credits or the power in the pill | Show the economy card; the next touch closes it |
> | Tap the attack toast | Jump the camera to the attack |
> | Tap Deselect at the command bar's start | Clear the selection (no Command); the bar hides, except during placement or a strike aim, when it keeps its place |
> | Tap Stop | Stop the selected units (`STOP`) |
> | Tap a group / "+" / long-press a group | Select it / save the selection in the lowest free group / overwrite it |
>
> **The section "Collapsible build menu (ADR 0024)" becomes "Corner HUD and build drawer (ADR
> 0025)":**
> - In battle only the corners show: the pill (menu, credits, power) top left, the radar scope top
>   right, BUILD bottom right, the strike button above BUILD when owned, the group column on the
>   left edge, and the command bar bottom left (portrait: bottom, with BUILD lifted 8 dp above it)
>   while something is selected. One function places them (`HudCorners.place`), mirror-ready.
>   Placement and the strike aim freeze the bar's slot and BUILD's lift, so nothing moves under
>   the thumb while the player places or aims.
> - One unfold at a time: the build drawer, the full map, the economy card, the pause menu. A map
>   gesture closes it (not a pinned full map, not pause) and still does its work; the game runs on
>   behind all but pause, which pauses the match.
> - The drawer: landscape a side panel from the right (40 % of the width, 312 to 420 dp), portrait a
>   bottom sheet of half the height; the economy in its head (the pill hides), a close button, the
>   tabs with names, the card grid (cards at least 88 x 96 dp, as many columns as fit, at least
>   two), the queue row (tap an item to cancel). It slides over `menu_slide_ms`; no pin. It opens on
>   BUILD, on a producer's selection (its tab) and after a placement begun in it.
> - The full map closes after `radar_close_ms` without a touch unless pinned; the scope is never
>   offline.
> - Under attack: a toast at the top (tap to jump), a marker on the scope's rim and a ping on the
>   full map; while the full map is open only the ping.
>
> **The sections "Layout in landscape" and "Layout in portrait":** their build-menu, minimap,
> credits, army-bar and selection-panel bullets are replaced by a pointer to the section above and
> ADR 0025 §2's table; "No ads on this screen, ever", the safe-area, the base-size and the turn
> bullets stay; the 40 % bullet reads "the bottom stack (command bar, BUILD and the group column)
> takes at most 40 % of the safe height; the drawer is transient and may take half".
>
> **"Building placement", last bullet, becomes:** "Placement closes the build drawer; when a build
> or the X ends it, the drawer comes back if placement began in it; a strike aim that ends placement
> leaves it closed."
>
> **"Text and feedback":** "Under attack: edge-of-screen indicator and a minimap ping" becomes
> "Under attack: a toast with a jump, a marker on the radar scope's rim and a ping on the full map".
> New bullet: "Fonts: Big Shoulders for buttons and titles (upper case), Chakra Petch for numbers
> (tabular) and body, from `theme.tres` only."

Status note (2026-11-03, the docs row after wave y; the text above stays as accepted): the quoted
gesture row "Any gesture on the map" ends with "a touch on a HUD control never closes them", which
contradicts §1 and §3 for the economy card: any next touch closes it, a HUD control's included, as
P119c and P119b do. `touch-ui-rules` line 40 carries the same clause. The proposed wording, for
Michael's yes before any skill edit: "| Any gesture on the map | Also closes the open drawer, full
map (unless pinned) or economy card; the gesture still does its work. A touch on a HUD control
leaves the drawer and the full map open (only opening another unfold closes them); the economy card
closes on any next touch, a HUD control's included |".

### 19. HOW_TO_PLAY rows per plan row
Each row adds or rewrites these entries in `docs/HOW_TO_PLAY.md` in its own PR (CLAUDE.md); a
"Teach" mark in brackets. Settings named, never numbers.
| Row | Section | Action → Result |
| --- | --- | --- |
| P119 | Build menu → "The screen in battle" (new) | Look at the screen → your credits and power are in a pill at the top left, sideways and upright alike; the build menu no longer repeats them. The "Look at the screen with the phone sideways/upright" rows lose their credits sentences (P120 rewrites them whole) |
| P120 | same | Look at the screen → the map fills it: the pill at the top left, the round radar at the top right, BUILD at the bottom right, nothing else until you select something. Replaces the two "Look at the screen" rows (yes) |
| P119 | same | Use more power than you make → the pill turns red with "LOW POWER" and a warning triangle |
| P119b | same | Tap the credits or the power in the pill → a card shows your income per minute, your tankers, the power you use and make and what uses it; the next touch closes it. When you spend, a red "-N" shows for a moment and the number counts down; when a tanker delivers, a green "+N" |
| P121 | Camera | Look at the round radar at the top right → the ground round your view, with a white frame for what the screen shows. Tap it → the whole map unfolds under it: tap or drag there to jump the view; with units selected, hold it to send them there; it folds away by itself after a few seconds without a touch (`radar_close_ms`), unless you tap its pin; the arrows button folds it at once. Replaces the two minimap rows (yes) |
| P120 | Build menu | Tap BUILD → the build drawer slides in (sideways from the right, upright up from the bottom); your credits and power move into its top; the game runs on behind it. Touch the map, tap the drawer's arrow or swipe it back toward its edge (upright: from its top), and it slides away (yes) |
| P120 | Build menu | Watch BUILD → its ring fills with the item that finishes first and the number counts what is queued |
| P120c | Build menu | A grey ring with "!" on BUILD → a queue cannot go on (its factory is gone or switched off, or you have as many units as you may). A "Ready" chip beside BUILD → a building is finished; tap it to open the drawer on Structures (until P130). Own a Deep Bore or a Blackout Array → its round button stands above BUILD (the Superweapon row's place words change) |
| P120 | Build menu | Tap a tab → Structures, Infantry or Vehicles, each with its name; a padlocked card says what you need for it ("Needs <name>") |
| P120b | Build menu | Tap a unit card → one is queued and paid at once; hold it → several at once, as many as room and credits allow up to `queue_hold_count` (yes; replaces "Hold an item → cancelled") |
| P120b | Build menu | Tap an item in the queue row at the drawer's foot → it is cancelled and paid back in full (yes) |
| P122 | Orders | Select units → a bar at the bottom left (upright: the bottom, BUILD above it) shows them and their health, a Deselect button at its start and the order Stop; tap Stop → they stop where they are (yes) |
| P122 | Selection | Tap Deselect ("CLEAR", at the start of the bar) → nothing is selected any more and the bar goes away; it works for units and buildings alike. The rows "Long-press and drag a box with no own unit inside" and "Tap the ground with a building selected" lose "the only way to deselect" (yes) |
| P122 | Selection | Any selection → shown in the bar's chip with its count; more types show "+N". Replaces the selection-panel row |
| P122b | Army bar → "Groups" (runs before P122) | Tap "+" with units selected → they are saved as the next free group; tap a group → it is selected; hold a group → it is overwritten with the selection, the phone buzzes; "All army" on top selects every own unit that can fight (yes; replaces the hold-to-assign row) |
| P123 | Combat | A unit or building of yours is hit out of view → a red message at the top says what (tap it to jump there), a red mark on the radar's rim points that way, and the full map pings; while the full map is open you get only the ping (replaces the "Not yet" row) (yes) |
| P124 | Pause (new) | Tap the menu button in the pill → the match pauses: the goal, the time and your losses, and Resume, Restart, Surrender, Exit to menu and Vibration; Restart, Surrender and Exit ask first (yes) |
| P120 + P121 | Turn the phone | The drawer, the full map and the toast keep their state through a turn and move to the other layout |
| P130 (ADR 0026) | Build menu | ADR 0026 §9's rows |

Note (2026-11-05, P26ax docs): P120e rewrites the P120b rows (a hold cancels the last one of its
type; no queue row) and the drawer's rows (the chevron on the tabs row, the pill staying in its
corner); P124b rewrites the P124 row with the menu's look. Their PRs carry the wording.

## Consequences
- The field gets the screen: in battle about 5 % is HUD, against the band's 20-30 % in portrait.
- One more tap for the minimap's jump (the scope, then the full map); the scope itself is always
  there. The Ready chip and the drawer's return keep placement within the taps it takes today until
  ADR 0026 shortens it.
- `BuildSidebar` loses most of its layout code; `StatusPill`, `MinimapSlot`, `SelectionPanel`,
  `ArmyBar` and the battle screen's Dev button go; their suites move to the new nodes. The six-size
  layout suites (`test_build_sidebar_layout`, `test_build_sidebar_items_layout`,
  `test_floating_panels`, `test_hud_layout`, `test_minimap_layout`, `test_strike_controls`,
  `test_touch_target_sizes`, `test_ui_orientation_flip`, the selection panel and army bar suites)
  are rewritten against `HudCorners`; this is most of the plan's test work.
- P85f2 is withdrawn (answer 1 A); `HudPrefs` arrives with P124's
  Vibration key instead. P89 keeps only its low-power part; P90's Surrender button lives in the top
  left only until P124.
- The fonts add a few hundred KB to every build and two OFL texts to every export.
- Risks: the drawer's sideways slide on the phone (fallback `menu_slide_ms` 0); the two fonts'
  glyph caches on first use (a short hitch when a text first shows; P118 checks on the phone card);
  the short landscape screens for the group column (a second column); muscle memory for groups
  ("+" instead of a hold); the accent's orange near danger red (the hue rule of §13, and never
  colour alone).

## Alternatives considered
- **Keep ADR 0024's band and plate and restyle them:** no field gain in portrait, and Michael drew a
  new layout.
- **A pinned drawer:** see §6 and question 1.
- **The bottom sheet in landscape too:** a 430 dp high landscape screen would lose half its height;
  the side panel keeps the field's width-to-height shape usable.
- **The minimap at the top right as a rectangle** (ADR 0023 §12's slot): the scope is smaller (56
  against 148 x 86 dp) and the full map is one tap away.
- **The check mark and X in the BUILD corner** (the design): M2.
- **The start page now:** a Phase 5 box pulled forward, with one working button (§12).
- **Edge arrows and the toast together:** more on screen for one event; the rim marker gives the
  direction at the same glance as the radar.
- **The strike button shrunk to 56 dp** to match the scope: its 40 dp card, 6 dp ring and foot
  label do not fit; it keeps P112's 72 dp.

## Questions for Michael (answered 2026-11-02, on #259)
As proposed; "Michael's answers" at the top records the answers.
Only what the rules do not answer: each one goes against one of Michael's own earlier answers, a
CLAUDE.md rule or his new design. The start page's timing, left-handed mode, the attack cues and
the tagline are decisions above (§12, §14, §8; the tagline in P126's PR).
1. **The build menu's pin** (P85f2, asked for on 2026-10-31). A: drop it; the drawer opens on BUILD
   and closes on a map touch or a swipe (sideways a pinned panel would be a permanent right-hand
   column, the C&C sidebar look; upright it would halve the field); the pin glyphs go to the radar.
   B: keep it upright only. Recommended: A. **Answered A.**
2. **Holding a unit card.** A: as the design says, a hold queues up to five, and you cancel by
   tapping the item in the queue row. B: a hold keeps cancelling the last one of that type (your
   "ja" of 2026-10-22), and the queue row's tap cancels too. Recommended: A. **Answered A.**
3. **"All army".** A: keep it at the top of the group column, always shown. B: drop it, as the
   design does (double-tap and the box select remain). Recommended: A. **Answered A.**
4. **Attack.** A: a tap on the ground keeps moving without fighting, and Attack is a button you tap
   before the ground tap to attack-move there. B: as the design says, Attack is the default, so a
   ground tap attack-moves (this changes CLAUDE.md's "tap ground = move (stops an attack)").
   Recommended: A. **Answered neither:** keep today's taps, no Attack button or mode, and add a
   button that clears the selection (Deselect, §9).
5. **Radar offline** without a radar building or on low power (the design): a new gameplay rule,
   and Command & Conquer's own (ADR 0023 §13). Recommended: no; the radar is always on. **Answered
   no.**
6. **Queue without the money** (the design: an item too expensive can still be queued and BUILD
   waits for credits). That is pay-as-you-go, a sim change to "paid when queued" (your answer of
   2026-10-22). Recommended: no; "stalled" shows a queue that cannot go on for other reasons.
   **Answered no.**
7. **Team colour.** In a skirmish, should your units take your side's HUD colour (Lumen Accord
   cyan, Derrick League orange), so HUD and army match? It changes the GDD's "player 1 orange,
   player 2 cyan by default". (ja/nej; recommended: ja; P90's routes set it, a data choice)
   **Answered ja.**
8. **A match starts with everything folded away**, the build drawer closed, instead of ADR 0024's
   "a match starts with the menu open" (accepted 2026-10-31). (ja/nej; recommended: ja: the open
   drawer would cover 40-50 % of the screen at the first look, and BUILD is one tap away)
   **Answered ja.**
