# ADR 0052: Menu look v2: the intro, the menus, loading, pause and result after Michael's Figma screens

**In short, for Michael:** the intro, the main menu, Skirmish, loading, pause and the result screen
take the look of your Figma screens: a picture behind the menus with a dark shade over it, the
numbered list with arrows, square panels, amber for the action and the three Figma faces. We make
the pictures new with Figma AI; the pictures inside your file never ship. What stays: buttons of
at least 48 dp, the ad rules, the corner HUD in battle, the build drawer, English text, RANK and
not LEVEL, and our own names. You chose the recommended answer to all five questions (at the end).

Status: **accepted, 2026-11-26.** Michael's answer (2026-11-26, verbatim): "Godkend alle 5
(anbefalet)", so A for questions 1 to 5. Proposed the same day by the architect in row P660 on
branch `claude/p660-adr0052-menu-look` (base `main` at 99d0a5b5, PR #682), and accepted in that
PR; the planned acceptance row P660b was folded into it. Plan:
`docs/plans/2026-11-26-menu-look-v2.md`, linked from `docs/plans/2026-11-24-treadline-restyle.md`.

Amends (dated notes added in PR #682; no accepted text is rewritten):
- ADR 0049 §3, "Other screens": the Intro, Main menu, Loading and Victory rows (§3 below).
- ADR 0043 §2 (the open-out meets the backdrop picture) and §5 (the main menu's content).
- The restyle plan's rows P613 to P617 and P650. They are marked replaced, not deleted.

No sim rule, Command, `STATE_FORMAT`, hash, balance number or HUD geometry changes.

## Context
Michael, 2026-11-26, verbatim: "det er i den retning jeg gerne vil have spillet så det ser mere
profisionelt ud og ligner noget til en million", "også i forhold til intro og menu".

- **The source.** His Figma file `HsBPSXZ6PTRp6KkdhEi6bT`. The architect has no Figma tools. The
  values come from P602's read-out in `assets/art/STYLE.md`, "Treadline UI look". P602 read the
  landscape boards by text and the portrait boards and the Intro by structure only.
- **What is done.** Tokens v3 (P604) and the type (P605) are on `main`. The rename (P607) and the
  AI-row check (P623) are on `main` too.
- **What is open.** The menu rows P613 to P617 and P650 have not started. ADR 0049 §3 wrote them
  before the read-out existed. The read-out then found real differences: STYLE.md "Check of ADR
  0049 section 3", items 8 to 13.
  - The main menu is a numbered list with arrows and no icons, beside a campaign card.
  - Loading has a tip line.
  - Victory has an unlock card.
  - Production is a centred modal.
  - The landscape battle is a full-width console.
- **The names.** The file still uses names this project has blocked or rated risky (STYLE.md
  "Names in the file, screened").
- **Out of scope here.** The map art (units, buildings, terrain) is in another lane: the
  pre-render prototype P653 and an ADR 0050 §3 amendment, P621c. Nothing here touches it.

## Decision

### 1. Screens in scope
| File board | Ours | Change | Row |
| --- | --- | --- | --- |
| Intro | Boot splash, `IntroPlayer` | The open-out reveals the menu backdrop and the logo (§3) | P665 |
| Hovedmenu (main menu) | `MainMenu` on `MenuScreen` | Backdrop and scrim; the list and the commander card (§3) | P663, P664 |
| Træfning (Skirmish) | `MapSelect` | Faction cards with a hero portrait; maps and levels as cards and chips | P666, P667 |
| Indlæsning (loading) | `DeployCard` | A still card over the loading backdrop, plus one still tip line (§3) | P668 |
| Pause | `PauseMenu` | The new look over the frozen map | P669 |
| Sejr (result) | `ResultScreen` | The stat strip and the look; an unlock card for real unlocks only (§3) | P670 |
| Produktion (production) | `BuildSidebar`, `ItemTile` | The look only, in P611. It stays a drawer (§2) | P611 |
| Kamp (battle) | The corner HUD | The look only: P609, P610, P618 | P609, P610, P618 |
| Felttog (campaign), Enhedsdetaljer (unit details) | none | Out of scope (ADR 0049 decision 2) | none |

Settings, How to play, Licences, Tutorial and Restore take the menu frame's look with Skirmish
(P666).

### 2. Rules where the file meets a rule (hard)
1. **Touch and text.** Every target is at least 48 dp. The file's 46 px menu items become 48 dp.
   Body text is at least 14 sp and HUD numbers at least 18 sp. The file's 6 to 9 px map tags are
   not adopted.
2. **Banners.**
   - The start page keeps 48 dp of air above its banner (ADR 0025 §12, ADR 0039 §5).
   - The pause foot banner is upright only and at least 16 dp from any control (ADR 0039 §6).
   - There is no banner on Result or Loading, and no ad of any kind on the intro.
   - The rewarded offers stay the player's explicit choice: +500 on Skirmish, Double XP on
     Result.
3. **No full-width battle bars.** The corner HUD keeps its geometry (ADR 0049 answer 1 A, ADR
   0015 §5). The file's landscape battle console is not built in any form: the full-width
   bottom bar, the minimap bottom left and the Move, Attack, Guard and Patrol buttons.
4. **No production modal.** The build drawer stays a drawer over the live map (ADR 0025 §5). The
   file's card content (name, price, state word) may be adopted in P611. The centred 732 x 270
   modal with its "Luk" button is not.
5. **Copy is English, through the text tables** (ADR 0044 §3): `MainMenuText`, `MapSelectText`,
   `DeployCardText`, `ResultText` and `MenuText`. The file's Danish words are a reference for the
   meaning only.
6. **RANK, not LEVEL** (ADR 0045 §3). The file's "LEVEL 07" becomes the rank and its title. "Level"
   already means the computer's Easy, Normal or Hard.
7. **Scrim colours live in `theme.tres`.**
   - The file's `Læseskygge` gradient and `Kontrastlag` tint become theme tokens. No colour or
     alpha literal goes in code (the theme scan).
   - Text over a picture meets 4.5:1 against the scrim drawn over a white pixel. The test then
     holds for any picture, now and later.
   - Screens inside a match (Pause, Result) use the flat `scrim_panel` over the frozen map. They
     carry no picture and no gradient texture, so a match holds no menu texture.
8. **The type stays as ADR 0049 §5 sets it** (amendment of 2026-11-25): Roboto Condensed Bold,
   Inter Regular and Bold, IBM Plex Mono Regular.
   - The intro and menu logo is Roboto Condensed Bold. ExtraBold is part of a variable font,
     and the project ships static files only.
   - A further weight of a shipped face comes only through ADR 0025 §13's process, in the row
     that uses it.
9. **Pictures** (ADR 0049 §1, ADR 0051).
   - No raster image from the file ships, whole, cropped, traced or as a texture.
   - New stand-alone art is made fresh with Figma's own AI features: the menu backdrop, the
     loading backdrop and one hero portrait per faction.
   - Each file gets its own `assets/CREDITS.md` row: "AI-made with Figma AI, no copyright claimed
     by AppCode ApS", with the frame, the feature, the date, a short prompt and the hand edits.
     The art-director screens each one for resemblance before the commit (P623's test).
   - Each picture is wired by a theme or data reference, never by a path literal in code.
   - No such picture goes in the match atlas.
10. **No new menu features.** The file shows several things this ADR does not build:
    - save and load slots, Restart mission, settings tabs with Apply;
    - the Skirmish player table, start resources, unit cap and rule toggles;
    - stars, an objectives list and a next-operation card;
    - map coordinates and a loading bar.
    Asks for them go to the lead's follow-up list.

### 3. The look per screen (Michael's answers 1 to 5, all A)
- **Main menu (P664).**
  - The file's pattern for each item: a number, the word, an arrow. The word carries the
    meaning. The number is decoration in `text_mute` and counts the items shown. The arrow is
    our own SVG glyph.
  - The first item has the 2 px amber bar. Items at rest are `ground` at 50 %.
  - The items: Continue (only while a resume exists), Skirmish, Tutorial, How to play and
    Settings. There is no Campaign or Multiplayer item.
  - Where the file has the campaign card, a **commander card**: the rank insignia and title, the
    XP bar to the next rank, and the next unlock with its rank, all from `Progression` and
    `ProgressionDef`.
  - The card stands beside the list where the measured width allows, else above it. This is
    never decided by orientation.
  - The logo is TREADLINE, with the tagline and the two side names in their accents.
- **Intro (P665).** The open-out ends on the menu's own first frame: the backdrop picture under
  its scrim and the logo in place.
  - No title card is added.
  - `min_ms`, `max_ms`, `open_ms` and `fade_ms` in `data/intro_settings.tres` keep their
    values. The intro never ends before loading does and never adds a wait (ADR 0043 §2).
  - The backdrop is part of the threaded menu load.
  - With Reduced effects, the cross-fade goes to the same frame.
- **Loading (P668).** A still card over the loading backdrop: DEPLOYING, the map's name and one
  tip line, with no bar and no spinner, because the bake blocks.
  - The tips are keys in a text table. The tip is picked by a counter in `MenuPrefs`. It
    advances once per card shown and wraps at the count. There is no randomness, so a test pins
    the order.
  - The loading backdrop is let go when the card closes.
- **Result (P670).** An unlock card shows only when this match's XP crossed a rank whose
  `ProgressionDef.unlocks` entry opens a map or a level. Its text comes from those entries.
  Units are never unlocks (ADR 0045 §4). No new save field.

### 4. Names and look that are never taken over (legal, hard)
- **Helix** and every "Helix-…" name, and the "⌁ H" glyph. The blue side is Facet; its mark is
  our own.
- **Prisme/Prism, Aegis, Ion… (Ionreaktor), Spøgelse/Ghost, Krigsfabrik/War Factory.**
- **The ore economy:** malm, Ravmalm, Malmhøster and glowing crystal ore. Ours stays oil and gas
  (ADR 0023 §11, ADR 0049 answer 4 A).
- **The building set as a set.** Byggecentral, Krigsfabrik, Raffinaderi, Malmlager, Teknologilab,
  Reparationsdepot, Kraftværk, Kaserne, Radarstation and Helikopterplads together reproduce Red
  Alert's tech tree. No screen, tip or card lists them, in any language.
- **The file's tagline** ("Krigen om Nord"), place names (Askehavn, Isbrud, Isfronten,
  Nordhavet), people (Lind, Voss) and unit codes (K-7, X-9 and so on). STYLE.md rates most of
  them clear as words. They are the file's campaign fiction, and ours keeps its own tagline and
  lore (ADR 0049 §2). So no screen, tip or card uses them.
- **Announcer lines in the C&C style**: no "Construction complete", "Unit ready", "Insufficient
  funds", "Base under attack" or the like as text or voice (ADR 0025 §16). Loading tips are plain
  how-to sentences.
- **The landscape battle console layout**, which reads as the Generals control bar (§2 item 3).
- **The landscape drawer** keeps ADR 0025 §16's differences from the Red Alert sidebar. It is on
  demand and closed by any map touch, never pinned, without the radar, with named cards and
  worded tabs.

### 5. Budget and proof
- **Menus.** The backdrop and the gradient add at most 2 draw calls to a menu screen. Each
  backdrop ships in two crops (wide and tall) of at most 1920 px on the long side. The row
  reports the web-size cost. The crop is chosen by the measured aspect of the screen, not by an
  orientation flag.
- **Battle.** Pause and Result add no texture. Labels are set on change only.
- **Headless:**
  - Each screen's suite passes at the six sizes in both orientations: 48 dp targets, the safe
    area and the banner gaps.
  - The theme scan and the token tests pass, including the scrim contrast of §2 item 7.
  - The intro's timing tests pass with their values unchanged.
  - The tip order and the unlock card's cases are pinned.
  - The player-text scan finds none of §4's names.
- **Not headless:** whether it looks like the file and "noget til en million". That is
  Michael's phone check in P671.

## Consequences
- The menus take the file's look in small rows, without new features, and the HUD rows are not
  touched.
- Two Figma-AI pictures and two portraits enter the game. AppCode ApS claims no copyright in
  them, and each carries a resemblance screen (ADR 0051 §5).
- The menu uses more memory while it is open. Nothing new stays in memory during a match.
- P613 to P617 and P650 are replaced. Their tests and HOW_TO_PLAY duties move to the new rows.

## Alternatives considered
- **Use the file's own pictures as backdrops.** Rejected. ADR 0049 §1: their feature, date and
  prompt are unknown, and they were never screened.
- **Icon-and-word tiles as ADR 0049 §3 wrote.** Not taken (answer 1 A). It looks less like the
  file.
- **A title card after the intro.** Not taken (answer 3 A), because it adds time.
- **A loading bar.** Rejected. The bake blocks the main thread (ADR 0043 §2).

## Michael's answers (2026-11-26)
Verbatim: "Godkend alle 5 (anbefalet)". The questions stay as they were asked, with the answer
under each.

1. **Main menu items.** A: the file's numbered list (a number, the word, an arrow), in one or two
   columns as the width allows. B: icon-and-word tiles as ADR 0049 §3 wrote. **Recommended: A.**
   It is the file's look, and the word still carries the meaning.
   *Dansk: Hovedmenuen som filens nummererede liste med pil (anbefalet), eller som ikon-fliser?*
   **Answer: A.**
2. **The card beside the menu.** A: a commander card where the file has its campaign card: rank
   insignia, rank title, XP bar and the next unlock. B: no card; the rank line stays under the
   list as today. **Recommended: A.** There is no campaign, and the rank is the player's progress.
   *Dansk: Et kommandørkort med rang, XP og næste oplåsning i stedet for felttogskortet (anbefalet)?*
   **Answer: A.**
3. **Intro into the menu.** A: the open-out reveals the menu backdrop and the logo, with no
   added time. B: a short title card after the open-out, which adds 1 to 2 seconds.
   **Recommended: A.** ADR 0043 §2 says the intro never adds a wait.
   *Dansk: Introen åbner direkte ud i menuens baggrund og logo uden ekstra ventetid (anbefalet)?*
   **Answer: A.**
4. **A tip on Loading.** A: one still tip line in a fixed order, which changes each time. B: no
   tip. **Recommended: A.** The card shows for a few seconds anyway, and nothing on it can move.
   *Dansk: En fast tip-linje på indlæsningsskærmen, en ny hver gang (anbefalet)?*
   **Answer: A.**
5. **An unlock card on Result.** A: only when the match reached a rank that opens a map or a
   level. B: never. **Recommended: A.** It shows a real unlock, and never a promise the game has
   no feature for.
   *Dansk: Et oplåsningskort på resultatskærmen kun når en bane eller sværhedsgrad faktisk låses
   op (anbefalet)?*
   **Answer: A.**
