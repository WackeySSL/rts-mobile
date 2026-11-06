---
name: balance-report
description: Runs headless AI-vs-AI matches with fixed seeds and writes a balance report (win rates per side and difficulty, match length, production share and kill efficiency per unit) with at most three data-only tuning proposals. Use for any balance question, unit strength complaint, difficulty tuning and the nightly balance job.
argument-hint: "[number of matches, default 100]"
---

# Balance report

Number of matches: `$ARGUMENTS` (use 100 if empty). Seeds are 1..N (`--seed-start 1`), so reports
stay comparable; only the Phase 4 gate run uses the held-out seeds 1001-1100 (ADR 0031 §6).

The matches run only in GitHub Actions (the nightly balance job), never in a session (CLAUDE.md,
Token budget). In a session, read the latest comment on the `balance` issue or the balance run's
artifact instead of running step 1.

1. Per set, run `bash scripts/run-sim-smoke.sh --matches N --seed-start S --levels A,B
   --scenarios KIND --report build/balance/<set>-<A>-<B>-<S>.json` for each shard, then
   `bash scripts/balance-summary.sh --out build/balance/<set>.json <the set's shard reports>`
   (ADR 0031 §2, §4).
2. Write `docs/balance/<yyyy-mm-dd>.md` with:
   - win rate per side and per difficulty pairing, with N,
   - match length: median and 90th percentile in minutes,
   - per unit type: production share, kills per 1000 credits spent, survival rate,
   - what moved compared with the previous report in `docs/balance/` (same seeds).
3. Flag any win rate outside 40-60%, a median match length outside 8-10 minutes, and any unit
   type below 5% or above 40% of production.
4. Propose at most three changes, each a single number in `data/*.tres`, with the expected
   effect. Never change code here. Apply changes only when asked, one at a time, re-running the
   same seeds after each.
5. In the balance run, post the summary as one comment on the open issue labelled `balance`, with
   one block per set (ADR 0031 §5).
