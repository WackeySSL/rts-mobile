---
name: project-ground-support-decisions
description: ADR 0037 (ground support: sale, mend, repair buildings, medics, ground carrier, mines) PROPOSED 2026-11-09 on b6bfe95, reconciled with ADR 0036 (e01ee4c); plan docs/plans/2026-11-09-ground-support.md rows P270-P297
metadata:
  type: project
---

- ADR 0037 PROPOSED 2026-11-09 (branch claude/design-ground-support). Rows P270-P297 (+P270b, P295b); P298-P299 free for splits. Lead said P260+, but ADR 0036's plan holds P230-P269.
- Releases (Q1 rec B): v1 = SELL 17 + MEND 18 (~550 lines, no layout change: mend switch = a building's `cargo`); 1.1 = Weld Shed / Drone Dock (repair buildings) + Patchers / Menders (medics) on ADR 0036's repair role (~840); 1.2 = Bunk Wagon / Linecar on Carry.gd + Shot Truck / Seeder mines (~1,670). Total ~3,060, no C++.
- Shared with ADR 0036: LOAD 5, UNLOAD 6, REPAIR 7 (names a building only); repair role (`repair_classes` move-class mask FOOT 1/WHEELED 2/TRACKED 4/AIR 8) moved to UnitDef + `repair_slots`, `repair_seek_milli`; Air.run keeps pad types, Repair.run the rest; `carry_eject_percent` (0 = ADR 0036's die rule). Mine: LAY_MINE 8; events MINE_BLAST 7, REPAIRED 8; DIED flag 3 = sold (2 = boarded, ADR 0036); carry_mode 2 lay / 3 sweep; 9 STANCE and 19 PATROL reserved.
- Mines: separate table (own id counter), trigger by enemy GROUND non-aware rows in FIRE mark after Strike.run, no friendly fire, per-player records like LastSeen (MineMemory in MEMORY, detectors = minelayers 3,000 + scouts 2,000), sweep by standing, rupture clears, cap 12. Rides STATE_FORMAT 7 (P262). AI reads only own_mines/known_mines.
- Questions: 1 when (B), 2 carrier (A: no firing, Bunk Wagon eject 50 %, Linecar 0), 3 mines own units (A none), 4 ranks/stances/patrol (A later, hold position first), 5 names (A).
- Pitfall: a parallel design can take your row range and numbers; read the sibling branch's plan before numbering, and reconcile Commands, events, DIED flags and STATE_FORMAT bumps in one table (ADR 0037 §2).
- Pitfall: page 1 holds every y-sorted item (ADR 0036's page rule); new ground units can never move to page 2, so their rows compete with ADR 0036's buildings; estimate rows as canvas texels / 4096 x 1.08 (today's packing loss: 3,277 canvas rows -> 3,550 page).
- Pitfall: Geneva emblems (red cross/crescent/crystal) are protected: medic art needs its own kit mark.
