# ADR 0021: Phase 3 performance: the perf arena stays, a base arena joins it

Status: accepted, 2026-10-22 (Michael: 1 ja, 2 ja). Proposed 2026-10-22. Docs PR P68 (with
`docs/plans/2026-10-22-phase-3.md`), accepted by the lead's row P68b on the same PR (#166). The
Phase 3 gate needs "the perf budget still met" while the sim grows by three phases, buildings,
harvesters and production. This ADR decides how the headless perf test, the CI budget, the golden
hashes and the phone card follow that growth. It changes no threshold.

## Acceptance note (2026-10-22)
Michael answered the questions of ADRs 0017-0021 in chat on 2026-10-22, verbatim "Ja til alle
anbefalinger" (yes to all recommendations), which the lead records for this ADR as "1 ja, 2 ja":
1. **ja:** CI runs the base arena beside the perf arena, with its own `PERF bases` lines, golden
   hashes and cost bounds now (plan rows P80, P93), and its own `[bases]` budget at the end of
   Phase 3 (P93b).
2. **ja:** the Phase 3 gate asks for `GATE: PASS` on Michael's phone three times on each card,
   the perf arena and the base arena, with Phase 2's limits (§3, §5).

The decision below is unchanged by the acceptance. P68b named the two new fields of §2 as
exports of the lead's `game/core/PerfGateDef.gd`, whose exact field list the lead's
`tests/core/test_timing_probe.gd` pins and so gains the two names in the same row (the plan's
exception 15). Nothing here is applied in code yet.

Status note (2026-10-26, P68e docs; ADR 0023 accepted 2026-10-26, Michael's answer 3 A): §1 and §2
carry dated status notes: the perf arena's golden hashes move once more, in plan row P109, and
the base arena holds both factions and fires each superweapon once. No threshold changes.

## Context
- CLAUDE.md rule 6: 150 units at 60 fps on a mid-range 2021 Android phone; the gate phone is
  Michael's own phone for good, with the divided limits (ADR 0011's acceptance note, ADR 0012 §4,
  ADR 0014). `data/dev/perf_gate.tres` holds them (`work_p95_ms` 5.6, `sim_p95_ms` 13.3,
  `job_p99_ms` 26.7, `draw_calls_max` 60, `heavy_rigs` 135, `heavy_frames_min` 600, ...) and the six
  golden hashes of the seed-42 perf arena at ticks 150-900.
- `tests/perf/budget.cfg` (P49b) is a regression ratchet on the native tick of the perf arena
  (`[sim]` `mean_ms` 0.4575, `p95_ms` 0.8475, 900 ticks, 150 units). Its header says: "A sim PR
  never raises these numbers (plan exception 3). A rise that a new tick phase causes (Phase 3's
  production and economy) is a qa-engineer PR with before and after calibration numbers and its
  reason, which the lead reviews."
- The Phase 2 plan's exception 3: a sim PR that changes the arena run re-pins the golden hashes and
  the run-outcome pins; the cost bounds and `budget.cfg` are qa-engineer's only. Exception 10 (ADR
  0016): a layout change of the hash re-pins `golden_hex`, `TICK_0_SEED_1`, the `STATE_FORMAT` pin
  and the sanitizer's `KNOWN_FORMATS`.
- ADR 0016: the watch line (3.325 ms on both halves of `job_minus_step`) and P65q's
  `WATCH sim hash_bytes` line in every CI log.
- ADR 0013 §1 and §15: the port clauses and the GDScript-phase port trigger, both read by the
  lead from `PERF` lines and cards.
- The perf arena is units only (150 rows, two players, no building, ore or queue), so it cannot see
  any Phase 3 phase at work. The P51 job summary selects `^PERF sim (units=|impl=native)` lines.

## Decision

### 1. The perf arena stays as it is
Scenario, seed 42, 900 ticks and 150 units are unchanged, and so is its role: the regression
ratchet of the combat tick. Its golden hashes move only with a hash layout change (P65, then ADR
0017's P70, both under exception 10). Every other Phase 3 row leaves them bit-identical (ADR 0017
§7). `budget.cfg`'s `[sim]` section keeps the ratchet rule: a Phase 3 row that pushes the native
arena tick over it stops and asks qa-engineer, who raises it in its own PR with before and after
numbers and the reason (the three new phases' idle cost on the arena is the expected case).

Status note (2026-10-26, P68e docs, ADR 0023 accepted 2026-10-26, Michael's answer 3 A; the text
above stays as accepted): the perf arena's golden hashes move once more after P70, in plan row
P109 (ADR 0023 §10): the strike state adds two row columns and three player arrays to the state
hash (`STATE_FORMAT` 4), so `golden_hex`, `TICK_0_SEED_1` and `KNOWN_FORMATS` are re-pinned under
exception 10 with that reason, and P65q's byte line moves once. The arena's units behave
bit-identically, and every other Phase 3 row, P106's faction column included, leaves the hashes as
they are. Its role, scenario, seed, ticks and `budget.cfg` are unchanged.

### 2. A base arena measures Phase 3's load
- A second perf scenario, `data/scenarios/perf_bases.tres` with its own map: two compact bases
  with every building type, two ore fields and four working harvesters per side, both unit queues
  filled by scenario orders at tick 0, and armies that meet between the bases from tick 0, so that
  150 mobile rows plus about 30 buildings are alive in the heavy part of the run. It is laid out so
  the arena camera frames every row at the run start (the P50c rule). Seed 42, 900 ticks.
- CI (qa-engineer): a `PERF bases` line (GDScript and native, the same keys as `PERF sim`),
  report-only at first; its own six golden hashes (`bases_golden_ticks`, `bases_golden_hex` in
  `perf_gate.tres`, two new exports of the lead's `game/core/PerfGateDef.gd` beside `golden_ticks`
  and `golden_hex`, which plan row P93 adds under the plan's exception 15, together with their
  names in the field contract of the lead's `tests/core/test_timing_probe.gd`); deterministic cost
  bounds for the new `Stat` counters; and a `WATCH bases hash_bytes` line beside P65q's. After the
  last Phase 3 sim row, a `[bases]` section in `budget.cfg`, calibrated as P49b did (1.5 x the worst
  native min-of-3 of 11 runs).
- The job summary (release-engineer) shows the `PERF bases` lines next to `PERF sim`.

Status note (2026-10-26, P68e docs, ADR 0023 accepted 2026-10-26, Michael's answer 3 A; the text
above stays as accepted): the base arena (plan row P80) holds both factions: side 1 the Derrick
League, side 2 the Lumen Accord, every building type of both (about 30 buildings) and 150 mobile
rows, and one scenario order fires each superweapon once (`OrderDef` gains `SUPERWEAPON`). P93
pins its golden hashes after the last sim row of plan revision 5. The arena scene gets the iso
layers, and its card's draw calls are judged against ADR 0023 §2's forecast (13) plus the HUD.

### 3. The phone card runs both
The perf arena scene gets a scenario choice (perf arena, base arena), and the dev menu a route to
each. Both cards use the same verdicts and thresholds as today (ADR 0012 §4 as ADR 0014 changes it,
with `heavy_rigs`, `draw_calls_max` and the golden hashes). The Phase 3 gate asks for `GATE: PASS`
on both, three runs each (question 2).

### 4. Ports and watch lines
The lead applies ADR 0013 §1's clauses (a) and (b) to ECONOMY, PRODUCTION and MEMORY at the first
`PERF bases` line with all three filled (plan row P93), and §15's port trigger and ADR 0016's
watch line to every base-arena card. A port is a plan row under ADR 0013, not a new ADR.

### 5. What does not change
Every threshold in `perf_gate.tres`, the divisor k 2.5, the gate phone, the ratios (re-derived
only under the Phase 2 plan's exception 5), and the perf arena's role.

## Consequences
- CI runs two arenas in `tests/perf` (twice the perf time of today) and prints two `WATCH`
  hash-byte lines.
- A Phase 3 cost (flow-field churn after placements, harvester searches, production spawns, the
  extra draw calls of buildings) shows in a deterministic run before it shows on the phone.
- The perf arena's ratchet keeps guarding the combat tick, unmixed with Phase 3's load.

## Alternatives considered
- **Add buildings to the perf arena:** one scenario, but every Phase 2 number and golden hash
  would move, and the combat tick's ratchet would lose its baseline.
- **Measure Phase 3 only on the phone:** no CI regression signal; rejected by ADR 0012 §4's
  ratchet reasoning.
- **A full AI-vs-AI match as the perf scenario:** its load depends on the AI's choices, which
  Phase 4 changes; scenario orders keep the base arena fixed.

## Questions for Michael
1. Phase 2's perf arena has no buildings. Should CI also run a "base arena" (two full bases,
   harvesters and factories working, 150 units fighting) with its own golden hashes and, at the
   end of Phase 3, its own budget? (ja/nej; recommended: ja)
2. For the Phase 3 gate, should your phone show `GATE: PASS` three times on both cards, the perf
   arena and the base arena, with the same limits as Phase 2? (ja/nej; recommended: ja)
