# ADR 0020: The dummy opponent, `PlayerView` and where AI runs in the tick

Status: accepted, 2026-10-22 (Michael: 1 ja, 2 ja). Proposed 2026-10-22. Docs PR P68 (with
`docs/plans/2026-10-22-phase-3.md`), accepted by the lead's row P68b on the same PR (#166). The
Phase 3 gate is "a full match can be played against a dummy opponent that only builds and
defends"; this ADR decides how that opponent sees the match, where its code runs, and how it is
proven deterministic. Phase 4's real AI uses the same hook.

## Acceptance note (2026-10-22)
Michael answered the questions of ADRs 0017-0021 in chat on 2026-10-22, verbatim "Ja til alle
anbefalinger" (yes to all recommendations), which the lead records for this ADR as "1 ja, 2 ja":
1. **ja:** AI controllers run inside the tick job, before `loop.step` (on the worker in `WORKER`),
   see the match only through `PlayerView`, think every `think_period` (15) ticks, and their
   Commands are stamped and recorded like a player's (§2, §3). This supersedes ADR 0012 §1's and
   §2's plan to run the AI on the main thread in `ticked`, and ADR 0012 §3's scan allowance of
   `.world` in `game/ai`, and only those (ADR 0012 carries dated status notes).
2. **ja:** `scripts/run-sim-smoke.sh` runs three dummy-vs-dummy matches of 1 800 ticks with fixed
   seeds from Phase 3 on (plan row P95), with its flags, exit codes and report schema unchanged.
   It runs wherever `scripts/verify.sh` runs: in CI's verify job and in each session's one
   verify run before a push (§5). Balance runs stay in GitHub Actions only (CLAUDE.md, Token
   budget).

The decision below is unchanged by the acceptance. P68b corrected §5's "in CI" (verify.sh runs
the smoke step in every session too). §3's "and only those" names ADR 0012 §1 and §2; its last
bullet also ends ADR 0012 §3's scan allowance of `.world` in `game/ai`, which the supersession
covers too (ADR 0012 §3 carries a dated status note). Nothing here is applied in code yet:
plan rows P78, P78q, P81-P83b and P95 apply it. The line for `.claude/agents/ai-dev.md` (AI code
reads only `PlayerView` and runs in the tick job) waits for Michael's explicit yes to that agent
file.

Status note (2026-10-26, P68e docs; ADR 0023 accepted 2026-10-26): §4 carries a dated status note:
one dummy `AiDef` per faction; the dummy never builds or fires a superweapon. No accepted text
changed.

Status note (2026-10-26, P26ai docs): §1, §2, §3 and §4 carry dated status notes on `PlayerView`
(P78), `AiDriver` (P82), the `game/ai` scan (P78q) and the dummy (P83, P83b) as merged: the
answers for what a player cannot see, the end rule and the turn test, `game/ai` without the
allocation check, the guard point as a data offset and the defence's cost. No accepted text
changed.

Status note (2026-10-27, P26ak docs): §3 and §4 carry dated status notes: `MatchRunner.opponents`
is not exported, and the dummy has its two defs as P83d merged them. No accepted text changed.

## Context
- CLAUDE.md rule 4: humans and AI act only through `Command` objects. Rule 3: randomness only
  through per-match `DetRandom` streams; `game/sim/DetRandom.gd` says "AI controllers use
  STREAM_AI_BASE plus the player id" (`STREAM_AI_BASE` is 100).
- ADR 0010 §1 reserves `game/sim/PlayerView.gd` (visible enemy rows, own rows, explored cells),
  "with a scan test over `game/ai` like the randomness scan", built by the first AI code.
- ADR 0012 §1 and §2 expected the AI on the main thread: "A command submitted inside a
  `ticked(N)` handler is stamped N in both modes. The Phase 4 AI acts there", and "The main thread
  reads the World only inside a `ticked` handler or after `wait_idle()` ... Phase 4's AI and
  `PlayerView` read it there". `tests/project/test_view_reads_snapshot.gd` therefore allows `.world`
  in `game/ai`.
- ADR 0014 judges the main thread's work p95 over the heavy window and over its publish frames
  (5.6 ms each on the gate phone). A think every 15 ticks falls on 1 publish frame in 15 (6.7 %),
  more than the 5 % a p95 ignores, so a think of more than a few ms on the main thread would show
  in that verdict. On the worker, the job p95 limit is 13.3 ms and the gate runs measured 5.6-6.0
  ms (ADR 0016's table).
- ADR 0007 §9: `MatchLoop` is the one tick driver; `TickJob.run` calls `loop.step` on whichever
  thread runs the job, and `tests/core/test_tick_job.gd` walks the job's objects and fails on a
  Node or a Resource.
- `.claude/agents/ai-dev.md`: decide every 15 ticks, each decision under 1 ms on CI, all randomness
  through the match's stream, difficulty as data.
- `scripts/run-sim-smoke.sh` is a stub that prints "no sim yet"; `scripts/verify.sh` runs it with
  `--matches 3`; its real body is the Phase 4 box "runs real headless AI-vs-AI matches".

## Decision

### 1. `PlayerView` (game/sim, pure)
One player's legal view of a World, made per think by `PlayerView.of(world, player)`. It gives:
own rows and their columns; the enemy rows the player sees (the `Targeting.sees` rule: the cell
holding the row is visible) and only their public columns (owner, type, position, hp); the
player's credits, queues, power and rally points; whether a cell is explored; the last-seen
records (ADR 0017 §3); `Placement.reason` for the player; and the World constants the AI needs
(tabs, harvest modes) re-exported, so `game/ai` never names `World`. An accessor asked about a
row the player does not see answers as if the row did not exist.

Status note (2026-10-26, P26ai docs, P78 as merged, #196, and P77, #203; the text above stays
as accepted), on `game/sim/PlayerView.gd`:
- **Rows.** `own_rows` and `seen_rows` are ascending World rows (seen: every other owner's row,
  enemy or neutral, in a cell the player sees). The public getters (`row_id`, `row_owner`,
  `row_type`, `row_pos`, `row_hp`) answer an own or a seen row; the own columns (`row_order`,
  `row_harvest_mode`, `row_home`) an own row only; anything else answers `PlayerView.MISSING`
  (-1), `row_pos` (-1, -1). A gap between two listed rows shows that hidden rows lie between them;
  a controller does no arithmetic on row indexes.
- **Placement.** `placement(type_index, col, row)` is `Placement.reason` for the player, which
  reads every row, so a tile held by a mobile enemy row the player does not see answers
  `OCCUPIED`. The sim's `PLACE` refuses it too, and no row is returned, so §5's "never returns a
  row the player does not see" holds.
- **Aliases.** Every public field is a copy; the row columns and the placement input are aliases
  of the World's arrays behind an underscore, read only by the getters. GDScript has no private
  members, so only the naming keeps a caller from them; `test_view_reads_snapshot.gd` keeps
  `game/ai` off the name `World`, not off `._` members (ADR 0012 §3's note of the same date).
- **Re-exports:** `Tab`, `HarvestMode`, `Order`, `TABS`, `MILLI_PER_TILE`, `TILE_CENTRE`, with
  the World's values (a test pins each pair). P77 adds the last-seen records (`ghost_*` copies,
  `ghost_of`, `ghost_pos`).

### 2. `AiController` and the driver
- `game/ai/AiController.gd` (ai-dev): `class_name AiController extends RefCounted`, with
  `player_id`, `think_period` and `think_offset` ints and
  `func think(view: PlayerView, out: Array[Command]) -> void`. A controller copies its `AiDef`'s
  values into ints and arrays when it is made and keeps no Resource and no Node, so the job's walk
  stays green.
- `game/core/AiDriver.gd` (lead, pure): `static func think_all(world: World, controllers:
  Array[AiController], out: Array[Command]) -> void` calls, in ascending player order, every
  controller with `(world.tick + think_offset) % think_period == 0`, each with a fresh `PlayerView`.
  It is the only code that hands a World to the AI side.
- `think_period` is 15 (data). `think_offset` puts the think on a tick whose step does not end in
  a checkpoint (a checkpoint hashes after the step that starts at `tick % 15 == 14`): the dummy of
  player p thinks at `tick % 15 == 7 + p - 2` for p in 2..4.

Status note (2026-10-26, P26ai docs, P82 as merged, #205; the text above stays as accepted), on
`game/core/AiDriver.gd`:
- **The end.** Nothing thinks once `match_end_tick` is above 0: the sim drops every Command after
  the end, and a controller cannot see the end through its view.
- **The order** is picked in place, without scratch storage: each pass takes the due controller
  with the smallest (player, list index) after the one that thought last, so two controllers of
  one player think in list order. A null entry is skipped; a period below 1 counts as 1.
- **The turn test** is GDScript's `%`, as written above, so a controller with a negative
  `think_offset` would miss its turns. `DummyAi.create` gives an offset in 0 to `think_period` - 1
  (`posmod`), so no merged controller is affected; a later controller keeps its offset in that
  range.

### 3. Where it runs: inside the tick job
This supersedes ADR 0012 §1's "The Phase 4 AI acts there" and §2's "Phase 4's AI and
`PlayerView` read it there" (the main thread in `ticked`), and only those:
- `TickJob.run` calls `AiDriver.think_all(world, controllers, commands)` before `loop.step`, on
  the thread that runs the job (the worker in `WORKER`, the main thread in `SYNC`). The human's
  commands drained by the runner are already in the list, so the AI's follow them; `MatchLoop`
  stamps every command with this tick and records it in the replay.
- The result equals ADR 0012's plan: the AI reads state N and its commands are stamped N, in both
  modes. The cost moves off the main thread.
- Every headless driver (the suites, the perf harness if it ever runs AI, `run-sim-smoke.sh`) calls
  `AiDriver.think_all` before `MatchLoop.step`, so the phone and CI cannot drift.
- A replay holds the AI's commands like a player's: `Replay.play` needs no AI.
- `MatchRunner` gets `@export var opponents: Array[AiDef]` (player 2 upward) and builds the
  controllers at `start()`, each with its stream from
  `DetRng.create(match_seed, DetRandom.STREAM_AI_BASE + player)`; the job gets them with the World.
- `game/ai` joins the thread rules of ADR 0012 §2 (no Node, no autoload, no engine singleton, no
  clock) and the purity scan's rules for the sim; `test_view_reads_snapshot.gd` drops its `.world`
  allowance for `game/ai`, and a new rule fails on the name `World` there.

Status note (2026-10-26, P26ai docs, P78q as merged, #201; the text above stays as accepted):
the scan is applied. `tests/project/test_view_reads_snapshot.gd` fails on `.world`, `.loop`,
`.replay`, `.probe` and the name `World` in `game/ai`, and `tests/project/test_sim_purity.gd`
scans `game/ai` with the sim's purity and thread rules. **`game/ai` is exempt from the sim's
allocation check** (no array literal, `duplicate()` or `slice()` in a loop body), the lead's
decision of 2026-10-26: that check guards the loops of the per-tick phases, and a think runs on
one tick in 15, counted and bounded by its tests (§4).

Status note (2026-10-27, P26ak docs, P109 as merged, #214, 1d7b2cb, which ported the change from
P107's branch, e685d5e; the text and the note above stay as accepted and as dated):
`MatchRunner.opponents` is a typed `Array[AiDef]` that is **not** exported. Godot 4.7.2 keeps an
exported default in a cache that `GDScript::clear()` does not empty; with the typed array there, the
editor's exit (export, import) can free `AiDef` while it clears `MatchRunner`, and the autoload
scripts leak, which fails `scripts/export-web.sh`. No scene or `.tres` sets the list: the tests and
the Skirmish route (P90) set it in code. Any exported typed array or dictionary of a `class_name`
script in a long-lived script carries the same risk; the CI web export is its guard.

### 4. The dummy opponent
`DummyAi extends AiController`, driven by `data/ai/dummy.tres` (`AiDef`):
- **Build:** it follows the def's build order (a list of types), queuing the next affordable item
  whose requirement it owns, keeping each queue at most `queue_target` long; it places a ready
  structure at the first tile of a fixed spiral around its Headquarters where `Placement.reason`
  is `OK`; it keeps `harvesters_wanted` harvesters per refinery and rebuilds lost buildings in
  build-order order.
- **Defend:** when it sees an enemy row within `defend_radius_tiles` of one of its buildings, it
  sends its idle combat units there with `ATTACK_MOVE`; with none in that radius, it sends them back
  to a guard point beside its Headquarters. It never sends a unit farther than `defend_radius_tiles`
  from its buildings, so it never attacks.
- It uses no random number (it gets its stream for Phase 4's use), no information beyond
  `PlayerView`, and no bonus.
- Cost: one think visits its own rows, the seen enemy rows and at most `place_tries` spiral tiles.
  Tests count that work (no clock in a session); the ai-dev rule of 1 ms on CI is read from CI's
  log only.

Status note (2026-10-26, P68e docs, ADR 0023 accepted 2026-10-26; the text above stays as
accepted): with two factions (ADR 0023 §6) the dummy has one `AiDef` per faction:
`data/ai/dummy.tres` becomes `dummy_fossil.tres` (the Derrick League's build order) and
`dummy_renew.tres` is new (the Lumen Accord's), and the Skirmish route puts the dummy of the
opponent's faction in `MatchRunner.opponents` (plan rows P83d, P90). A build order lists only its
faction's types. The dummy builds no strike building and never sends `SUPERWEAPON`; Phase 4's AI
uses the superweapons. The rules above are unchanged.

Status note (2026-10-26, P26ai docs, P83 as merged, #204, and P83b, #206; the text and the
note above stay as accepted and as dated), on `game/ai/DummyAi.gd`, `PlacementSpiral.gd` and
`DummyDefence.gd`:
- **The def** (`AiDef`) also names the Headquarters' and the harvester's type ids (`hq_type`,
  `harvester_type`), the spiral's stride (`place_stride_tiles`, the largest footprint plus one
  free tile) and the think slot (`think_tick`: player p thinks at `tick % think_period ==
  think_tick + p - 2`), and from P83b `guard_offset_tiles`. All numbers are in `data/ai/dummy.tres`.
- **The guard point** is the Headquarters' centre (the first building's when there is none) moved
  by `guard_offset_tiles`, each axis cut to half of `defend_radius_tiles`, so it lies inside the
  radius whatever the data says.
- **The destination** is the most pressing threat's position (the seen row of another non-neutral
  owner nearest to its nearest own building, within the radius; ties to the lower row), else the
  guard point. The defence orders an `IDLE` combat unit, or one it sent there itself; a unit that
  a player or a rally point gave an order keeps it. A unit it sent keeps its order until the
  destination changes (an order that ended short counts as arrived), so a still threat costs one
  Command; a moving threat costs one per think.
- **"Never farther than `defend_radius_tiles`"** holds for the order's target point.
  `Formation.assign` spreads the units round that point, so a slot can lie a tile or so past the
  radius, and an `ATTACK_MOVE` may chase a target past it (the way back to the guard point too).
  The dummy still sends no order to a point outside the radius, so it never attacks.
- **Cost.** A think visits its own rows, makes (seen enemy rows) x (own buildings) distance tests
  for the threat (`DummyDefence.tests`, pinned) and asks at most `place_tries` spiral slots
  (`DummyAi.placement_tries`): more than "visits the seen enemy rows", bounded and counted.

Status note (2026-10-27, P26ak docs, P83d as merged, #221; the text and the notes above stay as
accepted and as dated): the defs are `data/ai/dummy_fossil.tres` (id `dummy_fossil`, the Derrick
League's build order) and `data/ai/dummy_renew.tres` (id `dummy_renew`, the Lumen Accord's, the
same order with the `renew_*` types); `data/ai/dummy.tres` is gone. The run-sim-smoke matches (P95)
play the two against each other on Kestrel Flats; the Skirmish routes (P90) give the dummy the
other faction's def.

### 5. Proof
- A dummy-vs-dummy match of 9 000 ticks (10 minutes) run twice from one seed gives the same
  checkpoint hashes, and its replay replays to them.
- A scripted attacker (scenario orders) against the dummy ends in the attacker's victory, and in a
  dummy-vs-dummy match `dropped_commands` stays 0 (the dummy never sends an invalid Command).
- `PlayerView` never returns a row the player does not see (a crafted World with hidden rows).
- The scan over `game/ai` (§3).
- `run-sim-smoke.sh` (question 2, ja): it runs 3 dummy-vs-dummy matches of 1 800 ticks each with
  fixed seeds and writes the report JSON's schema. `scripts/verify.sh` calls it with
  `--matches 3`, so it runs in CI's verify job and in each session's verify run before a push;
  balance runs (many matches) stay in GitHub Actions. Phase 4 swaps in the real AI and the longer
  matches for its box.

## Consequences
- The AI's think cost lands in the job p95 on 1 tick in 15, which the job limit (13.3 ms) has room
  for; the main thread's verdicts do not see it.
- `ticked` keeps working for the view; no AI code waits for it.
- Phase 4 adds strategy, scouting and attack waves behind the same `think` call and `AiDef` data.

## Alternatives considered
- **The AI in `ticked` on the main thread** (ADR 0012's plan): equal results, but its cost lands
  in the main thread's publish-frame p95 (Context).
- **The AI inside `Sim.step`:** it would make `game/sim` depend on `game/ai` and put AI code under
  the sim's kernel rules.
- **A dummy that cheats** (full vision, free credits): breaks GDD pillar 4 and would teach Phase 4
  nothing.

## Questions for Michael
1. The dummy opponent runs inside the sim's own tick on the sim thread, thinks once a second, sees
   only what its side sees, and its orders are saved in the replay like yours. Do you accept that
   (it changes ADR 0012's plan to run the AI on the main thread)? (ja/nej; recommended: ja)
2. From Phase 3 on, should `scripts/run-sim-smoke.sh` run three short dummy-vs-dummy matches in
   CI (about 2 minutes of game each), instead of printing "no sim yet" until Phase 4? (ja/nej;
   recommended: ja)
