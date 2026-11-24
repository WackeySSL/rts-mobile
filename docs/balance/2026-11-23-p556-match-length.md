# P556 match length, closed 2026-11-23

Michael closed balance row P556 on 2026-11-23 with lever 3: AI-vs-AI matches on Normal may run
12-15 minutes, and the 8-10 minute median of the Phase 5 gate is measured in human-vs-AI playtests
(ROADMAP Phase 5 gate; plan `docs/plans/2026-11-15-phase-5.md`, P556; ADR 0031's note of
2026-11-23). The timeout counts are from CI; section 2 is a local probe.

## 1. Measured (CI)

Normal vs Normal timeouts (Kestrel Flats: scenario `cross`):

| Commit | Kestrel (of 100) | Heron Fords (of 50) | Curlew Crags (of 50) |
| --- | --- | --- | --- |
| main 3be11231 | 99 | 36 | 47 |
| lever A 7682046e (attack timings) | 94 | 32 | 34 |
| P250e b75019df (grouped waves) | 96 | 35 | 39 |

All medians 15.0 min.

P250e on Kestrel, 40 matches each:
- Hard vs Normal: 38/40 timeouts; level shares hard 525 / normal 475.
- Easy vs Normal: 30 victories, median 10.9 min; easy 875 / normal 125, so Easy beat Normal there.
  That is a separate open question (difficulty order), not part of this decision.

## 2. The defender (local probe)

Kestrel, Normal vs Normal, seeds 1-3 and 36, all timeouts:
- static defence per side: 2 turrets (1200 credits) + 2 AA (1400), about 2600;
- producers: HQ, barracks, factory, plus airfield/engineering in most;
- replacement in the last 3 min: 7-9 units/min per side (one side 4.7);
- 17 wave arrivals within 14 tiles of the enemy HQ: wave value 1.3k-4.8k vs defence + home units
  2.1k-11k; only 1 of 17 was ahead (4557 vs 2092).

## 3. Cause

The defender's home units plus replacement beat each wave. Normal and Hard pull waves back when the
enemy near them is worth 2x (Normal) or 1.5x (Hard) the wave (`retreat_ratio_percent` 200/150,
`counter_percent` 30/60). Easy has 0/0 and never retreats.

## 4. Levers

Not chosen:
- 0: AI data, let Normal/Hard commit like Easy (higher `retreat_ratio_percent`, or no retreat/recall
  after all-in); AI only.
- 1: data, slower production or dearer units to cut replacement to about 5/min.
- 2: a rules ADR, a siege bonus vs structures.

Chosen: lever 3, accept 12-15 min AI-vs-AI for Normal (Michael, 2026-11-23). The branch
`claude/p250e-grouped-waves` (b75019df) and the lever A commit 7682046e stay unmerged, as reference.
