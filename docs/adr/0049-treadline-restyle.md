# ADR 0049: The Treadline restyle: the new UI look, the faction rename and the art direction

**In short, for Michael:** the game keeps its name, Treadline. The two sides get new names:
Nordværn (orange, today's Derrick League) and Facet (blue, today's Lumen Accord). We bring the look
of your Figma file into the game, starting with the menus and the battle HUD: its colours,
panels, type and its icon-and-word buttons. We build all of it ourselves in the game's theme. The
vehicle, building, terrain and backdrop pictures in the file are photo-like raster images. We use
them only to see where the look should go. We never import, trace or copy them. The HUD keeps
today's corners (credits top left, radar top right, BUILD bottom right), as you chose. Unit and
building names and the lore stay. How the new unit and building art is made is ADR 0050. Your
answers to all eight questions are recorded below.

Status: **accepted, 2026-11-24** (Michael; answers below; accepted in row P603 on the same branch,
PR #642). Proposed 2026-11-24 by the architect in row P600 on branch
`claude/p600-treadline-plan` (base `main` at 52b2649e), with the plan
`docs/plans/2026-11-24-treadline-restyle.md`.

Status note (2026-11-26, P621c docs; ADR 0050 "Amendment (2026-11-26, P621c)", Michael "A:
Holdfarve på pladerne"): the fixed faction colours behind answer 5, §5's "Team colours" bullet
and §7's palette line ("Each side carries its fixed faction colour in large panels and stripes …
A small marker carries the team colour") are replaced. The large panels wear the player's team
colour, the bodies stay neutral (Nordværn steel and iron, Facet white and graphite), and the
sides are told apart by shape, as §7's last Art direction line already asks ("in silhouette alone,
in fog grey and with team colours swapped"). The HUD accents keep the Nordværn orange and Facet
blue hues. No accepted text changed.

## Michael's answers (2026-11-24)
First reply (verbatim: "A, SVG til enheder men prøv om du ikke kan gøre dem mere realistiske.
brug gerne figma som tegner og PNG kun til de store bygninger, faste farver, Facet. og i spillet
skal det være muligt at zoome længere ind end det er idag."), then "ja til resten":
1. **A.** The corner HUD keeps its geometry and takes the file's look.
2. **Facet.** The blue faction is named Facet (§2 says why the first name was dropped).
3. **A.** Today's unit and building names stay. P606 is not run now (§6).
4. **A.** The lore stays: Nordværn is oil and gas, Facet is wind and sun.
5. **Superseded by "faste farver" (fixed colours).** Nordværn units are always orange and Facet
   units always blue. A small marker in the player's team colour shows the owner. ADR 0050 §3
   decides it; the HUD accents take the same hues (§5).
6. **No mono face**, unless P602 finds the file uses one (the recommendation).
7. **A.** The clock and the unit count go into the credits pill when the top row has room
   (P618).
8. **Yes.** Michael runs the free EUIPO/TMview and USPTO searches himself for "Treadline",
   "Nordværn" and "Facet". The formal clearance stays the Phase 7 box.

The rest of his first reply (SVG units made more realistic, PNG only for the large buildings,
Figma as a drawing tool, a closer zoom) is ADR 0050 (proposed). ADR 0051 (#643, accepted
2026-11-24) allows art made with Figma's own AI features; §1 below says how it meets this ADR.

Amends, on acceptance (P603 writes the dated notes; no accepted text is rewritten): ADR 0025 §13
(the tokens' values, the Lumen Accord accent) and §15 (the new design's overrulings, §4 below),
ADR 0023 §6 (the faction display names) and ADR 0006 (its 2026-10-26 status note about the
trademark search now names Nordværn and Facet). P603 wrote those notes. It changes no sim
rule, no Command, no `STATE_FORMAT`, no balance number and no hash: no unit or building name
changes (answer 3 A, §6).

## Michael's decisions (2026-11-24, relayed by the lead)
1. Restyle the whole look toward his Figma file (file key `HsBPSXZ6PTRp6KkdhEi6bT`), starting with
   the UI. Beside it runs one prototype unit and one prototype building in the new style (row
   P601, already running in another lane).
2. The game is **Treadline**. The factions become **Nordværn** (orange; internal id `fossil`) and
   **Facet** (blue; internal id `renew`; answer 2). Game text stays English through translation keys (ADR
   0044 §3). Campaign, multiplayer and the unit-details screen are wishes for later and are out of
   scope.

## Context
- **The title is already Treadline.** ADR 0006 (accepted 2026-10-10) made the store title
  "Treadline: Offline RTS" and the launcher label "Treadline". The main menu reads TREADLINE (P524)
  and the Android back question reads "Quit Treadline?". The package id is `dk.appcode.rts`, and
  Play has locked it. So the rename is the factions only (answer 3 A). The title does not
  change.
- **How the Figma file was read.** This session had no Figma tools: no ToolSearch and no Figma MCP
  tool was available to the architect. The element list in §3 is the lead's read-out of the file
  (the brief of 2026-11-24). Row P602 (art-director, with the Figma tools) reads the exact values:
  colours, sizes, type, the order glyphs and every name in the file. It checks §3's table against
  the screens and records the differences. No number in this ADR claims to come from the file.
- **The file's pictures are raster image fills.** Every vehicle, building, terrain and backdrop
  picture in the file is one rectangle holding a photo-like render, with no vector shapes. Where
  they came from is not known to us. CLAUDE.md (Legal) allows only SVG authored in this repository,
  CC0 or CC-BY assets with a CREDITS row, and Michael's own vector art drawn in Figma. It forbids
  AI images from outside tools, web images, and art from community files or shared libraries.
- **The HUD is pinned by tests and by guide v2.** `HudCorners.place` (ADR 0025 §2) is one pure
  function of the safe rect, the orientation, dp, the mirror and what shows. P581 (#639, open)
  makes the command bar 106 dp tall when it holds Stop or wraps a second row, and 64 dp
  otherwise. Guide v2 (ADR 0048, rows P582-P596, in flight) docks the tutorial card from
  `HudCorners.place`'s rects: 64 dp from the top in landscape and 120 dp upright. A sweep proves
  every lesson's target is reachable at the six sizes. `CoachMark.gd` has five rows in series
  (P585, P588, P589, P591, P592). P585 (#641, open) adds `GuideTokens` and `GuideCardThrough` to
  `theme.tres`.
- **The look already lives in one file.** `game/ui/theme.tres` holds the HUD's and the menus'
  tokens (`HudTokens`, `HudPanel`, `AccentFossil`, `AccentRenew`, the `Menu*` types) and both
  font families. `tests/project/test_ui_theme_scan.gd` fails on a font or a colour named outside
  it. A restyle is mostly this file plus the few layouts that change.
- **Names reach the defs hash.** `UnitDef.display_name` fills `World.type_names`. That table is
  one of `TYPE_ARRAYS`, and `WorldHash.defs_hash` feeds all of them. So renaming a unit or a
  building moves the defs hash. Every golden pair and every resume file then fails. Faction
  display names are not hashed: only `faction_ids` are.
- **The art budget is tight.** The sorted world's atlas page (cross-faction) is 2730 of 3584 rows
  (`tests/view/test_iso_atlas_budget.gd`, 854 left). Page 2 (shadows and flyers) is 2510. The
  page is 4096 px wide. A full page is about 44 to 56 MB of GPU memory (RGBA8, ADR 0027 §4).
  `assets/art/iso/` holds 18 MB of generated SVG, which is baked into the atlas at match start
  behind the deploy card.

## Decision

### 1. The file is a style reference, never an asset (hard rule)
- **The pictures.** No picture from the Figma file enters the repository or a build. This covers
  every vehicle, building, terrain, backdrop or other raster fill, whether whole, cropped,
  recoloured, upscaled or as a texture. Nothing is traced over them, by hand or by a tool. No
  model, outline, silhouette or panel layout is measured from them to be copied. They show a
  direction in words (§7). Our art is then made from our own models and shapes.
- **Figma AI (ADR 0051, 2026-11-24).** Figma's own AI features may now make new art that ships:
  large building pictures, backdrops and portraits (ADR 0050 §2). Each file needs its own
  CREDITS row (feature, date, short prompt, hand edits) and the resemblance screen. The pictures
  already in the style file stay a reference under the rule above. Their feature, date and
  prompt are not recorded, and they were not screened, so they cannot meet ADR 0051 §4. Using
  one would need Michael to supply those facts, then the screen and a CREDITS row.
- **Tool use.** A row that reads the file uses `get_screenshot` (base64, at most 1000 px) and
  `get_metadata` to look and to read values. Screenshots go to the session's scratchpad only and
  are never committed. `get_design_context`'s generated code is a reference for layout and values
  only. Its image or asset URLs are never fetched, and none of its code is pasted: we write
  GDScript and `theme.tres` ourselves.
- **The UI look** (panel shapes, colours, type choices, spacing, the icon-and-word button pattern)
  is a design direction from Michael's own file. We build it ourselves in `theme.tres` and our
  code. That is the same rule ADR 0025 used for his HUD design.
- **Glyphs.** If the file's order icons differ from ours, art-director draws our own SVG glyphs
  from simple shapes (`svg-art-style`, ADR 0046's licence, a CREDITS row each). They are never
  vectorised from the file.
- **Names in the file** are screened by §2 before any of them ships.

### 2. Names
- **Internal ids stay**: `fossil_*`, `renew_*`, `data/factions/fossil.tres`, the scenario and
  data paths, the theme type names `AccentFossil` and `AccentRenew`, and the replay and save
  formats. Only display names, lore text and translation values change. A new translation key is
  added only where a name is hard-coded today (the menus' `SIDE_FOSSIL` and `SIDE_RENEW`).
- **Factions.** **Nordværn** is written "Nordværn" everywhere players see it ("NORDVÆRN" in
  capitals). Every shipped font covers æ and Æ, and `tests/art/test_font_assets.gd` already checks
  æøå in each face. A key that needs ASCII uses `nordvaern`. **Facet** is the blue faction
  (answer 2).
- **Risky names, found so far:**
  - **"Helix"** is the name of a unit in *Command & Conquer: Generals – Zero Hour*: the China
    faction's heavy transport helicopter. CLAUDE.md forbids names from C&C. This is a must-fix
    before release. Note (answer 2, 2026-11-24): Michael dropped the name and chose Facet.
  - **"Ion …"** names. *Ion Cannon* is the C&C superweapon.
  - **Glowing crystal ore.** It reads as Tiberium (C&C) or the crystal minerals of StarCraft. Our
    economy stays oil and gas fields (ADR 0023 §11). The terrain kit's crystals are not adopted in
    any form.
- **The screen for every other name in the file** (P602 lists them all, from the screens and the
  four art sheets): ADR 0023 §13's list, plus the C&C, Red Alert, Generals, Tiberian Sun and
  StarCraft unit and building names known to the reviewer (for example Prism, Tesla, Mammoth,
  Obelisk, Orca, Kirov, Overlord, Paladin, Juggernaut, Predator, Siege Tank, Goliath, Thor), and
  real military designations. A name is either clear, risky (with the reason) or blocked. This is
  not a trademark search. That search stays a Phase 7 box in the ROADMAP (answer 8).
- **Unit and building display names.** Today's names stay (answer 3 A). They were
  screened in ADR 0023 §13, 0032, 0036 §16 and 0037 §14, they fit ADR 0032's one-line rule, and the
  HOW_TO_PLAY and lesson texts use them. P602 still screens the file's names, for the record.
- **Lore.** The energy-bloc framing stays, with the new materials (answer 4 A). Nordværn stays
  the oil-and-gas bloc, now in heavy northern steel. Facet stays the
  wind-and-sun bloc, now faceted and closed. The buildings (Turbine Hall, Wind Park, Oil Works),
  the economy and the superweapons are built on that framing. The tagline "Oil and gas against
  wind and sun. Choose your side." stays.
- **Store.** The store title stays "Treadline: Offline RTS" (ADR 0006). The package id
  `dk.appcode.rts` cannot change. The store texts in `docs/store/` name no faction today.

### 3. The UI restyle mapping
**Rule for every row:** the file sets the look (panel, border, colour, type, the icon-over-word
pattern, the stripes). Our component keeps its behaviour, its geometry and its tests, unless this
table says otherwise. Each look change is in the theme where it can be, or in code reading theme
tokens.

**Battle** (landscape 2:9945, portrait 14:352)

| Figma element | Ours today | Change |
| --- | --- | --- |
| Top bar: title or operation name | None. The map's name is on the pause card | Not shown: operations belong to the campaign, which is out of scope |
| Top bar: credits, power | `EconomyPill` (menu button, credits, power bar; one 48 dp pill, top left) | New look (P609). Same rect, same tap areas |
| Top bar: unit count, clock | None in battle (the pause card shows the time) | Answer 7 A: both go into the pill where the top row has room, measured and never by orientation (P618, after guide v2) |
| Top bar: Pause | The pill's menu button, which opens `PauseMenu` | Restyled with the pill. It stays a 48 dp target |
| Objectives panel | Skirmish: the objective line on the pause card (ADR 0025 §11). Lessons: the docked guide card (ADR 0048 §1) | No panel in skirmish (it would sit where the guide card docks). The guide card takes the panel's look (P612) |
| Alert line | `AttackToast` (`HudCorners.TOAST`, 4 s, a tap jumps there) | New look (P609). Same slot. With Reduced effects, no pulse |
| Radio or subtitle line | None in skirmish. Lessons: the prompt plus a radio chirp | Not built in this restyle (§4). It goes to the follow-up list |
| Command bar: Move, Attack | A ground tap moves (and stops an attack); an enemy tap attacks | No buttons (Michael's answer 4 of ADR 0025) |
| Command bar: Guard, Patrol | Not in the game (ADR 0023 §8) | Not shown |
| Command bar: Stop, Repair | `CommandBar`: STOP (in the column with CLEAR, P581), REPAIR (units to a repair building), MEND (buildings) | The icon-over-word look for every order: CLEAR, STOP, HOME, REPAIR, BOARD, UNLOAD, MINE, MEND, SELL (P610). P581's sizes are kept: 56 x 48 dp buttons, 106 dp with Stop or a wrap, 64 dp otherwise |
| Big Build or Train button | `BuildButton` (round, 64 dp, a progress ring, a count badge) | New look (P609). The word stays BUILD: one button, one meaning. The drawer's tabs already say what is trained |
| Minimap, bottom left | `RadarScope` (56 dp, top right) and the full `RadarMap` under it | Answer 1 A: it stays top right, with the new frame look (P609) |
| Ours, not in the file: the group column, the strike button, the guide dock | As today | Restyled with the HUD (P609, P612) |

**Other screens**

| Figma screen (landscape / portrait) | Ours | Change |
| --- | --- | --- |
| Intro 2:9631 / 14:34 | Boot splash and `IntroPlayer` (the icon tank, ADR 0043 §1-§2) | Kept. The file's backdrop picture is not used. The open-out meets the new menu backdrop colour (a token, P613) |
| Main menu 2:9654 / 14:57 | `MainMenu` (one column of buttons, the sides, the rank, the banner foot) | Tiles: icon and word, two columns where the width allows (measured), else one (P613). No Campaign or Multiplayer tile. The banner keeps its 48 dp of air |
| Skirmish, "Træfning" 2:9791 / 14:195 | `MapSelect` (map cards, side, level, Start, the +500 offer slot) | New look (P614). The rewarded offer stays the player's explicit choice |
| Loading 2:9902 / 14:309 | `DeployCard` (a still card: the icon, DEPLOYING, the map's name) | New look, still (P615). There is no progress bar or spinner: the bake blocks the main thread, so a bar could not move. No ad |
| Pause 2:10084 / 14:443 | `PauseMenu` (card, button column, chips, the upright foot banner) | New look (P616). The foot banner rules are unchanged: upright only, at least 16 dp from any control, none sideways or while the menu scrolls |
| Victory 2:10194 / 14:559 | `ResultScreen` (emblem, word, stats, Back, Play again, Double XP by choice) | New look (P617). No banner. The interstitial comes only after leaving, capped (ADR 0039) |
| Production 13:11 / 14:645 | The build drawer (`BuildSidebar`: a side panel sideways, a bottom sheet upright; tabs; `ItemTile` cards; queue; ADR 0032's sash) | New look (P611). It stays a drawer over the live map (ADR 0025 §5). Tile sizes are unchanged, because the guide's sweep uses them as anchors |
| Unit details 13:19 / 14:690, Campaign 2:9713 / 14:113 | None | Out of scope (Michael's decision 2) |
| Settings, How to play, Licences, Tutorial (not in the file) | `MenuScreen` screens | They take the menu frame's look (P614) |

Note (2026-11-26, P660; ADR 0052 accepted 2026-11-26, Michael: "Godkend alle 5 (anbefalet)"; the
table above stays as accepted): ADR 0052 sets the menu screens' look after P602's read-out.
- **Main menu:** the file's numbered list (a number, the word, an arrow) in place of icon-and-word
  tiles, with a commander card (rank insignia, title, XP bar, the next unlock) where the file has
  its campaign card.
- **Intro:** the open-out reveals a Figma-AI menu backdrop and the logo, with no added time.
- **Loading:** a still tip line.
- **Victory:** an unlock card for real unlocks only.
- **Rows:** P613 to P617 are replaced by P664, P666, P668, P669 and P670, and P650 by P661 and
  P667 (`docs/plans/2026-11-26-menu-look-v2.md`).

### 4. Where the file meets a rule
| The file | Here | Source |
| --- | --- | --- |
| Landscape: a full-width top bar and a full-width bottom command bar, with the minimap at the bottom left | Answer 1 A: keep the corner HUD's geometry and take the look. A short landscape phone is 280 to 411 dp high, and a 106 dp bottom bar takes 26 to 38 % of the map. The minimap at the bottom left would collide with the command bar and the group column under the left thumb. `GuideDock`, the guide sweep, P581's stack test and the lesson anchors are all built on `HudCorners` | ADR 0025 §2, ADR 0048 §1, ADR 0015 §5, touch-ui-rules |
| An objectives panel in battle | No panel in skirmish. The lesson card takes its look | ADR 0048 §1 (the dock's place) |
| A radio or subtitle line | Not built now: it would be a new event feed (a new feature). Its lines must not echo the voiced announcer phrases of C&C ("Construction complete", "Unit ready", "Insufficient funds" and the like). Follow-up list | Scope; CLAUDE.md Legal |
| Move, Attack, Guard and Patrol buttons | Not shown | ADR 0025 answer 4; ADR 0023 §8 |
| "Train" on the big button | BUILD only | ADR 0025 §4 |
| A loading progress bar | A still card | ADR 0043 §2 (P536) |
| Any ad shown on the battle, victory or loading screens | None. Battle: only the upright pause-menu foot banner. Result: none | CLAUDE.md Monetization; ADR 0039 §6; ADR 0025 §15 |
| Blur, glow, additive light, animated stripes or scanlines | Flat `StyleBoxFlat` panels with alpha, no blur, no additive blend. Anything animated is steady with Reduced effects | ADR 0025 §13; ADR 0029 §6; ADR 0027 §8 |
| Danish labels in the file ("Træfning", "Kamp") | English game text through the existing tables | CLAUDE.md; ADR 0044 §3 |
| Touch targets drawn under 48 dp, or controls in a notch or cut-out | At least 48 dp; the safe area holds | CLAUDE.md Mobile UX |
| The file's portrait and landscape boards as two fixed layouts | One layout function of the safe rect. The UI never assumes width > height. Tested at the six sizes and both orientations | ADR 0015 §5, §6 |

### 5. Tokens and type
- **Colours are theme tokens.** P604 sets the values that P602 reads from the file:
  - `HudTokens`: panel, border, text, money, danger, ok and warning, plus new tokens as the file
    needs them (expected: `line`, `panel_raised`, `text_dim` and `stripe`).
  - `AccentFossil`: the Nordværn orange.
  - `AccentRenew`: the Facet blue, which replaces today's cyan (the hue of ADR 0050 §3).
  - The `Menu*` styles.
  - `GuideTokens`, after P585, with values only.
  Type names stay, so no code changes for a colour. No colour literal is allowed outside
  `theme.tres` (the existing scan). Each accent keeps ADR 0025 §13's checks: a hue at least 15°
  from danger and from money, and text on the accent at a contrast of 4.5:1 or more. P604 pins
  them in a test.
- **Team colours.** Answer 5 is superseded by "faste farver" (fixed colours): fixed faction
  panels and a small team marker. ADR 0050 §3 decides it and plans its rows.
- **Type.** Amendment (2026-11-25): Michael chose the Figma type, three faces: Roboto Condensed
  (titles and headings), Inter (body text and buttons) and IBM Plex Mono (labels and numbers).
  Big Shoulders and Chakra Petch are removed, files and CREDITS rows with them (P605). The older
  text of this bullet follows as it was written, for the record: Big Shoulders (titles, buttons) and Chakra Petch (body, numbers) stay where the file's
  faces are close to them. A monospace label face is added only if P602 finds the file uses one
  (answer 6). Then it is one weight of an OFL 1.1 family: JetBrains Mono, or IBM Plex Mono with
  its "Plex" reserved name, so its files stay unmodified. It covers æøåäöüß and follows the ADR
  0025 §13 process: unmodified upstream files and `OFL.txt` under `assets/art/fonts/<family>/`, a
  CREDITS row, the Licences screen's list and the export notices, and a `FontVariation` in the
  theme only. P605 reports its web-size cost. A side benefit: its digits are fixed-width, which
  Chakra Petch's are not (the code keeps fixed digit slots today).
- **Sizes** stay as `touch-ui-rules` says: body text at least 14 sp, HUD numbers at least 18 sp,
  targets at least 48 dp.

### 6. Display names leave the defs hash (only if a unit or building name changes)
When a unit or building name must change (not now: answer 3 A; or before Phase 7's trademark
renames), row P606 makes
`WorldHash.defs_hash` skip `type_names` (and any other display-name table it feeds). Names are
not rules. A replay or a resume on renamed data is still the same game. The defs hash moves once:
the golden pairs and the smoke hashes are re-pinned in that row, and a resume file from an older
build is refused once (ADR 0042, as for any new build). After that, renames cost nothing in the
sim. The snapshot keeps `type_names`, so the HUD reads names as today. P606 is a `game/sim` row,
so it gets mutation testing (at most about 10 mutants). With answer 3 A, P606 is not run now. It
moves to Phase 7 as the first step of any rename that the trademark search forces.

### 7. Art direction (the target, in words) and the pipeline (decided in ADR 0050)
- **The target.** A grounded, readable military-industrial look, moving from today's flat,
  muted vector toward lit materials. It keeps the 2:1 isometric view (ADR 0023) and the one light
  from the north-west.
  - **Materials:** painted steel with worn edges, rubber tracks, dark glass, concrete pads.
  - **Shading:** two or three tone steps per face, a soft contact shadow, a thin highlight on top
    edges. There is no photo texture and no bloom.
  - **Palette:** desaturated greys and earth on the ground. Each side carries its fixed faction
    colour in large panels and stripes, so a unit reads at the far zoom. A small marker carries
    the team colour (ADR 0050 §3).
  - **Detail:** enough to read at 48 to 96 px on a phone (hatches, vents, track links, panel
    lines), with no detail smaller than 2 px at the bake scale.
  - **Nordværn:** heavy steel, wide tracks, tall boxy hulls and turrets, orange panels and
    hazard stripes, rivets and plates.
  - **Facet:** faceted, low wedge hulls, closed armour with no visible crew or open hatches, blue
    panels, flush seams, narrow light slits.
  - The two must still tell apart in silhouette alone, in fog grey and with team colours swapped
    in a mirror match (the readability check of `svg-art-style`).
- **Pipeline options** (to get closer to the target while staying legal):

  | | A: richer `tools/artgen` | B: own 3D models rendered to PNG | C: hybrid |
  | --- | --- | --- | --- |
  | What | More primitives per model (bevels, panels, track links, hatches) and shading baked into the SVG (tone steps, edge highlights, a contact shadow, panel lines) | Own 3D models built from code (for example bpy scripts in `tools/`) and rendered with lights to PNG frames, team colour from a mask | A for units (many frames, team colour), B for buildings (few frames, large) |
  | Legal | As today: own code, own output (ADR 0046) | Clean if the models are ours and no outside asset, HDRI or texture pack is used; the renderer is a tool and its licence does not reach its output | As A and B |
  | Frame time and draw calls (rule 6) | No change: still atlas quads on the same pages | No change, if the frames fit the same pages | No change |
  | Atlas memory | Same, if the frame boxes keep their size | Same at the same pixel size. A sharper 2x render would double the rows and break the one sorted page (ADR 0027 §4) | Same |
  | Web and APK size | The SVG grows, guess 2 to 3 times today's 18 MB (it compresses well). Bake time at match start grows with the path count | PNG frames, guess 15 to 40 MB, plus masks. The bake turns into a blit, so it gets faster | In between |
  | Team colour | Key-triad swap in the SVG text (as today) | A per-frame mask, recoloured at the bake: a new bake path | Both paths |
  | Tooling | None new | A pinned renderer in CI and in cloud sessions (a new install script, "say what is missing and stop" until it exists) | As B |
  | Ceiling | Illustrated, never photo-like | Closest to the file's renders | Close for buildings |

  Michael chose after P601 (2026-11-24): units in SVG (A, made more realistic), PNG only for the
  large buildings, Figma as a drawing tool. ADR 0050 (row P621) decides it. ADR 0051 adds Figma
  AI for single-view art. No art row starts before ADR 0050 is accepted.

  Note (2026-11-24, after ADR 0050's answers 2-5): the art rows that do not depend on ADR 0050's
  open question 1 (the building route) may start: the generator, the colour migration, the zoom
  and the unit batches. The building rows wait for the route (plan, P621b). ADR 0050 §8 adds
  Michael's rule of one coherent look across all graphics.

### 8. Sequencing against guide v2
- **It runs now, with no guide wait:** P602 (the read-out, docs only) and P601 (already running).
  The rename (P607) and the menu rows (P613-P615) touch no guide file.
- **It waits for a guide merge:**
  - P604 (tokens) waits for P585 (#641), the guide's own `theme.tres` row.
  - P610 (command bar) waits for P581 (#639).
  - P611 (drawer look) waits for P591 (`BuildSidebar.reveal_tile`).
  - P612 (the guide card's look) waits for P592, the last `CoachMark` row. It changes theme
    values only, so it never edits `CoachMark.gd`.
  - P608 (the lesson text rename) waits for P594, the last lesson-data row.
  - P618 (the pill's clock and count) waits for P595. It changes the top row that `GuideDock`
    reads, so it re-runs the guide sweep after the guide is proven.
- **Never built twice:** the restyle changes no `HudCorners` geometry before P595 and adds no
  `CoachMark` code at all (answer 1 A keeps the corner geometry).
- **HOW_TO_PLAY:** guide lane T1 owns `menus-tutorial-guide`, `menus-tutorial`,
  `menus-tutorial-end` and `menus-settings`. The restyle rows own `menus-main`, `menus-skirmish`,
  `factions-*` and the new `the-screen-in-battle-clock`. No two open PRs edit the same row.

### 9. Budget and proof
- **Battle screen.** Panels stay `StyleBoxFlat`, which batches as untextured rects. Stripes and
  frames come from at most one small UI texture. The HUD may add at most 4 draw calls over today,
  read on the phone's perf card in P620; the perf suites' forecasts leave the HUD out. Labels are
  updated on change only: the clock once a second and the count when it changes. No string is
  built per frame.
- **Headless proof:**
  - Every restyled screen passes its suite at the six sizes and both orientations (ADR 0015 §6).
  - Targets are at least 48 dp, and everything is inside the safe area.
  - The ad gaps hold: 48 dp on the start page, 16 dp at the pause foot.
  - `test_ui_theme_scan.gd` stays green, with no literal outside the theme.
  - The token tests check hue distance and contrast.
  - The guide sweep and P581's stack test stay green.
  - `HudCorners`' tables are unchanged until P618.
  - A view-only check: the tutorial bot's Basics under the new theme gives the same command log
    and state hash.
- **Not headless:** whether it looks like the file and reads well on the phone. That is Michael's
  check in P620.

## Consequences
- The game gets the new look screen by screen, in small theme-led rows, without moving a control.
  The guide, the sweep and the lesson anchors stay valid.
- The faction rename is text and data, and its data rows start one balance run (`data/**`). If
  only faction names change, the sim and its hashes are untouched.
- The file's art is never an input. Our units and buildings move toward it only through our own
  models, chosen after P601.
- The file's landscape layout was not taken (answer 1 A). It would have cost a new layout plan,
  a redone dock and sweep, and less map on short phones.

## Alternatives considered
- **Import the file's renders as interim art.** Rejected. It breaks CLAUDE.md Legal and ADR 0046,
  and the renders' origin is unknown.
- **Generate code from `get_design_context` and adapt it.** Rejected. Its output is web code, and
  our UI is GDScript and a theme. The values are read and typed in by hand.
- **Rename all 52 unit and building names to the file's.** Not taken (answer 3 A). It costs
  a new screen, the HOW_TO_PLAY and lesson texts, ADR 0032's fit work and a hash change, for no
  gameplay gain.
- **The file's landscape layout first.** Rejected (answer 1 A). It would rebuild the
  geometry that guide v2 is being built on right now.
- **A full localisation pass with the rename.** Out of scope. English stays the only language, and
  the existing tables only change values.

## Questions for Michael (answered 2026-11-24)
1. **The HUD layout in landscape.** A: keep the corners with the file's look; B: the file's
   full-width bars and a bottom-left minimap; C: B upright only. **Answer: A.**
2. **The blue faction's name.** The first name clashed with a C&C unit (§2). A: keep it; B: a new
   name, "Facet" or "Lattice" proposed. **Answer: Facet.**
3. **Unit and building names.** A: keep today's; B: the file's names after P602's screen.
   **Answer: A.**
4. **The lore.** A: Nordværn oil and gas, Facet wind and sun, new materials, the tagline kept;
   B: new lore. **Answer: A.**
5. **The blue faction's colour.** A: blue accent and blue default team colour; B: blue in the HUD
   only. **Answer: superseded by fixed faction colours and a team marker (ADR 0050 §3).**
6. **A monospace label face.** A: none; B: one OFL mono weight if the file uses one. **Answer:
   none unless P602 finds the file uses one.**
7. **Clock and unit count in battle.** A: in the pill when there is room; B: neither.
   **Answer: A.**
8. **Trademark.** Free EUIPO/TMview and USPTO searches now, formal clearance in Phase 7.
   **Answer: yes; Michael runs the free searches for "Treadline", "Nordværn" and "Facet".**
