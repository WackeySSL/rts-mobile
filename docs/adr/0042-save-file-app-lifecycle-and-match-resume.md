# ADR 0042: One save file, the app lifecycle, and resuming a match by replaying its log

**In short, for Michael:** everything the game keeps on the phone (settings, rank and XP, tutorial
progress, Phase 6's ad state) goes into one file with a version number, written so that a crash or a
dead battery in the middle of a write can never destroy it. When the phone sends the game to the
background, the match pauses, the sound goes quiet, and the game writes down the match's seed and
your orders. If Android kills the game while it is away, the main menu offers Continue: the game
plays the match again from its start, very fast and without drawing, with your orders at the same
moments, until it reaches the point where you left; it checks itself at every second of the match
on the way. That takes an estimated 10-36 seconds for a 10-15 minute match, behind a progress bar. A
frozen copy of the whole battle would load at once, but it would need every piece of the battle and
of the computer's memory written and read back, and one forgotten piece would quietly change the
match; replaying is exact by construction.

Status: **proposed, 2026-11-15 (awaiting Michael).** Written by the architect on branch
`claude/p500-phase5-plan` (base `main` at a2204d2f) with the plan
`docs/plans/2026-11-15-phase-5.md` (rows P510-P516, P531). Questions 7 and 13 of the plan are this
ADR's. The section layout and `get_section`/`set_section` are agreed with Phase 6 (2026-11-15).

Amends by dated notes at acceptance (P500b): ADR 0007 §9 ("Storage": the resume file is the one
stored log; `user://replays/` stays out of scope) and its Consequences ("a Phase 5 save must store
the flow-cache state or rebuild it at load": not needed, the restore replays from tick 0, so a
resumed game is bit-identical); ADR 0024 §7 and ADR 0025 §11 (`settings.cfg` is taken over by the
save file); ADR 0027 §8 (the reduced switch is stored in section `settings`).

## Context
- Today one file exists: `user://settings.cfg`, `[hud] haptics`, through `HudPrefs` (static, no
  autoload, a test path override used by every suite that builds the sidebar).
- `MatchRunner` already stops ticking on `NOTIFICATION_APPLICATION_PAUSED` and restarts on
  `RESUMED`; nothing is written. Android may kill a backgrounded process at any time after
  `onStop`; iOS allows about 5 s after the pause (the `mobile-development` skill).
- `Replay` (ADR 0007 §9, `FORMAT` 2) holds the scenario path, the seed, `defs_hash`,
  `income_percent`, every stamped Command, a checkpoint hash every 15 ticks and the final hash, and
  has `to_bytes`. ADR 0038 §5: the AI's Commands are recorded at their applied tick; `SYNC` and
  `WORKER` give the same hashes, with the AI on its thread or inline.
- No serialiser exists for the World (about a hundred columns and arrays in `WorldShape`'s lists,
  plus derived caches that `prepare()` rebuilds) or for the AI's memory (five managers, `AiMemory`,
  think slots, the pending T+1 batch, its `DetRandom` streams).
- Cost of a tick: CI's native perf arena mean is 0.46 ms at 150 units (`tests/perf/budget.cfg`);
  ADR 0014's phone ratio was about 3.6-3.8; the AI adds its thinks. Matches run 9,000-13,500 ticks
  (`docs/balance/2026-11-10-gate.md`).

## Decision
### 1. One file, sections
- Autoload **`SaveService`** (`game/meta/save_service.gd`, no `class_name`). File
  `user://save.cfg`, a `ConfigFile` (text; it keeps ints as ints, which JSON would not).
- Sections: `meta` (`version`, `app_version`), `settings` (sound and music steps, reduced effects),
  `hud` (`HudPrefs`' keys, haptics among them), `progress` (ADR 0045), `tutorial` (ADR 0044),
  `match` (the resume pointer, §6), `ads` (Phase 6, opaque here). A section the code does not know
  is kept as read and written back unchanged.
- API: `get_section(name: StringName) -> Dictionary` (a copy), `set_section(name, values)` (whole
  section, marks the file dirty), `flush() -> Error`, signal `saved`. Writes are coalesced to one
  flush per frame at most, plus the forced flushes of §5. Main thread only.
- Tests: `set_path_override(path)` / `clear_path_override()`, as `HudPrefs` has today.

### 2. The atomic write
1. Encode to text; prepend one line `; sha256=<hex of the rest>`.
2. Write `save.cfg.tmp`, close it, read it back and check the hash.
3. Rename `save.cfg` to `save.cfg.bak` (replacing the old one), then `save.cfg.tmp` to `save.cfg`.
Load, newest first: `save.cfg.tmp` if its hash matches (a hash-valid temp is always the newest
write: the app was killed after step 2 and before the last rename, so it may hold a paid
`apply_bonus` that `save.cfg` lacks; the load then finishes the two renames); else `save.cfg` if its
hash matches; else `save.cfg.bak`; else defaults. A temp whose hash fails is a write that never
finished and is deleted; a main or backup file that fails is kept once as `save.cfg.bad`.
Rename-over semantics on Android, desktop and the web's `user://` (IndexedDB-backed) are checked in
P510 (unverified here).

### 3. Versions and migration
- `meta.version` starts at 1. Migrations are ordered pure functions `v(n) -> v(n+1)` on the
  `ConfigFile`, run at load; a test per step.
- **v0** = no `save.cfg` but a `settings.cfg`: its `[hud]` keys move to section `hud`, the file is
  deleted after the first good write. `HudPrefs` keeps its API and reads through `SaveService`
  (P510b), so none of its five callers changes.
- A file with a **newer** version (an older app installed over a newer one) is never written: the
  game runs on its readable known sections and a warning line, and saves nothing until updated.

### 4. What is not in the save
No personal data, nothing that leaves the device, no timestamps from the system clock in `game/sim`
(meta may store none either; nothing needs one).

### 5. The app lifecycle
| Notification | What happens |
| --- | --- |
| `NOTIFICATION_APPLICATION_PAUSED` | the runner stops (today's path); the pause menu opens (P531); `AudioService` adds `background`; `SaveService.flush()`; `ResumeStore` writes the match (§6) |
| `NOTIFICATION_APPLICATION_FOCUS_OUT` (shade, call overlay, a browser tab hidden) | the pause menu opens and the match pauses; audio mute; no file write |
| `NOTIFICATION_APPLICATION_RESUMED`, `FOCUS_IN` | audio unmutes; the match stays paused in the pause menu until Resume (question 13) |
| `NOTIFICATION_WM_GO_BACK_REQUEST` | ADR 0043 §4 |
All writes are small (a few KB for the save; under 1 MB compressed for the resume file, estimated),
well inside iOS's few seconds.

### 6. Resuming a match: replay the log (option A), not a snapshot
**Write.** On `PAUSED`, `MenuFlow` (which holds the running main scene) calls `runner.wait_idle()`,
then `ResumeStore.write(setup, runner.replay)`: `user://resume.bin`, written temp + rename, holding
a header (its own format, `app_version`, `defs_hash`, the `MatchSetup` as a dictionary, the local
player) and `Replay.to_bytes()` compressed. Section `match` points at it. The file is deleted when
the match ends, on Exit to menu, on a new match and after a failed restore. Tutorial matches are not
resumed (the lesson restarts).

**Restore.** The main menu shows Continue while a valid file exists (same `app_version` and
`defs_hash`; else it is deleted with a short note). Continue opens the restore screen:
1. The main scene is instantiated **off the tree**; its runner gets the setup, `restored = true`
   (so `_ready` does not start a second match) and `start()`.
2. AudioService gets the mute reason `restoring` (ADR 0041 §5) until step 4. Each frame, for as
   many ticks as fit in `restore_slice_ms` (data, 50 ms; time is read only in `game/core`): submit
   the **local player's** logged Commands stamped t through `CommandQueue.submit_logged` (queued
   like `submit`, but without the `submitted` signal, so no order chirp and no other listener
   reacts), then `run_ticks(1)`. The AI is not fed from the log; it thinks as it did, on the same
   views, and regenerates its own Commands (ADR 0038 §1, §5).
   - **Why a 50 ms slice:** the restore screen is opaque and static (a progress bar and Cancel), so
     the frame can spend nearly all its time on ticks; the bar still redraws about 19 times a
     second, a Cancel tap is seen within one frame, and Android's input timeout (5 s) is far away.
     A 10 ms slice in a 16.7 ms frame would stretch the wall time about 1.7 times; 50 ms costs
     about 5 % (the frame's own work). The battle's frame pacing does not apply: nothing is
     drawn.
3. At each checkpoint tick the loop's hash must equal the log's. A mismatch stops the restore,
   deletes the file and says the match could not be restored (no XP, no penalty).
4. At the last logged tick the scene enters the tree, paused under the pause menu. The view layers
   start from a first snapshot at tick N (P516 proves it; wrecks and craters of the past are not
   redrawn). The new runner's own replay is the same log again, so a second background save works.

**Why A.** It reuses only proven parts (`Replay`, checkpoints, the runner, the AI pipeline); it is
bit-identical to the uninterrupted match by construction and checked on the way; it adds no second
state format to keep in lockstep with `STATE_FORMAT` and with the AI's fields; it keeps ADR 0007's
"the sim is a pure function of its log". **Cost:** time grows with the match. Estimate on the phone:
1-2.5 ms of CPU per tick with the AI, so 9-23 s for 10 minutes and 14-34 s for 15; with the 50 ms
slice the wall time is about 1.05 times that: **about 10-24 s for 10 minutes and 15-36 s for 15**
(unverified; P516 prints CI's ticks per second, and Michael's phone measures it).

**Trigger for B.** If Michael's phone restores a 10-minute match in more than 15 s of wall time
with the 50 ms slice, a new ADR designs option B (below) or a hybrid; A stays the fallback and the
proof. The estimate's range straddles 15 s, so the phone measurement in P516's follow-up (Michael's
PerfCard run, not a session timing) decides it early, before the menu rows depend on Continue's
feel. Raising the slice further gains under 5 %.

### 7. Proof (headless)
`SaveService`: the write sequence with each step interrupted (a valid temp beside an older main
file loads the temp; a valid temp with no main file; a temp with a bad hash is ignored; a bad main
hash falls back to `.bak`), newer-version read-only, v0 migration, unknown sections kept.
Resume: a skirmish played to ticks 300 and 3,000, written, restored and played on equals the
uninterrupted run at every checkpoint, under GDSCRIPT and AUTO and in SYNC and WORKER with the AI
thread; refusals for a tampered log, another `defs_hash` and another app version; the main scene
entering at tick N; a restore starts no voice and emits no `CommandQueue.submitted`.

## Consequences
- One file for Phase 5 and Phase 6; `settings.cfg` disappears after the first launch of the new
  build.
- A killed app comes back to the same match, exactly, at the cost of a wait proportional to its
  length. A restore across an app update is impossible (the log is valid only for its code and data,
  ADR 0007 §9); the file is dropped.
- `MatchRunner` gains one guard field; nothing in `game/sim` changes for resume.
- The pause menu becomes the landing point after any interruption.

## Alternatives considered
- **B. Snapshot the World and the AI.** Instant restore. Rejected for now: a serialiser for every
  hashed column and array, every derived cache rebuilt or stored (ADR 0007's Consequences, the
  flow-cache note), and every AI field (managers, memory, slots, the pending batch, RNG
  positions), each future field a silent divergence unless a test covers it; a second format
  beside `STATE_FORMAT`.
- **C. No resume across a kill; in-memory pause only** (today). Rejected as the default: ROADMAP's
  "save and resume when the app goes to the background"; it stays what happens when the process
  survives, which is most of the time.
- **JSON save.** Rejected: numbers come back as floats; ConfigFile keeps Variant types.
- **Two files (settings apart from progress).** Rejected: agreed with Phase 6 as one versioned file;
  the resume log is apart only because it is large, short-lived and tied to one build.
