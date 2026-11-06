---
name: project-phase4-decisions
description: Phase 4 plan (P170, 2026-11-06, PROPOSED) and ADRs 0030 (opponent AI, think slots, difficulty) and 0031 (harness, report schema 2, nightly, gate run); rows P170-P193, exceptions 20-21
metadata:
  type: project
---

- P170 (2026-11-06, base f51e3ff, PROPOSED): `docs/plans/2026-11-06-phase-4.md` + ADR 0030 + ADR 0031. Rows P170-P193 (+P170b, P171b, P176b, P180b, P183b, P189b, P192a..), P168-P169 unused, P194-P199 reserved; exceptions 20 (tuning edits gameplay-dev data + pins) and 21 (P188's arm64 line in ci.yml); next free exception 22.
- Key design: `OpponentAi` = 5 managers (Economy, Production, Intel, Army, Strikes) over `AiMemory` (ints, ids never rows); think_period 5 with 3 slots from the tick, so each manager once per 15 ticks; think_tick 7 keeps players 1-2 off `tick % 15 == 14` (4 players would collide); counted caps in `OpponentDef`; `AiDifficultyDef` x3, `AiBuildOrderDef` per faction x tier; `AiFactory` (OpponentDef -> OpponentAi, plain AiDef -> DummyAi); `MatchRunner.opponent_levels`; `TickJob` stamps `think_usec`; Perf AI card on `perf_ai.tres`.
- Harness: smoke keeps `--matches/--report`, adds `--seed-start --levels --scenarios --ticks` (13 500 cap, timeout not a smoke failure), AUTO impl (ADR 0013 §3 note), per-type counts from `world.events` (no sim stats), schema 2 all ints; `scripts/balance-summary.sh` merges; gate set = 100 Normal-Normal `cross` (odd seed League top), retry seeds 101-200 only if 350-399/601-650 per-mille.
- P171 freezes the perf and base arenas' defs in `data/dev/arena/` so balance tuning never moves goldens or the [sim]/[bases] workloads.
- Questions (rec.): 0030 1 C (Hard bonus only if Hard < 60 % vs Normal), 2 A (strikes Normal+Hard), 3 A (dev-menu level buttons), 4 ja (dummy stays), 5 ja (ai-dev 0.15 ms/slot CI); 0031 1 A (factions crossed), 2 A (built in >= half the matches), 3 A (nightly when main moved), 4 ja (ai-dev tunes), 5 A (Easy/Hard may surrender).
- Pitfall: an AI think lands in `job_minus_step` (TickJob.job_usec spans think_all; step_usec does not), so keep thinks off checkpoint ticks and read the noncp half and sim_p95 for AI cost; ai-dev's "1 ms on CI" is ~6 ms on the phone at GDScript ratio 5.9.
- Pitfall: a deterministic AI with no draws plus a sim with no random rule makes N seeds one match; the AI must draw (jitter, weighted mix) and the report checks distinct final hashes.
- Pitfall: balance tuning of `data/units` moves any golden whose scenario loads those files (perf arena loads three League units + rules.tres); freeze arena inputs before tuning. GDD already promised Hard +20 % income, contradicting "no resource cheats unless Michael chooses" - asked again.
