# ADR 0024: The collapsible build menu and the placement controls at the ghost

Status: accepted, 2026-10-31 (Michael, on #255: "ADR 0024 accepted"; his answers Q1 A, Q2 A,
Q3 A, R1 and R2 below). Proposed 2026-10-31 on `main` at 81c9b61; accepted with the lead's docs row
P26ao folded into #255, on `main` at 610e513. Builds on P86b (#253, 6e845b5) and P88 (#254,
610e513), both merged as they were (L4). Amends ADR 0015 §5, ADR 0019 §1, §2 and §4, ADR 0023
§12 and the `touch-ui-rules` lines quoted in §11, each only after Michael's yes. Plan:
`docs/plans/2026-10-31-collapsible-build-menu.md` (rows P26ao, P85g, P86c, P85f, P85f2). No sim
rule, Command, definition, data column or hash changes: everything here is view and input state.

Status note (2026-10-31): Michael answered the ADR's three questions the same day ("Answers to this
ADR's questions" below: Q1 A, Q2 A, Q3 A), confirmed the end-of-placement rule with a strike
exception (R1) and accepted the 96 dp strip, to be judged on the phone (R2); he said yes to the
`touch-ui-rules` edit of §11 once the ADR is accepted. The text below is written to those answers.

Status note (2026-10-31, P26ao docs, accepted on #255): Michael accepted the ADR as a whole. P26ao
applied §11's `touch-ui-rules` text and a dated note on ADR 0019 §2 (P86b's pending, "Blocked" and
edge pan as merged); the other dated notes §11 lists (ADRs 0015 §5, 0019 §1 and §4, 0023 §12) come
with the lead's docs row after P86c and P85f. P86b (#253) and P88 (#254) merged after this ADR was
written; where the text below cites their branches (a19cee5, 4f35204), the merged code is the
same. No accepted text changed.

## Context
**Michael, 2026-10-31**, after trying placement (P86) and the Strike test route (P112d) on his
phone, verbatim: "Det hele virker, men jeg tænker man skulle flytte fluebenet og x ud på selve
bygningen når man er ved at placere og at menuen i bunden forsvinder eller bliver trukket ned så man
får mere plads på skærmen, det er hele generelt menuen skal standard trække sig væk fra skærmen når
man ikke bruger den og et tryk på en knap trækker den ind igen. Det skal være muligt at vælge at
låse dens placering så den ikke forsvinder som standard."

In English: everything works, but the check mark and the X of placement should move onto the
building being placed, and the bottom menu should get out of the way to give the map more screen.
In general the menu should retract by default when it is not in use, and a tap on a button brings it
back. It must be possible to lock it so that it does not retract.

**His answers to the lead's questions** (2026-10-31; cited as L1-L4, to keep them apart from this
ADR's own questions Q1-Q3):
1. Collapsed, the menu is **a thin strip** with the credits, the power, a "Ready" badge when a
   structure is ready, and a button that opens the menu. **The minimap stays visible.**
2. The menu collapses **when the player touches the battlefield** (pan, select, order) **and always
   during placement**; no timer. It opens on the strip's button (the lead suggests a tap on the
   Ready badge too).
3. A **lock** toggle on the menu; locked, the menu never collapses by itself. Default unlocked.
   Remembered between matches (save data, `game/meta`).
4. P86b (pending, "Blocked", the edge pan) and P88 (the minimap: landscape `MinimapSlot` at the top
   right, portrait at the band's right end) finish and merge as they are first; the new rows build
   on them.

**The lead's design points** for the check mark and the X: beside the ghost, not on it (a tap on the
ghost and a drag from it keep their P86 meanings), at least 64 dp each, hidden while the ghost is
dragged and shown on release, inside the safe area and the visible map (they flip to the other side
near an edge), the dimmed check mark's rule unchanged (P86b's `can_confirm`), and with them the
panel no longer needs the card row's place.

**Answers to this ADR's questions** (Michael, 2026-10-31; the questions are at the end), cited as
Q1-Q3:
1. **A:** a tap on the Ready badge opens the menu on the Structures tab; placement still starts from
   the READY card (§6).
2. **A:** a pinned menu stays open during placement; placement does not collapse it (§5, §10).
3. **A:** a tap that selects an own Headquarters, barracks or vehicle factory on the map opens the
   menu on the tab it builds (§6).
He also said yes to the `touch-ui-rules` text of §11, applied once the ADR is accepted.

**His answers to the review's two points** (2026-10-31), cited as R1 and R2:
- **R1:** after placement (built or the X) the menu returns to the state it had when placement
  began: open goes back to open. If a strike aim ended placement, the menu stays collapsed, so the
  strike row's check mark and X do not move under the player's thumb (§6).
- **R2:** the 96 dp portrait strip is accepted, to be judged on the phone; its height lives in one
  place, `HudLayout.STRIP_DP`, so it can be tuned in one line (§2).

**The code this changes** (`main` at 81c9b61, with P86b and P88 on their branches; both merged
since, #253 and #254, as they were):
- `BuildSidebar` (`game/ui/BuildSidebar.gd`) is one `PanelContainer` in `Hud/SafeArea`. Portrait:
  the bottom band, `HudLayout.band_dp` high (20 % of the safe height, at least 200 dp, at most what
  keeps the band and the ArmyBar line within 40 %, floor `BAND_FLOOR_DP` 172), the status line
  (`Status`: credits and the power bar, 32 dp) first; P88 adds a `Body` row under it, `Left` (the
  tabs and the item row) and the `Minimap` at its right end, a 2:1 box of at most 40 % of the row
  (`HudLayout.minimap_box_px`). Landscape: a floating panel at the bottom right,
  `HudLayout.panel_px` wide (184 to 372 dp), the tabs above one row of named 80 x 88 dp cards; the
  status line moves into the `StatusPill` at the top left and the minimap into `MinimapSlot` (148 x
  86 dp) at the top right.
- `HudLayout.bottom_zone_dp` (a static var) is the portrait band's height, 0 in landscape. Its
  readers: `ArmyBar._lift` (the bar sits 8 dp above the band), `StrikeControls._apply_dp` (the
  strike row sits above the ArmyBar line), P88's `_place_minimap` (the room beside the tabs) and
  P86b's `PlacementController.edge_heading` (the bottom edge band ends at the band's top, read per
  call). The first two re-read it only on `size_changed`.
- `PlacementControls` (P86, 64 dp check mark and X, `can_confirm` since P86b) is a row in the
  sidebar's stack; `BuildSidebar._on_placement_changed` hides the item row while placement is on.
- `TouchInput` feeds the `GestureRecognizer` with presses the GUI did not take (`_unhandled_input`)
  and routes `PAN`, `PINCH` and `CAMERA_END` to the camera, the rest to `PlayerController`; a press
  on a Control stays with that Control. `cancel_all()` (a turn, focus loss) emits `BOX_CANCEL` or
  `CAMERA_END` only.
- `RtsCamera.visible_world_rect()` is the whole viewport's world rect; P88's minimap frame draws it.
  The HUD lies over the map everywhere ("Drag the map to its edge": what lies under the build menu
  can be scrolled into view).
- `game/meta/` holds only a `.gitkeep`; nothing is saved on the device yet. Local save is a Phase 5
  box.

## Decisions in short
| # | Topic | Decision |
| --- | --- | --- |
| 1 | States | The build menu is OPEN or COLLAPSED, local view state; a match starts OPEN; a turn keeps the state |
| 2 | Collapsed, portrait | A 96 dp strip (`HudLayout.STRIP_DP`, accepted to be judged on the phone, R2) on the safe bottom edge: the status line over the Build button and the Ready badge, the minimap at the right end (same box rule as the band) |
| 3 | Collapsed, landscape | A 56 dp plate at the bottom right: the Ready badge and the Build button; credits and power stay in the pill, the minimap in its slot |
| 4 | What moves | `HudLayout.bottom_zone_dp` is the menu's height and the new `HudLayout.menu_top_px` its real top on the screen, both animated; the ArmyBar, the strike row, the ghost buttons and P86b's edge band follow them every frame; the camera, its view rect and the minimap frame do not move |
| 5 | Collapse | A map gesture (`TouchInput`: tap, double-tap, long-press, pan, pinch, ghost drag, wheel) and the start of placement, both only while unpinned; never a touch on a HUD control |
| 6 | Open | The Build button; the Ready badge, on the Structures tab (Q1 A); a tap that selects one own producer, on its tab (Q3 A); the end of placement by a build or the X (R1; a strike aim leaves it collapsed) |
| 7 | Pin (the lock) | A 48 dp toggle at the open menu's top-right corner, a new pin glyph; pinned, nothing collapses the menu, placement included (Q2 A); default unpinned; saved in `user://settings.cfg` by `game/meta` |
| 8 | Slide | Height slides over `menu_slide_ms` (`data/input_settings.tres`, 160); the target layout is placed at once and clipped; input never waits; 0 = no slide |
| 9 | Cues | The Ready badge (the item's picture and the word; hidden while the menu is open or placement runs); low power as today on the status line (strip) or the pill (landscape) |
| 10 | Check mark and X | `GhostControls`: a column right of the ghost's silhouette, `ghost_grab_dp` + 8 dp out, flipped left, then above, clear of the HUD; hidden during a ghost drag; `PlacementControls` and its card-row place go |

## Decision

### 1. Two states, owned by the view
- The build menu is **OPEN** (today's band or floating panel) or **COLLAPSED** (§2, §3). The state
  is local to the battle screen, like placement mode: no Command, nothing in `game/sim`, the replay
  or the state hash. `BuildSidebar` owns it (`is_open()`, `open()`, `collapse()`, signal
  `state_changed`).
- **A match starts OPEN**: every match begins with building, and the open menu shows a new player
  where it is. The first map gesture (§5) collapses it. A new match (Play again, a dev route) starts
  OPEN again, whatever the state at the end of the last.
- **A turn keeps the state.** The layout is a function of (state, orientation) alone, like
  `_place()` today, so a turn and back changes nothing; a turn during a slide (§8) ends the slide at
  its target.

### 2. Collapsed in portrait: the strip
- The band shrinks to a **strip on the safe bottom edge, the full safe width, 96 dp high**
  (`HudLayout.STRIP_DP`): the backdrop's 4 dp, a left column of the **status line** (32 dp, the same
  `Status` node with its low-power look) over the **button row** (48 dp: the **Build** button,
  64 x 48 dp, and the **Ready badge**, §9, at most 112 x 48 dp, shown only when a structure is
  ready), 8 dp between them, then 4 dp; and the **minimap** at the right end. The height lives in
  that one constant (R2: accepted, to be judged on the phone and tuned there in one line); every
  reader takes it from `HudLayout`. The badge's 112 dp is a hard cap, not a target: at 360 dp the
  button row has 3 dp to spare (184 of 187 dp), so a longer word or a wider plate does not fit.
- **The minimap stays in the strip**, at the band's right end as in P88, with P88's box rule: a 2:1
  box of at most 40 % of the row (less the 8 dp gap) and no higher than the room, here the strip's
  inner 88 dp. The room comes from the **target state**, not from the zone's current height: P88's
  rule (`BuildSidebar._place_minimap` at 4f35204: the zone less the backdrop, the status line and a
  gap) would give 48 dp in a 96 dp strip and a band-sized box in mid-slide. P85f takes 88 dp for the
  strip and the band less 8 + 48 + 8 dp for the open band, set once when a slide starts. On a phone
  (up to about 480 dp wide) the room does not bind, so the minimap keeps the open band's size and x
  and only rides down with the strip; on a tablet it is height-bound in the strip (176 x 88 dp) and
  larger in the open band.
- **Budget** (the backdrop's 8 dp sides; content = safe inner width less 16 dp):

  | Phone | Content | Minimap | Left column | Status line (least) | Button row |
  | --- | --- | --- | --- | --- | --- |
  | `web_phone_portrait`, 360 dp | 320 dp | 125 x 62 | 187 dp | 139 dp | 64 + 8 + 112 = 184 dp |
  | `android_6in_portrait`, 411 dp | 371 dp | 145 x 72 | 218 dp | 139 dp | 184 dp |

  The status line's least width is the coin (24), five digits at 18 sp (about 55), the bolt (24)
  and the bar's least 24, with 4 dp gaps (P85c); the bar takes the rest and shows its numbers where
  they fit (`_fit_bar_text`).
- **Why not the minimap at the top right**, as in landscape: in portrait the top line holds the
  SelectionPanel's line from the Dev button to the right edge (280 dp at 360 dp wide); a 148 dp
  minimap and its gap would leave 124 dp, below fit level 4's one row and "+N" chip (about 150 dp,
  ADR 0015 §5), and ADR 0015 §5 keeps the often-tapped minimap in thumb reach at the bottom.
- **Why not a thinner single-line strip** (56-64 dp): the four parts Michael named side by side need
  64 + 139 + 112 + 125 dp and three 8 dp gaps, 464 dp, against 320 dp at 360 dp wide. Two lines
  are the least that fits, and the minimap fills their height.
- **The bottom stack collapsed** (strip, 8 dp, the 56 dp ArmyBar line): 160 dp, 17.5 % of the
  6-inch phone's 914 dp (open: 264 dp, 29 %). The map gains 104 dp of height.

### 3. Collapsed in landscape: the plate
- The floating panel shrinks to a **plate at the bottom right**: the Ready badge (when shown) and
  the Build button in one row, 4 + 48 + 4 = **56 dp high**, as wide as its content (at most
  8 + 112 + 8 + 64 + 8 = 200 dp), right-aligned where the panel's bottom-right corner is. The
  Build button is the rightmost part, under the right thumb.
- The credits and the power stay in the pill at the top left and the minimap in `MinimapSlot`
  (P85d, P88): both are always visible in landscape, so the plate does not repeat them.
- The bottom row's zone for the panel (`HudLayout.right_zone_px`, which the SelectionPanel's band
  leaves free) **stays reserved** in both states, so the SelectionPanel never moves or re-fits on a
  collapse. The landscape gain is the panel's 154 dp x up to 372 dp over the map's bottom right.

### 4. The open menu gains the pin; what moves when the state changes
- **The pin** (§7) sits at the open menu's **top-right corner** in both orientations:
  - portrait: at the right end of the band's first line, which becomes a 48 dp **head line** (the
    status line, then the pin). The band's content is 48 + 8 + 48 + 8 + 64 = 176 dp, so
    `BAND_FLOOR_DP` rises from 172 to **188** (176, the backdrop's 4 + 4 and 4 dp for the gaps'
    rounding). The floor binds only on a safe height under about 660 dp, which no size or profile of
    ADR 0015 §6 has: the phone profiles keep the 200 dp band (the 360 x 700 dp web phone: 200,
    within 40 %), and the taller ones keep the 20 % they get today (`desktop_portrait` 256 dp,
    `web_tablet_portrait` about 205 dp; the headless test windows 256, 480 and 410 dp). P88's
    minimap room beside the tabs becomes the band less 8 + 48 + 8 dp (136 dp at 200), still above
    what the 40 % width rule leaves the box on a phone (72 dp).
  - landscape: at the right end of the tab row. The row then needs three 48 dp tabs, the 48 dp pin
    and three 8 dp gaps, 216 dp, so `HudLayout.PANEL_MIN_DP` rises from 184 to **232** (with the 8
    dp sides). It binds only on a safe inner width under about 736 dp; every landscape profile of
    ADR 0015 §6 gives a panel of at least 272 dp (`web_phone_small`, 800 dp wide). The tabs stay
    icon-only, as P85d left them.
- **Two published values.** `HudLayout.bottom_zone_dp` stays the menu's **height** in portrait (the
  band's while OPEN, `STRIP_DP` while COLLAPSED, the slide's current height in between, §8; 0 in
  landscape). New, `HudLayout.menu_top_px` is the menu's **real top**: the y of the menu holder's
  rect on the screen in base px, which `BuildSidebar._place` writes after it lays the menu out (row
  P86c adds it, because its buttons need it first) and the slide writes each frame (P85f) (the safe
  rect's bottom where no menu covers the map, landscape included). The height is right for what sits
  in the same `SafeArea` (a margin above the band); the top is right for anything that measures the
  screen, because the band's bottom is not the safe rect's bottom: `SafeAreaMargin` adds 12 dp and
  gives both ends of an axis the larger inset, so with a portrait top cutout the band sits higher
  than `safe.end.y - bottom_zone_dp` says.
- `BuildSidebar` emits `zone_changed(top_px, height_px)` whenever it writes them; `ArmyBar` and
  `StrikeControls` re-run their lift on it (not only on `size_changed`), so **the ArmyBar line and
  the strike row ride on the menu**, 8 dp above its top, through the slide.
- **P86b's bottom edge band** (`edge_heading`) today ends at `_safe.end.y - bottom_zone_dp`, which
  with a portrait top cutout lies inside the build band. P86c changes that one line to
  `HudLayout.menu_top_px`, so the band ends at the menu's real top during placement: the strip's
  top while unpinned (placement collapses the menu, §5) and the open band's top while pinned
  (Q2 A), following the slide. P86c's test pins the top-cutout case
  (`ui_profiles.with_safe_area`); P85f's pin the strip, the pinned band and the slide.
- **The camera does not move**, nor its zoom: a collapse is triggered by a touch on the map (§5),
  and a camera shift right then would be a pan the player did not make, under the finger that just
  touched. `RtsCamera.visible_world_rect()` stays the whole viewport, so **the minimap's frame does
  not change** either: it already shows the map under the HUD as part of the view, as the HUD lies
  over the map everywhere. The ghost still starts on the tile under the view centre (P86).
- **P89's under-attack arrows** (not merged) keep to the map's visible rect: the bottom ones above
  `menu_top_px` (and the ArmyBar line), so they follow the menu's top like the edge band.

### 5. What collapses the menu
- **A gesture on the map.** `TouchInput` emits `map_gesture` before it routes the first event of a
  gesture the recognizer made from a press the GUI did not take: `TAP`, `DOUBLE_TAP`, `LONG_PRESS`,
  `PAN`, `PINCH`, `GHOST_DRAG`, and a wheel step (the desktop preview's zoom). The gesture then does
  what it does today: the touch that collapses the menu also pans, selects or orders (Michael's
  "pan, select, order"). The events of `cancel_all()` (a turn, focus loss) and `BOX_*` and
  `CAMERA_END` (ends of a gesture already counted) never collapse it.
- **Never a touch on a HUD control**: the ArmyBar, the SelectionPanel, the minimap (its jump and
  P88b's long-press `MOVE`), the strike button and its row, the Dev button, the pill, the pin, and
  the menu itself (a card, a tab, the item row's scroll, a long-press cancel). The player is
  working in the menu while touching it, so it **stays open**. The GUI keeps such a press from the
  recognizer, so `map_gesture` never fires for it and the HUD controls need no change.
- **The start of placement** (`PlacementController.changed` with `active` turning true): an
  unpinned menu collapses, so the ghost has the screen (the check mark and the X are at the ghost,
  §10).
- **Pinned** (§7), none of these collapses it, **placement included** (Q2 A: Michael's L3, "it
  never collapses by itself", wins over L2's "always during placement"). A pinned menu stays open
  through placement with its cards showing; the check mark and the X stand beside the ghost in the
  map above the open band (§10), and P86b's bottom edge band ends at the open band's top (§4).
- Requests are applied in order and the last one in a frame wins; the slide (§8) starts from the
  height the menu has, so a collapse and an open in the same frame (Q3's producer tap) end
  OPEN without a visible move.

### 6. What opens the menu
- **The Build button** in the strip or the plate (64 x 48 dp, a new glyph, §7).
- **The Ready badge** (Q1 A): a tap **opens the menu on the Structures tab** and scrolls the
  item row so the READY card is in view; it starts nothing else. The player then taps the READY card
  to place the structure, as before, so placement has one way in: the card.
- **A tap that selects one own production building** (Q3 A): `BuildSidebar`'s
  `set_selected` opens the menu as well as its tab, as the gesture table says today ("a production
  building opens its build tab"). The tap's own `map_gesture` collapsed it a moment earlier in the
  same frame; §5's last-wins rule leaves it open with no move.
- **The end of placement** (R1, Michael's answer of 2026-10-31): when the building is placed or the
  X ends placement (a "Blocked" ghost included), the menu returns to the state it had **when
  placement began**. Placement begins only on a READY card, in the open menu (Q1 A), so that state
  is OPEN: the menu comes back up and the next item is one tap away. Map gestures during placement
  do not change it. Two exceptions: **a strike aim that ends placement leaves the menu collapsed**,
  so the strike row, which rides on the menu's top in portrait, and its check mark and X do not move
  while the player aims; and the match's end opens nothing (P90's result screen covers the HUD, and
  the next match starts OPEN anyway, §1).
- Nothing else opens it: no timer, no event of the match (a structure becoming ready shows the badge
  and does not open the menu).

### 7. The pin and where it is saved
- **The control:** a 48 x 48 dp toggle at the open menu's top-right corner (§4), absent while
  collapsed (there it would have nothing to keep open). It is called the pin, not a lock: the
  padlock glyph (`glyph_lock.svg`) already means "a requirement is missing" on a card, and a
  padlock on the menu would read as "the menu is disabled". HOW_TO_PLAY calls it "the pin (lock)".
- **Its look:** a pin glyph upright and pushed in when pinned, tilted and lifted when not
  (`glyph_pin.svg`, `glyph_pin_off.svg`), on the tab's plate with its pressed look when pinned:
  a shape and a plate, never colour alone. The Build button's glyph is new too
  (`glyph_menu_open.svg`: a chevron up over a row of cards). art-director draws the three by hand in
  `assets/art/svg/icons/` (plan row P85g); no existing glyph fits.
- **Pinned:** nothing collapses the menu (§5); unpinning leaves it open until the next trigger.
- **Default unpinned.** Saved on the device: `game/meta/HudPrefs.gd` (a `RefCounted` of static
  functions, no Node, no autoload; the folder holds only a `.gitkeep` today) reads and writes one
  key, `[hud] build_menu_pinned`, in `user://settings.cfg` through `ConfigFile`. `BuildSidebar`
  reads it once in `_ready` and writes it on each toggle; a missing or unreadable file means
  unpinned. Phase 5's settings and local save (ROADMAP Phase 5) take this file over and add their
  keys; this ADR adds only the one.
- **The test hook:** `HudPrefs.set_path_override(path)` and `clear_path_override()`, a static
  override like `UiScale.set_override`. Every suite that builds a `BuildSidebar` (the scene suites
  that load `scenes/main.tscn` included) sets it to its own file under `user://` before `_ready`
  and clears it and deletes the file in `after_test`, through one helper in `tests/support/`; so no
  suite reads or writes the machine's real `user://settings.cfg`, and a pin left by one suite never
  changes another's layout.
- **The web export.** There `user://` is the browser's IndexedDB storage, which Godot syncs
  asynchronously after a write, so a reload at once after a toggle can lose it. P85f reads
  `OS.is_userfs_persistent()` on the phone preview: if it is true, the check is pin, wait a moment,
  reload, still pinned; if it is false, the pin lasts for the session on the web and the PR says so.
  Android, where `user://` is the app's own storage, is the target; no web workaround is built.
- Scope: this is the project's first save file, ahead of Phase 5's, because Michael asked for the
  pin to be remembered between matches. It stays one key; no save format, no migration.

### 8. The slide
- **Duration in data:** `menu_slide_ms` in `data/input_settings.tres` (`InputSettings`, beside the
  other HUD timings), 160 ms by default, eased out (cubic). 0 means no slide: the state's layout
  shows at once, and a later "reduce motion" setting can use it.
- **Tests without the slide:** `BuildSidebar.set_slide_ms_override(ms)` and
  `clear_slide_ms_override()`, a static override like `UiScale.set_override`, which the shared test
  helper of §7 sets to 0 and clears in `after_test`. Suites never write `menu_slide_ms` into the
  loaded `input_settings.tres`, which every scene shares through the resource cache, so the readers
  of `bottom_zone_dp` and `menu_top_px` (`_build_band()`, `bottom_zone_px()`, the lifts) see the
  final heights in the frame of the change. Only the slide's own suite sets a non-zero override.
- **One animated number:** the menu's visible height (portrait: `bottom_zone_dp`; landscape: the
  panel's height, 56 to about 154 dp). At the start the **target state's layout** is placed at once
  inside a clipping holder whose height slides from the current height to the target; the content
  is anchored to the holder's top, so opening reveals the band from the top down as it rises
  (a drawer pulled up from the bottom edge), and collapsing carries the strip down with the top.
  In landscape the plate's width changes at once (at the start of an opening, at the end of a
  collapse) and only the height slides.
- **The holder is a plain `Control` with `clip_contents`,** its content placed by code: a container
  cannot be smaller than its children's least size, so a `PanelContainer` holding the band could not
  slide below 200 dp. With `clip_contents` the parts outside the holder are neither drawn nor
  pickable (Godot's documented behaviour; P85f's test proves it with a press under the clip edge).
- **Input never waits:** every control is live during the slide; a request during a slide restarts
  it from the current height, for the share of `menu_slide_ms` that the distance left needs. A turn
  ends it at its target (§1).
- **Cost:** while sliding (about ten frames), each frame sets the holder's height, the zone and the
  two lifts; the content is not re-laid out (it has the target's size from the start), so the
  re-sorts are those of `SafeArea`'s few bands. **No allocation per frame takes a change to the
  lifts:** today `ArmyBar._lift` and `StrikeControls._apply_dp` call `HudLayout.is_portrait()` and
  `UiScale.dp()`, and each builds a `UiMetrics` through `UiScale.current()` and `_engine_metrics()`
  (about nine per frame), and `StrikeControls` has no lift of its own (its `_apply_dp` also sets
  theme overrides). P85f gives both a lift that uses the dp, the orientation and the safe area
  cached on `size_changed` (as P86b's `read_metrics`) and the base px that `zone_changed` carries,
  so a slide frame calls no `UiScale` function; `StrikeControls._apply_dp` keeps the theme overrides
  and runs on `size_changed` only. The plan's test pins it. At rest there is no per-frame work
  beyond today's (the sidebar still reads each new snapshot, so the hidden tiles keep their states
  and the badge knows when a structure is ready). Hidden tabs and cards are not drawn.
- **No timing in the sim:** the slide is frame time in `game/ui`, like the camera's snap; `game/sim`
  is untouched.

### 9. Cues while collapsed
- **The Ready badge:** shown in the strip or the plate while the local player's Structures queue
  holds a finished structure at its head (the READY tile state, which the sidebar computes for the
  hidden tiles too). It shows the item's card picture (32 dp, `assets/art/iso/icons/item_<id>.svg`,
  P85e) and the word "Ready" (at least 14 sp), on the READY banner's plate from the theme: a
  picture, a word and a shape. Hidden while the menu is open (the card says "Ready" there) and
  **while placement runs**: the ready structure is the one being placed, and a badge then would
  invite opening the menu mid-placement for what is already on the map. A tap on it opens the menu
  on the Structures tab with the READY card in view (§6, Q1 A); it is a cue and a way in, not a
  second start of placement.
- **Low power:** the strip's status line is the same node with P85c's look (the bar full and amber,
  the bolt a warning triangle); in landscape the pill shows it. P89's pulse goes on that node, so it
  shows in the pill, the band and the strip alike.
- **Nothing else.** No progress bar, no count of queued items and no haptic in the collapsed
  states: Michael named credits, power and Ready, and the open menu shows the rest one tap away.

### 10. The check mark and the X beside the ghost
- **`GhostControls`** (`game/ui/`, replacing `PlacementControls`): the two 64 x 64 dp buttons with
  the strike's plates and 32 dp glyphs (`ACTION_DP`, `ICON_DP` and the theme variations kept), a
  child of the `Hud` **before** `SafeArea`, so a HUD control drawn over it also wins its touches.
  Outside `SafeArea` it does not inherit the HUD theme, so the node sets `theme = theme.tres` in the
  scene, as `BoxOverlay` does (`scenes/main.tscn`). `BuildSidebar` loses `_actions`, its call to
  `PlacementControls.set_row_dp` and `_on_placement_changed`: the card row stays as it is in every
  state, and nothing takes its place.
- **Where:** the anchor is the ghost's silhouette box on the screen (`PlacementController`'s `_near`
  box with no margin, exposed as `silhouette_rect()`), recomputed every frame while placement is on,
  so the buttons follow pans, pinches, zoom snaps, edge pans and turns. The candidates, in order:
  1. **Right:** a column (the check mark above the X, 16 dp apart: 64 x 144 dp) whose left edge is
     `ghost_grab_dp` + 8 dp (32 dp today) right of the silhouette box, centred on its centre and
     slid along that side to the nearest place inside the allowed rect and clear of the HUD.
  2. **Left:** the same column mirrored.
  3. **Above:** a row (the check mark left of the X, 16 dp apart: 144 x 64 dp) whose bottom edge is
     the same gap above the box's top, centred on its x and slid sideways.
  4. If none fits, the right column clamped into the allowed rect: it may then lie under a HUD
     control (which keeps its touch) or over the ghost's grab ring. The edge pan (P86b) and a pan
     move the ghost out of that corner.
  The allowed rect is the safe rect, its bottom at `HudLayout.menu_top_px`: the strip's top while
  unpinned, the open band's top while pinned (Q2 A), the slide's current height in between, so the
  buttons never stand on the menu in either state; "clear of the HUD" means no overlap with a
  visible HUD control's rect (the ArmyBar, the SelectionPanel, the strike row, the menu, the pill,
  the minimap's slot, the Dev button). The placement is one static function of (silhouette box,
  allowed rect, HUD rects, dp, `ghost_grab_dp`), tested without a scene.
- **Why right first, and a column:** the column is 64 dp wide, so a side fits on a 360 dp portrait
  screen even for a 3x3 footprint at zoom 1.5 (silhouette 144 dp: 72 + 32 + 64 = 168 dp from the
  centre, the half of the 336 dp safe width); and a ghost drag ends with the finger
  `ghost_lift_dp` (64 dp) below the ghost's centre, nearest the column's lower button, the X, which
  only cancels. Below the ghost was rejected: the buttons would appear under the lifted finger and a
  quick second tap to nudge the ghost would confirm instead.
- **The gap keeps P86's meanings:** the buttons start outside the 24 dp grab ring, so a press on the
  silhouette (a tap leaves the ghost, a drag moves it) and in the ring (a tap moves the ghost there,
  a drag grabs it) behave as in P86. A press on a button goes to the GUI first and never reaches the
  recognizer, so it is never a ground tap, a pan or a map gesture (§5); a finger that started on the
  map and is dragged over a button keeps panning (`TouchInput._input`), and its release never
  presses it.
- **Shown and hidden:** shown while placement is on and the ghost is not being dragged; **hidden
  during a ghost drag** (and so during its edge pan) and shown again on release, beside the ghost's
  new tile. `PlacementController.dragging` is the flag, set by `TouchInput` while its recognizer is
  in `GRAB`. Shown while **pending** and **"Blocked"** (P86b): the check mark dimmed by
  `can_confirm()` (unchanged: the ghost fits, no PLACE in flight, not blocked), the X live in every
  state. A pinned open menu (Q2 A) shows its cards as usual during placement and is itself in the
  HUD list the buttons keep clear of; the portrait map above the open band is at least 60 % of the
  safe height less the top line (about 450 dp on the 6-inch phone), so the 144 dp column always
  finds room beside or above a ghost there. A tap on the READY card again re-centres the ghost
  (P86's `begin`, unchanged); a tap on another card queues it, as at any time.
- **The strike's check mark and X stay in the strike row** (ADR 0023 §10, P112). Putting them beside
  the aim's ring is a possible later change, not part of this ADR.

### 11. What this amends, and the proposed skill text
Nothing is superseded whole; on acceptance the lead's docs row P26ao adds dated status notes (the
accepted texts stay as they are):
- **ADR 0015 §5:** the portrait build band is open or collapsed (a 96 dp strip with the minimap at
  its right end); the bottom zone's height is the menu's height in either state and through the
  slide, and `HudLayout.menu_top_px` its real top on the screen; the ArmyBar sits 8 dp above
  whichever shows; the 40 % rule holds in both states; the band's floor is 188 dp (the head line
  with the pin). The P68b note's "during placement the check mark and X (64 dp) take the item row's
  place in the zone" no longer holds.
- **ADR 0019 §1:** the build sidebar collapses and opens as §1-§7 say; selecting an own producer
  opens it at its tab (Q3 A). **§2:** "a check mark and an X ... take the place of the item
  row in the sidebar zone" becomes §10 here (beside the ghost); pending, "Blocked" and the dimmed
  check mark unchanged. **§4:** in portrait the minimap is at the right end of the band and of the
  strip.
- **ADR 0023 §12:** the landscape build panel collapses to the plate (§3); the pin at the tab row's
  right end, `PANEL_MIN_DP` 232; "during placement the check mark and X take the card row's place"
  no longer holds (the P68e notes in ADR 0015 §5 and ADR 0019 §1-§2 say the same and get the same
  note).
- **`.claude/skills/touch-ui-rules/SKILL.md`**: Michael said yes on 2026-10-31; P26ao edits the
  file once the ADR is accepted, not before. The text also brings the skill's "Building placement"
  section up to P86 and P86b as merged. The lines and their proposed text (applied by P26ao on
  acceptance, 2026-10-31):

> **Line 3 (frontmatter `description`):** "... build menu layout (floating panels in landscape, a
> band in portrait, both collapsible, ADR 0024), safe areas, ..." (the rest unchanged).
>
> **Gesture table, four rows after line 38:**
> | Any gesture on the map (tap, double-tap, long-press, drag, pinch) | Also collapses the build menu unless it is pinned; a touch on a HUD control never does |
> | Tap the build menu's Build button | Open the menu |
> | Tap the Ready badge | Open the menu on the Structures tab, the ready card in view |
> | Tap the pin | Pin or unpin the open build menu (remembered on the device) |
>
> **Lines 64-80 (the section "Building placement") become:**
> "ADR 0019 §2 (Michael's answer 1 B), ADR 0024 §10. Placement mode is local input state; no Command
> until confirm.
> - Placement begins with a tap on a ready structure's card. The ghost starts at the tile under the
>   view centre. A one-finger drag that starts on the ghost (its silhouette plus the grab margin,
>   ADR 0023 §3) moves it; it follows the finger 64 dp above the touch point, so the finger never
>   hides it, and snaps to tiles. A tap on the ghost's own silhouette leaves it where it is; a tap
>   in the grab ring round it, or anywhere else on the ground, moves it to that tile. A one-finger
>   drag that starts elsewhere pans as usual; pinch and two-finger pan are unchanged; the long-press
>   box select is off. The lift and the grab margin are `ghost_lift_dp` (64) and `ghost_grab_dp`
>   (24) in `data/input_settings.tres`.
> - Placement and the strike aim exclude each other: entering one ends the other with no Command
>   (the structure stays ready), so one mode owns the map's taps.
> - Edge pan: while a dragged ghost is within `edge_band_dp` (32) of an edge of the map view, the
>   camera pans toward that edge at `edge_pan_dp_per_s` (300) of screen at any zoom, one frame
>   scrolling for at most `edge_pan_max_step_ms` (100), all in `data/input_settings.tres`. The top
>   band counts from the lifted ghost point, the left, right and bottom bands from the finger. The
>   bands lie inside the safe area, and in portrait the bottom band ends at the build menu's real
>   top (`HudLayout.menu_top_px`: the strip's top, or the open band's when the menu is pinned).
> - Valid tiles are tinted green with a solid outline, invalid red with a hatch and the reason's
>   glyph (never colour alone), from `Placement.reason` on the snapshot. Confirm with a check-mark
>   button, cancel with an X, each at least 64 dp, beside the ghost: a column right of its
>   silhouette, `ghost_grab_dp` + 8 dp out so it never covers the grab ring, flipped left (then
>   above) near an edge or a HUD control, inside the safe area and above the build menu; hidden
>   while the ghost is dragged, shown again on release. The check mark is dimmed while the ghost
>   does not fit, while a PLACE is pending and while it is "Blocked"; the X works in every state.
>   Never place a building on touch release alone.
> - After confirm the ghost waits ("pending") until the snapshot shows the building; if the
>   structure is still ready one published tick after the Command's tick, it turns invalid with
>   "Blocked". Cancel keeps the structure ready. A turn keeps the ghost's tile and sends nothing;
>   the check mark and X stay beside the ghost.
> - Placement collapses the build menu unless it is pinned; a pinned menu stays open with its cards.
>   When a build or the X ends placement, the menu returns to the state it had when placement
>   began (open, since placement begins on a card); a strike aim that ends placement leaves it
>   collapsed, so the strike row does not move."
>
> **New section after "Building placement", "Collapsible build menu (ADR 0024)":**
> - The build menu is open or collapsed. A match starts open. A gesture on the map and the start of
>   placement collapse it unless it is pinned; a touch on a HUD control never does, and it stays
>   open while the player works in it. The Build button opens it, the Ready badge opens it on the
>   Structures tab, and selecting an own production building opens it at its tab.
> - Collapsed: in portrait a 96 dp strip (the credits and power line over the Build button and the
>   Ready badge, the minimap at its right end); in landscape a 56 dp plate at the bottom right (the
>   Ready badge and the Build button; the pill and the minimap panel stay).
> - The pin (48 dp, the open menu's top-right corner) keeps it open, placement included; unpinned by
>   default; saved in `user://settings.cfg` by `game/meta`.
> - The height slides over `menu_slide_ms` (`data/input_settings.tres`); input never waits for it;
>   the camera never moves with it.
>
> **Lines 85-88 (Layout in landscape, the build panel) gain at the end:** "with the pin at the tab
> row's right end (so at least 232 dp wide); collapsed, a plate at the bottom right (ADR 0024 §3)."
>
> **Lines 101-107 (Layout in portrait, the zone) become:** "Build menu zone: a bottom band, the full
> safe width, 20% of the height and at least 200 dp when open (a 48 dp head line of credits, power
> and the pin, then the icon-only tabs (48 dp) and one row of build icons (at least 64 dp) that
> scrolls sideways: at least three whole icons on the 6-inch phone, two at 360 dp wide); a 96 dp
> strip when collapsed (ADR 0024 §2). The minimap is at the right end of both (an isometric diamond,
> at most 40% of the row). The zone's height is set by `BuildSidebar` through
> `HudLayout.bottom_zone_dp` (the menu's height; `HudLayout.menu_top_px` is its top on the screen)
> in either state and during the slide; a scene
> without the sidebar leaves it at 0. The tabs show icons only in the band."
>
> **Lines 108-109 become:** "Bottom-left: "All army" and groups 1-3, on the safe bottom edge while
> the zone is 0, then 8 dp above the band or the strip, moving with it."
>
> **Lines 114-115 become:** "Taps players make often (army, groups, build, minimap) stay at the
> bottom; the bottom stack (band or strip plus army line) takes at most 40% of the safe height, and
> the band gives way first."

- **`docs/HOW_TO_PLAY.md`:** the rows the plan names, in the rows that change the behaviour (P86c,
  P85f), as CLAUDE.md asks. `CLAUDE.md`, `docs/GDD.md` and the ROADMAP need no change: CLAUDE.md's
  Mobile UX gestures hold (a map gesture still pans, selects and orders), and no new box is needed
  (box 3's phone check, "build an item with one hand, jump with the minimap, rotate during a
  placement", runs on the collapsible menu once P85f has merged).

## Consequences
- The player gets the map back: in portrait 104 dp more height whenever the menu is collapsed and
  the whole bottom right in landscape; the check mark and X stand where the eye already is.
- The ArmyBar's height in portrait now depends on the menu's state (it rides up about 100 dp when
  the menu opens). The menu opens only after a player's tap (the Build button, the badge, a
  producer, the end of a placement begun from a card), never by itself, which keeps the bar where
  the thumb left it.
- Placing a building from the collapsed strip takes one more tap than a badge that placed at once
  would (the badge, the card, then the check mark); Michael chose that (Q1 A), so placement
  keeps one way in, the card, and the menu opens to show what is ready.
- `HudLayout.bottom_zone_dp` and `menu_top_px` change during a slide; every reader must follow
  `zone_changed`, not
  only `size_changed`. A future HUD part above the band joins that signal (review item).
- One more save file on the device before Phase 5; its one key is the only stored setting until
  Phase 5's settings screen takes the file over.
- The six-size layout suites run each orientation in both states: `test_build_sidebar_layout`,
  `test_build_sidebar_items_layout`, `test_floating_panels`, `test_hud_layout`,
  `test_minimap_layout` (P88), `test_strike_controls`, `test_touch_target_sizes`,
  `test_ui_orientation_flip`, the portrait profiles; `test_placement_controls` becomes
  `test_ghost_controls`; `test_placement_edge_pan` (P86b) gains the strip case and the pinned
  open-band case. Headless proof is
  listed in the plan; no timing run is needed.
- `PlacementControls` and its card-row stand-in go; the strike's own check mark and X keep their
  place, so the two confirm pairs now differ in where they stand (aim: in the strike row; build: at
  the ghost).
- Risks: the per-frame cost of the slide on the phone (bounded to about ten frames; fallback
  `menu_slide_ms` 0, data only); `clip_contents` picking and the web's `user://` are taken from the
  engine's documentation and checked by P85f; the floor's rise from 172 to 188 dp makes the open
  bottom stack pass the 40 % share where today's does not, by up to 16 dp, on a safe height between
  620 and 660 dp, and adds 16 dp to today's excess below 620 dp (no size or profile of ADR 0015 §6
  is that short; collapsed the stack is far within).

## Alternatives considered
- **A timer that collapses the menu:** Michael chose no timer (L2).
- **The check mark and X on the ghost:** a tap on the ghost and a drag from it already mean "leave
  it" and "move it" (P86); buttons on top would steal both.
- **Below the ghost:** where the lifted finger ends a drag (§10).
- **The minimap at the top right in portrait** (§2) and **a one-line strip** (§2): neither fits a
  360 dp phone.
- **Moving the camera so the visible map keeps its centre** (§4): a pan the player did not make.
- **Collapse on the press itself** instead of the first gesture event: the producer tap would close
  and reopen the menu (a flicker), and a press that the GUI later hands to a control would count.
- **Squashing the band's content while it slides:** a full re-layout of every tile each frame and
  a crushed picture; the clipped holder slides a finished layout.
- **A Ready badge that starts placement at once** (the proposal's recommendation): one tap fewer,
  but a second way into placement; not taken (Q1 A).
- **Placement collapsing a pinned menu too:** Michael's "always during placement" read literally;
  not taken (Q2 A: a pinned menu never collapses by itself).
- **A producer tap that collapses the menu like any other map tap:** not taken (Q3 A).
- **A padlock for the lock:** it already means "requirement missing" on a card (§7).
- **Remembering the pin for the session only:** Michael asked for it between matches, in save data.
- **A swipe on the strip to open it:** a new gesture on a HUD control; Michael asked for a button.
  It can come later beside the button.

## Questions for Michael (answered 2026-10-31)
As proposed; "Answers to this ADR's questions" in the Context records the answers.
1. **The Ready badge.** A: a tap opens the menu on the Structures tab, and you tap the "Ready" card
   to place it (the lead's suggestion). B: a tap starts placing the finished building at once,
   and the menu stays down. Recommended: B. **Answered A** (2026-10-31).
2. **A pinned menu while you place.** A: pinned means pinned; the menu stays open during placement
   too (the check mark and X are at the ghost, so the menu covers nothing they need). B: placement
   always pulls the menu down, pinned or not, and it comes back when you build or cancel.
   Recommended: A. **Answered A** (2026-10-31).
3. **Tapping your Headquarters, barracks or vehicle factory on the map.** A: the menu opens on the
   tab that building makes, as the tab switch does today. B: it goes down like any other tap on the
   map; the tab is switched for the next time you open it. Recommended: A. **Answered A**
   (2026-10-31).
