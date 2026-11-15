# ADR 0044: The tutorial, the How to play screen, and the test that every entry is covered

**In short, for Michael:** the tutorial is a real match on a small map against a scripted opponent,
with short text cards that point at the button or the spot to touch, and a radio chirp; no voice.
The first lesson, "Basics", takes about 3 minutes and starts on first launch; three short drills
(about a minute each) teach the rest of what a new player would not find alone. All can be replayed
from the menu. The How to play screen explains every entry of `docs/HOW_TO_PLAY.md` in player words.
A test checks that every entry has its How to play text and that every Teach entry is in a lesson,
so a feature added later without either fails the build.

Status: **accepted, 2026-11-15 (Michael: "Ja til anbefaling", yes to every recommendation of
the plan's questions).** Written by the architect on branch
`claude/p500-phase5-plan` (base `main` at a2204d2f) with the plan
`docs/plans/2026-11-15-phase-5.md` (rows P527, P528, P530, P540-P545, P560). Questions 2 and 3 of
the plan are this ADR's.

## Michael's answers (2026-11-15)
- **Question 2, narrator:** text-only coach cards with a radio chirp, no voice (§2).
- **Question 3, the tutorial's shape:** option A, Basics (about 3 minutes, first launch) plus three
  drills (§1), with the ROADMAP rewording that P500b applies (the plan's P500b gives the text).

## Context
- `docs/HOW_TO_PLAY.md` has 108 rows in 19 sections today, 51 marked Teach; Phase 4b adds
  more (Board, Unload, Mine, hidden mines, repair, Hold and others), so about 140 rows and 60-65
  Teach rows at the 4b gate. Rows carry developer references (`long_press_ms` in
  `data/input_settings.tres`) that a player must not see. Rows have no stable id.
- ROADMAP Phase 5: a tutorial of about 3 minutes that includes every Teach entry, on first launch,
  replayable; a How to play screen that explains every entry; the gate: a new player finishes the
  tutorial without help and every entry is covered by one or the other. GDD: no voice acting.
- Sixty Teach entries do not fit one 3-minute lesson: one beat takes 5-15 s, and many Teach rows of
  one gesture (the strike aim's four rows) share a beat, but air, carriers, mines, repair and sale
  are each a scene of their own.
- Rule 4: the opponent acts through Commands only; ADR 0030: the AI sees only its `PlayerView`.

## Decision
### 1. Lessons
- **Basics** (about 3 minutes, first launch): camera, select, move, box select, attack, build and
  place, power, harvest, train, groups, win. **Drills** (about 1 minute each): superweapon and the
  satellite; aircraft, Home and carriers; repair, sale, mines and Hold (question 3, option A,
  Michael's choice). Every Teach row is in at least one lesson.
- **This changes the ROADMAP's meaning.** ROADMAP Phase 5 asks for one tutorial of about 3 minutes
  that includes every Teach entry. Option A keeps the 3 minutes for the first-launch lesson only;
  with the drills the whole tutorial is about 6 minutes, and the Teach entries of Phase 4b are
  taught in the drills, which a player may never open. Michael picked A on 2026-11-15, with the
  rewording; P500b applies it to the ROADMAP line (the plan's P500b gives the text). The gate
  (P560) then tests Basics with a new player and the drills by the bot run and the coverage test.
- A lesson is a match of its own scenario (`data/scenarios/tutorial_*.tres` on a small
  `data/maps/tutorial_*.tres`) with a fixed seed, the local player and `TutorialAi`. It is never
  resumed after a kill (ADR 0042 §6); it restarts.

### 2. Runtime
- **`TutorialDirector`** (`game/ui/tutorial/`, Node-side) plays the lesson's beats
  (`data/tutorial/<lesson>.tres`, `TutorialBeatDef`: id, prompt text key, anchor (a HUD control by
  node name, or a world tile), condition kind and parameters, `covers` (HOW_TO_PLAY ids), optional
  pause). It reads the snapshot, the selection, `HudState`, the camera and the drawer's state, and
  never writes the sim; between prompts it may pause the match through `MatchRunner.paused` (no
  Command, as the pause menu does). It issues no Command for the player.
- **`TutorialConditions`**: pure checks (selected n of a type, units in an area, a building placed
  or finished, a unit trained, harvest started, an enemy killed, a zoom level, a drawer tab open, a
  strike aimed and fired, and the drills' own).
- **`TutorialAi`** (`game/ai/`): a scripted opponent from `TutorialScriptDef`, triggered only by what
  its `PlayerView` shows (for example "when an enemy unit is within 8 tiles of my base, send the
  two squads"). Commands only, recorded like any AI's; the lesson replays and runs headless.
- **`CoachMark`** (`game/ui/tutorial/`): a ring on the anchor and a prompt card (text, Next where a
  beat is read-only, Skip lesson), placed by ADR 0015's rules in both orientations; it never takes a
  gesture the beat asks for.
- Progress in `SaveService` section `tutorial` (lessons done, Basics offered). First launch: after
  the intro, Basics starts with a "Skip tutorial" choice on its first card. Replay from the
  Tutorial screen, Settings and How to play. One-time XP per lesson (ADR 0045).
- Text only, with a radio chirp per card (question 2).

### 3. The How to play screen
- Opened from the main menu, Settings and the pause menu (P531). Sections as in `HOW_TO_PLAY.md`;
  each row's player text.
- The player text is hand-written data, `data/help/how_to_play.tres` (`HelpDef`: per row id a
  title and a body, in English through translation keys, question 12), not generated from the
  Markdown: the Markdown stays the developers' list, with data names and file paths.

### 4. Ids
- P530 (after the 4b gate, when the stream of 4b rows has stopped) adds an `Id` column to every
  table of `HOW_TO_PLAY.md`: kebab case, unique, never reused, the section's prefix
  (`camera-pinch`). From then on a PR that adds a row gives it an id (CLAUDE.md's rule to add the
  entry stands; the lint enforces the id).
- "Not yet in the game" rows are excluded from coverage.

### 5. The coverage test
`tests/project/test_how_to_play_coverage.gd` parses `res://docs/HOW_TO_PLAY.md` (readable in the
test run; docs are not exported) and fails when:
1. a row id has no `HelpDef` entry, or the entry's text is empty;
2. a Teach row id is in no beat's `covers` of any lesson;
3. a `covers` id or a help id names no row (stale);
4. player text contains a developer reference (a backtick, `data/`, `.tres`, `_ms`, `res://`);
5. the `PENDING` list (ids not yet covered, each with the row that covers it) is not empty, from the
   gate row P560 on (the pattern of ADR 0015 §6's scan).
`tests/e2e/test_tutorial_run.gd`: `TutorialBot` plays each lesson to its end headless through the
player's entry points (the controller's methods and pushed touch events, as the e2e suites do), and
the sum of each lesson's beat budgets stays within its target (Basics 180 s).

### 6. The gate
- A new player (someone who has never played it) does Basics on Michael's phone without help; the
  lead records where they hesitated; a beat that needed help is fixed before the tick.
- The coverage test is green with `PENDING` empty.

## Consequences
- Coverage is a build-time fact, not a review judgement; a new feature without help text or a Teach
  row without a beat fails the suite.
- About 140 entries need player text (P528) and are kept current by the same test.
- Coach marks name HUD controls; a renamed control breaks a lesson, and the bot run shows it.
- The tutorial waits for Phase 4b's gate, because its HUD is still moving.

## Alternatives considered
- **One 3-minute lesson for everything** (question 3, C is a 7-minute variant). Rejected as
  recommendation: too long for a first launch, or too fast to learn.
- **Un-marking Teach rows to How to play only** (question 3, B). Possible; like A it changes ROADMAP's
  wording and leaves air, mines and carriers untaught.
- **Generating help text from the Markdown.** Rejected: developer references and table prose are not
  player text.
- **Ids from the row text** (a hash). Rejected: every wording fix would break coverage.
- **The director commands the scripted enemy.** Rejected: the AI would read UI state, not its view.
