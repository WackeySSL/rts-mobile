# ADR 0026: Place first, build afterwards (structures are built on the spot)

Status: proposed, 2026-11-01, on `main` at 5203ce0; revised 2026-11-02 after the lead's one-lens
review. Plan: `docs/plans/2026-11-01-hud-v2.md` (rows P128-P131). Michael asked for it after the HUD
rows; the lead reads that as the player-facing switch (P130) landing after the drawer: the sim rows
P128-P128c and P129 may run beside the HUD rows where files do not collide, and P130 waits for P120b
and P124 (lead decision, 2026-11-01). Amends ADR 0017 §1, §4 and §7, ADR
0018 §5 and §7, ADR 0019 §1 and §2, ADR 0020 §4, ADR 0023 §10, ADR 0024 §9 and ADR 0025 §4 and §6
(§12), each only on Michael's yes. A sim rule change: one new row column, a changed `PLACE`, one
new Command, `STATE_FORMAT` 5 and one re-pin of every golden hash.

## Context
- **Michael, 2026-11-01** (M3 in ADR 0025), answering the lead on his HUD design's layout rule 2
  ("Placer først, byg bagefter. Tryk en bygning → placér → byggeriet starter på stedet"): "Place
  first, build afterwards: yes." Tap a building card, place the ghost, tap the check mark: the price
  is taken and the building is constructed on the spot. No queue, no "Ready", no placing afterwards
  for structures. It gets its own ADR and is implemented after the HUD rows. Units keep a queue.
- **Today** (ADR 0018 §5, `game/sim/Production.gd`): a structure is queued in the player's
  STRUCTURES queue (`QUEUE`, paid at once), its progress runs in PRODUCTION at the Headquarters'
  rate (`low_power_percent` on low power, nothing while the producer is missing or blacked out),
  it stops "ready" at 100 %, and `PLACE` (payload empty) puts it on the map complete through
  `World.add_building`, which blocks its tiles, starts a strike building's charge
  (`Strike.start_charge`) and sets `had_producer`; `apply_place` pops the head, counts
  `stat_built` and gives a refinery its free tanker. The cost never moves at `PLACE`.
- The dummy AI (ADR 0020 §4, `game/ai/DummyAi.gd`) queues structures from its build order and
  places a ready head on a spiral round its Headquarters.
- The perf arena (units only) and the base arena (`perf_bases.tres`, whose scenario orders queue
  only units) place no structure, so they lose no behaviour; but a new hashed row column changes
  every golden hash, as P109's strike columns did.

## Decisions in short
| # | Topic | Decision |
| --- | --- | --- |
| 1 | State | A new row column `build_left`: the work left in hundredths of a tick; 0 = complete (every spawned, loaded or test-added building), above 0 = under construction |
| 2 | `PLACE` | Payload `[type_index]`: checks tab, build time, producer, faction, requirement, credits, the site limit and `Placement.reason`; takes the whole price, adds the row with `build_left` = `type_build_ticks * 100` and a starting hp |
| 3 | Construction | In PRODUCTION, rows ascending: the queue head's rate (`low_power_percent` on low power); pauses while the site is offline; goes on if the Headquarters dies (question 4); hp rises with the work; completion does what `PLACE` did (charge, free tanker, `stat_built`) |
| 4 | Unfinished | Blocks its tiles, can be seen, attacked and destroyed; makes and uses no power, produces nothing, meets no requirement, fires no gun or strike, takes no tanker, keeps no player alive |
| 5 | One at a time | A player has at most `construction_sites_max` (`data/rules.tres`, 1) buildings under construction |
| 6 | Cancel | `CANCEL_BUILD` = 16: refunds `construct_refund_percent` of the price (question 1); the row leaves in REMOVE with no loss counted and no wreck |
| 7 | Queue | Transition with both paths (P128), then `QUEUE` of a structure and the empty `PLACE` are dropped (P131); the STRUCTURES queue arrays stay and stay empty |
| 8 | AI | The dummy places first under the same rules (P129) |
| 9 | View | Tap a structure card → placement at once; the check mark shows the price; a construction badge with the percent; the BUILD ring and the drawer's queue row show it; Cancel on the command bar; READY and the Ready chip go |
| 10 | Hashes | `STATE_FORMAT` 5; one re-pin (the golden hexes, `TICK_0_SEED_1`, the format pins, the sanitizer's `KNOWN_FORMATS`); named exception 19 for `MatchSnapshot`; no kernel touched, the sanitizer's `dump.h` gains 5 |

## Decision

### 1. A building under construction is a row
- `World.ROW_ARRAYS` gains **`build_left`** (after `offline_until`): hundredths of a tick of work
  left, the unit of `queue_progress` (`Production.PROGRESS_PER_TICK`). 0 means complete; every row
  starts at 0 (`add_unit`), so scenario buildings, `WorldLoad` spawns and test Worlds stay complete
  with no change. Only `PLACE` writes a positive value; CANCEL_BUILD writes -1 (§6).
- **Three rule ints** in `RulesDef` and `data/rules.tres` (rule 5: no number in code), copied by
  `WorldLoad.copy_rules` into World scalars listed in `World.RULE_SCALARS` and `UNHASHED_SCALARS`
  (so in `defs_hash`, not in the state hash): `construct_start_hp_percent` (10),
  `construct_refund_percent` (75; 100 if question 1 is A) and `construction_sites_max` (1).
- **World.gd's room:** it has 969 of gdlint's 1,000 lines and `tests/sim/test_world_split.gd` pins
  it without the max-file-lines pragma. The column, the three scalars, their list entries and doc
  lines take about 20; P128 counts before it writes, and if the file would pass about 990 lines it
  first moves the thin wrappers `add_building` and `footprint_origin` out (their callers then call
  `Buildings` directly, as P70c moved code out) in the same PR, so the split test stays as it is.
- **A row, not player state:** a per-player "building under construction" id would also do with one
  construction at a time, but the column keeps the rule with the row (it dies, is selected, is
  drawn, is cancelled), works unchanged if a later rule allows several, and costs one int per row.
  The hash changes either way (a player array is hashed too).
- `Buildings.add` gains a parameter `complete: bool = true`; `PLACE` passes false, so the strike
  charge does not start at placement (§3). `had_producer` is still set at `add` (a player who
  places anything already had a Headquarters, so nothing changes).

### 2. `PLACE` starts the construction
- **Command 10, `PLACE`**: `target_x`, `target_y` a point in the footprint's origin tile (milli),
  as today; payload **`[type_index]`**. The factory gains the type as its **last** parameter,
  `place(player_id, target_x, target_y, type_index: int = -1)`, so its fifteen call sites in eight
  files (`PlacementController`, `DummyAi` and the tests among them) compile unchanged and -1 builds
  the old empty payload; P131 makes the type required, with every call site in that one PR. Valid,
  else dropped and counted (`dropped_commands`), when all hold:
  1. the payload has one entry, a type in range whose `type_tab` is STRUCTURES and whose
     `type_build_ticks` is at least 1 (a defence in depth; a data test rejects 0, below);
  2. the player owns a **complete** STRUCTURES producer that is not offline (`producer_row`, now
     skipping unfinished rows) whose faction allows the type (`_faction_allows`, ADR 0023 §6).
     "Not offline" is new for `PLACE` (today `apply_queue` asks only for a producer, and the queue
     head then waits while it is blacked out): a blacked-out Headquarters starts no site;
  3. the type's requirement is owned by a **complete** row (`_owns`, now skipping unfinished rows;
     ADR 0018 §5's "losing it later leaves things as they are" holds for a construction too);
  4. `credits >= type_cost`;
  5. the player has fewer than `construction_sites_max` rows under construction (§5);
  6. `Placement.reason(...) == OK` and `World.add_building` accepts the row.
- **Then**, in COMMANDS: the credits fall by the **whole price at once** (the design: the price is
  taken at the check mark; a price paid over the build time would need a "waiting for money" state
  and a rate rule, and ADR 0018's "paid when queued" already chose paying up front); `build_left` =
  `type_build_ticks * 100`; `hp` = `max(1, type_max_hp * construct_start_hp_percent / 100)`. The
  tiles are blocked at once (units cannot walk into the site), as `add_building` does today.
- `PLACE` with an empty payload keeps its old meaning (place the ready STRUCTURES head) until P131
  removes it (§7).
- **A build time of 0** is valid data today (`tests/sim/test_defs_data.gd` rejects only negative
  `build_ticks`); with it a site would never pass through completion (no charge, no tanker, no
  `stat_built`, 10 % hp) and `target(w)` would divide by 0. P128 adds one data rule instead: a type
  whose tab is STRUCTURES has `build_ticks` of at least 1 (every structure in `data/units/` has 150
  or more), and `PLACE` drops a type with less (rule 1, for hand-built Worlds). Not "complete at
  once in COMMANDS": a second completion path for a case no data has, and an instant building is a
  free wall or turret.

### 3. Construction in PRODUCTION
- `Production.run` first walks the derived `building_rows` (ascending; at most the players x
  `building_cap` rows, up to four players, no allocation) and advances each row with
  `build_left > 0` while its owner is not defeated and the row itself is not offline (a Blackout
  Array pauses a site as it pauses a queue). The step is `Power.scaled(world, owner,
  PROGRESS_PER_TICK)` (100, or `low_power_percent` of it on low power, as the queue head's). So the
  build time is `type_build_ticks` as before: the item now waits on the map, not in the queue.
- **The Headquarters dies while a site rises** (question 4): recommended, the site **goes on**. It
  is paid for and on the map; without a complete Headquarters no new site can start (`PLACE` rule
  2); and a player with no complete producer left is defeated by `Outcome` in the same PRODUCTION
  step whatever its sites are (§4), so a site cannot keep a beaten player in the match. Today the
  queue head waits while the producer is missing, and a finished structure can still be placed
  after the Headquarters died (ADR 0018 §5's note); "goes on" keeps the second and drops the first.
  If Michael answers B (freeze), the walk also asks for a complete Headquarters that is not offline:
  one condition more.
- **Hit points rise with the work:** with `done = type_build_ticks * 100`, `w = done - build_left`
  and `start` the starting hp, `target(w) = start + (type_max_hp - start) * w / done` (integer, an
  int64 product); each step adds `target(w_new) - target(w_old)` to `hp`, so damage taken stays
  taken and a site never heals past what its work allows (question 2). No repair exists.
- **Completion** (`build_left` reaches 0, in the same step): `Strike.start_charge` (a strike building
  charges from completion, question 3; ADR 0023 §10, the GDD's "from placement"), the free unit of a
  refinery (`ProductionSpawn.spawn_free`), `stat_built += 1`. Nothing else changes: the row was
  already a building.

### 4. What an unfinished building is
| Rule | Under construction | Code |
| --- | --- | --- |
| Blocks its tiles, counts for `build_reach_tiles` and `building_cap` | Yes | unchanged (`Buildings.add`, `Placement`) |
| Seen, selected, targeted, attacked, destroyed | Yes; destroyed it is a lost building (DIED, `stat_lost_buildings`), no refund | unchanged |
| Its sight | Yes | unchanged (FOG and its kernel) |
| Makes or uses power | No | `Power.run` skips it, as an offline row |
| Is a producer (queues advance through it, units spawn at it, `QUEUE` finds it) | No | `producer_row` skips it |
| Takes a rally point (`RALLY` names an own producer) | Yes, harmlessly: the point is kept per tab (ADR 0018 §6) and used once a complete producer spawns there | `Outcome.apply_rally` unchanged |
| Meets a requirement | No | `_owns` skips it |
| A defence fires | No; it still picks targets (TARGETING and its kernel unchanged, as a defence on low power) | `Combat.fire` skips it, as an offline row |
| A strike building fires (`SUPERWEAPON`) | No | `Strike` refuses it (its `ready_tick` is 0 until completion, so the check must be explicit) |
| A refinery takes tankers | No | `Harvest`'s refinery choice skips it |
| Keeps its owner alive (ADR 0018 §7) | No | `Outcome._owns_producer` skips it |
| A tap on it opens the drawer on its tab (ADR 0024 Q3 A) | No | the view (P130) |
| An enemy's last-seen record | The type only: the memory shows the finished picture | `LastSeen` unchanged (a known limit) |
An unfinished building is what it will be only in its ground and its hit points: nothing it does
for its owner starts before it is finished, which is what "under construction" means; a decision,
not a question.

### 5. One construction at a time
- A player builds `construction_sites_max` structures at a time, 1, as the one STRUCTURES queue
  builds one at a time today, so the base's pace and the dummy's balance stay where they are. A
  `PLACE` at the limit is dropped. More sites at once is a data change (each site then runs at the
  full rate; a shared rate would be a rule for a later ADR), not a question now.

### 6. Cancelling a construction
- **Command 16, `CANCEL_BUILD`** (from ADR 0017 §4's reserved 16-19): `target_id` an own row with
  `build_left > 0`; payload empty; the common rules (a player who is not defeated, nothing after
  `match_end_tick`). Factory `cancel_build(player_id, building_id)`.
- **Effect** in COMMANDS: the credits rise by `type_cost * construct_refund_percent / 100` (question
  1; the view reads `construct_refund_percent` from the snapshot to label the button, §10); `hp` = 0
  and `build_left` = -1 (the cancel mark). The row leaves in REMOVE with the others:
  its tiles are freed (`Buildings.unblock_dead`), its DIED record carries 1 in its seventh int
  (today always 0), `Outcome.count_losses` skips a row marked -1, and the view draws no wreck, crater
  or death effect for such a record. On its last tick the row may still be picked as a target and
  draw fire (TARGETING and FIRE run before REMOVE), in both twins alike, so it stays deterministic.
- A site that is destroyed is lost, with no refund (§4).

### 7. The STRUCTURES queue
- **P128** adds the new path beside the old: `PLACE [type]` starts a construction, while `QUEUE` of
  a structure and the empty `PLACE` work as today. The UI and the dummy keep the old path, so every
  merged state plays.
- **P129** moves the dummy and **P130** the UI to the new path. They **merge as a pair**, P130 first
  and P129 right after it, on one combined-tree check by the lead, so no merged state has the player
  and the dummy building by different rules. With P128's split taken, both wait for P128c (the
  `Strike`, `Harvest` and `Outcome` skips): without them a dummy's site could take tankers, keep it
  alive or fire a strike.
- **P131** removes the old one: `QUEUE` of a type whose tab is STRUCTURES is dropped and counted, an
  empty-payload `PLACE` is dropped, and `Production.run`'s "a done structure waits at the head"
  branch goes. The STRUCTURES queue's arrays stay (`TABS` stays 3, the tab still names what the
  Headquarters builds and sorts the drawer), always empty, so `CANCEL [STRUCTURES, slot]` finds
  nothing and is dropped. Dropping the arrays would be a second layout change for no gain.

### 8. The AI
- **P129** (ai-dev): `DummyAi` no longer queues structures. Each think, when it has no site under
  way, the next structure of its build order is affordable, its requirement is owned complete and
  its Headquarters stands, it sends one `PLACE [type]` at the first spiral slot that
  `view.placement` answers OK for (at most `place_tries` asked, as today). A site counts as "had"
  for its build order, so it is not placed twice. `PlayerView` exposes `build_left` for the rows it
  shows (own and seen; a seen site is visible state, so Pillar 4 holds; P128 adds it, the file is
  `game/sim`'s). The dummy sends `CANCEL_BUILD` never. Same rules as the player (GDD Pillar 4).
- **HOW_TO_PLAY** (P129's row, Buildings): "The enemy builds the same way: its buildings go up on
  the spot, show their percent and can be attacked and destroyed before they are finished".

### 9. The view and the UI (P130)
- **A structure card** (ADR 0025 §5) has the states ready to buy, too expensive, locked, and busy
  (another site under way: stripes and the word "BUILDING"). A tap on a ready-to-buy card starts
  placement at once (the card shows "selected"); a tap on another state shakes it. The drawer closes
  and returns after the placement as ADR 0024 R1 says.
- **The check mark** (`GhostControls`, M2) shows the price under its glyph ("600", tabular, 18 sp:
  `touch-ui-rules`' least size for HUD numbers and the theme's `ItemCost`; the 32 dp glyph and a
  22 dp line fit the 64 dp button). It
  sends one `PLACE [type]`. Pending and "Blocked" keep P86b's flow with a new answer rule: the
  placement ends when the published snapshot past the Command's tick shows an own building of the
  type at the ghost's origin; "Blocked" when it does not (the credits fell meanwhile, a unit walked
  onto the site, another site started).
- **The site on the map:** the building's own picture (no modulate, so the sorted world's one batch
  holds, ADR 0023 §2), its health bar always shown while unfinished, and a construction badge (a new
  glyph of P118g and the percent) over it, like the offline glyph (ADR 0023 §10); an enemy's seen
  site shows the same.
- **BUILD** (ADR 0025 §4): the ring may be the site's progress, the badge counts it. The drawer's
  queue row on the Structures tab: "CONSTRUCTION", the site's name and percent and a thumb (a tap
  selects the site and jumps the camera to it), or "NOTHING BUILDING" with "Tap a building, then
  place it on the map".
- **The command bar** with an own site selected: its chip with the percent and the order
  **Cancel**, labelled with the refund ("CANCEL +450"); one tap, one `CANCEL_BUILD`.
- **Every view reader that must skip a site** (P130's files and tests):
  - `game/input/StrikeAim.gd` (the charge it shows from `ready_tick`) and `StrikeButton`: an
    unfinished Deep Bore or Blackout Array has `ready_tick` 0, so without the skip the button would
    say "Ready" and the sim would drop the `SUPERWEAPON`; the button shows the site's percent and no
    charge until completion.
  - `BuildSidebar.gd`'s `_owned` and `_producers` (the requirement and producer counts that unlock
    cards): a site counts for neither, as in the sim (§4).
  - `EffectsLayer.gd` and `DecalLayer.gd`: a DIED record with the cancel flag gets no burst, wreck or
    crater.
  - The producer tap (`BuildSidebar.set_selected`, ADR 0024 Q3 A): selecting a site of a barracks or
    vehicle factory opens nothing.
- **Gone:** the READY tile state, the Ready chip (ADR 0025 §4) and its tap, the "ready" rows of
  `docs/HOW_TO_PLAY.md`.
- **HOW_TO_PLAY** (Build menu), with Teach on the first two: "Tap a building card → its ghost
  appears in the middle of the view; the check mark beside it shows the price. Tap the check mark →
  the price is paid and the building goes up on the spot; its badge counts the percent and its
  health rises with it; it does nothing (no power, no production, no shots) until it is finished
  (yes)"; "One building at a time: while one goes up, the other building cards are striped
  'BUILDING' (yes)"; "Select a building that is going up → Cancel: it is removed and you get back the
  part of its price the button shows"; "A building destroyed while it goes up is lost with its
  price"; the Superweapon row: "the ring starts when the building is finished".

### 10. Determinism, replays and hashes
- Integers only; rows ascending; no allocation in the PRODUCTION walk; nothing reads time.
  `STATE_FORMAT` becomes **5** (`build_left` in the rows' hash section).
- **One re-pin, in P128, with its reason** (as P109's, under the phase 3 plan's exception 10): the
  perf arena's units behave bit-identically and the base arena places no structure, but the new
  column is hashed. The pins that move (checked on `main` at 5203ce0):
  - `World.STATE_FORMAT` 4 → 5 asserted in `tests/sim/test_world_v1.gd:73`,
    `tests/sim/test_world_v2.gd:39` and `tests/sim/test_world_v3.gd:28`;
  - `TICK_0_SEED_1` in `tests/sim/test_world_hash.gd:26`;
  - `golden_hex` and `bases_golden_hex` in `data/dev/perf_gate.tres:31` and `:33` (the hexes only;
    `golden_ticks` and `bases_golden_ticks` stay);
  - `KNOWN_FORMATS` in `native/sim_kernels/sanitizer/dump.h:19` gains 5, as P109 added 4 in
    1d7b2cb (`tests/project/test_ci_workflow.gd:617-623` asserts the reader knows
    `World.STATE_FORMAT`), with the line of its comment that records why the dump stays the same.
  `tests/sim/native/sanitizer/dump_states.gd` and `tests/perf/support/hash_bytes.gd` read
  `World.STATE_FORMAT` and need no edit; `test_world_split.gd` and `test_fog_visible_derivation.gd`
  name it only in comments. qa-engineer reviews the re-pin. P129-P131 move no golden (no arena
  places a structure); the smoke's dummy-vs-dummy reports change, which nothing pins.
- **Named exception 19** (the next free one), the lead's files:
  - `game/core/MatchSnapshot.gd`: `COPIED` gains `&"build_left"` (`ROW_ARRAYS`, after
    `&"offline_until"`) with its `PackedInt32Array` member declaration and its capture line in
    `capture()`, as exception 18 did for P109 (the view reads it: the badge, the bar, the ring);
    `COPIED_SCALARS` gains `&"construct_refund_percent"` and `&"construction_sites_max"` with their
    int members and capture lines (the Cancel button's label, the cards' busy state);
  - `tests/core/test_match_snapshot.gd:101-103`: the pinned `COPIED_SCALARS` literal gains the two
    names.
  P128 names the exact lines in its PR. Next free exception: 20.
- **Replays:** a replay recorded before `STATE_FORMAT` 5 fails at its first checkpoint, as after
  P109; none ships. `PLACE`'s payload is already encoded (ADR 0017 §4), so `Command.encode`/`decode`
  do not change.
- **AI-vs-AI:** the dummies place first from P129 on; `run-sim-smoke.sh` keeps its flags.

### 11. Native kernels
No kernel is touched (ADR 0013): TARGETING (an unfinished defence picks targets as one on low power
does), FOG (it sees), FLOW, INTEGRATE and SEPARATION (the tiles are blocked at `PLACE`, as today)
read nothing new. The skipped work is in `Power.run`, `Combat.fire`, `Production`, `Strike`,
`Harvest` and `Outcome`, all GDScript, so the twin rule does not apply. But P128 touches `native/`:
the sanitizer reader's `KNOWN_FORMATS` in `native/sim_kernels/sanitizer/dump.h` gains 5 (§10). So
P128's review loads `rts-sim-conventions`' native checklist for that line, `verify.sh` checks it with
the pinned `clang-format` (20.1.8), and the sanitizer job runs on the PR. Mutation testing applies
to P128, P128b, P128c and P131 (they touch `game/sim/`).

### 12. Data, and what this amends
- **`data/rules.tres`** (`RulesDef`, copied by `WorldLoad.copy_rules` into World scalars, §1):
  `construct_start_hp_percent = 10`, `construct_refund_percent = 75` (question 1; 100 if Michael
  says A) and `construction_sites_max = 1`. `type_cost` and `type_build_ticks` keep their numbers
  and meaning; `tests/sim/test_defs_data.gd` gains "a Structures type has `build_ticks` >= 1".
- **Amends** (dated notes by the lead's docs row on acceptance): ADR 0017 §1 (a building row may be
  unfinished), §4 (the `PLACE` payload; Command 16), §7 (`STATE_FORMAT` 5); ADR 0018 §5 (structures
  are placed, paid and built on the spot; one at a time; low power slows a site) and §7 (an
  unfinished producer keeps no one alive); ADR 0019 §1 and §2 (no READY state; placement starts on
  the card; the "Blocked" rule of §9); ADR 0020 §4 (the dummy places first); ADR 0023 §10 (the
  charge starts at completion; a site cannot fire or be blacked out into progress); ADR 0024 §9 and
  ADR 0025 §4 and §6 (the Ready badge or chip goes); `touch-ui-rules` "Building placement", first
  bullet: "Placement begins with a tap on a structure's card (ADR 0026); the check mark shows the
  price and pays it"; the GDD's Superweapons line "charges for 5 minutes from placement" becomes
  "from completion" (question 3); `.claude/skills/rts-sim-conventions/SKILL.md` line 51 (16 leaves
  the reserved 16-19 for `CANCEL_BUILD`; lines 51-53 name it beside `SUPERWEAPON` 15) and line 89
  (`STATE_FORMAT` 5 adds `build_left`).

## Consequences
- One tap fewer per building and the choice of place comes first; the money leaves at the check
  mark. A base now has visible, vulnerable sites: an early rush can kill a site, and a player sees
  the enemy's sites.
- The STRUCTURES queue becomes dead state (always empty), kept to avoid a second layout change.
- The perf and base arenas re-pin once (P128); later ADR 0026 rows move no golden.
- The dummy's pace stays close (same build times, one at a time), but its sites can be attacked;
  the smoke's match lengths will move a little. Phase 4's AI is built on this rule.
- Risks: the hp growth's integer rounding (the plan's test sums the steps to `type_max_hp` for a
  site never hit); a cancelled row that draws fire on its last tick (harmless, deterministic); the
  enemy's memory of a site shows it finished (a known limit of `LastSeen`).

## Alternatives considered
- **Pay over the build time** (Command & Conquer's model): a "waiting for credits" state and a rate
  rule; the design and Michael say the price is taken at the check mark.
- **Full hit points from the start:** a free wall the moment it is placed.
- **Keep the ready-then-place queue for structures beside place-first:** two ways in for one thing.
- **Drop the STRUCTURES queue arrays:** a second layout change and re-pin for no player gain.
- **Remove a cancelled row at once in COMMANDS:** a compaction mid-tick, ahead of `FogUpdate.begin`,
  which REMOVE's order exists to avoid.
- **A player array for the one site:** §1.

## Questions for Michael
Only what the rules do not answer. One site at a time (a data number, `construction_sites_max`)
and "an unfinished building counts for nothing" (what under construction means) are decisions
(§4, §5).
1. **Cancel refund.** A: the full price back (as a cancelled queue item today). B: 75 % back (in
   `data/rules.tres`), so a site cannot serve as a free wall that you cancel later. Recommended: B.
2. **A site's health.** A: it starts at 10 % and rises with the work. B: full health from the
   start. Recommended: A.
3. **The superweapon's charge** starts when the building is finished, not when it is placed (the
   GDD says "from placement"). (ja/nej; recommended: ja)
4. **Your Headquarters is destroyed while a building goes up.** A: the site keeps building (it is
   paid for; without a Headquarters you cannot start another; and if you have no finished
   production building left you lose anyway). B: it freezes until you cancel it or the match ends.
   Recommended: A.
