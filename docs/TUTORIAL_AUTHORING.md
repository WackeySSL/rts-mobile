# Authoring a tutorial lesson

Notes for whoever adds or changes a lesson (ADR 0044, plan rows P541-P543). The four lessons are
`basics`, `strikes`, `air` and `support`; every file below is data, so no number lives in code.

## The files of a lesson `<id>`

| File | What it is |
|---|---|
| `data/tutorial/<id>.tres` | `TutorialLessonDef`: the beats in order, the time target, the scenario, the enemy and the match seed |
| `data/tutorial/<id>_enemy.tres` | `TutorialScriptDef`: the steps the scripted opponent plays (`TutorialAi`) |
| `data/scenarios/tutorial_<id>.tres` | The match: spawns, on `data/rules.tres` (every shipped scenario shares it) |
| `data/maps/tutorial_*.tres` | The ground; `basics` has its own, the three drills share `tutorial_drills` |
| `data/tutorial/text_en.tres` | The English words (`TutorialTextDef`): one string per beat prompt and lesson title, by `prompt_key`. Name a card as `{type_id}` (`{power_plant}`), never by typing its name: `TutorialText` puts in the display name from the defs |

`balance.yml` ignores `data/tutorial/**`, `data/maps/tutorial_*` and `data/scenarios/tutorial_*`, so
a lesson edit starts no balance run. Keep lessons out of the balance sets.

## A beat

One prompt and one condition. Fields are on `TutorialBeatDef`; the condition kinds and what each
reads are on `TutorialConditions`. A few rules that the tests enforce (`test_lesson_data.gd`):

- `covers` names rows of `docs/HOW_TO_PLAY.md` by id; a row that is not in the game (the "Not yet"
  section) is never named. That every Teach row is covered by some lesson is the coverage test's
  (P545), not this suite's.
- A beat that asks for units or buildings names a type that is in the match. A `SELECTED` or
  `UNITS_IN_AREA` beat is satisfied from the scenario's own units; a build or training beat names
  something the player's faction can build with a producer that stands (or that an earlier beat
  builds) and a requirement that stands. All the beats' purchases together stay within the start
  credits (2000 on the shared rules), because a lesson has no income to count on.
- An area is on the map and on ground a foot soldier can stand on.
- A read-only beat is `NEXT`. Only it may `pause` the match. Where nothing can be checked (hold a
  card, tap a button of the command bar) the beat is `NEXT` and its prompt says "Tap Next".
- `budget_s` is match time after which the card offers help. The beats' budgets sum within the
  lesson's `target_s` (Basics 180 s; a drill about a minute, up to 90 s).
- `delay_ticks` waits in match time, so a paused match does not count. A beat that must come
  after the pause menu closes (it shows while the menu is up otherwise) gets a delay.
- A prompt that talks about what the enemy is doing waits for it to be true: a step's tick is the
  think that sent the order, and the order takes effect a tick later and then travels. Give the
  beat a `delay_ticks` of the walk or flight (the poke's first hit lands about 110 ticks after its
  step, the raid's fighter is over the base about 55 ticks after), or word the prompt as what is
  about to happen.
- A card is named by `{type_id}` in the text, so the prompt shows the display name the card has.

### Anchors

- `CONTROL`: a HUD node by name, looked up under the HUD root. The names the lessons use:
  `EconomyPill`, `PowerBar`, `Menu`, `RadarScope`, `BuildButton`, `TabStructures`, `TabInfantry`,
  `TabVehicles`, `TabFlight`, `Tile_<type id>` (a card of the drawer), `PlaceConfirm`, `Deselect`,
  the command-bar buttons `Stop`, `Home`, `Repair`, `Board`, `Unload`, `Mine`, `Mend`, `Sell`,
  `AddGroup`, `Group1`, and `StrikeButton`, `StrikeConfirm`. A control that is not shown (the Stop
  button with nothing selected) gives a card without a ring, so a beat that points at a command-bar
  button comes after the beat that selects what shows it.
- `TILE`: a ground tile of the map. `CoachMark` projects it through the camera.

### Off-screen tiles

`CoachMark` does not move the camera. A tile that is off the screen gets its ring pinned to the
nearest edge of the safe rect, in the direction of the tile. So:

1. A tile the player must touch (a spot to move to, a unit to tap) is on the screen when the beat
   shows. The camera starts on `camera_start_tile` at the middle zoom level (1.0). A tile is 64 px
   wide and 32 px tall there, so a tile `(dx, dy)` from the start tile sits `32 * (dx - dy)` px
   across and `16 * (dx + dy)` px down from the middle of the screen. On the 1280 x 720 base that
   is on the screen up to `|dx - dy| <= 20` and `|dx + dy| <= 22` in landscape, and up to
   `|dx - dy| <= 11` and `|dx + dy| <= 40` in portrait. Stay inside both (`|dx - dy| <= 9` and
   `|dx + dy| <= 18` leaves room for the HUD), or put the beat after one that moves the view. The
   zoom levels 0.75 and 1.5 show a third more and a third fewer tiles.
2. A tile that is off the screen on purpose (the enemy's cluster for a strike, the far shore of the
   ridge) is a "look there" ring: the ring sits on the edge, the prompt says where and what, and the
   beat's condition asks for something that does not need the tile on screen (an area, a count).
   Do not rely on the ring alone for a tap: the player pans, or uses the radar, which the Basics
   lesson teaches first (`pan`, `zoom`, `radar` come before any beat that needs them).
3. The tile is on the map (the data test checks it), and the area a condition checks is where
   units can stand. An anchor on rock or water is allowed (a ring is only a mark), a condition's
   area is not.
4. In portrait the near edge of the screen can hide a tile under the drawer, the command bar or
   the group column. Prefer an anchor on the control (`Tile_<type>`, `BuildButton`) for build
   beats and a tile for the world.

## The scripted enemy

`TutorialAi` plays `steps` in script order on every think (1 s); a step fires once. It sees what
its `PlayerView` shows, so a trigger like `ENEMY_NEAR` reacts to the player and `TICK` to the clock.

- `after_ai_step` on a beat names a step of the lesson's enemy; the prompt waits for it to have fired
  (the director reads it after `wait_idle()`, through `MatchRunner.controller_of`; never inject
  a controller). The test checks every name against `step_ids()`.
- Two QUEUE steps of one type count each other's items. Put them in script order, or chain the
  later one with `after_step`; a step never waits for one that comes after it (checked).
- A QUEUE step needs a producer of its own in the scenario and credits for its items.
- A step that orders units waits until it has units to send and a place to send them (a `TILE`, a
  `HOME` building or the `TRIGGER` row), so give the enemy the units at the start.
- The enemy's walk takes real time (a squad walks about a tile a second): set a wave's tick so that
  it arrives when the beats that talk about it are on. The play test pins each step's tick.

## What to run

`bash scripts/run-tests.sh -a res://tests/ui/tutorial/test_lesson_data.gd` (the data),
`-a res://tests/ai/test_tutorial_lesson_enemies.gd` (the enemy on its scenario) and
`-a res://tests/ui/tutorial/test_tutorial_gate_worker.gd` (the gate on a WORKER runner).
