# ADR 0032: Short display names, the one-line rule and the locked card's sash

**In short, for Michael:** six building and unit names get shorter, so every name fits its build
card on one line: Oil Works, Fuel Works, Motor Hall, Relay Post, Dusk Array and Rig Hands. Turbine
Hall stays. A locked card gets a light diagonal band across its picture with the name of the
building it waits for, on one line, and a big padlock seal; its price is hidden while it is locked.
A test checks every name on every test screen, so a future name that is too long fails before it
merges.

Status: **accepted, 2026-11-06** (Michael: option A for the locked card, "kun når teksten står på
én linje"; then "ja til anbefaling" to the names; Acceptance note below). Proposed 2026-11-06 by the
architect in two notes to the lead (the locked card's three designs, then the short names), both
answered in chat the same day; written down by the docs part of row P120k. Base: `main` at cd8fb3f.
Supersedes six names of ADR 0023 §7 (and the places ADR 0023 repeats them) and adds rows to ADR
0023 §13's screen (§6 here). Amends ADR 0025 §5 and its 2026-11-04 note on the locked card (a dated
note at the end of §5 names each phrase it replaces). No sim rule, Command, state column, state hash
or golden hash changes; `defs_hash` changes (§5).

## Acceptance note (2026-11-06)
Michael answered two questions in chat on 2026-11-06, verbatim:
- **The locked card:** of three designs (A: a diagonal sash, the price hidden; B: a light lock plate
  in the price's place; C: a dark veil, a big padlock and the name in the middle) he chose **A**,
  "kun når teksten står på én linje" ("only when the text is on one line").
- **The names:** to seven numbered questions, each with a recommended A, he answered "ja til
  anbefaling" ("yes to the recommendation"): 1 Cracking Plant → Oil Works, 2 Synthesis Works → Fuel
  Works, 3 Motor Works → Motor Hall, 4 Relay Tower → Relay Post, 5 Blackout Array → Dusk Array,
  6 Roustabouts → Rig Hands, 7 keep Turbine Hall on the condition of §3.

## Context
- **The locked card read wrong.** Since ADR 0025 §5's note of 2026-11-04 a locked card shows the
  missing building's name above its price, in the same white 14 sp as the card's own name below it.
  At 88 dp that gave "Turbine Hall / 1400 / Cracking Plant", which reads as two labels of one thing,
  and the 14 dp corner padlock is too small to see at a glance.
- **Option A needs one line.** Measured with the real `ItemTile`, `theme.tres` and Godot 4.7.2 at
  the 88 dp floor card (`ItemTile.CARD_DP`), the sash holds 81.5 dp on one line. Five requirement
  names do not fit: Cracking Plant (99.4 dp), Synthesis Works (113.7), Motor Works (85.1), Relay
  Tower (81.7) and, on the worst profile, Turbine Hall (81.6).
- **The caption is cut today.** The card's own name has 83.4 dp inside the card's 2 dp frame at
  88 dp: "Cracking Pl…" and "Blackout Ar…" are cut by the ellipsis, and Roustabouts (84.6 dp) runs
  over the frame.
- **Widths depend on the profile.** Each profile draws 14 sp at its rounded pixel size:
  `android_6in` 25 px at 1.75 px per dp (+2.0 %), `web_tablet` 18 px at 1.25 (+2.9 %, the worst).
  Every width below is measured at the drawn size.

## Decision

### 1. Six new display names
Only `display_name` changes. Ids, file names, `strike_kind`'s "Blackout" and the scenarios'
sub-resource ids stay internal and unchanged. Widths in dp at `android_6in` (sash: Chakra Petch Bold
14; caption: Medium 14); "worst" is the widest over every test profile.

| Id | Faction, role | Was | Now | Sash / caption | Worst | Requirement? |
| --- | --- | --- | --- | --- | --- | --- |
| `refinery` | Derrick League refinery | Cracking Plant | **Oil Works** | 63.4 / 61.1 | 64.0 / 61.6 | yes |
| `renew_refinery` | Lumen Accord refinery | Synthesis Works | **Fuel Works** | 74.3 / 72.0 | 75.2 / 72.8 | yes |
| `renew_factory` | Lumen Accord vehicle factory | Motor Works | **Motor Hall** | 69.1 / 67.4 | 70.4 / 68.0 | yes (makes vehicles) |
| `renew_radar` | Lumen Accord radar | Relay Tower | **Relay Post** | 73.1 / 70.9 | 74.4 / 72.0 | yes |
| `renew_strike` | Lumen Accord strike | Blackout Array | **Dusk Array** | 75.4 / 72.6 | 76.0 / 73.6 | no |
| `rifle_squad` | Derrick League rifle squad | Roustabouts | **Rig Hands** | 69.1 / 66.3 | 69.6 / 68.0 | no |
| `power_plant` | Derrick League power | Turbine Hall | **Turbine Hall** (kept, §3) | 80.6 / 77.7 | 81.6 / 78.4 | yes |

Why: Oil Works says what it takes and keeps Rigworks' "-works"; the Fuel Runner unloads at the Fuel
Works; Motor Hall keeps "Motor" and pairs with the Crew Hall; Relay Post is the smallest change;
the light faction brings dusk to the enemy's base; a rig hand is an oilfield trade.

### 2. The one-line rule
- **Caption:** every display name in `data/units/*.tres` fits the card's caption on one line at the
  88 dp floor card on every test profile (`UiProfiles.all()` and `UiProfiles.portrait()`), measured
  at the profile's drawn font size. The room is the card's width less its frame's two borders
  (83.4 dp at `android_6in`). Never cut, never over the frame.
- **Sash:** every requirement name fits the sash on one line at the 88 dp card on every test
  profile. A requirement is a `requires` target or a def that produces a tab (the producer a locked
  card names); the HQ counts though it has no card.
- **Margin for new names:** a new name should leave about 3 dp of the room to spare on the worst
  profile. The test's limit stays the exact room, so a tight name passes; Turbine Hall (sash) is the
  tight one today. Rail Battery is not a requirement; it would be tight on the sash if it became one.
- **The guard:** `tests/ui/test_display_name_fit.gd` lands with P120j (it needs the `ItemSash`
  variation and `ItemTile.sash_room_px(card_px: Vector2) -> float`, which the sash's drawing and the
  test share). It reads every `data/units/*.tres` in sorted order, derives the requirement set from
  the data and fails with `<id> "<name>" is <w> dp, room <r> dp, at <profile> (caption|sash)`. It
  runs headless (font measuring needs no renderer) and also catches a font, theme or card-size
  change that brings back a second line or an ellipsis.
- **A failing name** is fixed by a shorter name (Michael's choice, recorded in an ADR) or by a
  layout change with its own ADR; never by an ellipsis or a smaller font for one name.

### 3. The locked card: option A
- **Price hidden** while locked (READY already hides it). The picture stays dimmed.
- **The sash:** a light band (proposal: #D9E0E8 with a 1.5 dp dark edge line) rises at about 27°
  across the picture and runs off both edges of the card. It carries the missing requirement's or
  producer's display name in Chakra Petch Bold 14 sp, dark on light (`ItemSash` in `theme.tres`),
  on **one line**: no wrap, no ellipsis, no "Needs" (Michael's rule of 2026-11-04 stands). The
  guard test of §2, not a runtime fallback, keeps every name inside it.
- **The seal:** a 26 dp padlock seal (a white padlock on a dark disc) at the top left. It replaces
  the 14 dp corner padlock.
- **The card's own name** stays in the caption, unchanged: white, level, under the picture.
- **The count badge** stays clear: the text ends below and left of it; the band's end runs under the
  badge plate, which is drawn on top.
- **Distinct by shape:** no other state is slanted and solid (stripes for UNAFFORDABLE and FULL, a
  level green banner for READY), so the meaning does not rest on colour.
- **Measured one-line room** at `android_6in` today: 81.5 dp at 88 wide (about 3.6 dp end margin),
  97.6 dp at 102 (the sideways drawer) and 109.1 dp at 113 (the upright sheet).
- **Turbine Hall's condition:** P120j sets the band's end margin so the one-line room at 88 dp is
  **at least 83 dp** (about 2.9 dp of end margin); Turbine Hall then has 1.4 dp to spare on the
  worst profile. If P120j cannot give 83 dp, the recommendation's fallback applies: Turbine Hall
  becomes **Boiler Hall** (69.7 / 66.9 dp), in P120j's PR, with a dated note here, and the lead
  tells Michael.
- **Proof headless (P120j):** the guard test; a suite that pins the hidden cost, one line at 88,
  102 and 113 dp, and a text box that never overlaps the badge's rect. Rotated text is rasterised
  level and then turned: check its sharpness on the Pixel 9a in the web preview.

### 4. "Blackout" stays the effect's word
The Lumen Accord's strike building is the Dusk Array; what it does is still a **blackout** in rules
text (ADR 0023 §10, `docs/HOW_TO_PLAY.md`; the GDD says the buildings "go dark") and in
`strike_kind`. "Blackout" alone is never a
display name (Call of Duty: Black Ops 4's mode), and "Dusk" is never used alone (DUSK, 2018).

### 5. Data and hashes
- Six `display_name` lines in `data/units/`. `type_names` is in `World.TYPE_ARRAYS`, so `defs_hash`
  changes. No test or fixture pins a `defs_hash` value (`tests/sim/test_replay.gd:40` is a
  synthetic one), and no replay is committed or saved by the game; a replay recorded on the old data
  would return `Replay.PLAY_DEFS_DIFFER`.
- No state hash, golden hash, perf-arena hash or `TICK_0_SEED_1` moves: names are not state. No
  Command, rule, state column or kernel changes. `game/sim/Strike.gd` changes a comment only, so it
  needs no mutation pass.

### 6. Legal screen
Run as ADR 0023 §13's screen (the same games, real military names, ADR 0025 §15's overruled list),
from the architect's knowledge. It is no trademark search: the lead adds the six new names to the
Phase 7 trademark list (ADR 0006's note of 2026-10-26), and the six retired names drop off it.

| Name or concept | Finding | Decision |
| --- | --- | --- |
| Oil Works, Fuel Works, Motor Hall, Relay Post, Rig Hands | no known hit in the screened games or among real military vehicles, aircraft, ships or weapon programmes; plain words or an oilfield trade | used (Michael, 2026-11-06) |
| Dusk Array | no known hit as the pair; "Dusk" alone is a game title (DUSK, 2018) | used; "Dusk" never alone |
| Turbine Hall | screened in ADR 0023 §13 | kept (on §3's condition) |
| Boiler Hall | no known hit | §3's fallback only |
| Gas Works, Still House, Synth Hall, Split House, Volt Works, Relay Mast, Sky Relay, Dark Array, Dim Array, Floorhands, Pipe Gang, Burner Hall | no known hit (Gas Works already in ADR 0023 §13) | not used |
| Motor Bay | no known hit as the pair; "Bay" is StarCraft II's Engineering and Robotics Bay and Red Alert 3's Mecha Bay | not used |
| Blackout Dish, Blackout Rig, Blackout Mast | too long for the caption | not used |
| Riggers; Drillers; Roughnecks | a Shadowrun archetype; Deep Rock Galactic's Driller and Mr. Driller; Starship Troopers (ADR 0023 §13) | rejected |
| Motor Pool; Outpost; Uplink | Company of Heroes; Dune II's radar; C&C 3's Space Command Uplink and Generals' Particle Cannon Uplink | rejected |
| Beacon; Reactor; Spire, Pylon; Shade | StarCraft II's Fleet Beacon; Halo Wars, C&C 3's Scrin and RA2's reactors; StarCraft; a Warcraft III unit | rejected |
| Blackout; Lights Out; Eclipse | a Call of Duty mode; a 1995 puzzle game; a board game | rejected as names ("blackout" stays the effect's word, §4) |
| Crack, Cracker; Tank Farm; "... Shop" | meanings outside the oil trade; reads as the tank unit; reads as a free-to-play game's shop | rejected |

### 7. What this supersedes and amends
- **ADR 0023:** §7's six names, and the same names where §13's rows and the answers repeat them
  (the rows stay as the screen's history). A dated pointer note sits in its header.
- **ADR 0025 §5:** the locked card (a dated note at the end of §5 names the phrases it replaces);
  §19's P120 row gets P120j's new HOW_TO_PLAY wording.
- **Kept as history:** ADRs 0007, 0018, 0019, 0025 (§5's older notes, §15), 0026, 0027 and 0029,
  and `docs/plans/`.
- **Updated by P120k:** `docs/GDD.md`, `docs/HOW_TO_PLAY.md`, `assets/art/STYLE.md`,
  `assets/CREDITS.md`, the art model's silhouette line, comments and the tests that pin a name.

## Consequences
- Every name in the drawer reads whole on every supported screen, and the guard test keeps it so.
- Naming gets a hard width budget: a future unit or building name is measured before it is chosen.
- The Phase 3 gate build shows the old names; the game is not public, so no player meets a rename.
- A locked card no longer shows its price; the player sees it once the requirement stands.
- The rename merges before P120j (P120j's guard test needs the new names to be green); P120j stacks
  on P120k's branch.

## Alternatives considered
- **Option B (lock plate in the price's place):** at 88 dp every two-word name wraps, and the plate
  sits where READY's green banner sits, so the two differ by colour. Not chosen.
- **Option C (veil, big padlock, name in the middle):** still stacks two names in one font, the
  shape that read wrong on the phone. Not chosen.
- **A two-line sash and the long names:** a two-line band is 46 dp high in a 77 dp stage; Michael
  ruled it out ("kun når teksten står på én linje").
- **"Needs <name>" on the sash:** "Needs Bunkhouse" alone is about 121 dp against at most 109 dp of
  room. Rejected; the seal does the word's work.
- **A smaller font or an ellipsis for long names:** breaks the 14 sp floor or cuts the name the
  player must find. Rejected.
- **Keeping Roustabouts with the Label's own 88 dp as the caption limit:** lets names touch the
  frame. Not chosen.
